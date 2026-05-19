import argparse
import os
import re
import subprocess
import time
from pathlib import Path

MEDIA_SUFFIXES = {".mp4", ".mkv", ".webm", ".mov", ".m4v"}
JOB_ID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I
)
PROJECTION_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:-[0-9]{2})?"
    r"\.(?:mp4|mkv|webm|mov|m4v|nfo)$",
    re.I,
)


def relative_target(source: Path, library: Path) -> str:
    return os.path.relpath(source, library)


def ensure_symlink(target: Path, source: Path, library: Path) -> None:
    wanted = relative_target(source, library)
    if target.is_symlink():
        if os.readlink(target) == wanted:
            return
        target.unlink()
    elif target.exists():
        raise RuntimeError(
            f"refusing to replace non-symlink projection target: {target}"
        )

    tmp = target.with_name(f".{target.name}.tmp-{os.getpid()}")
    try:
        if tmp.exists() or tmp.is_symlink():
            tmp.unlink()
        tmp.symlink_to(wanted)
        os.replace(tmp, target)
    finally:
        if tmp.exists() or tmp.is_symlink():
            tmp.unlink()


def media_files_for_job(job_dir: Path) -> list[Path]:
    return sorted(
        path
        for path in job_dir.iterdir()
        if path.is_file()
        and path.suffix.lower() in MEDIA_SUFFIXES
        and path.with_suffix(".nfo").is_file()
    )


def job_dirs(archive_db: Path) -> list[Path]:
    if not archive_db.is_dir():
        return []
    return sorted(
        path
        for path in archive_db.glob("*/*/*")
        if path.is_dir() and JOB_ID_RE.match(path.name)
    )


def reconcile(archive_db: Path, library: Path) -> None:
    library.mkdir(parents=True, exist_ok=True)
    desired: set[str] = set()
    jobs = job_dirs(archive_db)

    for job_dir in jobs:
        media_files = media_files_for_job(job_dir)
        for index, media in enumerate(media_files, start=1):
            stem = (
                job_dir.name if len(media_files) == 1 else f"{job_dir.name}-{index:02d}"
            )
            media_target = library / f"{stem}{media.suffix.lower()}"
            nfo_source = media.with_suffix(".nfo")
            nfo_target = library / f"{stem}.nfo"
            ensure_symlink(media_target, media, library)
            ensure_symlink(nfo_target, nfo_source, library)
            desired.add(media_target.name)
            desired.add(nfo_target.name)

    for entry in library.iterdir():
        if (
            entry.is_symlink()
            and PROJECTION_RE.match(entry.name)
            and entry.name not in desired
        ):
            entry.unlink()

    print(
        f"materialized {len(desired)} projection entries from {len(jobs)} archive jobs",
        flush=True,
    )


def wait_for_archive_db(archive_db: Path) -> None:
    while not archive_db.is_dir():
        time.sleep(5)


def watch(
    archive_db: Path, library: Path, inotifywait: str, debounce_seconds: float
) -> None:
    while True:
        wait_for_archive_db(archive_db)
        reconcile(archive_db, library)
        subprocess.run(
            [
                inotifywait,
                "-qq",
                "-r",
                "-e",
                "close_write,moved_to,create,delete,delete_self,move_self",
                str(archive_db),
            ],
            check=False,
        )
        time.sleep(debounce_seconds)


def parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Materialize filesystem projection for URL media archives"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_common_args(command_parser: argparse.ArgumentParser) -> None:
        command_parser.add_argument("--archive-db", type=Path, required=True)
        command_parser.add_argument("--library", type=Path, required=True)

    reconcile_parser = subparsers.add_parser("reconcile")
    add_common_args(reconcile_parser)

    watch_parser = subparsers.add_parser("watch")
    add_common_args(watch_parser)
    watch_parser.add_argument("--inotifywait", required=True)
    watch_parser.add_argument("--debounce-seconds", type=float, default=5.0)

    return parser


def main() -> None:
    args = parser().parse_args()
    if args.command == "reconcile":
        reconcile(args.archive_db, args.library)
    elif args.command == "watch":
        watch(args.archive_db, args.library, args.inotifywait, args.debounce_seconds)


if __name__ == "__main__":
    main()
