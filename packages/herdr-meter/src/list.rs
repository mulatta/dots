//! A plain table of every snapshot, for people; `--json` is for programs.

use std::fmt::Write;

use crate::fmt::{span, tokens, window_label};
use crate::snapshot::Snapshot;

#[must_use]
pub fn table(snaps: &[Snapshot], now: i64) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "{:<8} {:<7} {:<14} {:<7} {:<7} LIMITS",
        "TERMINAL", "AGENT", "MODEL", "CACHE", "STAKE"
    );
    for s in snaps {
        let cache = s.cache.as_ref();
        let left = match cache.and_then(|c| c.expires_at) {
            Some(at) if at > now => span(at - now),
            Some(_) => "cold".into(),
            None => "-".into(),
        };
        let stake = cache
            .and_then(|c| c.at_stake_tokens)
            .map_or("-".into(), tokens);
        let limits: Vec<String> = s
            .limits
            .iter()
            .map(|l| {
                format!(
                    "{} {:.0}%",
                    window_label(&l.kind, l.window_minutes),
                    l.used_pct_at(now)
                )
            })
            .collect();
        let _ = writeln!(
            out,
            "{:<8} {:<7} {:<14} {:<7} {:<7} {}",
            s.terminal,
            s.agent,
            s.model.as_deref().unwrap_or("-"),
            left,
            stake,
            limits.join(" ")
        );
    }
    out
}
