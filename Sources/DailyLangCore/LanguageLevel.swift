import Foundation

public enum LessonLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case indonesian
    case english

    public var id: String { rawValue }

    public var japaneseName: String {
        switch self {
        case .indonesian:
            "インドネシア語"
        case .english:
            "英語"
        }
    }

    public var englishName: String {
        switch self {
        case .indonesian:
            "Indonesian"
        case .english:
            "English"
        }
    }

    public var supertonicLanguageCode: String {
        switch self {
        case .indonesian:
            "id"
        case .english:
            "en"
        }
    }
}

public enum LessonGrammarFocus: String, CaseIterable, Codable, Sendable {
    case simpleStatement = "simple_statement"
    case currentAction = "current_action"
    case completedAction = "completed_action"
    case futurePlan = "future_plan"
    case purpose
    case sequence
    case cause
    case addition
    case alternative
    case contrast
    case condition
    case parallelAction = "parallel_action"
    case uncertainty

    public static func choices(for level: LanguageLevel) -> [LessonGrammarFocus] {
        switch level {
        case .beginner:
            [
                .simpleStatement,
                .currentAction,
                .completedAction,
                .futurePlan,
                .purpose,
            ]
        case .intermediate:
            [
                .simpleStatement,
                .currentAction,
                .completedAction,
                .futurePlan,
                .purpose,
                .sequence,
                .cause,
                .addition,
                .alternative,
                .contrast,
                .condition,
                .parallelAction,
            ]
        case .advanced:
            [
                .simpleStatement,
                .currentAction,
                .completedAction,
                .futurePlan,
                .purpose,
                .sequence,
                .cause,
                .addition,
                .alternative,
                .contrast,
                .condition,
                .parallelAction,
                .uncertainty,
            ]
        }
    }

    public func promptInstruction(for language: LessonLanguage) -> String {
        switch (language, self) {
        case (.indonesian, .simpleStatement):
            "Use a direct present statement. Do not use sedang, sambil, or sepertinya as filler."
        case (.indonesian, .currentAction):
            "Describe a current action with sedang if it sounds natural, but do not add sambil unless two distinct actions are grounded in the scene."
        case (.indonesian, .completedAction):
            "Use a completed or recent action with sudah or baru saja only when it can naturally relate to the visible object or selected situation. Do not invent an unseen past event."
        case (.indonesian, .futurePlan):
            "Use a near-future plan or intention with akan, ingin, or berencana, tied to a visible object or the selected situation. Do not invent a definite future event."
        case (.indonesian, .purpose):
            "Express purpose with untuk, agar, or supaya. Keep the purpose practical and tied to the visible object or selected situation."
        case (.indonesian, .sequence):
            "Express order or timing with sebelum, setelah, ketika, saat, lalu, or kemudian. Do not invent a detailed event sequence that the scene cannot support."
        case (.indonesian, .cause):
            "Express a grounded reason or result with karena, sebab, jadi, or sehingga. Do not invent a motive or outcome that is absent from the scene."
        case (.indonesian, .addition):
            "Express addition with dan juga, selain, baik ... maupun ..., or bukan hanya ... tetapi juga. Use two concrete scene elements when the construction needs two elements."
        case (.indonesian, .alternative):
            "Express a practical choice or alternative with atau. Keep both options related to the visible object or selected situation."
        case (.indonesian, .contrast):
            "Express a real contrast with tetapi, namun, meskipun, or walaupun. Do not manufacture a contrast from uncertain visual details."
        case (.indonesian, .condition):
            "Use a practical conditional with kalau or jika. Keep the condition close to the visible object or selected situation and do not invent a story."
        case (.indonesian, .parallelAction):
            "Use sambil for two genuinely compatible actions. Do not use sepertinya, and do not add sambil merely to make the sentence longer."
        case (.indonesian, .uncertainty):
            "Use sepertinya only to soften a genuinely uncertain observation. It must not be a sentence-opening filler, and do not pair it with sambil unless both are independently natural."
        case (.english, .simpleStatement):
            "Use a direct present statement. Do not use progressive wording, while, or apparently as filler."
        case (.english, .currentAction):
            "Describe a current action with a progressive form if it sounds natural, but do not add while unless two distinct actions are grounded in the scene."
        case (.english, .completedAction):
            "Use a completed or recent action with already or just only when it can naturally relate to the visible object or selected situation. Do not invent an unseen past event."
        case (.english, .futurePlan):
            "Use a near-future plan or intention with will, want to, or plan to, tied to a visible object or the selected situation. Do not invent a definite future event."
        case (.english, .purpose):
            "Express purpose with to, so that, or in order to. Keep the purpose practical and tied to the visible object or selected situation."
        case (.english, .sequence):
            "Express order or timing with before, after, when, then, or later. Do not invent a detailed event sequence that the scene cannot support."
        case (.english, .cause):
            "Express a grounded reason or result with because, so, or therefore. Do not invent a motive or outcome that is absent from the scene."
        case (.english, .addition):
            "Express addition with also, as well as, both ... and ..., or not only ... but also. Use two concrete scene elements when the construction needs two elements."
        case (.english, .alternative):
            "Express a practical choice or alternative with or. Keep both options related to the visible object or selected situation."
        case (.english, .contrast):
            "Express a real contrast with but, however, although, or even though. Do not manufacture a contrast from uncertain visual details."
        case (.english, .condition):
            "Use a practical conditional with if. Keep the condition close to the visible object or selected situation and do not invent a story."
        case (.english, .parallelAction):
            "Use while for two genuinely compatible actions. Do not use apparently, and do not add while merely to make the sentence longer."
        case (.english, .uncertainty):
            "Use apparently only to soften a genuinely uncertain observation. It must not be a sentence-opening filler, and do not pair it with while unless both are independently natural."
        }
    }
}

public enum LessonSituation: String, CaseIterable, Codable, Identifiable, Sendable {
    case random
    case home
    case friendsHome = "friends_home"
    case office
    case school
    case publicTransport = "public_transport"
    case park
    case shop
    case restaurantCafe = "restaurant_cafe"
    case airportOrPort = "airport_or_port"
    case date
    case outAndAbout = "out_and_about"
    case nature

    public var id: String { rawValue }

    public var japaneseName: String {
        switch self {
        case .random:
            "ランダム"
        case .home:
            "自宅"
        case .friendsHome:
            "友人宅"
        case .office:
            "会社"
        case .school:
            "学校"
        case .publicTransport:
            "公共交通機関を利用中"
        case .park:
            "公園"
        case .shop:
            "お店"
        case .restaurantCafe:
            "レストラン・カフェ"
        case .airportOrPort:
            "空港・港"
        case .date:
            "デート"
        case .outAndAbout:
            "外出中"
        case .nature:
            "自然の中"
        }
    }

    public var promptValue: String {
        switch self {
        case .random:
            "random"
        case .home:
            "at home"
        case .friendsHome:
            "at a friend's home"
        case .office:
            "at work or in an office"
        case .school:
            "at school"
        case .publicTransport:
            "using public transportation"
        case .park:
            "in a park"
        case .shop:
            "at a shop"
        case .restaurantCafe:
            "at a restaurant or cafe"
        case .airportOrPort:
            "at an airport or port"
        case .date:
            "on a date"
        case .outAndAbout:
            "out and about"
        case .nature:
            "in nature"
        }
    }

    public static var concreteCases: [LessonSituation] {
        allCases.filter { $0 != .random }
    }

    public func resolved() -> LessonSituation {
        var generator = SystemRandomNumberGenerator()
        return resolved(using: &generator)
    }

    public func resolved<Generator: RandomNumberGenerator>(
        using generator: inout Generator
    ) -> LessonSituation {
        guard self == .random else {
            return self
        }
        return Self.concreteCases.randomElement(using: &generator) ?? .home
    }
}

public enum LanguageLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case beginner
    case intermediate
    case advanced

    public var id: String { rawValue }

    public var japaneseName: String {
        switch self {
        case .beginner:
            "初級"
        case .intermediate:
            "中級"
        case .advanced:
            "上級"
        }
    }

    public var mainSentenceWordRange: ClosedRange<Int> {
        switch self {
        case .beginner:
            1...7
        case .intermediate:
            10...15
        case .advanced:
            20...40
        }
    }

    public var mainSentenceWordCountGuidance: String {
        mainSentenceWordCountGuidance(for: .indonesian)
    }

    public func mainSentenceWordCountGuidance(for language: LessonLanguage) -> String {
        switch self {
        case .beginner:
            "7 \(language.englishName) words or fewer"
        case .intermediate:
            "10 to 15 \(language.englishName) words"
        case .advanced:
            "20 to 40 \(language.englishName) words"
        }
    }

    public var preferredMainSentenceWordCountGuidance: String {
        preferredMainSentenceWordCountGuidance(for: .indonesian)
    }

    public func preferredMainSentenceWordCountGuidance(for language: LessonLanguage) -> String {
        switch self {
        case .beginner:
            "5 to 7 \(language.englishName) words"
        case .intermediate:
            "11 to 14 \(language.englishName) words"
        case .advanced:
            "24 to 30 \(language.englishName) words"
        }
    }

    public var vocabularyCountRange: ClosedRange<Int> {
        switch self {
        case .beginner:
            3...5
        case .intermediate:
            5...7
        case .advanced:
            7...10
        }
    }

    public var vocabularyCountGuidance: String {
        switch self {
        case .beginner:
            "3 to 5 vocabulary items"
        case .intermediate:
            "5 to 7 vocabulary items"
        case .advanced:
            "7 to 10 vocabulary items"
        }
    }

    public var minimumVocabularyCount: Int {
        vocabularyCountRange.lowerBound
    }

    public var maximumVocabularyCount: Int {
        vocabularyCountRange.upperBound
    }

    public var generationGuidance: String {
        generationGuidance(for: .indonesian)
    }

    public func generationGuidance(for language: LessonLanguage) -> String {
        switch self {
        case .beginner:
            "短文中心。基本文型を使い、語彙を少なめにして日本語解説を多めにする。"
        case .intermediate:
            language == .indonesian
                ? "接続表現、過去、予定、目的、順序、追加、選択、対比、仮定を写真に合う範囲で使い分ける。"
                : "写真に合う範囲で、接続表現、過去、予定、目的、順序、追加、選択、対比、仮定を使い分ける。"
        case .advanced:
            "自然な表現を使い、接続詞・時制・仮定・対比の選択を広げる。"
        }
    }
}
