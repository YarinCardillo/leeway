"""Controls inherit the native accent, including the multicolour setting."""

from pathlib import Path
import re


def test_app_controls_do_not_override_tint_toggle_style_or_system_palette():
    sources = Path(__file__).resolve().parents[2] / "App/Sources"
    overrides = re.compile(r"\.tint\s*\(|\.toggleStyle\s*\(|NSColor\s*\(srgbRed:|Color\s*\(red:")
    violations = [str(path.relative_to(sources)) for path in sources.rglob("*.swift")
                  if overrides.search(path.read_text())]
    assert violations == []
