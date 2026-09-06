import SwiftData
import SwiftUI

struct ReviewView: View {
    private enum ReviewContent: String, CaseIterable, Identifiable {
        case sentences
        case vocabulary

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sentences:
                "例文"
            case .vocabulary:
                "単語"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LessonRecord.createdAt, order: .reverse) private var lessons: [LessonRecord]
    @Query(sort: \VocabularyStudyRecord.registeredAt, order: .reverse) private var vocabularyStudyRecords: [VocabularyStudyRecord]
    @State private var selectedContent: ReviewContent = .sentences
    @State private var currentIndex = 0
    @State private var isAnswerVisible = false
    @State private var vocabularyIndex = 0
    @State private var isVocabularyAnswerVisible = false
    @State private var saveErrorMessage: String?

    private var savedLessons: [LessonRecord] {
        lessons.filter(\.hasLearnerVisibleText)
    }

    private var vocabularyFrequencies: [VocabularyFrequency] {
        VocabularyFrequencyIndex.make(from: savedLessons)
    }

    private var vocabularyCards: [VocabularyReviewCard] {
        VocabularyReviewQueue.make(
            frequencies: vocabularyFrequencies,
            studyRecords: vocabularyStudyRecords,
            now: Date()
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("復習内容", selection: $selectedContent) {
                    ForEach(ReviewContent.allCases) { content in
                        Text(content.title).tag(content)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch selectedContent {
                    case .sentences:
                        sentenceReview
                    case .vocabulary:
                        vocabularyReview
                    }
                }
            }
            .navigationTitle("Review")
            .onChange(of: selectedContent) { _, _ in
                isAnswerVisible = false
                isVocabularyAnswerVisible = false
            }
            .onChange(of: vocabularyCards.map(\.id)) { _, _ in
                vocabularyIndex = 0
                isVocabularyAnswerVisible = false
            }
            .onAppear {
                synchronizeVocabularyStudyRecords()
            }
            .onChange(of: vocabularyFrequencies.map(\.synchronizationToken)) { _, _ in
                synchronizeVocabularyStudyRecords()
            }
            .alert("保存できませんでした", isPresented: saveErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "もう一度試してください。")
            }
        }
    }

    @ViewBuilder
    private var sentenceReview: some View {
        if let lesson = currentLesson {
            VStack(alignment: .leading, spacing: 24) {
                Text(lesson.mainSentenceJP)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if isAnswerVisible {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(lesson.mainSentenceID)
                            .font(.title3.weight(.semibold))
                        Text(lesson.grammarNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        isAnswerVisible = true
                    } label: {
                        Label("答えを見る", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 12) {
                    Button {
                        mark(lesson, as: .again)
                    } label: {
                        Label("もう一度", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        mark(lesson, as: .remembered)
                    } label: {
                        Label("覚えた", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .disabled(!isAnswerVisible)

                Spacer()
            }
            .padding()
        } else {
            ContentUnavailableView(
                "保存済みレッスンがありません",
                systemImage: "checkmark.seal",
                description: Text("写真からレッスンを作ると、ここに復習カードが表示されます。")
            )
        }
    }

    @ViewBuilder
    private var vocabularyReview: some View {
        if let vocabulary = currentVocabulary {
            VStack(alignment: .leading, spacing: 24) {
                Text("保存済みの単語 \(vocabularyFrequencies.count)語")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text(vocabulary.frequency.japaneseMeaning)
                        .font(.largeTitle.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(vocabularySubtitle(for: vocabulary))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if isVocabularyAnswerVisible {
                    Text(vocabulary.frequency.term)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            vocabularyRatingButton(.again, for: vocabulary)
                            vocabularyRatingButton(.hard, for: vocabulary)
                        }
                        HStack(spacing: 12) {
                            vocabularyRatingButton(.good, for: vocabulary)
                            vocabularyRatingButton(.easy, for: vocabulary)
                        }
                    }
                } else {
                    Button {
                        isVocabularyAnswerVisible = true
                    } label: {
                        Label("答えを見る", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()
            }
            .padding()
        } else {
            ContentUnavailableView(
                vocabularyFrequencies.isEmpty ? "まだ単語がありません" : "今は復習予定の単語がありません",
                systemImage: "text.book.closed",
                description: Text(vocabularyFrequencies.isEmpty
                    ? "レッスンを作ると、本文で使われた単語だけをここで確認できます。"
                    : "新しい単語または次回復習日時になった単語がここに表示されます。")
            )
        }
    }

    private var currentLesson: LessonRecord? {
        guard !savedLessons.isEmpty else {
            return nil
        }
        return savedLessons[min(currentIndex, savedLessons.count - 1)]
    }

    private var currentVocabulary: VocabularyReviewCard? {
        guard !vocabularyCards.isEmpty else {
            return nil
        }
        return vocabularyCards[min(vocabularyIndex, vocabularyCards.count - 1)]
    }

    private func mark(_ lesson: LessonRecord, as status: ReviewStatus) {
        let previousStatus = lesson.reviewStatus
        lesson.reviewStatus = status

        do {
            try modelContext.save()
            isAnswerVisible = false
            if currentIndex < savedLessons.count - 1 {
                currentIndex += 1
            } else {
                currentIndex = 0
            }
        } catch {
            lesson.reviewStatus = previousStatus
            saveErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func vocabularyRatingButton(
        _ rating: VocabularyReviewRating,
        for vocabulary: VocabularyReviewCard
    ) -> some View {
        Button {
            rate(vocabulary, as: rating)
        } label: {
            Text(rating.japaneseName)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func vocabularySubtitle(for vocabulary: VocabularyReviewCard) -> String {
        let prefix = vocabulary.studyRecord.isNew ? "新規" : vocabulary.frequency.language.japaneseName
        return "\(prefix)・出現 \(vocabulary.studyRecord.appearanceCount)回"
    }

    private func synchronizeVocabularyStudyRecords() {
        do {
            try VocabularyStudyPersistence.synchronize(
                frequencies: vocabularyFrequencies,
                existingRecords: vocabularyStudyRecords,
                in: modelContext,
                now: Date()
            )
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func rate(_ vocabulary: VocabularyReviewCard, as rating: VocabularyReviewRating) {
        do {
            try VocabularyStudyPersistence.recordReview(
                vocabulary.studyRecord,
                rating: rating,
                in: modelContext,
                now: Date()
            )
            vocabularyIndex = 0
            isVocabularyAnswerVisible = false
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }
}
