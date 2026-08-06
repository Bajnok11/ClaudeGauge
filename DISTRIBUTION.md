# Distribution

This document describes how ClaudeGauge is signed and run today, and the exact steps required to move to notarized, publicly-distributable releases once the project has a paid Apple Developer Program membership.

> Disclaimer: ClaudeGauge is an unofficial, independent, community project. It is not affiliated with, endorsed by, or a product of Anthropic.

## Current state (read this first)

As of today, ClaudeGauge has **no paid Apple Developer Program membership**. That has real consequences for how it can be built and shared:

- **Signing**: The app and the `ClaudeGaugeWidget` extension build and run using a free/personal Apple ID team. `xcodebuild -allowProvisioningUpdates` (or a normal Xcode "Run") successfully builds, signs, and embeds the widget extension locally on the machine that built it.
- **Certificate lifetime**: Free personal-team code-signing certificates expire after **7 days**. This is a known Xcode limitation for free accounts, not a ClaudeGauge bug — you will need to re-open Xcode and let it re-sign periodically if you leave a build sitting untouched.
- **No notarization, and Gatekeeper's response is stricter than a soft warning**: There is no Developer ID Application certificate, so there is no notarized build. Verified with `spctl -a -vvv` against an actual built `.app`: the personal-team ("Apple Development") signature is **rejected outright** by Gatekeeper's policy check — this is not the milder "unidentified developer, right-click to open" tier that a Developer ID-signed-but-unnotarized app would get. The only reliable bypass is **System Settings → Privacy & Security → Open Anyway** (after a first blocked launch attempt), or removing the quarantine attribute directly (`xattr -d com.apple.quarantine`).
- **A DMG and Homebrew cask do exist** ([GitHub Releases](https://github.com/Bajnok11/ClaudeGauge/releases), [Bajnok11/homebrew-claudegauge](https://github.com/Bajnok11/homebrew-claudegauge)) — built via `Scripts/build-dmg.sh`, with the same free-team signing described above. The Homebrew cask's `postflight` step removes the quarantine attribute automatically after install, which sidesteps the Gatekeeper rejection for anyone installing that way; the raw DMG does not, so manual downloaders need the System Settings step above. Neither is notarized.
- **No Mac App Store listing**: ClaudeGauge is not, and is not currently planned to be, distributed through the Mac App Store (Developer ID / notarized distribution outside the App Store is the intended path, because `MenuBarExtra` + `LSUIElement` + WidgetKit + App Group all work fine outside the Store and Store review adds friction for a hobby/OSS project).

**Three ways to run ClaudeGauge today:**

- `brew tap Bajnok11/claudegauge && brew install --cask claudegauge` (handles the Gatekeeper issue for you)
- Download the DMG from [Releases](https://github.com/Bajnok11/ClaudeGauge/releases) and follow the Gatekeeper override steps above
- Build it yourself:
  1. Clone the repo.
  2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) if you don't have it.
  3. Run `xcodegen generate` from the repo root to produce `ClaudeGauge.xcodeproj` (the `.xcodeproj` is not committed — `project.yml` is the source of truth).
  4. Open the project in Xcode.
  5. In **Signing & Capabilities**, select your own personal Team for **both** the `ClaudeGauge` and `ClaudeGaugeWidget` targets (the committed `project.yml` intentionally ships without a hardcoded `DEVELOPMENT_TEAM` so it stays portable across contributors' own accounts).
  6. Run. Expect to re-sign every ~7 days if you're using a free account. (A locally-built app has no quarantine flag at all, so Gatekeeper never blocks it in the first place — this is why the workaround above is only needed for downloaded artifacts.)

Everything below is written for the day a paid Apple Developer Program membership ($99/year) exists for the project. Until then, treat it as a checklist/reference, not as something contributors need to do.

---

## Checklist: moving to notarized Developer ID distribution

### 1. Enroll in the Apple Developer Program

Enroll the account that will own the project's Apple ID at [developer.apple.com/programs](https://developer.apple.com/programs/). Note the resulting **Team ID** (a 10-character alphanumeric string, e.g. `A1B2C3D4E5`) — you'll need it repeatedly below.

### 2. Register the App IDs in the Apple Developer portal

Right now, the app's bundle identifiers exist only because Xcode's **automatic personal-team registration** creates ad-hoc, personal-team-scoped App IDs behind the scenes when you hit Run. That's fine for local development but is not a stable basis for a real release — it does not give you access to a proper App Group capability record, and it's tied to the individual developer's personal team rather than the project's team.

With a paid account, register these explicitly under **Certificates, Identifiers & Profiles → Identifiers**:

1. **App ID** for the main app: `dev.claudegauge.app`
   - Capability: **App Groups** — enabled.
2. **App ID** for the widget extension: `dev.claudegauge.app.widget`
   - Capability: **App Groups** — enabled.
   - (This must be registered as an explicit App ID, not wildcard, since it's an app extension.)
3. **App Group**: `group.dev.claudegauge.shared`
   - Register it once under **Identifiers → App Groups**, then attach it to both App IDs above.

Once these three records exist, the entitlements files already in the repo (`ClaudeGauge/ClaudeGauge.entitlements` and `ClaudeGaugeWidget/ClaudeGaugeWidget.entitlements`) don't need their App Group string changed — they already reference `group.dev.claudegauge.shared`. What changes is that Xcode will bind to the **real, portal-registered** App Group record instead of silently creating a personal-team-scoped one.

### 3. Obtain a Developer ID Application certificate

Distribution outside the Mac App Store (which is the intended path for ClaudeGauge) requires a **Developer ID Application** certificate, not the "Apple Development" certificate used for local runs.

1. In Xcode: **Settings → Accounts → [Team] → Manage Certificates → +  → Developer ID Application**, or generate it via the portal (**Certificates, Identifiers & Profiles → Certificates → + → Developer ID Application**) using a CSR from Keychain Access.
2. Confirm it appears in `security find-identity -v -p codesigning` as `"Developer ID Application: <Name> (<TEAM_ID>)"`.
3. Widget extensions are sandboxed by OS requirement regardless of signing identity — `ClaudeGaugeWidget.entitlements` already has App Sandbox enabled, so no entitlement change is needed there. The main app remains un-sandboxed (it needs to read `~/.claude/projects/**/*.jsonl` directly from disk for the local transcript parser, and falls back to reading a legacy `~/.claude/.credentials.json` file when the primary Keychain-based credential lookup finds nothing — both of which App Sandbox would block without broad file-access entitlements).

### 4. Update `project.yml`

Two settings need real values once a paid account is in play (currently both are intentionally left generic/blank so the project builds for any contributor's personal team):

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "<TEAM_ID>"
    CODE_SIGN_IDENTITY: "Developer ID Application"
    CODE_SIGN_STYLE: Manual
```

Notes:
- For local contributor development, keep `DEVELOPMENT_TEAM` and automatic signing **out of the committed `project.yml`** (or gated behind a local override / `xcconfig` file that's gitignored) so contributors on their own free/paid accounts aren't forced onto the project's team ID. The release/CI build should apply `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY: Developer ID Application` via a separate release-only xcconfig or `xcodebuild` command-line overrides (`DEVELOPMENT_TEAM=... CODE_SIGN_IDENTITY="Developer ID Application"`), not by hardcoding them into the shared `project.yml`.
- After any `project.yml` change, contributors and CI both need to re-run `xcodegen generate`.

### 5. Notarization flow

Once signing with a Developer ID Application identity works:

1. **Archive** the app (both targets, with the widget extension embedded):
   ```sh
   xcodebuild -project ClaudeGauge.xcodeproj -scheme ClaudeGauge \
     -configuration Release -archivePath build/ClaudeGauge.xcarchive \
     DEVELOPMENT_TEAM=<TEAM_ID> CODE_SIGN_IDENTITY="Developer ID Application" \
     archive
   ```
2. **Export** a Developer ID-signed `.app` from the archive. This needs an `ExportOptions.plist` with `method: developer-id`:
   ```xml
   <key>method</key><string>developer-id</string>
   <key>teamID</key><string>TEAM_ID</string>
   <key>signingStyle</key><string>manual</string>
   ```
   ```sh
   xcodebuild -exportArchive -archivePath build/ClaudeGauge.xcarchive \
     -exportPath build/export -exportOptionsPlist ExportOptions.plist
   ```
3. **Submit for notarization** with `notarytool` (the modern replacement for `altool`), using an App Store Connect API key (see the secrets list in step 7 — the same key works for notarization):
   ```sh
   ditto -c -k --keepParent build/export/ClaudeGauge.app build/ClaudeGauge.zip
   xcrun notarytool submit build/ClaudeGauge.zip \
     --key AuthKey.p8 --key-id <APP_STORE_CONNECT_API_KEY_ID> \
     --issuer <APP_STORE_CONNECT_API_ISSUER_ID> --wait
   ```
4. **Staple** the notarization ticket to the app so it verifies offline (e.g. right after download, before first launch, without contacting Apple):
   ```sh
   xcrun stapler staple build/export/ClaudeGauge.app
   ```
5. Verify with `spctl -a -vvv --type execute build/export/ClaudeGauge.app` — it should report `accepted` and `source=Notarized Developer ID`.

### 6. Package a DMG

Wrap the stapled `.app` in a `.dmg` for distribution. Either approach works; [`create-dmg`](https://github.com/create-dmg/create-dmg) is less boilerplate:

```sh
brew install create-dmg
create-dmg \
  --volname "ClaudeGauge" \
  --window-size 500 300 \
  --icon-size 100 \
  --app-drop-link 360 120 \
  "build/ClaudeGauge.dmg" \
  "build/export/ClaudeGauge.app"
```

Or with plain `hdiutil` if you'd rather not add a dependency:

```sh
mkdir -p build/dmg-staging
cp -R build/export/ClaudeGauge.app build/dmg-staging/
ln -s /Applications build/dmg-staging/Applications
hdiutil create -volname "ClaudeGauge" -srcfolder build/dmg-staging \
  -ov -format UDZO build/ClaudeGauge.dmg
```

The `.dmg` itself does **not** need separate notarization if the `.app` inside it is already stapled, but Apple also allows (and some guides recommend) notarizing the `.dmg` as a second artifact for a smoother Gatekeeper experience — `xcrun notarytool submit build/ClaudeGauge.dmg ... --wait` followed by `xcrun stapler staple build/ClaudeGauge.dmg`.

### 7. GitHub Actions release workflow

A future `.github/workflows/release.yml` triggered on tag push would need to:

1. Check out the repo, install XcodeGen, run `xcodegen generate`.
2. Import the Developer ID Application certificate into a **temporary, ephemeral keychain** (never the runner's default login keychain) from a base64-encoded `.p12` secret, then unlock it and add it to the search list so `codebuild`/`codesign` can find it.
3. Run the archive → export → notarize → staple → DMG steps above.
4. Upload the `.dmg` (and optionally the raw `.zip`) to the GitHub Release for that tag.
5. Tear down the temporary keychain at the end of the job (`security delete-keychain`), including on failure, so no signing material lingers on the runner.

Plausible repository secret names to configure under **Settings → Secrets and variables → Actions**:

| Secret | Purpose |
|---|---|
| `APPLE_CERTIFICATE_P12` | Base64-encoded Developer ID Application `.p12` (cert + private key) |
| `APPLE_CERTIFICATE_PASSWORD` | Password used to encrypt that `.p12` on export |
| `APPLE_TEAM_ID` | The 10-character Apple Developer Team ID |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID for the App Store Connect API key used by `notarytool` |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID paired with that API key |
| `APP_STORE_CONNECT_API_KEY` | Base64-encoded `.p8` private key content itself |

A representative import step (illustrative, not copy-paste-final):

```sh
KEYCHAIN=build.keychain
security create-keychain -p "$RUNNER_TEMP_PW" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$RUNNER_TEMP_PW" "$KEYCHAIN"

echo "$APPLE_CERTIFICATE_P12" | base64 --decode > cert.p12
security import cert.p12 -k "$KEYCHAIN" -P "$APPLE_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security

security list-keychains -d user -s "$KEYCHAIN" login.keychain
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$RUNNER_TEMP_PW" "$KEYCHAIN"

echo "$APP_STORE_CONNECT_API_KEY" | base64 --decode > AuthKey.p8

# ... archive / export / notarize / staple / dmg steps ...

security delete-keychain "$KEYCHAIN"
rm -f cert.p12 AuthKey.p8
```

Keep the temporary keychain password itself as a workflow-generated random value (e.g. `openssl rand -base64 32` at job start) rather than a stored secret — it only needs to exist for the lifetime of that job.

---

## Homebrew cask (once a release exists)

Only pursue this after step 6 above has produced at least one real, notarized, publicly downloadable `.dmg` attached to a GitHub Release — there is no tap and no cask today.

1. Fork [`Homebrew/homebrew-cask`](https://github.com/Homebrew/homebrew-cask).
2. Add `Casks/c/claudegauge.rb` (Homebrew casks are filed alphabetically by first letter):
   ```ruby
   cask "claudegauge" do
     version "0.1.0"
     sha256 "<sha256-of-the-dmg>"

     url "https://github.com/<your-username>/ClaudeGauge/releases/download/v#{version}/ClaudeGauge.dmg"
     name "ClaudeGauge"
     desc "Unofficial menu bar and widget tracker for Claude usage limits"
     homepage "https://github.com/<your-username>/ClaudeGauge"

     depends_on macos: ">= :sonoma"

     app "ClaudeGauge.app"

     zap trash: [
       "~/Library/Application Support/ClaudeGauge",
       "~/Library/Preferences/dev.claudegauge.app.plist",
     ]
   end
   ```
3. Compute the real `sha256` from the published `.dmg` (`shasum -a 256 ClaudeGauge.dmg`) — do not guess or reuse a placeholder.
4. Run `brew audit --new --cask claudegauge` and `brew style Casks/c/claudegauge.rb` locally and fix anything they flag before opening the PR — this is what CI checks first.
5. Open the PR against `homebrew-cask` following their contribution guidelines (PR title format `claudegauge 0.1.0`, one cask per PR, no unrelated changes). Expect their automated checks plus maintainer review; they will ask for a working, notarized download as a prerequisite — attempting this before step 6 above is functional will get the PR closed.
6. Once merged, `brew install --cask claudegauge` becomes the documented install path in [README.md](README.md), and future releases only need the `version`/`sha256` bumped (Homebrew's `brew bump-cask-pr` automates that).
