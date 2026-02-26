// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RxBurn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RxBurn",
            path: "Sources"
        )
    ]
)
