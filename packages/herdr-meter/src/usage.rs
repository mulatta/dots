//! Which report of an account's limits to believe: the program's own answer, or a terminal's.

use std::fmt::Write;

use serde::Serialize;

use crate::account::AGENTS;
use crate::fmt::{span, window_label};
use crate::snapshot::{Limit, Store};

/// An answer this old is taken as the question no longer working.
const FRESH_SECS: i64 = 1800;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Usage {
    pub agent: &'static str,
    /// `account` for the program's answer, `terminal` for what a session last saw.
    pub source: Option<&'static str>,
    pub updated_at: Option<i64>,
    /// Why the last question failed, whichever source is shown.
    pub error: Option<String>,
    pub plan: Option<String>,
    pub limits: Vec<Limit>,
}

#[must_use]
pub fn resolve(store: &Store, now: i64) -> Vec<Usage> {
    let sessions = store.all();
    AGENTS
        .iter()
        .map(|&agent| {
            let account = store.read_account(agent);
            let asked = account.as_ref().and_then(|a| a.updated_at);
            let seen = sessions
                .iter()
                .filter(|s| s.agent == agent && !s.limits.is_empty())
                .max_by_key(|s| s.updated_at);
            let error = account.as_ref().and_then(|a| a.error.clone());
            // The answer covers every session and model, so it wins while it is being renewed.
            let use_account = match (asked, seen) {
                (Some(asked), Some(seen)) => now - asked <= FRESH_SECS || asked >= seen.updated_at,
                (Some(_), None) => true,
                (None, _) => false,
            };
            match (account, seen) {
                (Some(account), _) if use_account => Usage {
                    agent,
                    source: Some("account"),
                    updated_at: asked,
                    error,
                    plan: account.plan,
                    limits: account.limits,
                },
                (_, Some(seen)) => Usage {
                    agent,
                    source: Some("terminal"),
                    updated_at: Some(seen.updated_at),
                    error,
                    plan: None,
                    limits: seen.limits.clone(),
                },
                _ => Usage {
                    agent,
                    source: None,
                    updated_at: None,
                    error,
                    plan: None,
                    limits: Vec::new(),
                },
            }
        })
        .collect()
}

#[must_use]
pub fn table(all: &[Usage], now: i64) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "{:<7} {:<9} {:<7} LIMITS", "AGENT", "SOURCE", "AGE");
    for l in all {
        let windows: Vec<String> = l
            .limits
            .iter()
            .map(|w| {
                let scope = w.scope.as_ref().map_or(String::new(), |s| format!(" {s}"));
                format!(
                    "{}{scope} {:.0}%",
                    window_label(&w.kind, w.window_minutes),
                    w.used_pct_at(now)
                )
            })
            .collect();
        let _ = writeln!(
            out,
            "{:<7} {:<9} {:<7} {}",
            l.agent,
            l.source.unwrap_or("-"),
            l.updated_at.map_or("-".into(), |at| span(now - at)),
            if windows.is_empty() {
                l.error.clone().unwrap_or_else(|| "-".into())
            } else {
                windows.join("  ")
            }
        );
    }
    out
}
