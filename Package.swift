// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DuplicateFinder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DuplicateFinder", targets: ["DuplicateFinder"])
    ],
    targets: [
        .executableTarget(
            name: "DuplicateFinder",
            path: "Sources/DuplicateFinder"
        )
    ]
)
