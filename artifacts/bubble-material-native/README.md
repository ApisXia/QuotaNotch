# Native bubble material lab

This is an isolated macOS SwiftUI prototype for the QuotaNotch collection bubble. It uses a SwiftUI shape filled by a Metal shader, with the shader evaluating a curved pearly shell, broad reflected environment lights, Fresnel response, and restrained thin-film color. Pointer movement rotates the reflected environment. The color shift is confined to reflected light; there is no painted moving spot or fixed rainbow rim.

The sample has two resting states: an empty shell and a populated shell with exactly three abstract drifting flakes. Its arrival pass gathers the flakes, holds them for 0.9 seconds, then contracts them into the bubble's own center over 0.7 seconds. The sample contains no count, text, or file glyph inside the bubble.

## Build and preview on macOS

Run `scripts/build-and-capture.sh /path/to/output` on macOS with Xcode command line tools installed. The script compiles the app for Apple silicon and Intel, compiles the Metal shader, runs motion and render checks, and writes native PNG frames, a steady-state pointer-sweep MP4, and a separate arrival MP4. It also packages `BubbleMaterialLab.app` in the output folder.

Open `BubbleMaterialLab.app` for the live pointer and arrival interaction. In the preview window, use the controls below the stage to show/hide flakes or play the arrival pass. The capture harness drives the same SwiftUI scene with fixed inputs so its output is repeatable.

The GitHub Actions workflow runs on `macos-15` and uploads the app, snapshots, movie, and a machine-readable capability report. It fails if Metal or the named SwiftUI shader cannot be loaded, or if SwiftUI image rendering does not produce useful native captures. A failed capability check is reported as unavailable; it is not counted as evidence of a successful material render.

## Implementation references

- Apple, [Creating visual effects with SwiftUI](https://developer.apple.com/documentation/SwiftUI/Creating-visual-effects-with-SwiftUI), WWDC24 sample project.
- Apple, [ShaderLibrary](https://developer.apple.com/documentation/swiftui/shaderlibrary) and [layerEffect](https://developer.apple.com/documentation/swiftui/view/layereffect(_:maxsampleoffset:isenabled:)) APIs.
- Apple, [ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer), used to capture the SwiftUI scene.
- The surface model follows thin-film optics qualitatively: a smooth, view-angle-dependent optical phase modulates only the environment reflection, with a low blend weight.
