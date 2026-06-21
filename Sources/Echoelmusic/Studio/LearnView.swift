#if canImport(SwiftUI)
import SwiftUI

// LearnView.swift
// Echoel — the "app as a school" surface. Browses the unified LearnLibrary
// (Your Body · Music Theory · Light & Colour · Safety & Scope) — one list bound
// to ONE source. Finally wires the built-but-unsurfaced LearnLibrary. Pure
// presentation; all copy + science live in the tested content models.

@MainActor
struct LearnView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var selected: LearnEntry?
    var embedded = false

    var body: some View {
        if embedded {
            list
        } else {
            NavigationStack {
                list
                    .navigationTitle("Learn")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(LearnSection.allCases) { section in
                    let entries = LearnLibrary.entries(for: section)
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(EchoelTheme.font(13, .semibold))
                                .foregroundStyle(EchoelTheme.dim)
                            ForEach(entries) { entry in row(entry) }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(EchoelTheme.bg)
        .sheet(item: $selected) { entryDetail($0) }
    }

    private func row(_ entry: LearnEntry) -> some View {
        Button { selected = entry } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).font(EchoelTheme.font(14)).foregroundStyle(EchoelTheme.text)
                        .lineLimit(1)
                    Text(entry.summary).font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Learn what this means")
    }

    private func entryDetail(_ entry: LearnEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title).font(EchoelTheme.font(20, .semibold)).foregroundStyle(EchoelTheme.text)
                    Spacer(minLength: 0)
                    Button("Done") { selected = nil }
                        .font(EchoelTheme.font(15)).foregroundStyle(EchoelTheme.accent)
                }
                Text(entry.summary).font(EchoelTheme.font(14)).foregroundStyle(EchoelTheme.dim)
                Divider().overlay(EchoelTheme.border)
                Text(entry.detail).font(EchoelTheme.font(15)).foregroundStyle(EchoelTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .background(EchoelTheme.bg)
        .presentationDetents([.medium, .large])
    }
}
#endif
