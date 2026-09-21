# Native bubble material lab

This is an isolated macOS SwiftUI prototype for the QuotaNotch collection bubble. It uses a SwiftUI shape filled by a Metal shader, with the shader evaluating a curved pearly shell, broad reflected environment lights, Fresnel response, and restrained thin-film color. Pointer movement rotates the reflected environment. The color shift is confined to reflected light; there is no painted moving spot or fixed rainbow rim.

The standalone sample uses only built-in demo content: a photo-like still life and a designed document crop. The empty state contains nothing inside the shell. The populated state shows no more than those two previews, with restrained drift and cross-fading. The small layered notch outline stays separate from the content.

Three content arrangements are available: **A·轻叠** (inset pair), **B·浮游** (floating pair), and **C·柔藏** (soft stack). At a 64-point shell size, both previews keep their recognizable color and outline; the document crop hides its lettering. Arrival gathers the previews, holds for 0.9 seconds, then contracts them at the bubble's own center over 0.7 seconds.

## Build and preview on macOS

Run `scripts/build-and-capture.sh /path/to/output` on macOS with Xcode command line tools installed. The script compiles the app for Apple silicon and Intel, compiles the Metal shader, runs motion and render checks, and writes native PNG frames on dark and light environments, three 64-point populated variants, a same-time three-way comparison, a steady-state pointer-sweep MP4, a three-way comparison MP4, and a separate arrival MP4. It also packages `BubbleMaterialLab.app` in the output folder.

Open `BubbleMaterialLab.app` for the live pointer and arrival interaction. In the preview window, use the controls below the stage to show or hide the built-in demo previews, choose a composition, or play the arrival pass. The capture harness drives the same SwiftUI scene with fixed inputs so its output is repeatable.

The GitHub Actions workflow runs on `macos-15` and uploads the app, snapshots, movie, and a machine-readable capability report. It fails if Metal or the named SwiftUI shader cannot be loaded, or if SwiftUI image rendering does not produce useful native captures. A failed capability check is reported as unavailable; it is not counted as evidence of a successful material render.

## Implementation references

- Apple, [Creating visual effects with SwiftUI](https://developer.apple.com/documentation/SwiftUI/Creating-visual-effects-with-SwiftUI), WWDC24 sample project.
- Apple, [ShaderLibrary](https://developer.apple.com/documentation/swiftui/shaderlibrary) and [layerEffect](https://developer.apple.com/documentation/swiftui/view/layereffect(_:maxsampleoffset:isenabled:)) APIs.
- Apple, [ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer), used to capture the SwiftUI scene.
- The surface model follows thin-film optics qualitatively: a smooth, view-angle-dependent optical phase modulates only the environment reflection, with a low blend weight.
