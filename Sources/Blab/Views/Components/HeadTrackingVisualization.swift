import SwiftUI

/// Visual indicator for head tracking position
/// Shows real-time head rotation as a 3D sphere with direction indicator
struct HeadTrackingVisualization: View {

    @ObservedObject var headTrackingManager: HeadTrackingManager

    var body: some View {
        VStack(spacing: 12) {
            // 3D Position Indicator
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.cyan.opacity(0.2), lineWidth: 2)
                    .frame(width: 120, height: 120)

                // Crosshairs
                Path { path in
                    // Horizontal line
                    path.move(to: CGPoint(x: 0, y: 60))
                    path.addLine(to: CGPoint(x: 120, y: 60))
                    // Vertical line
                    path.move(to: CGPoint(x: 60, y: 0))
                    path.addLine(to: CGPoint(x: 60, y: 120))
                }
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .frame(width: 120, height: 120)

                // Moving dot (represents head position)
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                headColor,
                                headColor.opacity(0.5)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 15
                        )
                    )
                    .frame(width: 20, height: 20)
                    .shadow(color: headColor.opacity(0.5), radius: 10)
                    .offset(headOffset)
                    .animation(.easeOut(duration: 0.1), value: headTrackingManager.normalizedPosition.x)
                    .animation(.easeOut(duration: 0.1), value: headTrackingManager.normalizedPosition.y)

                // Center reference dot
                if !headTrackingManager.isTracking {
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 120, height: 120)

            // Tracking Status
            HStack(spacing: 8) {
                Image(systemName: headTrackingManager.isTracking ? "location.fill" : "location.slash")
                    .font(.system(size: 12))
                    .foregroundColor(headTrackingManager.isTracking ? .green : .gray)

                Text(headTrackingManager.isTracking ? "Tracking" : "Inactive")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            // Rotation Values (Debug)
            if headTrackingManager.isTracking {
                VStack(spacing: 4) {
                    let degrees = headTrackingManager.headRotation.degrees

                    rotationRow(label: "Yaw", value: degrees.yaw, icon: "arrow.left.and.right")
                    rotationRow(label: "Pitch", value: degrees.pitch, icon: "arrow.up.and.down")
                    rotationRow(label: "Roll", value: degrees.roll, icon: "rotate.right")
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.3))
        )
    }

    // MARK: - Helper Views

    private func rotationRow(label: String, value: Double, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.cyan.opacity(0.7))
                .frame(width: 16)

            Text(label)
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 40, alignment: .leading)

            Text("\(Int(value))°")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 50, alignment: .trailing)

            Spacer()
        }
    }

    // MARK: - Computed Properties

    /// Calculate head position offset (-50 to +50 points from center)
    private var headOffset: CGSize {
        let maxOffset: CGFloat = 50  // Max distance from center

        let x = CGFloat(headTrackingManager.normalizedPosition.x) * maxOffset
        let y = CGFloat(-headTrackingManager.normalizedPosition.y) * maxOffset  // Invert Y

        return CGSize(width: x, height: y)
    }

    /// Color based on head position (dynamic visualization)
    private var headColor: Color {
        if !headTrackingManager.isTracking {
            return .gray
        }

        let colors = headTrackingManager.getVisualizationColor()
        return Color(red: colors.red, green: colors.green, blue: colors.blue)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.1, green: 0.05, blue: 0.2)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        let headTracking = HeadTrackingManager()

        VStack(spacing: 20) {
            HeadTrackingVisualization(headTrackingManager: headTracking)

            // Test button
            Button(action: {
                if headTracking.isTracking {
                    headTracking.stopTracking()
                } else {
                    headTracking.startTracking()
                }
            }) {
                Text(headTracking.isTracking ? "Stop Tracking" : "Start Tracking")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.cyan.opacity(0.8))
                    )
            }
        }
        .padding()
    }
}
