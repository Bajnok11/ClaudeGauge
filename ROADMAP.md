# Roadmap

ClaudeGauge is an unofficial, independent, community project. It is **not affiliated with, endorsed by, or a product of Anthropic**. This roadmap describes the direction the maintainers currently intend to explore — it is not a commitment, and none of the items below have target dates. Priorities can and will shift based on contributor availability and community input.

## Now shipped (v0.2)

- Explicit **credential source** picker (Automatic / Claude Code login / API key), plus proactive detection of an expired Claude Code login — the earlier build always preferred the CLI token, so a saved API key could never be reached.
- **Usage history window**: daily token charts (total or split by input/output/cache) and a per-project breakdown, from local transcripts only.
- **Threshold notifications** with rising-edge semantics — one alert per crossing, re-armed only after the window rolls over.
- **Account details** (plan, rate-limit tier, token expiry) surfaced from the existing login.
- **Codex support** via `CodexQuotaProvider`, reading OpenAI Codex CLI's own local rollout logs — no key, no network.
- **Customization**: menu bar style and metric, accent color, warning/critical thresholds, compact popover, section toggles, refresh interval up to 1 hour.
- **Configurable widgets** (small/medium/large) with a per-instance AppIntent — metric and trend line are set per placed widget.
- A real **app icon**, generated reproducibly by `Scripts/generate-icon.swift`.
- A reproducible **screenshot/GIF pipeline** (`Scripts/render-screenshots.sh`) that runs on sample data.

## Shipped in v0.1

- Menu bar app (SwiftUI `MenuBarExtra`, no Dock icon) showing session and weekly Claude usage as two gauges, with a configurable refresh interval (1/5/10/15/30 min).
- A real WidgetKit desktop / Notification Center widget (small + medium) — not just a menu bar item — sharing one visual design system and one data snapshot with the app via an App Group.
- Credential-safe data source: reads the same OAuth token the Claude Code CLI already stores (macOS Keychain on current versions, `~/.claude/.credentials.json` as a fallback on older ones), or a manually entered Anthropic API key stored in the Keychain, with no browser cookie scraping.
- Usage read from Anthropic's own official rate-limit response headers on a minimal `claude-haiku-4-5-20251001` request — the same signal Claude Code itself relies on. Both header shapes are handled: a subscription's Session/Weekly windows, and a pay-as-you-go API key's Tokens/Requests limits, each labeled correctly rather than assuming everyone is on a subscription.
- Shared rendering: both the popover and the widget draw through the same `GaugeDial` component and the same status-color rules, so they cannot visually drift apart.
- `TranscriptLogParser`, a local parser that rolls up daily token totals from Claude Code's own JSONL transcript logs on disk (surfaced in the History window as of v0.2).
- 65 passing XCTest cases in the `ClaudeGaugeCore` Swift package covering both rate-limit header shapes, credential precedence and expiry, JSONL and per-project parsing, Codex quota parsing, notification edge-detection, preferences normalization, and shared-storage round-tripping — runnable via `swift test`, no Xcode or network required.
- Local, unsigned builds via a free/personal Apple ID team (see [DISTRIBUTION.md](DISTRIBUTION.md) for current build steps and their limitations).

## Planned

### iOS companion app + Live Activity

A Live Activity on the Lock Screen / Dynamic Island is one of the more frequently requested ways to see Claude usage at a glance, but it's worth being precise about the constraints: ActivityKit and Live Activities are an iOS/iPadOS API with no direct macOS equivalent, so this is necessarily a new iOS app, not an extension of the existing macOS targets. There are two realistic ways to keep an iPhone's Live Activity in sync with real usage data:

- **(a) An APNs push-relay server.** The Mac app would push updates through a small server that forwards them to the iPhone via Apple Push Notifications, which then updates the Live Activity in near-real time. This is the most "live" option, but it means standing up, securing, and operating a server component — a meaningfully larger maintenance surface than anything else in this project, and one this project doesn't have yet.
- **(b) An independently-polling iOS app (recommended starting point).** The iOS companion polls Anthropic directly using its own stored credentials and starts/refreshes its own Live Activity locally, with no Mac-to-iPhone sync required at all. This is simpler, needs zero server infrastructure, and reuses the same `UsageProvider` logic already written for macOS. Mac/iPhone setting sync (shared refresh interval, shared "which account" state, etc.) could be layered on later via iCloud Key-Value storage once the basic companion app works standalone.

Path (b) is the more likely v2 starting point precisely because it has no new infrastructure dependency; path (a) stays on the table for later if a genuinely real-time experience turns out to matter enough to justify running a server.

### More providers (Gemini CLI, Copilot, …)

`UsageProvider` was written as a protocol from day one specifically so `ClaudeRateLimitProvider` wouldn't be the only thing the rest of the app could talk to. That paid off in v0.2: `CodexQuotaProvider` is a ~200-line conformance that reads OpenAI Codex CLI's own `~/.codex/sessions/**/rollout-*.jsonl` transcripts, where each `token_count` event carries a `rate_limits` block. No credentials, no network — the CLI already wrote the numbers to disk.

Gemini CLI and GitHub Copilot are the obvious next candidates, and the blocker is honesty rather than effort: we haven't been able to verify first-hand where and in what shape those tools record their quota locally, and guessing at a format produces an integration that silently reports wrong numbers — which is worse than not shipping one. **If you use either and can share a sample of its local state files, an issue is the fastest route to support.**

The freshness caveat is worth repeating for any local-file provider: the data is only as current as the last time that CLI ran, which is why Codex rows in the popover show their own age rather than implying a live poll.

### History / Charts UI

`TranscriptLogParser.dailyUsage()` already walks `~/.claude/projects/**/*.jsonl` and produces per-day token totals (input, output, cache-read, cache-creation), and it's covered by tests — but nothing in the app currently displays it. The natural next step is a history/charts screen (likely reachable from the menu bar popover or a dedicated window) that renders those daily rollups over time. Deliberately out of scope for that first version: any USD cost estimate. A competitor (ClaudeBar) has open issues about usage/cost figures being wildly overstated from hardcoded or stale pricing assumptions, and ClaudeGauge would rather ship raw, verifiable token counts than a dollar figure nobody can fully trust — a pricing table would only get added later if it can be sourced reliably and kept current.

### Notarized distribution + Homebrew cask

Right now ClaudeGauge only builds locally under a free/personal Apple ID team: `xcodebuild -allowProvisioningUpdates` successfully builds, signs, and embeds the widget extension, but free-team certificates expire after seven days and there is no notarized, publicly-distributable build — no signed DMG, no Homebrew cask, no Mac App Store listing. This is entirely blocked on enrolling in the paid Apple Developer Program, which the project does not currently have. Once that's in place, the intended path (detailed in [DISTRIBUTION.md](DISTRIBUTION.md)) is: register the App ID and App Group properly through the Apple Developer portal (rather than Xcode's automatic personal-team registration), obtain a Developer ID Application certificate, notarize via `notarytool` (or `xcodebuild -exportNotarizedApp`), staple the ticket, package a DMG, submit a Homebrew cask PR, and wire up GitHub Actions secrets (`APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`, `APP_STORE_CONNECT_API_KEY`, etc.) for automated signed releases going forward.

### Real app icon / marketing assets

`Assets.xcassets/AppIcon.appiconset` currently ships as an empty placeholder slot set — there is no actual icon artwork, screenshots, or other marketing material yet. This is tracked as its own roadmap item both because good icon design is its own skill (not something to bolt on last-minute) and because it's a good, self-contained way for a design-minded contributor to make a visible contribution without touching Swift at all.

## Get involved

None of the above is set in stone — if you'd like to see a particular item prioritized differently, have a design for the app icon, want to prototype the iOS companion, or think a provider integration should come before something listed here, please open an issue to discuss it. Pull requests are welcome, including partial implementations or proposals for items not yet listed here.
