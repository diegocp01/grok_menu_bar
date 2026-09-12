# Changelog

All notable changes to this project will be documented here.

## 0.1.0 - Unreleased

- Add the native universal macOS menu-bar app for Grok CLI (Grok Build) usage.
- Show weekly credit usage as a percentage or battery, including an on-pace marker.
- Show a live countdown or reset clock time, or hide the time for a more compact menu-bar item.
- Add daily/weekly widget selection, configurable refresh intervals, and Launch at Login by default.
- Read the existing `grok login` session from `~/.grok/auth.json` and call the same billing endpoint as `/usage`.
- Fall back to the last good snapshot when a live fetch fails.
- Add Check for Updates: compare to GitHub `main`, confirm with Update?, then git pull, rebuild, and restart.
