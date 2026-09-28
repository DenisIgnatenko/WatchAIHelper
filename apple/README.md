# Apple clients (iOS + watchOS)

## First-time setup

1. Install XcodeGen: `brew install xcodegen`.
2. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and set your
   `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX`. The file is git-ignored.
3. Generate the project: `cd apple && xcodegen`. Re-run it after pulling changes to `project.yml`
   or after adding/removing source files.
4. Open `AICopilot.xcodeproj`, select the `AICopilot` scheme and your iPhone, press Run.
   The Watch app is embedded and installed with it. To run the Watch app directly, select the
   `AICopilotWatch` scheme and the watch.

## Free (Personal Team) signing notes

- Profiles expire after 7 days: reconnect the devices and press Run again.
- First launch on iPhone: Settings > General > VPN & Device Management > trust your developer certificate.
- watchOS 27 + Xcode 27: the watch must be paired from the watch side
  (Device Hub > File > Pair Nearby Device, then on the watch: Settings > Privacy & Security > Developer Mode).
  Never remove the watch from Device Hub.

## Tests

`cd Packages/CopilotKit && swift test`
(If the repository is inside an iCloud-synced folder, add `--scratch-path /tmp/copilotkit-build`:
iCloud adds file attributes that break code signing of the test bundle.)

## Layout

| Path | Content |
|---|---|
| `project.yml` | XcodeGen project specification (targets, settings) |
| `Config/` | xcconfig files; `Signing.local.xcconfig` is personal and git-ignored |
| `Packages/CopilotKit` | Shared Swift package: domain, service contract, mock, request observation |
| `iOS/` | iOS app (Phase 1: placeholder + "Ask with Camera" App Shortcut) |
| `Watch/` | watchOS app |
