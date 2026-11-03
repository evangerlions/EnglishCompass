import AssistantCore

/// Synthetic only; used by preview rendering and explicit --ui-test launches.
enum WritingFixture {
    static let result = ModelResult(
        candidates: ["Please help me fix this bug.", "Please help me resolve this issue."],
        explanations: ["- **help**：Please 后使用动词原形，而不是 helps。",
                       "- **resolve this issue**：调整措辞，保持原有请求和语气。"],
        revisionDirection: "调整措辞", usesPlainTextAnswers: true, originalScore: 8)

    static let content = """
    ## Score
    8
    ## General
    Please help me fix this bug.
    ## General Notes
    - **help**：Please 后使用动词原形，而不是 helps。
    ## Direction
    调整措辞
    ## Alternative
    Please help me resolve this issue.
    ## Alternative Notes
    - **resolve this issue**：调整措辞，保持原有请求和语气。
    """
}
