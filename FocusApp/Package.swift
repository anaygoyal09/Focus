// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FocusApp",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "FocusApp", targets: ["FocusApp"])
    ],
    targets: [
        .executableTarget(
            name: "FocusApp",
            path: "Sources/FocusApp",
            exclude: ["Info.plist", "Views/PasswordPromptView 2.swift"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
