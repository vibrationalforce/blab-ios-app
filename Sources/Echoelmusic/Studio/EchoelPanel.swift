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

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct EchoelPanel<Content: View>: View {
    private let title: String
    private let subtitle: String
    @Binding private var isExpanded: Bool
    @ViewBuilder private let content: () -> Content

    init(_ title: String, _ subtitle: String = "", isExpanded: Binding<Bool>,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
                if !subtitle.isEmpty {
                    Text(subtitle).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
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
}
#endif
