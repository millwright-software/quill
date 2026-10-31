import AVFoundation
import FluidAudio

/// Keeps the microphone warm with a short rolling pre-roll in memory, so a press starts with the
/// audio from just before it (cold starts took 280–720 ms to deliver the first buffer, 10/30).
/// Never writes to disk; the pre-roll overwrites itself.
final class Recorder {
    static let sampleRate: Double = 16_000
    private static let preRollSeconds: Double = 0.5

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var preRoll: [Float] = []
    private var samples: [Float] = []
    private var capturing = false
    private var inputRate: Double = 48_000
    private let converter = AudioConverter(sampleRate: Recorder.sampleRate)
    private var configObserver: NSObjectProtocol?

    /// Opens the mic and keeps it open. Restarts itself when the input device changes.
    func warmUp() throws {
        try startEngine()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Log.write("audio configuration changed; restarting the mic")
            try? self?.startEngine()
        }
    }

    private func startEngine() throws {
        engine.stop()
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        lock.lock(); inputRate = format.sampleRate; preRoll.removeAll(); lock.unlock()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let chunk = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            self.lock.lock()
            if self.capturing {
                self.samples.append(contentsOf: chunk)
            } else {
                self.preRoll.append(contentsOf: chunk)
                let keep = Int(self.inputRate * Self.preRollSeconds)
                if self.preRoll.count > keep { self.preRoll.removeFirst(self.preRoll.count - keep) }
            }
            self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
    }

    func start() throws {
        if !engine.isRunning { try startEngine() }
        lock.lock()
        samples = preRoll
        preRoll.removeAll()
        capturing = true
        lock.unlock()
    }

    /// The capture so far, at 16 kHz, without stopping it. `lastSeconds` trims to the tail.
    func snapshot(lastSeconds: Double? = nil) -> [Float] {
        lock.lock()
        var raw = samples
        let rate = inputRate
        lock.unlock()
        if let lastSeconds {
            let keep = Int(rate * lastSeconds)
            if raw.count > keep { raw.removeFirst(raw.count - keep) }
        }
        return (try? converter.resample(raw, from: rate)) ?? []
    }

    /// Ends the capture and returns it at 16 kHz mono. The mic stays open.
    func stop() -> [Float] {
        lock.lock()
        capturing = false
        let raw = samples
        let rate = inputRate
        samples.removeAll()
        lock.unlock()
        return (try? converter.resample(raw, from: rate)) ?? []
    }
}
