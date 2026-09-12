# Grok CLI Usage Menu Bar

Small macOS menu-bar utility that shows live Grok CLI (Grok Build) usage limits, reset timing, and credits next to the clock.

<p>
  <img src="assets/menu-bar-preview.png" alt="Grok CLI Usage Menu Bar countdown preview" width="284">
  <img src="assets/menu-bar-battery-preview.png" alt="Battery view showing actual usage remaining and an on-pace marker" width="284">
</p>

In battery mode, the filled portion and number show your **actual percentage remaining**. When **Show % Left** is selected, the vertical contrast marker shows the **on-pace percentage for the time remaining** in the selected daily or weekly window. Like the number, the marker is dark over battery fill and light over empty space, so it remains visible in either position; it automatically softens when it passes beneath the number. If the fill ends before the marker, usage is ahead of pace; if it reaches beyond the marker, there is room to use more. The marker is hidden in **Show % Used** mode.

The app uses the same billing endpoint as Grok CLI `/usage`: `GET /v1/billing?format=credits` on the CLI chat proxy, authenticated with the session in `~/.grok/auth.json` from `grok login`. It understands the current credits-config snapshot, including the rolling weekly window, product split (Build, Chat, …), monthly credits when the API still sends them, and prepaid balance. If a live fetch fails, it falls back to the last good snapshot.

No Python runtime is required by the app. Grok CLI does not have to be running.

Click the menu-bar item to choose:

- Percentage or battery display, including the on-pace marker explained above.
- Percentage left or percentage used. The default is percentage left.
- Reset clock time, a live countdown to reset, or **Hide Time** to show only the icon and battery (or percentage) for a narrower menu-bar item.
- Refresh interval: 30 seconds, 1 minute, 3 minutes, or 5 minutes.
- Automatic login startup and restart after exits, with a menu opt-out.
- **Check for Updates** compares this build to GitHub `main` (new commits and merged PRs). If something is new, it asks **Update?**; **Yes** `git pull`s, rebuilds, and restarts.

The menu-bar icon is the Grok black-hole G-mark. This tracks **Grok CLI / Grok Build** credits, not Cursor Grok Bot.

> Unofficial. Uses the same local login as the Grok CLI and a billing metadata API. xAI may change either at any time.

## Requirements

- macOS 13 Ventura or newer
- A Grok account signed in with `grok login` (`~/.grok/auth.json`)

Grok CLI does not have to stay running. Building from source requires Apple's Xcode Command Line Tools.

## Install

No notarized GitHub Release has been published yet. For now, build the local `.app`:

```sh
./scripts/build.sh
open ".build/release/Grok CLI Usage Menu Bar.app"
```

Sign in once with Grok CLI if you have not already:

```sh
grok login
```

After a signed and notarized GitHub Release is published, it can be installed by downloading the release `.app` or with Homebrew:

```sh
brew tap diegocp01/grok_menu_bar https://github.com/diegocp01/grok_menu_bar
brew install --cask grok-cli-usage-menu-bar
```

The app enables **Launch at Login & Keep Running** on its first launch.

For local development builds, you can also install a per-user LaunchAgent. The script copies the app to `~/Applications` before registering it so cloud-sync metadata in a source checkout cannot invalidate its code signature:

```sh
./scripts/install_launch_agent.sh
```

The installer copies the app into a stable location; the app manages its own startup registration.

## Build Locally

```sh
./scripts/test.sh
./scripts/build.sh
open ".build/release/Grok CLI Usage Menu Bar.app"
```

The build script produces a universal Apple Silicon/Intel `.app` bundle and ad-hoc signs it for local use. This local build is not notarized.

Sanity-check the live billing parse without opening the menu bar:

```sh
".build/release/Grok CLI Usage Menu Bar.app/Contents/MacOS/GrokCLIUsageMenuBar" --dump-usage
```

## Release

Set the signing and notarization environment variables, then run:

```sh
VERSION=0.1.0 \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
./scripts/release.sh
```

See [RELEASING.md](RELEASING.md) for the full flow. Secrets stay in the environment and must never be committed.

## Legacy LaunchAgent Cleanup

To remove the local development LaunchAgent:

```sh
./scripts/uninstall_launch_agent.sh
```

## Persistent menu-bar startup

On first launch, the app installs a per-user LaunchAgent that starts it after login
(including after a restart) and reopens it if it exits. It uses `open -g -W` so
macOS launches the normal app bundle without creating duplicate instances, with
a 30-second throttle to avoid a tight restart loop. No administrator access is needed.
An existing saved opt-out is preserved.

**Quit will reopen the app while this option is enabled.** Turn off
**Launch at Login & Keep Running** in the app menu before quitting to keep it closed.
Registration failures are shown in the menu. If macOS blocks a background item,
allow the app in **System Settings → General → Login Items**, then toggle the option
off and on. macOS approval and a logged-in graphical session are required; startup
cannot put an icon on the login screen. Install the app in its final location before
opening it, and open it again after moving it to update the saved path.

Install/update scripts pause the restart job before replacing the app. The next normal
launch resumes it if enabled. To remove the app, disable the menu option first.

Run `./scripts/test-startup.sh` for isolated startup lifecycle tests. These use a
fake launchctl runner and temporary paths; they never alter your login items.

## Privacy

- Reads `~/.grok/auth.json` (the same session Grok CLI uses) and may refresh the OIDC access token in that file.
- Usage requests go to xAI (`cli-chat-proxy.grok.com` and `auth.x.ai`).
- No analytics. Tokens are never logged.
- `--dump-usage` prints sanitized usage JSON (percent, reset, plan). It does not print tokens.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). CI runs `./scripts/test.sh` and `./scripts/build.sh`.

## Disclaimer

This is an independent, unofficial project. It is not affiliated with or endorsed by xAI. Grok is a trademark of xAI.

## License

[MIT](LICENSE)
