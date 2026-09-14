# Focused feature cleanup

Removed experimental lyrics (including web/AppleScript fetching and timed updates), swipe gesture handling and notch scaling, camera mirror and camera permission onboarding/entitlement, open-notch HUD, media-specific fullscreen inference, unused download and slider demos, and the unfinished custom Lottie animation selector/editor. Removed direct Lottie, Pow and Collections package entries with no remaining imports.

Music, the original audio visualizer, calendar/reminders, AI quota, compact shared wings, language selection and closed-notch system indicators remain. Fullscreen options are now always/never; obsolete nowPlayingOnly values fall back to always. Removed feature settings are no longer read, so persisted old values cannot reactivate removed services.

Selected icon: sleeping cat whose body forms the quota ring (proposal 4). The original generated source is retained in docs/assets; AppIcon contains native 16–1024 pixel variants. README and onboarding use the same artwork. Original licenses and notices are preserved.
