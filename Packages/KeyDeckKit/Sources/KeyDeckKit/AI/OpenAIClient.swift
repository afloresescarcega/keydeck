import Foundation

public struct OpenAIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1")! // NOSONAR: default value of an injectable parameter
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

    public func transcribeAudio(
        audioData: Data,
        filename: String,
        mimeType: String,
        model: String,
        promptHint: String? = nil,
        apiKey: String
    ) async throws -> String {
        let boundary = "KeyDeckBoundary-\(UUID().uuidString)"
        let url = baseURL.appendingPathComponent("audio/transcriptions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: model)
        if let promptHint, !promptHint.isEmpty {
            appendField(name: "prompt", value: promptHint)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("Non-HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let msg = extractErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError(statusCode: http.statusCode, message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw AIError.invalidResponse("Missing text field in transcription response")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIError.emptyOutput
        }
        return trimmed
    }

    public func generateText(
        systemPrompt: String,
        userPrompt: String,
        model: String,
        apiKey: String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.25,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("Non-HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let msg = extractErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError(statusCode: http.statusCode, message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse("Missing choices/message content")
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIError.emptyOutput
        }
        return trimmed
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
