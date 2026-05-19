"""n8n hook modules."""

from . import (
    github,
    linkwarden,
    linkwarden_link_create,
    rss,
    slack,
    store_draft,
    vikunja,
    vikunja_task_create,
)

__all__ = [
    "github",
    "linkwarden",
    "linkwarden_link_create",
    "rss",
    "slack",
    "store_draft",
    "vikunja",
    "vikunja_task_create",
]
