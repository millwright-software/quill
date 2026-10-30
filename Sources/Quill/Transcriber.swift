import FluidAudio
import Foundation

/// Parakeet TDT v2 (English) through FluidAudio, loaded and warmed once at launch.
actor Transcriber {
    private var asr: AsrManager?

    func load() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v2)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asr = manager
        // Warm-up pass so the first real dictation doesn't pay for Core ML's first run.
        _ = try? await transcribe([Float](repeating: 0, count: Int(Recorder.sampleRate)))
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let asr else { throw QuillError.notLoaded }
        var audio = samples
        // Pad short clips to one second with silence; the model rejects very short input.
        let minimum = Int(Recorder.sampleRate)
        if audio.count < minimum { audio += [Float](repeating: 0, count: minimum - audio.count) }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let result = try await asr.transcribe(audio, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum QuillError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "the speech model isn't loaded yet" }
}
