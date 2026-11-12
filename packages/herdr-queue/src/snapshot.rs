//! The per-terminal record every agent adapter writes and every reader consumes.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::account::Account;

pub const VERSION: u32 = 1;
/// The shortest cache lifetime any supported provider documents, for agents that report none.
pub const FALLBACK_TTL_SECS: i64 = 300;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub v: u32,
    pub agent: String,
    pub terminal: String,
    pub session_id: Option<String>,
    pub cwd: Option<String>,
    pub model: Option<String>,
    /// Epoch seconds, like every other time here.
    pub updated_at: i64,
    pub cache: Option<Cache>,
    pub limits: Vec<Limit>,
    pub context: Option<Context>,
    pub cost_usd: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Cache {
    pub expires_at: Option<i64>,
    pub ttl: Option<String>,
    pub certainty: Certainty,
    pub warm: Option<bool>,
    /// Tokens re-sent at full price if the next request finds the cache cold.
    pub at_stake_tokens: Option<u64>,
    pub misses: Option<u64>,
    pub miss_recache_tokens: Option<u64>,
    pub last_miss_at: Option<i64>,
    /// The causes the agent named, joined with `+`.
    pub last_miss_cause: Option<String>,
}

/// Whether the agent reported the expiry or an adapter inferred it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Certainty {
    Exact,
    Estimated,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Limit {
    pub kind: String,
    /// What the window is limited to when it is not the whole account, such as one model.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope: Option<String>,
    /// Agents name their windows differently; the length is the common key.
    pub window_minutes: Option<u32>,
    pub used_pct: f64,
    pub resets_at: Option<i64>,
}

impl Limit {
    /// A window past its reset has started over; agents only report that on their next response.
    #[must_use]
    pub fn used_pct_at(&self, now: i64) -> f64 {
        if self.resets_at.is_some_and(|r| r <= now) {
            0.0
        } else {
            self.used_pct
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Context {
    pub tokens: Option<u64>,
    pub used_pct: Option<f64>,
}

pub struct Store {
    dir: PathBuf,
}

impl Store {
    #[must_use]
    pub fn new(dir: PathBuf) -> Self {
        Self { dir }
    }

    /// `$XDG_STATE_HOME/herdr-queue`, or `None` without a home to fall back on.
    #[must_use]
    pub fn default_dir() -> Option<PathBuf> {
        let state = std::env::var_os("XDG_STATE_HOME")
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/state")))?;
        Some(state.join("herdr-queue"))
    }

    #[must_use]
    pub fn events_path(&self) -> PathBuf {
        self.dir.join("events.jsonl")
    }

    fn sessions(&self) -> PathBuf {
        self.dir.join("sessions")
    }

    #[must_use]
    pub fn read(&self, terminal: &str) -> Option<Snapshot> {
        let text = fs::read_to_string(self.sessions().join(format!("{terminal}.json"))).ok()?;
        serde_json::from_str(&text).ok()
    }

    /// # Errors
    /// Fails when the state directory cannot be written.
    pub fn write(&self, snap: &Snapshot) -> io::Result<()> {
        replace(&self.sessions(), &snap.terminal, &serde_json::to_vec(snap)?)
    }

    fn accounts(&self) -> PathBuf {
        self.dir.join("accounts")
    }

    #[must_use]
    pub fn read_account(&self, agent: &str) -> Option<Account> {
        let text = fs::read_to_string(self.accounts().join(format!("{agent}.json"))).ok()?;
        serde_json::from_str(&text).ok()
    }

    /// # Errors
    /// Fails when the state directory cannot be written.
    pub fn write_account(&self, account: &Account) -> io::Result<()> {
        replace(
            &self.accounts(),
            &account.agent,
            &serde_json::to_vec(account)?,
        )
    }

    #[must_use]
    pub fn all(&self) -> Vec<Snapshot> {
        let Ok(entries) = fs::read_dir(self.sessions()) else {
            return Vec::new();
        };
        let mut out: Vec<Snapshot> = entries
            .filter_map(Result::ok)
            .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
            .filter_map(|e| serde_json::from_str(&fs::read_to_string(e.path()).ok()?).ok())
            .collect();
        out.sort_by(|a, b| a.terminal.cmp(&b.terminal));
        out
    }
}

fn replace(dir: &Path, name: &str, contents: &[u8]) -> io::Result<()> {
    fs::create_dir_all(dir)?;
    // Readers poll this file; a rename never shows them half of it.
    let tmp = dir.join(format!(".{name}.{}.tmp", std::process::id()));
    fs::write(&tmp, contents)?;
    fs::rename(tmp, dir.join(format!("{name}.json")))
}

/// Terminal ids become file names, so anything path-like is refused.
#[must_use]
pub fn valid_terminal(id: &str) -> bool {
    !id.is_empty()
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}
