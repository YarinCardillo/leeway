"""Generate a reviewable Homebrew cask pinned to the final ZIP checksum."""
import hashlib
from pathlib import Path
import sys


def write_cask(version, archive, destination):
    """Write cask metadata for a verified release archive."""
    digest = hashlib.sha256()
    with archive.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    checksum = digest.hexdigest()
    destination.write_text(f'''cask "leeway" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/YarinCardillo/leeway/releases/download/v#{{version}}/Leeway-#{{version}}.zip"
  name "Leeway"
  desc "Menu bar quota readings and forecasts for AI coding accounts"
  homepage "https://github.com/YarinCardillo/leeway"

  auto_updates true
  depends_on macos: :sonoma

  app "Leeway.app"
  binary "#{{appdir}}/Leeway.app/Contents/Helpers/leeway"
end
''')


if __name__ == "__main__":
    write_cask(sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]))
