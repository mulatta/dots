#![allow(dead_code)]

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("hq-test-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Runs the built `hq` against a private state directory and returns its stdout.
pub fn run(state: &Path, terminal: Option<&str>, args: &[&str], stdin: &str) -> String {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_hq"));
    cmd.args(args)
        .env("XDG_STATE_HOME", state)
        .env_remove("HC_TERMINAL_ID")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped());
    if let Some(t) = terminal {
        cmd.env("HC_TERMINAL_ID", t);
    }
    let mut child = cmd.spawn().unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(stdin.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(out.status.success());
    String::from_utf8(out.stdout).unwrap()
}

/// Like `run`, without stdin and with extra environment, for commands that start other programs.
pub fn run_env(state: &Path, env: &[(&str, &str)], args: &[&str]) -> String {
    let out = Command::new(env!("CARGO_BIN_EXE_hq"))
        .args(args)
        .env("XDG_STATE_HOME", state)
        .env_remove("HC_TERMINAL_ID")
        .envs(env.iter().copied())
        .stdin(Stdio::null())
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap()
}

pub fn now() -> i64 {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    i64::try_from(secs).unwrap()
}
