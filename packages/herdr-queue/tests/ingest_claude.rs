mod common;

use std::process::{Command, Stdio};

use common::{run, temp_dir};
use hq::claude::Status;
use hq::snapshot::{Certainty, Store};
use hq::{claude, events};

const FIXTURE: &str = include_str!("fixtures/claude-statusline.json");
const EXPIRES: i64 = 1_794_306_473;

#[test]
fn snapshot_carries_engine_cache_state() {
    let status = Status::parse(FIXTURE).unwrap();
    let snap = claude::snapshot(&status, "t9", 100);
    assert_eq!(snap.agent, "claude");
    assert_eq!(snap.terminal, "t9");
    assert_eq!(snap.updated_at, 100);
    let cache = snap.cache.unwrap();
    assert_eq!(cache.expires_at, Some(EXPIRES));
    assert_eq!(cache.ttl.as_deref(), Some("1h"));
    assert_eq!(cache.certainty, Certainty::Exact);
    assert_eq!(cache.at_stake_tokens, Some(46513));
    let windows: Vec<_> = snap
        .limits
        .iter()
        .map(|l| (l.window_minutes, l.used_pct))
        .collect();
    assert_eq!(windows, [(Some(300), 17.0), (Some(10080), 31.0)]);
}

#[test]
fn new_miss_is_logged_once() {
    let state = temp_dir("miss");
    run(&state, Some("t9"), &["ingest", "claude"], FIXTURE);
    let log = state.join("herdr-queue/events.jsonl");
    assert!(!log.exists());

    let missed = FIXTURE
        .replacen("\"misses\": 0", "\"misses\": 1", 1)
        .replacen(
            "\"miss_recache_tokens\": 0",
            "\"miss_recache_tokens\": 46000",
            1,
        )
        .replacen(
            "\"last_miss_at\": null",
            &format!("\"last_miss_at\": {}", EXPIRES + 900),
            1,
        )
        .replacen(
            "\"last_miss_cause\": null",
            r#""last_miss_cause": {"causes": ["ttl_expired", "tools_changed"], "tools_added": 2}"#,
            1,
        );
    run(&state, Some("t9"), &["ingest", "claude"], &missed);
    run(&state, Some("t9"), &["ingest", "claude"], &missed);

    let lines: Vec<events::Event> = std::fs::read_to_string(&log)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    assert_eq!(lines.len(), 1);
    assert_eq!(lines[0].event, "cache_miss");
    assert_eq!(lines[0].terminal, "t9");
    assert_eq!(lines[0].recache_tokens, Some(46000));
    assert_eq!(lines[0].cold_secs, Some(900));
    assert_eq!(lines[0].cause.as_deref(), Some("ttl_expired+tools_changed"));
}

#[test]
fn one_odd_cache_field_does_not_hide_the_expiry() {
    let odd = FIXTURE.replacen("\"last_miss_cause\": null", "\"last_miss_cause\": 7", 1);
    assert_ne!(odd, FIXTURE);
    let snap = claude::snapshot(&Status::parse(&odd).unwrap(), "t9", 100);
    assert_eq!(snap.cache.unwrap().expires_at, Some(EXPIRES));
}

#[test]
fn malformed_section_is_dropped_not_fatal() {
    let broken = FIXTURE.replacen("\"prompt_cache\": {", "\"prompt_cache\": 7, \"x\": {", 1);
    assert_ne!(broken, FIXTURE);
    let snap = claude::snapshot(&Status::parse(&broken).unwrap(), "t9", 100);
    assert!(snap.cache.is_none());
    assert_eq!(snap.limits.len(), 2);
}

#[test]
fn ingest_records_only_inside_herdr_and_draws_nothing() {
    let state = temp_dir("write");
    assert_eq!(run(&state, Some("t9"), &["ingest", "claude"], FIXTURE), "");
    let store = Store::new(state.join("herdr-queue"));
    assert_eq!(
        store.read("t9").unwrap().session_id.as_deref(),
        Some("00000000-0000-4000-8000-0000000c1a0d")
    );

    let listed = run(&state, None, &["list", "--json"], "");
    let listed: serde_json::Value = serde_json::from_str(&listed).unwrap();
    assert_eq!(listed[0]["terminal"], "t9");
    assert_eq!(listed[0]["cache"]["expiresAt"], EXPIRES);

    let outside = temp_dir("outside");
    run(&outside, None, &["ingest", "claude"], FIXTURE);
    assert!(!outside.join("herdr-queue").exists());
}

#[test]
fn wrapped_command_gets_the_same_input_and_draws_the_line() {
    let state = temp_dir("wrap");
    let out = run(
        &state,
        Some("t9"),
        &["ingest", "claude", "--", "cat"],
        FIXTURE,
    );
    assert_eq!(out, FIXTURE);
    assert!(Store::new(state.join("herdr-queue")).read("t9").is_some());

    let args = ["ingest", "claude", "--", "sh", "-c", "wc -c | tr -d ' \n'"];
    assert_eq!(run(&state, None, &args, FIXTURE), FIXTURE.len().to_string());
}

#[test]
fn wrapped_command_still_draws_when_the_input_cannot_be_recorded() {
    let state = temp_dir("wrap-bad");
    let out = Command::new(env!("CARGO_BIN_EXE_hq"))
        .args(["ingest", "claude", "--", "echo", "drawn"])
        .env("XDG_STATE_HOME", &state)
        .env("HC_TERMINAL_ID", "t9")
        .stdin(Stdio::null())
        .output()
        .unwrap();
    assert_eq!(String::from_utf8(out.stdout).unwrap(), "drawn\n");
    assert!(
        !out.status.success(),
        "the unreadable input is still reported"
    );
}
