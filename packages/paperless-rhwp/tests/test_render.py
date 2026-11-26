import os
import subprocess
import sys
from pathlib import Path

import pytest

from paperless_rhwp import PDFTOTEXT, render

SAMPLES = Path(os.environ["RHWP_SAMPLES"])


@pytest.mark.parametrize(
    ("sample", "expected"),
    [
        ("re-01-hangul-only-hancom.hwp", "가나다라마바사"),
        ("tac-host-spacing.hwpx", "NEXT PARAGRAPH"),
    ],
)
def test_render_keeps_text_layer(tmp_path: Path, sample: str, expected: str) -> None:
    pdf, text = render(SAMPLES / sample, tmp_path)
    assert pdf.read_bytes().startswith(b"%PDF")
    assert expected in text.replace("\n", "")


# U+22C5 is missing from Noto CJK and Nanum.
SYMBOL_SAMPLE = SAMPLES / "issue1880_anchor_stack_sb_convert.hwpx"


def test_render_keeps_symbols_missing_from_cjk_fonts(tmp_path: Path) -> None:
    _, text = render(SYMBOL_SAMPLE, tmp_path)
    assert "\u22c5" in text


@pytest.mark.skipif(
    sys.platform == "darwin",
    reason="rhwp also searches /System/Library/Fonts, which the darwin sandbox can read",
)
def test_render_falls_back_to_bundled_font(tmp_path: Path) -> None:
    pdf, _ = render(SYMBOL_SAMPLE, tmp_path)
    fonts = subprocess.run(
        [Path(PDFTOTEXT).with_name("pdffonts"), pdf],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    embedded = {line.split()[0].partition("+")[2] for line in fonts.splitlines()[2:]}
    assert "DejaVuSans" in embedded, embedded
