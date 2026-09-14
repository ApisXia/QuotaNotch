import SwiftUI
import AppKit

@main struct WarningPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let r = ImageRenderer(content: WarningSheet().preferredColorScheme(.dark))
        r.scale = 2
        guard let cg = r.cgImage,
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { fatalError() }
        try data.write(to: URL(fileURLWithPath: "build/QuotaNotch-dist/Warning-UX.png"))
    }
}
struct WarningSheet: View {
    let values: [Double] = [50, 45, 40, 35, 15, 10, 5, 0]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Quota warning · native components · sample data").font(.headline)
            ForEach(Array(QuotaBrand.allCases.enumerated()), id: \.offset) { _, brand in
                HStack(spacing: 12) {
                    QuotaBrandMark(brand: brand).frame(width: 20, height: 20)
                    ForEach(values, id: \.self) { value in
                        VStack(spacing: 8) {
                            CompactQuotaGauge(brand: brand, percent: value, showsNumbers: true, size: 20)
                            QuotaWindowTile(title: "Window", percent: value, reset: nil, accent: brand.color)
                        }.frame(width: 102)
                    }
                }
            }
            HStack(spacing: 18) {
                Text("Stale / unknown: no warning")
                CompactQuotaGauge(brand: .claude, percent: 0, stale: true, showsNumbers: true, size: 20)
                CompactQuotaGauge(brand: .claude, percent: nil, size: 20)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(24).foregroundStyle(.white).background(Color.black)
    }
}
