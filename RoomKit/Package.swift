// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoomKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "RoomModel", targets: ["RoomModel"]),
        .library(name: "RoomGeometry", targets: ["RoomGeometry"]),
        .library(name: "RoomStore", targets: ["RoomStore"]),
        .library(name: "RoomViewer", targets: ["RoomViewer"]),
        .library(name: "RoomCapture", targets: ["RoomCapture"]),
        .library(name: "RoomDressing", targets: ["RoomDressing"]),
    ],
    targets: [
        .target(name: "RoomModel"),
        .target(name: "RoomGeometry", dependencies: ["RoomModel"]),
        .target(name: "RoomDressing", dependencies: ["RoomModel"]),
        .target(name: "RoomStore", dependencies: ["RoomModel", "RoomDressing"]),
        .target(name: "RoomViewer", dependencies: ["RoomModel", "RoomGeometry", "RoomDressing"]),
        .target(name: "RoomCapture", dependencies: ["RoomModel", "RoomGeometry", "RoomDressing"]),
        .testTarget(name: "RoomModelTests", dependencies: ["RoomModel"]),
        .testTarget(name: "RoomGeometryTests", dependencies: ["RoomGeometry"]),
        .testTarget(name: "RoomStoreTests", dependencies: ["RoomStore"]),
        .testTarget(name: "RoomDressingTests", dependencies: ["RoomDressing", "RoomModel"]),
    ]
)
