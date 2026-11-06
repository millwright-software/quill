// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Quill",
    platforms: [.macOS(.v15)],
    dependencies: [
        // ASR/VAD only: no TTS, diarizer or NeMo text normalization.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: []),
        // Meeting transcription: Whisper Large v3 Turbo (the WhisperKit product only).
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
    ],
    targets: [
        // One Objective-C function: catches AVAudioEngine's NSExceptions so they can't abort the app.
        .target(name: "ObjCGuard"),
        .executableTarget(
            name: "Quill",
            dependencies: [
                "ObjCGuard",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
