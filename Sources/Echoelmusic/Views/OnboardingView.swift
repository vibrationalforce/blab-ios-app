#if canImport(SwiftUI)
import SwiftUI
import HealthKit
import os.log

/// Minimal onboarding: explain concept, request HealthKit, start playing.
/// Last tap ("Listen") completes onboarding AND auto-starts the soundscape.
struct OnboardingView: View {

    @Binding var isComplete: Bool
    /// Set to true on completion — EchoelmusicApp reads this to auto-play
    @Binding var shouldAutoPlay: Bool
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    healthPage.tag(1)
                    readyPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Echoelmusic")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)

            Text("Your body creates the soundscape.")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Text("Heart rate, breathing, weather, and time of day shape an ambient sound that's uniquely yours.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            nextButton(label: "Continue")
        }
        .padding(.bottom, 60)
    }

    private var healthPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))

            Text("Connect Your Body")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Echoelmusic reads heart rate and HRV from Apple Watch to make the soundscape respond to your physiology in real-time.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("No wearable? Use your camera or just enjoy the ambient mode.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                requestHealthKit()
                currentPage = 2
            } label: {
                Text("Allow HealthKit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            Button {
                currentPage = 2
            } label: {
                Text("Skip for now")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.bottom, 60)
    }

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))

            Text("Ready")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Your soundscape begins now.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()

            Button {
                shouldAutoPlay = true
                isComplete = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13))
                    Text("Listen")
                }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
        }
        .padding(.bottom, 60)
    }

    // MARK: - Helpers

    private func nextButton(label: String) -> some View {
        Button {
            withAnimation { currentPage += 1 }
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 40)
    }

    private func requestHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let types: Set<HKSampleType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.respiratoryRate)
        ]
        store.requestAuthorization(toShare: nil, read: types) { success, error in
            if let error {
                os_log(.error, "HealthKit auth failed: %{public}@", error.localizedDescription)
            } else if !success {
                os_log(.info, "HealthKit auth denied by user")
            }
        }
    }
}
#endif
