#!/usr/bin/env python3
"""Calendar notification daemon - checks for upcoming events and sends alerts."""
import dbm
import logging
import os
import platform
import subprocess
import sys
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from typing import Any

import pytz
from dateutil.rrule import rrulestr
from icalendar import Calendar, Event
from icalendar.prop import vDDDTypes, vDuration

# XDG Base Directory paths
XDG_STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
XDG_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))

STATE_DIR = XDG_STATE_HOME / "calendar-notify"
STATE_FILE = STATE_DIR / "notified-events.db"
CALENDAR_DIR = XDG_DATA_HOME / "calendars"

# Type aliases
type DateOrDateTime = date | datetime
type DurationLike = timedelta | vDuration
type TriggerType = datetime | timedelta | vDDDTypes
type RRuleType = rrulestr | None

logger = logging.getLogger(__name__)


class EventOccurrenceProcessor:
    """Handles event occurrence calculations."""

    def __init__(self, event: Event, ics_path: Path) -> None:
        self.event = event
        self.ics_path = ics_path
        self.dtstart = event.get("DTSTART")
        self.dtstart_dt: DateOrDateTime | None = None
        self.duration: timedelta | None = None

    def get_occurrences(
        self, start_date: datetime, end_date: datetime
    ) -> list[tuple[datetime, timedelta]]:
        """Get all occurrences of an event within a date range."""
        if not self.dtstart:
            return []

        self.dtstart_dt = (
            self.dtstart.dt if hasattr(self.dtstart, "dt") else self.dtstart
        )
        self.duration = self._calculate_duration()

        rrule = self.event.get("RRULE")
        if rrule:
            return self._process_recurrence(rrule, start_date, end_date)

        occurrences: list[tuple[datetime, timedelta]] = []
        self._add_if_in_range(occurrences, self.dtstart_dt, start_date, end_date)
        return occurrences

    def _calculate_duration(self) -> timedelta:
        """Calculate event duration from DTEND or DURATION properties."""
        dtend = self.event.get("DTEND")
        duration = self.event.get("DURATION")

        if dtend:
            dtend_dt: DateOrDateTime = dtend.dt if hasattr(dtend, "dt") else dtend
            if isinstance(self.dtstart_dt, datetime) and isinstance(dtend_dt, datetime):
                return dtend_dt - self.dtstart_dt
            return timedelta(days=1)
        if duration:
            return parse_duration(duration)
        return timedelta(hours=1)

    def _add_if_in_range(
        self,
        occurrences: list[tuple[datetime, timedelta]],
        dt: DateOrDateTime,
        start_date: datetime,
        end_date: datetime,
    ) -> None:
        """Add occurrence to list if it's within the date range."""
        if isinstance(dt, datetime):
            if start_date <= dt <= end_date:
                occurrences.append((dt, self.duration))
        else:
            dt_as_datetime = normalize_datetime(dt)
            if start_date <= dt_as_datetime <= end_date:
                occurrences.append((dt_as_datetime, self.duration))

    def _process_recurrence(
        self, rrule: Any, start_date: datetime, end_date: datetime
    ) -> list[tuple[datetime, timedelta]]:
        """Process RRULE and return occurrences."""
        occurrences: list[tuple[datetime, timedelta]] = []
        try:
            if hasattr(rrule, "to_ical"):
                rrule_str = rrule.to_ical().decode("utf-8")
            else:
                rrule_str = str(rrule)
            rule = parse_recurrence_rule(rrule_str, self.dtstart_dt)
            if rule:
                occurrences.extend(
                    (occurrence, self.duration)
                    for occurrence in rule.between(start_date, end_date, inc=True)
                )
        except (ValueError, TypeError) as e:
            summary = str(self.event.get("SUMMARY", "Unknown"))
            logger.warning(f"Error parsing RRULE for '{summary}': {e}")
            self._add_if_in_range(occurrences, self.dtstart_dt, start_date, end_date)
        return occurrences


def parse_duration(duration: DurationLike) -> timedelta:
    """Parse duration from icalendar vDuration to timedelta."""
    if hasattr(duration, "td"):
        return duration.td
    if isinstance(duration, timedelta):
        return duration
    return timedelta(minutes=15)


def parse_trigger_time(trigger: TriggerType, event_start: datetime) -> datetime | None:
    """Parse alarm trigger to get alarm time."""
    alarm_time: datetime | None = None

    if hasattr(trigger, "dt"):
        if isinstance(trigger.dt, datetime):
            alarm_time = trigger.dt
            if alarm_time.tzinfo is None:
                alarm_time = pytz.UTC.localize(alarm_time)
        elif isinstance(trigger.dt, timedelta):
            alarm_time = event_start + trigger.dt
    elif hasattr(trigger, "td"):
        alarm_time = event_start + trigger.td
    elif isinstance(trigger, timedelta):
        alarm_time = event_start + trigger
    else:
        try:
            if hasattr(trigger, "td"):
                alarm_time = event_start + trigger.td
            elif isinstance(trigger, timedelta):
                alarm_time = event_start + trigger
        except TypeError:
            alarm_time = event_start - timedelta(minutes=15)

    return alarm_time


def get_alarm_times(event: Event, event_start: datetime) -> list[datetime]:
    """Extract alarm times from a VEVENT component."""
    alarm_times: list[datetime] = []

    for component in event.walk():
        if component.name == "VALARM":
            trigger = component.get("TRIGGER")
            if trigger is not None:
                alarm_time = parse_trigger_time(trigger, event_start)
                if alarm_time is not None and isinstance(alarm_time, datetime):
                    alarm_times.append(alarm_time)

    return alarm_times


def parse_recurrence_rule(rrule_str: str, dtstart: DateOrDateTime) -> RRuleType:
    """Parse RRULE string safely."""
    try:
        rrule_str = rrule_str.removeprefix("RRULE:")
        return rrulestr(rrule_str, dtstart=dtstart)
    except (ValueError, TypeError) as e:
        print(f"Error parsing RRULE: {e}", file=sys.stderr)
        return None


def normalize_datetime(dt: DateOrDateTime) -> datetime:
    """Ensure datetime has timezone information."""
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            return pytz.UTC.localize(dt)
        return dt
    event_start = datetime.combine(dt, datetime.min.time())
    return pytz.UTC.localize(event_start)


def should_notify(alarm_time: datetime) -> bool:
    """Check if we should notify for this alarm time."""
    now = datetime.now(UTC)
    return alarm_time <= now + timedelta(minutes=5)


def was_notified(db: Any, event_id: str) -> bool:
    """Check if an event was already notified."""
    return event_id.encode("utf-8") in db


def save_notified_event(db: Any, event_id: str) -> None:
    """Mark event as notified in the database."""
    timestamp = str(int(datetime.now(UTC).timestamp()))
    db[event_id.encode("utf-8")] = timestamp.encode("utf-8")


def send_notification(title: str, time_str: str, body: str = "") -> None:
    """Send desktop notification."""
    logger.info(f"Sending notification: '{title}' at {time_str}")

    if platform.system() == "Darwin":
        # macOS notification using osascript
        notification_title = f"Event at {time_str}"
        notification_text = title + ("\n" + body if body else "")
        notification_title = notification_title.replace('"', '\\"')
        notification_text = notification_text.replace('"', '\\"')

        script = f'display alert "{notification_title}" message "{notification_text}" as critical'
        result = subprocess.run(
            ["osascript", "-e", script],
            check=False,
            capture_output=True,
            text=True,
        )
    else:
        # Linux notification using notify-send
        result = subprocess.run(
            [
                "notify-send",
                "--urgency=critical",
                "--expire-time=0",
                "--app-name=Calendar",
                "--icon=office-calendar",
                f"Event at {time_str}",
                title + ("\n" + body if body else ""),
            ],
            check=False,
        )

    if result.returncode == 0:
        logger.info("Notification sent successfully")
    else:
        logger.error(f"Failed to send notification: {result.returncode}")


def format_notification_time(event_start: datetime, duration: timedelta) -> str:
    """Format the time string for notification."""
    now = datetime.now(UTC)
    time_str = event_start.strftime("%H:%M")
    date_str = event_start.strftime("%Y-%m-%d")

    if event_start.date() != now.date():
        time_str = f"{date_str} {time_str}"

    if duration > timedelta(days=1):
        time_str += f" ({duration.days} day event)"

    return time_str


def process_event_alarms(
    db: Any,
    event: Event,
    occurrence_start: DateOrDateTime,
    duration: timedelta,
) -> None:
    """Process alarms for a single event occurrence."""
    uid = str(event.get("UID", ""))
    summary = str(event.get("SUMMARY", "Untitled Event"))
    location = str(event.get("LOCATION", ""))

    event_start = normalize_datetime(occurrence_start)
    alarm_times = get_alarm_times(event, event_start)

    if not alarm_times:
        alarm_times = [event_start - timedelta(minutes=15)]

    for i, alarm_time in enumerate(alarm_times):
        occurrence_id = event_start.isoformat()
        event_id = f"{uid}|{occurrence_id}|alarm{i}"

        logger.debug(f"Checking '{summary}' - alarm: {alarm_time}, event: {event_start}")

        if not was_notified(db, event_id) and should_notify(alarm_time):
            logger.info(f"Alarm triggered for '{summary}'")
            time_str = format_notification_time(event_start, duration)
            send_notification(summary, time_str, location)
            save_notified_event(db, event_id)


def process_calendar_file(db: Any, ics_path: Path) -> None:
    """Process a single calendar file."""
    now = datetime.now(UTC)
    start_date = now - timedelta(hours=1)
    end_date = now + timedelta(days=7)

    try:
        with ics_path.open("rb") as f:
            cal = Calendar.from_ical(f.read())

        for component in cal.walk():
            if component.name == "VEVENT":
                processor = EventOccurrenceProcessor(component, ics_path)
                occurrences = processor.get_occurrences(start_date, end_date)

                for occurrence_start, duration in occurrences:
                    process_event_alarms(db, component, occurrence_start, duration)

    except (ValueError, TypeError, OSError) as e:
        print(f"Error processing {ics_path}: {e}", file=sys.stderr)


def main() -> None:
    """Main function to check for calendar events with alarms."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
    )

    logger.info("Starting calendar notification check")

    with dbm.open(str(STATE_FILE), "c") as db:
        for ics_path in CALENDAR_DIR.rglob("*.ics"):
            process_calendar_file(db, ics_path)

    logger.info("Calendar notification check completed")


if __name__ == "__main__":
    main()
