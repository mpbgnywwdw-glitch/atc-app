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

/// Push-to-talk recogniser.
///
/// While a scenario is running the microphone is monitored continuously into a short pre-roll buffer, so the
/// first word isn't clipped while the audio engine starts. `start()` begins a transmission (live partial
/// transcript for display); `stop()` keeps listening for a short tail, then recognises the whole transmission
/// in one pass, which is noticeably more accurate than the streaming result.
@MainActor
final class RadioRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0

    /// How long to keep recording after the transmit key is released.
    static let tailSeconds: Double = 0.5
    /// Audio kept from just before the key was pressed.
    static let preRollSeconds: Double = 0.6

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private let capture = CaptureBuffer(preRollSeconds: RadioRecognizer.preRollSeconds)
    private var monitoring = false
    private var liveTask: SFSpeechRecognitionTask?
    private var contextualStrings: [String] = []
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

    // MARK: Monitoring

    /// Opens the microphone (pre-roll only, nothing is recognised until `start()`).
    func beginMonitoring() throws {
        guard !monitoring else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecognizerError.noMicrophone }
        input.removeTap(onBus: 0)
        capture.reset(sampleRate: format.sampleRate)
        installTap(on: input, format: format, capture: capture) { [weak self] rms in
            Task { @MainActor in self?.level = rms }
        }
        engine.prepare()
        try engine.start()
        monitoring = true
    }

    func endMonitoring() {
        cancel()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        monitoring = false
    }

    // MARK: Transmissions

    func start(contextualStrings: [String]) throws {
        cancel()
        guard let recognizer, recognizer.isAvailable else { throw RecognizerError.unavailable }
        try beginMonitoring()

        session += 1
        let thisSession = session
        self.contextualStrings = contextualStrings
        transcript = ""
        level = 0

        let live = makeRequest(partialResults: true)
        capture.startRecording(live: live)
        isRecording = true
        liveTask = startRecognition(recognizer, live) { [weak self] text, _, _ in
            Task { @MainActor in
                guard let self, self.session == thisSession, self.isRecording, let text else { return }
                self.transcript = text
            }
        }
    }

    /// Ends the transmission and returns what was said.
    func stop() async -> HeardTransmission {
        guard isRecording else { return HeardTransmission(text: transcript, speechDuration: nil) }
        let thisSession = session

        // Keep listening briefly so the last word isn't cut off by an early key release.
        try? await Task.sleep(nanoseconds: UInt64(Self.tailSeconds * 1_000_000_000))
        guard thisSession == session else { return HeardTransmission(text: "", speechDuration: nil) }

        let buffers = capture.stopRecording()
        isRecording = false
        level = 0
        liveTask?.cancel()
        liveTask = nil
        let liveText = transcript

        guard let recognizer, !buffers.isEmpty else {
            return HeardTransmission(text: liveText, speechDuration: nil)
        }

        // One recognition pass over the complete transmission.
        let request = makeRequest(partialResults: false)
        for b in buffers { request.append(b) }
        request.endAudio()
        let result = await recognizeOnce(recognizer, request, timeout: 10)
        guard thisSession == session else { return HeardTransmission(text: "", speechDuration: nil) }

        let text = result.text.trimmingCharacters(in: .whitespaces).isEmpty ? liveText : result.text
        transcript = text
        return HeardTransmission(text: text, speechDuration: result.duration)
    }

    func cancel() {
        session += 1
        _ = capture.stopRecording()
        liveTask?.cancel()
        liveTask = nil
        isRecording = false
        level = 0
    }

    private func makeRequest(partialResults: Bool) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = partialResults
        request.taskHint = .dictation
        request.contextualStrings = Array(contextualStrings.prefix(100))
        request.addsPunctuation = false
        let wantsOnDevice = UserDefaults.standard.bool(forKey: Prefs.onDeviceRecognition)
        if wantsOnDevice, recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
            if #available(macOS 14, *) {
                if let model = RTLanguageModel.shared.configuration { request.customizedLanguageModel = model }
            }
        }
        return request
    }
}

// MARK: - Capture buffer

/// Thread-safe store for microphone audio: a rolling pre-roll while idle, and the full transmission while
/// recording (also streamed to the live request).
private final class CaptureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let preRollSeconds: Double
    private var sampleRate: Double = 48_000
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollFrames: AVAudioFrameCount = 0
    private var recording: [AVAudioPCMBuffer]?
    private var live: SFSpeechAudioBufferRecognitionRequest?

    init(preRollSeconds: Double) { self.preRollSeconds = preRollSeconds }

    var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return recording != nil
    }

    func reset(sampleRate: Double) {
        lock.lock(); defer { lock.unlock() }
        self.sampleRate = sampleRate
        preRoll = []
        preRollFrames = 0
        recording = nil
        live = nil
    }

    func push(_ buffer: AVAudioPCMBuffer) {
        guard let copy = copyBuffer(buffer) else { return }
        lock.lock(); defer { lock.unlock() }
        if recording != nil {
            recording?.append(copy)
            live?.append(copy)
        } else {
            preRoll.append(copy)
            preRollFrames += copy.frameLength
            let limit = AVAudioFrameCount(sampleRate * preRollSeconds)
            while preRollFrames > limit, let first = preRoll.first, preRoll.count > 1 {
                preRollFrames -= first.frameLength
                preRoll.removeFirst()
            }
        }
    }

    func startRecording(live: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); defer { lock.unlock() }
        recording = preRoll
        for b in preRoll { live.append(b) }
        self.live = live
        preRoll = []
        preRollFrames = 0
    }

    /// Stops recording and returns the captured transmission (empty if not recording).
    func stopRecording() -> [AVAudioPCMBuffer] {
        lock.lock(); defer { lock.unlock() }
        let result = recording ?? []
        recording = nil
        live?.endAudio()
        live = nil
        return result
    }
}

private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
    copy.frameLength = buffer.frameLength
    let channels = Int(buffer.format.channelCount)
    let frames = Int(buffer.frameLength)
    if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
        for c in 0..<channels { dst[c].update(from: src[c], count: frames) }
    } else if let src = buffer.int16ChannelData, let dst = copy.int16ChannelData {
        for c in 0..<channels { dst[c].update(from: src[c], count: frames) }
    } else {
        return nil
    }
    return copy
}

// MARK: - Nonisolated helpers (these callbacks run on audio / recognition threads)

private func installTap(on input: AVAudioInputNode, format: AVAudioFormat, capture: CaptureBuffer,
                        level: @escaping @Sendable (Float) -> Void) {
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        capture.push(buffer)
        guard capture.isRecording, let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        level(min(1, sqrt(sum / Float(buffer.frameLength)) * 8))
    }
}

private func startRecognition(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                              handler: @escaping @Sendable (String?, TimeInterval?, Bool) -> Void) -> SFSpeechRecognitionTask {
    recognizer.recognitionTask(with: request) { result, error in
        handler(result?.bestTranscription.formattedString, speechDuration(result), (result?.isFinal ?? false) || error != nil)
    }
}

private func speechDuration(_ result: SFSpeechRecognitionResult?) -> TimeInterval? {
    guard let segments = result?.bestTranscription.segments, let first = segments.first, let last = segments.last,
          last.timestamp + last.duration > first.timestamp else { return nil }
    return last.timestamp + last.duration - first.timestamp
}

private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(text: String, duration: TimeInterval?), Never>?
    private var best: (text: String, duration: TimeInterval?) = ("", nil)

    init(_ c: CheckedContinuation<(text: String, duration: TimeInterval?), Never>) { continuation = c }

    func update(_ text: String?, _ duration: TimeInterval?) {
        lock.lock(); defer { lock.unlock() }
        if let text, !text.isEmpty { best = (text, duration ?? best.duration) }
    }

    func finish() {
        lock.lock()
        let c = continuation
        continuation = nil
        let result = best
        lock.unlock()
        c?.resume(returning: result)
    }
}

/// Recognises a complete (already ended) request and returns the final transcript, or the best partial at timeout.
private func recognizeOnce(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                           timeout: Double) async -> (text: String, duration: TimeInterval?) {
    await withCheckedContinuation { continuation in
        let shot = OneShot(continuation)
        let task = recognizer.recognitionTask(with: request) { result, error in
            shot.update(result?.bestTranscription.formattedString, speechDuration(result))
            if result?.isFinal == true || error != nil { shot.finish() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            task.finish()
            shot.finish()
        }
    }
}
