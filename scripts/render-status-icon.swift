import AppKit
import SwiftUI

@main struct StatusIconPreview {
    @MainActor static func main() throws {
        let bundle = Bundle(path: CommandLine.arguments[1])!
        guard let icon = bundle.image(forResource: "QuotaStatus") else {
            fatalError("Missing compiled status icon")
        }
        precondition(icon.isTemplate, "Status icon must adapt to menu bar appearance")
        precondition(icon.size.width == 18 && icon.size.height == 18)
        let view = VStack(spacing: 16) {
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 24) {
                    Text(dark ? "Dark menu bar" : "Light menu bar").font(.system(size: 12))
                    Image(nsImage: icon).renderingMode(.template)
                    Image(nsImage: icon).renderingMode(.template).resizable().frame(width: 72, height: 72)
                }
                .foregroundStyle(dark ? Color.white : Color.black)
                .padding(20).frame(width: 360, height: 112)
                .background(dark ? Color.black : Color.white)
            }
        }.padding(16).background(Color.gray)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            fatalError("Status preview rendering failed")
        }
        try data.write(to: URL(fileURLWithPath: "build/QuotaNotch-dist/Status-Icon.png"))
        print("Verified compiled 18pt template icon and rendered light/dark previews")
    }
}
