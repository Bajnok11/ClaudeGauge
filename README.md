# ClaudeGauge

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Xcode](https://img.shields.io/badge/xcode-16%2B-orange)
![License](https://img.shields.io/badge/license-MIT-green)

**ClaudeGauge** is a native macOS app that tracks your Claude session and weekly usage limits — from the menu bar, and from an actual **WidgetKit** desktop / Notification Center widget, both driven by the same data and the same design.

> **Not affiliated with Anthropic.** ClaudeGauge is an unofficial, independent, community project. It is not affiliated with, endorsed by, or a product of Anthropic. "Claude" is a trademark of Anthropic; this project simply reads usage data that Anthropic's own API and CLI already expose to you.

*[Screenshots and a demo GIF coming soon]*

## Features

- **Menu bar tracker** — session (5-hour) and weekly usage at a glance, with a monochrome status-bar glyph that matches macOS's Human Interface Guidelines.
- **Real desktop widget** — a small and medium WidgetKit widget you can pin to your desktop or Notification Center, not just another menu-bar-only app.
- **One shared design system** — the menu bar popover and the widget render through the exact same SwiftUI gauge component, so the numbers and the look can never drift apart.
- **Configurable refresh interval** — poll every 1, 5, 10, 15, or 30 minutes.
- **Credential-safe by design** — reads the OAuth token Claude Code's own CLI already stores locally, or a manually entered API key kept in the macOS Keychain. No browser cookie scraping, ever.
- **Color-coded status** — green under 60%, yellow 60–85%, red above 85%, for both session and weekly limits.
- **Local historical analytics (bonus)** — a local parser rolls up daily token totals (input / output / cache read / cache creation) straight from Claude Code's own transcript logs on disk, no network required. (The parser ships and is tested; it isn't wired into a UI screen yet — see [Roadmap](#roadmap).)

## Why another Claude usage tracker?

There are already several good menu-bar apps for tracking Claude usage on macOS — projects like ClaudeBar, Claude-Usage-Tracker, ClaudeMeter, ClaudeUsageBar, Usagebar, Claude Tracker, ai-usage-widget, claude-toolbar, and others each cover this space in their own way, some with broader multi-provider support or their own polish (like notch-style HUDs). ClaudeGauge isn't trying to claim that space is empty. It's built around a few specific choices that, as far as we've found, none of the existing menu-bar trackers combine:

- **A real WidgetKit widget.** Almost every tracker in this space is an `NSStatusItem` menu-bar app only. ClaudeGauge ships an actual WidgetKit extension — small and medium sizes — that lives on your desktop or in Notification Center, sharing one data snapshot and one visual component with the menu bar app.
- **No cookie scraping, no ToS risk.** Some trackers read your Claude.ai session cookies out of your browser to get usage data — a technique their own docs sometimes flag as a potential Terms of Service concern. ClaudeGauge instead reads the same OAuth token the official Claude Code CLI already stores locally (or a manually entered Anthropic API key as a fallback), and reads Anthropic's own official rate-limit response headers. Same signal Claude Code itself relies on — no scraping involved.
- **Local-only bonus analytics, no invented costs.** ClaudeGauge's optional historical view is built purely from your local Claude Code transcript logs — no network calls, no credentials needed for it. Deliberately, v1 does **not** compute a USD cost estimate: other trackers have had open issues about cost numbers being wildly overstated from stale or hardcoded pricing assumptions. ClaudeGauge would rather show accurate raw token counts than a confident-looking wrong dollar figure.

If your priority is broad multi-provider coverage today (Codex, Gemini, Copilot, etc.), one of the existing tools may already suit you better — ClaudeGauge's multi-provider support is architected for but not yet built (see [Roadmap](#roadmap)). If you specifically want a desktop widget and a credential model that never touches your browser, that's what ClaudeGauge is for.

## Requirements

- macOS 14 or later to run the app.
- [Claude Code](https://claude.com/claude-code) installed and logged in (ClaudeGauge reads its local OAuth credentials at `~/.claude/.credentials.json`), **or** your own Anthropic API key entered manually in Settings.
- To build from source: Xcode 16 or later (developed on Xcode 26.6), and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Building from source

There is no downloadable release yet — no signed build, no DMG, no Homebrew cask (see [Build & signing status](#build--signing-status) below). The only way to run ClaudeGauge today is to build it yourself:

```bash
# 1. Clone the repo
git clone https://github.com/<your-username>/ClaudeGauge.git
cd ClaudeGauge

# 2. Generate the Xcode project from project.yml (XcodeGen is the source of truth;
#    the .xcodeproj itself is not committed to git)
xcodegen generate

# 3. Open the generated project
open ClaudeGauge.xcodeproj
```

In Xcode, select your own Team under **Signing & Capabilities** for both the `ClaudeGauge` and `ClaudeGaugeWidget` targets (the committed `project.yml` ships without a hardcoded team so it stays portable), then hit **Run**.

If you're on a free/personal Apple ID (no paid Apple Developer Program membership), `xcodebuild -allowProvisioningUpdates` will build, sign, and embed the widget extension locally — that's how this project is developed today. Free personal-team certificates expire after 7 days and need re-signing periodically; that's a known Xcode limitation, not a ClaudeGauge bug.

To run just the core logic tests (no Xcode, no network calls, safe for CI):

```bash
cd ClaudeGaugeCore
swift test
```

### Build & signing status

ClaudeGauge builds and runs today via a free/personal Apple ID team. Because there's no paid Apple Developer Program account behind this project yet, there is **no notarized, publicly-distributable build** — no signed DMG, no Homebrew cask, not on the Mac App Store. See [DISTRIBUTION.md](DISTRIBUTION.md) for the exact steps planned for once a paid account is in place.

## How it reads your usage

The menu bar app is the only part of ClaudeGauge that ever talks to the network. On your configured timer, it resolves credentials — first the Claude Code CLI's own local OAuth token, falling back to a manually entered API key in the Keychain — and sends one minimal request to Anthropic's API (the cheapest possible real call). It doesn't care about the response body; it reads Anthropic's own rate-limit response headers, which report your current session and weekly utilization directly.

That reading is written to a small App Group–shared snapshot on disk, and the widget extension is told to refresh. Critically, the widget itself **never** calls the network — its WidgetKit timeline provider only ever reads the last snapshot the menu bar app already fetched. This keeps the widget inside WidgetKit's tight background-execution budget and guarantees it can never show a number the menu bar app didn't already show first. For the full technical breakdown, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Privacy

Nothing leaves your device except the direct API calls ClaudeGauge itself makes to `api.anthropic.com` to check your rate-limit headers. Specifically:

- No telemetry, no analytics, no crash reporting, no third-party servers of any kind.
- No credentials are ever transmitted anywhere except directly to Anthropic's API, over HTTPS, as part of the standard request authentication.
- The optional local historical analytics (from Claude Code's transcript logs) never touch the network at all — everything is read and computed on-disk, locally.
- API keys are stored in the macOS Keychain, not in plain text or `UserDefaults`.

## Roadmap

Highlights only — full detail and rationale in [ROADMAP.md](ROADMAP.md):

- **iOS companion app + Live Activity** — not available today; macOS has no direct Live Activity equivalent, so this is planned as a separate iOS app.
- **Multi-provider support** (Codex, Gemini, etc.) — the provider layer is architected for this, but only Claude ships in v1.
- **History/Charts view** — a UI for the local token-usage data the transcript parser already collects.
- **Notarized, signed distribution** (DMG, Homebrew cask) — blocked on a paid Apple Developer account.
- **Real app icon and marketing assets** — the current icon slot is an empty placeholder.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for dev setup, project structure, and code style conventions. Standard GitHub flow: fork, branch, PR. No CLA required.

## License

MIT — see [LICENSE](LICENSE) for the full text.
