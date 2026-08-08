// TheTakeSaysWhoMadeItTests.swift
// Echoel — #521. A take carries the artist it was saved under, and until this slice NOTHING
// read it back.
//
// ⚠️⚠️ THE REACH FIRST, BECAUSE IT DECIDES HOW TO READ EVERYTHING BELOW — and it CHANGED with
// #522, which is why this paragraph was rewritten rather than left standing. Until that slice
// **no take any Echoel build could produce showed a credit**: `SessionContext.artistName` had no
// production writer at all (its only assignments were the two inside `init`, and Swift does not
// run `didSet` from an initialiser, so the one line that would persist it never fired). #522
// added the door — a name field in "Save & Export", beside the manual place field — so the
// credit line is reachable for the first time. `YouCanNameYourselfTests` now owns that half.
//
// ⚠️ WHAT IS STILL TRUE, and it is the part a reader will get wrong: **an untouched install
// still shows no credit anywhere, and that is correct.** Until someone types a name, every
// device reports `E~`, every take is stamped `E~`, a take received from someone else's Echoel
// carries `E~` as well (`importProject` replaces only the `id`), and the difference-gate
// correctly returns `nil`. The credit appears exactly when two people have named themselves
// differently — which is the property this file tests and cannot itself create.
//
// ⚠️ AND ONE PROPERTY WENT LIVE WITH THE DOOR, named here because `Project.attribution`'s last
// paragraph predicted it: renaming yourself makes your OWN older takes show your OLD name. The
// stamp is what the take was saved under; it is not re-written retroactively, and re-writing it
// would be the fabrication this file's counterweights forbid.
//
// ⚠️ THE OTHER LIMIT. Three of the nine test METHODS are SOURCE SCANS, and for exactly one reason:
// `projectRow` and `currentProject()` are `private` members of a view no test bundle can
// instantiate. (An earlier draft named a third reason — "`SessionContext` is `@MainActor
// @Observable` over `UserDefaults`" — and it was not a constraint at all: its init takes an
// injectable `defaults:`, and this very bundle already builds one in
// `ResetSoundClearsWhatTheLaunchLineReportsTests`. That scan was turned into a behaviour test,
// which took the count from five to four; #522 then deleted the `Sources/`-wide sweep, taking it
// to three of nine — see the ⛔ receipt where that method stood.) **That the third line RENDERS,
// that it reads as a
// neutral fact rather than an accusation, and that it survives accessibility text sizes are
// three device trials, and all three are open.**
//
// WHAT WAS WRONG. `Project.artist` has been stamped, encoded and decoded since this format
// existed and had ZERO readers — nothing anywhere read `p.artist` back. That is #494's `modeRaw`
// shape exactly, and it is the shape no persistence test can see: a field that round-trips
// perfectly and is never read is invisible to every round-trip assertion.
//
// ⛔ AND THE MOTIVATING SENTENCE OF THE FIRST DRAFT WAS FALSE. It read "#520 made Import a door
// that REPORTS, **so** takes genuinely do arrive from other people now". Measured against the
// parent: the pre-#520 call site was already `projects.importProject(from: url)`, which ends in
// `save(p)`. A successful import landed in the library long before #520; what #520 changed is
// the FAILURE path. Arrival is not new — reporting is. The weaker claim is the true one and is
// enough: however a take arrives, it renders exactly like one you made.
//
// ⭐ THE COUNTERWEIGHTS ARE THE CONTENT, in the #343 shape. A guard that only asserts the new
// line stays green on a tree that kept the LINE and lost the FACT: the credit is worth nothing
// unless `currentProject()` still stamps it, and the difference-gate is quiet on a fresh install
// only because `SessionContext.init` migrates `.none`/`""`/`"Echoel"` to `E~`. Both premises are
// pinned here, and both are green on either side of this commit — said plainly rather than
// dressed up as regressions (#433).
//
// ⚠️ HONEST GRADING (#433), and it is the #464 situation stated rather than disguised: this file
// **cannot be graded against the parent tree at all** — every behaviour case names
// `Project.attribution(besideOwnName:)`, which does not exist there, so the bundle does not
// compile and NO claim has a verdict. Transcribed by hand (a Python rebuild of
// `SourceText.codeOnly` plus the brace matcher, run against `git show 42d887a:` and the working
// tree): **ONE** source scan is red for its NAMED reason (`projectRow` does not mount the
// credit there); the behaviour cases drive a symbol this same commit creates and could never
// have been red; the rest are counterweights, green on both trees.
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC here, and that is MEASURED rather than assumed
// (#484/#485 each had to retract the stronger claim once, #486 twice): raw versus stripped
// differ on **0 of 6 needle verdicts, on both trees — 0 of 12 cells.** (The history is the
// point. An earlier draft wrote "0 of 4", which was the count of source-scan METHODS rather than
// of needles; then "0 of 6", measured before `p.key.shortName` was added; then "0 of 7" once it
// was. #522 deleted the sweep and with it two needles, so the honest figure is six — RE-MEASURED
// on this tree, not decremented from the last one. One is worth naming: `BPM` occurs 75× raw and
// 31× stripped, and the verdict is unchanged only because the needle is POSITIVE; a negative
// scan on that token would flip. This repo counts needles, and often × 2 trees.) It stays
// because #453 created ONE definition for the whole
// blocking bundle — and every needle here is POSITIVE, so the stripper is the only thing
// standing between "the app does this" and "a comment says so" the day one of these tokens is
// quoted in prose.

import XCTest
@testable import Echoelmusic

@MainActor
final class TheTakeSaysWhoMadeItTests: XCTestCase {

    // MARK: - The decision (real behaviour, end to end on a public value type)

    /// A stamp that is not the reader's own name is what gets shown.
    func testAStrangersStampIsShown() {
        let take = self.take(artist: "Mira")
        XCTAssertEqual(take.attribution(besideOwnName: "E~"), "Mira")
    }

    /// Your own takes stay quiet — including when the two names differ only by surrounding
    /// whitespace. On the STAMPED side that is a real case today: an imported document can carry
    /// anything, and this repo already trims for the same reason in `SessionNamePreviewLeaf`.
    /// (The first draft justified it with "what a text field hands over after a paste" — there
    /// is no such field in `Sources/`; see the reach paragraph at the top. The trim on the
    /// READER side is therefore forward-looking, and the day #522 adds the field it is exactly
    /// the case that arrives.)
    func testYourOwnStampIsNotShown() {
        XCTAssertNil(take(artist: "E~").attribution(besideOwnName: "E~"))
        XCTAssertNil(take(artist: "  E~ ").attribution(besideOwnName: "E~"))
        XCTAssertNil(take(artist: "E~").attribution(besideOwnName: "\n E~  "))
    }

    /// ⚠️ COUNTERWEIGHT, and the one a later "tidy-up" is most likely to break. An empty stamp
    /// states NO artist (every file written before the field existed decodes to `""` through the
    /// decoder's `?? ""`). Substituting the `E~` brand mark there would attribute a stranger's
    /// take to THIS device — the fabricated-detail defect (#424/#426/#433/#461) aimed at a
    /// person. Absent is not default (#493/#494).
    func testAnAbsentStampInventsNobody() {
        XCTAssertNil(take(artist: "").attribution(besideOwnName: "E~"))
        XCTAssertNil(take(artist: "   ").attribution(besideOwnName: "E~"))
        XCTAssertNil(take(artist: "").attribution(besideOwnName: ""))
    }

    /// ⚠️ COUNTERWEIGHT for the compare itself. Exact after trimming, which ERRS TOWARD SHOWING,
    /// and that direction is chosen: showing a credit that happens to be yours is noise; hiding
    /// one that is not is a silent claim of authorship. A later switch to
    /// `caseInsensitiveCompare` or a diacritic-folding compare trades a truth property for a
    /// cosmetic one, so it must be a decision and not a refactor.
    func testTheCompareErrsTowardShowing() {
        XCTAssertEqual(take(artist: "e~").attribution(besideOwnName: "E~"), "e~")
        XCTAssertEqual(take(artist: "Mira").attribution(besideOwnName: "Mirá"), "Mira")
    }

    /// The credit survives the path a take actually travels between two people: the ONE shared
    /// document format (#519) out, `JSONDecoder` back in. Without this the field could round-trip
    /// in the library and still be dropped by the document the Import door reads.
    func testTheStampSurvivesTheSharedDocument() throws {
        let sent = take(artist: "Mira")
        let received = try JSONDecoder().decode(Project.self, from: sent.sharedDocumentData())
        XCTAssertEqual(received.artist, "Mira")
        XCTAssertEqual(received.attribution(besideOwnName: "E~"), "Mira")
        XCTAssertNil(received.attribution(besideOwnName: "Mira"))
    }

    // MARK: - The wiring (source scans — see the limit at the top of this file)

    /// THE REGRESSION. The library row must ask the decision, with the reader's own name taken
    /// from the LIVE `SessionContext` rather than a copy.
    func testTheLibraryRowAsksForTheCredit() throws {
        let row = try declarationBody(of: "private func projectRow(_ p: Project) -> some View {",
                                      in: studioView)
        XCTAssertTrue(row.contains("p.attribution(besideOwnName: session.artistName)"), """
            The library row no longer asks `Project.attribution(besideOwnName:)` with the live \
            session name. Every take carries a stamp and nothing else in the app reads it, so \
            dropping this line returns `artist` to being a field that round-trips and is never \
            seen — the exact state #521 exists to end (#494's `modeRaw` shape).
            """)
    }

    /// ⚠️ COUNTERWEIGHT (#343). A row that asks for a credit nobody stamps shows nothing, forever,
    /// while every assertion above stays green. This pins the ONE write site.
    func testTheSaveSiteStillStampsTheArtist() throws {
        let save = try declarationBody(
            of: "private func currentProject(named name: String? = nil) -> Project {",
            in: studioView)
        XCTAssertTrue(save.contains("artist: session.artistName"), """
            `currentProject()` no longer stamps the artist. The credit line is then dead code on \
            every take this build writes, and no other assertion in this file would notice.
            """)
    }

    /// ⚠️ COUNTERWEIGHT for the premise that makes the difference-gate QUIET rather than noisy.
    /// On an untouched install every take says `E~`, so the credit shows on nothing until a take
    /// really does come from elsewhere. Drop this migration and a fresh install starts stamping
    /// `""` (absent — invisible) or `Echoel` (a second name for the same person, visible on every
    /// row), and the line becomes chrome the reader learns to skip.
    ///
    /// ⛔ THIS WAS A SOURCE SCAN AND IS NOW BEHAVIOUR, because the scan could go RED ON CORRECT
    /// CODE (#364). It matched the verbatim `switch`-case text, so an `if`-chain rewrite that
    /// preserved the fact exactly would have failed it — and a guard that forbids correct work
    /// is how guards get deleted. The behavioural form is immune to any rewrite and strictly
    /// stronger; the injectable `defaults:` that makes it possible has been in this bundle since
    /// `ResetSoundClearsWhatTheLaunchLineReportsTests`.
    func testTheDefaultArtistIsStillTheBrandMark() throws {
        for stored in [nil, "", "Echoel"] as [String?] {
            let defaults = try scratchDefaults()
            if let stored { defaults.set(stored, forKey: artistKey) }
            XCTAssertEqual(SessionContext(defaults: defaults).artistName, "E~", """
                A fresh session on stored artist \(stored.map { "\"\($0)\"" } ?? "«none»") \
                reports something other than the `E~` brand mark. #521's credit line shows only \
                when the stamp DIFFERS from the reader's name, so this migration is what keeps \
                it silent on an untouched install — without it every library row grows a line \
                the reader learns to skip.
                """)
        }
        // And a name the user really chose must survive — otherwise the migration above would be
        // "always E~", which is a different (and much worse) fact wearing the same green tick.
        let defaults = try scratchDefaults()
        defaults.set("Mira", forKey: artistKey)
        XCTAssertEqual(SessionContext(defaults: defaults).artistName, "Mira",
                       "A stored artist name is no longer honoured — the migration swallowed it.")
    }

    // ⛔ `testNothingLetsYouNameYourselfYet` STOOD HERE AND IS DELETED BY #522 — deliberately,
    // and this note is its receipt. It swept `Sources/` for any writer of
    // `SessionContext.artistName` and asserted there were none, pinning the #506 "mechanism with
    // no producer" state so the door could not arrive silently. The door arrived; the assertion
    // did its job and went red exactly as designed (#456/#505), and its own failure message
    // instructed the deletion together with the three prose sites that described the feature as
    // unreachable — all three moved in this same commit. Keeping a weakened version ("at most
    // one writer") would be a guard that no longer states any decision.
    //
    // Its successor is `Tests/CISmoke/YouCanNameYourselfTests.swift`, which asserts the opposite
    // fact: the door EXISTS, is mounted, and stores through the one transform that keeps
    // `artistName` from ever becoming `""`.

    /// ⚠️ COUNTERWEIGHT: the credit is a THIRD line, not a replacement. The two lines that were
    /// there before must stay — a "simplification" that folded the name or the
    /// style · key · BPM line into the credit would pass every other claim here.
    func testTheRowStillLeadsWithTheNameAndTheSetup() throws {
        let row = try declarationBody(of: "private func projectRow(_ p: Project) -> some View {",
                                      in: studioView)
        XCTAssertTrue(row.contains("Text(p.name)"), "The library row no longer leads with the take's name.")
        // All THREE tokens the message names, not two. The first draft pinned style and BPM and
        // let the KEY through, so a tree that dropped `p.key.shortName` from that line stayed
        // green while the failure text advertised coverage of it (#343/#408): an assertion and
        // its message must describe the same set.
        XCTAssertTrue(row.contains("p.style.displayName")
                        && row.contains("p.key.shortName")
                        && row.contains("BPM"), """
            The library row no longer states style · key · BPM. The credit was added ALONGSIDE \
            that line, never in place of it.
            """)
    }

    // MARK: - Fixtures and source access

    private let studioView = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The stored key for the artist name. A LITERAL on purpose: `SessionContext` keeps its keys
    /// in a `private enum` and exposes only `a4StorageKey`/`keyStorageKeys`, and adding an
    /// `artistStorageKey` beside them would read as "the artist name is part of the reset set",
    /// which the very next doc line there says it deliberately is NOT. The same literal is
    /// already used by `ResetSoundClearsWhatTheLaunchLineReportsTests` in this bundle; if it is
    /// ever renamed, this test goes red rather than silently passing on a key nobody reads.
    private let artistKey = "echoel.artistName"

    private let suiteName = "TheTakeSaysWhoMadeItTests"

    /// A scratch defaults suite, so this file never writes into the process's own defaults —
    /// which is how a test starts depending on the order it runs in.
    private func scratchDefaults() throws -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return try XCTUnwrap(UserDefaults(suiteName: suiteName),
                             "could not open a scratch `UserDefaults` suite")
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func take(artist: String) -> Project {
        Project(name: "Take", styleRaw: "dubTechno", keyRoot: 0, scaleRaw: "minor",
                bpm: 120, modeRaw: "studioLocked", fxCharacterRaw: "auto", loopBars: 8,
                a4Hz: 440, toneSystemID: nil, moodFields: nil, artist: artist,
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
