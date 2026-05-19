# pim

`pim` is a focused Personal Information Manager agent wrapper around `pi`.
It is not the DAV migration path and does not discover or migrate DAV data by
itself.

The wrapper assumes local vdirsyncer data has already been reviewed, discovered,
and synced outside the agent session. It is intended for calendar, mail, todo,
contacts, RSS/Miniflux, and Vikunja workflows over local XDG data:

- Calendars: `~/.local/share/calendars/`
- Contacts: `~/.local/share/contacts/`
- Mail: `~/.local/share/mail/`
- vdirsyncer state: `~/.local/share/vdirsyncer/`
- vdirsyncer cache: `~/.cache/vdirsyncer/`
- vdirsyncer config: `~/.config/vdirsyncer/`
- Miniflux cache: `~/.cache/miniflux-cli/`
- Miniflux config: `~/.config/miniflux-cli/`
- Vikunja CLI config: `~/.config/vikunja-cli/`

## Scope

The wrapper provides a restricted PIM tool `PATH` containing `calendar-cli`,
`crabfit-cli`, `vdirsyncer`, `todoman`, `notmuch`, `afew`, `mrefile`/`mshow`
from mblaze, `msmtp`, `mbsync`, `email-sync`, `khard`, `miniflux-cli`, `vikunja-cli`,
`rbw`, and basic shell utilities. It also registers the bundled `crabfit-cli`,
`miniflux-cli`, and `vikunja-cli` pi skills with `--skill`, keeping them
available for focused PIM sessions without putting them in the default pi skill
set.

Use `calendar-cli --url` for a VEVENT primary source link and repeated
`--attach` values for related document/file links.

On Linux, `pim` uses `bubblewrap` when available and only binds the XDG
calendar/mail/contact/vdirsyncer/rbw/Vikunja/pi paths it needs. On Darwin, it runs
unsandboxed, matching the upstream Mic92 design.

The package is exposed as a flake package only. Do not add it to Home Manager
profiles until the DAV migration/configuration work has been reviewed.
