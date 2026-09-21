// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dum-sim",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "dum-sim", targets: ["dum-sim"]),
        .executable(name: "DumSimApp", targets: ["DumSimApp"]),
        .library(name: "DumSimKit", targets: ["DumSimKit"]),
        .executable(name: "make-icon", targets: ["make-icon"]),
    ],
    targets: [
        .target(name: "DumSimKit"),
        .executableTarget(name: "dum-sim", dependencies: ["DumSimKit"]),
        .target(name: "DumSimIcon"),
        .executableTarget(name: "DumSimApp", dependencies: ["DumSimKit", "DumSimIcon"]),
        .executableTarget(name: "make-icon", dependencies: ["DumSimIcon"]),
    ]
)
