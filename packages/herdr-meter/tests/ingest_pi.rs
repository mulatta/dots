mod common;

use common::{now, run, temp_dir};
use hmeter::pi::{self, Turn};
use hmeter::snapshot::{Certainty, Store};

const TURN: &str = include_str!("fixtures/pi-turn.json");

fn cached() -> String {
    let mut turn: serde_json::Value = serde_json::from_str(TURN).unwrap();
    turn["usage"]["cacheRead"] = 46592.into();
    turn.to_string()
}

#[test]
fn turn_without_cache_activity_has_no_expiry() {
    let turn = Turn::parse(TURN).unwrap();
    let snap = pi::snapshot(&turn, "t4", 1000, None);
    assert_eq!(snap.agent, "pi");
    assert_eq!(snap.model.as_deref(), Some("gpt-6.1-sol"));
    assert!(snap.cache.is_none());
    assert_eq!(snap.context.unwrap().tokens, Some(473));
}

#[test]
fn unknown_lifetime_falls_back_to_the_shortest() {
    let turn = Turn::parse(&cached()).unwrap();
    let cache = pi::snapshot(&turn, "t4", 1000, None).cache.unwrap();
    assert_eq!(cache.expires_at, Some(1300));
    assert_eq!(cache.ttl.as_deref(), Some("5m"));
    assert_eq!(cache.certainty, Certainty::Estimated);
    assert_eq!(cache.at_stake_tokens, Some(468 + 46592));
}

#[test]
fn model_lifetime_and_one_hour_writes_set_the_expiry() {
    let mut declared: serde_json::Value = serde_json::from_str(&cached()).unwrap();
    declared["cacheTtlSecs"] = 1800.into();
    let cache = pi::snapshot(
        &Turn::parse(&declared.to_string()).unwrap(),
        "t4",
        1000,
        None,
    )
    .cache
    .unwrap();
    assert_eq!(cache.expires_at, Some(2800));
    assert_eq!(cache.ttl.as_deref(), Some("30m"));

    let mut hour: serde_json::Value = serde_json::from_str(TURN).unwrap();
    hour["usage"]["cacheWrite"] = 900.into();
    hour["usage"]["cacheWrite1h"] = 900.into();
    let cache = pi::snapshot(&Turn::parse(&hour.to_string()).unwrap(), "t4", 1000, None)
        .cache
        .unwrap();
    assert_eq!(cache.expires_at, Some(4600));
    assert_eq!(cache.ttl.as_deref(), Some("1h"));
}

#[test]
fn quiet_turn_keeps_the_previous_cache() {
    let prev = pi::snapshot(&Turn::parse(&cached()).unwrap(), "t4", 1000, None);
    let snap = pi::snapshot(&Turn::parse(TURN).unwrap(), "t4", 1100, Some(&prev));
    assert_eq!(snap.cache.unwrap().expires_at, Some(1300));
}

#[test]
fn ingest_prints_expiry_for_the_footer_and_records_inside_herdr() {
    let state = temp_dir("pi");
    let before = now();
    let out = run(&state, Some("t4"), &["ingest", "pi"], &cached());
    let printed: i64 = out.trim().parse().unwrap();
    assert!(printed >= before + 300);
    let snap = Store::new(state.join("herdr-meter")).read("t4").unwrap();
    assert_eq!(snap.cache.unwrap().expires_at, Some(printed));

    let outside = temp_dir("pi-outside");
    let out = run(&outside, None, &["ingest", "pi"], &cached());
    assert!(out.trim().parse::<i64>().is_ok());
    assert!(!outside.join("herdr-meter").exists());

    assert_eq!(run(&outside, None, &["ingest", "pi"], TURN), "\n");
}
