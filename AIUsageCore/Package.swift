// swift-tools-version: 5.9
//
//  Package.swift
//  AI Usage
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import PackageDescription

// Cross-platform core shared by the macOS and iOS apps and their widgets:
// models, provider auth + network fetchers, pricing, aggregation, formatting,
// localization and the App-Group widget snapshot.
let package = Package(
    name: "AIUsageCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "AIUsageCore", targets: ["AIUsageCore"]),
    ],
    targets: [
        .target(name: "AIUsageCore"),
    ]
)
