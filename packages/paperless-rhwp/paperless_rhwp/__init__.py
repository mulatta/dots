"""Paperless-ngx parser that renders HWP/HWPX through rhwp and indexes the PDF text layer."""

from __future__ import annotations

import logging
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Self

if TYPE_CHECKING:
    import datetime
    from types import TracebackType

    from paperless.parsers import MetadataEntry, ParserContext

# Substituted with store paths at build time.
RHWP = "@rhwp@"
PDFTOTEXT = "@pdftotext@"
FONT_DIR = "@fontDir@"

MIME_TYPES = {
    "application/x-hwp": ".hwp",
    "application/x-hwp+zip": ".hwpx",
}

logger = logging.getLogger("paperless.parsing.rhwp")


def render(document: Path, out_dir: Path) -> tuple[Path, str]:
    """Render a document to PDF and return the PDF with its extracted text."""
    pdf = out_dir / "rhwp.pdf"
    subprocess.run(
        [RHWP, "export-pdf", str(document), "-o", str(pdf), "--font-path", FONT_DIR],
        check=True,
        capture_output=True,
    )
    # rhwp's markdown export repeats table cells.
    text = subprocess.run(
        [PDFTOTEXT, str(pdf), "-"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return pdf, text.strip()


class RhwpDocumentParser:
    name = "rhwp HWP Parser"
    version = "0.1.0"
    author = "mulatta"
    url = "https://github.com/mulatta/rhwp.nix"

    @classmethod
    def supported_mime_types(cls) -> dict[str, str]:
        return MIME_TYPES

    @classmethod
    def score(
        cls, mime_type: str, filename: str, path: Path | None = None
    ) -> int | None:
        return 10 if mime_type in MIME_TYPES else None

    @property
    def can_produce_archive(self) -> bool:
        return False

    @property
    def requires_pdf_rendition(self) -> bool:
        return True

    def __init__(self, logging_group: object = None) -> None:
        from django.conf import settings

        settings.SCRATCH_DIR.mkdir(parents=True, exist_ok=True)
        self._tempdir = Path(
            tempfile.mkdtemp(prefix="paperless-", dir=settings.SCRATCH_DIR)
        )
        self._text = ""
        self._pdf: Path | None = None

    def __enter__(self) -> Self:
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: TracebackType | None,
    ) -> None:
        shutil.rmtree(self._tempdir, ignore_errors=True)

    def configure(self, context: ParserContext) -> None:
        pass

    def _render(self, document_path: Path) -> Path:
        from documents.parsers import ParseError

        try:
            self._pdf, self._text = render(document_path, self._tempdir)
        except subprocess.CalledProcessError as err:
            stderr = err.stderr.decode(errors="replace") if err.stderr else ""
            raise ParseError(f"rhwp failed on {document_path}: {stderr}") from err
        return self._pdf

    def parse(
        self, document_path: Path, mime_type: str, *, produce_archive: bool = True
    ) -> None:
        # Browsers cannot show HWP, so always render.
        self._render(document_path)

    def get_text(self) -> str:
        return self._text

    def get_date(self) -> datetime.datetime | None:
        return None

    def get_archive_path(self) -> Path | None:
        return self._pdf

    def get_thumbnail(self, document_path: Path, mime_type: str) -> Path:
        from documents.parsers import make_thumbnail_from_pdf

        pdf = self._pdf or self._render(document_path)
        return make_thumbnail_from_pdf(pdf, self._tempdir)

    def get_page_count(self, document_path: Path, mime_type: str) -> int | None:
        if self._pdf is None:
            return None
        from paperless.parsers.utils import get_page_count_for_pdf

        return get_page_count_for_pdf(self._pdf, log=logger)

    def extract_metadata(
        self, document_path: Path, mime_type: str
    ) -> list[MetadataEntry]:
        return []
