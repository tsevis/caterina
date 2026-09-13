// swift-tools-version: 6.2
import PackageDescription

// FlickrKit is the whole of the application's logic, and it is a package
// rather than an Xcode target so `swift build` and `swift test` work without
// Xcode. FlickrKit itself links neither SwiftUI nor AppKit — that is what
// makes it testable headlessly, and the rule is enforced by a test.
let package = Package(
    name: "FlickrKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FlickrKit", targets: ["FlickrKit"]),
        .library(name: "CaterinaUI", targets: ["CaterinaUI"]),
    ],
    targets: [
        .target(name: "FlickrKit"),

        // The splash art will live here rather than in the app target: `App/`
        // is an Xcode target `swift test` cannot see, and `Bundle.module`
        // resolves the same way in the app and in a test, where `Bundle.main`
        // would be the test runner.
        .target(
            name: "CaterinaUI",
            dependencies: ["FlickrKit"],
            resources: [.copy("Resources")]
        ),

        .testTarget(name: "FlickrKitTests", dependencies: ["FlickrKit"]),
        .testTarget(name: "CaterinaUITests", dependencies: ["CaterinaUI"]),
    ]
)
