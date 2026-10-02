// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct FilePocketSettings: View {
    @ObservedObject private var store = FilePocketStore.shared
    @ObservedObject private var controller = FilePocketController.shared
    var body: some View {
        Form {
            Section {
                Toggle(PocketText.t("启用文件兜", "Enable file pocket"), isOn: $store.enabled)
                Text(PocketText.t("双击 Shift，在鼠标旁唤出。拖入左侧暂存，拖到右侧直接处理兜内和新拖入的文件。", "Double-tap Shift to open at the pointer. Drop on the pocket to collect files; drop on an action to process both stored and incoming files."))
                    .font(.callout).foregroundStyle(.secondary)
                Button(PocketText.t("打开文件兜", "Open file pocket")) { controller.show() }.disabled(!store.enabled)
                if !controller.accessibilityGranted {
                    Text(PocketText.t("跨应用双击 Shift 需要辅助功能权限；也可用菜单栏或上方按钮打开。", "Double-tap Shift across apps requires Accessibility access. You can also open the pocket from the menu bar or the button above."))
                        .font(.callout).foregroundStyle(.secondary)
                    Button(PocketText.t("允许全局快捷键…", "Allow global shortcut…")) { controller.requestAccessibility() }
                        .disabled(!store.enabled)
                }
            } header: { Text(PocketText.t("文件兜", "File pocket")) }
            Section {
                Picker(PocketText.t("转换为", "Convert to"), selection: $store.format) {
                    ForEach(PocketImageFormat.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent(PocketText.t("JPEG / HEIC 质量", "JPEG / HEIC quality")) {
                    HStack {
                        Slider(value: $store.quality, in: 0.1...1, step: 0.05).frame(maxWidth: 170)
                        Text("\(Int(store.quality * 100))%").monospacedDigit().frame(width: 42)
                    }
                }
                Picker(PocketText.t("缩放后最长边", "Resize longest edge"), selection: $store.longestEdge) {
                    ForEach([640, 1280, 1920, 2560, 3840], id: \.self) { Text("\($0) px").tag($0) }
                    if ![640, 1280, 1920, 2560, 3840].contains(store.longestEdge) { Text("\(store.longestEdge) px").tag(store.longestEdge) }
                }
                Text(PocketText.t("缩放保持比例，不放大小图。压缩和缩放保留 JPEG、PNG、HEIC 格式；其他静态图片使用所选输出格式。PNG 无损重编码不一定更小。", "Resize preserves aspect ratio and never enlarges images. Compression and resize keep JPEG, PNG or HEIC; other still images use the selected output format. Lossless PNG re-encoding may not reduce size."))
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text(PocketText.t("图片默认操作", "Default image actions")) }
            Section {
                Text(PocketText.t("结果保存在原文件旁，自动避开重名；原文件不变。透明图片转 JPEG 时使用白色背景。动画及多页图片会显示失败原因。", "Outputs are saved beside the original with unique names. Originals are unchanged. JPEG uses a white background for transparency. Animated and multi-page images show an error."))
                    .font(.callout).foregroundStyle(.secondary)
                Text(PocketText.t("暂存保存文件引用，重启后恢复。移出暂存不会删除原文件。", "The pocket remembers file references across restarts. Removing an item never deletes the original."))
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text(PocketText.t("文件保存", "Saving files")) }
        }
        .navigationTitle(PocketText.t("文件工具", "File tools"))
    }
}
