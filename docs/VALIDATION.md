# Native-Only Validation: 2026-10-11

## Single-Answer Compatibility and Compact Layout

Writing accepts a single final plain-text answer, a candidates-only JSON object,
or a single structured answer with optional explanation/summary/emphasis. Answer
text stays exact. Malformed JSON, empty answers, unexpected keys/types, reasoning,
length-truncated completions and tool calls are not promoted to usable text.
Existing three-answer validation and translation contracts remain unchanged.

Cards use 15-point answers, 10-point padding and inline small Copy buttons; gaps
are 8 points. Result content height is 500 points for multiple answers and 300
for one answer, with scrolling for longer content. Single answers use a neutral
label rather than claiming a style the provider did not return.
57 tests discovered: 56 passed, one optional live test skipped. Fixture previews
include both compact three-answer and single-answer states.

## Three Writing Versions

Writing now returns general, conversational and academic answers in fixed order,
one concise Chinese explanation each, and a two-to-three sentence overall summary.
Separate exact-substring highlights render bold without altering copied text.
The selected answer still passes existing writeback safety checks. Changes UI is
removed; translation retains faithful meaning selection and now shows explanations.

Native fixture testing verified Down/Up navigation and Return-to-copy, including
the conversational and academic selections. Editing shortcuts remain scoped to
native input fields. Result panels expand after the published phase is assigned,
avoiding a synchronous resize that previously left a stale loading view.

Live Bailian smoke passed for three-version writing and faithful translation
(4.48 seconds combined for the two synthetic requests, not a benchmark).
The prompt explicitly requires empty explanation arrays when unnecessary.
Single-phrase highlight arrays may be safely normalized from strings; all terms
are validated against exact answer substrings. No real draft or credential logged.
Automated coverage includes contract rejection, highlight normalization, selection
bounds and exact plain-text clipboard output. Full suite: 53 discovered, 52 passed,
one optional live test skipped; that live test passed separately with an explicitly
supplied shell credential. Installed release is ad-hoc signed;
macOS may ask for Accessibility/Keychain reauthorization after an update.

## Standard Editing Commands

Installed an AppKit application Edit menu with nil-target responder routing for
Command-V/C/X/A and Command-Z/Shift-Z. The previous app had only a status-item
menu, so standard editor commands were not routed. Live fixture interaction
verified Command-A selection, native paste replacing selection, and Command-Z
restoring the prior text. No model request or source-app submission occurred.
Tests cover exact key equivalents, selectors and native paste-action support;
the XCTest runner does not provide a running app keyboard event loop.

## Native Placeholder Alignment Fix

Replaced independent SwiftUI placeholder overlays with a shared NSTextView
editor. Placeholder glyphs use the same font, text-container padding, inset and
TextKit layout origin as entered text. Both the assistant and Instructions
settings use this component. The placeholder never enters the text binding.
46 tests discovered: 45 passed, one optional live test skipped. Geometry tests
cover 13/15-point fonts and narrow/wide containers. The installed fixture panel
was focused and the literal placeholder was typed: caret, placeholder and typed
text visually share the first-line baseline. No real provider request was made.

## Result Panel Simplification

Input/result editors take priority. Removed the large serif title, source and
online badges, repetitive provider/privacy instructions and always-visible diff.
Changes are optional disclosure content; request failures and writeback safety
warnings remain visible. Model and elapsed time appear only as footer metadata.
Timing resets on cancellation/new sessions and freezes on success or failure.
44 tests discovered: 43 passed and one optional live test skipped.
The artifacts/result-redesign-previews directory contains fixture-only visual
states, not real model or cross-app acceptance evidence.

## Settings Redesign

Replaced the tall grouped form with a compact 820 x 620 native settings window:
Shortcuts, Model & API, Instructions and Privacy & access. Navigation retains
the existing preferences instance; changing pages does not write credentials.
Uses semantic macOS surfaces, a restrained teal accent, visible field borders,
selected navigation accessibility traits and labelled controls.
All four pages inspected in the running app. No credentials or permissions
were changed during visual inspection. Offscreen fixture previews remain
visual evidence only, not cross-app or live-inference acceptance.

## Credential Cache Update

Inference reads Keychain lazily on the first valid request and retains the key
only in process memory. Successful Settings saves update the active service's
cache and cancel any request using the old key. Failed Keychain reads are not
cached; ordinary cancellation and provider errors do not reread Keychain.
43 tests discovered: 42 passed, optional live test skipped. Stub tests verify
read-once behavior across both actions, replacement-key headers and failed-read
recovery. Real Keychain dialog behavior still requires manual confirmation.

## Additional Instructions Update

Protected terms UI was replaced with a free-form additional-instructions field.
Both actions append these preferences to the system prompt, subordinate to the
task, preservation rules and JSON contract. Old lists migrate once into a normal
instruction; subsequent edits persist under `additionalInstructions`.
Intrinsic writeback safety checks remain. The deterministic suite passed
(40 passed, one optional live test skipped); no new live provider or cross-app
acceptance is claimed for this update. Evidence below describes the preceding
native-only release unless stated otherwise.

## Goal & Scope

The user explicitly retired local inference. The app now uses native Swift HTTPS
with fixed `qwen3.7-flash` and non-thinking. There are no provider/mode choices,
Python workers, runtime installers, MLX dependencies or model-management menus.

Keychain credentials, protected terms, shortcut settings, input snapshots and
safe writeback are retained. Only retired provider/thinking preference keys were
removed. Historical synthetic model-comparison artifacts remain as evidence,
not executable local-model functionality.

## Verified

| Gate | Evidence |
|---|---|
| Swift compilation and release bundle | Passed |
| Deterministic regressions | 40 passed; optional live test skipped in the normal 41-test suite |
| Native live HTTPS | Explicit live test passed separately: grammar and translation requests, about 1.33 seconds combined |
| Native cancellation | URLProtocol transport stop verified for explicit cancellation, parent-task cancellation and oversized response |
| Response safety | 128 KB maximum; wrong model, truncation, malformed JSON and tool calls fail closed; redirects rejected |
| Session safety | Queued/stale results cannot apply after cancellation; failures do not retry or replace drafts |
| Preference migration | Only obsolete mode/provider keys removed; terms and shortcuts retained |
| Independent reviews | Two reviewers passed after response bounding and pre-Keychain input validation fixes |
| Installed payload | Only executable, Info.plist and signing manifest; approximately 824 KiB, no Python resources |
| Installed signing | Strict verification passed after fixture execution |
| Exclusive storage cleanup | App-owned model (~5.6 GiB) and runtime (~340 MiB) removed; support directory now 0 B |
| Live Settings | Cloud-only model/key/shortcuts/terms/privacy; no download/unload/provider/mode controls |
| Fixture lifecycle/logs | Session smoke passed; controlled event names and metadata only, no raw inputs or credentials |

The explicit native live test injects an authorized temporary test credential.
It exercises the real native networking/contract code but **does not prove
post-signing Keychain authorization**. The production GUI reads only Keychain,
never the shell environment or startup scripts.

## Remaining Acceptance Gates

- The new ad-hoc signature requires renewed Accessibility approval; live
  cross-app read/write acceptance is not complete.
- The saved Keychain item is retained. Authorization to decrypt it after the
  signing change still needs human confirmation. No OS security prompt was
  bypassed or automatically approved.
- Required Marionette E2E remains unsupported: this native Swift app has no
  Flutter VM service. The native tests/screenshots are not labelled as a
  Marionette substitute.
- No notarized/distribution build is claimed.

## Artifacts

- `artifacts/logs/native-only-swift-tests-2026-10-11.txt`
- `artifacts/logs/native-only-live-smoke-2026-10-11.txt`
- `artifacts/logs/native-only-build-2026-10-11.txt`
- `artifacts/logs/native-only-install-2026-10-11.txt`
- `artifacts/logs/native-only-session-fixture-2026-10-11.txt`
- `artifacts/native-only-previews/*-fixture.png`: explicitly offscreen fixture
  renders, not live model/AX proof.

Cleanup was restricted to `~/Library/Application Support/EnglishCompass/`
model/runtime directories and this app's obsolete bundled worker resources.
Shared Python installations, uv/Hugging Face caches and other projects were
not targets. This intentionally leaves any shared cache residue alone.
