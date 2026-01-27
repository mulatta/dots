# Todoman configuration
# https://todoman.readthedocs.io/en/stable/configure.html

from typing import Any

import click

# Path to calendar directories synced by vdirsyncer
path = "~/.local/share/calendars/mulatta/*"

# Default list for new todos (must match a calendar name)
default_list = "Dev"

# Date format
date_format = "%Y-%m-%d"

# Time format
time_format = "%H:%M"

# Datetime format
dt_separator = " "

# Default priority for new todos (1-9, where 1 is highest)
default_priority = 5

# Default due date offset for new todos (e.g., "3d" for 3 days)
default_due = 72

# Start of the week (0 = Monday, 6 = Sunday)
startofweek = 0

# Color output
color = "auto"

# Show completed todos by default
show_completed = False

# Humanize dates (show "tomorrow" instead of date)
humanize = True
