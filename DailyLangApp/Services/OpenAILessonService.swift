import Foundation

enum OpenAILessonServiceError: LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case requestTimedOut
    case networkError(String)
    case apiError(String)
    case lessonJSONNotFound
    case invalidLessonPayload

    var errorDescription: String? {
        switch self {
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
        }
    }
}

struct OpenAILessonService: Sendable {
    private static let endpointString = "https://api.openai.com/v1/responses"
    private static let maxOutputTokens = 900
    private static let maxRepairAttempts = 1
    private static let requestTimeoutSeconds: TimeInterval = 45
    private static let repairInstruction = """
    The previous response was invalid because the main sentence was too generic, did not support at least 4 vocabulary items copied from it, or main_sentence_jp was not Japanese.
    Regenerate the lesson JSON using the same Scene data JSON.
    The main sentence must include a concrete object or action from image_keywords when available, main_sentence_jp must be a Japanese translation, and vocabulary ids must be exact Indonesian words or contiguous phrases copied from main_sentence_id.
    """

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

        let prompt = try promptBuilder.buildPrompt(from: context)
        var repairMessage: String?

        for attempt in 0...Self.maxRepairAttempts {
            let lessonPayload = try await requestLessonPayload(
                endpoint: endpoint,
                apiKey: trimmedKey,
                model: model,
                prompt: prompt,
                repairMessage: repairMessage
            )

            do {
                return try lessonPayload.lesson(source: .openAI)
            } catch {
                guard attempt < Self.maxRepairAttempts else {
                    throw OpenAILessonServiceError.invalidLessonPayload
                }
                repairMessage = Self.repairInstruction
            }
        }

        throw OpenAILessonServiceError.invalidLessonPayload
    }

    private func requestLessonPayload(
        endpoint: URL,
        apiKey: String,
        model: String,
        prompt: OpenAILessonPrompt,
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
        request.httpBody = try JSONEncoder().encode(
            ResponsesRequest(
                model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                input: input,
                maxOutputTokens: Self.maxOutputTokens,
                text: .lessonJSON
            )
        )

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

        let responseBody = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        guard let text = responseBody.outputText else {
            throw OpenAILessonServiceError.lessonJSONNotFound
        }

        return try JSONDecoder().decode(
            GeneratedLessonPayload.self,
            from: Data(Self.stripCodeFence(from: text).utf8)
        )
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

    static let lessonJSON = ResponsesTextConfig(
        format: ResponsesTextFormat(
            type: "json_schema",
            name: "indonesian_lesson",
            strict: true,
            schema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([
                    .string("main_sentence_id"),
                    .string("main_sentence_jp"),
                    .string("vocabulary"),
                    .string("grammar_note"),
                    .string("conversation"),
                    .string("similar_expressions"),
                ]),
                "properties": .object([
                    "main_sentence_id": .object([
                        "type": .string("string"),
                        "description": .string("One complete Indonesian sentence. This is not a numeric identifier."),
                    ]),
                    "main_sentence_jp": .object([
                        "type": .string("string"),
                        "description": .string("Japanese translation of main_sentence_id. Must contain Japanese text and must not copy the Indonesian sentence."),
                    ]),
                    "vocabulary": .object([
                        "type": .string("array"),
                        "minItems": .int(4),
                        "maxItems": .int(8),
                        "items": .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "required": .array([.string("id"), .string("jp")]),
                            "properties": .object([
                                "id": .object([
                                    "type": .string("string"),
                                    "description": .string("Exact Indonesian word or contiguous phrase copied from main_sentence_id. This is not a numeric identifier."),
                                ]),
                                "jp": .object([
                                    "type": .string("string"),
                                    "description": .string("Japanese meaning."),
                                ]),
                            ]),
                        ]),
                    ]),
                    "grammar_note": .object([
                        "type": .string("string"),
                        "description": .string("Brief grammar explanation in Japanese."),
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
                                    "description": .string("Indonesian conversation line. This is not a numeric identifier."),
                                ]),
                                "jp": .object([
                                    "type": .string("string"),
                                    "description": .string("Japanese translation."),
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
                                    "description": .string("Alternative Indonesian expression. This is not a numeric identifier."),
                                ]),
                                "jp": .object([
                                    "type": .string("string"),
                                    "description": .string("Japanese translation."),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ])
        )
    )
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
