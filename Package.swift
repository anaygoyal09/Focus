// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Focus",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "FocusApp", targets: ["FocusApp"])
    ],
    targets: [
        .executableTarget(
            name: "FocusApp",
            path: "Sources",
            exclude: ["Info.plist"],
            resources: []
        )
    ]
)
