import Foundation

enum AppStorageKey {
    static let notificationStartHour = "notificationStartHour"
    static let notificationEndHour = "notificationEndHour"
    static let dailyNotificationCount = "dailyNotificationCount"
    static let showNotificationTimes = "showNotificationTimes"
    static let languageLevel = "languageLevel"
    static let lessonLanguage = "lessonLanguage"
    static let savePhotos = "savePhotos"
    static let openAIModel = "openAIModel"
}

struct LessonGenerationSettings: Sendable {
    var languageLevel: LanguageLevel
    var lessonLanguage: LessonLanguage
    var lessonSituation: LessonSituation
    var lessonGrammarFocus: LessonGrammarFocus = .simpleStatement
    var lessonVocabularyFocus: LessonVocabularyFocus = .objectDetails
    var recentVocabularyTerms: [String] = []
    var recentlyRepeatedExpressions: [String] = []
    var savePhotos: Bool
    var openAIAPIKey: String
    var openAIModel: String

    var hasOpenAIAPIKey: Bool {
        !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum LessonGrammarFocusHistory {
    private static let keyPrefix = "lessonGrammarFocusHistory.v1"

    static func nextFocus(
        for level: LanguageLevel,
        language: LessonLanguage,
        userDefaults: UserDefaults = .standard
    ) -> LessonGrammarFocus {
        let choices = LessonGrammarFocus.choices(for: level)
        let recent = recentFocuses(for: level, language: language, userDefaults: userDefaults)
        return choices.first { !recent.contains($0) } ?? choices.first ?? .simpleStatement
    }

    static func record(
        _ focus: LessonGrammarFocus,
        level: LanguageLevel,
        language: LessonLanguage,
        userDefaults: UserDefaults = .standard
    ) {
        let choices = LessonGrammarFocus.choices(for: level)
        guard choices.contains(focus) else {
            return
        }

        let existing = recentFocuses(for: level, language: language, userDefaults: userDefaults)
        // Retaining at most n - 1 values lets every eligible pattern get a turn before repetition.
        let recentLimit = max(choices.count - 1, 0)
        let updated = ([focus] + existing.filter { $0 != focus }).prefix(recentLimit)
        userDefaults.set(updated.map(\.rawValue), forKey: key(for: level, language: language))
    }

    private static func recentFocuses(
        for level: LanguageLevel,
        language: LessonLanguage,
        userDefaults: UserDefaults
    ) -> [LessonGrammarFocus] {
        let validChoices = Set(LessonGrammarFocus.choices(for: level))
        return (userDefaults.stringArray(forKey: key(for: level, language: language)) ?? [])
            .compactMap(LessonGrammarFocus.init(rawValue:))
            .filter { validChoices.contains($0) }
    }

    private static func key(for level: LanguageLevel, language: LessonLanguage) -> String {
        "\(keyPrefix).\(language.rawValue).\(level.rawValue)"
    }
}

enum LessonVocabularyFocusHistory {
    private static let keyPrefix = "lessonVocabularyFocusHistory.v1"

    static func nextFocus(
        for level: LanguageLevel,
        language: LessonLanguage,
        userDefaults: UserDefaults = .standard
    ) -> LessonVocabularyFocus {
        let recent = userDefaults.stringArray(forKey: key(level, language)) ?? []
        return LessonVocabularyFocus.allCases.first { !recent.contains($0.rawValue) } ?? .objectDetails
    }

    static func record(
        _ focus: LessonVocabularyFocus,
        level: LanguageLevel,
        language: LessonLanguage,
        userDefaults: UserDefaults = .standard
    ) {
        let existing = (userDefaults.stringArray(forKey: key(level, language)) ?? [])
            .compactMap(LessonVocabularyFocus.init(rawValue:))
        // Advance only after saving; failed generation must not consume a perspective.
        let recentLimit = LessonVocabularyFocus.allCases.count - 1
        let updated = ([focus] + existing.filter { $0 != focus }).prefix(recentLimit)
        userDefaults.set(updated.map(\.rawValue), forKey: key(level, language))
    }

    private static func key(_ level: LanguageLevel, _ language: LessonLanguage) -> String {
        "\(keyPrefix).\(language.rawValue).\(level.rawValue)"
    }
}

enum AppDefaults {
    static let notificationStartHour = 9
    static let notificationEndHour = 21
    static let dailyNotificationCount = 3
    static let openAIModel = "gpt-5.4-mini"
}

enum AppLaunchArgument {
    static let sampleScene = "-DailyLangSampleScene"
    static let openSettings = "-DailyLangOpenSettings"
    static let exportDiagnostics = "-DailyLangExportDiagnostics"
    static let scheduleRandomNotifications = "-DailyLangScheduleRandomNotifications"
    static let scheduleTestNotification = "-DailyLangScheduleTestNotification"
    static let showNotificationTimes = "-DailyLangShowNotificationTimes"
    static let hideNotificationTimes = "-DailyLangHideNotificationTimes"
}
