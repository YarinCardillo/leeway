cask "leeway" do
  version "0.3.0"
  sha256 "984296d1421116236db7066f3254bd294af8720180031e13d90be3fc28b18a34"

  url "https://github.com/YarinCardillo/leeway/releases/download/v#{version}/Leeway-#{version}.zip"
  name "Leeway"
  desc "Menu bar quota readings and forecasts for AI coding accounts"
  homepage "https://github.com/YarinCardillo/leeway"

  auto_updates true
  depends_on macos: :sonoma

  app "Leeway.app"
  binary "#{appdir}/Leeway.app/Contents/Helpers/leeway"
end
