mod common;

use common::{now, run, temp_dir};
use hq::codex::{self, Hook, Rollout};
use hq::snapshot::{Certainty, Store};

const HOOK: &str = include_str!("fixtures/codex-post-model-request.json");
const ROLLOUT: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/tests/fixtures/codex-rollout.jsonl"
);

fn hook() -> String {
    HOOK.replace("ROLLOUT", ROLLOUT)
}

#[test]
fn completed_request_estimates_expiry_and_reads_windows_from_rollout() {
    let hook = Hook::parse(&hook()).unwrap();
    let rollout = Rollout::read(ROLLOUT);
    let snap = codex::snapshot(&hook, "t3", 1000, None, rollout.as_ref()).unwrap();
    assert_eq!(snap.agent, "codex");
    assert_eq!(snap.model.as_deref(), Some("gpt-5.6-sol"));
    let cache = snap.cache.unwrap();
    assert_eq!(cache.certainty, Certainty::Estimated);
    assert_eq!(cache.expires_at, Some(1000 + 300));
    assert_eq!(cache.at_stake_tokens, Some(84058));
    let windows: Vec<_> = snap
        .limits
        .iter()
        .map(|l| (l.window_minutes, l.used_pct, l.resets_at))
        .collect();
    assert_eq!(windows, [(Some(10080), 2.0, Some(1_794_387_269))]);
    let context = snap.context.unwrap();
    assert_eq!(context.tokens, Some(84058));
    assert_eq!(context.used_pct.map(f64::round), Some(33.0));
}

#[test]
fn failed_request_keeps_the_previous_cache_and_windows() {
    let ok = Hook::parse(&hook()).unwrap();
    let rollout = Rollout::read(ROLLOUT);
    let prev = codex::snapshot(&ok, "t3", 1000, None, rollout.as_ref()).unwrap();

    let failed = hook().replace("\"completed\"", "\"failed\"");
    let failed = failed.replace(
        &failed[failed.find("\"token_usage\"").unwrap()..],
        "\"token_usage\": null }",
    );
    let failed = Hook::parse(&failed).unwrap();
    let snap = codex::snapshot(&failed, "t3", 1200, Some(&prev), None).unwrap();
    assert_eq!(snap.updated_at, 1200);
    assert_eq!(snap.cache.unwrap().expires_at, Some(1300));
    assert_eq!(snap.limits.len(), 1);
}

#[test]
fn subagents_and_other_events_are_ignored() {
    let sub = hook().replace("\"turn_id\"", "\"agent_id\": \"a1\", \"turn_id\"");
    assert!(codex::snapshot(&Hook::parse(&sub).unwrap(), "t3", 1000, None, None).is_none());
    let pre = hook().replace("PostModelRequest", "PreModelRequest");
    assert!(codex::snapshot(&Hook::parse(&pre).unwrap(), "t3", 1000, None, None).is_none());
}

#[test]
fn ingest_records_snapshot_and_prints_nothing() {
    let state = temp_dir("codex");
    let before = now();
    let out = run(&state, Some("t3"), &["ingest", "codex"], &hook());
    assert_eq!(out, "");
    let snap = Store::new(state.join("herdr-queue")).read("t3").unwrap();
    assert_eq!(snap.agent, "codex");
    assert!(snap.cache.unwrap().expires_at.unwrap() >= before + 300);
    assert_eq!(snap.limits[0].window_minutes, Some(10080));

    let outside = temp_dir("codex-outside");
    run(&outside, None, &["ingest", "codex"], &hook());
    assert!(!outside.join("herdr-queue").exists());
}
