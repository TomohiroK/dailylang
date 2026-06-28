import SwiftData
import SwiftUI

struct SettingsView: View {
    private enum Constants {
        static let speechTestSentence = "Saya sedang belajar bahasa Indonesia."
        static let notificationSuccessMessageSeconds: TimeInterval = 8
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppStorageKey.notificationStartHour) private var startHour = AppDefaults.notificationStartHour
    @AppStorage(AppStorageKey.notificationEndHour) private var endHour = AppDefaults.notificationEndHour
    @AppStorage(AppStorageKey.dailyNotificationCount) private var dailyNotificationCount = AppDefaults.dailyNotificationCount
    @AppStorage(AppStorageKey.showNotificationTimes) private var showNotificationTimes = false
    @AppStorage(AppStorageKey.languageLevel) private var languageLevelRawValue = LanguageLevel.beginner.rawValue
    @AppStorage(AppStorageKey.savePhotos) private var savePhotos = false
    @AppStorage(AppStorageKey.openAIModel) private var openAIModel = AppDefaults.openAIModel
    @AppStorage(AppStorageKey.defaultLocationLabel) private var defaultLocationRawValue = AppDefaults.defaultLocationLabel

    @State private var createdSampleRecord: LessonRecord?
    @State private var diagnosticItems: [DeviceDiagnosticItem] = []
    @State private var isCreatingSampleLesson = false
    @State private var isRefreshingDiagnostics = false
    @State private var isSchedulingNotifications = false
    @State private var isSchedulingTestNotification = false
    @State private var isShowingCreatedSampleLesson = false
    @StateObject private var speechPlayer = SupertonicSpeechPlayer()
    @State private var scheduledNotifications: [ScheduledNotificationSnapshot] = []
    @State private var notificationStatusMessage: String?
    @State private var notificationStatusClearTask: Task<Void, Never>?
    @State private var statusMessage: String?

    private let notificationScheduler = NotificationScheduler()
    private let locationLabelService = LocationLabelService()
    private let diagnosticsService = DeviceDiagnosticsService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if diagnosticItems.isEmpty {
                        HStack {
                            ProgressView()
                            Text("診断中")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(diagnosticItems) { item in
                            DeviceDiagnosticRow(item: item)
                        }
                    }

                    Button {
                        Task {
                            await refreshDiagnostics(showLoading: true)
                        }
                    } label: {
                        Label("再チェック", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshingDiagnostics)

                    Button {
                        Task {
                            await createOnDeviceSampleLesson()
                        }
                    } label: {
                        Label(isCreatingSampleLesson ? "作成中" : "サンプルレッスンを作成", systemImage: "doc.badge.plus")
                    }
                    .disabled(isCreatingSampleLesson)

                    Button {
                        speechPlayer.toggle(sentence: Constants.speechTestSentence)
                    } label: {
                        Label(speechTestButtonTitle, systemImage: speechPlayer.iconName)
                    }
                    .accessibilityLabel(speechPlayer.buttonAccessibilityLabel)
                } header: {
                    Text("端末内診断")
                } footer: {
                    Text("実機確認では、ここがすべて利用可能になっているかを先に確認します。")
                }

                Section("通知") {
                    Stepper("開始 \(startHour):00", value: $startHour, in: 0...23)
                    Stepper("終了 \(endHour):00", value: $endHour, in: 1...24)
                    Stepper("1日の回数 \(dailyNotificationCount)", value: $dailyNotificationCount, in: 1...10)

                    Button {
                        Task {
                            await scheduleNotifications()
                        }
                    } label: {
                        Label(isSchedulingNotifications ? "通知を予約中" : "通知を予約", systemImage: "bell.badge")
                    }
                    .disabled(isSchedulingNotifications || isSchedulingTestNotification)

                    Button {
                        Task {
                            await scheduleTestNotification()
                        }
                    } label: {
                        Label(isSchedulingTestNotification ? "テスト通知を予約中" : "テスト通知", systemImage: "bell.and.waves.left.and.right")
                    }
                    .disabled(isSchedulingNotifications || isSchedulingTestNotification)

                    Toggle("通知時刻を表示", isOn: $showNotificationTimes)
                        .onChange(of: showNotificationTimes) { _, _ in
                            Task {
                                await refreshNotificationTimes()
                            }
                        }

                    if showNotificationTimes {
                        notificationTimesList
                    }

                    if let notificationStatusMessage {
                        Label(notificationStatusMessage, systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("学習") {
                    Picker("レベル", selection: $languageLevelRawValue) {
                        ForEach(LanguageLevel.allCases) { level in
                            Text(level.japaneseName).tag(level.rawValue)
                        }
                    }

                    Picker("現在地ラベル", selection: $defaultLocationRawValue) {
                        ForEach(LocationLabel.allCases) { label in
                            Text(label.japaneseName).tag(label.rawValue)
                        }
                    }

                    Button {
                        locationLabelService.requestAuthorizationIfNeeded()
                        statusMessage = "位置情報は移動中の道路判定に使います。停止中は現在地ラベルを使います。"
                    } label: {
                        Label("位置情報を許可", systemImage: "location")
                    }
                }

                Section {
                    Toggle("写真を端末内に保存", isOn: $savePhotos)
                } header: {
                    Text("プライバシー")
                } footer: {
                    Text("写真そのものは送信しません。OpenAIには端末内で認識した画像キーワード・時刻・場所ラベルだけを送ります。")
                }

                Section("OpenAI") {
                    TextField("モデル", text: $openAIModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Label("APIキーは開発環境からKeychainへ渡されます", systemImage: "key.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                Task {
                    await refreshDiagnostics(showLoading: true)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    return
                }
                Task {
                    await refreshDiagnostics(showLoading: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dailyLangNotificationScheduleDidChange)) { _ in
                Task {
                    await refreshNotificationTimes()
                }
            }
            .navigationDestination(isPresented: $isShowingCreatedSampleLesson) {
                if let createdSampleRecord {
                    LessonDetailView(record: createdSampleRecord)
                } else {
                    ContentUnavailableView("レッスンを表示できません", systemImage: "exclamationmark.triangle")
                }
            }
            .alert("音声テストできませんでした", isPresented: speechErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(speechPlayer.errorMessage ?? "もう一度試してください。")
            }
            .onDisappear {
                notificationStatusClearTask?.cancel()
                speechPlayer.stop()
            }
        }
    }

    @MainActor
    private func scheduleNotifications() async {
        guard !isSchedulingNotifications else {
            return
        }

        isSchedulingNotifications = true
        setNotificationStatus("通知を予約中です。")
        defer {
            isSchedulingNotifications = false
        }

        do {
            let summary = try await notificationScheduler.scheduleRandomPrompts(
                startHour: startHour,
                endHour: endHour,
                countPerDay: dailyNotificationCount
            )
            await refreshDiagnostics(showLoading: false)
            setNotificationStatus(
                summary.statusMessage,
                autoClearAfter: Constants.notificationSuccessMessageSeconds
            )
        } catch {
            setNotificationStatus(error.localizedDescription)
        }
    }

    @MainActor
    private func scheduleTestNotification() async {
        guard !isSchedulingTestNotification else {
            return
        }

        isSchedulingTestNotification = true
        setNotificationStatus("テスト通知を予約中です。")
        defer {
            isSchedulingTestNotification = false
        }

        do {
            try await notificationScheduler.scheduleTestPrompt()
            await refreshDiagnostics(showLoading: false)
            setNotificationStatus(
                "5秒後のテスト通知を予約しました。集中モード中は表示が抑制されることがあります。",
                autoClearAfter: Constants.notificationSuccessMessageSeconds
            )
        } catch {
            setNotificationStatus(error.localizedDescription)
        }
    }

    @MainActor
    private func setNotificationStatus(
        _ message: String?,
        autoClearAfter delay: TimeInterval? = nil
    ) {
        notificationStatusClearTask?.cancel()
        notificationStatusMessage = message

        guard let delay else {
            notificationStatusClearTask = nil
            return
        }

        notificationStatusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            notificationStatusMessage = nil
            await refreshDiagnostics(showLoading: false)
        }
    }

    @MainActor
    private func refreshDiagnostics(showLoading: Bool = true) async {
        if showLoading {
            isRefreshingDiagnostics = true
        }
        diagnosticItems = await diagnosticsService.loadItems(modelContext: modelContext)
        await refreshNotificationTimes()
        if showLoading {
            isRefreshingDiagnostics = false
        }
    }

    @MainActor
    private func refreshNotificationTimes() async {
        guard showNotificationTimes else {
            scheduledNotifications = []
            return
        }

        scheduledNotifications = await notificationScheduler.scheduledNotificationSnapshots()
    }

    @MainActor
    private func createOnDeviceSampleLesson() async {
        guard !isCreatingSampleLesson else {
            return
        }

        isCreatingSampleLesson = true
        statusMessage = "画像解析中"
        defer {
            isCreatingSampleLesson = false
        }

        do {
            let service = LessonCompositionService()
            let result = try await service.composeLesson(
                from: SampleSceneImageFactory.makeOfficeSceneImage(),
                userNote: "",
                settings: onDeviceSampleSettings,
                onPhaseChange: { nextPhase in
                    statusMessage = nextPhase.title
                }
            )
            let record = try LessonRecord(
                context: result.context,
                lesson: result.lesson,
                photoLocalPath: result.photoLocalPath
            )
            try LessonRecordPersistence.insertAndSave(record, in: modelContext)
            createdSampleRecord = record
            statusMessage = "OpenAIサンプルレッスンを保存しました。"
            await refreshDiagnostics(showLoading: true)
            isShowingCreatedSampleLesson = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var onDeviceSampleSettings: LessonGenerationSettings {
        LessonGenerationSettings(
            languageLevel: LanguageLevel(rawValue: languageLevelRawValue) ?? .beginner,
            savePhotos: false,
            openAIAPIKey: (try? KeychainAPIKeyStore().loadAPIKey()) ?? "",
            openAIModel: AppDefaults.openAIModel,
            defaultLocationLabel: LocationLabel(rawValue: AppDefaults.defaultLocationLabel) ?? .home
        )
    }

    private var speechTestButtonTitle: String {
        if speechPlayer.isGenerating {
            return "音声生成中"
        }
        return speechPlayer.isPlaying ? "音声テストを停止" : "音声テストを再生"
    }

    private var notificationTimesList: some View {
        Group {
            if scheduledNotifications.isEmpty {
                Text("予約済み通知はありません")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scheduledNotifications) { notification in
                    LabeledContent(notification.kind.japaneseName) {
                        Text(notificationTimeText(notification.nextTriggerDate))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func notificationTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private var speechErrorBinding: Binding<Bool> {
        Binding(
            get: { speechPlayer.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    speechPlayer.errorMessage = nil
                }
            }
        )
    }
}

private struct DeviceDiagnosticRow: View {
    let item: DeviceDiagnosticItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .accessibilityLabel(statusText)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch item.status {
        case .ready:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .blocked:
            "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .ready:
            .green
        case .warning:
            .orange
        case .blocked:
            .red
        }
    }

    private var statusText: String {
        switch item.status {
        case .ready:
            "利用可能"
        case .warning:
            "確認が必要"
        case .blocked:
            "利用不可"
        }
    }
}
