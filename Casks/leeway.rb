cask "leeway" do
  version "0.1.0"
  sha256 "0bd644691422302eedd9d2519b7d592c353bd3d10fbefe259ea686d02ee6c1fa"

  url "https://github.com/YarinCardillo/leeway/releases/download/v#{version}/Leeway-#{version}.zip"
  name "Leeway"
  desc "Menu bar quota readings and forecasts for AI coding accounts"
  homepage "https://github.com/YarinCardillo/leeway"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Leeway.app"
  binary "#{appdir}/Leeway.app/Contents/Helpers/leeway"
end
