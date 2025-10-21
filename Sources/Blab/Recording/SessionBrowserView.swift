import SwiftUI

/// Session browser and manager for loading/organizing recording sessions
struct SessionBrowserView: View {
    @EnvironmentObject var recordingEngine: RecordingEngine
    @Environment(\.dismiss) var dismiss

    @State private var sessions: [SessionInfo] = []
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dateDescending
    @State private var showDeleteConfirmation = false
    @State private var sessionToDelete: UUID?

    enum SortOrder: String, CaseIterable {
        case dateAscending = "Date (Oldest First)"
        case dateDescending = "Date (Newest First)"
        case nameAscending = "Name (A-Z)"
        case nameDescending = "Name (Z-A)"
        case durationAscending = "Duration (Shortest)"
        case durationDescending = "Duration (Longest)"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Sort picker
                sortPicker

                // Session list
                if filteredSessions.isEmpty {
                    emptyStateView
                } else {
                    sessionList
                }
            }
            .background(Color.black.opacity(0.9))
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSessions()
            }
            .alert("Delete Session", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let sessionID = sessionToDelete {
                        deleteSession(sessionID)
                    }
                }
            } message: {
                Text("Are you sure you want to delete this session? This action cannot be undone.")
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.5))

            TextField("Search sessions...", text: $searchText)
                .foregroundColor(.white)
                .autocapitalization(.none)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.1))
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Sort Picker

    private var sortPicker: some View {
        Picker("Sort", selection: $sortOrder) {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Text(order.rawValue).tag(order)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredSessions) { session in
                    SessionRow(session: session, onLoad: {
                        loadSession(session.id)
                    }, onDelete: {
                        sessionToDelete = session.id
                        showDeleteConfirmation = true
                    })
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text(searchText.isEmpty ? "No Sessions Yet" : "No Results")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            Text(searchText.isEmpty ?
                 "Create your first recording session to get started" :
                 "Try a different search term")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtered & Sorted Sessions

    private var filteredSessions: [SessionInfo] {
        let filtered = searchText.isEmpty ? sessions : sessions.filter { session in
            session.name.localizedCaseInsensitiveContains(searchText) ||
            session.genre.localizedCaseInsensitiveContains(searchText) ||
            session.mood.localizedCaseInsensitiveContains(searchText)
        }

        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .dateAscending:
                return lhs.modifiedAt < rhs.modifiedAt
            case .dateDescending:
                return lhs.modifiedAt > rhs.modifiedAt
            case .nameAscending:
                return lhs.name < rhs.name
            case .nameDescending:
                return lhs.name > rhs.name
            case .durationAscending:
                return lhs.duration < rhs.duration
            case .durationDescending:
                return lhs.duration > rhs.duration
            }
        }
    }

    // MARK: - Actions

    private func loadSessions() {
        // In a real implementation, this would scan the sessions directory
        // For now, create some mock data
        sessions = [
            SessionInfo(
                id: UUID(),
                name: "Morning Meditation",
                duration: 1200,
                trackCount: 3,
                genre: "Meditation",
                mood: "Calm",
                createdAt: Date().addingTimeInterval(-86400 * 7),
                modifiedAt: Date().addingTimeInterval(-86400 * 2)
            ),
            SessionInfo(
                id: UUID(),
                name: "Evening Flow",
                duration: 900,
                trackCount: 2,
                genre: "Healing",
                mood: "Peaceful",
                createdAt: Date().addingTimeInterval(-86400 * 3),
                modifiedAt: Date().addingTimeInterval(-86400)
            ),
            SessionInfo(
                id: UUID(),
                name: "Creative Jam",
                duration: 1800,
                trackCount: 5,
                genre: "Experimental",
                mood: "Inspired",
                createdAt: Date().addingTimeInterval(-86400),
                modifiedAt: Date()
            )
        ]
    }

    private func loadSession(_ id: UUID) {
        do {
            try recordingEngine.loadSession(id: id)
            dismiss()
        } catch {
            print("❌ Failed to load session: \(error)")
        }
    }

    private func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        // In real implementation, delete from disk
        print("🗑️ Deleted session: \(id)")
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: SessionInfo
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onLoad) {
            HStack(spacing: 16) {
                // Session icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(sessionColor.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundColor(sessionColor)
                }

                // Session info
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    HStack(spacing: 12) {
                        Label("\(session.trackCount)", systemImage: "waveform")
                        Label(durationString, systemImage: "clock")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 8) {
                        Text(session.genre)
                            .font(.system(size: 10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.cyan.opacity(0.2)))
                            .foregroundColor(.cyan)

                        Text(session.mood)
                            .font(.system(size: 10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.purple.opacity(0.2)))
                            .foregroundColor(.purple)
                    }
                }

                Spacer()

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundColor(.red.opacity(0.7))
                        .padding(12)
                }
                .buttonStyle(.borderless)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private var sessionColor: Color {
        let colors: [Color] = [.cyan, .purple, .blue, .green, .orange, .pink]
        let hash = session.id.hashValue
        return colors[abs(hash) % colors.count]
    }

    private var durationString: String {
        let minutes = Int(session.duration) / 60
        let seconds = Int(session.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Session Info Model

struct SessionInfo: Identifiable {
    let id: UUID
    var name: String
    var duration: TimeInterval
    var trackCount: Int
    var genre: String
    var mood: String
    var createdAt: Date
    var modifiedAt: Date
}
