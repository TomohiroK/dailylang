import AVFoundation
import Foundation

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

enum SupertonicSpeechError: LocalizedError {
    case emptyText
    case runtimeUnavailable
    case missingAssets(String)
    case playbackStartFailed
    case playbackDecodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            "読み上げる例文がありません。"
        case .runtimeUnavailable:
            "Supertonic の ONNX Runtime が読み込まれていません。"
        case .missingAssets(let detail):
            detail
        case .playbackStartFailed:
            "音声の再生を開始できませんでした。"
        case .playbackDecodeFailed(let detail):
            "音声の読み込み中に問題が起きました: \(detail)"
        }
    }
}

@MainActor
final class SupertonicSpeechPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private enum Constants {
        static let defaultSteps = 8
    }

    @Published private(set) var isGenerating = false
    @Published private(set) var isPlaying = false
    @Published var errorMessage: String?

    private let engine = SupertonicSpeechEngine()
    private var player: AVAudioPlayer?
    private var generationTask: Task<Void, Never>?
    private var currentAudioURL: URL?

    var iconName: String {
        if isGenerating {
            return "hourglass"
        }
        return isPlaying ? "stop.fill" : "speaker.wave.2.fill"
    }

    var buttonAccessibilityLabel: String {
        if isGenerating {
            return "音声を生成中"
        }
        return isPlaying ? "読み上げを停止" : "例文を読み上げ"
    }

    func toggle(sentence: String) {
        if isGenerating || isPlaying {
            stop()
            return
        }

        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSentence.isEmpty else {
            errorMessage = SupertonicSpeechError.emptyText.localizedDescription
            return
        }

        isGenerating = true
        errorMessage = nil

        generationTask = Task { [engine] in
            var generatedURL: URL?
            do {
                let url = try await engine.synthesizeIndonesian(
                    text: trimmedSentence,
                    steps: Constants.defaultSteps
                )
                generatedURL = url
                try Task.checkCancellation()
                try play(url: url)
            } catch is CancellationError {
                if let generatedURL {
                    removeTemporaryAudio(at: generatedURL)
                }
                stop()
            } catch {
                if let generatedURL {
                    removeTemporaryAudio(at: generatedURL)
                }
                stop()
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        player?.stop()
        player = nil
        if let currentAudioURL {
            removeTemporaryAudio(at: currentAudioURL)
            self.currentAudioURL = nil
        }
        deactivateAudioSession()
        isGenerating = false
        isPlaying = false
    }

    private func play(url: URL) throws {
        try configureAudioSession()
        let data = try Data(contentsOf: url)
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            throw SupertonicSpeechError.playbackStartFailed
        }
        self.player = player
        currentAudioURL = url
        isPlaying = true
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    private func removeTemporaryAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if let currentAudioURL = self.currentAudioURL {
                self.removeTemporaryAudio(at: currentAudioURL)
                self.currentAudioURL = nil
            }
            self.deactivateAudioSession()
            self.player = nil
            self.isPlaying = false
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            if let currentAudioURL = self.currentAudioURL {
                self.removeTemporaryAudio(at: currentAudioURL)
                self.currentAudioURL = nil
            }
            self.deactivateAudioSession()
            self.player = nil
            self.isPlaying = false
            self.errorMessage = SupertonicSpeechError
                .playbackDecodeFailed(error?.localizedDescription ?? "原因不明")
                .localizedDescription
        }
    }
}

#if canImport(OnnxRuntimeBindings)
actor SupertonicSpeechEngine {
    private enum Constants {
        static let defaultSpeed: Float = 1.05
        static let languageCode = "id"
        static let voiceStyleName = "M1"
    }

    private var service: SupertonicTextToSpeechService?

    func synthesizeIndonesian(text: String, steps: Int) async throws -> URL {
        if service == nil {
            service = try SupertonicTextToSpeechService()
        }

        guard let service else {
            throw SupertonicSpeechError.runtimeUnavailable
        }

        return try service.synthesize(
            text: text,
            languageCode: Constants.languageCode,
            voiceStyleName: Constants.voiceStyleName,
            steps: steps,
            speed: Constants.defaultSpeed
        )
    }
}

private final class SupertonicTextToSpeechService {
    private let textToSpeech: TextToSpeech
    private let sampleRate: Int

    init() throws {
        let onnxDirectory = try Self.locateOnnxDirectory()
        let environment = try ORTEnv(loggingLevel: .warning)
        textToSpeech = try loadTextToSpeech(onnxDirectory.path, false, environment)
        sampleRate = textToSpeech.sampleRate
    }

    func synthesize(
        text: String,
        languageCode: String,
        voiceStyleName: String,
        steps: Int,
        speed: Float
    ) throws -> URL {
        let styleURL = try Self.locateVoiceStyle(named: voiceStyleName)
        let style = try loadVoiceStyle([styleURL.path], verbose: false)
        let (wav, duration) = try textToSpeech.call(text, languageCode, style, steps, speed: speed)
        let sampleCount = min(Int(Float(sampleRate) * duration), wav.count)
        let clippedWave = Array(wav.prefix(sampleCount))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dailylang_supertonic_\(UUID().uuidString).wav")

        try writeWavFile(outputURL.path, clippedWave, sampleRate)
        return outputURL
    }

    private static func locateOnnxDirectory() throws -> URL {
        let fileManager = FileManager.default
        let requiredFiles = [
            "tts.json",
            "unicode_indexer.json",
            "duration_predictor.onnx",
            "text_encoder.onnx",
            "vector_estimator.onnx",
            "vocoder.onnx"
        ]

        let candidates = resourceCandidates(named: "onnx")
        for candidate in candidates where requiredFiles.allSatisfy({ fileManager.fileExists(atPath: candidate.appendingPathComponent($0).path) }) {
            return candidate
        }

        throw SupertonicSpeechError.missingAssets(
            "Supertonic の onnx フォルダがアプリに含まれていません。"
        )
    }

    private static func locateVoiceStyle(named name: String) throws -> URL {
        let fileManager = FileManager.default
        let fileName = "\(name).json"

        for candidate in resourceCandidates(named: "voice_styles") {
            let fileURL = candidate.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }

        throw SupertonicSpeechError.missingAssets(
            "Supertonic の voice_styles/\(fileName) がアプリに含まれていません。"
        )
    }

    private static func resourceCandidates(named folderName: String) -> [URL] {
        guard let resourceURL = Bundle.main.resourceURL else {
            return []
        }

        return [
            resourceURL.appendingPathComponent(folderName, isDirectory: true),
            resourceURL.appendingPathComponent("assets/\(folderName)", isDirectory: true)
        ]
    }
}
#else
actor SupertonicSpeechEngine {
    func synthesizeIndonesian(text: String, steps: Int) async throws -> URL {
        throw SupertonicSpeechError.runtimeUnavailable
    }
}
#endif
