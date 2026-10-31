import AVFoundation
import FluidAudio

/// Keeps the microphone warm with a short rolling pre-roll in memory, so a press starts with the
/// audio from just before it (cold starts took 280–720 ms to deliver the first buffer, 10/30).
/// Dictation never writes to disk; the pre-roll overwrites itself. A meeting can also tee the same
/// tap into an .m4a (`startFile` / `stopFile`) without disturbing dictation.
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
    // Meeting file: written from the tap thread, guarded by its own lock so dictation is never held up.
    private let fileLock = NSLock()
    private var file: AVAudioFile?
    private var fileConverter: AVAudioConverter?
    private var fileFormat: AVAudioFormat?
    private var fileFailed = false

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
        updateFileConverter(for: format)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.writeToFile(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
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

    // MARK: Meeting file

    /// Starts writing the mic to an AAC .m4a (mono, at the input's sample rate) from the running tap.
    func startFile(url: URL) throws {
        if !engine.isRunning { try startEngine() }
        let input = engine.inputNode.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: input.sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let newFile = try AVAudioFile(forWriting: url, settings: settings)
        fileLock.lock()
        file = newFile
        fileFormat = newFile.processingFormat
        fileFailed = false
        fileLock.unlock()
        updateFileConverter(for: input)
    }

    /// Stops writing and closes the file. Dictation is untouched.
    func stopFile() {
        fileLock.lock()
        file = nil
        fileConverter = nil
        fileFormat = nil
        fileLock.unlock()
    }

    /// Converts the input to the file's format (mono float at the file's rate). After a device change
    /// the new input may differ; the file keeps the format it was opened with.
    private func updateFileConverter(for input: AVAudioFormat) {
        fileLock.lock(); defer { fileLock.unlock() }
        guard file != nil, let target = fileFormat else { return }
        if input == target {
            fileConverter = nil
        } else {
            fileConverter = AVAudioConverter(from: input, to: target)
            Log.write("mic file: input is now \(Int(input.sampleRate)) Hz x\(input.channelCount); converting")
        }
    }

    private func writeToFile(_ buffer: AVAudioPCMBuffer) {
        fileLock.lock(); defer { fileLock.unlock() }
        guard let file, !fileFailed else { return }
        do {
            if let converter = fileConverter, let target = fileFormat {
                let ratio = target.sampleRate / buffer.format.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
                guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
                var supplied = false
                var error: NSError?
                converter.convert(to: out, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true
                    status.pointee = .haveData
                    return buffer
                }
                if let error { throw error }
                try file.write(from: out)
            } else {
                try file.write(from: buffer)
            }
        } catch {
            fileFailed = true
            Log.write("mic file write failed, file stops here: \(error.localizedDescription)")
        }
    }
}
