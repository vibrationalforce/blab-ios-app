#if canImport(AppIntents)
import AppIntents
import Foundation

/// Siri / Shortcuts / Spotlight entry points. The App Intents framework is iOS
/// 16+, comfortably under the app's iOS 18 floor, so no availability gating is
/// needed. Each intent opens the app and deposits a request in a shared App-Group
/// inbox; `EchoelStudioView` consumes it when it next becomes active and routes
/// it to the exact same handler the on-screen button uses (start/stop/keep loop).
/// Intents stay deliberately thin — they don't touch the audio engine directly,
/// so there is no cross-process audio-thread or actor-isolation hazard.

/// The action a Siri/Shortcuts request asks the app to perform.
enum EchoelIntentAction: String {
    case start
    case stop
    case keepLoop
}

/// Tiny cross-process mailbox in the shared App Group. The intent (which may run
/// out of process) posts; the app takes (read-once) on activation.
enum EchoelIntentInbox {
    private static let key = "pendingIntentAction"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroupStore.appGroupID) }

    static func post(_ action: EchoelIntentAction) {
        defaults?.set(action.rawValue, forKey: key)
    }

    /// Read and clear the pending action (so it fires exactly once).
    static func take() -> EchoelIntentAction? {
        guard let d = defaults, let raw = d.string(forKey: key) else { return nil }
        d.removeObject(forKey: key)
        return EchoelIntentAction(rawValue: raw)
    }
}

struct StartEchoelSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Echoelmusic Session"
    static let description = IntentDescription(
        "Start a bio-reactive session — your body begins making music.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        EchoelIntentInbox.post(.start)
        return .result()
    }
}

struct StopEchoelSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Echoelmusic Session"
    static let description = IntentDescription("Stop the current bio-reactive session.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        EchoelIntentInbox.post(.stop)
        return .result()
    }
}

struct KeepLastLoopIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Last Loop"
    static let description = IntentDescription(
        "Capture the loop you just played from the always-on buffer.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        EchoelIntentInbox.post(.keepLoop)
        return .result()
    }
}

/// Surfaces the intents to Siri, Spotlight and the Shortcuts app with spoken
/// phrases. `\(.applicationName)` resolves to the app's display name.
struct EchoelAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartEchoelSessionIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Begin a session in \(.applicationName)",
                "Make music with my body in \(.applicationName)"
            ],
            shortTitle: "Start Session",
            systemImageName: "waveform.path.ecg")
        AppShortcut(
            intent: StopEchoelSessionIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "End my \(.applicationName) session"
            ],
            shortTitle: "Stop Session",
            systemImageName: "stop.circle.fill")
        AppShortcut(
            intent: KeepLastLoopIntent(),
            phrases: [
                "Keep the last loop in \(.applicationName)",
                "Save that loop in \(.applicationName)"
            ],
            shortTitle: "Keep Last Loop",
            systemImageName: "scissors")
    }
}
#endif
