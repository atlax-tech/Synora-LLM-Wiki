// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SynoraCore",
  platforms: [.macOS("26.0")],
  products: [
    .executable(name: "SynoraPlatformProbe", targets: ["SynoraPlatformProbe"])
  ],
  targets: [
    .executableTarget(name: "SynoraPlatformProbe")
  ]
)
