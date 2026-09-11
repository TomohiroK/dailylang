import Foundation

enum OpenAILessonErrorCode: Int, Sendable {
    case invalidAPIKey = 1001
    case invalidResponse = 1002
    case requestTimedOut = 1003
    case networkError = 1004
    case apiError = 1005
    case lessonJSONNotFound = 1028
    case invalidLessonPayload = 1029
    case untranslatedImageKeywords = 1031
    case unexpected = 1099
}

enum OpenAILessonServiceError: LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case requestTimedOut
    case networkError(String)
    case apiError(String)
    case lessonJSONNotFound
    case invalidLessonPayload(String)
    case untranslatedImageKeywords([String])
    case unexpected(String)

    var code: OpenAILessonErrorCode {
        switch self {
        case .invalidAPIKey:
            .invalidAPIKey
        case .invalidResponse:
            .invalidResponse
        case .requestTimedOut:
            .requestTimedOut
        case .networkError:
            .networkError
        case .apiError:
            .apiError
        case .lessonJSONNotFound:
            .lessonJSONNotFound
        case .invalidLessonPayload:
            .invalidLessonPayload
        case .untranslatedImageKeywords:
            .untranslatedImageKeywords
        case .unexpected:
            .unexpected
        }
    }

    var diagnosticReason: String? {
        switch self {
        case .networkError(let message), .apiError(let message), .invalidLessonPayload(let message),
             .unexpected(let message):
            message
        case .untranslatedImageKeywords(let labels):
            "main_sentence_id contains untranslated image keywords: \(labels.joined(separator: ", "))"
        case .invalidAPIKey, .invalidResponse, .requestTimedOut, .lessonJSONNotFound:
            nil
        }
    }

    var isRepairableByRegeneration: Bool {
        switch self {
        case .lessonJSONNotFound, .invalidLessonPayload, .untranslatedImageKeywords:
            true
        case .invalidAPIKey, .invalidResponse, .requestTimedOut, .networkError, .apiError, .unexpected:
            false
        }
    }

    var errorDescription: String? {
        let message = switch self {
        case .invalidAPIKey:
            "OpenAI APIキーが設定されていません。"
        case .invalidResponse:
            "OpenAI APIの応答を読み取れませんでした。"
        case .requestTimedOut:
            "OpenAI APIの応答が時間内に返りませんでした。通信状態を確認してもう一度試してください。"
        case .networkError(let message):
            "OpenAI APIへの接続に失敗しました: \(message)"
        case .apiError(let message):
            message
        case .lessonJSONNotFound:
            "レッスンJSONが応答に含まれていませんでした。"
        case .invalidLessonPayload:
            "OpenAI APIのレッスン形式が不正でした。"
        case .untranslatedImageKeywords:
            "例文に未翻訳の画像キーワードが含まれていました。"
        case .unexpected:
            "OpenAI API連携で想定外のエラーが発生しました。"
        }
        return Self.withCode(message, code: code)
    }

    private static func withCode(_ message: String, code: OpenAILessonErrorCode) -> String {
        let separator = message.hasSuffix("。") ? "" : " "
        return "\(message)\(separator)(Error-\(code.rawValue))"
    }
}

private extension Error {
    var openAILessonDiagnosticReason: String {
        switch self {
        case let error as OpenAILessonServiceError:
            error.diagnosticReason ?? error.localizedDescription
        default:
            localizedDescription
        }
    }
}

@MainActor
enum LessonGenerationFailureDiagnostics {
    private static let latestFailureKey = "latestLessonGenerationFailure"
    private static let diagnosticsDirectoryName = "Diagnostics"
    private static let latestFailureFileName = "latest-lesson-generation-failure.txt"

    static func record(_ error: Error, userDefaults: UserDefaults = .standard) {
        record(
            error,
            userDefaults: userDefaults,
            failureFileURL: defaultFailureFileURL
        )
    }

    static func record(
        _ error: Error,
        userDefaults: UserDefaults,
        failureFileURL: URL?
    ) {
        let failureDetail = detail(for: error)
        userDefaults.set(failureDetail, forKey: latestFailureKey)
        guard let failureFileURL else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: failureFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try failureDetail.write(to: failureFileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("DailyLang failed to persist lesson-generation diagnostics: %@", error.localizedDescription)
        }
    }

    static func clear(userDefaults: UserDefaults = .standard) {
        clear(userDefaults: userDefaults, failureFileURL: defaultFailureFileURL)
    }

    static func clear(userDefaults: UserDefaults, failureFileURL: URL?) {
        userDefaults.removeObject(forKey: latestFailureKey)
        guard let failureFileURL,
              FileManager.default.fileExists(atPath: failureFileURL.path)
        else {
            return
        }

        do {
            try FileManager.default.removeItem(at: failureFileURL)
        } catch {
            NSLog("DailyLang failed to clear lesson-generation diagnostics: %@", error.localizedDescription)
        }
    }

    static func latest(userDefaults: UserDefaults = .standard) -> String? {
        latest(userDefaults: userDefaults, failureFileURL: defaultFailureFileURL)
    }

    static func latest(userDefaults: UserDefaults, failureFileURL: URL?) -> String? {
        if let storedFailure = userDefaults.string(forKey: latestFailureKey) {
            return storedFailure
        }
        guard let failureFileURL else {
            return nil
        }

        do {
            return try String(contentsOf: failureFileURL, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func detail(for error: Error) -> String {
        guard let openAIError = error as? OpenAILessonServiceError else {
            return error.localizedDescription
        }
        guard let reason = openAIError.diagnosticReason, !reason.isEmpty else {
            return openAIError.localizedDescription
        }
        return "\(openAIError.localizedDescription) reason: \(reason)"
    }

    private static var defaultFailureFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(diagnosticsDirectoryName, isDirectory: true)
            .appendingPathComponent(latestFailureFileName, isDirectory: false)
    }
}

struct OpenAILessonService: Sendable {
    private static let endpointString = "https://api.openai.com/v1/responses"
    private static let maxOutputTokens = 2_200
    private static let maxRepairAttempts = 4
    private static let requestTimeoutSeconds: TimeInterval = 45
    private static func repairInstruction(
        for level: LanguageLevel,
        language: LessonLanguage,
        reason: String,
        preserving previousPayload: GeneratedLessonPayload? = nil
    ) -> String {
        let targetLanguage = language.englishName
        let instruction = """
        The previous response failed validation for this exact reason: \(reason)
        Correct the lesson JSON using the same Scene data JSON.
        The main sentence must use natural \(targetLanguage), include a concrete object or action from image_keywords when available, and reflect the selected situation without contradicting the image evidence.
        main_sentence_word_count must equal the actual word count, main_sentence_jp must translate only what main_sentence_id says without adding omitted situation details, and vocabulary ids must be exact \(targetLanguage) words or contiguous phrases copied from main_sentence_id.
        Return \(level.vocabularyCountGuidance) after filtering to vocabulary ids that are actually copied from main_sentence_id.
        Every jp field must be Japanese, must not contain Thai, Lao, Khmer, or Myanmar script, and must not merely repeat its \(targetLanguage) id.
        """
        guard let previousPayload else {
            return instruction
        }
        return repairInstruction(
            instruction,
            preserving: previousPayload,
            language: language
        )
    }
    private static func groundingRepairInstruction(for language: LessonLanguage, reason: String) -> String {
        """
        The previous lesson omitted too much foreground evidence: \(reason)
        If the reason says vocabulary coverage, preserve the main sentence and translation and replace low-priority vocabulary with missing foreground nouns or phrases from that sentence, keeping valid Japanese meanings and level limits.
        Preserve already included foreground objects and add missing objects up to the level-specific coverage requirement. Do not satisfy used_keywords by listing objects absent from the sentence. Do not remove valid content merely to fit the preferred word count.
        Regenerate the lesson JSON in natural \(language.englishName) using the same Scene data JSON and selected situation.
        The main sentence must be about the foreground objects from image_keywords, such as food, flowers, cups, bottles, tools, or other items on the surface. Do not make the table, desk, room, or furniture the main topic.
        Fill used_keywords with the original foreground image keyword labels that are actually grounded in main_sentence_id.
        """
    }
    private static func untranslatedKeywordsRepairInstruction(for labels: [String]) -> String {
        let replacements = labels.map { label in
            let aliases = groundingAliases[label, default: []].sorted().joined(separator: " or ")
            return aliases.isEmpty ? label : "\(label) -> \(aliases)"
        }.joined(separator: "; ")
        return """
        The previous main_sentence_id copied English image keyword labels instead of writing natural Indonesian.
        Replace these exact labels with natural Indonesian: \(replacements).
        Keep used_keywords as the original image keyword labels, but update main_sentence_id, main_sentence_jp, vocabulary, grammar, conversation, similar expressions, and main_sentence_word_count wherever the corrected Indonesian sentence requires it.
        """
    }

    private static func japaneseFieldsRepairInstruction(
        reason: String,
        language: LessonLanguage
    ) -> String {
        """
        The previous response failed Japanese-field validation for this reason: \(reason)
        Audit and rewrite every learner-facing Japanese field, not only the first field reported by validation: main_sentence_jp, every vocabulary.jp, grammar_note, every conversation.jp, and every similar_expressions.jp.
        Keep valid \(language.englishName) id fields and used_keywords unchanged. Every jp field must contain natural Japanese, must not repeat its \(language.englishName) id, and must not contain Thai, Lao, Khmer, or Myanmar script.
        Do not return until all Japanese fields in the payload pass these requirements together.
        """
    }

    private static func requiresJapaneseFieldsRepair(_ error: Error) -> Bool {
        guard let payloadError = error as? GeneratedLessonPayloadError else {
            return false
        }
        switch payloadError {
        case .invalidMainSentenceTranslation, .invalidGrammarNote,
             .invalidConversationTranslation, .invalidSimilarExpressionTranslation:
            return true
        case .insufficientVocabulary(_, _, let rejectedItems):
            return rejectedItems.contains { $0.contains("invalid Japanese meaning") }
        case .invalidMainSentence, .overlyGenericMainSentence, .insufficientConversation,
             .invalidConversationLine, .insufficientSimilarExpressions,
             .invalidSimilarExpression:
            return false
        }
    }

    private static func repairInstruction(
        _ instruction: String,
        preserving previousPayload: GeneratedLessonPayload,
        language: LessonLanguage
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(previousPayload) else {
            return instruction
        }
        let previousJSON = String(decoding: data, as: UTF8.self)
        return """
        \(instruction)

        Previous invalid lesson JSON:
        \(previousJSON)

        Preserve every field that already satisfies the requirements. Correct the exact failed field and any directly dependent fields instead of creating an unrelated lesson from scratch.
        Before returning, audit the entire payload together: use natural \(language.englishName) in main_sentence_id, make main_sentence_word_count equal the actual word count, keep every vocabulary id inside main_sentence_id, and make every learner-facing jp field natural Japanese.
        """
    }

    private let session: URLSession
    private let promptBuilder: OpenAILessonPromptBuilder

    init(
        session: URLSession = .shared,
        promptBuilder: OpenAILessonPromptBuilder = OpenAILessonPromptBuilder()
    ) {
        self.session = session
        self.promptBuilder = promptBuilder
    }

    func generateLesson(
        from context: SceneContext,
        apiKey: String,
        model: String
    ) async throws -> Lesson {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAILessonServiceError.invalidAPIKey
        }
        guard let endpoint = URL(string: Self.endpointString) else {
            throw OpenAILessonServiceError.invalidResponse
        }

        let prompt: OpenAILessonPrompt
        do {
            prompt = try promptBuilder.buildPrompt(from: context)
        } catch {
            throw OpenAILessonServiceError.unexpected("prompt build failed: \(error.localizedDescription)")
        }
        var repairMessage: String?
        var lastInvalidPayloadReason = "lesson payload validation failed after repair attempts"

        for attempt in 0...Self.maxRepairAttempts {
            let lessonPayload: GeneratedLessonPayload
            do {
                lessonPayload = try await requestLessonPayload(
                    endpoint: endpoint,
                    apiKey: trimmedKey,
                    model: model,
                    prompt: prompt,
                    level: context.languageLevel,
                    language: context.lessonLanguage,
                    repairMessage: repairMessage
                )
            } catch let error as OpenAILessonServiceError where error.isRepairableByRegeneration {
                lastInvalidPayloadReason = error.diagnosticReason ?? error.localizedDescription
                guard attempt < Self.maxRepairAttempts else {
                    throw error
                }
                repairMessage = Self.repairInstruction(
                    for: context.languageLevel,
                    language: context.lessonLanguage,
                    reason: lastInvalidPayloadReason
                )
                continue
            }

            do {
                let untranslatedLabels = Self.untranslatedKeywordLabels(
                    in: lessonPayload,
                    context: context
                )
                if !untranslatedLabels.isEmpty {
                    guard attempt < Self.maxRepairAttempts else {
                        throw OpenAILessonServiceError.untranslatedImageKeywords(untranslatedLabels)
                    }
                    repairMessage = Self.repairInstruction(
                        Self.untranslatedKeywordsRepairInstruction(for: untranslatedLabels),
                        preserving: lessonPayload,
                        language: context.lessonLanguage
                    )
                    continue
                }
                let lesson = try lessonPayload.lesson(
                    source: .openAI,
                    languageLevel: context.languageLevel,
                    lessonLanguage: context.lessonLanguage
                )
                if let coverageIssue = Self.foregroundCoverageIssue(lessonPayload, context: context)
                    ?? Self.foregroundCoverageIssue(lessonPayload, context: context, vocabulary: lesson.vocabulary) {
                    guard attempt < Self.maxRepairAttempts else {
                        throw OpenAILessonServiceError.invalidLessonPayload(coverageIssue)
                    }
                    repairMessage = Self.repairInstruction(
                        Self.groundingRepairInstruction(for: context.lessonLanguage, reason: coverageIssue),
                        preserving: lessonPayload,
                        language: context.lessonLanguage
                    )
                    continue
                }
                return lesson
            } catch let error as OpenAILessonServiceError {
                throw error
            } catch {
                lastInvalidPayloadReason = error.openAILessonDiagnosticReason
                guard attempt < Self.maxRepairAttempts else {
                    throw OpenAILessonServiceError.invalidLessonPayload(lastInvalidPayloadReason)
                }
                if Self.requiresJapaneseFieldsRepair(error) {
                    repairMessage = Self.repairInstruction(
                        Self.japaneseFieldsRepairInstruction(
                            reason: lastInvalidPayloadReason,
                            language: context.lessonLanguage
                        ),
                        preserving: lessonPayload,
                        language: context.lessonLanguage
                    )
                } else {
                    repairMessage = Self.repairInstruction(
                        for: context.languageLevel,
                        language: context.lessonLanguage,
                        reason: lastInvalidPayloadReason,
                        preserving: lessonPayload
                    )
                }
            }
        }

        throw OpenAILessonServiceError.invalidLessonPayload(lastInvalidPayloadReason)
    }

    private static func untranslatedKeywordLabels(
        in payload: GeneratedLessonPayload,
        context: SceneContext
    ) -> [String] {
        guard context.lessonLanguage == .indonesian else {
            return []
        }
        let sentenceTokens = keywordTokens(payload.mainSentenceID)
        var seen = Set<String>()
        return context.imageKeywords.compactMap { keyword in
            let label = normalizedKeyword(keyword.label)
            guard let aliases = groundingAliases[label],
                  !aliases.contains(label),
                  containsKeywordTokens(keywordTokens(label), in: sentenceTokens),
                  seen.insert(label).inserted
            else {
                return nil
            }
            return label
        }
    }

    private static func keywordTokens(_ text: String) -> [String] {
        let normalized = normalizedKeyword(text)
        var tokens: [String] = []
        var current = ""
        for scalar in normalized.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func containsKeywordTokens(_ keywordTokens: [String], in sentenceTokens: [String]) -> Bool {
        guard !keywordTokens.isEmpty, keywordTokens.count <= sentenceTokens.count else {
            return false
        }
        for startIndex in 0...(sentenceTokens.count - keywordTokens.count) {
            let endIndex = startIndex + keywordTokens.count
            if Array(sentenceTokens[startIndex..<endIndex]) == keywordTokens {
                return true
            }
        }
        return false
    }

    static func foregroundCoverageIssue(
        _ payload: GeneratedLessonPayload,
        context: SceneContext,
        vocabulary: [VocabularyItem]? = nil
    ) -> String? {
        var seenTerms = Set<Set<String>>()
        let candidates: [(label: String, terms: Set<String>)] = context.imageKeywords.compactMap { keyword in
            let label = normalizedKeyword(keyword.label)
            guard keyword.role == .foreground, !label.isEmpty else { return nil }
            // Unknown manual spellings are hints, not mandatory objects. Known manual terms still count.
            if keyword.source == .manual,
               groundingAliases[label] == nil, englishGroundingAliases[label] == nil {
                return nil
            }
            let terms = groundingTerms(for: label, language: context.lessonLanguage)
            let translatedTerms = groundingAliases[label] ?? terms
            // A local dictionary cannot prove that an unknown translation is absent.
            guard !terms.isEmpty, seenTerms.insert(translatedTerms).inserted else { return nil }
            return (label, terms)
        }
        let required = min(context.languageLevel.foregroundKeywordCountRange.lowerBound, candidates.count)
        guard required > 0 else { return nil }
        let evidenceTexts = vocabulary?.map(\.id) ?? [payload.mainSentenceID]
        let covered = candidates.filter { candidate in
            evidenceTexts.contains { text in
                let sentenceTokens = keywordTokens(text)
                return candidate.terms.contains { term in
                    let tokens = keywordTokens(term)
                    if containsKeywordTokens(tokens, in: sentenceTokens) { return true }
                    guard context.lessonLanguage == .english, let last = tokens.last else { return false }
                    let plurals = [last + "s", last + "es"]
                        + (last.hasSuffix("y") ? [String(last.dropLast()) + "ies"] : [])
                    return plurals.contains { plural in
                        containsKeywordTokens(Array(tokens.dropLast()) + [plural], in: sentenceTokens)
                    }
                }
            }
        }
        guard covered.count < required else { return nil }
        let coveredLabels = Set(covered.map(\.label))
        let missing = candidates.filter { !coveredLabels.contains($0.label) }.map(\.label)
        let section = vocabulary == nil ? "foreground" : "foreground vocabulary"
        return "\(section) coverage \(covered.count)/\(required) for \(context.languageLevel.rawValue); missing candidates: \(missing.joined(separator: ", "))"
    }

    private static func normalizedKeyword(_ keyword: String) -> String {
        keyword
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func groundingTerms(
        for label: String,
        language: LessonLanguage
    ) -> Set<String> {
        let normalized = normalizedKeyword(label)
        guard !normalized.isEmpty else {
            return []
        }

        if language == .english {
            var terms = englishGroundingAliases[normalized, default: []]
            if normalized.unicodeScalars.allSatisfy({ $0.isASCII }) {
                terms.insert(normalized)
            }
            // Reuse known translations to support Japanese keyword chips without forcing untranslated labels.
            if let aliases = groundingAliases[normalized] {
                for (label, translations) in groundingAliases
                    where translations == aliases && label.unicodeScalars.allSatisfy({ $0.isASCII }) {
                    terms.insert(label)
                    terms.formUnion(englishGroundingAliases[label, default: []])
                }
            }
            return terms
        }

        guard let aliases = groundingAliases[normalized] else {
            return []
        }

        var terms = aliases
        terms.insert(normalized)
        return terms
    }

    private static let englishGroundingAliases: [String: Set<String>] = [
        "consumer electronics": ["device", "electronics"],
        "motor scooter": ["scooter", "motorbike"],
        "water jug": ["jug", "water bottle"],
        "window shade": ["blind", "curtain"],
        "blue sky": ["sky"],
        "cityscape": ["city", "buildings"],
        "cord": ["cable"],
        "textile": ["fabric", "cloth"],
        "portal": ["door", "gate", "entrance"],
        "container": ["jar", "bottle", "container"],
    ]

    private static let groundingAliases: [String: Set<String>] = [
        "banana": ["pisang"],
        "bananas": ["pisang"],
        "バナナ": ["pisang"],
        "milk": ["susu"],
        "牛乳": ["susu"],
        "ミルク": ["susu"],
        "water jug": ["teko air", "kendi", "wadah", "botol"],
        "jug": ["teko air", "kendi"],
        "水差し": ["teko air", "kendi"],
        "cup": ["cangkir", "gelas"],
        "コップ": ["cangkir", "gelas"],
        "カップ": ["cangkir", "gelas"],
        "basket": ["keranjang"],
        "かご": ["keranjang"],
        "籠": ["keranjang"],
        "bottle": ["botol"],
        "ボトル": ["botol"],
        "瓶": ["botol"],
        "cord": ["kabel", "tali"],
        "cable": ["kabel"],
        "コード": ["kabel"],
        "jar": ["toples", "stoples", "wadah"],
        "container": ["wadah", "toples", "botol"],
        "vase": ["vas"],
        "花瓶": ["vas"],
        "flower": ["bunga"],
        "花": ["bunga"],
        "cat": ["kucing"],
        "猫": ["kucing"],
        "laptop": ["laptop"],
        "ノートパソコン": ["laptop"],
        "keyboard": ["keyboard"],
        "キーボード": ["keyboard"],
        "document": ["dokumen"],
        "documents": ["dokumen"],
        "書類": ["dokumen"],
        "book": ["buku"],
        "books": ["buku"],
        "notebook": ["buku catatan", "laptop"],
        "soap dispenser": ["dispenser sabun"],
        "textile": ["kain", "tekstil"],
        "consumer electronics": ["elektronik", "perangkat elektronik"],
        "screenshot": ["screenshot", "tangkapan layar"],
        "screenshots": ["screenshot", "tangkapan layar"],
        "digital clock": ["jam digital", "jam"],
        "clock": ["jam"],
        "時計": ["jam"],
        "chair": ["kursi"],
        "椅子": ["kursi"],
        "window": ["jendela"],
        "窓": ["jendela"],
        "curtain": ["tirai", "gorden"],
        "カーテン": ["tirai", "gorden"],
        "furniture": ["perabot", "meja", "kursi"],
        "table": ["meja"],
        "desk": ["meja"],
        "portal": ["gerbang", "pintu"],
        "gate": ["gerbang"],
        "car": ["mobil"],
        "車": ["mobil"],
        "motor scooter": ["skuter", "sepeda motor"],
        "scooter": ["skuter", "sepeda motor"],
        "motorbike": ["sepeda motor", "motor"],
        "motorcycle": ["sepeda motor", "motor"],
        "バイク": ["sepeda motor", "motor"],
        "スクーター": ["skuter", "sepeda motor"],
        "person": ["orang"],
        "人": ["orang"],
    ]

    private func requestLessonPayload(
        endpoint: URL,
        apiKey: String,
        model: String,
        prompt: OpenAILessonPrompt,
        level: LanguageLevel,
        language: LessonLanguage,
        repairMessage: String?
    ) async throws -> GeneratedLessonPayload {
        var input = [
            ResponsesMessage(role: "developer", content: prompt.instructions),
            ResponsesMessage(role: "user", content: "Scene data JSON:\n\(prompt.sceneJSON)"),
        ]
        if let repairMessage {
            input.append(ResponsesMessage(role: "user", content: repairMessage))
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = Self.requestTimeoutSeconds
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(
                ResponsesRequest(
                    model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                    input: input,
                    maxOutputTokens: Self.maxOutputTokens,
                    text: .lessonJSON(for: level, language: language)
                )
            )
        } catch {
            throw OpenAILessonServiceError.unexpected("request JSON encode failed: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OpenAILessonServiceError.requestTimedOut
        } catch {
            throw OpenAILessonServiceError.networkError(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAILessonServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            throw OpenAILessonServiceError.apiError(
                errorBody?.error.message ?? "OpenAI API error: \(httpResponse.statusCode)"
            )
        }

        let responseBody: ResponsesResponse
        do {
            responseBody = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        } catch {
            throw OpenAILessonServiceError.invalidResponse
        }
        guard let text = responseBody.outputText else {
            throw OpenAILessonServiceError.lessonJSONNotFound
        }

        do {
            return try JSONDecoder().decode(
                GeneratedLessonPayload.self,
                from: Data(Self.stripCodeFence(from: text).utf8)
            )
        } catch {
            throw OpenAILessonServiceError.invalidLessonPayload(
                "lesson JSON decode failed: \(error.localizedDescription)"
            )
        }
    }

    private static func stripCodeFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return trimmed
        }

        return trimmed
            .split(separator: "\n")
            .dropFirst()
            .dropLast()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ResponsesRequest: Encodable {
    var model: String
    var input: [ResponsesMessage]
    var maxOutputTokens: Int
    var text: ResponsesTextConfig

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case maxOutputTokens = "max_output_tokens"
        case text
    }
}

private struct ResponsesMessage: Encodable {
    var role: String
    var content: String
}

private struct ResponsesTextConfig: Encodable {
    var format: ResponsesTextFormat

    static func lessonJSON(
        for level: LanguageLevel,
        language: LessonLanguage
    ) -> ResponsesTextConfig {
        let targetLanguage = language.englishName
        return ResponsesTextConfig(
            format: ResponsesTextFormat(
                type: "json_schema",
                name: "\(language.rawValue)_lesson",
                strict: true,
                schema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([
                    .string("main_sentence_id"),
                    .string("main_sentence_jp"),
                    .string("main_sentence_word_count"),
                    .string("vocabulary"),
                    .string("grammar_note"),
                    .string("conversation"),
                    .string("similar_expressions"),
                    .string("used_keywords"),
                ]),
                "properties": .object([
                    "main_sentence_id": .object([
                        "type": .string("string"),
                        "description": .string("One complete \(targetLanguage) sentence appropriate for the \(level.rawValue) level. Aim for \(level.mainSentenceWordCountGuidance(for: language)) and count the words before returning JSON. A length outside this target is still acceptable. This is not a numeric identifier."),
                    ]),
                    "main_sentence_jp": .object([
                        "type": .string("string"),
                        "description": .string("Japanese translation of main_sentence_id. Must contain Japanese text and must not copy the \(targetLanguage) sentence."),
                    ]),
                    "main_sentence_word_count": .object([
                        "type": .string("integer"),
                        "description": .string("Actual \(targetLanguage) word-token count of main_sentence_id. Count the sentence before returning JSON."),
                    ]),
                    "vocabulary": .object([
                        "type": .string("array"),
                        "minItems": .int(level.minimumVocabularyCount),
                        "maxItems": .int(level.maximumVocabularyCount),
                        "items": .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "required": .array([.string("id"), .string("jp")]),
                            "properties": .object([
                                "id": .object([
                                    "type": .string("string"),
                                    "description": .string("Exact \(targetLanguage) word or contiguous phrase copied from main_sentence_id. This is not a numeric identifier."),
                                ]),
                                "jp": .object([
                                    "type": .string("string"),
                                    "description": .string("Japanese meaning. Must not repeat the \(targetLanguage) id."),
                                ]),
                            ]),
                        ]),
                    ]),
                    "grammar_note": .object([
                        "type": .string("string"),
                        "description": .string("Brief grammar explanation in Japanese. Must not contain Thai, Lao, Khmer, or Myanmar script."),
                    ]),
                    "conversation": .object([
                        "type": .string("array"),
                        "minItems": .int(2),
                        "maxItems": .int(4),
                        "items": .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "required": .array([.string("speaker"), .string("id"), .string("jp")]),
                            "properties": .object([
                                "speaker": .object(["type": .string("string")]),
                                "id": .object([
                                    "type": .string("string"),
                                    "description": .string("\(targetLanguage) conversation line. This is not a numeric identifier."),
                                ]),
                                "jp": .object([
                                    "type": .string("string"),
                                    "description": .string("Japanese translation. Must not contain Thai, Lao, Khmer, or Myanmar script."),
                                ]),
                            ]),
                        ]),
                    ]),
                    "similar_expressions": .object([
                        "type": .string("array"),
                        "minItems": .int(3),
                        "maxItems": .int(3),
                        "items": .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "required": .array([.string("id"), .string("jp")]),
                            "properties": .object([
                                "id": .object([
                                    "type": .string("string"),
                                    "description": .string("Alternative \(targetLanguage) expression. This is not a numeric identifier."),
                                ]),
                                "jp": .object([
                                    "type": .string("string"),
                                    "description": .string("Japanese translation. Must not contain Thai, Lao, Khmer, or Myanmar script."),
                                ]),
                            ]),
                        ]),
                    ]),
                    "used_keywords": .object([
                        "type": .string("array"),
                        "description": .string("Original image keyword labels that are actually used as evidence in main_sentence_id."),
                        "items": .object(["type": .string("string")]),
                    ]),
                ]),
                ])
            )
        )
    }
}

private struct ResponsesTextFormat: Encodable {
    var type: String
    var name: String
    var strict: Bool
    var schema: JSONSchemaValue
}

private enum JSONSchemaValue: Encodable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case object([String: JSONSchemaValue])
    case array([JSONSchemaValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        }
    }
}

private struct ResponsesResponse: Decodable {
    var outputText: String?
    var output: [ResponsesOutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        output = try container.decodeIfPresent([ResponsesOutputItem].self, forKey: .output)

        if outputText == nil {
            outputText = output?
                .flatMap { $0.content ?? [] }
                .first(where: { $0.text != nil })?
                .text
        }
    }
}

private struct ResponsesOutputItem: Decodable {
    var content: [ResponsesContentItem]?
}

private struct ResponsesContentItem: Decodable {
    var type: String?
    var text: String?
}

private struct OpenAIErrorResponse: Decodable {
    var error: OpenAIError
}

private struct OpenAIError: Decodable {
    var message: String
}
