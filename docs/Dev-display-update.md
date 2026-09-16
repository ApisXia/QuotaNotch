# Development build: readable quota display

Version remains 1.0.0. Built from dev, without publishing a release.

- Larger display is on by default: a 32 pt notch now uses 28 pt icons (previously 20 pt), with a near-full-size ring and larger digits. Compact mode uses 24 pt icons. Existing show-number preferences are preserved.
- Expanded quota percentages grow from 21 to 28 pt, with larger labels and reset countdowns. The panel is 680 × 260 pt.
- Refresh cooldown is visible; the manual refresh action targets the selected provider and is disabled during cooldown.
- Stale readings are identified by age as well as failures; waking from sleep rechecks usage without bypassing provider cooldowns.
- Low-quota and confirmed-recovery notifications are opt-in under Settings → AI Usage, with 10/20/30% thresholds. Alerts are deduplicated per quota cycle.
- Optional automatic selection compares only chosen windows with fresh readings, and falls back to the manual pin.
- Copy diagnostics includes app/OS versions, connection states and timestamps, excluding credentials and account identifiers.
- Hover close delay is 250 ms, menus hold the panel open, and in-flight results are discarded after monitoring settings change.
- Nonzero readings below 1% display <1%; countdown expiry waits for server confirmation.

Validation: cloud fixture tests, macOS universal compilation, native English/Chinese and compact renders, signing and DMG checks. Actual pointer interactions and system notification delivery still require on-device use. Developer ID signing/notarization is not part of this build.
