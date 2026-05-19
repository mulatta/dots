"""Markdown+YAML Vikunja task template support for n8n-hooks."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n?(.*)\Z", re.DOTALL)


class TemplateError(ValueError):
    """Template or context validation failed."""


@dataclass(frozen=True)
class TemplateSpec:
    name: str
    path: Path
    description: str
    defaults: dict[str, Any]
    schema: dict[str, Any]
    attachment_expectations: list[str]


def load_template(name: str, template_dir: str | None = None) -> TemplateSpec:
    safe_name = _safe_template_name(name)
    path = _resolve_template_path(safe_name, template_dir)
    if not path.exists():
        raise TemplateError(f"template not found: {safe_name}")
    return _read_template(path, safe_name)


def validate_context(template: TemplateSpec, context: dict[str, Any]) -> list[str]:
    return _validate_value(context, template.schema, template.schema, [])


def missing_required(template: TemplateSpec, context: dict[str, Any]) -> list[str]:
    missing: list[str] = []
    schema = template.schema
    required = schema.get("required", [])
    properties = schema.get("properties", {})
    if not isinstance(required, list):
        return []
    if not isinstance(properties, dict):
        properties = {}
    for field in required:
        if not isinstance(field, str):
            continue
        value = context.get(field)
        prop = properties.get(field, {})
        if _is_missing_value(value):
            missing.append(_missing_label(field, prop))
            continue
        if isinstance(value, list) and isinstance(prop, dict):
            min_items = prop.get("minItems")
            if isinstance(min_items, int) and len(value) < min_items:
                missing.append(f"{field} (minItems {min_items})")
    return _dedupe(missing)


def default_template_dirs() -> list[Path]:
    override = os.environ.get("VIKUNJA_TEMPLATE_DIR")
    if override:
        return [Path(override).expanduser()]
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    bases = [data_home, *(Path(item) for item in data_dirs.split(":") if item)]
    return [base / "vikunja-cli" / "templates" for base in bases]


def _resolve_template_path(name: str, template_dir: str | None) -> Path:
    bases = (
        [Path(template_dir).expanduser()] if template_dir else default_template_dirs()
    )
    fallback: Path | None = None
    for base in bases:
        resolved_base = base.expanduser().resolve()
        candidates = [
            resolved_base / f"{name}.md",
            resolved_base / name / "template.md",
        ]
        if fallback is None:
            fallback = candidates[0]
        for path in candidates:
            root = path.parent.resolve()
            try:
                root.relative_to(resolved_base)
            except ValueError as exc:
                raise TemplateError("template path escapes template dir") from exc
            if path.exists():
                return path.resolve()
    return fallback or (
        default_template_dirs()[0].expanduser().resolve() / f"{name}.md"
    )


def _read_template(path: Path, expected_name: str) -> TemplateSpec:
    text = path.read_text()
    match = FRONTMATTER_RE.match(text)
    if not match:
        raise TemplateError(f"{path.name} must start with YAML frontmatter")
    try:
        raw = yaml.safe_load(match.group(1))
    except yaml.YAMLError as exc:
        raise TemplateError(f"invalid YAML in {path.name}: {exc}") from None
    if not isinstance(raw, dict):
        raise TemplateError(f"{path.name} frontmatter must be a YAML mapping")
    spec = _parse_template(path, raw)
    if spec.name != expected_name:
        raise TemplateError(
            f"template name '{spec.name}' does not match file name '{expected_name}'"
        )
    return spec


def _parse_template(path: Path, raw: dict[Any, Any]) -> TemplateSpec:
    errors: list[str] = []
    allowed = {"name", "description", "defaults", "schema", "attachment_expectations"}
    for key in raw:
        if key not in allowed:
            errors.append(f"unsupported key: {key}")

    name = raw.get("name")
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        errors.append("name must contain only letters, numbers, '_' or '-'")
        name = ""

    description = raw.get("description")
    if not isinstance(description, str) or not description.strip():
        errors.append("description must be a non-empty string")
        description = ""

    defaults = raw.get("defaults")
    if not isinstance(defaults, dict):
        errors.append("defaults must be a mapping")
        defaults = {}
    else:
        errors.extend(_validate_defaults(defaults))

    schema = raw.get("schema")
    if not isinstance(schema, dict):
        errors.append("schema must be a mapping")
        schema = {}
    else:
        errors.extend(_validate_schema_shape(schema))

    attachment_expectations = raw.get("attachment_expectations", [])
    if not _is_list_of_strings(attachment_expectations):
        errors.append("attachment_expectations must be a list of strings")
        attachment_expectations = []

    if errors:
        raise TemplateError(
            f"invalid template spec in {path.name}: " + "; ".join(errors)
        )

    return TemplateSpec(
        name=name,
        path=path,
        description=description,
        defaults=dict(defaults),
        schema=dict(schema),
        attachment_expectations=list(attachment_expectations),
    )


def _validate_defaults(defaults: dict[Any, Any]) -> list[str]:
    errors: list[str] = []
    allowed = {"priority", "labels"}
    for key in defaults:
        if key not in allowed:
            errors.append(f"defaults.{key} is unsupported")
    priority = defaults.get("priority")
    if not isinstance(priority, int) or priority < 0 or priority > 5:
        errors.append("defaults.priority must be an integer from 0 to 5")
    labels = defaults.get("labels", [])
    if not _is_list_of_strings(labels):
        errors.append("defaults.labels must be a list of strings")
    elif any(not item.strip() for item in labels):
        errors.append("defaults.labels must not contain empty strings")
    return errors


def _validate_schema_shape(schema: dict[Any, Any]) -> list[str]:
    errors: list[str] = []
    if schema.get("type") != "object":
        errors.append("schema.type must be object")
    properties = schema.get("properties")
    if not isinstance(properties, dict):
        errors.append("schema.properties must be a mapping")
    required = schema.get("required", [])
    if not _is_list_of_strings(required):
        errors.append("schema.required must be a list of strings")
    defs = schema.get("$defs", {})
    if defs is not None and not isinstance(defs, dict):
        errors.append("schema.$defs must be a mapping")
    errors.extend(_validate_schema_node(schema, schema, ["schema"]))
    return errors


def _validate_schema_node(
    node: Any, root: dict[Any, Any], path: list[str]
) -> list[str]:
    if not isinstance(node, dict):
        return []
    errors: list[str] = []
    ref = node.get("$ref")
    if ref is not None:
        if not isinstance(ref, str) or not _resolve_ref(root, ref):
            errors.append(f"{'.'.join(path)}.$ref points to an unknown definition")
        return errors
    node_type = node.get("type")
    if node_type == "array":
        min_items = node.get("minItems")
        max_items = node.get("maxItems")
        if min_items is not None and (not isinstance(min_items, int) or min_items < 0):
            errors.append(f"{'.'.join(path)}.minItems must be a non-negative integer")
        if max_items is not None and (not isinstance(max_items, int) or max_items < 0):
            errors.append(f"{'.'.join(path)}.maxItems must be a non-negative integer")
        if (
            isinstance(min_items, int)
            and isinstance(max_items, int)
            and min_items > max_items
        ):
            errors.append(
                f"{'.'.join(path)}.minItems must be less than or equal to maxItems"
            )
        errors.extend(_validate_schema_node(node.get("items"), root, [*path, "items"]))
    if node_type == "object":
        required = node.get("required", [])
        if not _is_list_of_strings(required):
            errors.append(f"{'.'.join(path)}.required must be a list of strings")
        properties = node.get("properties", {})
        if properties is not None and not isinstance(properties, dict):
            errors.append(f"{'.'.join(path)}.properties must be a mapping")
        elif isinstance(properties, dict):
            for key, value in properties.items():
                errors.extend(
                    _validate_schema_node(value, root, [*path, "properties", str(key)])
                )
    defs = node.get("$defs")
    if isinstance(defs, dict):
        for key, value in defs.items():
            errors.extend(
                _validate_schema_node(value, root, [*path, "$defs", str(key)])
            )
    enum = node.get("enum")
    if enum is not None and not isinstance(enum, list):
        errors.append(f"{'.'.join(path)}.enum must be a list")
    return errors


def _validate_value(
    value: Any,
    schema: dict[Any, Any],
    root: dict[Any, Any],
    path: list[str | int],
) -> list[str]:
    ref = schema.get("$ref")
    if isinstance(ref, str):
        resolved = _resolve_ref(root, ref)
        if resolved is None:
            return [_schema_path(path) + "unknown schema reference"]
        return _validate_value(value, resolved, root, path)

    errors: list[str] = []
    node_type = schema.get("type")
    if node_type == "object":
        if not isinstance(value, dict):
            return [f"{_schema_path(path)}must be an object"]
        properties = schema.get("properties", {})
        if not isinstance(properties, dict):
            properties = {}
        required = schema.get("required", [])
        if _is_list_of_strings(required):
            for field in required:
                if _is_missing_value(value.get(field)):
                    errors.append(f"{_schema_path([*path, field])}is required")
        if schema.get("additionalProperties") is False:
            for field in value:
                if field not in properties:
                    errors.append(f"{_schema_path([*path, str(field)])}is not allowed")
        for field, item in value.items():
            if field in properties and isinstance(properties[field], dict):
                errors.extend(
                    _validate_value(item, properties[field], root, [*path, str(field)])
                )
        return errors

    if node_type == "array":
        if not isinstance(value, list):
            return [f"{_schema_path(path)}must be an array"]
        min_items = schema.get("minItems")
        max_items = schema.get("maxItems")
        if isinstance(min_items, int) and len(value) < min_items:
            errors.append(f"{_schema_path(path)}needs at least {min_items} items")
        if isinstance(max_items, int) and len(value) > max_items:
            errors.append(f"{_schema_path(path)}needs at most {max_items} items")
        items = schema.get("items")
        if isinstance(items, dict):
            for index, item in enumerate(value):
                errors.extend(_validate_value(item, items, root, [*path, index]))
        return errors

    if node_type == "string":
        if not isinstance(value, str):
            return [f"{_schema_path(path)}must be a string"]
        min_length = schema.get("minLength")
        if isinstance(min_length, int) and len(value) < min_length:
            errors.append(
                f"{_schema_path(path)}must be at least {min_length} characters"
            )
        enum = schema.get("enum")
        if isinstance(enum, list) and value not in enum:
            errors.append(
                f"{_schema_path(path)}must be one of: {', '.join(str(item) for item in enum)}"
            )
        return errors

    return errors


def _resolve_ref(root: dict[Any, Any], ref: str) -> dict[Any, Any] | None:
    prefix = "#/$defs/"
    if not ref.startswith(prefix):
        return None
    defs = root.get("$defs")
    if not isinstance(defs, dict):
        return None
    value = defs.get(ref.removeprefix(prefix))
    return value if isinstance(value, dict) else None


def _schema_path(path: list[str | int]) -> str:
    return ".".join(str(item) for item in path) + ": " if path else ""


def _missing_label(field: str, property_schema: Any) -> str:
    if isinstance(property_schema, dict):
        min_items = property_schema.get("minItems")
        if (
            isinstance(min_items, int)
            and min_items > 0
            and property_schema.get("type") == "array"
        ):
            return f"{field} (minItems {min_items})"
    return field


def _is_missing_value(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return not value.strip()
    if isinstance(value, list):
        return len(value) == 0
    return False


def _is_list_of_strings(value: Any) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def _safe_template_name(name: str) -> str:
    trimmed = name.strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", trimmed):
        raise TemplateError("template must contain only letters, numbers, '_' or '-'")
    return trimmed


def _dedupe(items: list[str]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result
