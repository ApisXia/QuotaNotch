# File pocket preview

Enable **Settings → File tools → Enable file pocket**. The feature is independent
of the notch. Double-tap Shift near the destination, including while dragging
files in Finder. Global keyboard monitoring requires Accessibility access; the
menu bar and settings button also open the pocket without that permission.

- Drop on the left pouch to collect local files. References survive relaunch.
- Click the pouch to pour its contents into a scrollable list on the right.
- Click an item for Quick Look; × removes only its reference.
- Drop on Convert, Compress or Resize to process the current pocket plus the
  incoming files, deduplicated by their canonical paths. Clicking an action
  processes the pocket. Settings determine output format, quality and size.
- Work runs one image at a time off the main thread. Cancel preserves completed
  outputs. Show outputs reveals the generated files in Finder.
- Output names include the operation and a collision suffix. Originals and
  existing output files are never overwritten. JPEG transparency becomes white.
- Animated/multi-page images and images above 80 megapixels are rejected with a
  per-file reason. PNG compression is lossless; outputs that are not smaller are
  discarded. Video and audio operations are not in this preview.

macOS 26 uses native Liquid Glass with custom pouch/sector shapes. macOS 15 uses
an AppKit visual effect material. Pointer deformation is applied to the custom
shape; reduced motion and reduced transparency preferences are respected.

## Validation

`swift test --parallel` exercises Shift timing, chord/typing suppression,
symlink deduplication, collision naming, actual ImageIO conversion and resizing,
transparent-to-JPEG flattening, original preservation, and unsupported inputs.
The existing QuotaNotch workflow builds the universal app and installer on macOS.

Before release, check on a real Mac: Finder multi-file drags while double-tapping
Shift, permission grant/revocation, Quick Look, multiple monitors and screen-edge
clamping, background clicks passing through, native Liquid Glass on macOS 26+,
and cancelling a large batch. CI compilation does not validate those interactions.
