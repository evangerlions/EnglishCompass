import Foundation
import AssistantCore

/// Local latency benchmark across Bailian/DashScope text models.
///
/// Uses the EXACT production system prompt and generation parameters; only the
/// `model` field changes. Measures non-stream total, streaming TTFB/total and
/// token usage for both the Write and Understand requests.
///
/// Run from an interactive shell (so BAILIAN_API_KEY from ~/.zshrc is present):
///   ./Scripts/bench.sh                      # curated mainstream models, 3 runs
///   ./Scripts/bench.sh 5                    # 5 runs
///   ./Scripts/bench.sh 3 m1,m2              # 3 runs, specific models
///   ./Scripts/bench.sh 3 all                # probe every text model on the key
///   ./Scripts/bench.sh probe                # one-shot availability/timing probe
@main
struct ECBench {
    static let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    /// Current-generation text models that answer with the app's exact
    /// production parameters (enable_thinking + response_format). Models needing
    /// product activation or incompatible params are reachable via explicit args
    /// / `all`, just not in the default comparable set.
    static let curatedModels = [
        "qwen3.8-flash", "qwen3.8-max", "qwen3.8-27b",
        "qwen3.7-flash", "qwen3.7-plus", "qwen3.7-max",
        "qwen3.6-flash", "qwen3.5-flash",
        "deepseek-v4.1-flash", "deepseek-v4-pro"
    ]

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let probeOnly = args.first == "probe"
        if args.first == "parsefile" {
            let path = args.count > 1 ? args[1] : "/tmp/ec-formatcheck.md"
            let action: AssistantAction = args.count > 2 && args[2] == "understand" ? .understandEnglish : .writeEnglish
            let content = (try? String(contentsOfFile: path)) ?? ""
            print("chars=\(content.count)")
            do {
                let r = try CloudAPIContract.parse(data: Data(content.utf8), statusCode: 200, action: action)
                print("PARSE_OK cand=\(r.candidates.count) expl=\(r.explanations.count) md=\(r.markdownCandidates.count) sum=\(r.summary.count)")
            } catch { print("PARSE_FAIL:", error) }
            return
        }
        if args.first == "check" {
            guard let k = ProcessInfo.processInfo.environment["BAILIAN_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty else {
            FileHandle.standardError.write(Data("error: BAILIAN_API_KEY not set\n".utf8)); exit(2) }
            let model = args.count > 1 ? args[1] : CloudAPIContract.model
            await FormatCheck.run(model: model, key: k)
            return
        }
        let runs: Int = {
            if probeOnly { return 1 }
            if let s = args.first(where: { $0.allSatisfy { $0.isNumber } }), let v = Int(s) { return v }
            return 3
        }()
        let modelArg = args.first { $0 != "probe" && !$0.allSatisfy { $0.isNumber } }
        let parallel = 4

        guard let key = ProcessInfo.processInfo.environment["BAILIAN_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            FileHandle.standardError.write(Data("error: BAILIAN_API_KEY not set (run via Scripts/bench.sh)\n".utf8)); exit(2)
        }

        var models: [String]
        if modelArg == "all" {
            models = (try? await listTextModels(key: key)) ?? curatedModels
            print("probing \(models.count) text models visible to this key")
        } else if let m = modelArg, m != "all" {
            models = m.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } else {
            models = curatedModels
        }

        let samples: [(tag: String, action: AssistantAction, text: String)] = [
            ("write", .writeEnglish, SampleInput.write),
            ("understand", .understandEnglish, SampleInput.understand)
        ]

        print("runs=\(runs) parallel=\(parallel) models=\(models.count)")
        print("model,tag,mode,run,total_ms,ttfb_ms,prompt,completion,status")
        var rows: [Row] = []

        if probeOnly {
            await runParallel(models, parallel) { model in
                let r = await Caller.call(model: model, key: key, action: .writeEnglish,
                                          text: SampleInput.write, stream: false, strict: false)
                return [r]
            } collect: { rows.append(contentsOf: $0) }
            printProbe(rows)
            writeCSV(rows, suffix: "probe")
            return
        }

        for (tag, action, text) in samples {
            struct Job { let model: String; let runIndex: Int; let action: AssistantAction; let text: String; let tag: String }
            let jobs = models.flatMap { m in (0..<runs).map { Job(model: m, runIndex: $0, action: action, text: text, tag: tag) } }
            await runParallel(jobs, parallel) { job in
                async let ns = Caller.call(model: job.model, key: key, action: job.action, text: job.text,
                                           stream: false, strict: true, run: job.runIndex, tag: job.tag)
                async let st = Caller.call(model: job.model, key: key, action: job.action, text: job.text,
                                           stream: true, strict: true, run: job.runIndex, tag: job.tag)
                return (try? await [ns, st]) ?? []
            } collect: { rows.append(contentsOf: $0) }
        }

        printSummary(rows, samples: samples.map { $0.tag }, models: models)
        writeCSV(rows, suffix: "bench")
    }

    // MARK: - Parallel helper

    static func runParallel<T>(_ items: [T], _ width: Int,
                               body: @escaping (T) async -> [Row],
                               collect: ([Row]) -> Void) async {
        var index = 0
        await withTaskGroup(of: [Row].self) { group in
            func spawn(_ i: Int) {
                guard i < items.count else { return }
                group.addTask { await body(items[i]) }
            }
            for i in 0..<min(width, items.count) { spawn(i); index += 1 }
            while let out = await group.next() {
                collect(out)
                if index < items.count { spawn(index); index += 1 }
            }
        }
    }

    // MARK: - Reporting

    static func printProbe(_ rows: [Row]) {
        print("\n== availability probe (write, one non-stream call) ==")
        print(String(format: "%-28@ %8@ %8@ %8@  %@", "model", "ms", "prompt", "compl", "status"))
        for r in rows.sorted(by: { $0.model < $1.model }) {
            print(String(format: "%-28@ %8.0f %8d %8d  %@", r.model, r.totalMS, r.prompt, r.completion, r.status))
        }
    }

    static func printSummary(_ rows: [Row], samples: [String], models: [String]) {
        for tag in samples {
            print("\n================  \(tag.uppercased())  ================")
            print(String(format: "%-28@ %6@ | %@ | %@", "model", "ok/n",
                        "nonstream total (avg / p50 / min)", "stream TTFB (avg / p50 / min)  tok/s"))
            for model in models {
                let base = rows.filter { $0.model == model && $0.tag == tag && $0.ok }
                let ns = base.filter { $0.mode == "nonstream" }.map { $0.totalMS }.sorted()
                let st = base.filter { $0.mode == "stream" }
                let ttfb = st.map { $0.ttfbMS }.filter { $0 > 0 }.sorted()
                let n = base.filter { $0.mode == "nonstream" }.count
                let totalN = rows.filter { $0.model == model && $0.tag == tag && $0.mode == "nonstream" }.count
                guard !ns.isEmpty, !ttfb.isEmpty else {
                    print(String(format: "%-28@ %4d/%-2d | (no successful samples)", model, n, totalN)); continue
                }
                let avgComp = Double(st.map { $0.completion }.filter { $0 > 0 }.reduce(0, +)) / Double(max(1, st.count))
                let genMS = max(1, average(st.map { $0.totalMS }) - average(ttfb))
                let toks = avgComp / (genMS / 1000)
                print(String(format: "%-28@ %4d/%-2d | %6.0f / %5.0f / %5.0f | %6.0f / %5.0f / %5.0f  %5.0f",
                            model, n, totalN,
                            average(ns), pct(ns, 0.5), ns.first ?? 0,
                            average(ttfb), pct(ttfb, 0.5), ttfb.first ?? 0, toks))
            }
        }
    }

    static func average(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
    static func pct(_ a: [Double], _ p: Double) -> Double {
        guard !a.isEmpty else { return 0 }
        return a[min(a.count - 1, max(0, Int((Double(a.count - 1) * p).rounded())))]
    }

    static func writeCSV(_ rows: [Row], suffix: String) {
        let url = URL(fileURLWithPath: "/tmp/ec-bench-\(suffix).csv")
        let header = "model,tag,mode,run,total_ms,ttfb_ms,prompt,completion,status\n"
        let body = rows.map { r in
            String(format: "%@,%@,%@,%d,%.0f,%.0f,%d,%d,%@",
                   r.model, r.tag, r.mode, r.run, r.totalMS, r.ttfbMS, r.prompt, r.completion, r.status)
        }.joined(separator: "\n")
        try? (header + body).write(to: url, atomically: true, encoding: .utf8)
        print("\ncsv: \(url.path)")
    }

    static func listTextModels(key: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = o["data"] as? [[String: Any]] else { return curatedModels }
        let bad = ["image", "audio", "omni", "realtime", "embedding", "rerank", "asr", "translate",
                   "tts", "speech", "video", "ocr", "coder", "vl", "math", "0.5b", "1.5b", "1.8b",
                   "7b", "14b", "27b-instruct", "sre", "research", "gui", "character", "deep-search"]
        return list.compactMap { $0["id"] as? String }
            .filter { id in !bad.contains { id.lowercased().contains($0) } }
            .sorted()
    }

    // MARK: - Data

    struct Row {
        var model: String; var tag: String; var mode: String; var run: Int
        var totalMS: Double; var ttfbMS: Double
        var prompt: Int; var completion: Int
        var ok: Bool; var status: String
    }

    enum Caller {
        static func call(model: String, key: String, action: AssistantAction, text: String,
                         stream: Bool, strict: Bool, run: Int = 0, tag: String = "write") async -> Row {
            let mode = stream ? "stream" : "nonstream"
            let sys = (try? CloudAPIContract.prompt(action: action, additionalInstructions: "")) ?? ""
            let maxTokens = action == .writeEnglish ? 4096 : 1024
            var body: [String: Any] = [
                "model": model,
                "messages": [["role": "system", "content": sys], ["role": "user", "content": text]],
                "enable_thinking": false,
                "temperature": 0.1,
                "max_tokens": maxTokens,
                "stream": stream
            ]
            if stream { body["stream_options"] = ["include_usage": true] }
            if strict { body["response_format"] = ["type": "text"] }

            func attempt(extra: [String: Any]) async -> Row {
                var b = body
                extra.forEach { b[$0.key] = $0.value }
                var request = URLRequest(url: ECBench.endpoint, timeoutInterval: 120)
                request.httpMethod = "POST"
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
                request.httpBody = try? JSONSerialization.data(withJSONObject: b)

                let start = Date(); var ttfb = 0.0
                do {
                    let (bytes, response) = try await URLSession(configuration: .ephemeral).bytes(for: request)
                    var n = 0; var collected = Data()
                    for try await byte in bytes {
                        if n == 0 { ttfb = Date().timeIntervalSince(start) * 1000 }
                        n += 1; collected.append(byte)
                    }
                    let total = Date().timeIntervalSince(start) * 1000
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let usage = parseUsage(collected, stream: stream)
                    let ok = code == 200
                    var status = ok ? "ok" : "HTTP\(code)"
                    if ok, strict { status += parseable(collected, stream: stream, action: action) ? "+fmt" : "+badfmt" }
                    if !ok, let msg = errorMessage(collected) { status += " \(msg)" }
                    return Row(model: model, tag: tag, mode: mode, run: run, totalMS: total, ttfbMS: ttfb,
                               prompt: usage.prompt, completion: usage.completion, ok: ok, status: status)
                } catch {
                    return Row(model: model, tag: tag, mode: mode, run: run,
                               totalMS: Date().timeIntervalSince(start) * 1000, ttfbMS: ttfb,
                               prompt: 0, completion: 0, ok: false, status: "err \(String(describing: error).prefix(60))")
                }
            }

            var row = await attempt(extra: [:])
            // Some third-party models reject enable_thinking/response_format: retry
            // once on 400 with those stripped, and flag it so we do not treat the
            // result as production-compatible.
            if !row.ok, row.status.contains("HTTP400") {
                row = await attempt(extra: ["enable_thinking": NSNull(), "response_format": NSNull()])
                if row.ok { row.status += " (compat: dropped qwen params)" }
            }
            print(String(format: "%@,%@,%@,%d,%.0f,%.0f,%d,%d,%@",
                        model, tag, mode, run, row.totalMS, row.ttfbMS, row.prompt, row.completion, row.status))
            return row
        }

        private static func parseUsage(_ data: Data, stream: Bool) -> (prompt: Int, completion: Int) {
            let dictionaries: [[String: Any]]
            if stream {
                let text = String(data: data, encoding: .utf8) ?? ""
                dictionaries = text.split(separator: "\n").compactMap { line in
                    guard line.hasPrefix("data:") else { return nil }
                    let p = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    guard p != "[DONE]", let d = p.data(using: .utf8),
                          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
                    return o
                }
            } else if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dictionaries = [o]
            } else { dictionaries = [] }
            for o in dictionaries.reversed() {
                if let u = o["usage"] as? [String: Any] {
                    return (u["prompt_tokens"] as? Int ?? 0, u["completion_tokens"] as? Int ?? 0)
                }
            }
            return (0, 0)
        }

        private static func parseable(_ data: Data, stream: Bool, action: AssistantAction) -> Bool {
            let content: String
            if stream {
                let text = String(data: data, encoding: .utf8) ?? ""
                var acc = ""
                for line in text.split(separator: "\n") {
                    guard line.hasPrefix("data:") else { continue }
                    let p = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    guard p != "[DONE]", let d = p.data(using: .utf8),
                          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let choices = o["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let piece = delta["content"] as? String else { continue }
                    acc += piece
                }
                content = acc
            } else {
                guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = o["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let c = message["content"] as? String else { return false }
                content = c
            }
            return (try? CloudAPIContract.parse(data: Data(content.utf8), statusCode: 200, action: action)) != nil
        }

        private static func errorMessage(_ data: Data) -> String? {
            guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let e = o["error"] as? [String: Any], let m = e["message"] as? String else { return nil }
            return String(m.prefix(80))
        }
    }

    /// `check [model]`: one production-contract Write call; dumps headings and the
    /// strict parser result, so a `badfmt` signal can be diagnosed against the
    /// exact system prompt the app sends.
    enum FormatCheck {
        static func run(model: String, key: String) async {
            do {
                var req = try CloudAPIContract.request(text: SampleInput.write, action: .writeEnglish,
                                                       additionalInstructions: "", key: key)
                if model != CloudAPIContract.model,
                   let body = req.httpBody, var dict = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    dict["model"] = model
                    req.httpBody = try JSONSerialization.data(withJSONObject: dict)
                }
                let (data, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("model=\(model) HTTP\(code) bytes=\(data.count)")
                guard let env = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = env["choices"] as? [[String: Any]],
                      let content = (choices.first?["message"] as? [String: Any])?["content"] as? String else {
                    print(String(data: data, encoding: .utf8) ?? "<binary>"); return
                }
                print("headings:")
                print(content.replacingOccurrences(of: "\r\n", with: "\n")
                    .components(separatedBy: "\n").filter { $0.hasPrefix("#") }.joined(separator: "\n"))
                try? content.write(toFile: "/tmp/ec-formatcheck.md", atomically: true, encoding: .utf8)
                do {
                    let r = try CloudAPIContract.parse(data: data, statusCode: code, action: .writeEnglish)
                    print("PARSE_OK candidates=\(r.candidates.count) explanations=\(r.explanations.count) summaryChars=\(r.summary.count)")
                } catch {
                    print("PARSE_FAIL: \(error)")
                }
            } catch {
                print("request error: \(error)")
            }
        }
    }

    enum SampleInput {        static let write = """
        Hi team, I want to tell you about the bug we found yesterday. The login page is broken when the user uses a wrong password three times. The screen become white and user can not do anything, they must close the app and open again. I think this is very serious problem because many user will meet it. Can someone help me to check this quickly? We need fix it before this Friday release otherwise customer will be angry.
        """
        static let understand = "I'd rather we didn't roll this out until the edge cases around retries are sorted out."
    }
}
