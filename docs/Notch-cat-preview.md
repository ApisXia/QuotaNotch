# Pixel cat preview · build 295

Experimental build on feature/notch-cat, based on 1.03. Not a stable release.

- Uses the approved cream pixel cat, with distinct watching, dozing and rubbing sequences.
- Measures actual free wing space; respects the widget + minimal width limit.
- Pointer entry hides decoration and holds its occupied width until departure.
- Expanded panels, important overlays, screen lock, sleep and Reduced Motion suppress the cat.
- One cat across all displays. Task reactions use fresh unread session events and coalesce bursts.
- Full-body movement currently appears on the left only; frontal cheek poses work on either side without mirroring markings.
- Rub near either outer edge with two clear reversals within about 1.6 seconds; horizontal or vertical movement works. The sensing region follows the shell and has wider tolerance. If that wing is full, an available opposite wing responds. Clicks, drags and scrolling cancel the gesture.
- Cat heads are vertically centered in a fixed animation stage instead of hugging the bottom edge.
- Pointer sampling replaces unreliable mouseMoved delivery to transparent views; the sampler slows down away from the notch and stops when unavailable.
- Cloud tests exercise the production sampling timer through to visible animation using simulated pointer input; this is not a claim of manual physical-mouse validation.
- Two settings: cat enabled and task reactions enabled.

The installer is ad-hoc signed, not notarized. Native layout regression checks and core tests run in the build workflow.
