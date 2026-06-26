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
    /// at launch by `EchoelCrashLog.begin()`. Read once; plain string.
    private let priorLog = EchoelCrashLog.previousSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Echoel started in Safe Mode")
                        .font(EchoelTheme.font(20, .semibold))
                        .foregroundStyle(EchoelTheme.text)

                    Text("The last launch ran into a problem before the studio finished loading. To keep you out of a black screen, Echoel opened this recovery screen instead. Your projects and settings are untouched.")
                        .font(EchoelTheme.font(13))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onContinue) {
                        Text("Continue to Echoel")
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
                        Text(priorLog)
                            .font(.system(size: 11, design: .monospaced))
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
