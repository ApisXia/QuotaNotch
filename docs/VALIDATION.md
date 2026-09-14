# Validation status

Completed in the Linux Work workspace:

- `git diff --check`: no whitespace errors.
- `bash -n scripts/package-quotanotch.sh`: shell syntax accepted.
- Python JSON parser: both synthetic fixture files valid.
- Python plistlib: app Info.plist valid; upstream Sparkle update feed removed.
- YAML parser: workflow valid, `contents: read`, macOS 15 runner.
- Tree-sitter Swift grammar: all six new Swift files (core, UI, tests, manifest)
  parsed without error. This is syntax parsing, **not Swift compilation/typechecking**.
- OpenStep project parser: project.pbxproj valid; synchronized QuotaNotch source group
  attached to the app target. Independent app and XPC identifiers configured.

Added 14 XCTest cases covering parsing, unknown/malformed fields, actual window
durations, credential redaction, API-key rejection, credential expiry, concurrent
refresh coalescing, provider cooldowns, Retry-After, stale data and clearing on 401.
Tests inject synthetic credentials, clock and HTTP transport; no live account needed.

Subsequent GitHub macOS CI run 34780837703, source a5a142f:

- All 14 XCTest cases passed.
- Full Xcode 26 universal app build succeeded (arm64 + x86_64).
- Initial packaging failed because signing the primary executable implicitly signed
  the containing app before its XPC helper. The signing helper now defers bundle
  entrypoints and signs nested bundles before containers.
- The bundled MediaRemoteAdapter requires macOS 15; deployment target now matches it.

Still awaiting verification:

- Embedded helper/framework signing and DMG creation: see the latest Actions result.
- Keychain authorization and real Claude/Codex endpoint responses.
- SwiftUI/AppKit layout, real notch positioning, animations, gestures, full-screen,
  multiple displays and installation/Gatekeeper behavior.

Remote installation authorization is now working. Repository: ApisXia/QuotaNotch,
branch: feature/quotanotch-ai-usage, PR #1 targeting dev. No upstream branch modified.
