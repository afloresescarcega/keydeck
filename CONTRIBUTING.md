# Contributing to KeyDeck

Contributions, bug fixes, and ideas are welcome! KeyDeck is MIT licensed.

## Local Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
2. Create your local signing configuration (gitignored):
   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```
   Fill in your Apple Developer `KEYDECK_DEVELOPMENT_TEAM`, `KEYDECK_BUNDLE_PREFIX`, `KEYDECK_APP_GROUP`, `KEYDECK_ICLOUD_CONTAINER`, and `KEYDECK_KEYCHAIN_SUFFIX`.
3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
4. Run the shared package test suite:
   ```bash
   swift test --package-path Packages/KeyDeckKit
   ```
5. Open `KeyDeck.xcodeproj` in Xcode and run the **KeyDeck** scheme on your iPhone (custom keyboard microphone capture requires a physical iOS device).

## Design & Security Standards

- Follow [DESIGN.md](DESIGN.md) for all SwiftUI & keyboard UI changes (Apple HIG, native `.insetGrouped` lists, semantic colors, tactile keycap feedback, zero AI-slop clichés).
- Never commit `Config/Local.xcconfig`, API keys, `.env` files, or personal Apple Developer Team IDs.
- Keep `Packages/KeyDeckKit` free of UIKit-only dependencies so `swift test` runs fast on macOS CI.
- Update `PrivacyInfo.xcprivacy` in the affected target(s) if you introduce any Apple Required Reason API.
