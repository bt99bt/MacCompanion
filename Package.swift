// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacCompanion",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacCompanion", targets: ["MacCompanion"])
    ],
    targets: [
        .target(
            name: "MacCompanionCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "MacCompanion",
            dependencies: ["MacCompanionCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "MacCompanionSelfTest",
            dependencies: ["MacCompanionCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "MacCompanionFeiniuSmokeTest",
            dependencies: ["MacCompanionCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
