//! Compact text for the numbers every view shows.

#[must_use]
pub fn tokens(n: u64) -> String {
    #[allow(clippy::cast_precision_loss)]
    let f = n as f64;
    match n {
        0..1_000 => n.to_string(),
        1_000..10_000 => format!("{:.1}k", f / 1e3),
        10_000..1_000_000 => format!("{:.0}k", f / 1e3),
        _ => format!("{:.1}M", f / 1e6),
    }
}

/// Rounded up, so a live cache never reads `0m`.
#[must_use]
pub fn span(secs: i64) -> String {
    let m = (secs.max(0) + 59) / 60;
    match m {
        0..60 => format!("{m}m"),
        60..1440 if m % 60 == 0 => format!("{}h", m / 60),
        60..1440 => format!("{}h{}m", m / 60, m % 60),
        _ if m % 1440 < 60 => format!("{}d", m / 1440),
        _ => format!("{}d{}h", m / 1440, m % 1440 / 60),
    }
}

/// Agents name their windows differently, so the length is what gets shown.
#[must_use]
pub fn window_label(kind: &str, minutes: Option<u32>) -> String {
    minutes.map_or_else(|| kind.replace('_', " "), |m| span(i64::from(m) * 60))
}
