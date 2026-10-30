import AVFoundation
import FluidAudio

/// Captures the default input into memory. Never writes to disk.
final class Recorder {
    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var inputRate: Double = 48_000
    private let converter = AudioConverter(sampleRate: Recorder.sampleRate)
    private var startedAt = Date()
    private var firstBufferLogged = false

    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        startedAt = Date()
        firstBufferLogged = false
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        inputRate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let chunk = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            self.lock.lock(); self.samples.append(contentsOf: chunk); self.lock.unlock()
            if !self.firstBufferLogged {
                self.firstBufferLogged = true
                Log.write("first audio buffer \(Int(Date().timeIntervalSince(self.startedAt) * 1000)) ms after press")
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops capture and returns 16 kHz mono samples.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); let raw = samples; samples.removeAll(); lock.unlock()
        return (try? converter.resample(raw, from: inputRate)) ?? []
    }
}
