// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GlacierBackup",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GlacierBackup"),
        .testTarget(name: "GlacierBackupTests", dependencies: ["GlacierBackup"]),
    ]
)
