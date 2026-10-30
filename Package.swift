// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Quill",
    platforms: [.macOS(.v15)],
    dependencies: [
        // ASR/VAD only: no TTS, diarizer or NeMo text normalization.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: []),
    ],
    targets: [
        .executableTarget(
            name: "Quill",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
