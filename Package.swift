// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftUIPullToRefreshPercent",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SwiftUIPullToRefreshPercent",
            targets: ["SwiftUIPullToRefreshPercent"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "SwiftUIPullToRefreshPercent",
            dependencies: []
        )
    ]
)
