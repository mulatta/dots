//! Each account's rate limits, asked of the agent's own program so that `hq` never holds a token.

use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::snapshot::{Limit, Store, VERSION};

/// Both programs answer from an endpoint that throttles hard; nothing asks more often than this.
const MIN_INTERVAL_SECS: i64 = 300;
const MAX_INTERVAL_SECS: i64 = 3600;
const CLAUDE_TIMEOUT: Duration = Duration::from_secs(20);
const CODEX_START_TIMEOUT: Duration = Duration::from_secs(15);
const CODEX_REPLY_TIMEOUT: Duration = Duration::from_secs(20);

pub const AGENTS: [&str; 2] = ["claude", "codex"];

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Account {
    pub v: u32,
    pub agent: String,
    /// When `limits` were last read; a failed attempt leaves them and this untouched.
    pub updated_at: Option<i64>,
    pub attempted_at: i64,
    /// Attempts that failed since the last answer; each one doubles the wait.
    pub failures: u32,
    pub error: Option<String>,
    pub plan: Option<String>,
    pub limits: Vec<Limit>,
}

impl Account {
    fn due(&self, now: i64) -> bool {
        let wait = MIN_INTERVAL_SECS
            .saturating_mul(1_i64 << self.failures.min(8))
            .min(MAX_INTERVAL_SECS);
        now - self.attempted_at >= wait
    }
}

/// Days since the epoch for a civil date (Howard Hinnant's `days_from_civil`).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// Epoch seconds for an RFC 3339 time such as `2026-11-12T09:40:00.446010+00:00`.
fn epoch(text: &str) -> Option<i64> {
    let (date, time) = text.split_once('T')?;
    let mut date = date.split('-').map(str::parse::<i64>);
    let (year, month, day) = (date.next()?.ok()?, date.next()?.ok()?, date.next()?.ok()?);
    // The offset starts at the first sign or `Z` after the clock.
    let at = time.find(['+', '-', 'Z'])?;
    let (clock, offset) = time.split_at(at);
    let mut clock = clock.split(':');
    let hour: i64 = clock.next()?.parse().ok()?;
    let minute: i64 = clock.next()?.parse().ok()?;
    let second: i64 = clock.next()?.split('.').next()?.parse().ok()?;
    let offset = match offset.strip_prefix(['+', '-']) {
        None => 0,
        Some(hm) => {
            let (h, m) = hm.split_once(':')?;
            let secs = h.parse::<i64>().ok()? * 3600 + m.parse::<i64>().ok()? * 60;
            if offset.starts_with('-') { -secs } else { secs }
        }
    };
    Some(days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second - offset)
}

#[derive(Deserialize)]
struct Entry {
    kind: String,
    percent: f64,
    resets_at: Option<String>,
}

/// The windows and plan in Claude Code's reply to a `get_usage` control request.
///
/// # Errors
/// Fails when the reply carries no windows, as for an account without a subscription.
pub fn claude_limits(reply: &Value) -> Result<(Vec<Limit>, Option<String>), String> {
    let usage = &reply["response"]["response"];
    let entries = usage["rate_limits"]["limits"].as_array();
    let limits: Vec<Limit> = entries
        .into_iter()
        .flatten()
        .filter_map(|entry| {
            let e: Entry = serde_json::from_value(entry.clone()).ok()?;
            // Claude Code names its windows instead of giving their length.
            let (kind, window_minutes) = match e.kind.as_str() {
                "session" => ("five_hour", Some(300)),
                "weekly_all" | "weekly_scoped" => ("seven_day", Some(10080)),
                other => (other, None),
            };
            Some(Limit {
                kind: kind.into(),
                scope: entry["scope"]["model"]["display_name"]
                    .as_str()
                    .map(str::to_owned),
                window_minutes,
                used_pct: e.percent,
                resets_at: e.resets_at.as_deref().and_then(epoch),
            })
        })
        .collect();
    if limits.is_empty() {
        let error = reply["response"]["error"].as_str();
        return Err(error.unwrap_or("no rate limits in the answer").into());
    }
    Ok((
        limits,
        usage["subscription_type"].as_str().map(str::to_owned),
    ))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Slot {
    used_percent: f64,
    window_duration_mins: Option<u32>,
    resets_at: Option<i64>,
}

/// The windows and plan in the result of Codex's `account/rateLimits/read`.
///
/// # Errors
/// Fails when the result has no rate limits for Codex.
pub fn codex_limits(result: &Value) -> Result<(Vec<Limit>, Option<String>), String> {
    let limits = match &result["rateLimitsByLimitId"]["codex"] {
        Value::Null => &result["rateLimits"],
        by_id => by_id,
    };
    if !limits.is_object() {
        return Err("no rate limits in the answer".into());
    }
    // A plan with one window leaves the other slot null.
    let mut windows: Vec<Limit> = ["primary", "secondary"]
        .iter()
        .filter_map(|slot| {
            let w: Slot = serde_json::from_value(limits[slot].clone()).ok()?;
            Some(Limit {
                kind: (*slot).into(),
                scope: None,
                window_minutes: w.window_duration_mins,
                used_pct: w.used_percent,
                resets_at: w.resets_at,
            })
        })
        .collect();
    windows.sort_by_key(|l| l.window_minutes.unwrap_or(u32::MAX));
    Ok((windows, limits["planType"].as_str().map(str::to_owned)))
}

/// Starts `program` with its output read line by line in the background.
fn start(program: &str, args: &[&str]) -> Result<(Child, ChildStdin, Receiver<String>), String> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    let (Some(stdin), Some(stdout)) = (child.stdin.take(), child.stdout.take()) else {
        stop(child);
        return Err("no pipes to the program".into());
    };
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if tx.send(line).is_err() {
                break;
            }
        }
    });
    Ok((child, stdin, rx))
}

fn stop(mut child: Child) {
    let _ = child.kill();
    let _ = child.wait();
}

fn send(stdin: &mut ChildStdin, message: &Value) -> Result<(), String> {
    writeln!(stdin, "{message}").map_err(|e| e.to_string())
}

/// The first message `wanted` accepts; both programs also print lines nobody asked for.
fn wait_for(
    rx: &Receiver<String>,
    timeout: Duration,
    wanted: impl Fn(&Value) -> bool,
) -> Result<Value, String> {
    let deadline = Instant::now() + timeout;
    loop {
        let line = rx
            .recv_timeout(deadline.saturating_duration_since(Instant::now()))
            .map_err(|_| "no answer in time".to_owned())?;
        if let Ok(message) = serde_json::from_str::<Value>(&line)
            && wanted(&message)
        {
            return Ok(message);
        }
    }
}

fn ask_claude() -> Result<Value, String> {
    // Safe mode keeps hooks and MCP servers out of a process that only answers a question,
    // and without persistence it leaves no session file behind.
    let (child, mut stdin, rx) = start(
        "claude",
        &[
            "-p",
            "--safe-mode",
            "--no-session-persistence",
            "--input-format",
            "stream-json",
            "--output-format",
            "stream-json",
            "--verbose",
        ],
    )?;
    let request = json!({"type": "control_request", "request_id": "hq", "request": {
        "subtype": "get_usage", "skip_behaviors": true
    }});
    let reply = send(&mut stdin, &request).and_then(|()| {
        // The end of input is what makes Claude Code answer and exit; no turn starts.
        drop(stdin);
        wait_for(&rx, CLAUDE_TIMEOUT, |m| m["type"] == "control_response")
    });
    stop(child);
    reply
}

fn ask_codex() -> Result<Value, String> {
    // The server only answers questions here; it should not be able to do more.
    let (child, mut stdin, rx) = start("codex", &["-s", "read-only", "-a", "never", "app-server"])?;
    let reply = |id: u64, timeout| wait_for(&rx, timeout, |m| m["id"].as_u64() == Some(id));
    let result = (|| {
        send(
            &mut stdin,
            &json!({"id": 1, "method": "initialize", "params": {
                "clientInfo": {"name": "hq", "version": env!("CARGO_PKG_VERSION")}
            }}),
        )?;
        reply(1, CODEX_START_TIMEOUT)?;
        send(&mut stdin, &json!({"method": "initialized"}))?;
        send(
            &mut stdin,
            &json!({"id": 2, "method": "account/rateLimits/read", "params": {}}),
        )?;
        let message = reply(2, CODEX_REPLY_TIMEOUT)?;
        match message.get("result") {
            Some(result) => Ok(result.clone()),
            None => Err(message["error"].to_string()),
        }
    })();
    stop(child);
    result
}

fn ask(agent: &str) -> Result<(Vec<Limit>, Option<String>), String> {
    match agent {
        "claude" => ask_claude().and_then(|reply| claude_limits(&reply)),
        "codex" => ask_codex().and_then(|result| codex_limits(&result)),
        other => Err(format!("unknown agent: {other}")),
    }
    // Every failure names the program it came from, here and nowhere else.
    .map_err(|e| format!("{agent}: {e}"))
}

/// Asks `agent`'s program for its limits unless it was asked recently, and records the answer.
///
/// # Errors
/// Fails when the state directory cannot be written; a failed question is recorded, not returned.
pub fn refresh(store: &Store, agent: &str, now: i64) -> std::io::Result<()> {
    let prev = store.read_account(agent);
    if prev.as_ref().is_some_and(|p| !p.due(now)) {
        return Ok(());
    }
    let mut account = prev.unwrap_or_else(|| Account {
        v: VERSION,
        agent: agent.into(),
        updated_at: None,
        attempted_at: now,
        failures: 0,
        error: None,
        plan: None,
        limits: Vec::new(),
    });
    // Claimed before asking, so a second caller meanwhile does not ask too.
    account.attempted_at = now;
    store.write_account(&account)?;
    match ask(agent) {
        Ok((limits, plan)) => {
            account.updated_at = Some(now);
            account.failures = 0;
            account.error = None;
            account.plan = plan;
            account.limits = limits;
        }
        Err(e) => {
            account.failures = account.failures.saturating_add(1);
            account.error = Some(e);
        }
    }
    store.write_account(&account)
}
