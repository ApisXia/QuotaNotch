# Future 282 preview

This preview stays on `future`; stable 1.02 is unchanged.

- Tasks now share the closed notch row with the existing quota gauge. They no longer add a persistent row below the notch.
- The task summary uses a small paper glyph and count. Horizontal swipe or the separator button expands/minimizes it. Hovering the separator reveals a chevron; only the central notch hover opens the full panel.
- Token keeps its existing appearance and remains the only pinnable module, with one pin slot. Project pins were removed.
- Running and approval-waiting tasks remain visible. Finished unread tasks disappear from the compact summary after reading; reading never resolves a pending approval. Each task counts once, including mixed activity.
- Read receipts require an explicitly opened task panel and a visible row; hover alone does not mark tasks read. Finished rows stay in the full list until cleared.
- Four quick filters: active, completed, other, all. Larger provider/source labels, restrained colors, and custom paper glyphs replace success/error symbols.
- Local Claude Code transcripts are read alongside Codex, with current request/tool activity where available. Code sessions from Desktop or VS Code appear when they leave local transcripts; source labels depend on transcript metadata. Claude Chat/Cowork and remote sessions without local records are not covered.
- Optional Codex and Claude Code event connections detect approval waits. They preserve other hooks and never approve operations. Existing connections can be updated from monitoring settings.
- Codex opens the original app/extension task. Claude Code currently opens local details and offers its exact CLI resume command; there is no verified universal link to an existing Desktop Code session.

Validation includes parser and repository fixtures, all read/unread state combinations, repeated approvals, hook preservation/privacy, universal app compilation, and actual English/Chinese UI screenshots at 24/32/38-pixel notch heights.
