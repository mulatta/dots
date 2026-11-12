//! The per-turn report the Stow-managed pi extension pipes in.

use serde::Deserialize;

use crate::fmt::span;
use crate::snapshot::{Cache, Certainty, Context, FALLBACK_TTL_SECS, Snapshot, VERSION};

#[derive(Debug, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Turn {
    pub session_id: Option<String>,
    pub cwd: Option<String>,
    pub model: Option<String>,
    pub usage: Usage,
    /// Pi's lifetime for the model and retention tier, when the model declares one.
    pub cache_ttl_secs: Option<i64>,
    pub context_tokens: Option<u64>,
    pub context_window: Option<u64>,
    pub cost_usd: Option<f64>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Usage {
    pub input: u64,
    pub cache_read: u64,
    pub cache_write: u64,
    #[serde(rename = "cacheWrite1h")]
    pub cache_write_1h: u64,
}

impl Turn {
    /// # Errors
    /// Fails when the input is not a JSON object of the expected shape.
    pub fn parse(text: &str) -> serde_json::Result<Self> {
        serde_json::from_str(text)
    }
}

#[must_use]
pub fn snapshot(turn: &Turn, terminal: &str, now: i64, prev: Option<&Snapshot>) -> Snapshot {
    let prev = prev.filter(|p| p.agent == "pi" && p.session_id == turn.session_id);
    let u = &turn.usage;

    // Only a read or a write proves the provider holds a cache entry.
    let cache = if u.cache_read + u.cache_write > 0 {
        let ttl = if u.cache_write_1h > 0 {
            3600
        } else {
            turn.cache_ttl_secs.unwrap_or(FALLBACK_TTL_SECS)
        };
        Some(Cache {
            expires_at: Some(now + ttl),
            ttl: Some(span(ttl)),
            certainty: Certainty::Estimated,
            warm: Some(true),
            at_stake_tokens: Some(u.input + u.cache_read + u.cache_write),
            misses: None,
            miss_recache_tokens: None,
            last_miss_at: None,
            last_miss_cause: None,
        })
    } else {
        prev.and_then(|p| p.cache.clone())
    };

    Snapshot {
        v: VERSION,
        agent: "pi".into(),
        terminal: terminal.into(),
        session_id: turn.session_id.clone(),
        cwd: turn.cwd.clone(),
        model: turn.model.clone(),
        updated_at: now,
        cache,
        limits: Vec::new(),
        #[allow(clippy::cast_precision_loss)]
        context: turn.context_tokens.map(|tokens| Context {
            tokens: Some(tokens),
            used_pct: turn
                .context_window
                .filter(|w| *w > 0)
                .map(|w| tokens as f64 * 100.0 / w as f64),
        }),
        cost_usd: turn.cost_usd,
    }
}
