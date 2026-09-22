# Bubble Shelf 预览指南 / Preview Guide

本指南说明如何使用 QuotaNotch 的固定收纳球（Shelf holder）。

This guide explains the fixed, movable Shelf holder in QuotaNotch.

## 开始使用 / Start

1. 安装并打开 QuotaNotch，打开刘海后选择“收纳 / Shelf”。
2. 在 Shelf 页面手动打开“接收 / Receiving”。它默认关闭；打开后会显示收纳球。暂停接收会隐藏收纳球，但会保留已经保存的内容。
3. 收纳球可以拖到屏幕上的其他位置，位置会被保存并在下次启动时恢复。使用 Shelf 的固定选项可将它与刘海关联；该选项默认关闭。

1. Install and open QuotaNotch, open the notch, and choose Shelf.
2. Turn on Receiving in Shelf. It is off by default; turning it on shows the holder. Pausing hides the holder while keeping saved items.
3. Drag the holder to another place on the screen when needed. Its position is saved and restored at the next launch. The Shelf pin option keeps it associated with the notch and is off by default.

## 使用 / Use

- 把文件、文件夹、文本、网页链接或图像直接拖进收纳球。导入成功后，收纳球会留在原来的位置并继续显示。
- Drag a file, folder, text, web link, or image directly into the holder. After a successful import, the holder stays where it was and remains visible.

- 点击收纳球展开 Shelf，查看已保存项目。项目按最新加入的顺序排列；点击单项的移除按钮可删除 Shelf 条目。
- Click the holder to expand Shelf and view saved items. Items are listed newest first; use an item's Remove button to delete that Shelf entry.

- 在 Shelf 中拖动单项可以导出它；也可以把整组项目拖到支持接收的应用。取消拖动不会删除内容。把 Shelf 项目拖回收纳球会按相同内容去重。
- Drag one item from Shelf to export it, or drag the group to an application that accepts it. Cancelling a drag does not delete anything. Dragging a Shelf item back into the holder deduplicates matching content.

- 暂停接收不会删除内容；重启后，已保存项目、暂停状态和收纳球位置都会保留。清空 Shelf 或移除项目不会删除原始文件或文件夹。
- Pausing Receiving does not delete content. Saved items, the paused state, and the holder position survive restart. Clearing Shelf or removing an item never deletes the original file or folder.

## 支持范围 / Current limits

- 收纳球接受实际文件和文件夹 URL、文本、网页 URL，以及可解码的 PNG、JPEG 或 TIFF 图像。
- The holder accepts real file and folder URLs, text, web URLs, and decodable PNG, JPEG, or TIFF images.

- 文件承诺（file promise）会明确提示不支持；不会把尚未生成的文件伪装成已保存项目。原始文件后来不可用时，Shelf 会保留条目并标记不可用，导出会报告问题。
- File promises are reported as unsupported; an unfinished promised file is never presented as saved. If an original file later becomes unavailable, Shelf keeps the entry, marks it unavailable, and reports the problem during export.

- 预览不读取其他应用的选区，不轮询全局剪贴板，也不要求 Accessibility 或 Finder Automation 授权。只会处理用户明确拖入收纳球的内容。
- The preview does not read selections from other apps, poll the global clipboard, or require Accessibility or Finder Automation permission. It processes content only when the user explicitly drops it into the holder.
