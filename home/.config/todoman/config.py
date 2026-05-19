# Todoman configuration
# https://todoman.readthedocs.io/en/stable/configure.html

from __future__ import annotations

import os
from collections.abc import Iterable
from datetime import date, datetime
from typing import Any

import click

# Path to calendar directories synced by vdirsyncer
path = "~/.local/share/calendars/*"

# Default list for new todos (must match a calendar name)
default_list = "dev"

# Date format
date_format = "%Y-%m-%d"

# Time format
time_format = "%H:%M"

# Datetime format
dt_separator = " "

# Default priority for new todos (1-9, where 1 is highest)
default_priority = 5

# Do not invent due dates. Use -d/--due only for real deadlines.
default_due = 0

# Start of the week (0 = Monday, 6 = Sunday)
startofweek = 0

# Color output
color = "auto"

# Only show todos whose start date is today or in the past.
# Use future start dates as backlog review dates.
startable = True

# Show completed todos by default
show_completed = False

# Humanize dates (show "tomorrow" instead of date)
humanize = True


# Monkeypatch todoman's hardcoded colors for Catppuccin Mocha.
# This keeps todoman's native field coloring without the previous alpha/fade
# formatter override.
_original_style = click.style


def _mocha_style(text: str, **kwargs: Any) -> str:
    color_map: dict[str, tuple[int, int, int]] = {
        "magenta": (203, 166, 247),  # priority markers: mauve
        "red": (243, 139, 168),  # overdue: red
        "yellow": (249, 226, 175),  # due soon: yellow
        "white": (186, 194, 222),  # future dates: subtext1
    }

    fg = kwargs.get("fg")
    if isinstance(fg, str) and fg in color_map:
        kwargs["fg"] = color_map[fg]

    return _original_style(text, **kwargs)


click.style = _mocha_style


# Todoman's default sort puts undated tasks before dated tasks and orders due
# dates farthest first. Keep a small query-result sort so `todo list` shows
# higher priority and nearer due dates first while retaining native formatting.
if os.environ.get("TODOMAN_DISABLE_CUSTOM_LIST") != "1":
    from todoman.model import Database, Todo

    NO_PRIORITY = 10_000
    NO_DUE = (1, float("inf"))
    NO_CREATED = float("inf")

    _original_todos = Database.todos

    def _priority_value(todo: Todo) -> int:
        priority = getattr(todo, "priority", 0)
        if isinstance(priority, int) and priority > 0:
            return priority
        return NO_PRIORITY

    def _timestamp(value: date | datetime | None) -> float | None:
        if isinstance(value, datetime):
            return value.timestamp()
        if isinstance(value, date):
            return datetime(value.year, value.month, value.day).timestamp()
        return None

    def _due_value(todo: Todo) -> tuple[int, float]:
        timestamp = _timestamp(getattr(todo, "due", None))
        if timestamp is not None:
            return (0, timestamp)
        return NO_DUE

    def _urgency_key(todo: Todo) -> tuple[Any, ...]:
        created = _timestamp(getattr(todo, "created_at", None)) or NO_CREATED
        list_name = getattr(getattr(todo, "list", None), "name", "")
        return (
            _priority_value(todo),
            _due_value(todo),
            created,
            list_name,
            getattr(todo, "id", 0) or 0,
        )

    def _todos_by_urgency(self: Database, *args: Any, **kwargs: Any) -> Iterable[Todo]:
        todos = list(_original_todos(self, *args, **kwargs))
        if not kwargs.get("sort"):
            todos.sort(key=_urgency_key)
        return iter(todos)

    Database.todos = _todos_by_urgency
