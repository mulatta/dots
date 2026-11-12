mod common;

use common::{now, run, temp_dir};
use hq::snapshot::{Cache, Certainty, Limit, Snapshot, Store, VERSION};

fn snapshot(terminal: &str, expires_at: i64) -> Snapshot {
    Snapshot {
        v: VERSION,
        agent: "claude".into(),
        terminal: terminal.into(),
        session_id: Some("s1".into()),
        cwd: Some("/home/u/src/dots".into()),
        model: Some("Opus 5.5".into()),
        updated_at: now(),
        cache: Some(Cache {
            expires_at: Some(expires_at),
            ttl: Some("1h".into()),
            certainty: Certainty::Exact,
            warm: Some(true),
            at_stake_tokens: Some(154_000),
            misses: None,
            miss_recache_tokens: None,
            last_miss_at: None,
            last_miss_cause: None,
        }),
        limits: vec![
            Limit {
                kind: "five_hour".into(),
                scope: None,
                window_minutes: Some(300),
                used_pct: 17.0,
                resets_at: Some(now() + 3600),
            },
            Limit {
                kind: "seven_day".into(),
                scope: None,
                window_minutes: Some(10080),
                used_pct: 31.0,
                resets_at: Some(now() - 1),
            },
        ],
        context: None,
        cost_usd: None,
    }
}

#[test]
fn lists_every_snapshot_by_terminal() {
    let state = temp_dir("list");
    let store = Store::new(state.join("herdr-queue"));
    store.write(&snapshot("t7", now() + 42 * 60 - 5)).unwrap();
    store.write(&snapshot("t2", now() - 10)).unwrap();

    let table = run(&state, None, &["list"], "");
    let rows: Vec<Vec<&str>> = table
        .lines()
        .map(|l| l.split_whitespace().collect())
        .collect();
    assert_eq!(
        rows[0],
        ["TERMINAL", "AGENT", "MODEL", "CACHE", "STAKE", "LIMITS"]
    );
    assert_eq!(
        rows[1],
        [
            "t2", "claude", "Opus", "5.5", "cold", "154k", "5h", "17%", "7d", "0%"
        ]
    );
    assert_eq!(rows[2][..6], ["t7", "claude", "Opus", "5.5", "42m", "154k"]);

    let json: serde_json::Value =
        serde_json::from_str(&run(&state, None, &["list", "--json"], "")).unwrap();
    assert_eq!(json.as_array().unwrap().len(), 2);
    assert_eq!(json[1]["terminal"], "t7");
    assert_eq!(json[1]["cache"]["certainty"], "exact");
}

#[test]
fn empty_state_lists_nothing() {
    let state = temp_dir("list-empty");
    assert_eq!(run(&state, None, &["list", "--json"], ""), "[]\n");
}
