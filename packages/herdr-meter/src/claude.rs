//! Claude Code's status line input: the JSON it pipes to `statusLine.command`.

use std::collections::BTreeMap;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Deserializer};
use serde_json::Value;

use crate::snapshot::{Cache, Certainty, Context, Limit, Snapshot, VERSION};

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Status {
    #[serde(deserialize_with = "lenient")]
    pub session_id: Option<String>,
    #[serde(deserialize_with = "lenient")]
    pub cwd: Option<String>,
    #[serde(deserialize_with = "lenient")]
    pub model: Option<Model>,
    #[serde(deserialize_with = "lenient")]
    pub workspace: Option<Workspace>,
    #[serde(deserialize_with = "lenient")]
    pub cost: Option<Cost>,
    #[serde(deserialize_with = "lenient")]
    pub context_window: Option<ContextWindow>,
    #[serde(deserialize_with = "lenient")]
    pub prompt_cache: Option<PromptCache>,
    #[serde(deserialize_with = "lenient")]
    pub rate_limits: Option<BTreeMap<String, Value>>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Model {
    pub id: Option<String>,
    pub display_name: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Workspace {
    pub current_dir: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Cost {
    pub total_cost_usd: Option<f64>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct ContextWindow {
    pub total_input_tokens: Option<u64>,
    pub used_percentage: Option<f64>,
    pub current_usage: Option<CurrentUsage>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct CurrentUsage {
    pub input_tokens: u64,
    pub cache_creation_input_tokens: u64,
    pub cache_read_input_tokens: u64,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct PromptCache {
    #[serde(deserialize_with = "lenient")]
    pub warm: Option<bool>,
    #[serde(deserialize_with = "lenient")]
    pub caching_observed: Option<bool>,
    #[serde(deserialize_with = "lenient")]
    pub ttl: Option<String>,
    #[serde(deserialize_with = "lenient")]
    pub expires_at: Option<i64>,
    #[serde(deserialize_with = "lenient")]
    pub misses: Option<u64>,
    #[serde(deserialize_with = "lenient")]
    pub miss_recache_tokens: Option<u64>,
    #[serde(deserialize_with = "lenient")]
    pub last_miss_at: Option<i64>,
    #[serde(deserialize_with = "lenient")]
    pub last_miss_cause: Option<MissCause>,
    #[serde(deserialize_with = "lenient")]
    pub recache_tokens_if_cold: Option<u64>,
}

/// Why the last miss happened; Claude Code can name several causes at once.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct MissCause {
    pub causes: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct Window {
    used_percentage: f64,
    resets_at: Option<i64>,
}

// The input grows with every Claude Code release; a field that changes shape
// should cost that field, not the whole status line.
fn lenient<'de, D, T>(d: D) -> Result<Option<T>, D::Error>
where
    D: Deserializer<'de>,
    T: DeserializeOwned,
{
    let value = Value::deserialize(d)?;
    Ok(serde_json::from_value(value).ok())
}

impl Status {
    /// # Errors
    /// Fails when the input is not a JSON object.
    pub fn parse(text: &str) -> serde_json::Result<Self> {
        serde_json::from_str(text)
    }

    #[must_use]
    pub fn dir(&self) -> Option<&str> {
        self.workspace
            .as_ref()
            .and_then(|w| w.current_dir.as_deref())
            .or(self.cwd.as_deref())
    }

    #[must_use]
    pub fn model_name(&self) -> Option<&str> {
        let m = self.model.as_ref()?;
        m.display_name.as_deref().or(m.id.as_deref())
    }

    /// Tokens in the context right now: the last request's whole input.
    #[must_use]
    pub fn context_tokens(&self) -> Option<u64> {
        let cw = self.context_window.as_ref()?;
        cw.current_usage
            .as_ref()
            .map(|u| u.input_tokens + u.cache_creation_input_tokens + u.cache_read_input_tokens)
            .or(cw.total_input_tokens)
    }

    /// The cache block, unless the session has not cached anything yet.
    #[must_use]
    pub fn cache(&self) -> Option<&PromptCache> {
        self.prompt_cache
            .as_ref()
            .filter(|c| c.caching_observed != Some(false) && c.expires_at.is_some())
    }

    /// Windows shortest first; unknown kinds keep their name and sort last.
    #[must_use]
    pub fn limits(&self) -> Vec<Limit> {
        let mut out: Vec<Limit> = self
            .rate_limits
            .iter()
            .flatten()
            .filter_map(|(kind, v)| {
                let w: Window = serde_json::from_value(v.clone()).ok()?;
                let window_minutes = match kind.as_str() {
                    "five_hour" => Some(300),
                    "seven_day" => Some(10080),
                    _ => None,
                };
                Some(Limit {
                    kind: kind.clone(),
                    scope: None,
                    window_minutes,
                    used_pct: w.used_percentage,
                    resets_at: w.resets_at,
                })
            })
            .collect();
        out.sort_by_key(|l| l.window_minutes.unwrap_or(u32::MAX));
        out
    }
}

#[must_use]
pub fn snapshot(status: &Status, terminal: &str, now: i64) -> Snapshot {
    Snapshot {
        v: VERSION,
        agent: "claude".into(),
        terminal: terminal.into(),
        session_id: status.session_id.clone(),
        cwd: status.dir().map(Into::into),
        model: status.model_name().map(Into::into),
        updated_at: now,
        cache: status.cache().map(|c| Cache {
            expires_at: c.expires_at,
            ttl: c.ttl.clone(),
            certainty: Certainty::Exact,
            warm: c.warm,
            at_stake_tokens: c.recache_tokens_if_cold,
            misses: c.misses,
            miss_recache_tokens: c.miss_recache_tokens,
            last_miss_at: c.last_miss_at,
            last_miss_cause: c.last_miss_cause.as_ref().map(|m| m.causes.join("+")),
        }),
        limits: status.limits(),
        context: status.context_window.as_ref().map(|cw| Context {
            tokens: status.context_tokens(),
            used_pct: cw.used_percentage,
        }),
        cost_usd: status.cost.as_ref().and_then(|c| c.total_cost_usd),
    }
}
