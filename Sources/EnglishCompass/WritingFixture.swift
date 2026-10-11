import AssistantCore

/// Synthetic only; used by preview rendering and explicit --ui-test launches.
enum WritingFixture {
    static let result = ModelResult(
        candidates: ["Please help me fix this bug.", "Could you help me sort out this bug?",
                     "Please assist me in resolving this software defect."],
        explanations: ["通用表达，简洁自然，适合大多数协作场景。", "语气更轻松、委婉，适合同事之间的日常沟通。",
                       "措辞更正式，适合技术报告或正式沟通。"],
        summary: "Please 后使用动词原形 help，而不是 helps。三个版本保留同一个请求，仅调整语气和用词；正式表达不一定比日常表达更合适。",
        highlights: [["help"], ["sort out"], ["resolving", "software defect"]])
}
