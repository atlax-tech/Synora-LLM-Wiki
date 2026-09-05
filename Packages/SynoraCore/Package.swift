// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SynoraCore",
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "SynoraDomain", targets: ["SynoraDomain"]),
    .library(name: "SynoraPlatform", targets: ["SynoraPlatform"]),
    .library(name: "SynoraStoreProbe", targets: ["SynoraStoreProbe"]),
    .executable(name: "SynoraPlatformProbe", targets: ["SynoraPlatformProbe"])
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0")
  ],
  targets: [
    .target(name: "SynoraDomain"),
    .target(name: "SynoraPlatform"),
    .target(
      name: "SynoraStoreProbe",
      dependencies: ["SynoraDomain", .product(name: "GRDB", package: "GRDB.swift")]
    ),
    .executableTarget(name: "SynoraPlatformProbe", dependencies: ["SynoraPlatform"]),
    .testTarget(name: "SynoraDomainTests", dependencies: ["SynoraDomain"]),
    .testTarget(name: "SynoraPlatformTests", dependencies: ["SynoraPlatform"]),
    .testTarget(name: "SynoraStoreProbeTests", dependencies: ["SynoraStoreProbe"])
  ]
)
