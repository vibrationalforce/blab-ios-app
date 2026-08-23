#if canImport(SwiftUI) && canImport(StoreKit)
import SwiftUI
import StoreKit

// ProUnlockView.swift
// Echoel Pro — the ONE-TIME unlock surface (founder decision 2026-07-10:
// income first, Free + one purchase, no subscription). Policy lives in
// `ProGate` (what is gated), purchase state in `EchoelStore` (StoreKit 2).
//
// Honesty rules (Council 2026-07-10): the core instrument — biofeedback,
// sound, safety, accessibility — is free forever and says so here. We never
// sell something as available that has not shipped.
//
// ⛔ THIS HEADER SAID "Pro extensions that are still in development are labelled
// as such" AND THAT WAS THE HOLE, not the safeguard (#765). It made "in
// development" the sanctioned wording for anything unbuilt — so three rows and
// the header sentence used it for work that was DELETED (AUv3, #121 Slice 2) or
// never begun (video-FX catalog, 4K export). The rule now names the state that
// actually applies here: **planned, not built yet**. "In development" is a claim
// about the PRESENT and may only be written when code exists to back it.
// Guard: `Tests/CISmoke/TheProScreenSellsNoWorkThatIsNotHappeningTests`.

@MainActor
struct ProUnlockView: View {
    @Environment(EchoelStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var purchasing = false
    @State private var purchaseFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if store.isProUnlocked {
                        unlockedBanner
                    }
                    featureList
                    freeForever
                    if !store.isProUnlocked {
                        purchaseSection
                    }
                }
                .padding(16)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Echoel Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(EchoelTheme.text)
                }
            }
            .alert("Purchase failed", isPresented: $purchaseFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing was charged. Please try again later.")
            }
            .task {
                if store.proProduct == nil { await store.loadProducts() }
                await store.updateEntitlements()
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Buy once. Yours forever.")
                .font(EchoelTheme.font(20, .semibold))
                .foregroundStyle(EchoelTheme.text)
            // ⛔ THIS SENTENCE ENDED "— including the ones still in development, when they
            // ship." (#765). It is the sharpest form of the row defect below: a PURCHASE
            // PROMISE attached to work that does not exist. Measured — AUv3 was deleted, the
            // video-FX catalog is an enum case with no implementation, and no 4K/aspect-ratio
            // export code exists. Nothing was in development. What survives is the founder's
            // actual 2026-07-10 term, which is true and is the point of the screen: one
            // purchase, no subscription, later additions included. That describes the DEAL,
            // not the state of unbuilt work.
            Text("Echoel is an instrument, not a subscription. One purchase unlocks every Pro extension, including any added later.")
                .font(EchoelTheme.font(13))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unlockedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(EchoelTheme.accent)
            Text("Echoel Pro is unlocked on this Apple ID.")
                .font(EchoelTheme.font(13, .semibold))
                .foregroundStyle(EchoelTheme.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.accent, lineWidth: 1))
    }

    /// Pro extensions with HONEST status — never claim unshipped work as available.
    ///
    /// ⛔ THREE OF THESE FOUR ROWS SAID "In development" AND NOT ONE OF THEM HAD CODE (#765).
    /// The doc line above was already right about the LAW and the rows still broke it, because
    /// "in development" reads as a softener rather than as what it is: a claim about the
    /// PRESENT. Measured on this tree:
    ///   · AUv3 — the target was DELETED on 2026-07-24 (#121 Slice 2). `Sources/EchoelmusicAUv3`
    ///     does not exist, `Package.swift` links nothing, and `ContentPipelineClaimsTests`
    ///     pins that absence. The work was removed, not started. That is the opposite of
    ///     "in development".
    ///   · Video FX catalog — `videoFXCatalog` occurs in exactly two places: the `ProFeature`
    ///     case and the label below. No implementation of any kind.
    ///   · Export format presets (4K, aspect ratios) — no 4K, no aspect-ratio export code
    ///     anywhere under `Sources/`.
    /// Only "Extended sound preset packs" describes something real (`PatchStore`'s factory set),
    /// and its detail is not a present-tense work claim, so it is unchanged.
    ///
    /// ⚠️ THE ROW SET IS THE FOUNDER'S, THE TENSE IS NOT. What Echoel Pro contains is a pricing
    /// decision (2026-07-10, and superseded again by the v1.1 "Echoel Live" plan) — this change
    /// does not add or remove a row. It replaces a false present tense with a true one.
    ///
    /// ⚠️ WHY IT MATTERS WHILE NOTHING PRESENTS THIS VIEW: `ProUnlockView` is deliberately kept
    /// to be REPURPOSED for v1.1. The day it is re-doored it becomes a PAYWALL, the one surface
    /// where a false capability claim is an App Store 2.3 rejection — the failure #184 already
    /// paid for on the store text. Every AUv3 guard in this repo reads `docs/`, `fastlane/`,
    /// `ContentPipeline/CLAIMS.md` or the deleted target's path; NONE read app copy.
    /// `TheProScreenSellsNoWorkThatIsNotHappeningTests` is the one that does.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pro extensions")
                .font(EchoelTheme.font(11, .semibold))
                .foregroundStyle(EchoelTheme.dim)
                .padding(.bottom, 8)
            featureRow("square.grid.2x2", "Extended sound preset packs",
                       "Grows with every release")
            featureRow("arrow.up.right.square", "Export format presets",
                       "4K & aspect ratios — planned, not built yet")
            featureRow("pianokeys", "AUv3 plugin in your DAW",
                       "Planned, not built yet")
            featureRow("camera.filters", "Video FX catalog",
                       "Planned, not built yet")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(EchoelTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(EchoelTheme.font(13))
                    .foregroundStyle(EchoelTheme.text)
                Text(detail)
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    /// The core is never for sale — state it plainly.
    private var freeForever: some View {
        Text("The whole instrument — biofeedback, sound, composition, safety and accessibility — is free. Forever. Pro only adds extensions on top.")
            .font(EchoelTheme.font(12))
            .foregroundStyle(EchoelTheme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            if let product = store.proProduct {
                Button {
                    guard !purchasing else { return }
                    purchasing = true
                    Task {
                        defer { purchasing = false }
                        do {
                            _ = try await store.purchase(product)
                        } catch {
                            purchaseFailed = true
                        }
                    }
                } label: {
                    HStack {
                        if purchasing {
                            ProgressView().tint(EchoelTheme.bg)
                        } else {
                            Text("Unlock Echoel Pro — \(product.displayPrice)")
                                .font(EchoelTheme.font(15, .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.accent))
                    .foregroundStyle(EchoelTheme.bg)
                }
                .buttonStyle(.plain)
                .disabled(purchasing)
                .accessibilityLabel("Unlock Echoel Pro, one-time purchase, \(product.displayPrice)")
            } else if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            } else {
                Text("The Pro unlock isn't available right now. Please check back later.")
                    .font(EchoelTheme.font(12))
                    .foregroundStyle(EchoelTheme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await store.restorePurchases() }
            } label: {
                Text("Restore purchase")
                    .font(EchoelTheme.font(13))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Restores a previous Echoel Pro purchase on this Apple ID")
        }
    }
}
#endif
