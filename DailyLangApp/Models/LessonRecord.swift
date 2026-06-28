import Foundation
import SwiftData

@Model
final class LessonRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var photoLocalPath: String?
    var locationLabelRawValue: String
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
        vocabularyState.value ?? []
    }

    var conversation: [ConversationLine] {
        conversationState.value ?? []
    }

    var similarExpressions: [SimilarExpression] {
        similarExpressionsState.value ?? []
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
    case savedRecordNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .emptyLessonText:
            "本文または日本語訳が空のため、レッスンを保存できませんでした。"
        case .savedRecordNotFound(let id):
            "レッスン保存後の読み戻し確認に失敗しました。ID: \(id.uuidString)"
        }
    }
}

@MainActor
enum LessonRecordPersistence {
    static func insertAndSave(_ record: LessonRecord, in context: ModelContext) throws {
        guard hasVisibleLessonText(record) else {
            throw LessonRecordPersistenceError.emptyLessonText
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

    private static func hasVisibleLessonText(_ record: LessonRecord) -> Bool {
        !record.mainSentenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !record.mainSentenceJP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
