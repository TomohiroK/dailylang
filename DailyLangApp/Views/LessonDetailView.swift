import SwiftData
import SwiftUI
import UIKit

struct LessonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var record: LessonRecord
    @StateObject private var speechPlayer = SupertonicSpeechPlayer()
    @State private var saveErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                dataIntegrityWarning
                mainSentence
                vocabulary
                grammar
                conversation
                similarExpressions
            }
            .padding()
        }
        .navigationTitle("レッスン")
        .toolbar {
            Button {
                toggleFavorite()
            } label: {
                Image(systemName: record.favorite ? "star.fill" : "star")
            }
            .accessibilityLabel(record.favorite ? "お気に入りを解除" : "お気に入り")
        }
        .alert("保存できませんでした", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "もう一度試してください。")
        }
        .alert("読み上げできませんでした", isPresented: speechErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(speechPlayer.errorMessage ?? "もう一度試してください。")
        }
        .onDisappear {
            speechPlayer.stop()
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let path = record.photoLocalPath, let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var dataIntegrityWarning: some View {
        let unreadableSections = record.unreadableLessonSections
        if !unreadableSections.isEmpty {
            Label(
                "保存データの一部を読み取れません: \(unreadableSections.joined(separator: ", "))",
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var mainSentence: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("DUO式例文", systemImage: "quote.bubble")
                    .font(.headline)
                Spacer()
                Button {
                    speechPlayer.toggle(
                        sentence: record.mainSentenceID,
                        language: record.lessonLanguage
                    )
                } label: {
                    Image(systemName: speechPlayer.iconName)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(speechPlayer.buttonAccessibilityLabel)
            }
            Text(record.mainSentenceID)
                .font(.title3.weight(.semibold))
            Text(record.mainSentenceJP)
                .foregroundStyle(.secondary)
        }
    }

    private var vocabulary: some View {
        LessonSection(title: "単語", systemImage: "list.bullet.rectangle") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(record.vocabulary) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.id)
                            .font(.headline)
                        Text(item.jp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var grammar: some View {
        LessonSection(title: "文法", systemImage: "textformat.abc") {
            Text(record.grammarNote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var conversation: some View {
        LessonSection(title: "会話例", systemImage: "person.2") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(record.conversation.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 10) {
                        Text(line.speaker)
                            .font(.caption.weight(.bold))
                            .frame(width: 26, height: 26)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.id)
                                .font(.headline)
                            Text(line.jp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var similarExpressions: some View {
        LessonSection(title: "類似表現", systemImage: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(record.similarExpressions) { expression in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(expression.id)
                            .font(.headline)
                        Text(expression.jp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    @MainActor
    private func toggleFavorite() {
        record.favorite.toggle()
        do {
            try modelContext.save()
        } catch {
            record.favorite.toggle()
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

private struct LessonSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
    }
}
