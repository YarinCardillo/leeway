"""Validate release inputs and artifacts without accessing credentials."""
import argparse
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
RELEASE_URL = "https://github.com/YarinCardillo/leeway/releases/download"


def read_version(config, requested):
    """Return version and positive build from xcconfig, rejecting mismatches."""
    pattern = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(alpha|beta|rc)\.([1-9][0-9]*))?"
    if not re.fullmatch(pattern, requested):
        raise ValueError("Use MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-{alpha,beta,rc}.N")
    values = dict(re.findall(r"^([A-Z_]+)\s*=\s*(\S+)\s*$", config, re.MULTILINE))
    if values.get("LEEWAY_RELEASE_VERSION") != requested:
        raise ValueError("Requested version must match App/Version.xcconfig")
    build = values.get("CURRENT_PROJECT_VERSION", "")
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("CURRENT_PROJECT_VERSION must be a positive, increasing integer")
    return requested, int(build)


def release_notes(changelog, version):
    """Return the nonempty, exact version section, excluding other releases."""
    heading = rf"^## (?:\[{re.escape(version)}\]|{re.escape(version)})(?: - [0-9-]+)?\s*\n"
    match = re.search(heading, changelog, re.MULTILINE)
    if match is None:
        raise ValueError(f"CHANGELOG.md has no section for {version}")
    section = re.split(r"^## ", changelog[match.end():], maxsplit=1, flags=re.MULTILINE)[0].strip()
    if not section:
        raise ValueError(f"CHANGELOG.md section for {version} is empty")
    return section + "\n"


def validate_appcast(path, archive, version, build, signature):
    """Reject a feed whose current enclosure differs from the final archive."""
    items = ET.parse(path).findall("./channel/item")
    matches = [item for item in items if item.findtext(SPARKLE + "version") == str(build)]
    if len(matches) != 1:
        raise ValueError("Appcast must contain exactly one item for this build")
    item = matches[0]
    enclosure = item.find("enclosure")
    expected = {"url": f"{RELEASE_URL}/v{version}/{archive.name}",
                "length": str(archive.stat().st_size), SPARKLE + "edSignature": signature}
    if enclosure is None or any(enclosure.get(key) != value for key, value in expected.items()):
        raise ValueError("Appcast enclosure URL, length or signature differs from final ZIP")
    if item.findtext(SPARKLE + "shortVersionString") != version:
        raise ValueError("Appcast short version differs from bundle version")
    channel = "beta" if "-" in version else None
    if item.findtext(SPARKLE + "channel") != channel:
        raise ValueError("Appcast channel does not match release kind")
    if item.findtext(SPARKLE + "minimumSystemVersion") != "14.0":
        raise ValueError("Appcast must require macOS 14.0")


def validate_history(path, build):
    """Require a build greater than every previously distributed appcast item."""
    versions = [item.findtext(SPARKLE + "version", "") for item in ET.parse(path).findall("./channel/item")]
    if any(not value.isdecimal() or int(value) >= build for value in versions):
        raise ValueError("Build number must exceed every existing appcast build")


def main():
    """Expose release validation and changelog extraction to release.sh."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["version", "notes", "feed", "history"])
    parser.add_argument("inputs", nargs="+")
    args = parser.parse_args()
    if args.action == "version":
        print(read_version(Path(args.inputs[0]).read_text(), args.inputs[1])[1])
    elif args.action == "notes":
        print(release_notes(Path(args.inputs[0]).read_text(), args.inputs[1]), end="")
    elif args.action == "history":
        validate_history(Path(args.inputs[0]), int(args.inputs[1]))
    else:
        path, archive, version, build, signature = args.inputs
        validate_appcast(Path(path), Path(archive), version, int(build), signature)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, ET.ParseError) as error:
        sys.exit(str(error))
