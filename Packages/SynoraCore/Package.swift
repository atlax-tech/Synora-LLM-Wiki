// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SynoraCore",
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "SynoraDomain", targets: ["SynoraDomain"]),
    .library(name: "SynoraPlatform", targets: ["SynoraPlatform"]),
    .executable(name: "SynoraPlatformProbe", targets: ["SynoraPlatformProbe"])
  ],
  targets: [
    .target(name: "SynoraDomain"),
    .target(name: "SynoraPlatform"),
    .executableTarget(name: "SynoraPlatformProbe", dependencies: ["SynoraPlatform"]),
    .testTarget(name: "SynoraDomainTests", dependencies: ["SynoraDomain"]),
    .testTarget(name: "SynoraPlatformTests", dependencies: ["SynoraPlatform"])
  ]
)
