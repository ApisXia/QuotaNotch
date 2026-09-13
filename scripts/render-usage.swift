import SwiftUI
import AppKit

@main
struct RenderUsage {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let content = UsageSheet().environment(\.locale, Locale(identifier: language)).preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("Rendering failed")
        }
        let destination = CommandLine.arguments.last!
        try data.write(to: URL(fileURLWithPath: destination))
        print("Rendered", language, "AI usage layout")
    }
}

private struct UsageSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QuotaNotch").font(.system(size: 22, weight: .semibold))
            Text("AI 额度").font(.headline)
            VStack(spacing: 8) {
                HStack(spacing: 2) {
                    QuotaProviderTab(title: "Claude", brand: .claude, selected: true)
                    QuotaProviderTab(title: "Codex", brand: .codex, selected: false)
                    Spacer()
                }.padding(3).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                HStack(spacing: 8) {
                    QuotaWindowTile(title: QuotaText.localized("5 小时"), percent: 58,
                                    reset: Date(timeIntervalSince1970: 1789416000), accent: QuotaBrand.claude.color, pinned: true)
                    QuotaWindowTile(title: QuotaText.localized("7 天"), percent: 25,
                                    reset: Date(timeIntervalSince1970: 1789588800), accent: QuotaBrand.claude.color)
                }
                HStack(spacing: 10) {
                    Label("Claude · " + QuotaText.localized("5 小时"), systemImage: "pin.fill")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    QuotaRefreshStamp(updated: Date(timeIntervalSince1970: 1789400000),
                                      next: Date(timeIntervalSince1970: 1789400900))
                    Image(systemName: "gearshape")
                    Label("刷新", systemImage: "arrow.clockwise").fixedSize()
                    Label("暂停", systemImage: "pause").fixedSize()
                }
                .font(.system(size: 11))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(8).background(.black, in: RoundedRectangle(cornerRadius: 16))
            HStack {
                Label("主页", systemImage: "house.fill")
                Label("日历", systemImage: "calendar")
                Spacer()
                Text("跟随系统").foregroundStyle(.secondary)
            }.font(.system(size: 12))
            Text("Native SwiftUI components · fixture values").font(.caption).foregroundStyle(.secondary)
        }
        .padding(22).frame(width: 604).foregroundStyle(.white).background(Color(white: 0.075))
    }
}
