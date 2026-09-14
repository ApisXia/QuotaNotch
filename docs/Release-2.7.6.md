# QuotaNotch 2.7.6

- Remaining quota transitions from brand color to yellow between 45–35%, then to red between 15–5%. Subtle static glow follows the same transitions. Zero quota retains a red track; stale readings do not warn.
- Compact rings and every expanded quota window share the same styling. Numbers stay white and provider marks keep their brand color.
- Hover or click a closed notch to open the content under the pointer. Music + quota uses left/right halves; a single task owns both halves. The pointer is sampled after the hover delay and pages never follow it once expanded.
- About now shows the selected icon, version, manual update entry, repository and license credits. English and Chinese README pages are shorter.

No automatic-update activation or release publication is included in this change.

- Music keeps its configured pause residency before yielding to quota. Switching from quota to music uses opacity without a downward slide. Cancelled residency timers no longer expire a newer pause.
