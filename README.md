# English Compass

A native macOS cross-app English assistant using SwiftUI/AppKit, Accessibility
and direct HTTPS to Alibaba Cloud Bailian.

Planned improvements: [TODO](TODO.md).
GitHub tests and locally signed releases: [GitHub Build](docs/GITHUB_BUILD.md).

## Run

### Drag-to-Install DMG

After building, run `bash Scripts/package-dmg.sh /absolute/path/EnglishCompass.dmg`.
Requires `uv`; the script uses pinned `dmgbuild` to write Finder layout metadata
without GUI automation. The installer has a fixed window, real draggable icons,
an arrow and installation instructions. `SIGNING_IDENTITY` selects an existing
Keychain signing identity; default is ad-hoc. `APPLICATIONS_TARGET` optionally
selects a user-local Applications folder. Packaging does not export certificates
or upload anything. Signing with Apple Development does not provide notarization.

### Local Build

Requires macOS 14+ and Xcode command-line tools to build.

```bash
cd EnglishCompass
bash Scripts/build-app.sh
bash Scripts/install-app.sh
open "$HOME/Applications/English Compass.app"
```

The app appears in Dock and Command-Tab while running. Clicking its Dock icon
brings the existing assistant window forward without resetting input, answers,
or follow-up questions. Switching apps does not hide the window; close it with ×.

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
If writing returns only one answer (structured or plain text), it is shown as a
single answer rather than rejected or padded with invented alternatives. Empty,
malformed structured responses, reasoning tags and incomplete/tool-call results
still fail validation. Answer cards use compact spacing with inline Copy controls.

| Action | Shortcut | Behavior |
|---|---|---|
| Write in English | Control + Option + E | Correct English, translate Chinese, complete mixed-language text |
| Understand English | Control + Option + R | Translate an explicit English selection to Chinese; copy-only |
| Read Aloud | Control + Option + S | Speak the selected English with an on-device macOS voice; press again to stop |

Inside the result panel, Space reads the highlighted answer (or the English
source when translating), and each card has a speaker button. Speech runs
entirely on this Mac; nothing extra is uploaded. Settings → Shortcuts chooses
American or British English, the voice and the speed. Premium or Enhanced
voices downloaded in System Settings → Accessibility → Spoken Content sound
noticeably more natural.

Manual paste is available from the menu. The app snapshots the original
app/window/control and exact UTF-16 draft before showing its panel. Explicit
replacement revalidates that snapshot and protected tokens (code, links, paths,
numbers and negation). Line breaks may change freely when wording is improved.
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

## Local Lab mode

For prompt and UI work without touching the installed app:

```bash
bash Scripts/run-lab.sh
# or bare-binary mode without bundled icon: swift run EnglishCompass --lab
```

The launcher builds `dist/English Compass Lab.app` with the existing app artwork
and a separate Dock identity. Dock clicks bring the current Lab window forward.
Start with the script so the environment key is loaded; no key is stored in the
bundle. The release installation is not changed by the Lab launcher.

Lab mode opens the production assistant panel itself (same glass, same cards
and the same adaptive height) with only a `LAB` badge added, so UI work looks
exactly like the installed app. A separate inspector window holds the system
prompt, editable Lab-only additional instructions, and the raw request and
response; open it from the magnifying-glass icon or the Debug menu. The File
menu switches between Write and Understand and runs the current request.

It does not register hot keys, show a status item, use Accessibility, or read
Keychain. The API key is read only from the `BAILIAN_API_KEY` environment
variable (export it in `~/.zshrc`), and Lab settings are stored in a separate
`com.zook.EnglishCompass.lab` defaults suite.
