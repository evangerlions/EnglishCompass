import Foundation

enum WritingPrompt {
    static func instruction(language: WritingLanguage) -> String {
        let template = "Assess the original input and return one faithful {targetLanguage} general version, with a second alternative only when you judge it genuinely useful. " +
            "The target language of all returned answer bodies is always {targetLanguage}, regardless of the input language. For input in another language or mixed-language input, translate its meaning into {targetLanguage}; never merely polish it in the source language. Direction and each version's explanation remain in Chinese regardless of the target language. " +
            "First score the ORIGINAL input, not your revised answer, with an integer from 0 to 10 based on grammar, naturalness and clarity for its intended use in {targetLanguage}. 0–3 means substantial problems, 4–6 understandable but needs clear correction, 7–8 mostly good with useful improvements, 9 very good with a small worthwhile change, and 10 means no modification is needed. Do not invent problems just to lower the score. " +
            "For a score of 10, return the original input unchanged under ## General, briefly explain that no modification is needed under ## General Notes, and omit the entire second group. Keep the general version unchanged only if the input is already correct {targetLanguage}. Input in other languages must still be translated into {targetLanguage} even when correct in its source language, so do not give 10 when translation is needed. " +
            "The general version is natural and neutral with minimal necessary corrections. Generate an alternative only if it offers a distinct, meaningful benefit, not a trivial synonym swap or a forced difference. A score below 10 does not require an alternative. Choose its improvement strategy freely based on the text and likely context, without a predefined style category. " +
            "All returned versions must preserve the original meaning, speech act, tone strength and degree of commitment; do not turn a statement into a question or add information. Style differences must not change meaning. " +
            "Start with ## Score containing only the integer, then ## General and ## General Notes. If a second version is useful, append ## Direction, ## Alternative and ## Alternative Notes in that order; otherwise omit all three optional sections, with no empty headings or placeholder text. " +
            "Finish the first answer AND its own explanation before starting the second answer. Under ## General and ## Alternative write only the corresponding {targetLanguage} answer as plain text. " +
            "Do not add bold, italics, diff markers or other highlighting to the answer bodies. The client computes all differences from the original input; you must not compute or describe text offsets. Preserve literal formatting already present in the input. " +
            "Under ## General Notes explain only the first answer; under ## Alternative Notes explain only the second answer. Each explanation should be brief Chinese Markdown: one to three useful bullet points or a short paragraph about key changes, expressions and usage. No separate overall Notes or Summary section. " +
            "Under ## Direction return one short plain-text Chinese label (prefer 2 to 12 characters, maximum 40) describing the actual improvement strategy of the alternative. Choose the label freely, not from a fixed list; no prefix, explanation or Markdown. It becomes the second group title, never part of its answer. " +
            "Respect the input's layout in every version: keep its paragraphs, lists and intended line breaks, such as numbered steps on separate lines, instead of collapsing them into one paragraph. " +
            "The input's line breaks may be imperfect, so you may join a sentence that is clearly broken by accident, or start a new line where a list item obviously begins. This layout guidance refines the line-break preservation rule below. " +
            "Do not repeat the full answers in explanations. Do not use JSON or add fenced code blocks. No follow-up question or praise."
        return template.replacingOccurrences(of: "{targetLanguage}", with: language.name)
    }

    static func languageRequirement(_ language: WritingLanguage) -> String {
        " Output-language requirement: General and any returned Alternative MUST contain \(language.name) answers. " +
        "写作模式的目标语言是\(language.chineseName)，必须把其他语言翻译成\(language.chineseName)，不能只润色原文。" +
        "Direction、General Notes、Alternative Notes 使用中文。Example: input 我叫林晨，你好 → General: \(language.example) " +
        "If an Alternative is useful, it must also be in \(language.name); choose its improvement strategy freely. "
    }
}
