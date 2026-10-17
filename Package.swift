// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "BlitzClean",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "BlitzClean", targets: ["BlitzClean"])
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2"),
    .package(
      url: "https://github.com/metneo/LiquidGlass.git",
      revision: "36f81c85922aa3475b7e5bb210e69ffe20a2b377"),
  ],
  targets: [
    .executableTarget(
      name: "BlitzClean",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle"),
        .product(name: "LiquidGlass", package: "LiquidGlass"),
      ],
      resources: [.copy("Resources/Cuelume")]),
    .testTarget(name: "BlitzCleanTests", dependencies: ["BlitzClean"]),
  ]
)
