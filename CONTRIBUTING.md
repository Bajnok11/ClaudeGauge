# Contributing to ClaudeGauge

Thanks for taking a look at ClaudeGauge. It's a small, unofficial, independent, community project (not affiliated with, endorsed by, or a product of Anthropic — just a menu bar app + widget built by someone who wanted one), and outside contributions are genuinely welcome — bug fixes, new `UsageProvider`s, UI polish, docs fixes, all of it.

This doc covers how to get the project running locally, the conventions the existing code follows, and how to send a PR. It's meant to be practical, not a policy document — if something here is unclear or wrong, that's itself worth a PR. For the technical picture of how the app, widget, and core package fit together, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Getting set up

You'll need:

- **Xcode 16 or later** (this project is developed on Xcode 26.6, targeting macOS 26 "Tahoe" SDK; the app itself has a macOS 14+ deployment target, so it runs on older macOS too)
- **macOS 14+** to actually run the app
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)**, installed via Homebrew:

  ```sh
  brew install xcodegen
  ```

The `.xcodeproj` is **not** committed to git — `project.yml` at the repo root is the source of truth, and XcodeGen generates the Xcode project from it. This means after cloning (and after pulling any change that touches `project.yml`), you need to regenerate the project before opening it.

### Dev loop

From the repo root:

```sh
xcodegen generate
open ClaudeGauge.xcodeproj
```

Then, inside Xcode:

1. Select the **ClaudeGauge** target, go to **Signing & Capabilities**, and set **your own Team** (a free personal Apple ID team is fine for local development).
2. Do the same for the **ClaudeGaugeWidget** target — the widget extension needs its own signing team set too, or the build will fail to embed it.
3. Hit **Run**.

A couple of things that trip people up here:

- Because there's no paid Apple Developer Program membership behind this project (yet — see [DISTRIBUTION.md](DISTRIBUTION.md)), `project.yml` intentionally ships with no hardcoded team, so it stays portable across every contributor's own account. You always have to set your Team locally; that's expected, not a bug.
- Free personal-team signing certificates expire after **7 days**. If the app suddenly won't launch a week after you last built it, that's Xcode's free-account provisioning expiring, not a ClaudeGauge regression — just re-sign (Xcode will usually offer to do this automatically, or re-run with `xcodebuild -allowProvisioningUpdates`).

### Running the core logic tests

Most of the interesting, testable logic (rate-limit header parsing, credentials parsing, JSONL transcript parsing, shared-storage round-tripping) lives in the `ClaudeGaugeCore` Swift package, which has no SwiftUI or AppKit dependency — just Foundation. You don't need Xcode open, or even a signing team configured, to run its test suite:

```sh
cd ClaudeGaugeCore
swift test
```

This is fast, makes no network calls, and is safe to run in CI or in a sandboxed environment. If you're touching anything in `ClaudeGaugeCore/Sources`, run this before opening a PR. If you're adding new behavior there, add or extend an `XCTest` case alongside it — that's where all 65 current tests live (`ClaudeGaugeCore/Tests/ClaudeGaugeCoreTests/`).

## Code style

There's no SwiftLint or SwiftFormat config in the repo yet, so for now the rule is: **match the existing style**, which is:

- **4-space indentation**, no tabs.
- **Doc comments on public `ClaudeGaugeCore` API should explain *why*, not just *what***. A one-line `/// Parses the rate limit headers.` above `RateLimitHeaders.parse()` doesn't tell the next person anything they couldn't get from the function name. Explain the reasoning that isn't obvious from the code itself — e.g. why the widget extension never touches the network, why credentials are resolved in a particular order, why a given field is optional.
- **No force-unwraps (`!`) in new code.** Parsing untrusted input (API response headers, JSON on disk, JSONL transcript lines) is most of what this codebase does, and a force-unwrap there turns a malformed file or an unexpected header into a crash instead of a handled error. Prefer `guard let`, optional chaining, or propagating a typed error.
- **Prefer explicit methods over property-observer (`didSet`) side effects**, especially for anything that triggers I/O or writes shared state. The concrete reason: `didSet` does **not** fire when a property is set during `init`, only on assignments after initialization completes. That's a well-known Swift gotcha, and it's exactly the kind of thing that causes a silent, hard-to-debug bug in code like `UsageModel` — e.g. if writing a fresh snapshot to `SharedStorage` or calling `WidgetCenter.shared.reloadAllTimelines()` were wired up as a `didSet` on the snapshot property, that side effect would just never happen for the value set during initialization, and you'd only notice because the widget looks stale after a fresh launch. `UsageModel.swift` has a design-note comment in its header explaining this in more detail — writing an explicit `update(_:)`-style method that both sets the value and performs the side effect keeps the behavior the same regardless of whether the caller is `init` or a later poll tick.

None of this is enforced by tooling today, so it's on code review (yours and reviewers') to catch. If you want to propose adding SwiftLint/SwiftFormat with a config that encodes these rules, that'd be a welcome contribution in itself.

## Where to start

If you're looking for something scoped enough to be a first contribution, a few areas stand out:

- **UI polish** in `MenuBarView.swift`, `SettingsView.swift`, or the shared `GaugeDial`/`UsageStatus+Color` views in `Shared/`. These are small SwiftUI files and a good way to get familiar with how the app, widget, and popover all share the same rendering code.
- **A new `UsageProvider`** for another AI coding tool (Gemini CLI, Copilot, …), per the providers item in [ROADMAP.md](ROADMAP.md). `UsageProvider` is a protocol specifically so this is a new conformance rather than a rework. `CodexQuotaProvider.swift` is the best template if the tool writes quota to local files (no credentials at all), and `ClaudeRateLimitProvider.swift` if it needs an authenticated request. **Even without writing code, a sample of where your tool stores its local quota state is genuinely useful** — the reason Gemini and Copilot aren't supported is that we can't verify their formats first-hand, and guessing produces an integration that reports wrong numbers.
- **Cost estimation**, deliberately unimplemented so far. `TranscriptLogParser` already produces exact per-day, per-model-agnostic token counts; the missing piece is a pricing source that can be kept current without silently going stale. A proposal for how to source and update it is more valuable than the code.
- **A SwiftLint/SwiftFormat config** encoding the conventions above.

### Two things worth knowing before you touch the tests

- **Anything reading the Keychain must take an injectable service name.** An early version of the credential tests didn't, and silently read the real Claude Code login of whoever ran them — machine-dependent, and it printed a live OAuth token into the log on failure. See `ClaudeRateLimitProvider(keychainService:)` and how `CredentialResolutionTests` passes a UUID that can't exist.
- **Screenshots run on sample data, not yours.** `./Scripts/render-screenshots.sh` launches the app with an `isSample` model that disables polling, Keychain reads, and transcript parsing. If you add a view that loads data in `.task`, guard it the same way — otherwise regenerating the README images publishes your own project names.

If you want to work on something not listed here (including in [DISTRIBUTION.md](DISTRIBUTION.md)'s notarization/CI roadmap), opening an issue first to talk through the approach is a good idea before sinking time into a PR — especially for anything that touches signing, entitlements, or the shared App Group, since those are easy to get subtly wrong.

## Sending a PR

Standard GitHub flow, nothing unusual:

1. Fork the repo.
2. Create a branch for your change (off `main`).
3. Make your change. If it touches `ClaudeGaugeCore`, run `swift test` first. If it touches `project.yml`, re-run `xcodegen generate` and confirm the app still builds and runs for both targets.
4. Open a PR describing what changed and why. Screenshots are appreciated for anything UI-visible.
5. Address review feedback; a maintainer will merge once it looks good.

There's no CLA to sign — just open the PR.
