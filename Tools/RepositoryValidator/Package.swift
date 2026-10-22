// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RepositoryValidator",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RepositoryValidation", targets: ["RepositoryValidation"]),
        .executable(name: "repository-validator", targets: ["RepositoryValidator"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")
    ],
    targets: [
        .target(
            name: "RepositoryValidation",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .executableTarget(name: "RepositoryValidator", dependencies: ["RepositoryValidation"]),
        .testTarget(name: "RepositoryValidationTests", dependencies: ["RepositoryValidation"])
    ]
)
