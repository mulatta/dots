const formatter = new Intl.RelativeTimeFormat(undefined, { style: "narrow" });

const STEPS: Array<[limit: number, unit: Intl.RelativeTimeFormatUnit, divisor: number]> = [
  [3600, "minute", 60],
  [86400, "hour", 3600],
  [604800, "day", 86400],
  [2629800, "week", 604800],
  [31557600, "month", 2629800],
  [Number.POSITIVE_INFINITY, "year", 31557600],
];

/// Matches the native meta line: "now" under a minute, then short
/// relative units.
export function relativeTime(timestampSeconds: number, nowMillis: number): string {
  const elapsed = Math.max(0, nowMillis / 1000 - timestampSeconds);
  if (elapsed < 60) return "now";
  for (const [limit, unit, divisor] of STEPS) {
    if (elapsed < limit) return formatter.format(-Math.floor(elapsed / divisor), unit);
  }
  return "";
}
