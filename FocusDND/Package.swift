// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusDND",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FocusDND", targets: ["FocusDND"])
    ],
    targets: [
        .executableTarget(
            name: "FocusDND",
            path: "Sources/FocusDND"
        )
    ]
)
