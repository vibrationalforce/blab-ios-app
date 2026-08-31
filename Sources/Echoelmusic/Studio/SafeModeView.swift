//
//  SafeModeView.swift
//  Echoelmusic — Studio
//
//  The self-healing recovery screen. Shown by `EchoelmusicApp` when `LaunchGuard`
//  detects the previous launch(es) crashed before becoming healthy. Instead of a
//  black screen, the user gets a legible explanation, the crash diagnostics ready
//  to share, and a one-tap way back into the full app.
//
//  Deliberately the SIMPLEST possible view tree — `NavigationStack` + `ScrollView`
//  + plain `Text`/`Button` only. NO `Menu`, NO `ForEach` over `@Observable`
//  bindings, NO environment dependencies (it renders BEFORE any engine is injected).
//  This screen must be the one thing that can always render.
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct SafeModeView: View {

    /// Called when the user chooses to relaunch into the full app. The parent
    /// resets `LaunchGuard` and flips its own state to render `mainContent`.
    let onContinue: () -> Void

    /// The previous run's diagnostic log (breadcrumbs + any crash marker), captured
    /// at launch by `EchoelCrashLog.begin()` — plus, since #917, a retained crash from an
    /// EARLIER run when the previous one carries no marker of its own. Both values are read
    /// from memory, never from disk: this screen renders when nothing else can, and it must
    /// not gain a dependency on the file system to do it.
    ///
    /// ⭐ WHY IT NEEDS THE OLDER RUN AT ALL. The run immediately before this one CAN be a
    /// previous recovery launch — short, markerless, useless — and the screen that says
    /// "share this with the developer" was then handing over exactly that.
    ///
    /// ⚠️ NARROWER THAN THE FIRST DRAFT SAID, which claimed the run before a safe-mode launch
    /// simply IS the recovery launch. A SIGSEGV/SIGABRT writes a marker, so straight after one
    /// the composition declines and the screen already showed the right run. What #917 catches
    /// is a recovery launch that ends WITHOUT a marker — force-quit from this screen instead
    /// of tapping Continue (so `LaunchGuard.reset()` never runs and the streak holds), or a
    /// watchdog/jetsam kill. The exception, not the rule; stated so nobody plans from the rule.
    ///
    /// ⚠️ AND IT MAKES THIS SCREEN LONGER. The `Text` below has no `lineLimit`, and
    /// `ShareLink` carries the same string; a composed text can now add up to
    /// `EchoelCrashLog.retainedCrashCharacterBudget` characters on top of the previous run.
    /// The view tree is unchanged — still no `Menu`, no `ForEach`, no environment — but the
    /// growth is real and is recorded here as well as at `EchoelCrashLog.lastCrashLog()`.
    private let priorLog = EchoelCrashLog.recoveryExport()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Echoelmusic started in Safe Mode")
                        .font(EchoelTheme.font(20, .semibold))
                        .foregroundStyle(EchoelTheme.text)

                    Text("The last launch ran into a problem before the studio finished loading. To keep you out of a black screen, Echoelmusic opened this recovery screen instead. Your projects and settings are untouched.")
                        .font(EchoelTheme.font(13))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onContinue) {
                        Text("Continue to Echoelmusic")
                            .font(EchoelTheme.font(15, .semibold))
                            .foregroundStyle(EchoelTheme.onPrimary)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Relaunch the full app")

                    if !priorLog.isEmpty {
                        Divider().overlay(EchoelTheme.border)
                        Text("What happened (diagnostics)")
                            .font(EchoelTheme.font(13, .semibold))
                            .foregroundStyle(EchoelTheme.text)
                        Text("If this keeps happening, share this with the developer — it pinpoints the cause.")
                            .font(EchoelTheme.font(11))
                            .foregroundStyle(EchoelTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        ShareLink(item: priorLog) {
                            Text("Share diagnostics")
                                .font(EchoelTheme.font(13, .semibold))
                                .foregroundStyle(EchoelTheme.text)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                        }
                        // ⭐ THE TEXT-STYLE OVERLOAD, NOT THE BRAND HELPER — #353d. Every other
                        // string on this screen already scales (`EchoelTheme.font` is
                        // `.custom(…, relativeTo: .body)`); this one did not, because
                        // `.system(size: 11, …)` is an absolute point size that ignores Dynamic
                        // Type entirely. The user who most needs to read a recovery screen read
                        // its diagnostics at 11 pt whatever they had asked for.
                        //
                        // ⚠️ IT DOES NOT MOVE TO `EchoelTheme.font`, and that is the whole
                        // judgement: the brand face is proportional, and a log loses its column
                        // alignment the moment it stops being monospaced. `Font.system(_:design:)`
                        // takes a TEXT STYLE instead of a size — same monospaced family, but sized
                        // by the user's setting. `.caption2` is 11 pt at the default size, so this
                        // renders identically for anyone who has changed nothing.
                        //
                        // Deliberately UNCAPPED: no `dynamicTypeSize` ceiling. The #262 chrome cap
                        // exists so a toolbar cannot eat the canvas; this is content inside a
                        // `ScrollView` with nothing below it to crowd, and there is no `lineLimit`
                        // anywhere in this tree, so long log lines wrap instead of truncating.
                        Text(priorLog)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(EchoelTheme.dim)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    }
                }
                .padding(20)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Recovery")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
#endif
