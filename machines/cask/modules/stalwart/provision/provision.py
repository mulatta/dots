#!/usr/bin/env python3
"""Reconcile declarative Stalwart principals and mailbox sharing."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

from stalwart_api import StalwartClient, method_response, read_password

LIST_FIELDS = ("emails", "members", "urls")
SCALAR_FIELDS = ("description",)
SUPPORTED_TYPES = {"domain", "individual", "list", "oauthClient"}

CORE = "urn:ietf:params:jmap:core"
MAIL = "urn:ietf:params:jmap:mail"
PRINCIPALS = "urn:ietf:params:jmap:principals"
SUPPORTED_RIGHTS = {
    "mayAddItems",
    "mayCreateChild",
    "mayDelete",
    "mayReadItems",
    "mayRemoveItems",
    "mayRename",
    "maySetKeywords",
    "maySetSeen",
    "mayShare",
    "maySubmit",
}
# Directory-backed principals become queryable shortly after Stalwart starts;
# this only covers that gap, not an unavailable directory.
LOOKUP_DEADLINE_SECONDS = 30.0
LOOKUP_DELAY_SECONDS = 0.5


def normalize_principal(principal: dict[str, Any]) -> dict[str, Any]:
    normalized: dict[str, Any] = {
        "type": principal.get("type"),
        "name": principal.get("name"),
    }
    for field in SCALAR_FIELDS:
        if field in principal:
            normalized[field] = principal[field] or ""
    for field in LIST_FIELDS:
        if field in principal:
            value = principal[field] or []
            if not isinstance(value, list) or not all(
                isinstance(item, str) for item in value
            ):
                msg = f"{principal.get('name')}: {field} must be a list of strings"
                raise ValueError(msg)
            normalized[field] = value
    return normalized


def validate_principals(principals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    names: set[str] = set()
    normalized = []
    for raw in principals:
        principal = normalize_principal(raw)
        name = principal["name"]
        if not isinstance(name, str) or not name:
            msg = "principal name must be a non-empty string"
            raise ValueError(msg)
        if principal["type"] not in SUPPORTED_TYPES:
            msg = f"{name}: unsupported principal type {principal['type']!r}"
            raise ValueError(msg)
        if name in names:
            msg = f"duplicate principal name: {name}"
            raise ValueError(msg)
        names.add(name)
        normalized.append(principal)
    return normalized


def validate_mailbox_acls(acls: list[dict[str, Any]]) -> list[dict[str, Any]]:
    for acl in acls:
        if not acl.get("account") or not acl.get("role"):
            msg = "each mailbox ACL needs an account and a mailbox role"
            raise ValueError(msg)
        share_with = acl.get("shareWith") or {}
        if not isinstance(share_with, dict) or not share_with:
            msg = f"{acl['account']}: shareWith must be a non-empty object"
            raise ValueError(msg)
        for grantee, rights in share_with.items():
            if not isinstance(rights, list) or not rights:
                msg = f"{acl['account']}: rights for {grantee} must be a non-empty list"
                raise ValueError(msg)
            unsupported = sorted(set(rights) - SUPPORTED_RIGHTS)
            if unsupported:
                msg = (
                    f"{acl['account']}: unsupported rights for {grantee}: {unsupported}"
                )
                raise ValueError(msg)
    return acls


def build_principal_patch(
    current: dict[str, Any], desired: dict[str, Any]
) -> list[dict[str, Any]]:
    if current.get("type") != desired["type"]:
        msg = (
            f"{desired['name']}: refusing to change principal type from "
            f"{current.get('type')!r} to {desired['type']!r}"
        )
        raise ValueError(msg)

    patch = []
    for field in (*SCALAR_FIELDS, *LIST_FIELDS):
        if field not in desired:
            continue
        fallback: Any = [] if field in LIST_FIELDS else ""
        if (current.get(field) or fallback) != desired[field]:
            patch.append({"action": "set", "field": field, "value": desired[field]})
    return patch


def reconcile_principals(
    client: StalwartClient, desired_principals: list[dict[str, Any]]
) -> None:
    for desired in desired_principals:
        name = desired["name"]
        current = client.principal(name)
        if current is None:
            client.create_principal(desired)
            verify_principal(client, desired)
            print(f"created principal {name}")
            continue
        patch = build_principal_patch(current, desired)
        if not patch:
            print(f"principal {name} unchanged")
            continue
        client.patch_principal(name, patch)
        verify_principal(client, desired)
        print(f"updated principal {name}")


def verify_principal(client: StalwartClient, desired: dict[str, Any]) -> None:
    current = client.principal(desired["name"])
    if current is None:
        msg = f"{desired['name']}: principal is missing after reconciliation"
        raise RuntimeError(msg)
    remaining = build_principal_patch(current, desired)
    if remaining:
        msg = f"{desired['name']}: principal did not converge: {remaining}"
        raise RuntimeError(msg)


def principal_id(client: StalwartClient, admin_account: str, name: str) -> str:
    request = {
        "using": [CORE, PRINCIPALS],
        "methodCalls": [
            [
                "Principal/query",
                {"accountId": admin_account, "filter": {"text": name}, "limit": 20},
                "query",
            ],
            [
                "Principal/get",
                {
                    "accountId": admin_account,
                    "#ids": {
                        "resultOf": "query",
                        "name": "Principal/query",
                        "path": "/ids",
                    },
                    "properties": ["id", "name"],
                },
                "get",
            ],
        ],
    }
    deadline = time.monotonic() + LOOKUP_DEADLINE_SECONDS
    while True:
        result = method_response(client.jmap(request), "Principal/get")
        for principal in result.get("list", []):
            if principal.get("name") == name:
                return str(principal["id"])
        if time.monotonic() >= deadline:
            msg = f"principal is not available through JMAP: {name}"
            raise RuntimeError(msg)
        time.sleep(LOOKUP_DELAY_SECONDS)


def mailbox(client: StalwartClient, account_id: str, role: str) -> dict[str, Any]:
    request = {
        "using": [CORE, MAIL],
        "methodCalls": [
            [
                "Mailbox/get",
                {
                    "accountId": account_id,
                    "ids": None,
                    "properties": ["id", "role", "shareWith"],
                },
                "mailboxes",
            ]
        ],
    }
    result = method_response(client.jmap(request), "Mailbox/get")
    for entry in result.get("list", []):
        if entry.get("role") == role:
            return dict(entry)
    msg = f"account {account_id} has no mailbox with role {role}"
    raise RuntimeError(msg)


def sharing_diff(
    entry: dict[str, Any], grants: dict[str, list[str]]
) -> dict[str, dict[str, bool]]:
    """Return the rights to change so declared grantees hold exactly their rights.

    Grantees that are not declared keep whatever the mailbox owner shared with
    them, because mailbox sharing is also a user-facing feature.
    """
    share_with = entry.get("shareWith") or {}
    diff: dict[str, dict[str, bool]] = {}
    for grantee_id, rights in grants.items():
        granted = share_with.get(grantee_id) or {}
        changes = {right: True for right in rights if not granted.get(right)}
        changes.update(
            {
                right: False
                for right, held in granted.items()
                if held and right not in rights
            }
        )
        if changes:
            diff[grantee_id] = changes
    return diff


def apply_sharing(
    client: StalwartClient,
    account_id: str,
    entry: dict[str, Any],
    grants: dict[str, list[str]],
) -> None:
    """Replace the whole sharing map.

    Stalwart accepts per-right patch pointers only for grants: pointing a right
    at false leaves it set. Replacing shareWith is therefore the only way to
    revoke, so undeclared grantees are copied over unchanged.
    """
    mailbox_id = str(entry["id"])
    share_with = {
        grantee_id: dict(rights)
        for grantee_id, rights in (entry.get("shareWith") or {}).items()
        if grantee_id not in grants
    }
    for grantee_id, rights in grants.items():
        share_with[grantee_id] = dict.fromkeys(rights, True)
    update = {"shareWith": share_with}
    request = {
        "using": [CORE, MAIL],
        "methodCalls": [
            [
                "Mailbox/set",
                {"accountId": account_id, "update": {mailbox_id: update}},
                "set",
            ]
        ],
    }
    result = method_response(client.jmap(request), "Mailbox/set")
    not_updated = result.get("notUpdated") or {}
    if mailbox_id in not_updated:
        msg = f"mailbox {mailbox_id} was not updated: {not_updated[mailbox_id]}"
        raise RuntimeError(msg)


def reconcile_mailbox_acls(
    client: StalwartClient, desired_acls: list[dict[str, Any]]
) -> None:
    if not desired_acls:
        return
    session = client.jmap_session()
    admin_account = (session.get("primaryAccounts") or {}).get(PRINCIPALS)
    if not isinstance(admin_account, str):
        msg = "JMAP session exposes no principals account"
        raise RuntimeError(msg)

    for desired in desired_acls:
        account = desired["account"]
        role = desired["role"]
        account_id = principal_id(client, admin_account, account)
        grants = {
            principal_id(client, admin_account, grantee): rights
            for grantee, rights in desired["shareWith"].items()
        }
        entry = mailbox(client, account_id, role)
        diff = sharing_diff(entry, grants)
        if not diff:
            print(f"{account} {role} sharing unchanged")
            continue
        apply_sharing(client, account_id, entry, grants)
        remaining = sharing_diff(mailbox(client, account_id, role), grants)
        if remaining:
            msg = f"{account} {role} sharing did not converge: {remaining}"
            raise RuntimeError(msg)
        print(f"updated {account} {role} sharing")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True, help="Stalwart HTTP base URL")
    parser.add_argument("--admin-password-file", required=True, type=Path)
    parser.add_argument("--resources", required=True, type=Path)
    parser.add_argument("--username", default="admin")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        desired = json.loads(args.resources.read_text())
        if not isinstance(desired, dict):
            msg = "resources JSON must be an object"
            raise ValueError(msg)
        client = StalwartClient(
            args.base_url, args.username, read_password(args.admin_password_file)
        )
        reconcile_principals(
            client, validate_principals(desired.get("principals") or [])
        )
        reconcile_mailbox_acls(
            client, validate_mailbox_acls(desired.get("mailboxAcls") or [])
        )
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"stalwart-provision: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
