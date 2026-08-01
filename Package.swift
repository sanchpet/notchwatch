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
    targets: [
        .executableTarget(
            name: "Notchwatch",
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
