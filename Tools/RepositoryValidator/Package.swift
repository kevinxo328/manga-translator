// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RepositoryValidator",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RepositoryValidation", targets: ["RepositoryValidation"]),
        .executable(name: "repository-validator", targets: ["RepositoryValidator"])
    ],
    targets: [
        .target(name: "RepositoryValidation"),
        .executableTarget(name: "RepositoryValidator", dependencies: ["RepositoryValidation"]),
        .testTarget(name: "RepositoryValidationTests", dependencies: ["RepositoryValidation"])
    ]
)
