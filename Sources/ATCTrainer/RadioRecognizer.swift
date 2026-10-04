import AVFoundation
import Speech

struct HeardTransmission {
    let text: String
    /// Seconds from the first to the last recognised word, if known.
    let speechDuration: TimeInterval?
}

enum RecognizerError: LocalizedError {
    case unavailable
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Speech recognition for English (UK) isn't available right now."
        case .noMicrophone: return "No microphone input was found."
        }
    }
}

/// Push-to-talk recogniser: `start()` while the transmit key is held, `stop()` on release.
@MainActor
final class RadioRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var duration: TimeInterval?
    private var gotFinal = false
    private var waiter: CheckedContinuation<HeardTransmission, Never>?
    private var session = 0

    /// Returns an error message, or nil if both speech recognition and microphone access are granted.
    static func requestPermissions() async -> String? {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else {
            return "Speech recognition is turned off for RT Trainer. Allow it in System Settings › Privacy & Security › Speech Recognition."
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard mic else {
            return "Microphone access is turned off for RT Trainer. Allow it in System Settings › Privacy & Security › Microphone."
        }
        return nil
    }

    func start(contextualStrings: [String]) throws {
        cancel()
        guard let recognizer, recognizer.isAvailable else { throw RecognizerError.unavailable }

        session += 1
        let thisSession = session
        transcript = ""
        duration = nil
        gotFinal = false
        level = 0

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = Array(contextualStrings.prefix(100))
        request.addsPunctuation = false
        if UserDefaults.standard.bool(forKey: Prefs.onDeviceRecognition) && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecognizerError.noMicrophone }
        input.removeTap(onBus: 0)
        installTap(on: input, format: format, request: request) { [weak self] rms in
            Task { @MainActor in
                guard let self, self.session == thisSession else { return }
                self.level = rms
            }
        }
        engine.prepare()
        try engine.start()
        isRecording = true

        task = startRecognition(recognizer, request) { [weak self] text, duration, final in
            Task { @MainActor in
                self?.handle(text: text, duration: duration, final: final, session: thisSession)
            }
        }
    }

    /// Ends the transmission and waits briefly for the final transcript.
    func stop() async -> HeardTransmission {
        guard isRecording else { return current }
        stopAudio()
        request?.endAudio()
        if gotFinal { return current }
        return await withCheckedContinuation { continuation in
            waiter = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.finishWaiting()
            }
        }
    }

    func cancel() {
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        finishWaiting()
    }

    private var current: HeardTransmission { HeardTransmission(text: transcript, speechDuration: duration) }

    private func handle(text: String?, duration: TimeInterval?, final: Bool, session s: Int) {
        guard s == session else { return }
        if let text { transcript = text }
        if let duration { self.duration = duration }
        if final {
            gotFinal = true
            finishWaiting()
        }
    }

    private func finishWaiting() {
        guard let w = waiter else { return }
        waiter = nil
        w.resume(returning: current)
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        level = 0
    }
}

// Nonisolated helpers: these callbacks run on audio / recognition threads.

private func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                        request: SFSpeechAudioBufferRecognitionRequest,
                        level: @escaping @Sendable (Float) -> Void) {
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        request.append(buffer)
        if let data = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
            level(min(1, sqrt(sum / Float(buffer.frameLength)) * 8))
        }
    }
}

private func startRecognition(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                              handler: @escaping @Sendable (String?, TimeInterval?, Bool) -> Void) -> SFSpeechRecognitionTask {
    recognizer.recognitionTask(with: request) { result, error in
        let text = result?.bestTranscription.formattedString
        var duration: TimeInterval?
        if let segments = result?.bestTranscription.segments, let first = segments.first, let last = segments.last,
           last.timestamp + last.duration > first.timestamp {
            duration = last.timestamp + last.duration - first.timestamp
        }
        handler(text, duration, (result?.isFinal ?? false) || error != nil)
    }
}
