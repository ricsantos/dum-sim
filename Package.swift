// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dum-sim",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "dum-sim", targets: ["dum-sim"]),
        .library(name: "DumSimKit", targets: ["DumSimKit"]),
    ],
    targets: [
        .target(name: "DumSimKit"),
        .executableTarget(name: "dum-sim", dependencies: ["DumSimKit"]),
    ]
)
