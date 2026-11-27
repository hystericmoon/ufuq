import AppKit
@preconcurrency import AVFoundation
@preconcurrency import Speech
import UfuqCore

@MainActor
final class SpeechTranscriber: ObservableObject {
    static let shared = SpeechTranscriber()

    @Published private(set) var isRecording = false
    @Published private(set) var isProcessing = false
    @Published private(set) var transcript = ""
    @Published private(set) var statusMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private init() {}

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    func startRecording() async {
        guard !isRecording else { return }
        let speechOK = await requestAuthorization()
        guard speechOK else {
            statusMessage = "Allow Speech Recognition in Settings"
            return
        }
        let micOK = await AVCaptureDevice.requestAccess(for: .audio)
        guard micOK else {
            statusMessage = "Allow Microphone in Settings"
            return
        }
        guard let speechRecognizer = SFSpeechRecognizer(), speechRecognizer.isAvailable else {
            statusMessage = "Speech recognizer unavailable"
            return
        }

        stopRecording(copyToClipboard: false)
        transcript = ""
        statusMessage = "Listening…"

        let engine = AVAudioEngine()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            statusMessage = "Could not start microphone"
            return
        }

        self.recognizer = speechRecognizer
        self.audioEngine = engine
        self.request = req
        self.isRecording = true

        self.task = speechRecognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishSession(copy: true)
                    }
                } else if error != nil, self.isRecording {
                    self.finishSession(copy: !self.transcript.isEmpty)
                }
            }
        }
    }

    func stopRecording(copyToClipboard: Bool = true) {
        guard isRecording else { return }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
        if copyToClipboard, !transcript.isEmpty {
            copyTranscript()
        }
    }

    func copyTranscript() {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(trimmed, forType: .string)
        let words = trimmed.split(whereSeparator: \.isWhitespace).count
        statusMessage = TrayActions.formatTranscriptStatus(wordCount: words)
    }

    func clear() {
        stopRecording(copyToClipboard: false)
        transcript = ""
        statusMessage = nil
    }

    func transcribeFile(at url: URL) async -> Result<String, Error> {
        let speechOK = await requestAuthorization()
        guard speechOK else {
            return .failure(NSError(domain: "UfuqSpeech", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Allow Speech Recognition in Settings"
            ]))
        }
        guard let speechRecognizer = SFSpeechRecognizer(), speechRecognizer.isAvailable else {
            return .failure(NSError(domain: "UfuqSpeech", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Speech recognizer unavailable"
            ]))
        }

        isProcessing = true
        defer { isProcessing = false }

        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        if speechRecognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }

        return await withCheckedContinuation { continuation in
            var resumed = false
            speechRecognizer.recognitionTask(with: req) { result, error in
                if resumed { return }
                if let error {
                    resumed = true
                    continuation.resume(returning: .failure(error))
                    return
                }
                if let result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: .success(result.bestTranscription.formattedString))
                }
            }
        }
    }

    private func finishSession(copy: Bool) {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        request = nil
        task = nil
        isRecording = false
        if copy { copyTranscript() }
    }
}
