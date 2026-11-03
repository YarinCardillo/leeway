"""The icon generator must leave only portable vector artwork for app runtime."""

import json
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="module")
def generated_icon(tmp_path_factory):
    if sys.platform != "darwin" or not shutil.which("swift"):
        pytest.skip("CoreText outlines require macOS and Swift")
    output = tmp_path_factory.mktemp("icon") / "AppIcon.icon"
    subprocess.run(
        ["swift", str(ROOT / "scripts/generate_app_icon.swift"), str(output)],
        check=True, capture_output=True, text=True, timeout=60,
    )
    return output


def test_app_icon_has_exact_sage_background_and_one_wordmark_layer(generated_icon):
    icon = json.loads((generated_icon / "icon.json").read_text())
    colors = icon["fill"]["linear-gradient"]
    for actual, expected in zip(colors, [(95, 125, 107), (63, 90, 74)], strict=True):
        channels = [float(c) for c in actual.removeprefix("srgb:").split(",")]
        assert channels == pytest.approx([*(c / 255 for c in expected), 1], abs=0.00001)
    layers = [layer for group in icon["groups"] for layer in group["layers"]]
    assert len(layers) == 1
    assert layers[0]["image-name"] == "wordmark.svg"
    assert layers[0]["position"]["scale"] == 1
    assert layers[0]["position"]["translation-in-points"] == [0, 0]


def test_app_icon_wordmark_is_white_outlines_without_runtime_fonts(generated_icon):
    svg = ET.parse(generated_icon / "Assets/wordmark.svg").getroot()
    assert svg.attrib["viewBox"] == "0 0 1024 1024"
    assert svg.attrib["fill"].lower() == "#ffffff"
    children = list(svg)
    assert len(children) == len("Leeway")
    assert all(child.tag.endswith("}path") and child.attrib.get("d") for child in children)
    text = ET.tostring(svg, encoding="unicode").lower()
    assert all(token not in text for token in ["<text", "font-family", "href", "<image"])


def test_app_icon_generation_is_repeatable(generated_icon):
    before = {p.relative_to(generated_icon): p.read_bytes() for p in generated_icon.rglob("*") if p.is_file()}
    subprocess.run(
        ["swift", str(ROOT / "scripts/generate_app_icon.swift"), str(generated_icon)],
        check=True, capture_output=True, text=True, timeout=60,
    )
    after = {p.relative_to(generated_icon): p.read_bytes() for p in generated_icon.rglob("*") if p.is_file()}
    assert after == before
