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
    func infer(text: String, action: AssistantAction, additionalInstructions: String) async throws -> ModelResult
    func cancel()
}

extension InferencePerforming {
    var lastRawRequest: String? { nil }
    var lastRawResponse: String? { nil }
}

@MainActor
final class InferenceService: InferencePerforming {
    private let session: URLSession
    private let credential: () throws -> String
    // Process-local only: never persist or log this copy of the Keychain secret.
    private var cachedCredential: String?
    private var active: Task<ModelResult, Error>?
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
        configuration.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: configuration, delegate: CloudSessionDelegate(), delegateQueue: nil)
    }
    func cancel() {
        operationID = nil
        active?.cancel()
        active = nil
    }
    func useSavedCredential(_ key: String) {
        cancel()
        cachedCredential = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func infer(text: String, action: AssistantAction, additionalInstructions: String) async throws -> ModelResult {
        try Task.checkCancellation()
        guard operationID == nil else { throw AssistantFailure.cloudUnavailable }
        try CloudAPIContract.validateInput(text)
        let key = try cachedCredential ?? credential()
        let request = try CloudAPIContract.request(text: text, action: action, additionalInstructions: additionalInstructions, key: key)
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
}
