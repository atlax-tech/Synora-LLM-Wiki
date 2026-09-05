// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SynoraCore",
  platforms: [.macOS("26.0")],
  products: [
    .library(name: "SynoraPlatform", targets: ["SynoraPlatform"]),
    .executable(name: "SynoraPlatformProbe", targets: ["SynoraPlatformProbe"])
  ],
  targets: [
    .target(name: "SynoraPlatform"),
    .executableTarget(name: "SynoraPlatformProbe", dependencies: ["SynoraPlatform"]),
    .testTarget(name: "SynoraPlatformTests", dependencies: ["SynoraPlatform"])
  ]
)
