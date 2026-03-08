import AppKit

/// Text-to-speech announcements for gate events using macOS NSSpeechSynthesizer.
class GateVoice {
    static let shared = GateVoice()

    private let synthesizer = NSSpeechSynthesizer()
    private(set) var enabled = false

    private init() {}

    /// Configure voice from rules.toml settings.
    func configure(enabled: Bool) {
        self.enabled = enabled
    }

    /// Announce a gate event. No-op if voice is disabled.
    func announce(_ text: String) {
        guard enabled else { return }
        synthesizer.stopSpeaking()
        synthesizer.startSpeaking(text)
    }

    /// Announce a gate approval request.
    func announceGate(ruleName: String, riskLevel: String, command: String) {
        let shortCmd = command.count > 80 ? String(command.prefix(77)) + "..." : command
        announce("Authorization required. \(ruleName). Risk level: \(riskLevel). Command: \(shortCmd)")
    }

    /// Announce a decision.
    func announceDecision(_ decision: String) {
        announce(decision)
    }

    /// Stop any current speech.
    func stop() {
        synthesizer.stopSpeaking()
    }
}
