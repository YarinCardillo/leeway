cask "leeway" do
  version "0.2.0"
  sha256 "083212dea422aa9e43c59c3982b282ee94ad66d907b532d6fa9705a2246a6cc0"

  url "https://github.com/YarinCardillo/leeway/releases/download/v#{version}/Leeway-#{version}.zip"
  name "Leeway"
  desc "Menu bar quota readings and forecasts for AI coding accounts"
  homepage "https://github.com/YarinCardillo/leeway"

  auto_updates true
  depends_on macos: :sonoma

  app "Leeway.app"
  binary "#{appdir}/Leeway.app/Contents/Helpers/leeway"
end
