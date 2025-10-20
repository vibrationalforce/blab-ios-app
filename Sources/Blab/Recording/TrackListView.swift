import SwiftUI

/// Track list view with individual track controls
struct TrackListView: View {
    @EnvironmentObject var recordingEngine: RecordingEngine
    @Binding var session: Session

    @State private var showDeleteConfirmation = false
    @State private var trackToDelete: UUID?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    if session.tracks.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(session.tracks) { track in
                            TrackRow(track: track)
                                .environmentObject(recordingEngine)
                        }
                    }
                }
                .padding()
            }
            .background(Color.black.opacity(0.9))
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Delete Track", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let trackID = trackToDelete {
                    try? recordingEngine.deleteTrack(trackID)
                }
            }
        } message: {
            Text("Are you sure you want to delete this track? This action cannot be undone.")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text("No Tracks Yet")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            Text("Start recording to create your first track")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/// Individual track row with controls
struct TrackRow: View {
    @EnvironmentObject var recordingEngine: RecordingEngine
    let track: Track

    @State private var showTrackDetails = false

    var body: some View {
        VStack(spacing: 12) {
            // Track header
            HStack(spacing: 12) {
                // Track type icon
                Image(systemName: track.type.icon)
                    .font(.system(size: 18))
                    .foregroundColor(track.type.color)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(track.type.color.opacity(0.2))
                    )

                // Track info
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text(track.type.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))

                        Text("•")
                            .foregroundColor(.white.opacity(0.3))

                        Text(formatDuration(track.duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                // Details button
                Button(action: { showTrackDetails.toggle() }) {
                    Image(systemName: showTrackDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // Waveform preview (if available)
            if let waveformData = track.waveformData {
                waveformView(data: waveformData)
                    .frame(height: 40)
            }

            // Track controls
            trackControlsView

            // Expanded details
            if showTrackDetails {
                trackDetailsView
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Track Controls

    private var trackControlsView: some View {
        HStack(spacing: 16) {
            // Mute button
            Button(action: {
                recordingEngine.setTrackMuted(track.id, muted: !track.isMuted)
            }) {
                Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundColor(track.isMuted ? .red : .white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(track.isMuted ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
                    )
            }

            // Solo button
            Button(action: {
                recordingEngine.setTrackSoloed(track.id, soloed: !track.isSoloed)
            }) {
                Text("S")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(track.isSoloed ? .black : .white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(track.isSoloed ? Color.yellow : Color.white.opacity(0.1))
                    )
            }

            // Volume slider
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))

                Slider(
                    value: Binding(
                        get: { track.volume },
                        set: { recordingEngine.setTrackVolume(track.id, volume: $0) }
                    ),
                    in: 0...1
                )
                .tint(.cyan)

                Text("\(Int(track.volume * 100))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 30)
            }
        }
    }

    // MARK: - Track Details

    private var trackDetailsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.white.opacity(0.2))

            // Pan control
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pan")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    Text(panString(track.pan))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }

                Slider(
                    value: Binding(
                        get: { track.pan },
                        set: { recordingEngine.setTrackPan(track.id, pan: $0) }
                    ),
                    in: -1...1
                )
                .tint(.purple)
            }

            // Effects
            if !track.effects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Effects")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    ForEach(track.effects, id: \.self) { effectID in
                        HStack {
                            Image(systemName: "waveform.path")
                                .font(.system(size: 10))
                                .foregroundColor(.cyan)

                            Text(effectID)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }

            // Delete button
            Button(action: {
                try? recordingEngine.deleteTrack(track.id)
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Track")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                )
            }
        }
    }

    // MARK: - Waveform View

    private func waveformView(data: [Float]) -> some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midY = height / 2

                // Draw center line
                var centerPath = Path()
                centerPath.move(to: CGPoint(x: 0, y: midY))
                centerPath.addLine(to: CGPoint(x: width, y: midY))
                context.stroke(centerPath, with: .color(.white.opacity(0.1)), lineWidth: 1)

                // Draw waveform
                let samplesPerPixel = max(1, data.count / Int(width))
                var waveformPath = Path()

                for x in 0..<Int(width) {
                    let sampleIndex = x * samplesPerPixel
                    if sampleIndex < data.count {
                        let amplitude = CGFloat(data[sampleIndex])
                        let y = midY - (amplitude * height * 0.8)

                        if x == 0 {
                            waveformPath.move(to: CGPoint(x: CGFloat(x), y: y))
                        } else {
                            waveformPath.addLine(to: CGPoint(x: CGFloat(x), y: y))
                        }
                    }
                }

                context.stroke(
                    waveformPath,
                    with: .color(track.type.color.opacity(0.8)),
                    lineWidth: 1.5
                )
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func panString(_ pan: Float) -> String {
        if abs(pan) < 0.01 {
            return "Center"
        } else if pan < 0 {
            return "L \(Int(abs(pan) * 100))"
        } else {
            return "R \(Int(pan * 100))"
        }
    }
}

// MARK: - Track Type Extensions

extension Track.TrackType {
    var icon: String {
        switch self {
        case .audio: return "waveform"
        case .voice: return "mic.fill"
        case .binaural: return "headphones"
        case .spatial: return "airpodspro"
        case .master: return "slider.horizontal.3"
        }
    }

    var color: Color {
        switch self {
        case .audio: return .cyan
        case .voice: return .green
        case .binaural: return .purple
        case .spatial: return .blue
        case .master: return .orange
        }
    }
}
