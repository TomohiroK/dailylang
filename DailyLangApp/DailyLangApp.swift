import SwiftData
import SwiftUI

@main
struct DailyLangApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate
    @StateObject private var notificationLaunchHandler = NotificationLaunchHandler.shared
    @AppStorage(AppStorageKey.notificationStartHour) private var startHour = AppDefaults.notificationStartHour
    @AppStorage(AppStorageKey.notificationEndHour) private var endHour = AppDefaults.notificationEndHour
    @AppStorage(AppStorageKey.dailyNotificationCount) private var dailyNotificationCount = AppDefaults.dailyNotificationCount
    private let modelContainer = DailyLangModelContainer.make()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notificationLaunchHandler)
                .task {
                    migrateDefaultLocationLabelIfNeeded()
                    seedOpenAIKeyIfProvided()
                    await refreshNotificationsIfAuthorized()
                }
        }
        .modelContainer(modelContainer)
    }

    private func seedOpenAIKeyIfProvided() {
        _ = try? KeychainAPIKeyStore().seedFromEnvironmentIfAvailable()
    }

    private func migrateDefaultLocationLabelIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: AppStorageKey.didMigrateDefaultLocationLabel) else {
            return
        }

        let currentValue = defaults.string(forKey: AppStorageKey.defaultLocationLabel)
        if currentValue == nil || currentValue == LocationLabel.unknown.rawValue {
            defaults.set(AppDefaults.defaultLocationLabel, forKey: AppStorageKey.defaultLocationLabel)
        }
        defaults.set(true, forKey: AppStorageKey.didMigrateDefaultLocationLabel)
    }

    @MainActor
    private func refreshNotificationsIfAuthorized() async {
        try? await NotificationScheduler().refreshRandomPromptsIfAuthorized(
            startHour: startHour,
            endHour: endHour,
            countPerDay: dailyNotificationCount
        )
    }
}

enum DailyLangModelContainer {
    private static let storeFileName = "DailyLangLessons.store"

    static func make(storeURL explicitStoreURL: URL? = nil, fileManager: FileManager = .default) -> ModelContainer {
        let schema = Schema([LessonRecord.self])
        let storeURL = explicitStoreURL ?? applicationSupportURL(fileManager: fileManager)
            .appendingPathComponent(storeFileName)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("DailyLang SwiftData store could not be opened: \(error.localizedDescription)")
        }
    }

    private static func applicationSupportURL(fileManager: FileManager) -> URL {
        do {
            let url = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            fatalError("DailyLang Application Support directory could not be created: \(error.localizedDescription)")
        }
    }
}
