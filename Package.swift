// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceTok",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "VoiceTok", targets: ["VoiceTok"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "VoiceTok",
            dependencies: ["WhisperKit"],
            path: "VoiceTok"
        )
    ]
)
