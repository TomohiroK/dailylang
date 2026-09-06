import Foundation
import SwiftData

@Model
final class LessonRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var photoLocalPath: String?
    var locationLabelRawValue: String
    var lessonLanguageRawValue: String?
    var lessonSituationRawValue: String?
    var imageKeywordsJSON: String
    var mainSentenceID: String
    var mainSentenceJP: String
    var vocabularyJSON: String
    var grammarNote: String
    var conversationJSON: String
    var similarExpressionsJSON: String
    var reviewStatusRawValue: String
    var favorite: Bool
    var sourceRawValue: String

    init(
        context: SceneContext,
        lesson: Lesson,
        photoLocalPath: String?
    ) throws {
        id = lesson.id
        createdAt = lesson.createdAt
        self.photoLocalPath = photoLocalPath
        locationLabelRawValue = context.locationLabel.rawValue
        lessonLanguageRawValue = context.lessonLanguage.rawValue
        lessonSituationRawValue = context.lessonSituation.rawValue
        imageKeywordsJSON = try StoredJSONCoding.encode(context.imageKeywords)
        mainSentenceID = lesson.mainSentenceID
        mainSentenceJP = lesson.mainSentenceJP
        vocabularyJSON = try StoredJSONCoding.encode(lesson.vocabulary)
        grammarNote = lesson.grammarNote
        conversationJSON = try StoredJSONCoding.encode(lesson.conversation)
        similarExpressionsJSON = try StoredJSONCoding.encode(lesson.similarExpressions)
        reviewStatusRawValue = ReviewStatus.new.rawValue
        favorite = false
        sourceRawValue = lesson.source.rawValue
    }

    var locationLabel: LocationLabel {
        LocationLabel(rawValue: locationLabelRawValue) ?? .unknown
    }

    var lessonLanguage: LessonLanguage {
        LessonLanguage(rawValue: lessonLanguageRawValue ?? "") ?? .indonesian
    }

    var lessonSituation: LessonSituation {
        LessonSituation(rawValue: lessonSituationRawValue ?? "") ?? .random
    }

    var reviewStatus: ReviewStatus {
        get { ReviewStatus(rawValue: reviewStatusRawValue) ?? .new }
        set { reviewStatusRawValue = newValue.rawValue }
    }

    var source: LessonGenerationSource {
        LessonGenerationSource(rawValue: sourceRawValue) ?? .local
    }

    var imageKeywords: [ImageKeyword] {
        imageKeywordsState.value ?? []
    }

    var vocabulary: [VocabularyItem] {
        VocabularyItem.itemsUsedInMainSentence(
            mainSentenceID,
            vocabulary: vocabularyState.value ?? []
        )
    }

    var conversation: [ConversationLine] {
        conversationState.value ?? []
    }

    var similarExpressions: [SimilarExpression] {
        similarExpressionsState.value ?? []
    }

    var hasLearnerVisibleText: Bool {
        !mainSentenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && LessonTextValidation.isValidJapaneseTranslation(mainSentenceJP, sourceText: mainSentenceID)
            && vocabulary.count >= 3
            && LessonTextValidation.isValidJapaneseTranslation(grammarNote)
            && conversation.count >= 2
            && conversation.allSatisfy {
                LessonTextValidation.isValidJapaneseTranslation($0.jp, sourceText: $0.id)
            }
            && similarExpressions.count >= 3
            && similarExpressions.allSatisfy {
                LessonTextValidation.isValidJapaneseTranslation($0.jp, sourceText: $0.id)
            }
    }

    var imageKeywordsState: StoredJSONDecodeState<[ImageKeyword]> {
        StoredJSONCoding.decodeState([ImageKeyword].self, from: imageKeywordsJSON)
    }

    var vocabularyState: StoredJSONDecodeState<[VocabularyItem]> {
        StoredJSONCoding.decodeState([VocabularyItem].self, from: vocabularyJSON)
    }

    var conversationState: StoredJSONDecodeState<[ConversationLine]> {
        StoredJSONCoding.decodeState([ConversationLine].self, from: conversationJSON)
    }

    var similarExpressionsState: StoredJSONDecodeState<[SimilarExpression]> {
        StoredJSONCoding.decodeState([SimilarExpression].self, from: similarExpressionsJSON)
    }

    var unreadableLessonSections: [String] {
        var sections: [String] = []
        if imageKeywordsState.isUnreadable {
            sections.append("画像キーワード")
        }
        if vocabularyState.isUnreadable {
            sections.append("単語")
        }
        if conversationState.isUnreadable {
            sections.append("会話例")
        }
        if similarExpressionsState.isUnreadable {
            sections.append("類似表現")
        }
        return sections
    }
}

enum LessonRecordPersistenceError: Equatable, LocalizedError {
    case emptyLessonText
    case missingJapaneseTranslation
    case invalidLessonContent
    case savedRecordNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .emptyLessonText:
            "本文または日本語訳が空のため、レッスンを保存できませんでした。"
        case .missingJapaneseTranslation:
            "日本語訳が含まれていないため、レッスンを保存できませんでした。"
        case .invalidLessonContent:
            "レッスン本文、単語、文法、会話のいずれかが不正なため保存できませんでした。"
        case .savedRecordNotFound(let id):
            "レッスン保存後の読み戻し確認に失敗しました。ID: \(id.uuidString)"
        }
    }
}

struct VocabularyFrequency: Identifiable, Equatable {
    let language: LessonLanguage
    let term: String
    let japaneseMeaning: String
    let occurrenceCount: Int
    let firstSeenAt: Date
    let lastSeenAt: Date

    var id: String {
        "\(language.rawValue)|\(VocabularyFrequencyIndex.normalizedTerm(term))"
    }

    var synchronizationToken: String {
        "\(id)|\(occurrenceCount)|\(japaneseMeaning)|\(lastSeenAt.timeIntervalSinceReferenceDate)"
    }
}

enum VocabularyFrequencyIndex {
    private static let normalizationLocale = Locale(identifier: "en_US_POSIX")

    private struct Key: Hashable {
        let language: LessonLanguage
        let normalizedTerm: String
    }

    private struct Aggregate {
        let language: LessonLanguage
        let term: String
        var occurrenceCount: Int
        var japaneseMeaningCounts: [String: Int]
        var firstSeenAt: Date
        var lastSeenAt: Date
    }

    static func make(from records: [LessonRecord]) -> [VocabularyFrequency] {
        var aggregates: [Key: Aggregate] = [:]

        for record in records where record.hasLearnerVisibleText {
            var termsInLesson = Set<String>()

            for vocabulary in record.vocabulary {
                let normalizedVocabularyTerm = normalizedTerm(vocabulary.id)
                guard !normalizedVocabularyTerm.isEmpty, termsInLesson.insert(normalizedVocabularyTerm).inserted else {
                    continue
                }

                let key = Key(language: record.lessonLanguage, normalizedTerm: normalizedVocabularyTerm)
                let japaneseMeaning = vocabulary.jp.trimmingCharacters(in: .whitespacesAndNewlines)

                if var aggregate = aggregates[key] {
                    aggregate.occurrenceCount += 1
                    aggregate.japaneseMeaningCounts[japaneseMeaning, default: 0] += 1
                    aggregate.firstSeenAt = min(aggregate.firstSeenAt, record.createdAt)
                    aggregate.lastSeenAt = max(aggregate.lastSeenAt, record.createdAt)
                    aggregates[key] = aggregate
                } else {
                    aggregates[key] = Aggregate(
                        language: record.lessonLanguage,
                        term: vocabulary.id.trimmingCharacters(in: .whitespacesAndNewlines),
                        occurrenceCount: 1,
                        japaneseMeaningCounts: [japaneseMeaning: 1],
                        firstSeenAt: record.createdAt,
                        lastSeenAt: record.createdAt
                    )
                }
            }
        }

        return aggregates.values
            .map { aggregate in
                VocabularyFrequency(
                    language: aggregate.language,
                    term: aggregate.term,
                    japaneseMeaning: preferredJapaneseMeaning(from: aggregate.japaneseMeaningCounts),
                    occurrenceCount: aggregate.occurrenceCount,
                    firstSeenAt: aggregate.firstSeenAt,
                    lastSeenAt: aggregate.lastSeenAt
                )
            }
            .sorted {
                if $0.occurrenceCount != $1.occurrenceCount {
                    return $0.occurrenceCount > $1.occurrenceCount
                }
                if $0.language.rawValue != $1.language.rawValue {
                    return $0.language.rawValue < $1.language.rawValue
                }
                return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
            }
    }

    static func normalizedTerm(_ term: String) -> String {
        term
            .folding(options: [.diacriticInsensitive], locale: normalizationLocale)
            .lowercased(with: normalizationLocale)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func preferredJapaneseMeaning(from counts: [String: Int]) -> String {
        counts
            .sorted {
                if $0.value != $1.value {
                    return $0.value > $1.value
                }
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            .first?
            .key ?? ""
    }
}

enum VocabularyStudyState: String, CaseIterable {
    case new
    case learning
    case review
    case relearning
}

enum VocabularyReviewRating: String, CaseIterable, Identifiable {
    case again
    case hard
    case good
    case easy

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .again:
            "もう一度"
        case .hard:
            "難しい"
        case .good:
            "できた"
        case .easy:
            "簡単"
        }
    }

    fileprivate var grade: Double {
        switch self {
        case .again:
            1
        case .hard:
            2
        case .good:
            3
        case .easy:
            4
        }
    }
}

@Model
final class VocabularyStudyRecord {
    @Attribute(.unique) var uniqueKey: String
    var languageRawValue: String
    var normalizedTerm: String
    var term: String
    var japaneseMeaning: String
    var appearanceCount: Int
    var firstObservedAt: Date
    var lastObservedAt: Date
    var registeredAt: Date
    var stateRawValue: String
    var learningStepIndex: Int
    var stabilityDays: Double
    var difficulty: Double
    var reviewCount: Int
    var lapseCount: Int
    var lastReviewAt: Date?
    var dueAt: Date?
    var lastRatingRawValue: String?

    init(frequency: VocabularyFrequency, registeredAt: Date) {
        uniqueKey = frequency.id
        languageRawValue = frequency.language.rawValue
        normalizedTerm = VocabularyFrequencyIndex.normalizedTerm(frequency.term)
        term = frequency.term
        japaneseMeaning = frequency.japaneseMeaning
        appearanceCount = frequency.occurrenceCount
        firstObservedAt = frequency.firstSeenAt
        lastObservedAt = frequency.lastSeenAt
        self.registeredAt = registeredAt
        stateRawValue = VocabularyStudyState.new.rawValue
        learningStepIndex = -1
        stabilityDays = 0
        difficulty = 0
        reviewCount = 0
        lapseCount = 0
        lastReviewAt = nil
        dueAt = nil
        lastRatingRawValue = nil
    }

    var language: LessonLanguage {
        LessonLanguage(rawValue: languageRawValue) ?? .indonesian
    }

    var state: VocabularyStudyState {
        get { VocabularyStudyState(rawValue: stateRawValue) ?? .new }
        set { stateRawValue = newValue.rawValue }
    }

    var lastRating: VocabularyReviewRating? {
        get { lastRatingRawValue.flatMap(VocabularyReviewRating.init(rawValue:)) }
        set { lastRatingRawValue = newValue?.rawValue }
    }

    var isNew: Bool {
        state == .new && reviewCount == 0
    }

    @discardableResult
    func synchronize(with frequency: VocabularyFrequency) -> Bool {
        guard uniqueKey == frequency.id else {
            return false
        }

        var didChange = false

        if term != frequency.term {
            term = frequency.term
            didChange = true
        }
        if japaneseMeaning != frequency.japaneseMeaning {
            japaneseMeaning = frequency.japaneseMeaning
            didChange = true
        }
        if frequency.occurrenceCount > appearanceCount {
            appearanceCount = frequency.occurrenceCount
            didChange = true
        }
        if frequency.firstSeenAt < firstObservedAt {
            firstObservedAt = frequency.firstSeenAt
            didChange = true
        }
        if frequency.lastSeenAt > lastObservedAt {
            lastObservedAt = frequency.lastSeenAt
            didChange = true
        }

        return didChange
    }
}

struct VocabularyReviewCard: Identifiable {
    let frequency: VocabularyFrequency
    let studyRecord: VocabularyStudyRecord

    var id: String {
        frequency.id
    }
}

enum VocabularyReviewQueue {
    static func make(
        frequencies: [VocabularyFrequency],
        studyRecords: [VocabularyStudyRecord],
        now: Date
    ) -> [VocabularyReviewCard] {
        let recordsByKey = Dictionary(
            studyRecords.map { ($0.uniqueKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return frequencies
            .compactMap { frequency in
                guard let studyRecord = recordsByKey[frequency.id] else {
                    return nil
                }
                return VocabularyReviewCard(frequency: frequency, studyRecord: studyRecord)
            }
            .filter { card in
                card.studyRecord.isNew || (card.studyRecord.dueAt ?? .distantFuture) <= now
            }
            .sorted(by: { lhs, rhs in
                let leftIsNew = lhs.studyRecord.isNew
                let rightIsNew = rhs.studyRecord.isNew
                if leftIsNew != rightIsNew {
                    return leftIsNew
                }

                if leftIsNew {
                    if lhs.studyRecord.registeredAt != rhs.studyRecord.registeredAt {
                        return lhs.studyRecord.registeredAt > rhs.studyRecord.registeredAt
                    }
                } else {
                    let leftDueAt = lhs.studyRecord.dueAt ?? .distantFuture
                    let rightDueAt = rhs.studyRecord.dueAt ?? .distantFuture
                    if leftDueAt != rightDueAt {
                        return leftDueAt < rightDueAt
                    }
                }

                if lhs.studyRecord.appearanceCount != rhs.studyRecord.appearanceCount {
                    return lhs.studyRecord.appearanceCount > rhs.studyRecord.appearanceCount
                }
                if lhs.frequency.language.rawValue != rhs.frequency.language.rawValue {
                    return lhs.frequency.language.rawValue < rhs.frequency.language.rawValue
                }
                return lhs.frequency.term.localizedCaseInsensitiveCompare(rhs.frequency.term) == .orderedAscending
            })
    }
}

enum VocabularyFSRSScheduler {
    private enum Parameter: Int {
        case initialAgain
        case initialHard
        case initialGood
        case initialEasy
        case initialDifficulty
        case initialDifficultyRating
        case difficultyChange
        case difficultyMeanReversion
        case recallStabilityBase
        case recallStabilityDecay
        case recallRetrievabilityGain
        case forgetStabilityBase
        case forgetDifficultyDecay
        case forgetStabilityGrowth
        case forgetRetrievabilityGain
        case hardPenalty
        case easyBonus
        case sameDayStabilityGain
        case sameDayStabilityOffset
        case sameDayStabilityDecay
        case forgettingCurveDecay
    }

    private static let defaultWeights: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194,
        0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629,
        1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]
    private static let desiredRetention = 0.9
    private static let secondsPerDay: TimeInterval = 86_400
    private static let learningSteps: [TimeInterval] = [60, 600]
    private static let relearningSteps: [TimeInterval] = [600]
    private static let minimumStability = 0.001
    private static let maximumIntervalDays = 36_500
    private static let minimumDifficulty = 1.0
    private static let maximumDifficulty = 10.0

    static func schedule(
        _ record: VocabularyStudyRecord,
        rating: VocabularyReviewRating,
        at now: Date
    ) {
        switch record.state {
        case .new:
            record.stabilityDays = initialStability(for: rating)
            record.difficulty = initialDifficulty(for: rating)
            record.learningStepIndex = 0
            scheduleLearning(record, rating: rating, steps: learningSteps, state: .learning, now: now)

        case .learning:
            updateMemoryState(for: record, rating: rating, at: now)
            scheduleLearning(record, rating: rating, steps: learningSteps, state: .learning, now: now)

        case .review:
            updateMemoryState(for: record, rating: rating, at: now)
            if rating == .again {
                record.lapseCount += 1
                record.learningStepIndex = 0
                scheduleLearning(record, rating: rating, steps: relearningSteps, state: .relearning, now: now)
            } else {
                scheduleReview(record, now: now)
            }

        case .relearning:
            updateMemoryState(for: record, rating: rating, at: now)
            scheduleLearning(record, rating: rating, steps: relearningSteps, state: .relearning, now: now)
        }

        record.reviewCount += 1
        record.lastReviewAt = now
        record.lastRating = rating
    }

    static func retrievability(of record: VocabularyStudyRecord, at now: Date) -> Double {
        guard let lastReviewAt = record.lastReviewAt, record.stabilityDays > 0 else {
            return 0
        }

        let elapsedDays = max(0, now.timeIntervalSince(lastReviewAt) / secondsPerDay)
        let decay = -weight(.forgettingCurveDecay)
        let factor = pow(desiredRetention, 1 / decay) - 1
        return pow(1 + factor * elapsedDays / record.stabilityDays, decay)
    }

    private static func updateMemoryState(
        for record: VocabularyStudyRecord,
        rating: VocabularyReviewRating,
        at now: Date
    ) {
        guard let lastReviewAt = record.lastReviewAt,
              record.stabilityDays > 0,
              record.difficulty > 0
        else {
            record.stabilityDays = initialStability(for: rating)
            record.difficulty = initialDifficulty(for: rating)
            return
        }

        let elapsedDays = max(0, now.timeIntervalSince(lastReviewAt) / secondsPerDay)
        if elapsedDays < 1 {
            record.stabilityDays = sameDayStability(
                stability: record.stabilityDays,
                rating: rating
            )
        } else {
            record.stabilityDays = nextStability(
                difficulty: record.difficulty,
                stability: record.stabilityDays,
                retrievability: retrievability(of: record, at: now),
                rating: rating
            )
        }
        record.difficulty = nextDifficulty(from: record.difficulty, rating: rating)
    }

    private static func scheduleLearning(
        _ record: VocabularyStudyRecord,
        rating: VocabularyReviewRating,
        steps: [TimeInterval],
        state: VocabularyStudyState,
        now: Date
    ) {
        let currentStep = min(max(record.learningStepIndex, 0), steps.count - 1)

        switch rating {
        case .again:
            record.state = state
            record.learningStepIndex = 0
            record.dueAt = now.addingTimeInterval(steps[0])

        case .hard:
            record.state = state
            record.learningStepIndex = currentStep
            let interval: TimeInterval
            if currentStep == 0, steps.count == 1 {
                interval = steps[0] * 1.5
            } else if currentStep == 0 {
                interval = (steps[0] + steps[1]) / 2
            } else {
                interval = steps[currentStep]
            }
            record.dueAt = now.addingTimeInterval(interval)

        case .good:
            if currentStep + 1 == steps.count {
                scheduleReview(record, now: now)
            } else {
                record.state = state
                record.learningStepIndex = currentStep + 1
                record.dueAt = now.addingTimeInterval(steps[currentStep + 1])
            }

        case .easy:
            scheduleReview(record, now: now)
        }
    }

    private static func scheduleReview(_ record: VocabularyStudyRecord, now: Date) {
        record.state = .review
        record.learningStepIndex = -1
        record.dueAt = now.addingTimeInterval(TimeInterval(nextIntervalDays(for: record)) * secondsPerDay)
    }

    private static func initialStability(for rating: VocabularyReviewRating) -> Double {
        max(weight(initialStabilityParameter(for: rating)), minimumStability)
    }

    private static func initialDifficulty(for rating: VocabularyReviewRating) -> Double {
        clampDifficulty(
            weight(.initialDifficulty) - exp(weight(.initialDifficultyRating) * (rating.grade - 1)) + 1
        )
    }

    private static func sameDayStability(stability: Double, rating: VocabularyReviewRating) -> Double {
        var increase = exp(weight(.sameDayStabilityGain) * (rating.grade - 3 + weight(.sameDayStabilityOffset)))
            * pow(stability, -weight(.sameDayStabilityDecay))
        if rating != .again {
            increase = max(increase, 1)
        }
        return max(stability * increase, minimumStability)
    }

    private static func nextStability(
        difficulty: Double,
        stability: Double,
        retrievability: Double,
        rating: VocabularyReviewRating
    ) -> Double {
        switch rating {
        case .again:
            let longTerm = weight(.forgetStabilityBase)
                * pow(difficulty, -weight(.forgetDifficultyDecay))
                * (pow(stability + 1, weight(.forgetStabilityGrowth)) - 1)
                * exp((1 - retrievability) * weight(.forgetRetrievabilityGain))
            let shortTerm = stability / exp(weight(.sameDayStabilityGain) * weight(.sameDayStabilityOffset))
            return max(min(longTerm, shortTerm), minimumStability)

        case .hard, .good, .easy:
            let hardPenalty = rating == .hard ? weight(.hardPenalty) : 1
            let easyBonus = rating == .easy ? weight(.easyBonus) : 1
            let increase = exp(weight(.recallStabilityBase))
                * (11 - difficulty)
                * pow(stability, -weight(.recallStabilityDecay))
                * (exp((1 - retrievability) * weight(.recallRetrievabilityGain)) - 1)
                * hardPenalty
                * easyBonus
            return max(stability * (1 + increase), minimumStability)
        }
    }

    private static func nextDifficulty(from difficulty: Double, rating: VocabularyReviewRating) -> Double {
        let easyBaseline = weight(.initialDifficulty)
            - exp(weight(.initialDifficultyRating) * (VocabularyReviewRating.easy.grade - 1))
            + 1
        let delta = -(weight(.difficultyChange) * (rating.grade - 3))
        let dampedDelta = (10 - difficulty) * delta / 9
        let adjusted = difficulty + dampedDelta
        let meanReverted = weight(.difficultyMeanReversion) * easyBaseline
            + (1 - weight(.difficultyMeanReversion)) * adjusted
        return clampDifficulty(meanReverted)
    }

    private static func nextIntervalDays(for record: VocabularyStudyRecord) -> Int {
        let decay = -weight(.forgettingCurveDecay)
        let factor = pow(desiredRetention, 1 / decay) - 1
        let interval = record.stabilityDays / factor * (pow(desiredRetention, 1 / decay) - 1)
        return min(max(Int(interval.rounded()), 1), maximumIntervalDays)
    }

    private static func initialStabilityParameter(for rating: VocabularyReviewRating) -> Parameter {
        switch rating {
        case .again:
            .initialAgain
        case .hard:
            .initialHard
        case .good:
            .initialGood
        case .easy:
            .initialEasy
        }
    }

    private static func clampDifficulty(_ difficulty: Double) -> Double {
        min(max(difficulty, minimumDifficulty), maximumDifficulty)
    }

    private static func weight(_ parameter: Parameter) -> Double {
        defaultWeights[parameter.rawValue]
    }
}

@MainActor
enum VocabularyStudyPersistence {
    static func synchronize(
        frequencies: [VocabularyFrequency],
        existingRecords: [VocabularyStudyRecord],
        in context: ModelContext,
        now: Date
    ) throws {
        let recordsByKey = Dictionary(
            existingRecords.map { ($0.uniqueKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var didChange = false

        for frequency in frequencies {
            if let studyRecord = recordsByKey[frequency.id] {
                didChange = studyRecord.synchronize(with: frequency) || didChange
            } else {
                context.insert(VocabularyStudyRecord(frequency: frequency, registeredAt: now))
                didChange = true
            }
        }

        if didChange {
            try context.save()
        }
    }

    static func recordReview(
        _ studyRecord: VocabularyStudyRecord,
        rating: VocabularyReviewRating,
        in context: ModelContext,
        now: Date
    ) throws {
        VocabularyFSRSScheduler.schedule(studyRecord, rating: rating, at: now)
        try context.save()
    }
}

@MainActor
enum LessonRecordPersistence {
    static func insertAndSave(_ record: LessonRecord, in context: ModelContext) throws {
        guard !record.mainSentenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !record.mainSentenceJP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw LessonRecordPersistenceError.emptyLessonText
        }
        guard LessonTextValidation.isValidJapaneseTranslation(
            record.mainSentenceJP,
            sourceText: record.mainSentenceID
        ) else {
            throw LessonRecordPersistenceError.missingJapaneseTranslation
        }
        guard record.hasLearnerVisibleText else {
            throw LessonRecordPersistenceError.invalidLessonContent
        }

        context.insert(record)
        context.processPendingChanges()
        try context.save()
        context.processPendingChanges()
    }

    static func fetchSavedRecord(id: UUID, in context: ModelContext) throws -> LessonRecord? {
        let targetID = id
        var descriptor = FetchDescriptor<LessonRecord>(
            predicate: #Predicate<LessonRecord> { record in
                record.id == targetID
            }
        )
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).first
    }

    static func fetchSavedRecords(in context: ModelContext) throws -> [LessonRecord] {
        var descriptor = FetchDescriptor<LessonRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor)
    }

    static func fetchLearnerVisibleRecords(in context: ModelContext) throws -> [LessonRecord] {
        try fetchSavedRecords(in: context).filter(\.hasLearnerVisibleText)
    }
}

enum LessonDailyLifeExpressionHistory {
    private static let recentLessonLimit = 6
    private static let repeatThreshold = 2
    private static let maximumExpressionCount = 5

    private struct ExpressionGroup {
        let canonicalTerms: [String]
    }

    static func recentlyRepeatedExpressions(
        from records: [LessonRecord],
        situation: LessonSituation,
        language: LessonLanguage
    ) -> [String] {
        guard isComparableHomeSituation(situation) else {
            return []
        }

        let recentComparableRecords = records
            .filter {
                $0.hasLearnerVisibleText
                    && $0.lessonLanguage == language
                    && isComparableHomeSituation($0.lessonSituation)
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(recentLessonLimit)

        guard !recentComparableRecords.isEmpty else {
            return []
        }

        var occurrences: [String: Int] = [:]
        for record in recentComparableRecords {
            let sentenceWords = targetLanguageWords(in: record.mainSentenceID)
            for group in dailyLifeExpressionGroups(for: language) {
                for term in group.canonicalTerms where sentenceWords.contains(term) {
                    occurrences[term, default: 0] += 1
                }
            }
        }

        return occurrences
            .filter { $0.value >= repeatThreshold }
            .sorted {
                if $0.value != $1.value {
                    return $0.value > $1.value
                }
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            .prefix(maximumExpressionCount)
            .map(\.key)
    }

    private static func isComparableHomeSituation(_ situation: LessonSituation) -> Bool {
        situation == .home || situation == .friendsHome
    }

    private static func dailyLifeExpressionGroups(for language: LessonLanguage) -> [ExpressionGroup] {
        switch language {
        case .indonesian:
            [
                ExpressionGroup(canonicalTerms: ["merapikan", "rapikan"]),
                ExpressionGroup(canonicalTerms: ["menata"]),
                ExpressionGroup(canonicalTerms: ["menyusun"]),
                ExpressionGroup(canonicalTerms: ["mengatur"]),
                ExpressionGroup(canonicalTerms: ["makan", "memakan"]),
                ExpressionGroup(canonicalTerms: ["minum", "meminum"]),
                ExpressionGroup(canonicalTerms: ["menyiapkan"]),
                ExpressionGroup(canonicalTerms: ["memasak"]),
                ExpressionGroup(canonicalTerms: ["menggunakan", "memakai"]),
                ExpressionGroup(canonicalTerms: ["membawa"]),
                ExpressionGroup(canonicalTerms: ["membaca"]),
                ExpressionGroup(canonicalTerms: ["menonton"]),
                ExpressionGroup(canonicalTerms: ["mendengarkan"]),
                ExpressionGroup(canonicalTerms: ["beristirahat"]),
                ExpressionGroup(canonicalTerms: ["berbicara", "mengobrol"]),
                ExpressionGroup(canonicalTerms: ["merawat"]),
                ExpressionGroup(canonicalTerms: ["memberi"]),
                ExpressionGroup(canonicalTerms: ["menerima"]),
                ExpressionGroup(canonicalTerms: ["mencari"]),
                ExpressionGroup(canonicalTerms: ["meletakkan", "menaruh"]),
                ExpressionGroup(canonicalTerms: ["memindahkan"]),
                ExpressionGroup(canonicalTerms: ["masuk"]),
                ExpressionGroup(canonicalTerms: ["keluar", "pulang", "pergi"]),
            ]
        case .english:
            [
                ExpressionGroup(canonicalTerms: ["tidy", "tidied", "tidying"]),
                ExpressionGroup(canonicalTerms: ["organize", "organized", "organizing"]),
                ExpressionGroup(canonicalTerms: ["arrange", "arranged", "arranging"]),
                ExpressionGroup(canonicalTerms: ["eat", "eating", "ate"]),
                ExpressionGroup(canonicalTerms: ["drink", "drinking", "drank"]),
                ExpressionGroup(canonicalTerms: ["serve", "serving", "served"]),
                ExpressionGroup(canonicalTerms: ["prepare", "preparing", "prepared"]),
                ExpressionGroup(canonicalTerms: ["cook", "cooking", "cooked"]),
                ExpressionGroup(canonicalTerms: ["use", "using", "used"]),
                ExpressionGroup(canonicalTerms: ["carry", "carrying", "carried"]),
                ExpressionGroup(canonicalTerms: ["read", "reading"]),
                ExpressionGroup(canonicalTerms: ["watch", "watching", "watched"]),
                ExpressionGroup(canonicalTerms: ["listen", "listening", "listened"]),
                ExpressionGroup(canonicalTerms: ["rest", "resting", "rested"]),
                ExpressionGroup(canonicalTerms: ["talk", "talking", "talked"]),
                ExpressionGroup(canonicalTerms: ["visit", "visiting", "visited"]),
                ExpressionGroup(canonicalTerms: ["care", "caring", "cared"]),
                ExpressionGroup(canonicalTerms: ["give", "giving", "gave"]),
                ExpressionGroup(canonicalTerms: ["receive", "receiving", "received"]),
                ExpressionGroup(canonicalTerms: ["look", "looking"]),
                ExpressionGroup(canonicalTerms: ["place", "placing", "placed"]),
                ExpressionGroup(canonicalTerms: ["move", "moving", "moved"]),
                ExpressionGroup(canonicalTerms: ["arrive", "arriving", "arrived"]),
                ExpressionGroup(canonicalTerms: ["leave", "leaving", "left"]),
            ]
        }
    }

    private static func targetLanguageWords(in sentence: String) -> Set<String> {
        Set(
            sentence
                .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
        )
    }
}
