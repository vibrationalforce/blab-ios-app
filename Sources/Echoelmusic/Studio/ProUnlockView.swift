#if canImport(SwiftUI) && canImport(StoreKit)
import SwiftUI
import StoreKit

// ProUnlockView.swift
// Echoel Pro — the ONE-TIME unlock surface (founder decision 2026-07-10:
// income first, Free + one purchase, no subscription). Policy lives in
// `ProGate` (what is gated), purchase state in `EchoelStore` (StoreKit 2).
//
// Honesty rules (Council 2026-07-10): the core instrument — biofeedback,
// sound, safety, accessibility — is free forever and says so here. Pro
// extensions that are still in development are labelled as such; we never
// sell something as available that has not shipped.

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
            Text("Echoel is an instrument, not a subscription. One purchase unlocks every Pro extension — including the ones still in development, when they ship.")
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
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pro extensions")
                .font(EchoelTheme.font(11, .semibold))
                .foregroundStyle(EchoelTheme.dim)
                .padding(.bottom, 8)
            featureRow("square.grid.2x2", "Extended sound preset packs",
                       "Grows with every release")
            featureRow("arrow.up.right.square", "Export format presets",
                       "4K & aspect ratios — in development")
            featureRow("pianokeys", "AUv3 plugin in your DAW",
                       "In development")
            featureRow("camera.filters", "Video FX catalog",
                       "In development")
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
