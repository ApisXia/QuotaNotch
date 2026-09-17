# Pixel cat preview · build 294

Experimental build on feature/notch-cat, based on 1.03. Not a stable release.

- Uses the approved cream pixel cat, with four authored animation timelines.
- Measures actual free wing space; respects the widget + minimal width limit.
- Pointer entry hides decoration and holds its occupied width until departure.
- Expanded panels, important overlays, screen lock, sleep and Reduced Motion suppress the cat.
- One cat across all displays. Task reactions use fresh unread session events and coalesce bursts.
- Full-body movement currently appears on the left only; frontal cheek poses work on either side without mirroring markings.
- Rub either outer edge with two clear horizontal reversals within about one second to summon the cat on that side. The region follows the shell; layout movement alone does not count. Clicks, drags and scrolling cancel the gesture.
- Two settings: cat enabled and task reactions enabled.

The installer is ad-hoc signed, not notarized. Native layout regression checks and core tests run in the build workflow.
