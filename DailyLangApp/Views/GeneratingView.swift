import SwiftData
import SwiftUI

struct GeneratingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let photo: CapturedPhoto
    let onComplete: (LessonRecord) -> Void

    @AppStorage(AppStorageKey.languageLevel) private var languageLevelRawValue = LanguageLevel.beginner.rawValue
    @AppStorage(AppStorageKey.savePhotos) private var savePhotos = false
    @AppStorage(AppStorageKey.openAIModel) private var openAIModel = AppDefaults.openAIModel
    @AppStorage(AppStorageKey.defaultLocationLabel) private var defaultLocationRawValue = AppDefaults.defaultLocationLabel

    @State private var userNote = ""
    @State private var phase = "画像解析中"
    @State private var errorMessage: String?
    @State private var isGenerating = false
    @State private var apiKey = ""

    private let keyStore: APIKeyStoring = KeychainAPIKeyStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                TextField("メモ（任意）", text: $userNote, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .disabled(isGenerating)

                VStack(spacing: 12) {
                    ProgressView()
                    Text(phase)
                        .font(.headline)
                }
                .opacity(isGenerating ? 1 : 0)

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
                .disabled(isGenerating)

                Spacer()
            }
            .padding()
            .navigationTitle("生成")
            .toolbar {
                Button("閉じる") {
                    dismiss()
                }
            }
            .task {
                apiKey = (try? keyStore.loadAPIKey()) ?? ""
                await generate()
            }
        }
    }

    @MainActor
    private func generate() async {
        guard !isGenerating else {
            return
        }

        isGenerating = true
        errorMessage = nil
        phase = "画像解析中"

        do {
            let service = LessonCompositionService()
            let result = try await service.composeLesson(
                from: photo.image,
                userNote: userNote,
                settings: settings,
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
            phase = "保存しました"
            onComplete(record)
            dismiss()
        } catch {
            phase = "停止しました"
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    private var settings: LessonGenerationSettings {
        LessonGenerationSettings(
            languageLevel: LanguageLevel(rawValue: languageLevelRawValue) ?? .beginner,
            savePhotos: savePhotos,
            openAIAPIKey: apiKey,
            openAIModel: openAIModel.isEmpty ? AppDefaults.openAIModel : openAIModel,
            defaultLocationLabel: LocationLabel(rawValue: defaultLocationRawValue) ?? .unknown
        )
    }
}
