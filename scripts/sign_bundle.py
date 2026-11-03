"""Sign every physical Mach-O and code bundle inside out, without deep signing."""
from pathlib import Path
import plistlib
import subprocess
import sys

MACHO_MAGICS = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}


def is_macho(path):
    """Identify executable images by their Mach-O header, not filename suffix."""
    if path.is_symlink() or not path.is_file():
        return False
    with path.open("rb") as stream:
        return stream.read(4) in MACHO_MAGICS


def verify_universal(path):
    """Require both supported architecture slices before signing an image."""
    subprocess.run(["lipo", str(path), "-verify_arch", "arm64", "x86_64"], check=True, timeout=30)


def bundle_executable(bundle):
    """Find the executable signed through its owning code container."""
    if bundle.suffix == ".framework":
        info = bundle / "Resources/Info.plist"
        base = bundle
    else:
        info = bundle / "Contents/Info.plist"
        base = bundle / "Contents/MacOS"
    with info.open("rb") as stream:
        name = plistlib.load(stream)["CFBundleExecutable"]
    return (base / name).resolve()


def signing_targets(app):
    """Return inside-out targets; each container signs its own main executable."""
    paths = [path for path in app.rglob("*") if not path.is_symlink()]
    containers = [path for path in paths if path.is_dir() and path.suffix in {".app", ".xpc", ".framework", ".bundle"}]
    owned = {bundle_executable(bundle) for bundle in containers + [app]}
    images = [path for path in paths if is_macho(path) and path.resolve() not in owned]
    return sorted(images + containers, key=lambda path: len(path.parts), reverse=True) + [app]


def sign_bundle(app, identity, entitlements):
    """Verify all slices, sign inside out, then verify the complete app."""
    images = [path for path in app.rglob("*") if is_macho(path)]
    if not images:
        raise ValueError("App contains no Mach-O images")
    for path in images:
        verify_universal(path)
    for path in signing_targets(app):
        subprocess.run(["codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp",
                        "--entitlements", str(entitlements), str(path)], check=True, timeout=120)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True, timeout=120)


if __name__ == "__main__":
    sign_bundle(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]))
