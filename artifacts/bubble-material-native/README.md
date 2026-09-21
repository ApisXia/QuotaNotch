# Native bubble material lab

This is an isolated macOS SwiftUI prototype for the QuotaNotch collection bubble. It uses a SwiftUI shape filled by a Metal shader, with the shader evaluating a curved pearly shell, broad reflected environment lights, Fresnel response, and restrained thin-film color. Pointer movement rotates the reflected environment. The color shift is confined to reflected light; there is no painted moving spot or fixed rainbow rim.

The standalone sample uses built-in demo content only: a still-life image and native SwiftUI document, diagram, report, and field-note previews. Its count selector and synchronized comparison show 0, 1, 2, 3, and 6 examples. The empty state stays empty; one is a single calm preview, two use the preferred B·浮游 pair, three use an unequal layered arrangement, and six retain three stable preview slots with a quiet aggregate rear-edge cue. The cue does not claim to show the exact hidden items. At six, one stable slot cross-fades over 0.8 seconds, followed by a long dwell before the next slot changes; the loop reverses in the same staggered order. No item count appears inside the bubble. This remains sample content and is not connected to the future collector or shelf.

The pearly shell evaluates curved sphere normals against a moving reflected studio environment. Its curved softbox ribbon changes arc, width, and return toward grazing angles; restrained thin-film color remains localized to the reflection. The separate light-sweep movie holds the content and shell breathing still while the reflection travels. At a 64-point shell size, the same count layouts remain within the shell and simplify their small document details. Arrival gathers the previews, holds for 0.9 seconds, then contracts them at the bubble's own center over 0.7 seconds.

## Build and preview on macOS

Run `scripts/build-and-capture.sh /path/to/output` on macOS with Xcode command line tools installed. The script compiles the app for Apple silicon and Intel, compiles the Metal shader, runs layout, motion, and render checks, and writes native PNG frames for all five counts at 226 and 64 points, a synchronized count comparison, center/rim lighting poses, patterned-background transmission, and arrival states. It also writes a 12-second five-count comparison movie, an isolated light sweep, an arrival movie, and packages `BubbleMaterialLab.app` in the output folder.

Open `BubbleMaterialLab.app` for the live pointer and arrival interaction. In the preview window, use the count selector to choose a built-in sample state or play the arrival pass. The capture harness drives the same SwiftUI scene with fixed inputs so its output is repeatable.

The GitHub Actions workflow runs on `macos-15` and uploads the app, snapshots, movie, and a machine-readable capability report. It fails if Metal or the named SwiftUI shader cannot be loaded, or if SwiftUI image rendering does not produce useful native captures. A failed capability check is reported as unavailable; it is not counted as evidence of a successful material render.

## Implementation references

- Apple, [Creating visual effects with SwiftUI](https://developer.apple.com/documentation/SwiftUI/Creating-visual-effects-with-SwiftUI), WWDC24 sample project.
- Apple, [ShaderLibrary](https://developer.apple.com/documentation/swiftui/shaderlibrary) and [layerEffect](https://developer.apple.com/documentation/swiftui/view/layereffect(_:maxsampleoffset:isenabled:)) APIs.
- Apple, [ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer), used to capture the SwiftUI scene.
- The surface model follows thin-film optics qualitatively: a smooth, view-angle-dependent optical phase modulates only the environment reflection, with a low blend weight.
