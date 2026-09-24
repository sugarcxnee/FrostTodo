// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FrostTodo",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "FrostTodo",
            path: "Sources/FrostTodo"
        ),
        .executableTarget(
            name: "FrostTodoApp",
            dependencies: ["FrostTodo"],
            path: "Sources/FrostTodoApp"
        ),
        .testTarget(
            name: "FrostTodoTests",
            dependencies: ["FrostTodo"],
            path: "Tests/FrostTodoTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
