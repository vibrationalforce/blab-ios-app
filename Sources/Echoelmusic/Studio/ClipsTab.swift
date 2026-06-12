#if canImport(SwiftUI)
import SwiftUI

// ClipsTab.swift
// Echoel — the Clips tab hosts two views of the same material, Ableton-style:
// SESSION (the launchable clip grid) and ARRANGE (the linear song timeline).
// A segmented toggle switches between them, so the song-mode surface lands
// without spending a 6th iPhone tab slot (the TabView limit before "More…").

@MainActor
struct ClipsTab: View {

    enum Mode: String, CaseIterable, Identifiable {
        case session = "Session"
        case arrange = "Arrange"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .session

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(EchoelTheme.bg)

            switch mode {
            case .session: ClipView()
            case .arrange: ArrangementView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoelTheme.bg)
    }
}
#endif
