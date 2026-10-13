import AVFoundation
import Combine
import SwiftUI

/// On-device English speech. Nothing is uploaded; voices come from macOS.
@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    /// The text currently being spoken, or nil when idle.
    @Published private(set) var speakingText: String?
    /// Bumped when macOS installs or removes a voice, so voice lists re-read.
    @Published private(set) var voicesRevision = 0
    private let synthesizer = AVSpeechSynthesizer()
    private let preferences: Preferences
    private var voicesObserver: NSObjectProtocol?

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
        synthesizer.delegate = self
        // Voices downloaded while the app is running (e.g. Zoe Premium) only
        // appear after this notification; without it the list stays stale.
        voicesObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.voicesRevision += 1 }
        }
    }

    deinit {
        if let voicesObserver { NotificationCenter.default.removeObserver(voicesObserver) }
    }

    /// Manual fallback for the voice-change notification: re-reads the list.
    func refreshVoices() { voicesRevision += 1 }

    var isSpeaking: Bool { speakingText != nil }

    /// English voices for an accent, best quality first (Premium, Enhanced, Default).
    /// Novelty voices (Bells, Bubbles, Zarvox…) are excluded.
    static func voices(for accent: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == accent && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { lhs, rhs in
                lhs.quality.rawValue != rhs.quality.rawValue
                    ? lhs.quality.rawValue > rhs.quality.rawValue
                    : lhs.name < rhs.name
            }
    }

    static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Default"
        }
    }

    /// macOS already appends the quality to some names, e.g. "Zoe (Premium)";
    /// strip that so the label does not read "Zoe (Premium) · Premium".
    static func displayName(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality = qualityLabel(voice)
        let name = voice.name.replacingOccurrences(of: " (\(quality))", with: "")
        return "\(name) · \(quality)"
    }

    /// The saved voice if it is still installed, otherwise the best one for the accent.
    func resolvedVoice() -> AVSpeechSynthesisVoice? {
        if !preferences.speechVoice.isEmpty,
           let saved = AVSpeechSynthesisVoice(identifier: preferences.speechVoice),
           saved.language == preferences.speechAccent {
            return saved
        }
        return Self.voices(for: preferences.speechAccent).first
            ?? AVSpeechSynthesisVoice(language: preferences.speechAccent)
    }

    /// Speaks the text. Calling again with the same text while it plays stops it.
    func toggle(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if speakingText == clean { stop(); return }
        speak(clean)
    }

    func speak(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = resolvedVoice()
        utterance.rate = preferences.speechRate
        speakingText = clean
        synthesizer.speak(utterance)
        Diagnostics.event("speech_started")
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        speakingText = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        Task { @MainActor in if self.speakingText == text { self.speakingText = nil } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        Task { @MainActor in if self.speakingText == text { self.speakingText = nil } }
    }
}

/// Plays a sample sentence with the current voice settings.
struct SpeechPreviewButton: View {
    @ObservedObject var speech: SpeechService
    static let sample = "Could you help me sort out this bug before the release?"

    var body: some View {
        let playing = speech.speakingText == Self.sample
        Button { speech.toggle(Self.sample) } label: {
            Label(playing ? "Stop" : "Preview", systemImage: playing ? "stop.fill" : "play.fill")
        }
        .controlSize(.small)
        .accessibilityIdentifier("speech_preview")
    }
}

/// Speaker toggle shown next to an English sentence.
struct SpeakButton: View {
    @ObservedObject var speech: SpeechService
    let text: String
    var tint: Color = .secondary

    var body: some View {
        let playing = speech.speakingText == text.trimmingCharacters(in: .whitespacesAndNewlines)
        Button { speech.toggle(text) } label: {
            Image(systemName: playing ? "stop.circle.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(playing ? tint : Color.secondary)
                .symbolEffect(.variableColor.iterative, isActive: playing)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(playing ? "Stop" : "Read aloud")
        .accessibilityLabel(playing ? "Stop reading" : "Read aloud")
    }
}
