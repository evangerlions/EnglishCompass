import Foundation

enum WritingPrompt {
    static func instruction(language: WritingLanguage) -> String {
        let template = "Rewrite or translate the input into exactly two faithful {targetLanguage} versions: a general version and an alternative with a useful improvement strategy you choose for this input. " +
                "The target language of BOTH answer bodies is always {targetLanguage}, regardless of the input language. For input in another language or mixed-language input, translate its meaning into {targetLanguage}; never merely polish it in the source language. Direction, Notes and Summary remain in Chinese regardless of the target language. " +
                "The general version is natural and neutral with minimal necessary corrections. Choose the alternative strategy freely based on the text and likely context, without a predefined style category or forced differences. " +
                "Both versions must preserve the original meaning, speech act, tone strength and degree of commitment; do not turn a statement into a question or add information. " +
                "Keep the general version unchanged only if the input is already correct {targetLanguage}. Input in other languages must still be translated into {targetLanguage} even when correct in its source language. Style differences must not change meaning. " +
                "Return only Markdown using exactly these five level-2 headings in order: ## General, ## Direction, ## Alternative, ## Notes, ## Summary. " +
                "Under ## General and ## Alternative write only the corresponding {targetLanguage} answer, with no extra headings or commentary. " +
                "Under ## Direction return a separate metadata field: one short plain-text Chinese label (prefer 2 to 12 characters, maximum 40) describing the actual improvement strategy of the alternative. Choose the label freely, not from a fixed list; no prefix, explanation or Markdown. It becomes the second card title, never part of its answer. " +
                "In each answer, mark key changes relative to the original input using these fixed meanings: use **bold** only for corrections of errors such as grammar, spelling, tense or prepositions; use *italics* only for expression improvements where the original wording is valid but the revision is more natural, conversational or formal. " +
                "If a changed phrase both corrects an error and improves expression, use bold only, not combined bold and italics. Do not label stylistic preferences or translation choices as errors. " +
                "English example illustrating emphasis only (always use the selected target language for actual answers): input 'Please helps me fix this bug.'; General: 'Please **help** me fix this bug.'; Alternative: 'Please **help** me *resolve this issue*.' Here **help** corrects grammar, while *resolve this issue* improves expression. " +
                "Leave unchanged wording unmarked; do not invent edits or emphasis. When translating or rewriting most of a sentence, mark only a few key expressions, never the entire answer. " +
                "These inline emphasis markers are display aids and may be added without changing the answer's wording or layout; never insert them inside protected code, identifiers, paths, URLs or email addresses. " +
                "Respect the input's layout in every version: keep its paragraphs, lists and intended line breaks, such as numbered steps on separate lines, instead of collapsing them into one paragraph. " +
                "The input's line breaks may be imperfect, so you may join a sentence that is clearly broken by accident, or start a new line where a list item obviously begins. " +
                "This layout guidance refines the line-break preservation rule below. " +
                "Under ## Notes write exactly two Chinese bullet items in the same order, one brief explanation per version, without prefixing the version name. " +
                "Under ## Summary write two or three concise Chinese sentences about corrections, key expressions and usage differences. " +
                "Do not use JSON or fenced code blocks. Do not repeat the answers in Notes or Summary. No follow-up question or praise."
        return template.replacingOccurrences(of: "{targetLanguage}", with: language.name)
    }

    static func languageRequirement(_ language: WritingLanguage) -> String {
        " Output-language requirement: General and Alternative MUST contain \(language.name) answers. " +
        "写作模式的目标语言是\(language.chineseName)，必须把其他语言翻译成\(language.chineseName)，不能只润色原文。" +
        "Direction、Notes、Summary 使用中文。Example: input 我叫林晨，你好 → General: \(language.example) " +
        "Alternative must also be in \(language.name); choose its improvement strategy freely. "
    }
}
