//! Codex's `PostModelRequest` hook input, plus the rollout file it points at.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

use serde::Deserialize;
use serde_json::Value;

use crate::fmt::span;
use crate::snapshot::{Cache, Certainty, Context, FALLBACK_TTL_SECS, Limit, Snapshot, VERSION};

// Token-count events are small, but tool output between them is not.
const ROLLOUT_TAIL_BYTES: u64 = 512 * 1024;
// OpenAI caches prompts from this size up without being asked.
const MIN_CACHED_PROMPT_TOKENS: u64 = 1024;

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Hook {
    pub session_id: Option<String>,
    pub cwd: Option<String>,
    pub model: Option<String>,
    pub transcript_path: Option<String>,
    pub hook_event_name: Option<String>,
    pub status: Option<String>,
    /// Set for subagent requests, which keep a prompt cache of their own.
    pub agent_id: Option<String>,
    pub token_usage: Option<TokenUsage>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct TokenUsage {
    /// Includes the cached tokens.
    pub input_tokens: u64,
}

impl Hook {
    /// # Errors
    /// Fails when the input is not a JSON object of the expected shape.
    pub fn parse(text: &str) -> serde_json::Result<Self> {
        serde_json::from_str(text)
    }
}

/// What only the rollout knows: the usage windows and the context size.
#[derive(Debug, Default)]
pub struct Rollout {
    pub limits: Vec<Limit>,
    pub context_window: Option<u64>,
}

#[derive(Deserialize)]
struct Slot {
    used_percent: f64,
    window_minutes: Option<u32>,
    resets_at: Option<i64>,
}

impl Rollout {
    /// The newest token-count event in the file, if it has one near its end.
    #[must_use]
    pub fn read(path: &str) -> Option<Self> {
        let mut file = File::open(path).ok()?;
        let len = file.metadata().ok()?.len();
        file.seek(SeekFrom::Start(len.saturating_sub(ROLLOUT_TAIL_BYTES)))
            .ok()?;
        let mut tail = Vec::new();
        file.read_to_end(&mut tail).ok()?;
        let tail = String::from_utf8_lossy(&tail);
        let line = tail.lines().rev().find(|l| l.contains("\"rate_limits\""))?;
        let payload = serde_json::from_str::<Value>(line)
            .ok()?
            .get("payload")?
            .clone();

        // Codex does not say which slot is the weekly one; the window length does.
        let mut limits: Vec<Limit> = ["primary", "secondary"]
            .iter()
            .filter_map(|slot| {
                let w: Slot = serde_json::from_value(payload["rate_limits"][slot].clone()).ok()?;
                Some(Limit {
                    kind: (*slot).into(),
                    scope: None,
                    window_minutes: w.window_minutes,
                    used_pct: w.used_percent,
                    resets_at: w.resets_at,
                })
            })
            .collect();
        limits.sort_by_key(|l| l.window_minutes.unwrap_or(u32::MAX));
        Some(Self {
            limits,
            context_window: payload["info"]["model_context_window"].as_u64(),
        })
    }
}

/// `None` for input that says nothing about the main thread's cache.
#[must_use]
pub fn snapshot(
    hook: &Hook,
    terminal: &str,
    now: i64,
    prev: Option<&Snapshot>,
    rollout: Option<&Rollout>,
) -> Option<Snapshot> {
    if hook.hook_event_name.as_deref() != Some("PostModelRequest") || hook.agent_id.is_some() {
        return None;
    }
    let prev = prev.filter(|p| p.agent == "codex" && p.session_id == hook.session_id);
    let usage = hook
        .token_usage
        .as_ref()
        .filter(|_| hook.status.as_deref() == Some("completed"));

    // Codex reports no expiry, so this is the earliest the cache can lapse.
    let cache = match usage {
        Some(u) if u.input_tokens >= MIN_CACHED_PROMPT_TOKENS => Some(Cache {
            expires_at: Some(now + FALLBACK_TTL_SECS),
            ttl: Some(span(FALLBACK_TTL_SECS)),
            certainty: Certainty::Estimated,
            warm: Some(true),
            at_stake_tokens: Some(u.input_tokens),
            misses: None,
            miss_recache_tokens: None,
            last_miss_at: None,
            last_miss_cause: None,
        }),
        _ => prev.and_then(|p| p.cache.clone()),
    };
    let context = match usage {
        #[allow(clippy::cast_precision_loss)]
        Some(u) => Some(Context {
            tokens: Some(u.input_tokens),
            used_pct: rollout
                .and_then(|r| r.context_window)
                .filter(|w| *w > 0)
                .map(|w| u.input_tokens as f64 * 100.0 / w as f64),
        }),
        None => prev.and_then(|p| p.context.clone()),
    };

    Some(Snapshot {
        v: VERSION,
        agent: "codex".into(),
        terminal: terminal.into(),
        session_id: hook.session_id.clone(),
        cwd: hook.cwd.clone(),
        model: hook.model.clone(),
        updated_at: now,
        cache,
        limits: rollout.map_or_else(
            || prev.map(|p| p.limits.clone()).unwrap_or_default(),
            |r| r.limits.clone(),
        ),
        context,
        cost_usd: None,
    })
}
