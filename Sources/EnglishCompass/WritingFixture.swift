import AssistantCore

/// Synthetic only; used by preview rendering and explicit --ui-test launches.
enum WritingFixture {
    static let result = ModelResult(
        candidates: ["Please help me fix this bug.", "Please help me resolve this issue."],
        summary: "## Notes\n- Please 后使用动词原形 help，而不是 helps。\n- 第二版调整措辞，保持原有请求和语气。",
        markdownCandidates: ["Please **help** me fix this bug.", "Please **help** me *resolve this issue*."],
        revisionDirection: "调整措辞")
}
