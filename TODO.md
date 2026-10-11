# TODO

- [ ] Add a proper app icon and stable Developer ID signing/notarization to reduce repeated Accessibility and Keychain authorization after updates.
- [ ] Validate capture and safe replacement in commonly used apps, including browsers, VS Code and chat apps.
- [ ] Test long passages and small screens; improve result sizing, scrolling and keyboard focus where needed.
- [ ] Expand synthetic model checks for meaning preservation, negation, technical terms and the usefulness of the three writing styles.
- [ ] Measure three-answer latency and token usage; tune concise explanations without sacrificing quality.
- [ ] Add CI for Swift tests and document a reproducible release process.

## Current Scope

Native macOS 14+ menu-bar assistant. Qwen3.7 Flash only; API key stays in macOS
Keychain with a process-local cache. Three writing versions with explanations,
plain-text copying and keyboard selection. Faithful Chinese translation.
No local model, automatic submission, draft history or iCloud key sync.
