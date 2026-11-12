use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::process::{Command, ExitCode, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

use hmeter::claude::{self, Status};
use hmeter::codex::{self, Hook, Rollout};
use hmeter::pi::{self, Turn};
use hmeter::snapshot::{Snapshot, Store, valid_terminal};
use hmeter::{account, events, list, usage};

const USAGE: &str = "usage:
  hmeter ingest claude [-- command...]
                     record Claude Code's status line JSON from stdin, then run command on it
  hmeter ingest codex    record Codex's PostModelRequest hook JSON from stdin
  hmeter ingest pi       record the pi extension's turn JSON from stdin, print the cache expiry
  hmeter list [--json]   show every agent session's cache and usage state
  hmeter usage [--refresh] [--json]
                     show each account's usage against its rate limits; --refresh asks
                     claude and codex first";

fn now() -> i64 {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    i64::try_from(secs).unwrap_or(i64::MAX)
}

fn stdin() -> Result<String, String> {
    let mut input = String::new();
    std::io::stdin()
        .read_to_string(&mut input)
        .map_err(|e| e.to_string())?;
    Ok(input)
}

/// The store and this terminal's id; outside herdr no terminal owns a snapshot.
fn home() -> Option<(Store, String)> {
    let terminal = std::env::var("HC_TERMINAL_ID")
        .ok()
        .filter(|t| valid_terminal(t))?;
    Some((Store::new(Store::default_dir()?), terminal))
}

fn record(store: &Store, prev: Option<&Snapshot>, next: &Snapshot) -> Result<(), String> {
    store.write(next).map_err(|e| format!("snapshot: {e}"))?;
    if let Some(event) = prev.and_then(|prev| events::cache_miss(prev, next)) {
        events::append(&store.events_path(), &event).map_err(|e| format!("event log: {e}"))?;
    }
    Ok(())
}

/// Hands the status line input to the command `hmeter` was wrapped around, which draws the line.
fn pass_through(command: &[&str], input: &str) -> Result<(), String> {
    let mut child = Command::new(command[0])
        .args(&command[1..])
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| format!("{}: {e}", command[0]))?;
    if let Some(mut stdin) = child.stdin.take() {
        // A command that exits without reading its input has still done its job.
        let _ = stdin.write_all(input.as_bytes());
    }
    let status = child.wait().map_err(|e| format!("{}: {e}", command[0]))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{}: {status}", command[0]))
    }
}

fn record_claude(input: &str) -> Result<(), String> {
    let status = Status::parse(input).map_err(|e| format!("status line input: {e}"))?;
    if let Some((store, terminal)) = home() {
        let prev = store.read(&terminal);
        record(
            &store,
            prev.as_ref(),
            &claude::snapshot(&status, &terminal, now()),
        )?;
    }
    Ok(())
}

fn ingest_claude(rest: &[&str]) -> Result<(), String> {
    let command = match rest {
        [] => None,
        ["--", command @ ..] if !command.is_empty() => Some(command),
        _ => return Err("expected `hmeter ingest claude [-- command...]`".into()),
    };
    let input = stdin()?;
    let recorded = record_claude(&input);
    // The user looks at the status line, not the snapshot, so it is drawn whatever happened above.
    if let Some(command) = command {
        pass_through(command, &input)?;
    }
    recorded
}

/// Whether the terminal's program is Codex; `None` when hc cannot be asked.
fn terminal_runs_codex(terminal: &str) -> Option<bool> {
    let output = Command::new("hc")
        .args(["get", terminal, "--json"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    Some(
        output.status.success()
            && codex::terminal_runs_codex(&String::from_utf8_lossy(&output.stdout)),
    )
}

fn ingest_codex() -> Result<(), String> {
    let hook = Hook::parse(&stdin()?).map_err(|e| format!("hook input: {e}"))?;
    let Some((store, terminal)) = home() else {
        return Ok(());
    };
    // Under Codex's shared daemon the hook carries the daemon's terminal, not the session's.
    if terminal_runs_codex(&terminal) == Some(false) {
        return Ok(());
    }
    let prev = store.read(&terminal);
    let rollout = hook.transcript_path.as_deref().and_then(Rollout::read);
    match codex::snapshot(&hook, &terminal, now(), prev.as_ref(), rollout.as_ref()) {
        Some(next) => record(&store, prev.as_ref(), &next),
        None => Ok(()),
    }
}

fn ingest_pi() -> Result<(), String> {
    let turn = Turn::parse(&stdin()?).map_err(|e| format!("turn input: {e}"))?;
    let home = home();
    let prev = home
        .as_ref()
        .and_then(|(store, terminal)| store.read(terminal));
    let terminal = home.as_ref().map_or("", |(_, terminal)| terminal);
    let next = pi::snapshot(&turn, terminal, now(), prev.as_ref());
    // The extension shows this in pi's footer; an empty line means no known expiry.
    let expiry = next.cache.as_ref().and_then(|c| c.expires_at);
    println!("{}", expiry.map(|at| at.to_string()).unwrap_or_default());
    match home {
        Some((store, _)) => record(&store, prev.as_ref(), &next),
        None => Ok(()),
    }
}

fn list_sessions(json: bool) -> Result<(), String> {
    let snaps = Store::default_dir()
        .map(|d| Store::new(d).all())
        .unwrap_or_default();
    if json {
        println!(
            "{}",
            serde_json::to_string(&snaps).map_err(|e| e.to_string())?
        );
    } else {
        print!("{}", list::table(&snaps, now()));
    }
    Ok(())
}

fn on_path(program: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|path| {
        std::env::split_paths(&path).any(|dir| {
            std::fs::metadata(dir.join(program))
                .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        })
    })
}

fn show_usage(args: &[&str]) -> Result<(), String> {
    let (mut refresh, mut json) = (false, false);
    for arg in args {
        match *arg {
            "--refresh" => refresh = true,
            "--json" => json = true,
            other => return Err(format!("unknown option: {other}")),
        }
    }
    let store = Store::new(Store::default_dir().ok_or("no home directory for state")?);
    if refresh {
        // Each program takes seconds to start, so they are asked side by side.
        std::thread::scope(|scope| {
            for agent in account::AGENTS {
                if on_path(agent) {
                    let store = &store;
                    scope.spawn(move || {
                        if let Err(e) = account::refresh(store, agent, now()) {
                            eprintln!("hmeter: {agent}: {e}");
                        }
                    });
                }
            }
        });
    }
    let all = usage::resolve(&store, now());
    if json {
        println!(
            "{}",
            serde_json::to_string(&all).map_err(|e| e.to_string())?
        );
    } else {
        print!("{}", usage::table(&all, now()));
    }
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let result = match args.as_slice() {
        ["ingest", "claude", rest @ ..] => ingest_claude(rest),
        ["ingest", "codex"] => ingest_codex(),
        ["ingest", "pi"] => ingest_pi(),
        ["list"] => list_sessions(false),
        ["list", "--json"] => list_sessions(true),
        ["usage", rest @ ..] => show_usage(rest),
        _ => {
            eprintln!("{USAGE}");
            return ExitCode::from(2);
        }
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("hmeter: {e}");
            ExitCode::FAILURE
        }
    }
}
