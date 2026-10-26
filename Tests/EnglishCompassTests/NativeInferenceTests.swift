import Foundation
import AppKit
import SwiftUI
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
    @MainActor func testWritingLanguageReachesBothTransportModes() async throws {
        defer { clearStub() }
        let inference = service()
        StubURLProtocol.handler = { _ in (401, Data("{}".utf8)) }
        for language in [WritingLanguage.french, .arabic] {
            inference.useWritingLanguage(language)
            for streaming in [false, true] {
                do {
                    if streaming {
                        _ = try await inference.inferStream(text: "你好", action: .writeEnglish, additionalInstructions: "") { _ in }
                    } else {
                        _ = try await inference.infer(text: "你好", action: .writeEnglish, additionalInstructions: "")
                    }
                    XCTFail("Expected authentication failure from stub")
                } catch { XCTAssertEqual(error as? AssistantFailure, .cloudAuth) }
                let raw = try XCTUnwrap(inference.lastRawRequest)
                XCTAssertTrue(raw.contains("always \(language.name)"))
                XCTAssertFalse(raw.contains("always English"))
                XCTAssertFalse(raw.contains("{targetLanguage}"))
            }
        }
    }

    @MainActor func testQuestionStreamsMarkdownAndReusesCachedCredential() async throws {
        defer { clearStub() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        var reads = 0
        let inference = InferenceService(session: URLSession(configuration: configuration),
                                         credential: { reads += 1; return "synthetic-key" })
        inference.useModel(.plus37)
        let markdown = "## Grammar\n\nUse **inertial scrolling**."
        let payload = String(decoding: try JSONSerialization.data(withJSONObject:
            ["choices": [["delta": ["content": markdown]]]]), as: UTF8.self)
        StubURLProtocol.handler = { _ in
            (200, Data("data: \(payload)\n\ndata: [DONE]\n\n".utf8))
        }
        for _ in 0..<2 {
            var streamed = ""
            let answer = try await inference.answerQuestion(context: "Original sentence",
                messages: [.init(role: .user, content: "Why?")]) { streamed += $0 }
            XCTAssertEqual(answer, markdown)
            XCTAssertEqual(streamed, markdown)
        }
        XCTAssertEqual(reads, 1)
        let body = try XCTUnwrap(inference.lastRawRequest)
        XCTAssertTrue(body.contains(QwenModel.plus37.rawValue))
        XCTAssertFalse(body.contains("synthetic-key"))
    }

    @MainActor func testModelPresetsPersistAndReachBothTransportModes() async throws {
        defer { clearStub() }
        let name = "ModelSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.model, .flash37)
        let inference = service()
        for model in QwenModel.allCases {
            preferences.model = model
            XCTAssertEqual(Preferences(defaults: defaults).model, model)
            inference.useModel(preferences.model)
            StubURLProtocol.handler = { _ in
                (401, Data("{\"error\":\"synthetic\"}".utf8))
            }
            func checkRequest() throws {
                let raw = try XCTUnwrap(inference.lastRawRequest)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
                XCTAssertEqual(json["model"] as? String, model.rawValue)
                XCTAssertEqual(json["max_tokens"] as? Int, 8192)
                XCTAssertEqual(json["enable_thinking"] as? Bool, false)
            }
            for action in [AssistantAction.writeEnglish, .understandEnglish] {
                do {
                    _ = try await inference.infer(text: "Hi.", action: action, additionalInstructions: "")
                    XCTFail("Expected controlled error")
                } catch { XCTAssertEqual(error as? AssistantFailure, .cloudAuth) }
                try checkRequest()
                do {
                    _ = try await inference.inferStream(text: "Hi.", action: action, additionalInstructions: "") { _ in }
                    XCTFail("Expected controlled error")
                } catch { XCTAssertEqual(error as? AssistantFailure, .cloudAuth) }
                try checkRequest()
            }
        }
        defaults.set("unknown-model", forKey: "qwenModel")
        XCTAssertEqual(Preferences(defaults: defaults).model, .flash37)
    }

    @MainActor func testSessionCapturesModelAtRequestStart() async throws {
        defer { clearStub() }
        let name = "ModelSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.model = .plus37
        preferences.writingLanguage = .french
        let content = "## General\nHello.\n## Direction\n更自然\n## Alternative\nHi.\n## Notes\nA note."
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": content]]]]), as: UTF8.self)
        StubURLProtocol.handler = { _ in
            return (200, Data("data: \(payload)\n\ndata: [DONE]\n\n".utf8))
        }
        let session = AssistantSession(preferences: preferences, accessibility: AccessibilityBridge(), inference: service())
        session.input = "Hello."; session.process()
        preferences.model = .max38
        preferences.writingLanguage = .spanish
        for _ in 0..<200 where session.requestStartedAt != nil { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(session.requestModel, .plus37)
        XCTAssertEqual(session.requestLanguage, .french)
        XCTAssertEqual(session.actionTitle, "Write in French")
        XCTAssertEqual(session.result?.candidates.count, 2)
        let json = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(session.rawRequest).utf8)) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, QwenModel.plus37.rawValue)
        XCTAssertEqual(session.candidateIndex, 0)
        XCTAssertEqual(session.suggestion, "Hello.")
    }

    @MainActor func testOptionalLiveQwenPresetsSmoke() async throws {
        guard ProcessInfo.processInfo.environment["ENGLISHCOMPASS_TEST_MODELS"] == "1",
              let key = ProcessInfo.processInfo.environment["ENGLISHCOMPASS_TEST_KEY"], !key.isEmpty else {
            throw XCTSkip("Preset live calls require opt-in and a test credential.")
        }
        let inference = InferenceService(credential: { key })
        defer { inference.cancel() }
        for model in QwenModel.allCases {
            inference.useModel(model)
            let content = try await inference.inferStream(text: "Please helps me fix this bug.",
                action: .writeEnglish, additionalInstructions: "") { _ in }
            let result = try CloudAPIContract.parseContent(content, action: .writeEnglish)
            XCTAssertEqual(result.candidates.count, 2)
            XCTAssertFalse(result.summary.isEmpty)
            XCTAssertFalse(inference.lastRawRequest?.contains(key) == true)
            XCTAssertTrue(inference.lastRawResponse?.contains("[DONE]") == true)
            print("event=live_preset_smoke model=\(model.rawValue) candidates=\(result.candidates.count)")
        }
    }

    @MainActor func testStreamPreservesWireResponseIncludingMetadataAndDone() async throws {
        defer { clearStub() }
        let wire = """
        data: {"id":"synthetic-completion","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello **world**."},"finish_reason":null}]}

        data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":4}}

        data: [DONE]

        """
        StubURLProtocol.handler = { _ in (200, Data(wire.utf8)) }
        let inference = service()
        var deltas = ""
        let content = try await inference.inferStream(text: "Hello world.", action: .writeEnglish,
                                                       additionalInstructions: "") { delta in
            deltas += delta
            XCTAssertTrue(inference.lastRawResponse?.hasPrefix("data:") == true,
                          "Raw response must be available before the UI receives a delta")
        }
        XCTAssertEqual(content, "Hello **world**.")
        XCTAssertEqual(deltas, content)
        XCTAssertEqual(inference.lastRawResponse, wire)
        XCTAssertTrue(inference.lastRawResponse?.contains("completion_tokens") == true)
        XCTAssertTrue(inference.lastRawResponse?.contains("[DONE]") == true)
    }

    @MainActor func testSuccessfulStreamSessionPublishesRawResponseAndClearsItOnNewSession() async throws {
        defer { clearStub() }
        let content = "## General\nHello.\n\n## Direction\n更自然\n## Alternative\nHi.\n\n\n## Notes\nA short note."
        let event: [String: Any] = ["choices": [["index": 0, "delta": ["content": content]]]]
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self)
        let wire = "data: \(payload)\n\ndata: [DONE]\n\n"
        StubURLProtocol.handler = { _ in (200, Data(wire.utf8)) }
        let name = "EnglishCompassTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = AssistantSession(preferences: Preferences(defaults: defaults),
                                       accessibility: AccessibilityBridge(), inference: service())
        session.input = "Hello."
        session.process()
        for _ in 0..<200 where session.requestStartedAt != nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(session.phase, .result)
        XCTAssertNil(session.requestStartedAt, "The actual request must have completed")
        XCTAssertEqual(session.result?.candidates, ["Hello.", "Hi."])
        XCTAssertEqual(session.rawResponse, wire, "Valid responses must not leave the debug sheet empty")
        XCTAssertNotNil(session.rawRequest)
        XCTAssertFalse(try XCTUnwrap(session.rawRequest).contains("synthetic-key"))
        XCTAssertEqual(String(JSONDebugView.highlight(try XCTUnwrap(session.rawResponse)).characters), wire)
        session.begin(.understandEnglish, capture: false)
        XCTAssertNil(session.rawResponse, "A new request must not show the previous response")
        XCTAssertNil(session.rawRequest)
    }

    @MainActor func testMalformedStreamSessionKeepsOriginalRawWireBody() async throws {
        defer { clearStub() }
        let wire = "data: {\"choices\":[{\"delta\":{\"content\":\"An unsectioned answer.\"}}]}\n\ndata: [DONE]\n\n"
        StubURLProtocol.handler = { _ in (200, Data(wire.utf8)) }
        let name = "EnglishCompassTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = AssistantSession(preferences: Preferences(defaults: defaults),
                                       accessibility: AccessibilityBridge(), inference: service())
        session.input = "Hello."
        session.process()
        for _ in 0..<200 where session.requestStartedAt != nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertNil(session.requestStartedAt)
        XCTAssertEqual(session.phase, .result)
        XCTAssertEqual(session.rawResponse, wire, "Fallback must not replace raw SSE with the extracted answer")
    }

    @MainActor func testStreamHTTPErrorBodyRemainsInspectable() async throws {
        defer { clearStub() }
        let wire = "{\"error\":{\"code\":\"invalid_api_key\",\"message\":\"Synthetic auth failure\"}}"
        StubURLProtocol.handler = { _ in (401, Data(wire.utf8)) }
        let inference = service()
        do {
            _ = try await inference.inferStream(text: "Hello.", action: .writeEnglish,
                                                additionalInstructions: "") { _ in XCTFail("No content delta expected") }
            XCTFail("Expected auth failure")
        } catch { XCTAssertEqual(error as? AssistantFailure, .cloudAuth) }
        XCTAssertEqual(inference.lastRawResponse, wire)
    }

    @MainActor func testOptionalLiveStreamingRawResponseSmoke() async throws {
        guard let key = ProcessInfo.processInfo.environment["ENGLISHCOMPASS_TEST_KEY"], !key.isEmpty else {
            throw XCTSkip("Live smoke requires an explicitly supplied test credential.")
        }
        let name = "EnglishCompassTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = AssistantSession(preferences: Preferences(defaults: defaults),
                                       accessibility: AccessibilityBridge(),
                                       inference: InferenceService(credential: { key }))
        for (action, text) in [(AssistantAction.writeEnglish, "Please helps me fix this bug."),
                               (.understandEnglish, "Do not delete the file.")] {
            session.begin(action, capture: false)
            session.input = text
            session.process()
            for _ in 0..<600 where session.requestStartedAt != nil {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertNil(session.requestStartedAt, "Live request must complete within smoke timeout")
            XCTAssertEqual(session.phase, .result)
            let raw = try XCTUnwrap(session.rawResponse)
            XCTAssertTrue(raw.hasPrefix("data:"))
            XCTAssertTrue(raw.contains("[DONE]"))
            XCTAssertTrue(raw.contains("usage"))
            XCTAssertFalse(raw.contains(key))
            XCTAssertNotNil(session.result)
            if action == .writeEnglish { XCTAssertEqual(session.result?.candidates.count, 2) }
            else { XCTAssertEqual(session.result?.candidates.count, 1) }
            XCTAssertEqual(String(JSONDebugView.highlight(raw).characters), raw)
            if action == .writeEnglish,
               let path = ProcessInfo.processInfo.environment["ENGLISHCOMPASS_RAW_PREVIEW"] {
                // Opt-in local verification of the exact sheet the user sees.
                // No headers/keys, and no persistent snapshot during normal tests.
                let view = NSHostingView(rootView: RequestDebugSheet(request: session.rawRequest, response: raw))
                view.frame = NSRect(x: 0, y: 0, width: 680, height: 560)
                view.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 100_000_000)
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: path))
            }
            print("event=live_raw_response_smoke action=\(action.rawValue) bytes=\(raw.utf8.count)")
        }
        session.cancel()
    }

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
        XCTAssertEqual(written.candidates.count, 2)
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
        let fixture = WritingFixture.result
        let content = "## General\n\(fixture.markdownCandidates[0])\n## Direction\n\(fixture.revisionDirection!)\n## Alternative\n\(fixture.markdownCandidates[1])\n\(fixture.summary)"
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
