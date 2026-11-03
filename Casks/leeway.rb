cask "leeway" do
  version "0.1.0"
  sha256 "5fb3cd59bb69707f43b528d1a3ec207fd4a92c123496c160b55d5bd3a9cc249a"

  url "https://github.com/YarinCardillo/leeway/releases/download/v#{version}/Leeway-#{version}.zip"
  name "Leeway"
  desc "Menu bar quota readings and forecasts for AI coding accounts"
  homepage "https://github.com/YarinCardillo/leeway"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Leeway.app"
  binary "#{appdir}/Leeway.app/Contents/Helpers/leeway"
end
