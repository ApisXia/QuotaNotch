# Bubble Shelf 预览指南 / Preview Guide

本指南说明如何使用 QuotaNotch 的悬浮收纳球（Floating bubble）。

This guide explains the Floating bubble and Shelf tab in QuotaNotch.

## 开始使用 / Start

1. 安装并打开 QuotaNotch，打开刘海后选择“收纳 / Shelf”。
2. 在 Shelf 页面打开“悬浮球 / Floating bubble”开关。它默认关闭；打开后会显示桌面悬浮球。关闭开关会隐藏悬浮球，但会保留已经保存的内容。
3. “固定到刘海 / Pin to notch”独立控制刘海中的收纳标记，默认关闭。它不会自动显示悬浮球，也不会改变已保存内容。

1. Install and open QuotaNotch, open the notch, and choose Shelf.
2. Turn on the “Floating bubble” switch in Shelf. It is off by default; turning it on shows the desktop bubble. Turning it off hides the bubble while keeping saved items.
3. “Pin to notch” is independent and off by default. It controls the compact Shelf mark in the notch; it does not show the Floating bubble or change saved content.

## 使用 / Use

- 把文件、文件夹、文本、网页链接或图像直接拖进桌面悬浮球。导入成功后，悬浮球会留在原来的位置并继续显示。
- Drag a file, folder, text, web link, or image directly into the desktop Floating bubble. After a successful import, the bubble stays where it was and remains visible.

- 拖动桌面悬浮球只会移动它的位置，不会导出内容。位置会保存并在下次启动时恢复。
- Dragging the desktop Floating bubble only moves it; it does not export content. Its position is saved and restored at the next launch.

- 点击桌面悬浮球会展开横向项目行：前三项清晰显示，第四项作为模糊预览；横向滑动或使用左右翻页按钮查看其他项目。每张卡片左上角的“×”只移除该 Shelf 条目。
- Clicking the desktop Floating bubble opens a horizontal row: three items are clear and a fourth appears as a blurred peek. Swipe horizontally or use the page buttons to view other items. The “×” at the top left of a card removes only that Shelf entry.

- 点击刘海中的收纳标记会打开 Shelf 页面列表。列表按最新加入的顺序排列；从列表行拖动单项可导出单项，点击单项的移除按钮可删除它。
- Clicking the compact notch Shelf mark opens the Shelf tab list. Items are newest first; drag an individual list row to export one item, or use its Remove button to delete it.

- 从刘海中的收纳标记横向拖出可导出整组已保存项目。取消拖动不会删除内容；把 Shelf 项目拖回悬浮球会按相同内容去重。
- Drag the compact notch Shelf mark outward to export the whole saved group. Cancelling a drag does not delete anything; dropping a Shelf item back onto the Floating bubble deduplicates matching content.

- 关闭“悬浮球 / Floating bubble”不会删除内容；重启后，已保存项目、开关状态和悬浮球位置都会保留。清空 Shelf 或移除项目不会删除原始文件或文件夹。
- Turning off “Floating bubble” does not delete content. Saved items, the switch state, and the bubble position survive restart. Clearing Shelf or removing an item never deletes the original file or folder.

## 支持范围 / Current limits

- 悬浮球接受实际文件和文件夹 URL、文本、网页 URL，以及可解码的 PNG、JPEG 或 TIFF 图像。
- The Floating bubble accepts real file and folder URLs, text, web URLs, and decodable PNG, JPEG, or TIFF images.

- 文件承诺（file promise）会明确提示不支持；不会把尚未生成的文件伪装成已保存项目。原始文件后来不可用时，Shelf 会保留条目并标记不可用，导出会报告问题。
- File promises are reported as unsupported; an unfinished promised file is never presented as saved. If an original file later becomes unavailable, Shelf keeps the entry, marks it unavailable, and reports the problem during export.

- 预览不读取其他应用的选区，不轮询全局剪贴板，也不要求 Accessibility 或 Finder Automation 授权。只会处理用户明确拖入悬浮球的内容。
- The preview does not read selections from other apps, poll the global clipboard, or require Accessibility or Finder Automation permission. It processes content only when the user explicitly drops it into the Floating bubble.
