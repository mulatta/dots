---
name: contacts
description: Manage local CardDAV/vdirsyncer contacts. Use for saving, updating, searching, normalizing, merging, or deleting contact data: phones, emails, names, organizations, titles, notes, and categories.
---

# Contacts tool access

Contacts are vCard files synced by vdirsyncer. Follow `AGENTS.md` for contact
intent, safety, category, and reply policy; this skill only covers mechanics.

- Pair: `contacts_stalwart`
- Local path: `/var/lib/opencrow/.local/share/contacts/contacts/`
- Config: `/var/lib/opencrow/.config/vdirsyncer/config`
- Extension: `.vcf`

Do not put contact details in `MEMO.md` unless user explicitly asks for memo.
Do not expose credentials.

## Workflow

```bash
# 1. Refresh before reading
vdirsyncer sync contacts_stalwart

# 2. Search related contacts first
rg -n -i "<name>|<company-alias>|<phone-fragment>|<email-domain>" \
  /var/lib/opencrow/.local/share/contacts/contacts/*.vcf

# 3. Inspect relevant cards
rg -n "^(FN|N|ORG|TITLE|TEL|EMAIL|NOTE|CATEGORIES|UID|REV):" \
  /var/lib/opencrow/.local/share/contacts/contacts/<file>.vcf

# 4. Edit/create .vcf, then sync and verify
vdirsyncer sync contacts_stalwart
```

## vCard rules

Prefer vCard 3.0 for new cards:

```vcf
BEGIN:VCARD
VERSION:3.0
PRODID:-//opencrow//contacts//EN
UID:<uuid>
FN:<display name>
N:<family>;<given>;;;
ORG:<normalized organization>
TITLE:<job title>
TEL;TYPE=CELL,VOICE:<phone>
EMAIL;TYPE=WORK,INTERNET:<email>
NOTE:<short note>
CATEGORIES:<comma,separated,categories>
REV:<YYYYMMDDTHHMMSSZ>
END:VCARD
```

Generate `UID` with `uuidgen` or Python. Use UTC `REV`.

Escape text values: backslash as `\\`, comma as `\,`, semicolon as `\;`, newline as `\n`. Do not escape structural semicolons in `N:`.

## Naming mechanics

- Person contact: `FN` is name only. Put company in `ORG`, rank/role in `TITLE`.
- Service/team contact: `FN` may be service display name.
- Normalize organization names by matching existing contacts first.
- Avoid `ORG:<company>;<team>` because iPhone may show semicolon. Prefer:

```vcf
ORG:<company>
TITLE:<team-or-role>
```

## Conflicts

vdirsyncer hooks keep the local storage root under git and commit item updates
and deletions. If sync reports both local and remote changed, an unexpected
deletion appears, or overwrite is ambiguous, inspect git history before choosing
a version:

```bash
git -C /var/lib/opencrow/.local/share/contacts log -- <file>
git -C /var/lib/opencrow/.local/share/contacts show <commit> -- <file>
```

Preserve unrelated remote edits. Resolve with local version only when current
user request clearly authorizes those fields; otherwise ask.
