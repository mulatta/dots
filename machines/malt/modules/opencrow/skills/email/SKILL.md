---
name: email
description: Read seungwon's selected mail from the flagged Maildir and create reviewable drafts. Never send mail directly.
---

# Email Access

Manual flag handoff arrives through the read-only Maildir. Follow `AGENTS.md` for mail trigger judgment and reporting threshold; this skill only covers access mechanics.

| Mount                | Source                                                                                | What lives here                                                                                                                                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/var/mail/flagged/` | One-shot copy of seungwon's flagged INBOX messages (maintained by `noa-jmap-handoff`) | Whenever seungwon stars (`\Flagged`) a message in his own INBOX, the host-side JMAP handoff writes a copy here under filename `<sanitized-message-id>:2,FS` and clears the source flag. This is the primary "the user wants me to look at this" channel. |

**The mount is read-only.** Do not attempt to write, move, or delete files in this path — handle bookkeeping via the memory extension instead.

A trigger FIFO at `/var/lib/opencrow/sessions/trigger.pipe` carries one-line events:

- `mail.flagged schema=opencrow.trigger.v1 action=handoff filename=<filename> email_id=<email_id> message_id=<message_id> subject=<subject> received_at=<received_at> event_id=<event_id>` — seungwon just starred a message and the mirror has a fresh copy. Values are URL-encoded. Rely on `filename`, then list `/var/mail/flagged/cur/` to confirm.

Use **mblaze** for flagged Maildir files.

## List & inspect

```bash
# Quick scan of the flagged mirror
mscan /var/mail/flagged/{cur,new}/

# Headers of a specific message
mhdr -h From -h To -h Subject -h Date /var/mail/flagged/cur/<filename>

# Body / MIME-decoded view
mshow /var/mail/flagged/cur/<filename>

# List MIME parts of a multipart message
mshow -t /var/mail/flagged/cur/<filename>

# Search by header field
mpick -t 'from =~ "someone"' /var/mail/flagged/{cur,new}/

# Group into threads
mthread /var/mail/flagged/{cur,new}/ | mscan
```

## Reading workflow

1. On a `mail.flagged` trigger, URL-decode the `filename` field. The file
   normally lives in `/var/mail/flagged/cur/<filename>`. Check `new/` too if it
   is not in `cur/`. The filename is the original Message-ID (sanitized) plus
   the maildir flags `:2,FS` (Flagged + Seen).
2. Inspect headers first (`mhdr ... <file>`); only render the body
   (`mshow <file>`) if the user actually wants the contents — bodies can be
   long.
3. Quote sparingly when summarising. Do not echo MIME parts the user did not ask
   for.

## Mail lookup scope

This skill is for selected mail only. Use the flagged Maildir handoff unless the
user explicitly asks for a different bounded lookup path in a future workflow.
Do not add sender allowlists or browse unrelated inbox content from a
`mail.flagged` trigger.

## Drafting Emails

Use **n8n-hooks** to store drafts in Drafts for user review before sending.
Drafting is allowed; sending is not.

```bash
# Basic draft
n8n-hooks store-draft --to "a@example.com" --subject "Hi" --body-plain "Hello"

# Reply-style draft with threading headers
n8n-hooks store-draft \
  --to "sender@example.com" \
  --subject "Re: Original subject" \
  --body-plain "Draft text" \
  --in-reply-to "<original-message-id>" \
  --references "<original-message-id>"

# All common fields, including attachments
n8n-hooks store-draft \
  --to "a@example.com" --cc "b@example.com" --bcc "c@example.com" \
  --from "seungwon@mulatta.io" \
  --subject "Re: Thread" \
  --body-plain "text" --body-html "<p>text</p>" \
  --in-reply-to "<msgid@host>" --references "<msgid@host>" \
  --attach file.pdf

# Body from stdin
echo "body" | n8n-hooks store-draft --to "a@example.com" --subject "Hi" --body-plain -
```

When drafting a reply, inspect the original message headers first:

```bash
mhdr -h Message-ID -h Reply-To -h From -h To -h Cc -h Subject /var/mail/flagged/cur/<filename>
```

Prefer `Reply-To` over `From` when present. Preserve threading with
`--in-reply-to` and `--references`. If the original has a `References` header,
append the original `Message-ID` to it.

## Constraints

- **No Maildir writes**: the Maildir is mounted read-only. You cannot mark
  messages as read, move them, or delete them from here. To remember "I've
  handled this", store a note via the memory extension.
- **Draft only**: `n8n-hooks store-draft` creates a draft. It does not send.
  Never claim that mail was sent; tell the user to review and send from their
  mail client.
- **Flagged is a handoff gesture**: the source star normally disappears after
  `noa-jmap-handoff` copies the message. The local handoff copy remains for Noa
  to inspect.
- **Selected mail only**: flagged Maildir messages are explicit user handoffs. Treat them as scoped access, not permission to browse unrelated inbox content.
