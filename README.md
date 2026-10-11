# English Compass

A native macOS cross-app English assistant using SwiftUI/AppKit, Accessibility
and direct HTTPS to Alibaba Cloud Bailian.

Planned improvements: [TODO](TODO.md).

## Run

Requires macOS 14+ and Xcode command-line tools to build.

```bash
cd EnglishCompass
bash Scripts/build-app.sh
bash Scripts/install-app.sh
open "$HOME/Applications/English Compass.app"
```

The installed app needs no Python, MLX, model weights or separate server.
Packaging removes obsolete worker resources from previous installations.

## Model & Privacy

- Fixed model: `qwen3.7-flash`, non-thinking.
- The current input and additional instructions are sent to Bailian (Beijing).
- API keys live in macOS Keychain, never the app bundle or UserDefaults.
- Settings allows saving a new key. Existing keys are retained. Re-signing a
  development build can require renewed Keychain and Accessibility approval.
- There is no model/provider switch, local fallback, model download or runtime
  installer. There is no automatic application-level retry.
- Requests use an ephemeral HTTPS session without disk cache or cookies.
  Redirects cannot forward the draft or credential to another endpoint.
- Cancellation reaches the native network task; stale results cannot replace
  text. A request has a 120-second resource deadline.
- Malformed, truncated and tool-call results fail closed. Blank optional
  explanations are ignored; candidates are never silently repaired.
- Input is limited to 16,000 Unicode code points; output to 2,048 tokens for
  writing and 512 tokens for translation.
- Drafts and output history are not saved locally. Logs contain controlled
  lifecycle events and optional timing/length metadata only.

The authorized setup command `--configure-cloud` reads a key from stdin and
saves it in Keychain. Never put the key in command-line arguments. The GUI
does not source shell startup files.

## Actions

Writing shows three ordered versions: general, conversational and academic.
Each has a brief explanation and Copy button, followed by an overall explanation.
Use Up/Down to select and Return to copy while viewing writing results. Input
editing keeps normal native keyboard behavior. Emphasis is display-only: copying
or replacing uses the exact plain-text answer, not explanations or bold markers.
The Changes view is removed. Model and elapsed time remain in the footer.

| Action | Shortcut | Behavior |
|---|---|---|
| Write in English | Control + Option + E | Correct English, translate Chinese, complete mixed-language text |
| Understand English | Control + Option + C | Translate an explicit English selection to Chinese; copy-only |

Manual paste is available from the menu. The app snapshots the original
app/window/control and exact UTF-16 draft before showing its panel. Explicit
replacement revalidates that snapshot, protected tokens and Markdown structure.
It never presses Enter, submits a message or reads terminal history.

Settings retains shortcuts, additional instructions, launch at login and diagnostics.
Additional instructions apply to both writing and translation, within the fixed
task and safety rules. They are saved on this Mac; never enter secrets here.
Old protected-term lists are migrated into an instruction to retain those terms.

The API key is read from Keychain on the first valid request and reused in
process memory until the app exits. Saving a replacement key refreshes the
memory copy after the Keychain save succeeds. Cancelling a translation does not
trigger another Keychain read; failed Keychain reads are not cached.
Old provider/thinking preferences are removed without resetting these values.

## Validation

```bash
swift test
"$HOME/Applications/English Compass.app/Contents/MacOS/EnglishCompass" --ui-test --self-test
"$HOME/Applications/English Compass.app/Contents/MacOS/EnglishCompass" --cloud-smoke-test
```

The cloud smoke uses synthetic text, native HTTPS and Keychain. A separate
explicit live XCTest can use a temporary `ENGLISHCOMPASS_TEST_KEY`; it does not
prove Keychain access. Normal tests skip that live test when no key is supplied.
`--ui-test` is a labelled fixture, not real inference or cross-app E2E evidence.
See `docs/VALIDATION.md` for current evidence and remaining acceptance blockers.
