// swift-tools-version: 5.9
import PackageDescription

// The same core source files are compiled into the Xcode app via its synchronized group.
let package = Package(
    name: "QuotaNotchCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "QuotaNotchCore", targets: ["QuotaNotchCore"])],
    targets: [
        .target(name: "QuotaNotchCore", path: "QuotaNotch/Core"),
        .testTarget(name: "QuotaNotchCoreTests", dependencies: ["QuotaNotchCore"],
                    path: "QuotaNotchTests", resources: [.process("Fixtures")])
    ]
)
