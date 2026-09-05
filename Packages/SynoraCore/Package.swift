// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SynoraCore",
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "SynoraDomain", targets: ["SynoraDomain"]),
    .library(name: "SynoraPlatform", targets: ["SynoraPlatform"]),
    .library(name: "SynoraStoreProbe", targets: ["SynoraStoreProbe"]),
    .library(name: "SynoraSkillProbe", targets: ["SynoraSkillProbe"]),
    .library(name: "SynoraBenchmark", targets: ["SynoraBenchmark"]),
    .executable(name: "SynoraBenchmarkGenerator", targets: ["SynoraBenchmarkGenerator"]),
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
    .target(name: "CWasmtimeShim", publicHeadersPath: "include"),
    .target(name: "SynoraSkillProbe", dependencies: ["CWasmtimeShim"]),
    .target(name: "SynoraBenchmark"),
    .executableTarget(name: "SynoraBenchmarkGenerator", dependencies: ["SynoraBenchmark"]),
    .executableTarget(name: "SynoraPlatformProbe", dependencies: ["SynoraPlatform"]),
    .executableTarget(name: "SynoraStoreCrashWriter", dependencies: ["SynoraStoreProbe"]),
    .testTarget(name: "SynoraDomainTests", dependencies: ["SynoraDomain"]),
    .testTarget(name: "SynoraPlatformTests", dependencies: ["SynoraPlatform"]),
    .testTarget(name: "SynoraStoreProbeTests", dependencies: ["SynoraStoreProbe"]),
    .testTarget(name: "SynoraStoreHeavyTests", dependencies: ["SynoraStoreProbe"]),
    .testTarget(name: "SynoraSkillProbeTests", dependencies: ["SynoraSkillProbe"]),
    .testTarget(name: "SynoraBenchmarkTests", dependencies: ["SynoraBenchmark"])
  ]
)
