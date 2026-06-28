import Foundation
import SwiftData

@MainActor
struct DiagnosticsExportService {
    private enum Constants {
        static let directoryName = "Diagnostics"
        static let fileName = "latest-device-diagnostics.json"
        static let speechTestSentence = "Saya belajar bahasa Indonesia."
        static let speechTestSteps = 2
    }

    private let diagnosticsService: DeviceDiagnosticsService
    private let fileManager: FileManager
    private let speechEngine: SupertonicSpeechEngine
    private let keyStore: APIKeyStoring
    private let modelContext: ModelContext?

    init(
        modelContext: ModelContext? = nil,
        diagnosticsService: DeviceDiagnosticsService? = nil,
        speechEngine: SupertonicSpeechEngine = SupertonicSpeechEngine(),
        keyStore: APIKeyStoring = KeychainAPIKeyStore(),
        fileManager: FileManager = .default
    ) {
        self.modelContext = modelContext
        self.diagnosticsService = diagnosticsService ?? DeviceDiagnosticsService()
        self.speechEngine = speechEngine
        self.keyStore = keyStore
        self.fileManager = fileManager
    }

    func exportLatest() async throws -> URL {
        let items = await diagnosticsService.loadItems()
        let exportItems = items.map(DiagnosticsExportItem.init(item:))
            + [
                storedLessonsItem(),
                saveRoundTripItem(),
                await lessonCompositionItem(),
                await speechSynthesisItem(),
            ]
        let payload = DiagnosticsExportPayload(
            exportedAt: Date(),
            items: exportItems
        )
        let data = try JSONEncoder.dailylangDiagnostics.encode(payload)
        let directoryURL = try diagnosticsDirectoryURL()
        let fileURL = directoryURL.appendingPathComponent(Constants.fileName)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private func diagnosticsDirectoryURL() throws -> URL {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = applicationSupportURL.appendingPathComponent(Constants.directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func storedLessonsItem() -> DiagnosticsExportItem {
        do {
            guard let modelContext else {
                return DiagnosticsExportItem(
                    id: "stored-lessons",
                    title: "保存済みレッスン",
                    detail: "アプリ本体の保存先に接続できませんでした。",
                    status: "blocked"
                )
            }

            let context = modelContext
            let records = try LessonRecordPersistence.fetchSavedRecords(in: context)

            if let latest = records.first {
                return DiagnosticsExportItem(
                    id: "stored-lessons",
                    title: "保存済みレッスン",
                    detail: "\(records.count)件 / 最新: \(latest.mainSentenceID)",
                    status: "ready"
                )
            }

            return DiagnosticsExportItem(
                id: "stored-lessons",
                title: "保存済みレッスン",
                detail: "0件。Homeで写真からレッスンを作成するとReviewにも表示されます。",
                status: "warning"
            )
        } catch {
            return DiagnosticsExportItem(
                id: "stored-lessons",
                title: "保存済みレッスン",
                detail: error.localizedDescription,
                status: "blocked"
            )
        }
    }

    private func saveRoundTripItem() -> DiagnosticsExportItem {
        guard let modelContext else {
            return DiagnosticsExportItem(
                id: "save-roundtrip",
                title: "保存読み戻し",
                detail: "アプリ本体の保存先に接続できませんでした。",
                status: "blocked"
            )
        }

        var diagnosticRecordID: UUID?
        do {
            let record = try makeDiagnosticLessonRecord()
            diagnosticRecordID = record.id

            try LessonRecordPersistence.insertAndSave(record, in: modelContext)
            guard let savedRecord = try LessonRecordPersistence.fetchSavedRecord(id: record.id, in: modelContext) else {
                throw LessonRecordPersistenceError.savedRecordNotFound(record.id)
            }

            modelContext.delete(savedRecord)
            try modelContext.save()

            return DiagnosticsExportItem(
                id: "save-roundtrip",
                title: "保存読み戻し",
                detail: "実アプリの保存先で保存、ID指定読み戻し、削除OK。",
                status: "ready"
            )
        } catch {
            if let diagnosticRecordID,
               let record = try? LessonRecordPersistence.fetchSavedRecord(id: diagnosticRecordID, in: modelContext) {
                modelContext.delete(record)
                try? modelContext.save()
            }

            return DiagnosticsExportItem(
                id: "save-roundtrip",
                title: "保存読み戻し",
                detail: error.localizedDescription,
                status: "blocked"
            )
        }
    }

    private func makeDiagnosticLessonRecord() throws -> LessonRecord {
        let context = SceneContext(
            timeText: "12:00",
            dayText: "Monday",
            locationLabel: .home,
            imageKeywords: [ImageKeyword(label: "diagnostic", confidence: 1.0)],
            languageLevel: .beginner
        )
        let lesson = Lesson(
            mainSentenceID: "Saya sedang belajar bahasa Indonesia.",
            mainSentenceJP: "私はインドネシア語を勉強しています。",
            vocabulary: [
                VocabularyItem(id: "saya", jp: "私"),
                VocabularyItem(id: "sedang", jp: "〜している"),
                VocabularyItem(id: "belajar", jp: "勉強する"),
            ],
            grammarNote: "sedang + 動詞 = 今〜している。",
            conversation: [
                ConversationLine(speaker: "A", id: "Kamu sedang apa?", jp: "何をしていますか。"),
                ConversationLine(speaker: "B", id: "Saya sedang belajar.", jp: "私は勉強しています。"),
            ],
            similarExpressions: [
                SimilarExpression(id: "Saya belajar setiap hari.", jp: "私は毎日勉強します。"),
                SimilarExpression(id: "Saya sedang membaca.", jp: "私は読んでいます。"),
                SimilarExpression(id: "Saya mau berlatih.", jp: "私は練習したいです。"),
            ],
            source: .local
        )
        return try LessonRecord(context: context, lesson: lesson, photoLocalPath: nil)
    }

    private func lessonCompositionItem() async -> DiagnosticsExportItem {
        do {
            let key = try keyStore.loadAPIKey()
            let service = LessonCompositionService()
            let result = try await service.composeLesson(
                from: SampleSceneImageFactory.makeOfficeSceneImage(),
                userNote: "",
                settings: LessonGenerationSettings(
                    languageLevel: .beginner,
                    savePhotos: false,
                    openAIAPIKey: key,
                    openAIModel: AppDefaults.openAIModel,
                    defaultLocationLabel: LocationLabel(rawValue: AppDefaults.defaultLocationLabel) ?? .home
                )
            )

            guard !result.context.imageKeywords.isEmpty else {
                return DiagnosticsExportItem(
                    id: "lesson-composition",
                    title: "画像からレッスン生成",
                    detail: "画像キーワードが空でした。",
                    status: "blocked"
                )
            }

            guard result.lesson.source == .openAI,
                  !result.lesson.mainSentenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !result.lesson.vocabulary.isEmpty
            else {
                return DiagnosticsExportItem(
                    id: "lesson-composition",
                    title: "画像からレッスン生成",
                    detail: "OpenAI応答から本文を作成できませんでした。",
                    status: "blocked"
                )
            }

            let keywordText = result.context.imageKeywords
                .prefix(5)
                .map(\.label)
                .joined(separator: ", ")

            return DiagnosticsExportItem(
                id: "lesson-composition",
                title: "画像からレッスン生成",
                detail: "keywords: \(keywordText) / 本文: \(result.lesson.mainSentenceID)",
                status: "ready"
            )
        } catch {
            return DiagnosticsExportItem(
                id: "lesson-composition",
                title: "画像からレッスン生成",
                detail: error.localizedDescription,
                status: "blocked"
            )
        }
    }

    private func speechSynthesisItem() async -> DiagnosticsExportItem {
        do {
            let url = try await speechEngine.synthesizeIndonesian(
                text: Constants.speechTestSentence,
                steps: Constants.speechTestSteps
            )
            defer {
                try? fileManager.removeItem(at: url)
            }

            let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            guard let byteCount = size?.intValue, byteCount > 44 else {
                return DiagnosticsExportItem(
                    id: "supertonic-synthesis",
                    title: "Supertonic音声生成",
                    detail: "WAVファイルが空に近い状態でした。",
                    status: "blocked"
                )
            }

            return DiagnosticsExportItem(
                id: "supertonic-synthesis",
                title: "Supertonic音声生成",
                detail: "端末内でWAV生成OK (\(byteCount) bytes)",
                status: "ready"
            )
        } catch {
            return DiagnosticsExportItem(
                id: "supertonic-synthesis",
                title: "Supertonic音声生成",
                detail: error.localizedDescription,
                status: "blocked"
            )
        }
    }
}

private struct DiagnosticsExportPayload: Encodable {
    var exportedAt: Date
    var items: [DiagnosticsExportItem]

    enum CodingKeys: String, CodingKey {
        case exportedAt = "exported_at"
        case items
    }
}

private struct DiagnosticsExportItem: Encodable {
    var id: String
    var title: String
    var detail: String
    var status: String

    init(id: String, title: String, detail: String, status: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
    }

    init(item: DeviceDiagnosticItem) {
        id = item.id
        title = item.title
        detail = item.detail
        status = item.status.rawValue
    }
}

private extension DeviceDiagnosticItem.Status {
    var rawValue: String {
        switch self {
        case .ready:
            "ready"
        case .warning:
            "warning"
        case .blocked:
            "blocked"
        }
    }
}

private extension Lesson {
    var searchableText: String {
        (
            [
                mainSentenceID,
                mainSentenceJP,
                grammarNote,
            ]
            + vocabulary.flatMap { [$0.id, $0.jp] }
            + conversation.flatMap { [$0.id, $0.jp] }
            + similarExpressions.flatMap { [$0.id, $0.jp] }
        )
        .joined(separator: " ")
        .lowercased()
    }
}

private extension JSONEncoder {
    static var dailylangDiagnostics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
