mod common;

use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use common::{now, run_env, temp_dir};
use hmeter::account::{self, Account};
use hmeter::snapshot::{Limit, Snapshot, Store, VERSION};
use serde_json::Value;

const CLAUDE_USAGE: &str = include_str!("fixtures/claude-get-usage.json");
const CODEX_LIMITS: &str = include_str!("fixtures/codex-rate-limits.json");

/// Kind, scope, window minutes, used percent, reset.
type Window<'a> = (&'a str, Option<&'a str>, Option<u32>, f64, Option<i64>);

fn windows(limits: &[Limit]) -> Vec<Window<'_>> {
    limits
        .iter()
        .map(|l| {
            (
                l.kind.as_str(),
                l.scope.as_deref(),
                l.window_minutes,
                l.used_pct,
                l.resets_at,
            )
        })
        .collect()
}

#[test]
fn claude_reply_gives_session_week_and_model_windows() {
    let reply: Value = serde_json::from_str(CLAUDE_USAGE).unwrap();
    let (limits, plan) = account::claude_limits(&reply).unwrap();
    assert_eq!(
        windows(&limits),
        [
            ("five_hour", None, Some(300), 30.0, Some(1_794_476_400)),
            ("seven_day", None, Some(10080), 11.0, Some(1_794_996_000)),
            (
                "seven_day",
                Some("Fable"),
                Some(10080),
                14.0,
                Some(1_794_996_000)
            ),
        ]
    );
    assert_eq!(plan.as_deref(), Some("max"));
}

#[test]
fn claude_reset_time_with_an_offset_is_converted() {
    let reply = serde_json::json!({"response": {"response": {"rate_limits": {"limits": [
        {"kind": "session", "percent": 5, "resets_at": "2026-11-12T18:40:00+09:00"},
        {"kind": "weekly_all", "percent": 6, "resets_at": "2026-11-18T10:00:00Z"},
        {"kind": "weekly_scoped", "percent": 7, "resets_at": null},
    ]}}}});
    let (limits, _) = account::claude_limits(&reply).unwrap();
    let resets: Vec<_> = limits.iter().map(|l| l.resets_at).collect();
    assert_eq!(resets, [Some(1_794_476_400), Some(1_794_996_000), None]);
}

#[test]
fn claude_reply_without_windows_is_an_error() {
    let reply = serde_json::json!({"response": {"subtype": "error", "error": "not logged in"}});
    let error = account::claude_limits(&reply).unwrap_err();
    assert!(error.contains("not logged in"));
}

#[test]
fn codex_response_gives_its_windows_and_plan() {
    let result: Value = serde_json::from_str(CODEX_LIMITS).unwrap();
    let (limits, plan) = account::codex_limits(&result).unwrap();
    assert_eq!(
        windows(&limits),
        [("primary", None, Some(10080), 2.0, Some(1_794_999_224))]
    );
    assert_eq!(plan.as_deref(), Some("prolite"));
}

/// `cat` with shell builtins only: the stand-ins run with nothing else on PATH.
const PRINT: &str = "while IFS= read -r line; do echo \"$line\"; done";

fn program(dir: &Path, name: &str, script: &str) {
    let path = dir.join(name);
    std::fs::write(&path, format!("#!/bin/sh\n{script}")).unwrap();
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

/// Stand-ins that answer the way the real programs did when the fixtures were captured.
fn agents(dir: &Path) {
    let claude: Value = serde_json::from_str(CLAUDE_USAGE).unwrap();
    program(
        dir,
        "claude",
        &format!("read -r _\n{PRINT} <<'EOF'\n{claude}\nEOF\n"),
    );
    program(
        dir,
        "codex",
        &format!(
            "read -r _\necho '{{\"id\":1,\"result\":{{}}}}'\nread -r _\nread -r _\n\
             echo '{{\"method\":\"account/updated\",\"params\":{{}}}}'\n\
             {PRINT} <<'EOF'\n{{\"id\":2,\"result\":{}}}\nEOF\n",
            serde_json::from_str::<Value>(CODEX_LIMITS).unwrap()
        ),
    );
}

fn usage(state: &Path, bin: &Path, args: &[&str]) -> Vec<Value> {
    let out = run_env(state, &[("PATH", bin.to_str().unwrap())], args);
    serde_json::from_str(&out).unwrap()
}

#[test]
fn refresh_asks_each_agent_and_keeps_account_ids_out() {
    let state = temp_dir("usage-refresh");
    let bin = temp_dir("usage-refresh-bin");
    agents(&bin);

    let got = usage(&state, &bin, &["usage", "--refresh", "--json"]);
    let by_agent = |name: &str| got.iter().find(|a| a["agent"] == name).unwrap().clone();

    let claude = by_agent("claude");
    assert_eq!(claude["source"], "account");
    assert_eq!(claude["limits"][2]["scope"], "Fable");
    assert_eq!(claude["limits"][2]["usedPct"], 14.0);
    assert_eq!(claude["plan"], "max");

    let codex = by_agent("codex");
    assert_eq!(codex["source"], "account");
    assert_eq!(codex["plan"], "prolite");
    assert_eq!(codex["limits"][0]["windowMinutes"], 10080);

    let stored = std::fs::read_to_string(state.join("herdr-meter/accounts/codex.json")).unwrap();
    assert!(!stored.contains("00000000-0000-4000-8000-000000000000"));
}

#[test]
fn refresh_leaves_a_recently_asked_agent_alone() {
    let state = temp_dir("usage-throttle");
    let bin = temp_dir("usage-throttle-bin");
    agents(&bin);
    usage(&state, &bin, &["usage", "--refresh", "--json"]);

    // A program that would now fail proves it was not run again.
    program(&bin, "claude", "exit 1\n");
    let got = usage(&state, &bin, &["usage", "--refresh", "--json"]);
    let claude = got.iter().find(|a| a["agent"] == "claude").unwrap();
    assert_eq!(claude["source"], "account");
    assert_eq!(claude["error"], Value::Null);
}

fn terminal_snapshot(agent: &str, updated_at: i64) -> Snapshot {
    Snapshot {
        v: VERSION,
        agent: agent.into(),
        terminal: "t1".into(),
        session_id: None,
        cwd: None,
        model: None,
        updated_at,
        cache: None,
        limits: vec![Limit {
            kind: "five_hour".into(),
            scope: None,
            window_minutes: Some(300),
            used_pct: 41.0,
            resets_at: Some(updated_at + 3600),
        }],
        context: None,
        cost_usd: None,
    }
}

#[test]
fn failed_refresh_falls_back_to_what_a_terminal_reported() {
    let state = temp_dir("usage-fallback");
    let bin = temp_dir("usage-fallback-bin");
    program(
        &bin,
        "claude",
        "echo '{\"type\":\"control_response\",\"response\":{\"subtype\":\"error\",\"error\":\"not logged in\"}}'\n",
    );
    let store = Store::new(state.join("herdr-meter"));
    store
        .write(&terminal_snapshot("claude", now() - 30))
        .unwrap();

    let got = usage(&state, &bin, &["usage", "--refresh", "--json"]);
    let claude = got.iter().find(|a| a["agent"] == "claude").unwrap();
    assert_eq!(claude["source"], "terminal");
    assert_eq!(claude["limits"][0]["usedPct"], 41.0);
    assert!(claude["error"].as_str().unwrap().contains("not logged in"));
}

#[test]
fn an_old_answer_gives_way_to_a_newer_terminal_report() {
    let state = temp_dir("usage-stale");
    let store = Store::new(state.join("herdr-meter"));
    let t = now();
    store
        .write_account(&Account {
            v: VERSION,
            agent: "claude".into(),
            updated_at: Some(t - 7200),
            attempted_at: t - 7200,
            failures: 0,
            error: None,
            plan: None,
            limits: terminal_snapshot("claude", t - 7200).limits,
        })
        .unwrap();
    let mut newer = terminal_snapshot("claude", t - 60);
    newer.limits[0].used_pct = 55.0;
    store.write(&newer).unwrap();

    let empty = temp_dir("usage-stale-bin");
    let got = usage(&state, &empty, &["usage", "--json"]);
    let claude = got.iter().find(|a| a["agent"] == "claude").unwrap();
    assert_eq!(claude["source"], "terminal");
    assert_eq!(claude["limits"][0]["usedPct"], 55.0);
}
