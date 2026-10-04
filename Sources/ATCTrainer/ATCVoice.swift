import AVFoundation

/// Speaks ATC transmissions with a British voice, optionally through a band-limited "VHF radio" chain
/// with a burst of static at either end.
@MainActor
final class ATCVoice: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let distortion = AVAudioUnitDistortion()
    private var graphFormat: AVAudioFormat?
    private var directContinuation: CheckedContinuation<Void, Never>?
    private var generation = 0
    private var cancelPlayback: (@Sendable () -> Void)?

    override init() {
        super.init()
        synth.delegate = self
        engine.attach(player)
        engine.attach(distortion)
        engine.attach(eq)
        distortion.loadFactoryPreset(.speechRadioTower)
        distortion.wetDryMix = 30
        let highPass = eq.bands[0]
        highPass.filterType = .highPass
        highPass.frequency = 350
        highPass.bypass = false
        let lowPass = eq.bands[1]
        lowPass.filterType = .lowPass
        lowPass.frequency = 2800
        lowPass.bypass = false
        let presence = eq.bands[2]
        presence.filterType = .parametric
        presence.frequency = 1600
        presence.bandwidth = 1.0
        presence.gain = 5
        presence.bypass = false
    }

    static var britishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-GB") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    /// Adjusts written RT for the synthesiser (acronyms spelled out, etc).
    static func spokenForm(_ text: String) -> String {
        var s = text
        let replacements: [(String, String)] = [
            ("QNH", "Q N H"), ("QFE", "Q F E"), ("MATZ", "mats"), ("ATZ", "A T Z"), ("VFR", "V F R"),
            ("ATIS", "ay-tiss"), ("AFIS", "ay-fiss"), ("PPL", "P P L"), ("Mayday", "May-day"),
            ("take-off", "take off"), ("Pan", "Pahn"),
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: "\\b\(from)\\b", with: to, options: .regularExpression)
        }
        return s
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let defaults = UserDefaults.standard
        let u = AVSpeechUtterance(string: Self.spokenForm(text))
        let rate = defaults.double(forKey: Prefs.voiceRate)
        u.rate = Float(rate > 0 ? rate : 0.5)
        let id = defaults.string(forKey: Prefs.voiceID) ?? ""
        u.voice = (id.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: id))
            ?? Self.britishVoices.first
            ?? AVSpeechSynthesisVoice(language: "en-GB")
        u.preUtteranceDelay = 0.05
        return u
    }

    /// Speaks `text` and returns when playback has finished (or was stopped).
    func speak(_ text: String) async {
        stop()
        generation += 1
        let gen = generation
        isSpeaking = true
        defer { if gen == generation { isSpeaking = false } }

        if UserDefaults.standard.bool(forKey: Prefs.radioEffect) {
            let buffers = await render(makeUtterance(text))
            guard gen == generation else { return }
            if !buffers.isEmpty {
                let played = await playThroughRadio(buffers)
                if played { return }
            }
            guard gen == generation else { return }
        }
        await speakDirect(makeUtterance(text))
    }

    func stop() {
        generation += 1
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player.stop()
        cancelPlayback?()
        cancelPlayback = nil
        resumeDirect()
        isSpeaking = false
    }

    // MARK: - Radio effect path

    private func render(_ utterance: AVSpeechUtterance) async -> [AVAudioPCMBuffer] {
        let state = RenderState()
        return await withCheckedContinuation { continuation in
            state.setContinuation(continuation)
            beginRender(synth, utterance, state)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { state.finish() }
        }
    }

    private func playThroughRadio(_ buffers: [AVAudioPCMBuffer]) async -> Bool {
        guard let format = buffers.first?.format else { return false }
        if graphFormat != format {
            engine.stop()
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(distortion)
            engine.disconnectNodeOutput(eq)
            engine.connect(player, to: distortion, format: format)
            engine.connect(distortion, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
            graphFormat = format
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        guard let openNoise = makeNoise(format: format, seconds: 0.15),
              let closeNoise = makeNoise(format: format, seconds: 0.12) else { return false }

        let seconds = ([openNoise] + buffers + [closeNoise]).reduce(0.0) { $0 + Double($1.frameLength) / format.sampleRate }
        let once = Once()
        return await withCheckedContinuation { continuation in
            let done: @Sendable () -> Void = {
                if once.claim() { continuation.resume(returning: true) }
            }
            cancelPlayback = done
            scheduleRadio(player, [openNoise] + buffers + [closeNoise], completion: done)
            // Safety net in case the completion callback is never delivered.
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 1.5, execute: done)
        }
    }

    private func makeNoise(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        for c in 0..<Int(format.channelCount) {
            for i in 0..<Int(frames) { channels[c][i] = Float.random(in: -0.06...0.06) }
        }
        return buffer
    }

    // MARK: - Plain speech path

    private func speakDirect(_ utterance: AVSpeechUtterance) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            directContinuation = continuation
            synth.speak(utterance)
        }
    }

    fileprivate func resumeDirect() {
        let c = directContinuation
        directContinuation = nil
        c?.resume()
    }
}

extension ATCVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeDirect() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeDirect() }
    }
}

// MARK: - Rendering helpers (nonisolated: the buffer callback arrives on a background thread)

/// Collects rendered speech buffers and resumes once, on completion, inactivity or timeout.
private final class RenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>?

    func setContinuation(_ c: CheckedContinuation<[AVAudioPCMBuffer], Never>) {
        lock.lock()
        continuation = c
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        buffers.append(buffer)
        let count = buffers.count
        lock.unlock()
        // Some OS versions never deliver the empty "end" buffer; finish after a short silence.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let unchanged = self.buffers.count == count
            self.lock.unlock()
            if unchanged { self.finish() }
        }
    }

    func finish() {
        lock.lock()
        let c = continuation
        continuation = nil
        let result = buffers
        lock.unlock()
        c?.resume(returning: result)
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

private func scheduleRadio(_ player: AVAudioPlayerNode, _ buffers: [AVAudioPCMBuffer], completion: @escaping @Sendable () -> Void) {
    for (i, b) in buffers.enumerated() {
        if i == buffers.count - 1 {
            player.scheduleBuffer(b, completionCallbackType: .dataPlayedBack) { _ in completion() }
        } else {
            player.scheduleBuffer(b, completionHandler: nil)
        }
    }
    player.play()
}

private func beginRender(_ synth: AVSpeechSynthesizer, _ utterance: AVSpeechUtterance, _ state: RenderState) {
    synth.write(utterance) { buffer in
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            state.finish()
        } else if let copy = floatCopy(of: pcm) {
            state.append(copy)
        }
    }
}

/// Converts a synthesiser buffer (often 16-bit integer) to mono Float32, which the effect units need.
private func floatCopy(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1),
          let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
          let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
    do {
        try converter.convert(to: out, from: buffer)
    } catch {
        return nil
    }
    return out.frameLength > 0 ? out : nil
}
