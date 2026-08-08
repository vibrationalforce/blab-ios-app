// YouCanNameYourselfTests.swift
// Echoel — #522. The door that had never existed, and the successor to
// `TheTakeSaysWhoMadeItTests.testNothingLetsYouNameYourselfYet`, which asserted the opposite
// fact and was deleted in the same commit exactly as its own failure message instructed.
//
// ⚠️ THE LIMIT FIRST. The DECISION half is real behaviour driven end to end —
// `SessionContext.storedArtistName`/`typedArtistName`/`unnamedArtist` are `nonisolated` pure
// members, `SessionNaming` is Foundation-only, `Project` is plain `Codable` — so those cases
// exercise shipped code rather than describing it. The WIRING half is a SOURCE-TEXT SCAN:
// `ArtistNameRow` is a `private` `View` behind `#if canImport(SwiftUI)` resolving an
// `@Environment`, and `utilityRow` is a `private var` on a view this bundle cannot construct.
// **That the field RENDERS, that the keyboard behaves, and that a name typed on the device
// actually reaches a saved take are three device trials and all three are OPEN.**
//
// ⭐ WHAT WAS WRONG. `SessionContext.artistName` is persisted, is stamped onto every saved take
// by `currentProject()`, and travels inside the shared document — but its `didSet` is the ONLY
// writer of the stored value, and **Swift does not run `didSet` from an initialiser**, so the
// one line that would persist a name could never fire. `git grep artistName -- Sources` returned
// the key, the property, that `didSet`, two `init` assignments and a handful of readers, and
// NOTHING that assigned it. Every device reported `E~`, every take was stamped `E~`, and #521's
// credit line was correctly silent on every take in existence — a mechanism with no producer in
// the #506 shape.
//
// ⛔ IT DOES NOT FIX #513, although the v10.79.382 deploy note said one word would "solve three
// things at once". Measured: `MCPeerID` is constructed exactly once, in `MultipeerSession.init()`,
// from `UIDevice.current.name` — which iOS 16+ returns as the MODEL name ("iPhone") without the
// user-assigned-device-name entitlement Echoel does not hold. Live-Colabo peers stay
// indistinguishable. **Two things land here, not three**, and claim 7 pins that so the overclaim
// cannot quietly return.
//
// ⭐ THE COUNTERWEIGHTS ARE THE CONTENT (#343). A guard that only asserted "a field exists" would
// stay green on a tree that kept the field and lost every property that makes it safe: the
// never-`""` invariant (without it `Project.attribution` fires `by E~` on your OWN takes), the
// verbatim store (trim on the way in makes a two-word name untypeable), and the coincidence of
// `SessionContext.unnamedArtist` with `SessionNaming.stem`'s independent `E~` fallback, which
// `SessionContext`'s own doc promises will go red rather than diverge silently.
//
// ⚠️ HONEST GRADING (#433/#464), stated plainly rather than disguised: this file **cannot be
// graded against the parent tree at all** — every behaviour case names
// `SessionContext.storedArtistName(fromTyped:)`, which does not exist there, so the bundle does
// not compile and NO claim has a verdict. Transcribed by hand instead (a Python rebuild of
// `SourceText.codeOnly` plus the brace matcher, run against the parent and the working tree):
// the three source scans are red on the parent for their NAMED reason — `ArtistNameRow` is not
// declared, not mounted, and the transform it calls does not exist — which is **ONE absence
// reported three times (#486)**, not three findings. The behaviour cases drive symbols this same
// commit creates and could never have been red. Two are genuine counterweights, green on both
// trees: the `SessionNaming` fallback coincidence and the ordering of name-before-place.
//
// ⚠️ `SourceText.codeOnly` is **LOAD-BEARING here, and that is MEASURED** (#484/#485 each had to
// retract the stronger claim once, #486 twice). The mount comment this slice writes quotes
// `` `#if canImport(CoreLocation)` `` verbatim, to record that the row sits OUTSIDE that guard.
// Raw, `utilityRow` therefore contains that token **twice**, and the first occurrence is the
// COMMENT — which sits BEFORE `ArtistNameRow()`, so the ordering claim would be **red on correct
// code**. Stripped it occurs once and the order holds. This is the #486/#491 collision again:
// this repo writes down what it did, and a scan that reads raw text reads the explanation too.

import XCTest
@testable import Echoelmusic

final class YouCanNameYourselfTests: XCTestCase {

    // MARK: - The decision (real behaviour on pure, `nonisolated` members)

    /// A typed name is stored VERBATIM — including the trailing space, which is the case that
    /// decides the design. Trimming on the way in would eat the space in "Mira " the instant it
    /// is typed, so a two-word name could not be entered at all.
    func testATypedNameIsStoredVerbatim() {
        XCTAssertEqual(SessionContext.storedArtistName(fromTyped: "Mira"), "Mira")
        XCTAssertEqual(SessionContext.storedArtistName(fromTyped: "Mira "), "Mira ",
                       "The stored value was trimmed. A two-word name is then untypeable.")
        XCTAssertEqual(SessionContext.storedArtistName(fromTyped: " Mira Nakamura"),
                       " Mira Nakamura")
    }

    /// ⚠️⚠️ THE INVARIANT, and it is not cosmetic: `artistName` must NEVER become `""`.
    /// `Project.attribution(besideOwnName:)` trims both sides and returns `nil` when they match,
    /// so a live `""` against takes stamped `E~` would make every one of your OWN takes sprout
    /// `by E~` — the credit line firing on exactly the takes it exists to stay quiet about.
    /// Trimming here decides only WHETHER the field is empty; it never touches the stored value.
    func testClearingTheFieldStoresTheMarkAndNeverAnEmptyString() {
        for typed in ["", " ", "\n", "  \t \n "] {
            XCTAssertEqual(SessionContext.storedArtistName(fromTyped: typed),
                           SessionContext.unnamedArtist, """
                Clearing the name field stored \"\(typed)\" instead of the brand mark. A live \
                empty name makes `Project.attribution` show `by \(SessionContext.unnamedArtist)` \
                on the user's OWN takes.
                """)
        }
    }

    /// The mark reads back as "nothing typed yet", so a new user sees an empty field with a
    /// placeholder rather than an `E~` they never typed and would have to select-all-delete.
    func testTheMarkReadsAsAnEmptyField() {
        XCTAssertEqual(SessionContext.typedArtistName(fromStored: SessionContext.unnamedArtist), "")
        XCTAssertEqual(SessionContext.typedArtistName(fromStored: "Mira"), "Mira")
        XCTAssertEqual(SessionContext.typedArtistName(fromStored: "Mira "), "Mira ")
        // Round trip: whatever a user types comes back to the field unchanged.
        for typed in ["Mira", "Mira ", "E~~", "e~"] {
            XCTAssertEqual(
                SessionContext.typedArtistName(
                    fromStored: SessionContext.storedArtistName(fromTyped: typed)),
                typed, "Typing \"\(typed)\" did not survive a store/read round trip.")
        }
    }

    /// ⚠️ COUNTERWEIGHT, end to end through the SHIPPED credit rule: with the field cleared, a
    /// take you stamped yourself must still stay quiet. This is the assertion that would go red
    /// if `storedArtistName` were ever "simplified" to return the typed string as-is.
    func testAClearedFieldStillLeavesYourOwnTakesUncredited() {
        let own = SessionContext.storedArtistName(fromTyped: "")
        XCTAssertNil(take(artist: SessionContext.unnamedArtist).attribution(besideOwnName: own), """
            After clearing the name field, your own takes show a credit. The field stored \
            \"\(own)\" where the stamp says \"\(SessionContext.unnamedArtist)\".
            """)
        // And a stranger's take still shows one — otherwise the assertion above would be
        // satisfied by a rule that credits nobody, ever.
        XCTAssertEqual(take(artist: "Mira").attribution(besideOwnName: own), "Mira")
    }

    /// ⚠️ COUNTERWEIGHT for a coincidence `SessionContext`'s own doc promises to keep visible.
    /// `SessionNaming.stem` carries its OWN `E~` fallback — deliberately not folded into
    /// `unnamedArtist`, because it answers a different question (what a FILENAME uses when the
    /// artist token sanitises to nothing, reachable with an emoji-only name). They coincide
    /// today; the day they stop, this goes red instead of drifting apart in silence.
    func testTheFilenameFallbackStillEqualsTheStoredMark() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let unnamed = SessionNaming.stem(artist: "", date: date, key: "Am", bpm: 120, a4Hz: 440)
        let marked = SessionNaming.stem(artist: SessionContext.unnamedArtist, date: date,
                                        key: "Am", bpm: 120, a4Hz: 440)
        XCTAssertEqual(unnamed, marked, """
            `SessionNaming.stem`'s own fallback no longer equals \
            `SessionContext.unnamedArtist` (\"\(SessionContext.unnamedArtist)\"). One of the two \
            moved; decide deliberately which is right rather than letting file names and the \
            take stamp disagree.
            """)
        XCTAssertTrue(unnamed.hasPrefix(SessionContext.unnamedArtist),
                      "An unnamed export stem no longer leads with the brand mark: \(unnamed)")
        // And a real name reaches the file name — the second of the two things #522 delivers.
        let named = SessionNaming.stem(artist: "Mira Nakamura", date: date, key: "Am",
                                       bpm: 120, a4Hz: 440)
        XCTAssertTrue(named.hasPrefix("MiraNakamura"), """
            A typed name no longer reaches the export stem (\(named)). Half of what this slice \
            ships is that your files stop being called \(SessionContext.unnamedArtist)_….
            """)
    }

    // MARK: - The wiring (source scans — see the limit at the top of this file)

    /// THE REGRESSION. The door must exist, and it must store through the transform rather than
    /// binding `artistName` raw — a raw binding re-introduces both the literal `E~` in the field
    /// and the empty-string state the invariant above forbids.
    func testTheRowExistsAndStoresThroughTheTransform() throws {
        let row = try declarationBody(of: "private struct ArtistNameRow: View {", in: studioView)
        XCTAssertTrue(row.contains("SessionContext.storedArtistName(fromTyped:"), """
            `ArtistNameRow` no longer stores through `SessionContext.storedArtistName(fromTyped:)`. \
            Binding `artistName` raw lets the field write `""`, and `Project.attribution` then \
            shows `by \(SessionContext.unnamedArtist)` on the user's own takes.
            """)
        XCTAssertTrue(row.contains("SessionContext.typedArtistName(fromStored:"), """
            `ArtistNameRow` no longer reads through `SessionContext.typedArtistName(fromStored:)`. \
            The field then shows the literal brand mark to a user who never typed it.
            """)
    }

    /// ⚠️ THE FREEZE LAW (10.76.41/50, in the form #486 had to correct). `utilityRow` has no
    /// `panel(...)` host at its top level; it is reached through `dropdownContent`'s
    /// `case .export`, which is evaluated in the ROOT body PERMANENTLY, and `AnyView(...)` is not
    /// an observation boundary. Folding this row into `utilityRow` as a `@ViewBuilder` fragment
    /// is the obvious later simplification and it puts a per-keystroke `@State`-class rebuild on
    /// the body that hosts every `.menu` Picker of the instrument.
    func testTheRowIsItsOwnViewStruct() throws {
        let src = try code(at: studioView)
        XCTAssertTrue(src.contains("private struct ArtistNameRow: View {"), """
            `ArtistNameRow` is no longer a `View` struct. See the 10.76.41/50 freeze law — \
            `utilityRow` is evaluated in the root body, so an inlined field churns it.
            """)
    }

    /// The mount, plus the ordering that makes it read correctly, plus the guard it must stay
    /// OUT of. A name is not optional the way a place is: folding the row inside
    /// `#if canImport(CoreLocation)` would make the one door to your own identity depend on a
    /// framework that has nothing to do with it.
    func testTheRowIsMountedBeforeThePlaceRowAndOutsideItsGuard() throws {
        let panel = try declarationBody(of: "private var utilityRow: some View {", in: studioView)
        guard let mount = panel.range(of: "ArtistNameRow()") else {
            return XCTFail("""
                `ArtistNameRow` is not mounted in `utilityRow`. The name field is then built, \
                correct and unreachable — the exact state #522 exists to end.
                """)
        }
        guard let guardRange = panel.range(of: "#if canImport(CoreLocation)") else {
            throw AnchorMissing(reason: """
                `utilityRow` no longer contains the CoreLocation guard this claim is anchored on. \
                Re-anchor rather than deleting the assertion (#408).
                """)
        }
        XCTAssertTrue(mount.lowerBound < guardRange.lowerBound, """
            `ArtistNameRow()` now sits at or after the `#if canImport(CoreLocation)` guard. Two \
            things are wrong with that: the name would disappear on any platform without \
            CoreLocation, and it would read AFTER the place while \
            `SessionNaming.stem(artist:date:key:bpm:a4Hz:place:)` writes it BEFORE.
            """)
    }

    /// ⚠️ COUNTERWEIGHT that pins the scope. #522 delivers TWO things — the credit line becomes
    /// reachable, and export/session file names carry the name. It does NOT make Live-Colabo
    /// peers distinguishable, though the v10.79.382 deploy note claimed it would: `MCPeerID` is
    /// built from `UIDevice.current.name` in a no-argument `init()`. If someone wires the artist
    /// name into that peer id, #513 really is fixed and this assertion should be deleted
    /// deliberately — but it must not happen by accident, and the claim must not return first.
    func testTheArtistNameStillDoesNotReachThePeerIdentity() throws {
        let session = try code(at: "Sources/Echoelmusic/Sync/MultipeerSession.swift")
        guard session.contains("MCPeerID(") else {
            throw AnchorMissing(reason: """
                `MultipeerSession` no longer constructs an `MCPeerID`; this scan is anchored on \
                that. Re-anchor rather than deleting the assertion.
                """)
        }
        XCTAssertFalse(session.contains("artistName"), """
            `MultipeerSession` now reads `artistName`. If that is deliberate, #513 is fixed and \
            this counterweight should be DELETED in the same commit — together with the ⛔ \
            paragraphs in `Project.attribution` and `ArtistNameRow` that currently state the \
            opposite.
            """)
    }

    // MARK: - Fixtures and source access

    private let studioView = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    private func take(artist: String) -> Project {
        Project(name: "Take", styleRaw: "dubTechno", keyRoot: 0, scaleRaw: "minor",
                bpm: 120, modeRaw: "studioLocked", fxCharacterRaw: "auto", loopBars: 8,
                a4Hz: 440, toneSystemID: nil, artist: artist,
                patch: SynthPatch(name: "Default"), notes: [], rawTake: nil,
                drumSteps: [], drumAccents: [])
    }

    private struct AnchorMissing: Error { let reason: String }

    /// Directory-gated, never per-file (#475): a `fileExists` bracket around each read turns the
    /// very catastrophe this file guards against into a green SKIP.
    private func code(at relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body following `key`, which must end in its opening brace.
    ///
    /// ⚠️ The matcher counts braces inside string literals too. It is sound for these two anchors
    /// because their blocks are brace-balanced in literals as well; a future block holding an
    /// unbalanced `{` in a string would need a real lexer, not a wider net.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try code(at: relativePath)
        guard let start = text.range(of: key) else {
            throw AnchorMissing(reason: """
                \(relativePath) no longer declares `\(key)`. This scan is anchored on it; \
                re-anchor rather than deleting the assertion.
                """)
        }
        var depth = 0
        var index = text.index(before: start.upperBound)   // the opening brace itself
        while index < text.endIndex {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" {
                depth -= 1
                if depth == 0 { return String(text[start.upperBound..<index]) }
            }
            index = text.index(after: index)
        }
        throw AnchorMissing(reason: "Unbalanced braces after `\(key)` in \(relativePath).")
    }
}
