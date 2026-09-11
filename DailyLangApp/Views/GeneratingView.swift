import SwiftData
import SwiftUI

struct GeneratingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let photo: CapturedPhoto
    let onComplete: (LessonRecord) -> Void

    @AppStorage(AppStorageKey.languageLevel) private var languageLevelRawValue = LanguageLevel.beginner.rawValue
    @AppStorage(AppStorageKey.lessonLanguage) private var lessonLanguageRawValue = LessonLanguage.indonesian.rawValue
    @AppStorage(AppStorageKey.savePhotos) private var savePhotos = false
    @AppStorage(AppStorageKey.openAIModel) private var openAIModel = AppDefaults.openAIModel

    @State private var selectedLessonSituation: LessonSituation = .random
    @State private var phase = "画像解析中"
    @State private var errorMessage: String?
    @State private var imageKeywords: [ImageKeyword] = []
    @State private var imageRelations: [String] = []
    @State private var newKeywordLabel = ""
    @State private var isAnalyzing = false
    @State private var isGenerating = false
    @State private var apiKey = ""
    @State private var didAnalyze = false

    private let keyStore: APIKeyStoring = KeychainAPIKeyStore()
    private let keywordColumns = [
        GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack {
                    Text("場所")
                        .font(.headline)
                    Spacer()
                    Picker("場所", selection: $selectedLessonSituation) {
                        ForEach(LessonSituation.selectableCases) { situation in
                            Text(situation.japaneseName).tag(situation)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("場所")
                    .accessibilityIdentifier("generation-location-picker")
                }
                .disabled(isAnalyzing || isGenerating)

                    keywordEditor

                VStack(spacing: 12) {
                    ProgressView()
                    Text(phase)
                        .font(.headline)
                }
                    .opacity(isAnalyzing || isGenerating ? 1 : 0)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        await generate()
                    }
                } label: {
                    Label(isGenerating ? "生成中" : "レッスンを生成", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                    .disabled(!canGenerate)

                Spacer()
            }
            .padding()
            }
            .navigationTitle("生成")
            .toolbar {
                Button("閉じる") {
                    dismiss()
                }
            }
            .task {
                apiKey = (try? keyStore.loadAPIKey()) ?? ""
                await analyzeImageIfNeeded()
            }
        }
    }

    private var keywordEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("キーワード")
                    .font(.headline)
                Spacer()
                if didAnalyze {
                    Button {
                        Task {
                            await analyzeImage(force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isAnalyzing || isGenerating)
                    .accessibilityLabel("画像解析をやり直す")
                }
            }

            if imageKeywords.isEmpty {
                Text(isAnalyzing ? "画像解析中" : "写っている物を1つ入力してください")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: keywordColumns, alignment: .leading, spacing: 8) {
                    ForEach(imageKeywords) { keyword in
                        Button {
                            removeKeyword(keyword)
                        } label: {
                            HStack(spacing: 6) {
                                Text(keyword.label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isAnalyzing || isGenerating)
                        .accessibilityLabel("\(keyword.label)を削除")
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("単語を追加", text: $newKeywordLabel)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isAnalyzing || isGenerating)
                    .onSubmit(addKeyword)

                Button(action: addKeyword) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(isAnalyzing || isGenerating || normalizedNewKeyword.isEmpty)
                .accessibilityLabel("単語を追加")
            }
        }
    }

    private var canGenerate: Bool {
        guard !isAnalyzing, !isGenerating else {
            return false
        }
        return !imageKeywords.isEmpty
    }

    @MainActor
    private func analyzeImageIfNeeded() async {
        guard !didAnalyze else {
            return
        }
        await analyzeImage(force: false)
    }

    @MainActor
    private func analyzeImage(force: Bool) async {
        guard !isAnalyzing, !isGenerating else {
            return
        }
        if didAnalyze, !force {
            return
        }

        isAnalyzing = true
        errorMessage = nil
        phase = "画像解析中"

        let service = LessonCompositionService()
        let evidence = await service.analyzeImage(photo.image)
        imageKeywords = evidence.keywords
        imageRelations = evidence.relations
        didAnalyze = true
        isAnalyzing = false
    }

    @MainActor
    private func generate() async {
        guard canGenerate else {
            return
        }

        isGenerating = true
        errorMessage = nil
        phase = "レッスン作成中"

        do {
            let resolvedSituation = selectedLessonSituation.resolved()
            let recentLessons = try LessonRecordPersistence.fetchLearnerVisibleRecords(in: modelContext)
            let generationSettings = settings(
                lessonSituation: resolvedSituation,
                lessonGrammarFocus: LessonGrammarFocusHistory.nextFocus(
                    for: languageLevel,
                    language: lessonLanguage
                ),
                lessonVocabularyFocus: LessonVocabularyFocusHistory.nextFocus(
                    for: languageLevel,
                    language: lessonLanguage
                ),
                recentlyRepeatedExpressions: LessonDailyLifeExpressionHistory.recentlyRepeatedExpressions(
                    from: recentLessons,
                    situation: resolvedSituation,
                    language: lessonLanguage
                )
            )
            let service = LessonCompositionService()
            let result = try await service.composeLesson(
                from: photo.image,
                evidence: ImageSceneEvidence(
                    keywords: imageKeywords,
                    relations: imageRelations
                ),
                userNote: "",
                settings: generationSettings,
                onPhaseChange: { nextPhase in
                    phase = nextPhase.title
                }
            )

            let record = try LessonRecord(
                context: result.context,
                lesson: result.lesson,
                photoLocalPath: result.photoLocalPath
            )
            try LessonRecordPersistence.insertAndSave(record, in: modelContext)
            LessonGrammarFocusHistory.record(
                result.context.lessonGrammarFocus,
                level: result.context.languageLevel,
                language: result.context.lessonLanguage
            )
            LessonVocabularyFocusHistory.record(
                result.context.lessonVocabularyFocus,
                level: result.context.languageLevel,
                language: result.context.lessonLanguage
            )
            LessonGenerationFailureDiagnostics.clear()
            phase = "保存しました"
            onComplete(record)
            dismiss()
        } catch {
            phase = "停止しました"
            LessonGenerationFailureDiagnostics.record(error)
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    private var normalizedNewKeyword: String {
        newKeywordLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func addKeyword() {
        let label = normalizedNewKeyword
        guard !label.isEmpty else {
            return
        }

        let key = label.lowercased()
        if !imageKeywords.contains(where: { $0.label.lowercased() == key }) {
            imageKeywords.insert(
                ImageKeyword(label: label, confidence: 0.5, count: 1, role: .foreground, source: .manual),
                at: 0
            )
        }
        newKeywordLabel = ""
    }

    private func removeKeyword(_ keyword: ImageKeyword) {
        imageKeywords.removeAll { $0.label == keyword.label }
        imageRelations = imageRelations.filter { relation in
            !relation.localizedCaseInsensitiveContains(keyword.label)
        }
    }

    private var languageLevel: LanguageLevel {
        LanguageLevel(rawValue: languageLevelRawValue) ?? .beginner
    }

    private var lessonLanguage: LessonLanguage {
        LessonLanguage(rawValue: lessonLanguageRawValue) ?? .indonesian
    }

    private func settings(
        lessonSituation: LessonSituation,
        lessonGrammarFocus: LessonGrammarFocus,
        lessonVocabularyFocus: LessonVocabularyFocus,
        recentlyRepeatedExpressions: [String]
    ) -> LessonGenerationSettings {
        LessonGenerationSettings(
            languageLevel: languageLevel,
            lessonLanguage: lessonLanguage,
            lessonSituation: lessonSituation,
            lessonGrammarFocus: lessonGrammarFocus,
            lessonVocabularyFocus: lessonVocabularyFocus,
            recentlyRepeatedExpressions: recentlyRepeatedExpressions,
            savePhotos: savePhotos,
            openAIAPIKey: apiKey,
            openAIModel: openAIModel.isEmpty ? AppDefaults.openAIModel : openAIModel
        )
    }
}
