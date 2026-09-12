cask "grok-cli-usage-menu-bar" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/diegocp01/grok_menu_bar/releases/download/v#{version}/GrokCLIUsageMenuBar-#{version}-macOS-universal.zip"
  name "Grok CLI Usage Menu Bar"
  desc "Menu bar monitor for Grok CLI credit usage"
  homepage "https://github.com/diegocp01/grok_menu_bar"

  depends_on macos: ">= :ventura"

  app "Grok CLI Usage Menu Bar.app"

  uninstall launchctl: "com.local.autostart.grok-cli-usage",
            delete: "~/Library/LaunchAgents/com.local.autostart.grok-cli-usage.plist"

  zap trash: [
    "~/Library/LaunchAgents/com.local.autostart.grok-cli-usage.plist",
    "~/Library/Preferences/com.local.grok-cli-usage-menu-bar.plist",
    "~/Library/LaunchAgents/com.local.grok-cli-usage-menu-bar.plist",
  ]
end
