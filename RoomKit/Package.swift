// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoomKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "RoomModel", targets: ["RoomModel"]),
        .library(name: "RoomGeometry", targets: ["RoomGeometry"]),
        .library(name: "RoomStore", targets: ["RoomStore"]),
    ],
    targets: [
        .target(name: "RoomModel"),
        .target(name: "RoomGeometry", dependencies: ["RoomModel"]),
        .target(name: "RoomStore", dependencies: ["RoomModel"]),
        .testTarget(name: "RoomModelTests", dependencies: ["RoomModel"]),
        .testTarget(name: "RoomGeometryTests", dependencies: ["RoomGeometry"]),
        .testTarget(name: "RoomStoreTests", dependencies: ["RoomStore"]),
    ]
)
