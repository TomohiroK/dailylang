import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LessonRecord.createdAt, order: .reverse) private var lessons: [LessonRecord]
    @State private var currentIndex = 0
    @State private var isAnswerVisible = false
    @State private var saveErrorMessage: String?

    private var savedLessons: [LessonRecord] {
        lessons.filter(\.hasLearnerVisibleText)
    }

    var body: some View {
        NavigationStack {
            Group {
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
            .navigationTitle("Review")
            .alert("保存できませんでした", isPresented: saveErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "もう一度試してください。")
            }
        }
    }

    private var currentLesson: LessonRecord? {
        guard !savedLessons.isEmpty else {
            return nil
        }
        return savedLessons[min(currentIndex, savedLessons.count - 1)]
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
