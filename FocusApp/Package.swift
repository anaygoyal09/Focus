// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FocusApp", targets: ["FocusApp"])
    ],
    targets: [
        .executableTarget(
            name: "FocusApp",
            path: "Sources/FocusApp"
        )
    ]
)
