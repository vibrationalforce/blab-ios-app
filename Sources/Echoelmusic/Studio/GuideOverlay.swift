#if canImport(SwiftUI)
import SwiftUI

// GuideOverlay.swift
// Echoelmusic — Studio
//
// #603 B1+B2: the founder's on/off guide ("an- und ausschaltbarer Guide der hilft die
// App zu bedienen und zu verstehen"), as a NON-MODAL card overlay.
//
// WHY AN OVERLAY AND NOT A SHEET. `EchoelStudioView.body`'s presentation chain is pinned
// at 14 modifiers (file-wide 16) and growing it is the 10.76.34 black-screen SIGSEGV.
// `WorkspaceView`'s ZStack already hosts exactly this shape — `FloatingVisualWindow` is a
// non-modal sibling toggled by an `@AppStorage` flag — so the guide mounts there as a
// third layer and costs ZERO presentation modifiers.
//
// WHY THE CONTENT IS NOT WRITTEN HERE (#416). `LearnLibrary.guideEntries` — the "Start
// Here" section, six entries written for exactly this purpose (#589) — is the ONE source,
// and it is already guarded: `TheGuideNamesOnlyRealControlsTests` pins every control name
// in it to the shipping UI, which is the Skeptic's condition from the #603 Council ("a
// guide that goes stale LIES"). This file renders; it never authors copy. Fewer cards,
// all true.
//
// FREEZE LAW (10.76.41/50): this view reads ONE low-frequency `@AppStorage` bool and its
// own paging `@State`. No bio, no playhead, no transport — nothing here can rebuild at
// rate, and `WorkspaceView` only CONSTRUCTS it (constructing registers no observation).
//
// UNCODIXFY: solid `surface` fill, 1 px border, radius ≤ 16, no blur/glass, no shadows
// beyond the house 8 pt, opacity/color transitions only. Dynamic Type is deliberately
// UNCLAMPED — a guide that truncates for the users who most need it would be the
// accessibility audit's "anti-fix" one surface further on; the detail scrolls instead.
struct GuideOverlay: View {

    @AppStorage(StudioDefaultKeys.guideVisible.key)
    private var guideVisible = StudioDefaultKeys.guideVisible.value

    /// Card index into `entries`. Survives hide/show within a launch on purpose — a
    /// player who closes the guide mid-tour and reopens it resumes where they were.
    @State private var page = 0

    /// The one content source (#416). Computed, not cached: six value-type entries,
    /// built only while the guide is actually open.
    private var entries: [LearnEntry] { LearnLibrary.entries(for: .guide) }

    var body: some View {
        if guideVisible, !entries.isEmpty {
            let index = min(page, entries.count - 1)
            let entry = entries[index]
            VStack {
                Spacer(minLength: 0)
                card(entry, index: index, of: entries.count)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .transition(.opacity)
        }
    }

    private func card(_ entry: LearnEntry, index: Int, of count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.title)
                    .font(EchoelTheme.font(15, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(index + 1)/\(count)")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
                    .accessibilityHidden(true)   // the group's value announces the page
                Button { guideVisible = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EchoelTheme.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide guide")
                .accessibilityHint("The guide switch in Save & Export brings it back")
            }
            Text(entry.summary)
                .font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
            // The detail SCROLLS instead of truncating or shrinking — the a11y audit's
            // rule (#353c: "shrinking text the user asked to be larger is the anti-fix").
            // maxHeight keeps the card from swallowing the instrument beneath it.
            ScrollView {
                Text(entry.detail)
                    .font(EchoelTheme.font(13))
                    .foregroundStyle(EchoelTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            HStack(spacing: 8) {
                pageButton("chevron.left", label: "Previous guide card", disabled: index == 0) {
                    page = index - 1
                }
                pageButton("chevron.right", label: "Next guide card", disabled: false) {
                    // Last card: forward means "done" — the tour ends by getting out of
                    // the way, not by dead-ending on a disabled control.
                    if index >= count - 1 { guideVisible = false } else { page = index + 1 }
                }
                Spacer(minLength: 0)
                if index >= count - 1 {
                    Text("Done — this switch lives in Save & Export.")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge).fill(EchoelTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Guide")
        .accessibilityValue("\(entry.title), card \(index + 1) of \(count)")
    }

    private func pageButton(_ symbol: String, label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(disabled ? EchoelTheme.dim : EchoelTheme.text)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    // `borderStrong`, not `border` — the a11y audit's WCAG 1.4.11 rollout
                    // (#367): interactive boundaries at 3.7:1, the divider stroke stays
                    // for genuinely decorative outlines only. The token already CARRIES
                    // its 0.45 opacity — adding another `.opacity` would square it back
                    // below the contrast it exists to provide.
                    .strokeBorder(EchoelTheme.borderStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}
#endif
