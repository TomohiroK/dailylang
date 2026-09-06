import AVFoundation
import CoreLocation
import Foundation
import SwiftData
import UIKit
import UserNotifications

struct DeviceDiagnosticItem: Identifiable, Sendable {
    enum Status: Sendable {
        case ready
        case warning
        case blocked
    }

    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let status: Status
}

@MainActor
struct DeviceDiagnosticsService {
    private let notificationCenter: UNUserNotificationCenter
    private let userDefaults: UserDefaults

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        userDefaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults
    }

    func loadItems(modelContext: ModelContext? = nil) async -> [DeviceDiagnosticItem] {
        let notificationSettings = await notificationCenter.notificationSettings()
        let pendingNotifications = await notificationCenter.pendingNotificationRequests()
        let deliveredNotifications = await notificationCenter.deliveredNotifications()

        var items = [
            cameraItem(),
            locationItem(),
            notificationItem(
                settings: notificationSettings,
                pendingRequests: pendingNotifications,
                deliveredNotifications: deliveredNotifications
            ),
            openAIKeyItem(),
            privacyItem(),
            supertonicItem(),
            await inputPipelineItem()
        ]

        if let modelContext {
            items.append(storedLessonsItem(modelContext: modelContext))
            items.append(homeReviewVisibilityItem(modelContext: modelContext))
            items.append(saveRoundTripItem(modelContext: modelContext))
        }

        return items
    }

    private func cameraItem() -> DeviceDiagnosticItem {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return DeviceDiagnosticItem(
                id: "camera",
                title: "カメラ",
                detail: "この環境ではカメラがありません。実機で撮影確認が必要です。",
                systemImage: "camera",
                status: .warning
            )
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return DeviceDiagnosticItem(
                id: "camera",
                title: "カメラ",
                detail: "撮影に利用できます。",
                systemImage: "camera.fill",
                status: .ready
            )
        case .notDetermined:
            return DeviceDiagnosticItem(
                id: "camera",
                title: "カメラ",
                detail: "初回撮影時に権限確認が表示されます。",
                systemImage: "camera",
                status: .warning
            )
        case .denied, .restricted:
            return DeviceDiagnosticItem(
                id: "camera",
                title: "カメラ",
                detail: "設定アプリでカメラ権限を許可してください。",
                systemImage: "camera.fill",
                status: .blocked
            )
        @unknown default:
            return DeviceDiagnosticItem(
                id: "camera",
                title: "カメラ",
                detail: "カメラ権限の状態を確認できませんでした。",
                systemImage: "camera",
                status: .warning
            )
        }
    }

    private func locationItem() -> DeviceDiagnosticItem {
        guard CLLocationManager.locationServicesEnabled() else {
            return DeviceDiagnosticItem(
                id: "location",
                title: "位置情報",
                detail: "端末の位置情報サービスがOFFです。レッスン生成には現在地ラベルを使いません。",
                systemImage: "location.slash",
                status: .warning
            )
        }

        let manager = CLLocationManager()

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return DeviceDiagnosticItem(
                id: "location",
                title: "位置情報",
                detail: "許可されています。レッスン生成には現在地ラベルを使いません。",
                systemImage: "location.fill",
                status: .ready
            )
        case .notDetermined:
            return DeviceDiagnosticItem(
                id: "location",
                title: "位置情報",
                detail: "未許可です。許可してもレッスン生成には現在地ラベルを使いません。",
                systemImage: "location",
                status: .warning
            )
        case .denied, .restricted:
            return DeviceDiagnosticItem(
                id: "location",
                title: "位置情報",
                detail: "位置情報は許可されていません。レッスン生成には現在地ラベルを使いません。",
                systemImage: "location.slash",
                status: .warning
            )
        @unknown default:
            return DeviceDiagnosticItem(
                id: "location",
                title: "位置情報",
                detail: "位置情報の状態を確認できませんでした。",
                systemImage: "location",
                status: .warning
            )
        }
    }

    private func notificationItem(
        settings: UNNotificationSettings,
        pendingRequests: [UNNotificationRequest],
        deliveredNotifications: [UNNotification]
    ) -> DeviceDiagnosticItem {
        let promptRequests = pendingRequests
            .filter { $0.identifier.hasPrefix(NotificationScheduler.scheduledPromptIdentifierPrefix) }
        let testRequests = pendingRequests
            .filter(NotificationScheduler.isTestPrompt)
        let deliveredPromptNotifications = deliveredNotifications
            .filter { $0.request.identifier.hasPrefix(NotificationScheduler.scheduledPromptIdentifierPrefix) }
        let deliveredTestNotifications = deliveredNotifications
            .filter { NotificationScheduler.isTestPrompt($0.request) }
        let promptCount = promptRequests.count
        let testCount = testRequests.count
        let deliveredPromptCount = deliveredPromptNotifications.count
        let deliveredTestCount = deliveredTestNotifications.count
        let visibleRequestCount = promptCount + testCount
        let visibilityText = notificationVisibilityText(settings)
        let nextPromptText = nextPromptText(from: promptRequests + testRequests)
        let lastDeliveredText = lastDeliveredText(from: deliveredPromptNotifications + deliveredTestNotifications)

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            let status = notificationStatus(settings: settings, pendingRequestCount: visibleRequestCount)
            return DeviceDiagnosticItem(
                id: "notifications",
                title: "通知",
                detail: "予約 ランダム \(promptCount)件 / テスト \(testCount)件 / 配信済み ランダム \(deliveredPromptCount)件 / テスト \(deliveredTestCount)件 / 次: \(nextPromptText) / 最終配信: \(lastDeliveredText) / \(visibilityText)",
                systemImage: "bell.badge",
                status: status
            )
        case .notDetermined:
            return DeviceDiagnosticItem(
                id: "notifications",
                title: "通知",
                detail: "まだ許可されていません。通知予約またはテスト通知で確認します。\(visibilityText)",
                systemImage: "bell",
                status: .warning
            )
        case .denied:
            return DeviceDiagnosticItem(
                id: "notifications",
                title: "通知",
                detail: "設定アプリで通知を許可してください。\(visibilityText)",
                systemImage: "bell.slash",
                status: .blocked
            )
        @unknown default:
            return DeviceDiagnosticItem(
                id: "notifications",
                title: "通知",
                detail: "通知権限の状態を確認できませんでした。\(visibilityText)",
                systemImage: "bell",
                status: .warning
            )
        }
    }

    private func notificationStatus(
        settings: UNNotificationSettings,
        pendingRequestCount: Int
    ) -> DeviceDiagnosticItem.Status {
        guard pendingRequestCount > 0 else {
            return .warning
        }
        guard settings.alertSetting == .enabled else {
            return .warning
        }
        guard settings.notificationCenterSetting == .enabled || settings.lockScreenSetting == .enabled else {
            return .warning
        }
        guard settings.scheduledDeliverySetting != .enabled else {
            return .warning
        }

        return .ready
    }

    private func notificationVisibilityText(_ settings: UNNotificationSettings) -> String {
        [
            "auth: \(settings.authorizationStatus.japaneseName)",
            "alert: \(settings.alertSetting.japaneseName)",
            "sound: \(settings.soundSetting.japaneseName)",
            "center: \(settings.notificationCenterSetting.japaneseName)",
            "lock: \(settings.lockScreenSetting.japaneseName)",
            "summary: \(settings.scheduledDeliverySetting.japaneseName)",
            "time-sensitive: \(settings.timeSensitiveSetting.japaneseName)"
        ]
        .joined(separator: ", ")
    }

    private func nextPromptText(from requests: [UNNotificationRequest]) -> String {
        let nextDate = requests
            .compactMap(NotificationScheduler.nextTriggerDate)
            .min()
        guard let nextDate else {
            return "なし"
        }

        return formattedNotificationDate(nextDate)
    }

    private func lastDeliveredText(from notifications: [UNNotification]) -> String {
        guard let latestDate = notifications.map(\.date).max() else {
            return "なし"
        }

        return formattedNotificationDate(latestDate)
    }

    private func formattedNotificationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func privacyItem() -> DeviceDiagnosticItem {
        let savePhotos = userDefaults.bool(forKey: AppStorageKey.savePhotos)

        if savePhotos {
            return DeviceDiagnosticItem(
                id: "privacy",
                title: "プライバシー既定",
                detail: "写真保存がONです。写真は端末内だけに保存され、APIへは送信されません。",
                systemImage: "hand.raised",
                status: .warning
            )
        }

        return DeviceDiagnosticItem(
            id: "privacy",
            title: "プライバシー既定",
            detail: "写真保存OFF / 写真送信機能なし / OpenAIへは画像キーワード・関係・時刻・曜日・作成言語・生成時に選んだ場所のみ送信します。",
            systemImage: "hand.raised.fill",
            status: .ready
        )
    }

    private func openAIKeyItem() -> DeviceDiagnosticItem {
        let key = (try? KeychainAPIKeyStore().loadAPIKey()) ?? ""
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return DeviceDiagnosticItem(
                id: "openai-key",
                title: "OpenAI APIキー",
                detail: "Keychainまたは起動環境にAPIキーがありません。",
                systemImage: "key.slash",
                status: .blocked
            )
        }

        return DeviceDiagnosticItem(
            id: "openai-key",
            title: "OpenAI APIキー",
            detail: "Keychainまたは起動環境から利用できます。",
            systemImage: "key.fill",
            status: .ready
        )
    }

    private func supertonicItem() -> DeviceDiagnosticItem {
        let status = SupertonicResourceStatus.current()

        guard status.runtimeAvailable else {
            return DeviceDiagnosticItem(
                id: "supertonic",
                title: "Supertonic",
                detail: "ONNX Runtime がリンクされていません。",
                systemImage: "waveform",
                status: .blocked
            )
        }

        guard status.missingFiles.isEmpty else {
            return DeviceDiagnosticItem(
                id: "supertonic",
                title: "Supertonic",
                detail: "不足: \(status.missingFiles.joined(separator: ", "))",
                systemImage: "waveform",
                status: .blocked
            )
        }

        return DeviceDiagnosticItem(
            id: "supertonic",
            title: "Supertonic",
            detail: "ONNXモデルと音声スタイルを端末内で利用できます。",
            systemImage: "waveform",
            status: .ready
        )
    }

    private func inputPipelineItem() async -> DeviceDiagnosticItem {
        let image = SampleSceneImageFactory.makeOfficeSceneImage()

        do {
            let context = try await diagnosticSceneContext(from: image)
            let keywordText = context.imageKeywords
                .prefix(8)
                .map { keyword in
                    keyword.count > 1 ? "\(keyword.label) x\(keyword.count)" : keyword.label
                }
                .joined(separator: ", ")
            let displayKeywords = keywordText.isEmpty ? "なし" : keywordText
            let status: DeviceDiagnosticItem.Status = context.imageKeywords.isEmpty ? .warning : .ready

            return DeviceDiagnosticItem(
                id: "input-pipeline",
                title: "画像キーワード入力",
                detail: "keywords: \(displayKeywords) / API送信用データ作成OK",
                systemImage: "iphone",
                status: status
            )
        } catch {
            return DeviceDiagnosticItem(
                id: "input-pipeline",
                title: "画像キーワード入力",
                detail: error.localizedDescription,
                systemImage: "iphone",
                status: .blocked
            )
        }
    }

    private func diagnosticSceneContext(from image: UIImage) async throws -> SceneContext {
        let evidence = (try? await ImageKeywordService().detectSceneEvidence(in: image))
            ?? ImageSceneEvidence(keywords: [], relations: [])
        return SceneContextFactory().makeContext(
            date: Date(),
            imageKeywords: evidence.keywords,
            imageRelations: evidence.relations,
            userNote: "",
            level: .beginner
        )
    }

    private func storedLessonsItem(modelContext: ModelContext) -> DeviceDiagnosticItem {
        do {
            let records = try LessonRecordPersistence.fetchSavedRecords(in: modelContext)
            let visibleRecords = records.filter(\.hasLearnerVisibleText)
            let hiddenCount = records.count - visibleRecords.count
            guard let latest = records.first else {
                return DeviceDiagnosticItem(
                    id: "stored-lessons",
                    title: "保存済みレッスン",
                    detail: "0件。写真からレッスンを作るとHomeとReviewに表示されます。",
                    systemImage: "tray",
                    status: .warning
                )
            }

            return DeviceDiagnosticItem(
                id: "stored-lessons",
                title: "保存済みレッスン",
                detail: "\(records.count)件 / 表示対象 \(visibleRecords.count)件 / 非表示 \(hiddenCount)件 / 最新: \(latest.mainSentenceID)",
                systemImage: "tray.fill",
                status: hiddenCount > 0 ? .warning : .ready
            )
        } catch {
            return DeviceDiagnosticItem(
                id: "stored-lessons",
                title: "保存済みレッスン",
                detail: error.localizedDescription,
                systemImage: "tray",
                status: .blocked
            )
        }
    }

    private func homeReviewVisibilityItem(modelContext: ModelContext) -> DeviceDiagnosticItem {
        do {
            let visibleRecords = try LessonRecordPersistence.fetchLearnerVisibleRecords(in: modelContext)
            guard let latest = visibleRecords.first else {
                return DeviceDiagnosticItem(
                    id: "home-review-visibility",
                    title: "Home/Review表示",
                    detail: "日本語訳つきの表示可能レッスンがありません。",
                    systemImage: "rectangle.on.rectangle",
                    status: .warning
                )
            }

            return DeviceDiagnosticItem(
                id: "home-review-visibility",
                title: "Home/Review表示",
                detail: "Home最新とReview対象: \(visibleRecords.count)件 / 最新: \(latest.mainSentenceID) / 訳: \(latest.mainSentenceJP)",
                systemImage: "rectangle.on.rectangle.fill",
                status: .ready
            )
        } catch {
            return DeviceDiagnosticItem(
                id: "home-review-visibility",
                title: "Home/Review表示",
                detail: error.localizedDescription,
                systemImage: "rectangle.on.rectangle",
                status: .blocked
            )
        }
    }

    private func saveRoundTripItem(modelContext: ModelContext) -> DeviceDiagnosticItem {
        var diagnosticRecordID: UUID?
        do {
            let record = try makeDiagnosticLessonRecord()
            diagnosticRecordID = record.id

            try LessonRecordPersistence.insertAndSave(record, in: modelContext)
            guard let savedRecord = try LessonRecordPersistence.fetchSavedRecord(id: record.id, in: modelContext) else {
                throw LessonRecordPersistenceError.savedRecordNotFound(record.id)
            }

            guard savedRecord.unreadableLessonSections.isEmpty else {
                return DeviceDiagnosticItem(
                    id: "save-roundtrip",
                    title: "保存読み戻し",
                    detail: "保存後に読み取れない項目: \(savedRecord.unreadableLessonSections.joined(separator: ", "))",
                    systemImage: "internaldrive",
                    status: .blocked
                )
            }

            guard savedRecord.photoLocalPath == nil else {
                return DeviceDiagnosticItem(
                    id: "save-roundtrip",
                    title: "保存読み戻し",
                    detail: "写真保存OFFの診断で写真パスが保存されました。",
                    systemImage: "internaldrive",
                    status: .blocked
                )
            }

            modelContext.delete(savedRecord)
            modelContext.processPendingChanges()
            try modelContext.save()
            modelContext.processPendingChanges()

            return DeviceDiagnosticItem(
                id: "save-roundtrip",
                title: "保存読み戻し",
                detail: "実アプリの保存先で保存、ID指定読み戻し、削除OK。",
                systemImage: "internaldrive.fill",
                status: .ready
            )
        } catch {
            if let diagnosticRecordID,
               let record = try? LessonRecordPersistence.fetchSavedRecord(id: diagnosticRecordID, in: modelContext) {
                modelContext.delete(record)
                try? modelContext.save()
            }

            return DeviceDiagnosticItem(
                id: "save-roundtrip",
                title: "保存読み戻し",
                detail: error.localizedDescription,
                systemImage: "internaldrive",
                status: .blocked
            )
        }
    }

    private func makeDiagnosticLessonRecord() throws -> LessonRecord {
        let sceneContext = SceneContext(
            timeText: "12:00",
            dayText: "Monday",
            locationLabel: .home,
            imageKeywords: [ImageKeyword(label: "diagnostic", confidence: 1.0)],
            userNote: "",
            languageLevel: .beginner
        )
        let lesson = Lesson(
            mainSentenceID: "Saya sedang belajar bahasa Indonesia.",
            mainSentenceJP: "私はインドネシア語を勉強しています。",
            vocabulary: [
                VocabularyItem(id: "saya", jp: "私"),
                VocabularyItem(id: "sedang", jp: "〜している"),
                VocabularyItem(id: "belajar", jp: "勉強する"),
                VocabularyItem(id: "bahasa Indonesia", jp: "インドネシア語"),
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
        return try LessonRecord(
            context: sceneContext,
            lesson: lesson,
            photoLocalPath: nil
        )
    }
}

private struct SupertonicResourceStatus {
    let runtimeAvailable: Bool
    let missingFiles: [String]

    static func current(bundle: Bundle = .main) -> SupertonicResourceStatus {
        let requiredOnnxFiles = [
            "tts.json",
            "unicode_indexer.json",
            "duration_predictor.onnx",
            "text_encoder.onnx",
            "vector_estimator.onnx",
            "vocoder.onnx"
        ]
        let requiredVoiceFiles = ["M1.json"]

        let missingOnnxFiles = missingFiles(
            in: bundle,
            folderName: "onnx",
            fileNames: requiredOnnxFiles
        )
        .map { "onnx/\($0)" }

        let missingVoiceFiles = missingFiles(
            in: bundle,
            folderName: "voice_styles",
            fileNames: requiredVoiceFiles
        )
        .map { "voice_styles/\($0)" }

        return SupertonicResourceStatus(
            runtimeAvailable: isRuntimeAvailable,
            missingFiles: missingOnnxFiles + missingVoiceFiles
        )
    }

    private static var isRuntimeAvailable: Bool {
        #if canImport(OnnxRuntimeBindings)
        true
        #else
        false
        #endif
    }

    private static func missingFiles(
        in bundle: Bundle,
        folderName: String,
        fileNames: [String]
    ) -> [String] {
        guard let folderURL = resourceFolderURL(in: bundle, folderName: folderName) else {
            return fileNames
        }

        return fileNames.filter { fileName in
            !FileManager.default.fileExists(atPath: folderURL.appendingPathComponent(fileName).path)
        }
    }

    private static func resourceFolderURL(in bundle: Bundle, folderName: String) -> URL? {
        guard let resourceURL = bundle.resourceURL else {
            return nil
        }

        let candidates = [
            resourceURL.appendingPathComponent(folderName, isDirectory: true),
            resourceURL.appendingPathComponent("assets/\(folderName)", isDirectory: true)
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private extension UNNotificationSetting {
    var japaneseName: String {
        switch self {
        case .enabled:
            "有効"
        case .disabled:
            "無効"
        case .notSupported:
            "非対応"
        @unknown default:
            "不明"
        }
    }
}

private extension UNAuthorizationStatus {
    var japaneseName: String {
        switch self {
        case .notDetermined:
            "未確認"
        case .denied:
            "拒否"
        case .authorized:
            "許可"
        case .provisional:
            "仮許可"
        case .ephemeral:
            "一時許可"
        @unknown default:
            "不明"
        }
    }
}
