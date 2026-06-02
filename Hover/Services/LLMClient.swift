//
//  LLMClient.swift
//  Hover
//
//  Created by Hover Contributors on 2026-05-26.
//  Implements an OpenAI-compatible streaming chat completions client using URLSession.
//

import Darwin
import Foundation

struct LLMConfiguration: Equatable {
    let baseURL: URL
    let apiKey: String
    let modelName: String
    let systemPrompt: String
}

struct LLMRequestContext: Equatable {
    let userPrompt: String?
    let selectedText: String?
    let screenContext: ScreenContext?
}

final class LLMClient {
    private let session: URLSession
    private let redirectDelegate: NoRedirectSessionDelegate
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil

        let redirectDelegate = NoRedirectSessionDelegate()
        self.redirectDelegate = redirectDelegate
        self.session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }

    func streamCompletion(
        for requestContext: LLMRequestContext,
        configuration: LLMConfiguration
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(context: requestContext, configuration: configuration)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMClientError.invalidResponse
                    }

                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw LLMClientError.httpStatus(httpResponse.statusCode)
                    }

                    for try await rawLine in bytes.lines {
                        try Task.checkCancellation()

                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard line.hasPrefix("data:") else {
                            continue
                        }

                        let payload = line
                            .dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        if payload == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        guard let data = payload.data(using: .utf8) else {
                            continue
                        }

                        let chunk = try jsonDecoder.decode(ChatCompletionChunk.self, from: data)
                        for choice in chunk.choices {
                            if let content = choice.delta.content, !content.isEmpty {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func testConnection(configuration: LLMConfiguration) async throws -> String {
        // Use the same streaming path as real requests. This catches endpoints that accept
        // non-streaming completions but fail Hover's live response UI.
        let requestContext = LLMRequestContext(
            userPrompt: "Reply with OK only. This is a Hover connection test.",
            selectedText: nil,
            screenContext: nil
        )
        var response = ""

        for try await token in streamCompletion(for: requestContext, configuration: configuration) {
            response += token

            if response.count >= 24 {
                break
            }
        }

        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResponse.isEmpty else {
            throw LLMClientError.streamingUnavailable
        }

        return trimmedResponse
    }

    private func makeRequest(context: LLMRequestContext, configuration: LLMConfiguration) throws -> URLRequest {
        let endpoint = endpointURL(from: configuration.baseURL)
        try validateTransport(for: endpoint)

        // Ephemeral sessions plus no-store headers reduce the chance of prompt, response,
        // or Authorization data being cached by the client stack.
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-store", forHTTPHeaderField: "Pragma")

        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let userContent = makeUserContent(context: context, configuration: configuration)
        let body = ChatCompletionRequest(
            model: configuration.modelName,
            messages: [
                ChatMessage(role: "system", content: .text(configuration.systemPrompt)),
                ChatMessage(role: "user", content: userContent)
            ],
            stream: true,
            temperature: 0.4,
            maxTokens: nil
        )

        request.httpBody = try jsonEncoder.encode(body)
        return request
    }

    private func makeUserContent(
        context: LLMRequestContext,
        configuration: LLMConfiguration
    ) -> ChatMessageContent {
        let text = makeUserText(context: context)

        guard Self.supportsImageInput(modelName: configuration.modelName),
              let screenshotDataURL = context.screenContext?.screenshotDataURL else {
            return .text(text)
        }

        return .parts([
            ChatContentPart(type: "text", text: text, imageURL: nil),
            ChatContentPart(
                type: "image_url",
                text: nil,
                imageURL: ChatImageURL(url: screenshotDataURL, detail: "low")
            )
        ])
    }

    private func makeUserText(context: LLMRequestContext) -> String {
        var sections: [String] = []

        if let prompt = context.userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            sections.append("User request:\n\(prompt)")
        }

        if let selectedText = context.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedText.isEmpty {
            sections.append("Selected text:\n\(selectedText)")
        }

        if let screenContext = context.screenContext {
            var contextLines: [String] = []

            if let appName = screenContext.activeApplicationName {
                contextLines.append("Active app: \(appName)")
            }

            if let windowTitle = screenContext.focusedWindowTitle {
                contextLines.append("Window: \(windowTitle)")
            }

            if let accessibilityText = screenContext.accessibilityText {
                contextLines.append("Visible or focused text:\n\(accessibilityText)")
            }

            if !contextLines.isEmpty {
                sections.append("Screen context:\n\(contextLines.joined(separator: "\n"))")
            }
        }

        if sections.isEmpty {
            return "The user opened Hover without selecting text. Ask a concise clarifying question."
        }

        return sections.joined(separator: "\n\n")
    }

    static func supportsImageInput(modelName: String) -> Bool {
        let model = modelName.lowercased()
        let visionMarkers = [
            "gpt-4o",
            "gpt-4.1",
            "vision",
            "llava",
            "qwen-vl",
            "qwen2-vl",
            "qwen2.5-vl",
            "pixtral",
            "minicpm-v",
            "gemini"
        ]

        return visionMarkers.contains { model.contains($0) }
    }

    private func validateTransport(for endpoint: URL) throws {
        let scheme = endpoint.scheme?.lowercased()
        guard scheme == "https" || isLoopbackHost(endpoint.host) else {
            throw LLMClientError.insecureRemoteHTTP
        }

        if isLoopbackHost(endpoint.host),
           let port = endpoint.port ?? defaultPort(for: scheme),
           !Self.isLocalPortAcceptingConnections(UInt16(port)) {
            throw LLMClientError.localServerUnavailable(port)
        }
    }

    private func endpointURL(from baseURL: URL) -> URL {
        let trimmedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.hasSuffix("chat/completions") {
            return baseURL
        }

        return baseURL.appendingPathComponent("chat/completions")
    }

    private func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else {
            return false
        }

        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host == "0.0.0.0"
    }

    private func defaultPort(for scheme: String?) -> Int? {
        switch scheme {
        case "http":
            80
        case "https":
            443
        default:
            nil
        }
    }

    private static func isLocalPortAcceptingConnections(_ port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }

        defer {
            close(descriptor)
        }

        let currentFlags = fcntl(descriptor, F_GETFL, 0)
        guard currentFlags >= 0,
              fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) >= 0 else {
            return false
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian

        guard inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1 else {
            return false
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return true
        }

        guard errno == EINPROGRESS else {
            return false
        }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pollDescriptor, 1, 120)
        guard pollResult > 0 else {
            return false
        }

        var socketError: Int32 = 0
        var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
        let status = getsockopt(
            descriptor,
            SOL_SOCKET,
            SO_ERROR,
            &socketError,
            &socketErrorLength
        )

        return status == 0 && socketError == 0
    }
}

private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Provider redirects are blocked so Authorization headers never follow a changed origin.
        completionHandler(nil)
    }
}

enum LLMClientError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case insecureRemoteHTTP
    case localServerUnavailable(Int)
    case streamingUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The API returned a response Hover could not read."
        case .httpStatus(let statusCode):
            switch statusCode {
            case 401:
                "The API rejected the key. Check the provider and API key, then try again."
            case 403:
                "The API blocked this request. Check account access, model access, or provider policy settings."
            case 404:
                "The API endpoint or model was not found. Check the base URL and model name."
            case 429:
                "The API is rate limited or out of credits. Check your provider account."
            case 500...599:
                "The model provider returned HTTP \(statusCode). Try again, or choose another model."
            default:
                "The API returned HTTP \(statusCode)."
            }
        case .insecureRemoteHTTP:
            "Remote HTTP endpoints are blocked. Use HTTPS for cloud or custom providers, or localhost for local models."
        case .localServerUnavailable(let port):
            "No local model server is listening on port \(port). Start LM Studio or Ollama, then try again."
        case .streamingUnavailable:
            "The provider connected, but did not return streaming tokens. Choose an OpenAI-compatible chat completions endpoint with streaming enabled."
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: ChatMessageContent
}

private enum ChatMessageContent: Encodable {
    case text(String)
    case parts([ChatContentPart])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case .parts(let parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }
}

private struct ChatContentPart: Encodable {
    let type: String
    let text: String?
    let imageURL: ChatImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct ChatImageURL: Encodable {
    let url: String
    let detail: String
}

private struct ChatCompletionChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}
