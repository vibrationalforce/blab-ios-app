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

    /// E4: opt-in news/event push (CloudKit, serverless, no account). Lives
    /// here because Learn is the one always-reachable info surface — never
    /// requested at first launch.
    #if canImport(CloudKit) && canImport(UserNotifications)
    @Environment(AnnouncementCenter.self) private var announcements
    #endif

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
                #if canImport(CloudKit) && canImport(UserNotifications)
                announcementsSection
                #endif
            }
            .padding(16)
        }
        .background(EchoelTheme.bg)
        .sheet(item: $selected) { entryDetail($0) }
    }

    #if canImport(CloudKit) && canImport(UserNotifications)
    /// Opt-in broadcast push for new features and live events. Serverless
    /// (CloudKit public DB), no account, default OFF — honest status below.
    private var announcementsSection: some View {
        @Bindable var announcements = announcements
        return VStack(alignment: .leading, spacing: 8) {
            Text("Stay in the loop")
                .font(EchoelTheme.font(13, .semibold))
                .foregroundStyle(EchoelTheme.dim)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $announcements.enabled) {
                    Text("News & live events")
                        .font(EchoelTheme.font(14)).foregroundStyle(EchoelTheme.text)
                }
                .tint(EchoelTheme.accent)
                .accessibilityHint("A push notification when a new feature ships or a live event starts. No account, nothing tracked; turn off anytime.")
                Text(statusLine)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
    }

    private var statusLine: String {
        switch announcements.status {
        case "denied": return "Notifications are off for Echoel in Settings."
        case "error": return "Couldn't subscribe — check that iCloud is signed in, then toggle again."
        case "on": return "You'll hear about new features and live events. Nothing else, ever."
        default: return "Off by default. When on, one push per announcement — no account, nothing tracked."
        }
    }
    #endif

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
