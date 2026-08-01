// swift-tools-version:5.9
import PackageDescription

// The app has no external dependencies: the OTLP receiver that pulled in
// opentelemetry-swift and swift-protobuf was removed, so the whole product is
// one executable target built against the system frameworks.
//
// scripts/build-app.sh turns this executable into the .app bundle — SwiftPM
// itself cannot produce one. Info.plist comes from Resources/Info.plist.in and
// the bundle's identity from scripts/product.env.
let package = Package(
    name: "Notchwatch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Notchwatch", targets: ["Notchwatch"]),
    ],
    // Test-only. The product itself still resolves to nothing external: this is
    // never linked into the app. Neither XCTest nor Testing ships with the
    // Command Line Tools, and a test that cannot run on the machine that writes
    // it is a test that does not get written.
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        // Pure logic, kept apart from the app so it can be tested without a
        // screen: the app target is an executable with @main and a great deal of
        // AppKit, none of which a unit test can or should stand up.
        .target(name: "NotchwatchKit"),
        .testTarget(
            name: "NotchwatchKitTests",
            dependencies: [
                "NotchwatchKit",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .executableTarget(
            name: "Notchwatch",
            dependencies: ["NotchwatchKit"],
            // Assets.xcassets needs actool, which ships with Xcode.app and not
            // with the Command Line Tools; it is kept as the source material for
            // regenerating Resources/AppIcon.icns, not as a build input.
            // AppIcon.icns is copied into the bundle by scripts/build-app.sh, so
            // it must not also become a SwiftPM resource bundle that no code
            // ever opens through Bundle.module.
            exclude: [
                "Assets.xcassets",
                "Resources",
            ]
        ),
    ]
)
