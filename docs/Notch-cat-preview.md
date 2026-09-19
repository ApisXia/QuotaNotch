# Pixel cat preview · build 305

Experimental build on feature/notch-cat, based on 1.03. Not a stable release.

Task panels now expose a direct Read all action. The notch covers all current unread tasks; a selected project in the task window scopes the action to that project. Reading preserves history and live states, and later events become unread again.

- Uses the approved cream pixel cat, with distinct watching, dozing and rubbing sequences.
- Measures actual free wing space; respects the widget + minimal width limit.
- Each accepted rub plays once and withdraws even if the pointer stays over the shell. Repeated requests during playback do not restart, queue, or swap sides. Camera hover, clicks and scrolling request a short continuous retreat; there is no hidden spacer waiting for pointer departure.
- Expanded panels, important overlays, screen lock, sleep and Reduced Motion suppress the cat.
- One cat across all displays. Task reactions use fresh unread session events and coalesce bursts.
- Full-body movement currently appears on the left only; frontal cheek poses work on either side without mirroring markings.
- Rub near either outer edge with two clear reversals within about 1.6 seconds; horizontal or vertical movement works. The sensing region follows the shell and has wider tolerance. A full wing responds on that same side with a partial head, two small nudges, and withdrawal within three seconds. It borrows at most eight pixels inside the existing wing; the shell never exceeds its width limit. Clicks, drags and scrolling cancel the gesture.
- Cat heads are vertically centered in a fixed animation stage instead of hugging the bottom edge.
- Pointer sampling replaces unreliable mouseMoved delivery to transparent views; the sampler slows down away from the notch and stops when unavailable.
- Entry and retreat use monotonic elapsed time rather than accumulated frame sleeps, so delayed frames cannot stretch a short exit indefinitely.
- Task-only summaries register their right wing too. Crowded screenshot checks require visible cream cat pixels, not just unchanged shell bounds. Task status marks retain their camera-side overflow at rest.
- Widget measurement updates no longer restart the director. A changed active wing requests withdrawal.
- Cloud tests check natural completion, continuous retreat, repeated gestures, layout changes and same-side crowded responses. They exercise the production sampling timer through to visible animation using simulated pointer input; this is not a claim of manual physical-mouse validation.
- Two settings: cat enabled and task reactions enabled.

The installer is ad-hoc signed, not notarized. Native layout regression checks and core tests run in the build workflow.

Unified task-state presentation: one primary state controls shape, color, motion and badge count. Unread failures precede waiting, then running; other unread results follow recency. Waiting stays visible after reading. The fixed widget/minimal slots use page exchange, a double-bouncing bubble, a red cross, a closed green page, and purple twin bars for interruption. Cloud artifacts include a real-size animated glyph board.

Build 305 applies the approved folded-page design across widgets, minimal slots, task-only summaries, panel rows, the full task window and details. Every size, including six-point list marks, scales the same master artwork with identical details, line proportions and layers; interruption consistently uses purple twin bars. Existing module widths and task-title space remain fixed.

Approved final details: failed/interrupted folds and borders stay neutral; all resting documents share one stack geometry. The error cross is smaller, optically shifted left, and has a three-second breathing red halo without changing symbol size. Reduced Motion suppresses the halo. Reply dots align to the speech-bubble body, excluding the tail.
