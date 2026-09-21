# Bubble Shelf 预览指南 / Preview Guide

这是一份 `feature/bubble-native-material` 的测试预览说明。它描述收纳（Shelf）功能的实际范围，不代表正式发布承诺。

This guide covers the `feature/bubble-native-material` test preview. It describes the current Shelf behavior and does not promise a production release.

## 启用 / Enable

1. 使用 `SETTINGS_PREVIEW` 构建测试版本，并启用测试功能 `enableShelfTab`。打开设置中的“收纳 / Shelf”标签，或在刘海打开后切换到 Shelf 标签。
2. “接收 / Receiving”默认关闭。手动打开后，QuotaNotch 才会读取前台应用的可访问性选择；暂停只停止接收，不清除已有内容。
3. 首次打开接收模式时，按提示在“系统设置 → 隐私与安全性 → 辅助功能”允许 QuotaNotch。Finder 的 Automation 读取是另一项明确的用户操作：让 Finder 置前并选中文件，再使用测试界面的显式重试；被动监听不会自行触发 Automation 授权。

1. Build the test configuration with `SETTINGS_PREVIEW` and enable the `enableShelfTab` test feature. Open Settings → Shelf, or switch to the Shelf tab after opening the notch.
2. Receiving is off by default. Turn it on manually before QuotaNotch reads a supported selection from the frontmost app. Pausing stops capture and keeps saved items.
3. The first receive-mode enable may ask for QuotaNotch Accessibility access in System Settings → Privacy & Security → Accessibility. Finder Automation is a separate explicit action: bring Finder forward with a file selected, then use the test surface’s explicit retry. Passive monitoring does not request Automation consent.

## 使用 / Use

- 在支持的应用中选择文本，或在 Finder 中选中文件/文件夹，然后点击选择旁边出现的收纳气泡以保存。也可以把支持的内容直接拖进 Shelf。
- Select text in a supported app, or select files/folders in Finder, then click the nearby Shelf bubble to save the candidate. You can also drag supported content directly into Shelf.

- 悬停到关闭状态的刘海可看到 Shelf 小气泡；在气泡上向上滚动开启接收，向下滚动暂停。点击 Shelf 图标会打开整个 Shelf 页面；拖动关闭状态图标会导出全部项目。
- Hovering over the closed notch reveals the Shelf bubble. Scroll up on it to start receiving and down to pause. Click the Shelf glyph to open the full Shelf page; drag the closed glyph to export all items.

- 在打开的 Shelf 中，拖动单行的图标可导出单个项目。取消拖动不会删除或改变 Shelf 内容。
- In the open Shelf, drag a row’s icon to export one item. Cancelling a drag does not remove or change Shelf contents.

- 新项目排在最前面；相同内容会去重并提升到最前。点击“清空”或单项移除只清理 Shelf 自己保存的副本、缩略图和导出缓存，不会删除原始文件或文件夹。
- New items appear first; duplicates are promoted instead of copied. Clear and item removal delete only Shelf-owned copies, thumbnails, and export cache. Original files and folders are left untouched.

- 内容和暂停状态会在重启后保留。原始文件后来不可用时，Shelf 会保留条目并标记不可用，导出会报告问题而不会伪造成功。
- Items and the paused state survive restart. If an original file later becomes unavailable, Shelf keeps the entry and marks it unavailable; export reports the problem instead of claiming success.

## 当前支持范围 / Current limits

- 选择捕获依赖 macOS Accessibility 的 AX 文本和选择接口；不是所有应用都会暴露可读取的文本或选择内容。Finder 文件捕获使用实际的 file URL。
- Selection capture depends on macOS Accessibility AX text and selection attributes; some apps expose no readable selection. Finder file capture uses real file URLs.

- 粘贴板和拖放支持实际文件/文件夹 URL、文本、网页 URL，以及可解码的 PNG/TIFF 图像。文件承诺（file promise）目前会明确拒绝；不会伪造一个已经完成的文件。
- Pasteboard and drag-and-drop accept real file/folder URLs, text, web URLs, and decodable PNG/TIFF images. File promises are explicitly rejected for now; the preview does not pretend a promised file has arrived.

- 这份预览不轮询全局剪贴板，也不宣称覆盖所有应用。它没有音频手势或音乐控制手势；上下滚动只切换 Shelf 接收模式，横向拖动用于导出。
- This preview does not poll the global clipboard or claim support for every app. It has no audio or music gestures: vertical scrolling toggles Shelf receiving, and horizontal dragging exports saved items.
