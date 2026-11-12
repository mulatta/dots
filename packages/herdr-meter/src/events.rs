//! An append-only record of cache misses, kept to judge what cold caches cost.

use std::fs::OpenOptions;
use std::io::{self, Write};
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::snapshot::Snapshot;

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Event {
    pub ts: i64,
    pub event: String,
    pub agent: String,
    pub terminal: String,
    pub session_id: Option<String>,
    pub cause: Option<String>,
    /// Tokens this miss made the agent send again.
    pub recache_tokens: Option<u64>,
    /// How long the cache had been expired when the request arrived.
    pub cold_secs: Option<i64>,
}

/// The miss that happened between two snapshots of one session, if any.
#[must_use]
pub fn cache_miss(prev: &Snapshot, next: &Snapshot) -> Option<Event> {
    if prev.session_id != next.session_id {
        return None;
    }
    let (before, after) = (prev.cache.as_ref()?, next.cache.as_ref()?);
    if after.misses? <= before.misses.unwrap_or(0) {
        return None;
    }
    let cold_secs = match (after.last_miss_at, before.expires_at) {
        (Some(at), Some(expired)) if at > expired => Some(at - expired),
        _ => None,
    };
    Some(Event {
        ts: next.updated_at,
        event: "cache_miss".into(),
        agent: next.agent.clone(),
        terminal: next.terminal.clone(),
        session_id: next.session_id.clone(),
        cause: after.last_miss_cause.clone(),
        recache_tokens: after
            .miss_recache_tokens
            .map(|t| t.saturating_sub(before.miss_recache_tokens.unwrap_or(0))),
        cold_secs,
    })
}

/// # Errors
/// Fails when the log cannot be opened or written.
pub fn append(path: &Path, event: &Event) -> io::Result<()> {
    let mut line = serde_json::to_vec(event)?;
    line.push(b'\n');
    // One write per line keeps concurrent sessions from interleaving.
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?
        .write_all(&line)
}
