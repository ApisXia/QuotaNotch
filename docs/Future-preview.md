# Future 286 preview

This preview stays on `future`; stable 1.02 is unchanged.

- Music and token retain their existing widgets. With token plus tasks or music plus tasks, each module gets an independent widget; tasks alone also use a widget.
- All three modules use a fixed layout: music left, quota widget and task minimal right. A static divider has equal space on both sides. There is no mode switching, swipe gesture, or hover arrow. Clicking tasks opens their panel directly.
- White paper outlines and counts combine with state-colored inner marks and labels: blue working, orange waiting, green completed, red failed, purple interrupted, gray unknown. Running motion stays inside the glyph.
- Clicking a task expands details inline; one row can be expanded at a time. Inputs and recent activity share the parent list's scrolling. Task clicks and notifications never create a details window.
- Selecting All expands the same notch panel downward, with fixed width and a screen-relative height cap. The filter bar stays above the scrolling list. Leaving the task tab or closing restores the original window height.
- Live task updates preserve the list order while browsing. Selecting All does not mark everything read: read receipts still require explicit opening and sufficient visible time.
- Token remains the only pinnable module, with one slot. Project/source information, quick filters, and local Codex/Claude Code monitoring remain available.
- Local transcript availability still governs coverage: Claude Chat/Cowork and remote sessions without local records are not monitored. Optional hooks observe approval waits and never approve operations.

Validation includes the existing parser/hook/read-receipt tests, all eight presence combinations, playback transitions, state-color screenshots, and actual same-window panel expansion/inline details/scrolling checks in English and Chinese.
