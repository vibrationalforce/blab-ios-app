// LockCueDoesNotShoveTheControlsTests.swift
// Echoel — a six-second congratulation must not move the buttons under the finger. #382.
//
// WHAT THIS GUARDS. `BioStripView.statusBanner` is one `@ViewBuilder` if/else-if chain that
// renders AT MOST one line above the strip. Two of its three cases are persistent states
// (camera recovering, camera access denied). The third is a TIMER: when the pulse settles,
// `lockedCueVisible` flips true, and six seconds later it flips back — both inside
// `withAnimation`. While it was an ordinary `else if`, those two flips INSERTED and REMOVED a
// view from the layout, so everything below moved twice.
//
// "Everything below" is not the strip alone. In `EchoelStudioView.bioPanel` this view is the
// FIRST child of a `VStack`, followed by the explanatory sentence, the always-on sentence
// (#542), the breath-coach strip, the breath-voice row, the "Open Routing" button and — inside
// `#if canImport(HealthKit)` — `HealthWriteOptInRow()`. The shove lands on them six seconds
// apart, long enough that the user has stopped expecting it and is plausibly reaching for the
// button when the second one fires.
//
// ⛔ THAT LIST READ "the explanatory sentence, the 'Open Routing' button and … so two controls
// always and three on the shipping iPhone target" — an enumeration that stopped matching as the
// panel grew, and #542 added the sixth child. No assertion in this file counts or orders
// `bioPanel`'s children, so nothing went red; it is corrected because the argument for this
// guard is exactly HOW MUCH the shove displaces, and an undercount makes the case look smaller
// than it is. Deliberately no number now — the count is the thing that keeps going stale.
//
// ⭐ WHY THIS BECAME WORTH A SLICE NOW, stated plainly because the honest version is less
// flattering than "we found a bug": the behaviour is OLD, and #353d made it BIGGER. Before
// that slice the banner was pinned at 11 pt and the shove was one line, roughly 26 pt. Now the
// banner scales with Dynamic Type and wraps, so at AX3+ the same sentence is three or four
// lines and the shove is on the order of 80–110 pt — a third of a phone's usable panel height,
// twice, unannounced. Fixing the font exposed the layout, which is the normal shape of this
// kind of debt and not a reason to regret the font fix.
//
// THE FIX AND WHY THIS ONE. Three answers were on the table and only one needs no device to
// justify:
//   (a) reserve the slot — calm, but a naive fixed height cannot be right at every Dynamic
//       Type size, and a wrong reservation clips or wastes space;
//   (b) drop only the HIDE animation — halves nothing. It is still two layout changes; it just
//       makes the second one instant, i.e. gives the user LESS warning, not more;
//   (c) float the cue over the strip — no shove, but it covers the numbers at the exact moment
//       the numbers are the payoff.
// What ships is (a) done without a magic number: the slot holds the REAL cue view, made
// invisible with `.opacity`, so its reserved height is by construction the height that view
// will occupy at whatever text size the reader has chosen. There is no constant to get wrong.
//
// AND THE RESERVATION IS GATED ON `cameraRPPG.isRunning`, which is the part that keeps it
// honest. A status line that exists only while a measurement is running is a design statement;
// a permanently blank 26 pt above the strip for someone who never starts the camera is a tax.
// The `else` branch is therefore conditional, and this file asserts that it stays conditional —
// an unconditional `else` would "fix" the shove by charging every user for it.
//
// ⛔ WHAT THIS SLICE DOES **NOT** DO, because the first version of this header implied it did
// and both mandatory reviewers independently caught the same over-claim. It stops the CUE'S OWN
// TIMER from moving anything. Two height changes remain, and a device pass that only watches
// the six-second window will miss both:
//   1. The slot appears when the camera STARTS and goes when it STOPS — still two shoves of the
//      full banner height. The trade is that both are now user-initiated instead of arriving
//      unannounced mid-measurement. Better, not free.
//   2. Branch 1 outranks branch 3 whenever `recoveryState.userHint != nil`, and the two render
//      different strings through the same wrapping helper — so a stall, a thermal `.cooling` or
//      an iOS `.interrupted` resizes the slot mid-measurement by a wrapped line or two at AX3+.
//      Left alone deliberately: those messages are informative and low-frequency.
// And the "tax" argument above cuts both ways, which the first version only applied to the
// option it rejected: what ships charges a blank banner row to every MEASURING user for the
// whole measurement. That is the deliberate trade, written down so the next reader weighs the
// same two costs rather than only the flattering one.
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator. It proves the cue is expressed as an
// opacity change inside a conditionally-reserved slot; it cannot prove anything about what the
// panel looks like, and it cannot prove the reserved height is comfortable at AX5.
// NEEDS-FOUNDER-VERIFY: Larger Text at AX3+, open Bio, let the pulse lock, and reach for
// "Open Routing" while the green line appears and disappears. Does anything move? And does the
// reserved blank row read as calm or as a hole?
//
// BOTH tests go red on the pre-fix source (`6e58d8e`), verified by re-deriving every assertion
// against `git show 6e58d8e:…`. The shape test fails three of its four ways — `else if
// lockedCueVisible` present, no `.opacity(` of `lockedCueVisible` in the cue branch, the cue's
// nearest enclosing condition not mentioning `isRunning`; only "no unconditional `else`" was
// already true, and it is a pin against a future over-correction rather than a description of
// the bug. The inertness test fails both ways: neither `accessibilityHidden` nor
// `allowsHitTesting` appears anywhere in the file at that revision. Written out per assertion
// instead of as a tally, because a tally in exactly this position has been wrong twice in this
// bundle.
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class LockCueDoesNotShoveTheControlsTests: XCTestCase {

    private static let strip = "Sources/Echoelmusic/Studio/BioStripView.swift"
    /// ⛔ NOT `bannerDeclaration`. `CoachingTextScalesTests` has a constant of that name
    /// pointing at `banner(_:color:systemImage:)` — a DIFFERENT member of this same file, and
    /// the two guards are ones a reader will inevitably read side by side. One name, two
    /// members, one source file is a collision waiting to mislead.
    private static let statusBannerDeclaration = "private var statusBanner: some View"
    private static let cueText = "Pulse detected"

    /// The transient cue changes its OPACITY inside a reserved slot — it is not inserted.
    func testTheLockCueIsAReservedSlotNotAnInsertion() throws {
        let source = try codeLines(Self.strip)
        let slot = try window(source, from: Self.statusBannerDeclaration)

        XCTAssertFalse(slot.contains { $0.contains("else if lockedCueVisible") }, """
            `statusBanner` is branching on `lockedCueVisible` again, which puts the six-second \
            "Pulse detected" cue back INTO and OUT OF the layout. In `bioPanel` this view is \
            the first child of a `VStack`, so both flips move the sentence below it, the \
            "Open Routing" button and (on any build with HealthKit) the Health opt-in row — \
            twice, six seconds apart, at a moment when the user has every reason to be \
            reaching for one of them. Since the banner scales with Dynamic Type (#353d) that \
            shove is 80–110 pt at AX3+, not the 26 pt it used to be. Express the cue as an \
            opacity change inside a slot that is already reserved, so that the cue's own \
            timer stops moving anything.
            """)

        // ⛔ THE CUE BRANCH, NOT THE WINDOW. The first version asked only whether the tokens
        // appeared ANYWHERE in `statusBanner`, so moving `.opacity`/`.accessibilityHidden`
        // onto the RECOVERY banner while leaving the gate in place would have kept every
        // assertion green with the bug fully re-opened. Everything below is scoped to the
        // lines from the cue's own text to the end of the member — it is the last branch, so
        // that slice is exactly the branch and nothing else.
        guard let cueLine = slot.firstIndex(where: { $0.contains(Self.cueText) }) else {
            throw XCTSkip("""
                the cue text "\(Self.cueText)" is gone from `statusBanner` — if the wording \
                changed, update `cueText` in the same commit; if the branch was removed, this \
                guard should be rewritten with it rather than left to pass on an empty window
                """)
        }
        let cueBranch = slot[cueLine...]

        // ⛔ MATCHED LOOSELY ON PURPOSE. Pinning the whole ternary would redden on `? 1.0 : 0.0`
        // — identical code — with a message claiming the modifier was "lost", and a guard
        // whose failure text is wrong is worse than a missing guard (the lesson written into
        // `CoachingTextScalesTests`). The load-bearing fact is that the cue's VISIBILITY is an
        // opacity of `lockedCueVisible`, not its presence.
        XCTAssertTrue(cueBranch.contains { $0.contains(".opacity(") && $0.contains("lockedCueVisible") }, """
            The lock cue's visibility is no longer an `.opacity(...)` of `lockedCueVisible`. \
            That expression is the whole fix: the slot always builds the REAL cue view while a \
            measurement runs, so the height it reserves is by construction the height the cue \
            will need at the reader's own text size — no constant to get wrong, at any Dynamic \
            Type setting. Replacing it with a conditional, or with a hard-coded `minHeight`, \
            brings back either the shove or a number that is right at exactly one text size.
            """)

        // The gate is read BACKWARDS from the cue — the nearest branch header above it — so
        // this proves the cue's OWN branch is the gated one, not merely that the token exists.
        let header = slot[..<cueLine].last { $0.contains("if ") }
        // Hoisted rather than interpolated inline: a nested string literal inside a `\(…)`
        // inside a `"""` block is legal but is exactly the shape that made this bundle's
        // gate RED once before on type-check cost (#287). Keep interpolations trivial.
        let headerText = header?.trimmingCharacters(in: .whitespaces) ?? "missing"
        XCTAssertTrue(header?.contains("cameraRPPG.isRunning") == true, """
            The branch that renders the lock cue is no longer gated on \
            `cameraRPPG.isRunning` — its nearest enclosing condition is \(headerText). \
            That gate is what keeps the reservation from becoming a tax: while a measurement \
            runs a status line exists and the cue's timer moves nothing; when nothing is \
            measuring there is no line and no blank space. An ungated slot would hold empty \
            height above the strip for every user who never starts the camera — solving the \
            shove by charging everyone for it. (Refining the condition is fine, dropping \
            `isRunning` from it is not.)
            """)

        // ⛔ BRANCH LEVEL ONLY. Scanning the whole window for `} else {` would redden on a
        // perfectly ordinary nested `if/else` inside branch 1 or 2, with a message accusing
        // `statusBanner` of an unconditional final `else` — again, right assertion, wrong
        // accusation. The branch headers of this member sit one indent step in from the
        // declaration, so that is what gets checked. The `else {`-on-its-own-line spelling is
        // covered too; `} else{` is not, and is left as an accepted miss rather than a regex.
        let branchIndent = String(slot[slot.startIndex].prefix { $0 == " " }) + "    "
        // Hoisted: two concatenations inside one boolean is cheap, but this bundle has been
        // RED once on type-check cost (#287) and the habit is worth more than the brevity.
        let closingElse = branchIndent + "} else {"
        let bareElse = branchIndent + "else {"
        XCTAssertFalse(slot.contains { $0 == closingElse || $0 == bareElse }, """
            `statusBanner` grew an unconditional `else` at branch level. Every branch here \
            must be gated on a state that means "there is something to say", otherwise the \
            slot is reserved even when the camera is off — see the message above. If a \
            genuinely unconditional status line is wanted, that is a design change and this \
            guard should be rewritten with it, deliberately, rather than deleted to let it \
            through.
            """)
    }

    /// An invisible cue must be inert — not merely transparent.
    ///
    /// ⚠️ `.opacity(0)` removes a view from NEITHER the accessibility tree NOR the hit-test
    /// region. `banner(_:color:systemImage:)` ends in `.accessibilityLabel(text)`, which
    /// propagates that sentence onto the subtree's elements; without an explicit hide a
    /// VoiceOver user would swipe into "Pulse detected — you can let go & play" for the entire
    /// measurement, including before any pulse has been detected. That is worse than the layout
    /// bug this slice set out to fix: the shove was an annoyance for sighted users, this would
    /// be a false statement to the one reader who cannot check it.
    ///
    /// ⛔ AN EARLIER VERSION CALLED THESE "A PAIR" AND SHIPPED TWO OF THREE. The house pattern
    /// is stated verbatim in `WorkspaceView` — *"Hidden means INERT, not merely transparent:
    /// no hit target (`allowsHitTesting`), no VoiceOver element (`accessibilityHidden`)"* — and
    /// is written there as `.opacity` + `.allowsHitTesting` + `.accessibilityHidden`. Today the
    /// missing third cost nothing, because this banner holds only an `Image`, a `Text` and a
    /// `Spacer`; it would become a live bug the moment anyone puts a control in it, and the
    /// wording is what a future author copies. So all three are asserted.
    func testTheInvisibleCueIsInert() throws {
        let source = try codeLines(Self.strip)
        let slot = try window(source, from: Self.statusBannerDeclaration)
        guard let cueLine = slot.firstIndex(where: { $0.contains(Self.cueText) }) else {
            throw XCTSkip("""
                the cue text "\(Self.cueText)" is gone from `statusBanner` — see the sibling \
                test; this guard is rewritten with the branch, not left to pass vacuously
                """)
        }
        let cueBranch = slot[cueLine...]

        XCTAssertTrue(cueBranch.contains { $0.contains("accessibilityHidden(!lockedCueVisible)") }, """
            The reserved lock-cue slot lost `.accessibilityHidden(!lockedCueVisible)`. \
            Opacity is a visual property only — the view stays in the accessibility tree, so \
            VoiceOver would announce "Pulse detected — you can let go & play" for the whole \
            measurement, including the many seconds before anything has been detected.
            """)

        XCTAssertTrue(cueBranch.contains { $0.contains("allowsHitTesting(lockedCueVisible)") }, """
            The reserved lock-cue slot lost `.allowsHitTesting(lockedCueVisible)`. An \
            `.opacity(0)` view still takes taps, so the invisible banner would sit over its \
            own row swallowing them. Nothing in the banner is interactive today, which is \
            exactly why this is easy to drop and easy to regret: the house rule in \
            `WorkspaceView` is that hidden means INERT, and it names all three modifiers \
            together. Restore it rather than narrowing the rule to what happens to be \
            harmless in this one view.
            """)
    }

    // MARK: - Reading the source

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// Structural, not a naming convention and not a line count — the two shapes that have
    /// already failed in this bundle. A count rots the moment a rationale block above the
    /// member grows; a `private var ` / `private func ` terminator is a guess about how the
    /// author of the NEXT declaration writes, and when it misses, the window runs on and the
    /// failure text accuses this member of a neighbour's line. `CoachingTextScalesTests`
    /// carries the same helper and the same reasoning at length.
    ///
    /// ⚠️ Accepted limit: a multi-line string literal containing a line that is exactly the
    /// declaration's indentation plus `}` would end the window early. `statusBanner` holds no
    /// string literal spanning lines; if it grows one, this needs a real brace scanner.
    private func window(_ source: [String], from declaration: String) throws -> ArraySlice<String> {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from BioStripView — if the status line was \
                restructured this test should be rewritten with it, not left to pass vacuously
                """)
        }
        let indent = String(source[start].prefix { $0 == " " })
        let closer = indent + "}"
        guard let end = source[start...].dropFirst().firstIndex(where: {
            $0.hasPrefix(closer) && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            throw XCTSkip("""
                `\(declaration)` in BioStripView has no closing brace at its own indentation \
                — the file was reformatted or the member restructured, and reading on would \
                inspect the wrong lines. Rewrite this guard with the new shape rather than \
                letting it report on a window it cannot delimit
                """)
        }
        return source[start...end]
    }

    /// Lines of `path` that are not whole-line comments.
    ///
    /// ⛔ THE FIRST VERSION JUSTIFIED THIS WITH A MECHANISM THAT CANNOT HAPPEN. It said the
    /// stripping was "required" because the rationale block above `statusBanner` quotes the
    /// refuted `else if lockedCueVisible` spelling. It does quote it — but that block sits
    /// ABOVE the declaration, and `window(_:from:)` starts AT the declaration, so prose above
    /// the member is outside every window whether comments are stripped or not. A rationale
    /// whose premise a reader can check and find false is the exact failure this repo keeps
    /// paying for, and writing one INSIDE a guard against that failure is worse than usual.
    ///
    /// The real reasons, both narrower: a future comment line containing the literal string
    /// `private var statusBanner: some View` would move `firstIndex` onto a comment and drag
    /// the prose into the window; and a rationale comment placed INSIDE a branch — the very
    /// thing this slice added elsewhere in the file — could satisfy a `contains` check with
    /// text rather than code. Neither is hypothetical in a file that documents this heavily.
    ///
    /// ⚠️ Whole-line only — a TRAILING comment on a code line survives and reads as code. Same
    /// accepted limit as the sibling guards in this bundle.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probe = root.appendingPathComponent(Self.strip)
        guard FileManager.default.fileExists(atPath: probe.path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
