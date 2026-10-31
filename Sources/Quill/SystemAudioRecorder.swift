import AVFoundation
import CoreAudio

/// Records everything the Mac plays to an .m4a (AAC) through a Core Audio process tap (macOS 14.2+):
/// a global stereo tap, read through a private aggregate device. The first use asks for the system's
/// audio-capture permission. Adapted from humanitas-labs/quill (MIT), without segments or telemetry.
final class SystemAudioRecorder: @unchecked Sendable {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private let ioQueue = DispatchQueue(label: "com.millwright.quill.system-tap")
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var writeFailed = false

    /// Creates the tap, the aggregate device and the file, then starts writing. Throws, with
    /// everything it made already released, if any step fails.
    func start(url: URL) throws {
        guard tapID == kAudioObjectUnknown else { throw Failure(description: "already recording") }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "quill system tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTap)
        guard tapStatus == noErr else {
            throw Failure(description: "the audio tap was refused (OSStatus \(tapStatus)); allow Quill under System Settings → Privacy & Security → Screen & System Audio Recording")
        }
        tapID = newTap

        do {
            let format = try tapFormat()
            try makeAggregate(tapUUID: description.uuid)
            file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                ],
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            writeFailed = false
            try startIO(format: format)
        } catch {
            release()
            throw error
        }
    }

    /// Stops the device, destroys the IO proc, the aggregate device and the tap, and closes the file.
    func stop() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
        }
        // Let a callback already running finish before the file closes.
        ioQueue.sync {}
        release()
    }

    private func tapFormat() throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw Failure(description: "could not read the tap's format (OSStatus \(status))")
        }
        return format
    }

    private func makeAggregate(tapUUID: UUID) throws {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "quill-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id)
        guard status == noErr else {
            throw Failure(description: "could not create the aggregate device (OSStatus \(status))")
        }
        aggregateID = id
    }

    private func startIO(format: AVAudioFormat) throws {
        var status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self, let file = self.file, !self.writeFailed,
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil)
            else { return }
            do {
                try file.write(from: buffer)
            } catch {
                self.writeFailed = true
                Log.write("system audio write failed, file stops here: \(error.localizedDescription)")
            }
        }
        guard status == noErr, procID != nil else {
            throw Failure(description: "could not create the IO proc (OSStatus \(status))")
        }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            throw Failure(description: "could not start the device (OSStatus \(status))")
        }
    }

    /// Releases whatever exists, in dependency order. Safe after a partial start.
    private func release() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        file = nil
    }
}
