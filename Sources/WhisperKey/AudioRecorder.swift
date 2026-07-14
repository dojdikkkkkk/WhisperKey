import AVFoundation

/// Records the microphone into a 16 kHz mono 16-bit WAV — Whisper's native input format.
final class AudioRecorder {
    private var avRecorder: AVAudioRecorder?
    private(set) var currentURL: URL?

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperkey-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        guard rec.record() else {
            throw NSError(domain: "WhisperKey", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder failed to start"])
        }
        let device = AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
        debugLog("record: started, input device=\(device)")
        avRecorder = rec
        currentURL = url
    }

    /// Current input level normalized to 0...1 (for the reactive glow).
    var level: Double {
        guard let rec = avRecorder else { return 0 }
        rec.updateMeters()
        let db = Double(rec.averagePower(forChannel: 0))  // ≈ -60 (silence) ... 0 (loud)
        return max(0, min(1, (db + 45) / 35))
    }

    /// Stops recording and returns the WAV file URL, or nil if nothing was recorded.
    func stop() -> URL? {
        guard let rec = avRecorder else { return nil }
        rec.updateMeters()
        let avg = rec.averagePower(forChannel: 0)
        let peak = rec.peakPower(forChannel: 0)
        rec.stop()
        avRecorder = nil
        let url = currentURL
        currentURL = nil
        if let url {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int) ?? 0
            debugLog("record: stopped, \(size) bytes, avg=\(avg) dB, peak=\(peak) dB"
                     + (peak < -50 ? " SILENT RECORDING" : ""))
        }
        return url
    }
}
