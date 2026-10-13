import Foundation
import XCTest
import AssistantCore
@testable import EnglishCompass

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var holdOpen = false
    static var onStart: (() -> Void)?
    static var onStop: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            Self.onStart?()
            if !Self.holdOpen { client?.urlProtocolDidFinishLoading(self) }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { Self.onStop?() }
}

final class NativeInferenceTests: XCTestCase {
    @MainActor func testCredentialReadOnceAcrossActionsAndUpdatedWithoutRereadingKeychain() async {
        defer { clearStub() }
        var reads = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let inference = InferenceService(session: URLSession(configuration: configuration),
                                         credential: { reads += 1; return "synthetic-key" })
        var expected = "Bearer synthetic-key"
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), expected)
            return (401, Data())
        }
        for action in [AssistantAction.writeEnglish, .understandEnglish] {
            do {
                _ = try await inference.infer(text: "Synthetic draft.", action: action, additionalInstructions: "")
                XCTFail("Expected auth failure")
            } catch { XCTAssertEqual(error as? AssistantFailure, .cloudAuth) }
        }
        XCTAssertEqual(reads, 1)
        inference.cancel()
        inference.useSavedCredential(" replacement-key ")
        expected = "Bearer replacement-key"
        do {
            _ = try await inference.infer(text: "Synthetic draft.", action: .writeEnglish, additionalInstructions: "")
            XCTFail("Expected auth failure")
        } catch { XCTAssertEqual(error as? AssistantFailure, .cloudAuth) }
        XCTAssertEqual(reads, 1)
    }

    @MainActor func testPreparedCredentialIsReusedByLaterRequests() async {
        defer { clearStub() }
        var reads = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let inference = InferenceService(session: URLSession(configuration: configuration),
                                         credential: { reads += 1; return "synthetic-key" })
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
            return (401, Data())
        }
        inference.prepareCredential()
        inference.prepareCredential()
        XCTAssertEqual(reads, 1)
        do {
            _ = try await inference.infer(text: "Synthetic draft.", action: .writeEnglish, additionalInstructions: "")
            XCTFail("Expected auth failure")
        } catch { XCTAssertEqual(error as? AssistantFailure, .cloudAuth) }
        XCTAssertEqual(reads, 1)
    }

    @MainActor func testFailedKeychainReadIsNotCached() async {
        var reads = 0
        let inference = InferenceService(credential: {
            reads += 1
            throw AssistantFailure.cloudKeychainAccess
        })
        for _ in 0..<2 {
            do {
                _ = try await inference.infer(text: "Synthetic draft.", action: .writeEnglish, additionalInstructions: "")
                XCTFail("Expected Keychain failure")
            } catch { XCTAssertEqual(error as? AssistantFailure, .cloudKeychainAccess) }
        }
        XCTAssertEqual(reads, 2)
    }

    @MainActor func testInvalidInputNeverReadsCredential() async {
        var credentialReads = 0
        let inference = InferenceService(credential: { credentialReads += 1; return "synthetic-key" })
        for (text, expected) in [("  ", AssistantFailure.noText), (String(repeating: "A", count: 16_001), .contextLimit)] {
            do {
                _ = try await inference.infer(text: text, action: .writeEnglish, additionalInstructions: "")
                XCTFail("Invalid input accepted")
            } catch { XCTAssertEqual(error as? AssistantFailure, expected) }
        }
        XCTAssertEqual(credentialReads, 0)
    }
    private func clearStub() {
        StubURLProtocol.handler = nil; StubURLProtocol.holdOpen = false
        StubURLProtocol.onStart = nil; StubURLProtocol.onStop = nil
    }
    @MainActor func testCancellationStopsNativeTransport() async throws {
        defer { clearStub() }
        let started = expectation(description: "Request started"), stopped = expectation(description: "Transport stopped")
        StubURLProtocol.handler = { _ in (200, Data()) }
        StubURLProtocol.holdOpen = true
        StubURLProtocol.onStart = { started.fulfill() }
        StubURLProtocol.onStop = { stopped.fulfill() }
        let inference = service()
        let request = Task { try await inference.infer(text: "Synthetic draft.", action: .writeEnglish, additionalInstructions: "") }
        await fulfillment(of: [started], timeout: 2)
        inference.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        do { _ = try await request.value; XCTFail("Cancelled request succeeded") }
        catch { XCTAssertEqual(error as? AssistantFailure, .cancelled) }
    }
    @MainActor func testParentCancellationStopsNativeTransport() async throws {
        defer { clearStub() }
        let started = expectation(description: "Request started"), stopped = expectation(description: "Transport stopped")
        StubURLProtocol.handler = { _ in (200, Data()) }
        StubURLProtocol.holdOpen = true
        StubURLProtocol.onStart = { started.fulfill() }
        StubURLProtocol.onStop = { stopped.fulfill() }
        let inference = service()
        let request = Task { try await inference.infer(text: "Synthetic draft.", action: .writeEnglish, additionalInstructions: "") }
        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        do { _ = try await request.value; XCTFail("Cancelled request succeeded") }
        catch { XCTAssertEqual(error as? AssistantFailure, .cancelled) }
    }
    @MainActor func testOversizedResponseStopsTransportAndFailsClosed() async throws {
        defer { clearStub() }
        let stopped = expectation(description: "Oversized transport stopped")
        StubURLProtocol.handler = { _ in (200, Data(repeating: 65, count: 200_000)) }
        StubURLProtocol.holdOpen = true
        StubURLProtocol.onStop = { stopped.fulfill() }
        do {
            _ = try await service().infer(text: "Synthetic draft.", action: .writeEnglish, additionalInstructions: "")
            XCTFail("Oversized response accepted")
        } catch { XCTAssertEqual(error as? AssistantFailure, .invalidResult) }
        await fulfillment(of: [stopped], timeout: 2)
    }
    @MainActor func testOptionalLiveBailianSmoke() async throws {
        guard let key = ProcessInfo.processInfo.environment["ENGLISHCOMPASS_TEST_KEY"], !key.isEmpty else {
            throw XCTSkip("Live smoke requires an explicitly supplied test credential.")
        }
        let inference = InferenceService(credential: { key })
        defer { inference.cancel() }
        let start = Date()
        let written = try await inference.infer(text: "Please helps me fix this bug.", action: .writeEnglish, additionalInstructions: "")
        XCTAssertEqual(written.candidates.count, 3)
        XCTAssertEqual(written.candidates[0], "Please help me fix this bug.")
        let translated = try await inference.infer(text: "Do not delete the file.", action: .understandEnglish, additionalInstructions: "")
        XCTAssertEqual(translated.candidates.count, 1)
        XCTAssertTrue(translated.candidates[0].contains("不"))
        XCTAssertTrue(translated.candidates[0].contains("删除"))
        print("event=native_https_smoke_passed elapsed_seconds=\(Date().timeIntervalSince(start))")
    }
    @MainActor private func service() -> InferenceService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return InferenceService(session: URLSession(configuration: configuration), credential: { "synthetic-key" })
    }
    @MainActor func testNativeRequestUsesFixedProviderAndCredentialHeader() async throws {
        defer { StubURLProtocol.handler = nil }
        let content = String(decoding: try JSONEncoder().encode(WritingFixture.result), as: UTF8.self)
        let response: [String: Any] = ["model": "qwen3.7-flash", "choices": [
            ["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": content]]]]
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "dashscope.aliyuncs.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
            return (200, try JSONSerialization.data(withJSONObject: response))
        }
        let result = try await service().infer(text: "Synthetic draft.", action: .writeEnglish, additionalInstructions: "")
        XCTAssertEqual(result, WritingFixture.result)
    }
    @MainActor func testAuthenticationFailureIsNotRetried() async {
        defer { StubURLProtocol.handler = nil }
        var calls = 0
        StubURLProtocol.handler = { _ in calls += 1; return (401, Data("private provider error".utf8)) }
        do {
            _ = try await service().infer(text: "Synthetic draft.", action: .writeEnglish, additionalInstructions: "")
            XCTFail("Expected auth failure")
        } catch { XCTAssertEqual(error as? AssistantFailure, .cloudAuth) }
        XCTAssertEqual(calls, 1)
    }
    @MainActor func testTimeoutHasSafeRecoveryMessage() async {
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await service().infer(text: "Synthetic draft.", action: .writeEnglish, additionalInstructions: "")
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? AssistantFailure, .timedOut) }
    }
    func testRedirectCannotForwardCredentialOrDraft() {
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let redirect = URLRequest(url: URL(string: "https://example.invalid/")!)
        CloudSessionDelegate().urlSession(session, task: session.dataTask(with: url),
                                         willPerformHTTPRedirection: response, newRequest: redirect) { request in
            XCTAssertNil(request)
        }
        session.invalidateAndCancel()
    }
}
