// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ATCTrainer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ATCTrainer", targets: ["ATCTrainer"]),
        .library(name: "RTCore", targets: ["RTCore"]),
    ],
    targets: [
        // Pure-Foundation core: phraseology, scenarios, transcript normalisation and scoring.
        .target(name: "RTCore"),
        // macOS SwiftUI app: ATC voice (AVSpeechSynthesizer) and push-to-talk recognition (Speech).
        .executableTarget(name: "ATCTrainer", dependencies: ["RTCore"]),
        .testTarget(name: "RTCoreTests", dependencies: ["RTCore"]),
    ]
)
