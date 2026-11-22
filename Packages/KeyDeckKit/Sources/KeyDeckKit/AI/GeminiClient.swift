import Foundation

public struct GeminiClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession? = nil,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.httpCookieStorage = nil
            config.timeoutIntervalForRequest = 60
            self.session = URLSession(configuration: config)
        }
        self.baseURL = baseURL
    }

    private struct SinglePassPayload: Codable {
        let raw_transcript: String
        let output_text: String
    }

    public func processAudioSinglePass(
        audioData: Data,
        mimeType: String,
        model: String,
        systemPrompt: String,
        apiKey: String
    ) async throws -> VoiceAIOutput {
        let endpoint = makeEndpoint(model: model)

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": audioData.base64EncodedString()
                            ]
                        ],
                        [
                            "text": "Listen to the audio and return JSON matching the schema with `raw_transcript` and `output_text`."
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "raw_transcript": ["type": "STRING"],
                        "output_text": ["type": "STRING"]
                    ],
                    "required": ["raw_transcript", "output_text"]
                ]
            ]
        ]

        let rawText = try await executeGenerateContent(endpoint: endpoint, apiKey: apiKey, body: body)
        let parsed = parseSinglePassResponse(rawText)
        let finalOutput = parsed.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalOutput.isEmpty else {
            throw AIError.emptyOutput
        }
        let rawTranscript = parsed.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        return VoiceAIOutput(
            outputText: finalOutput,
            rawTranscript: rawTranscript.isEmpty ? finalOutput : rawTranscript,
            providerUsed: .gemini,
            modelUsed: model
        )
    }

    public func generateText(
        systemPrompt: String,
        userPrompt: String,
        model: String,
        apiKey: String
    ) async throws -> String {
        let endpoint = makeEndpoint(model: model)
        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userPrompt]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3
            ]
        ]

        let text = try await executeGenerateContent(endpoint: endpoint, apiKey: apiKey, body: body)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIError.emptyOutput
        }
        return text
    }

    internal func parseSinglePassResponse(_ rawText: String) -> (outputText: String, rawTranscript: String) {
        let cleanedJSON = Self.stripCodeFences(rawText)
        if let data = cleanedJSON.data(using: .utf8),
           let payload = try? JSONDecoder().decode(SinglePassPayload.self, from: data) {
            return (payload.output_text, payload.raw_transcript)
        }
        return (rawText, rawText)
    }

    private static func stripCodeFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let newline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: newline)...])
            }
            if trimmed.hasSuffix("```") {
                trimmed = String(trimmed.dropLast(3))
            }
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeEndpoint(model: String) -> URL {
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return baseURL.appendingPathComponent("models/\(cleanModel):generateContent")
    }

    private func executeGenerateContent(endpoint: URL, apiKey: String, body: [String: Any]) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("Non-HTTP response")
        }

        if !(200..<300).contains(http.statusCode) {
            let msg = extractErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError(statusCode: http.statusCode, message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIError.invalidResponse("Missing candidates/content parts")
        }

        let joined = parts.compactMap { $0["text"] as? String }.joined()
        guard !joined.isEmpty else {
            throw AIError.emptyOutput
        }
        return joined
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
