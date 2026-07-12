//
//  EchoelPanel.swift
//  Echoelmusic — Studio
//
//  The one shared panel vocabulary: a collapsible ("aufklappen"), accessibility-first
//  titled card. A screen becomes one scrollable stack of expandable sections. The
//  Studio sections, the EFX view, and the coming persistent workspace all use THIS,
//  so every panel reads and behaves identically (Echoel CI — black fill, subtle 1px
//  border, small radius, no glow/glassmorphism).
//
//  DMMW shell (founder 2026-07-12: "Alles bleibt im Hauptfenster es gehen nur
//  dropdown Menüs auf"): inside the menu-bar DROPDOWN a panel renders ALWAYS OPEN
//  (plain header, no disclosure chevron) — the dropdown IS the open state, a second
//  collapse level inside it would be noise. The host sets the environment flag once;
//  every panel picks it up, so the whole vocabulary moved into menus with one switch.
//

#if canImport(SwiftUI)
import SwiftUI

/// True inside the menu-bar dropdown host: panels render expanded, without the
/// disclosure chrome. Default false → the classic collapsible card everywhere else.
private struct EchoelPanelForceOpenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var echoelPanelForceOpen: Bool {
        get { self[EchoelPanelForceOpenKey.self] }
        set { self[EchoelPanelForceOpenKey.self] = newValue }
    }
}

@MainActor
struct EchoelPanel<Content: View>: View {
    private let title: String
    private let subtitle: String
    @Binding private var isExpanded: Bool
    @ViewBuilder private let content: () -> Content
    @Environment(\.echoelPanelForceOpen) private var forceOpen

    init(_ title: String, _ subtitle: String = "", isExpanded: Binding<Bool>,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        Group {
            if forceOpen {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: 14) { content() }
                        .padding(.top, 12)
                }
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 14) { content() }
                        .padding(.top, 12)
                } label: {
                    header
                }
            }
        }
        .tint(EchoelTheme.dim)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
            if !subtitle.isEmpty {
                Text(subtitle).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
            }
        }
    }
}
#endif
