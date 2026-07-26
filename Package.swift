// swift-tools-version: 5.10
// Copyright (C) 2025, Shyamal Suhana Chandra
// The tools used to build, test, and package the Yankovinator software.

import PackageDescription

let package = Package(
    name: "Yankovinator",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "Yankovinator",
            targets: ["Yankovinator"]),
        .executable(
            name: "yankovinator",
            targets: ["YankovinatorCLI"]),
        .executable(
            name: "keyword-generator",
            targets: ["KeywordGeneratorCLI"]),
        .executable(
            name: "benchmark",
            targets: ["BenchmarkCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swift-server/async-http-client", from: "1.20.0"),
    ],
    targets: [
        .target(
            name: "Yankovinator",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ]),
        .executableTarget(
            name: "YankovinatorCLI",
            dependencies: [
                "Yankovinator",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .executableTarget(
            name: "KeywordGeneratorCLI",
            dependencies: [
                "Yankovinator",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .executableTarget(
            name: "BenchmarkCLI",
            dependencies: [
                "Yankovinator",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .testTarget(
            name: "YankovinatorTests",
            dependencies: ["Yankovinator"]),
    ]
)

