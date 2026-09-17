# Notch cat preview · build 292

An original white/gray vector cat shares the existing closed-notch wings. It peeks from either side and nudges a widget only into unused space; widget + minimal is the per-wing limit. Music keeps its usual position. No extra row or external popup is added.

- Curious peeking, resting, completion greeting, and attention gesture.
- Task reactions coalesce and expire, do not mark tasks read, and do not replay historical results at launch.
- Pointer entry pauses motion so controls do not move under the cursor. Motion resumes after departure.
- Expanded panels, system overlays, hidden notch, and unsupported small heights suppress the cat.
- Appearance settings: cat on/off and task reactions on/off. Reduced Motion uses a still pose.
- No global input monitoring, network service, downloaded art, or new permissions.

Validation includes wing bounds/animation lifecycle/cue queue unit tests, actual native screenshots for all eight module combinations at three heights and both sides, and the existing English/Chinese layout and navigation regression suite. This is an experimental branch, not a stable release.
