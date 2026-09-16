# Future 290 preview

This preview stays on `future`; stable 1.02 is unchanged.

Horizontal page switching covers the entire open header row, including its empty space and right-hand controls. Existing button clicks and body scrolling are preserved.

The task list uses 6-point state marks in the camera-side gap. Working uses a slowly rotating open ring; waiting uses two short bars; completed uses a ring with a center dot; errors use broken link ends; interrupted uses a small square; unknown uses a dashed ring. Color remains supplementary, only working animates, and Reduce Motion keeps it still. The task-name width and overall footprint stay unchanged.

- Hover anywhere in the open panel’s header row and swipe horizontally to move between Music, Quota, and Tasks. Each gesture moves one page, stops at either end, ignores momentum and vertical scrolling, and uses the same explicit task read behavior as a click. Closed widgets keep their existing behavior.

- Music and token retain their existing widgets. With token plus tasks or music plus tasks, each module gets an independent widget; tasks alone use a task glyph on the left and the two most recently active task names on the right. The left glyph prioritizes errors, then running, then the latest other state. The right wing reuses the widget-plus-minimal width budget; small state symbols sit in the camera-side gap to preserve text space. Source logos are reserved for quota.
- With all three modules, music stays left while quota and tasks share the right wing. A divider centered in a 10-point gap softly morphs into a short chevron on hover; click it or swipe to exchange widget/minimal without changing total width. Clicking a task opens its panel directly.
- Minimal modules use one centered graphic without numbers: a provider mark inside a thin quota arc, or a state-colored task paper glyph. Exact numbers remain in the widget and panel. Unknown quota has an empty dashed track; stale readings are muted.
- White paper outlines and counts combine with state-colored inner marks and labels: blue working, orange waiting, green completed, red failed, purple interrupted, gray unknown. Running motion stays inside the glyph.
- Task names lead each task row, with project/source on the second line. Compact details align with task names, and redundant calls to view details are omitted. Read history is slightly subdued, with relative activity times; active and unread tasks retain normal emphasis.
- Clicking a task expands details inline; one row can be expanded at a time. Inputs and recent activity share the parent list's scrolling. Task clicks and notifications never create a details window.
- The task panel keeps the original fixed height for every filter and inline detail state. All only changes the filter; the list scrolls beneath the fixed filter bar. Compact details use short Input/Latest rows with reduced spacing; long text can expand within the list without resizing the panel.
- All includes bounded history even after reading: choose 1 hour, 5 hours (default), or 1 day in Task monitoring settings. Each conversation still has one latest record. Active/waiting tasks stay regardless of age; reading remains separate from history retention.
- Live task updates preserve the list order while browsing. Selecting All does not mark everything read: read receipts still require explicit opening and sufficient visible time.
- Token remains the only pinnable module, with one slot. Project/source information, quick filters, and local Codex/Claude Code monitoring remain available.
- Local transcript availability still governs coverage: Claude Chat/Cowork and remote sessions without local records are not monitored. Optional hooks observe approval waits and never approve operations.

Validation includes the existing parser/hook/read-receipt tests, all eight presence combinations, playback transitions, state-color screenshots, and actual fixed-height panel/inline details/long-text/scrolling checks in English and Chinese.
