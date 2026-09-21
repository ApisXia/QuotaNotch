# Bubble Shelf 预览指南 / Preview Guide

本指南说明 QuotaNotch 收纳（Shelf）预览的实际使用方式和支持范围。

This guide describes how to use the QuotaNotch Shelf preview and what it supports.

## 开始使用 / Start

1. 安装并打开 QuotaNotch。打开刘海，在标签栏选择“收纳 / Shelf”。
2. 在 Shelf 页面手动打开“接收 / Receiving”。它默认关闭；暂停接收会保留已经保存的内容。
3. 如果系统要求授权，请在“系统设置 → 隐私与安全性 → 辅助功能”允许 QuotaNotch。Finder 的额外读取授权只应在你明确执行 Finder 选择读取操作后按系统提示允许；被动接收不会自行请求 Automation 授权。

1. Install and open QuotaNotch. Open the notch and choose the Shelf tab.
2. Turn on the Receiving switch in Shelf. It is off by default; pausing keeps items already saved.
3. If macOS asks for permission, allow QuotaNotch in System Settings → Privacy & Security → Accessibility. Finder’s additional selection access should be approved only after you explicitly start a Finder selection read; passive receiving does not request Automation consent.

## 使用 / Use

- 在支持的应用中选择文本，或在 Finder 中选中文件/文件夹，然后点击选择旁边出现的收纳气泡以保存。也可以把支持的内容直接拖进 Shelf。
- Select text in a supported app, or select files/folders in Finder, then click the nearby Shelf bubble to save the candidate. You can also drag supported content directly into Shelf.

- 当关闭状态的 Shelf 图标已经显示时，把指针移到图标上并向上滚动可开启接收，向下滚动可暂停。点击图标会打开整个 Shelf 页面；向任意方向拖动图标会导出全部项目。图标不会因为悬停而自动开启接收。
- When the closed Shelf glyph is visible, move the pointer over it and scroll up to start receiving or down to pause. Click the glyph to open the full Shelf page; drag it in any direction to export all items. Hovering never turns receiving on by itself.

- 在打开的 Shelf 中，拖动单行的图标可导出单个项目。取消拖动不会删除或改变 Shelf 内容。
- In the open Shelf, drag a row’s icon to export one item. Cancelling a drag does not remove or change Shelf contents.

- 接收模式至少手动设置过一次后，即使暂停，关闭状态的 Shelf 图标也会保留；从未设置且没有内容时，关闭状态可能没有 Shelf 图标。
- After Receiving has been set manually once, the closed Shelf glyph remains available while paused. With no saved content and no prior setup, the closed notch may show no Shelf glyph.

- 新项目排在最前面；相同内容会去重并提升到最前。点击“清空”或单项移除只删除 Shelf 条目和它管理的缩略图；已经准备好的导出文件可能暂时保留以完成当前拖动，不会删除原始文件或文件夹。
- New items appear first; duplicates are promoted instead of copied. Clear and item removal delete Shelf entries and owned thumbnails. Prepared export files may remain temporarily so an active drag can finish; original files and folders are left untouched.

- 内容和暂停状态会在重启后保留。原始文件后来不可用时，Shelf 会保留条目并标记不可用，导出会报告问题而不会伪造成功。
- Items and the paused state survive restart. If an original file later becomes unavailable, Shelf keeps the entry and marks it unavailable; export reports the problem instead of claiming success.

## 当前支持范围 / Current limits

- 选择捕获依赖 macOS Accessibility 的 AX 文本和选择接口；不是所有应用都会暴露可读取的文本或选择内容。Finder 文件捕获使用实际的 file URL。
- Selection capture depends on macOS Accessibility AX text and selection attributes; some apps expose no readable selection. Finder file capture uses real file URLs.

- 粘贴板和拖放支持实际文件/文件夹 URL、文本、网页 URL，以及可解码的 PNG/TIFF 图像。文件承诺（file promise）目前会明确拒绝；不会伪造一个已经完成的文件。
- Pasteboard and drag-and-drop accept real file/folder URLs, text, web URLs, and decodable PNG/TIFF images. File promises are explicitly rejected for now; the preview does not pretend a promised file has arrived.

- 这份预览不轮询全局剪贴板；可读取的内容取决于应用提供的选择接口。它没有音频或音乐控制手势；上下滚动只切换 Shelf 接收模式，拖动任意方向都可导出。
- The preview reads only selections exposed by the current app and does not poll the global clipboard. It has no audio or music gestures: vertical scrolling toggles Shelf receiving, and dragging in any direction exports saved items.
