import Foundation

enum AppStorageKey {
    static let notificationStartHour = "notificationStartHour"
    static let notificationEndHour = "notificationEndHour"
    static let dailyNotificationCount = "dailyNotificationCount"
    static let languageLevel = "languageLevel"
    static let savePhotos = "savePhotos"
    static let openAIModel = "openAIModel"
    static let defaultLocationLabel = "defaultLocationLabel"
    static let didMigrateDefaultLocationLabel = "didMigrateDefaultLocationLabel"
}

struct LessonGenerationSettings: Sendable {
    var languageLevel: LanguageLevel
    var savePhotos: Bool
    var openAIAPIKey: String
    var openAIModel: String
    var defaultLocationLabel: LocationLabel

    var hasOpenAIAPIKey: Bool {
        !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AppDefaults {
    static let notificationStartHour = 9
    static let notificationEndHour = 21
    static let dailyNotificationCount = 3
    static let openAIModel = "gpt-5.4-mini"
    static let defaultLocationLabel = LocationLabel.home.rawValue
}

enum AppLaunchArgument {
    static let sampleScene = "-DailyLangSampleScene"
    static let openSettings = "-DailyLangOpenSettings"
    static let exportDiagnostics = "-DailyLangExportDiagnostics"
}
