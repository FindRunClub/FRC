// swift-tools-version: 5.9
import PackageDescription

// FRCKit holds everything that doesn't need UIKit/SwiftUI: Strava models and
// networking, OAuth, the weekly schedule logic, and the demo data set.
// Keeping it UI-free means it can be unit-tested with `swift test`.
let package = Package(
    name: "FRCKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "FRCKit", targets: ["FRCKit"]),
    ],
    targets: [
        .target(name: "FRCKit"),
        .testTarget(name: "FRCKitTests", dependencies: ["FRCKit"]),
    ]
)
