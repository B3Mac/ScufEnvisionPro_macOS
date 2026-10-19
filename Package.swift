// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScufBridge",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ScufBridge", targets: ["ScufBridge"]),
    ],
    targets: [
        // Pure logic: decoding, profiles, mapping. No Apple-only frameworks, so it is unit-testable anywhere.
        .target(name: "ScufCore"),
        // The macOS menu-bar app.
        .executableTarget(
            name: "ScufBridge",
            dependencies: ["ScufCore"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreHID"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(name: "ScufCoreTests", dependencies: ["ScufCore"]),
    ],
    swiftLanguageModes: [.v5]
)
