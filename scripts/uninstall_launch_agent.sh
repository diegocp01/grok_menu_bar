#!/usr/bin/env bash
set -euo pipefail

defaults write com.local.grok-cli-usage-menu-bar launchAtLoginPreference -bool false
for label in com.local.autostart.grok-cli-usage com.local.grok-cli-usage-menu-bar; do
  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$label"
  fi
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
echo "Disabled Grok CLI automatic startup and restart."
