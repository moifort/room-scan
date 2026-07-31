// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoomKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "RoomModel", targets: ["RoomModel"]),
    ],
    targets: [
        .target(name: "RoomModel"),
        .testTarget(name: "RoomModelTests", dependencies: ["RoomModel"]),
    ]
)
