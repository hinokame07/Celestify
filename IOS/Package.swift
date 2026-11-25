// swift-tools-version: 5.10
//
//  Package.swift
//  Celestify (iOS)
//
//  Swift Package Manager manifest provided alongside Celestify.xcodeproj and project.yml
//  for SourceKit-LSP indexing and `xcodebuild -scheme Celestify -destination 'platform=iOS Simulator,...' test`.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import PackageDescription

let package = Package(
    name: "Celestify",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Celestify",
            targets: ["Celestify"]
        )
    ],
    targets: [
        .target(
            name: "Celestify",
            path: "Celestify",
            exclude: [
                "App/CelestifyApp.swift",
                "Resources/Assets.xcassets",
                "Resources/Localizable.xcstrings"
            ],
            resources: [
                .process("Resources/Spotify")
            ]
        ),
        .testTarget(
            name: "CelestifyTests",
            dependencies: ["Celestify"],
            path: "Tests/CelestifyTests"
        )
    ]
)
