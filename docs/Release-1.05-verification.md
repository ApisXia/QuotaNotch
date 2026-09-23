# 1.05 scope audit

Branch starts at a5c9e4c, preserving the experimental branch unchanged.

Removed: Shelf tab/settings, compact accessories, floating holder, file store/drop/export,
material shaders, file-specific fixtures, material demo and preview workflow, and Finder permission.
No migration deletes saved user files.

Retained compared with 1.04:
- Claude credential repository, system security adapter, memory cache, auth fallback policy,
  attribution and credential regression fixtures.
- Shared full-wing scroll monitor: slow-delta accumulation, axis ownership, momentum suppression,
  nonactivating panel coordinate handling and click-through behavior. Extracted from BubbleNotchLayout
  into feature-neutral NotchScrollRouter; both existing shared-router tests retained.
- Physical-camera hover target uses the actual inset gap, leaving wing controls accessible.
- Existing cat, task state/read/history, and audio/quota/task layout behavior.

All other changes to integration files compared with origin/main were audited as Shelf-specific.
The native preview runner retains its existing complete combination/height/localization fixtures;
its new gesture fixture exercises the real quota/task dock without Shelf dependencies.

Native builds and preview execution must run on GitHub macOS runners only.
Actual login Keychain authorization after reboot requires verification on an installed user build;
fixtures use fake credentials/processes and cannot certify that real authorization state.
