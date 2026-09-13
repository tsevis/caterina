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
        .library(name: "CaterinaLibrary", targets: ["CaterinaLibrary"]),
        .library(name: "CaterinaUI", targets: ["CaterinaUI"]),
    ],
    // The only third-party code, and it is kept out of FlickrKit: SQLite is how
    // the local copy of the library is stored, not how Flickr is spoken to.
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .target(name: "FlickrKit"),

        // The local copy of your library: every photo's metadata in SQLite, so
        // Organize filters instantly and Insights keeps history past Flickr's
        // 28 days.
        .target(
            name: "CaterinaLibrary",
            dependencies: ["FlickrKit", .product(name: "GRDB", package: "GRDB.swift")]
        ),

        // The splash art will live here rather than in the app target: `App/`
        // is an Xcode target `swift test` cannot see, and `Bundle.module`
        // resolves the same way in the app and in a test, where `Bundle.main`
        // would be the test runner.
        .target(
            name: "CaterinaUI",
            dependencies: ["FlickrKit", "CaterinaLibrary"],
            resources: [.copy("Resources")]
        ),

        .testTarget(name: "FlickrKitTests", dependencies: ["FlickrKit"]),
        .testTarget(name: "CaterinaLibraryTests", dependencies: ["CaterinaLibrary"]),
        .testTarget(name: "CaterinaUITests", dependencies: ["CaterinaUI"]),
    ]
)
