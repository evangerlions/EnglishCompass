import Foundation
import AssistantCore

/// A redirect must never forward the draft or its credential to another endpoint.
final class CloudSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
protocol InferencePerforming: AnyObject {
    var lastRawRequest: String? { get }
    var lastRawResponse: String? { get }
    /// Real cloud transport streams. Test doubles default to false and use the
    /// non-stream `infer` path that returns an already-parsed ModelResult.
    var usesStreaming: Bool { get }
    func infer(text: String, action: AssistantAction, additionalInstructions: String) async throws -> ModelResult
    func inferStream(text: String, action: AssistantAction, additionalInstructions: String,
                     onDelta: @escaping @MainActor (String) -> Void) async throws -> String
    func cancel()
    func prepareCredential()
    func useModel(_ model: QwenModel)
    func answerQuestion(context: String, messages: [QuestionMessage],
                        onDelta: @escaping @MainActor (String) -> Void) async throws -> String
}

extension InferencePerforming {
    var lastRawRequest: String? { nil }
    var lastRawResponse: String? { nil }
    var usesStreaming: Bool { false }
    func inferStream(text: String, action: AssistantAction, additionalInstructions: String,
                     onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        throw AssistantFailure.cloudUnavailable
    }
    func prepareCredential() {}
    func useModel(_ model: QwenModel) {}
    func answerQuestion(context: String, messages: [QuestionMessage],
                        onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        throw AssistantFailure.cloudUnavailable
    }
}

@MainActor
final class InferenceService: InferencePerforming {
    let usesStreaming = true
    private let session: URLSession
    private let credential: () throws -> String
    private var selectedModel: QwenModel = .flash37
    // Process-local only: never persist or log this copy of the Keychain secret.
    private var cachedCredential: String?
    private var active: Task<ModelResult, Error>?
    private var activeStream: Task<String, Error>?
    private var operationID: UUID?
    private(set) var lastRawRequest: String?
    private(set) var lastRawResponse: String?

    init(session: URLSession? = nil, credential: @escaping () throws -> String = CloudCredentialStore.read) {
        self.credential = credential
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        // Whole-response cap. At ~64 tok/s an 8192-token answer needs ~130s,
        // so 120s would cut the longest outputs off mid-stream.
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration, delegate: CloudSessionDelegate(), delegateQueue: nil)
    }
    func useModel(_ model: QwenModel) { selectedModel = model }
    func cancel() {
        operationID = nil
        active?.cancel()
        active = nil
        activeStream?.cancel()
        activeStream = nil
    }
    func useSavedCredential(_ key: String) {
        cancel()
        cachedCredential = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Reads the Keychain key before the panel is shown. A Keychain password
    /// prompt deactivates the app, and the floating panel hides on deactivation,
    /// so the prompt must not appear while the user is working in the panel.
    /// Failures are not cached; the request path reports them normally.
    func prepareCredential() {
        guard cachedCredential == nil else { return }
        cachedCredential = try? credential()
    }
    func infer(text: String, action: AssistantAction, additionalInstructions: String) async throws -> ModelResult {
        try Task.checkCancellation()
        guard operationID == nil else { throw AssistantFailure.cloudUnavailable }
        try CloudAPIContract.validateInput(text)
        let key = try cachedCredential ?? credential()
        let request = try CloudAPIContract.request(text: text, action: action, additionalInstructions: additionalInstructions,
                                                   key: key, model: selectedModel.rawValue)
        lastRawRequest = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        lastRawResponse = nil
        cachedCredential = key
        let id = UUID()
        operationID = id
        Diagnostics.event("cloud_request_started", action: action.rawValue, mode: "non-thinking")
        let task = Task { [session] in
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw AssistantFailure.cloudUnavailable }
            guard response.expectedContentLength <= 128_000 else { throw AssistantFailure.invalidResult }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 128_000 else { throw AssistantFailure.invalidResult }
                data.append(byte)
            }
            await MainActor.run {
                self.lastRawResponse = String(data: data, encoding: .utf8) ?? "<binary response>"
            }
            do {
                return try CloudAPIContract.parse(data: data, statusCode: http.statusCode, action: action)
            } catch let failure as AssistantFailure where failure == .invalidResult && http.statusCode == 200 {
                // 200 OK but the content could not be parsed: surface the raw body for debug.
                throw InvalidResultError(underlying: failure,
                                         rawResponse: String(data: data, encoding: .utf8) ?? "<binary response>")
            }
        }
        active = task
        defer {
            if operationID == id { active = nil; operationID = nil }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard operationID == id else { throw AssistantFailure.cancelled }
            Diagnostics.event("cloud_request_success", action: action.rawValue, mode: "non-thinking")
            return result
        } catch {
            if Task.isCancelled || operationID != id || (error as? URLError)?.code == .cancelled || error is CancellationError {
                Diagnostics.event("cloud_request_cancelled", action: action.rawValue)
                throw AssistantFailure.cancelled
            }
            Diagnostics.event("cloud_request_failed", action: action.rawValue)
            if let debug = error as? InvalidResultError { throw debug }
            if let failure = error as? AssistantFailure { throw failure }
            if (error as? URLError)?.code == .timedOut { throw AssistantFailure.timedOut }
            // Never expose provider response bodies, drafts or credential-bearing errors.
            throw AssistantFailure.cloudUnavailable
        }
    }

    func inferStream(text: String, action: AssistantAction, additionalInstructions: String,
                     onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        try Task.checkCancellation()
        guard operationID == nil else { throw AssistantFailure.cloudUnavailable }
        try CloudAPIContract.validateInput(text)
        let key = try cachedCredential ?? credential()
        let request = try CloudAPIContract.request(text: text, action: action,
                                                   additionalInstructions: additionalInstructions,
                                                   key: key, stream: true, model: selectedModel.rawValue)
        cachedCredential = key
        return try await performStream(request: request, action: action.rawValue, onDelta: onDelta)
    }

    func answerQuestion(context: String, messages: [QuestionMessage],
                        onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        try Task.checkCancellation()
        guard operationID == nil else { throw AssistantFailure.cloudUnavailable }
        try QuestionAPIContract.validate(context: context, messages: messages)
        let key = try cachedCredential ?? credential()
        let request = try QuestionAPIContract.request(context: context, messages: messages,
                                                       key: key, model: selectedModel.rawValue)
        cachedCredential = key
        return try await performStream(request: request, action: "question", onDelta: onDelta)
    }

    private func performStream(request: URLRequest, action: String,
                               onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        lastRawRequest = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        lastRawResponse = nil
        let id = UUID()
        operationID = id
        Diagnostics.event("cloud_request_started", action: action, mode: "stream")

        let task = Task { [session] () -> String in
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw AssistantFailure.cloudUnavailable }
            var wireData = Data()
            defer {
                // Includes metadata-only events, [DONE] and incomplete bytes if
                // transport ends early. Stale requests cannot overwrite new ones.
                if self.operationID == id, !wireData.isEmpty {
                    self.lastRawResponse = String(decoding: wireData, as: UTF8.self)
                }
            }
            // Keep the original HTTP error body for inspection, without exposing
            // request headers or the credential in user-facing error messages.
            if http.statusCode != 200 {
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard wireData.count < 200_000 else { break }
                    wireData.append(byte)
                }
                switch http.statusCode {
                case 401, 403: throw AssistantFailure.cloudAuth
                case 429: throw AssistantFailure.cloudRateLimit
                default: throw AssistantFailure.cloudUnavailable
                }
            }

            var accumulator = ""
            var lineBuffer = Data()
            func handleLine() async {
                defer { lineBuffer.removeAll(keepingCapacity: true) }
                guard lineBuffer.starts(with: Data("data:".utf8)) else { return }
                var payload = lineBuffer.dropFirst(5)
                while let first = payload.first, first == 0x20 || first == 0x09 || first == 0x0D {
                    payload = payload.dropFirst()
                }
                guard !payload.isEmpty, payload != Data("[DONE]".utf8) else { return }
                let payloadData = Data(payload)
                guard let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                      let choices = obj["choices"] as? [[String: Any]] else { return }
                // Content may arrive as a streaming delta; some providers also
                // echo a complete message. Accept both.
                var piece: String?
                if let delta = choices.first?["delta"] as? [String: Any] {
                    piece = delta["content"] as? String
                } else if let message = choices.first?["message"] as? [String: Any] {
                    piece = message["content"] as? String
                }
                if let piece, !piece.isEmpty {
                    accumulator += piece
                    let snapshot = piece
                    await MainActor.run {
                        guard self.operationID == id else { return }
                        self.lastRawResponse = String(decoding: wireData, as: UTF8.self)
                        onDelta(snapshot)
                    }
                }
            }
            for try await byte in bytes {
                try Task.checkCancellation()
                guard wireData.count < 2_000_000, accumulator.utf8.count < 200_000 else {
                    throw AssistantFailure.invalidResult
                }
                wireData.append(byte)
                if byte == 0x0A {
                    await handleLine()
                } else {
                    lineBuffer.append(byte)
                }
            }
            await handleLine()
            return accumulator
        }

        activeStream = task
        defer { if operationID == id { activeStream = nil; operationID = nil } }
        do {
            let content = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard operationID == id else { throw AssistantFailure.cancelled }
            Diagnostics.event("cloud_request_success", action: action, mode: "stream")
            return content
        } catch {
            if Task.isCancelled || operationID != id || (error as? URLError)?.code == .cancelled || error is CancellationError {
                Diagnostics.event("cloud_request_cancelled", action: action)
                throw AssistantFailure.cancelled
            }
            Diagnostics.event("cloud_request_failed", action: action)
            if let failure = error as? AssistantFailure { throw failure }
            if (error as? URLError)?.code == .timedOut { throw AssistantFailure.timedOut }
            throw AssistantFailure.cloudUnavailable
        }
    }
}
