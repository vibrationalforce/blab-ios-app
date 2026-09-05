import XCTest
@testable import Echoelmusic

/// #989 — the front door opens at every text size.
///
/// WHY IT EXISTS. Onboarding is the only way into the app and the only writer of
/// `hasCompletedOnboarding`. Its three pages were bare `VStack`s with no scroll container, every
/// string scales with Dynamic Type, and this is the ONE surface with no `dynamicTypeSize` ceiling
/// — the instrument branch caps itself in `WorkspaceView`, this is a sibling branch. So at
/// accessibility text sizes in PORTRAIT the Start button sat below the screen with no in-app way
/// to reach it: install, cannot enter, delete. The user that hits it is exactly the user the
/// WCAG-tuned safety copy on that page was written for.
///
/// ⚠️ WHAT THIS FILE CAN AND CANNOT SEE. It renders no SwiftUI and measures no layout, so whether
/// the pages LOOK right at ordinary sizes is the NEEDS-FOUNDER-VERIFY at the foot of this file.
/// What it pins is the SHAPE that makes the fix work, including the trap the first draft of the
/// fix would have fallen into.
final class OnboardingPagesScrollTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    private func onboarding() throws -> String {
        try source("Sources/Echoelmusic/Views/OnboardingView.swift")
    }

    // 1 — all three pages go through the scroll container. Counting the CALLS rather than naming
    // the pages is deliberate: a fourth page must be wrapped too, and a needle per page name
    // would silently pass for one that does not exist yet.
    func testEveryPageGoesThroughTheScrollContainer() throws {
        let view = try onboarding()
        let pages = view.components(separatedBy: "Page: some View {").count - 1
        let wrapped = view.components(separatedBy: "scrollablePage {").count - 1
        XCTAssertGreaterThan(pages, 0, """
            No page property found at all. Either onboarding was restructured or this scan can no \
            longer match its shape — the second is how a guard passes forever on a file it never \
            read (#808).
            """)
        XCTAssertEqual(wrapped, pages, """
            \(pages) onboarding pages, \(wrapped) wrapped. An unwrapped page cannot be scrolled, \
            and on the page that carries Start that means a user at accessibility text sizes \
            cannot enter the app at all.
            """)
    }

    // 2 — the trap. A BARE `ScrollView` gives its content the content's own ideal height, which
    // collapses every `Spacer()` in these pages to zero and top-aligns all three at ordinary text
    // sizes: an accessibility fix paid for with a visual regression nobody asked for. The
    // viewport-height floor is what keeps the Spacers working when the content fits.
    func testTheScrollContainerKeepsTheSpacersWorkingWhenItFits() throws {
        let view = try onboarding()
        XCTAssertTrue(view.contains("minHeight: proxy.size.height"), """
            The scroll container no longer floors its content at the viewport height. Without \
            that floor every `Spacer()` in the three pages collapses and the layout top-aligns \
            at ordinary text sizes — the regression this shape exists to avoid.
            """)
        XCTAssertTrue(view.contains("GeometryReader"), """
            The viewport height has no source. `minHeight` needs the container's own size; there \
            is no other way to know it here.
            """)
        XCTAssertTrue(view.contains("scrollBounceBehavior(.basedOnSize)"), """
            A page that FITS now rubber-bands. That reads as "there is more below" on precisely \
            the pages where there is not, which is its own small lie on the front door.
            """)
    }

    // 3 — the button the whole slice is about is inside the wrapped region. If Start ever moves
    // out of the page body (into a fixed footer, say), THAT IS ALLOWED — but then the reason this
    // file exists has changed, and the claim above stops describing the real risk (#364).
    func testTheStartWriterIsInsideAPageBody() throws {
        let view = try onboarding()
        guard let wrap = view.range(of: "scrollablePage {"),
              let start = view.range(of: "isComplete = true"),
              let helper = view.range(of: "private func scrollablePage") else {
            XCTFail("Could not locate the wrapper, the helper or the Start writer — re-anchor "
                    + "rather than delete: the subject is that Start is reachable by scrolling.")
            return
        }
        XCTAssertTrue(wrap.lowerBound < start.lowerBound && start.lowerBound < helper.lowerBound, """
            `isComplete = true` no longer sits inside a wrapped page body. Start is the only \
            writer of `hasCompletedOnboarding`; if it now lives outside the scrollable region, \
            re-derive whether it can still be reached at accessibility text sizes.
            """)
    }

    // 4 — the ceiling this whole defect rests on. Onboarding must NOT quietly grow a
    // `dynamicTypeSize` cap as a shortcut: capping the text would hide the symptom by shrinking
    // the very safety copy this page is legally showing.
    func testOnboardingDoesNotCapTextInsteadOfScrolling() throws {
        let view = try onboarding()
        let modifier = view.components(separatedBy: ".dynamicTypeSize(").count - 1
        XCTAssertEqual(modifier, 0, """
            Onboarding now caps Dynamic Type. That makes the Start button fit by making the \
            MANDATED safety warnings smaller for the user who most needs them large — the \
            opposite of the fix. Scroll the page instead.
            """)
    }

    // NEEDS-FOUNDER-VERIFY: launch onto a fresh install and walk all three onboarding pages, once
    // at the default text size and once at the largest accessibility size in Settings, in
    // portrait. At the default size the pages should look unchanged (content centred, no bounce);
    // at the largest they should scroll and Start must be reachable without rotating the phone.
}
