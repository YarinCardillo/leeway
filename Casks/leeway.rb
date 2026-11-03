cask "leeway" do
  version "0.1.1"
  sha256 "74fd54bedcfd48d14feda225a0dda6e81155d48d63c3cefd90ed7c348f38aee9"

  url "https://github.com/YarinCardillo/leeway/releases/download/v#{version}/Leeway-#{version}.zip"
  name "Leeway"
  desc "Menu bar quota readings and forecasts for AI coding accounts"
  homepage "https://github.com/YarinCardillo/leeway"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Leeway.app"
  binary "#{appdir}/Leeway.app/Contents/Helpers/leeway"
end
