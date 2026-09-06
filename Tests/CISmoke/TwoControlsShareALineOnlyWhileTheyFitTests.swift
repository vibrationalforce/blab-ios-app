import XCTest

/// #1026 — TWO PARAMETER CONTROLS MAY SHARE A LINE ONLY WHILE THEY FIT.
///
/// THE DEFECT, and it is measured in `EchoelValueField`'s own documentation, not deduced here.
/// A labelled field renders `HStack { Text(label); Spacer(minLength: 8); valueBox }`, and the
/// box is PINNED to `valueWidth` — 150 pt at the default text size, `@ScaledMetric` so it grows
/// with Dynamic Type. That file states the consequence in one sentence: *"A `.frame(width:)` is
/// a pin and does not compress."* Two labelled fields on one line therefore demand roughly
/// `label + 8 + 150` EACH plus the spacing — about 410 pt before the sheet's own padding — on a
/// phone that offers ~369 pt. A vertical `ScrollView` does not clip an over-wide child, it
/// CENTRES it, so the overflow splits between the two edges and the WHOLE sheet reads as
/// shifted: the founder's screenshot of build 452 shows "onnections" for "Connections" and the
/// port boxes running off the right edge, in PORTRAIT.
///
/// ⛔ THE BUILD BEFORE THIS ONE BLAMED THE ORIENTATION, AND THAT WAS WRONG. #1025 read a screen
/// recording, saw rotated frames, and concluded landscape was undesigned. The founder then
/// measured it on the device: *"Queer war doch alles gut. Nur hochkant war nicht passend."*
/// Landscape was fine; portrait was broken. A recording whose frames rotate makes a wrong story
/// look complete — the rows themselves were two greps away the whole time. The recommendation
/// to drop landscape from `Info.plist` is WITHDRAWN. (This paragraph originally ended "#1025's
/// width ceiling STAYS … still right for iPad · Mac · Vision"; the founder deleted the ceiling
/// one build later, so that clause is struck — see the next paragraph. A retraction that leaves
/// a forward-looking claim standing is half a retraction.)
///
/// ⛔ AND THE BUILD AFTER THAT ONE SHIPPED A WIDTH CEILING, WHICH THE FOUNDER ALSO REJECTED
/// (#1027): *"Mache das rückgängig du hast das falsche korrigiert. Ich will adaptive Größe
/// also Bildschirmgröße ausfüllend für alle Ansichten. War nur bei Play with Simulation und
/// routing hochkant über den Bildschirm Rand hinaus."* `EchoelTheme.readableContentWidth`
/// capped a control column at 560 pt and centred it — the OPPOSITE of filling the screen —
/// and `TheLayoutHasAReadableWidthCeilingTests` guarded it. Both are deleted; this file
/// absorbed the one claim of that guard worth keeping (claim 5 below).
///
/// ⭐ TWO WRONG ANSWERS IN A ROW, ONE CAUSE: both came from reading a screen recording instead
/// of measuring the view. The founder's sentence above names the two surfaces exactly —
/// Routing and "Play with Simulation" — and both turn out to be the SAME defect: a row whose
/// children all have floors, given one element more than the width can hold. Routing gets one
/// too many when a second pinned field sits beside the first; the transport row gets one too
/// many when `PulseMonitorMini` adds its `Text("Demo")` tag, which it does ONLY while the
/// source is synthetic. That is why he saw it "nur bei Play with Simulation".
///
/// ⚠️ WHAT THIS PROVES. Source text only: that the three rows go through `ViewThatFits` and that
/// no pair of labelled fields is pinned onto one `HStack` anywhere in `Sources/`. It cannot show
/// that the sheet now fits — that is the founder's next look, and it is the whole point of
/// asking him rather than guessing again.
final class TwoControlsShareALineOnlyWhileTheyFitTests: XCTestCase {

    private static let patchbay = "Sources/Echoelmusic/Studio/PatchbayView.swift"
    private static let field = "Sources/Echoelmusic/Studio/EchoelValueField.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - 1. the helper offers BOTH shapes

    /// A `ViewThatFits` holding only the row fixes nothing — it would pick the row every time.
    /// The stacked alternative IS the repair; the horizontal one is the thing being escaped.
    func testTheHelperOffersARowAndAColumn() throws {
        let code = try code(Self.patchbay)
        XCTAssertEqual(occurrences(of: "private func pairedRow<A: View, B: View>", in: code), 1, """
            `pairedRow` is not declared exactly once in PatchbayView. Zero means the helper \
            moved or was inlined — re-anchor this guard and all three call sites in the same \
            commit (#456).
            """)
        guard let start = code.range(of: "ViewThatFits(in: .horizontal) {") else {
            return XCTFail("""
                `pairedRow` no longer uses `ViewThatFits(in: .horizontal)`. If a different \
                adaptive mechanism replaced it, re-point this claim at that one — do not \
                delete it and leave the overflow unguarded.
                """)
        }
        let body = String(code[start.upperBound...].prefix(300))
        XCTAssertTrue(body.contains("HStack(spacing: spacing)"), """
            `pairedRow`'s first candidate is no longer the horizontal row. `ViewThatFits` takes \
            the FIRST candidate that fits, so the row must come first or the controls stack even \
            on a canvas that could hold them side by side.
            """)
        XCTAssertTrue(body.contains("VStack(alignment: .leading, spacing: spacing)"), """
            `pairedRow` lost its stacked fallback. With only one candidate `ViewThatFits` picks \
            it unconditionally and the pinned boxes overflow again — the defect the founder \
            screenshotted, restored in the shape of a fix.
            """)
    }

    // MARK: - 2. all three overflowing rows go through it

    func testTheThreeRoutingRowsUseTheHelper() throws {
        let code = try code(Self.patchbay)
        XCTAssertEqual(occurrences(of: "pairedRow(spacing:", in: code), 3, """
            PatchbayView no longer routes exactly three rows through `pairedRow`. The three are \
            Port + Universe (every network output), Master + Blackout, and Fixtures + Spacing — \
            measured as the only places in this sheet that put two width-pinned controls on one \
            line. Fewer means one regressed to a bare `HStack`; more is fine ONLY if the new \
            row genuinely pairs two controls, so update this count with its reason (#408).
            """)
    }

    // MARK: - 3. the defect class is gone from the whole tree, not just this file

    /// COUNT, do not reason (#766/#768). The sweep that found these three ran over all of
    /// `Sources/` and returned exactly two `HStack`s with two labelled fields (the third pairs a
    /// field with a Button and needs its own eye). Pinning that at zero turns "I fixed the ones
    /// I saw" into "there are none left", and catches the next one before a founder does.
    func testNoHStackPinsTwoLabelledFieldsSideBySide() throws {
        var offenders: [String] = []
        for url in try sourceFiles() {
            let lines = SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (i, line) in lines.enumerated() where line.contains("HStack(") {
                let indent = line.prefix { $0 == " " }.count
                var fields = 0
                for j in (i + 1)..<min(i + 16, lines.count) {
                    let row = lines[j]
                    let trimmed = row.trimmingCharacters(in: .whitespaces)
                    if trimmed == "}" && row.prefix { $0 == " " }.count <= indent { break }
                    if trimmed.contains("EchoelValueField(label: \"") { fields += 1 }
                }
                if fields >= 2 {
                    offenders.append("\(url.lastPathComponent):\(i + 1) — \(fields) labelled fields")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) `HStack`(s) put two or more LABELLED `EchoelValueField`s on one \
            line. Each labelled field pins its box to `valueWidth` (150 pt, Dynamic-Type-scaled) \
            and a pin does not compress — see the doc on `EchoelValueField.stacksLabel`. Two of \
            them overflow a phone in portrait, and a vertical ScrollView centres the overflow \
            instead of clipping it, so the WHOLE surface reads as shifted (#1026):
            \(offenders.joined(separator: "\n"))
            Wrap them in a `ViewThatFits` row/column pair — `PatchbayView.pairedRow` is the shape.
            """)
    }

    // MARK: - 4. COUNTERWEIGHT — the premise this whole file rests on

    /// If the box ever stops being pinned, these three rows would fit on their own and the
    /// helper becomes ceremony. That would be good news; it must not be SILENT news, because
    /// this file's reasoning and PatchbayView's comment both quote the pin as fact.
    func testTheFieldStillPinsItsBox() throws {
        let code = try code(Self.field)
        XCTAssertTrue(code.contains(".frame(width: pinnedBoxWidth)"), """
            `EchoelValueField` no longer pins its value box to `pinnedBoxWidth`. THAT MAY BE AN \
            IMPROVEMENT — a compressible box would make #1026's three `pairedRow`s unnecessary. \
            But it is a change of premise: this guard, `PatchbayView.pairedRow`'s doc comment and \
            `EchoelValueField.stacksLabel`'s doc all argue from the pin. Re-judge all three in \
            the same commit (#456) instead of letting them describe a layout that is gone.
            """)
        XCTAssertTrue(code.contains("@ScaledMetric(relativeTo: .body) private var valueWidth"), """
            `valueWidth` is no longer a `@ScaledMetric`. The overflow gets WORSE with Dynamic \
            Type precisely because the pin scales; if the width became fixed, the arithmetic in \
            this file's header is stale and must be re-derived, not re-quoted.
            """)
    }

    // MARK: - 5. the transport row wraps instead of overflowing

    /// The second surface the founder named. `startControlRow`'s LINE 1 has four children, no
    /// `Spacer`, and a floor under every one of them — it is the row with the least slack in
    /// the app. `PulseMonitorMini` adds a `Text("Demo")` tag while the source is synthetic, and
    /// that one extra element is what pushed it past the edge.
    func testTheTransportLineWrapsWhenItCannotFit() throws {
        let studio = try code(Self.studio)
        XCTAssertEqual(occurrences(of: "private var transportLine1: some View", in: studio), 1, """
            `transportLine1` is not declared exactly once. It is the transport row's adaptive \
            form; if it was inlined back into `startControlRow` the simulation's "Demo" tag \
            pushes the row off the right edge again (#1027).
            """)
        guard let start = studio.range(of: "private var transportLine1: some View") else { return }
        let body = String(studio[start.upperBound...].prefix(700))
        XCTAssertTrue(body.contains("ViewThatFits(in: .horizontal)"), """
            The transport row no longer chooses its shape with `ViewThatFits`. A fixed `HStack` \
            is what overflowed; a fixed `VStack` would waste a line whenever it fits. If a \
            different adaptive mechanism replaced it, re-point this claim at that one.
            """)
        XCTAssertTrue(body.contains("let pulse = PulseMonitorMiniLive()"), """
            The pulse tile is no longer built once and reused across both candidates. \
            `PulseMonitorMiniLive` is the LEAF that reads the ~10 Hz camera publisher \
            (10.76.50 freeze law); constructing it separately in each branch puts two live \
            readers in the tree where one belongs.
            """)
    }

    /// COUNTERWEIGHT — the premise that makes claim 5 a real finding rather than a precaution.
    /// If the "Demo" tag ever stops being conditional, the row carries it always and the
    /// founder's "nur bei Play with Simulation" stops describing anything.
    func testTheDemoTagIsStillTheConditionalExtra() throws {
        let header = try code("Sources/Echoelmusic/Studio/HeaderMonitors.swift")
        XCTAssertTrue(header.contains("if synthetic {"), """
            `PulseMonitorMini` no longer gates its "Demo" tag on `synthetic`. That gate is the \
            reason the transport row overflowed ONLY while the simulation played — the whole \
            diagnosis in this file's header rests on it. If the tag became unconditional, the \
            row is now always at its widest and claim 5 protects more than it used to; say so \
            here rather than leaving the reasoning stale (#456).
            """)
    }

    // MARK: - 7. the width ceiling stays deleted

    /// ⛔ INHERITED FROM THE GUARD #1027 DELETED. `TheLayoutHasAReadableWidthCeilingTests`
    /// protected `EchoelTheme.readableContentWidth`; the founder removed the feature, so the
    /// guard went with it (#1024's shape — a red guard on a correct tree is the tangle he
    /// warned about). This claim is the inverse and it is the one worth carrying forward: the
    /// ceiling must not quietly come back, because "it would help on iPad" is exactly the kind
    /// of plausible, future-tense, unmeasured argument that survives a founder's "no".
    func testNoWidthCeilingIsReintroduced() throws {
        for path in [Self.studio,
                     "Sources/Echoelmusic/Studio/WorkspaceView.swift",
                     "Sources/Echoelmusic/Studio/EchoelSheetPanel.swift",
                     "Sources/Echoelmusic/Studio/EchoelTheme.swift"] {
            let body = try code(path)
            for needle in ["readableContentWidth", "readableWidth()"] {
                XCTAssertEqual(occurrences(of: needle, in: body), 0, """
                    `\(needle)` is back in \(path). THIS IS NOT AUTOMATICALLY A BUG — the \
                    founder may have changed his mind, and a wide canvas genuinely may want a \
                    narrower column. But he said the opposite in his own words: "Ich will \
                    adaptive Größe also Bildschirmgröße ausfüllend für alle Ansichten." So it \
                    is HIS call, and reinstating it means pulling the tombstones along in the \
                    same commit: `EchoelTheme`'s ⛔ #1027 block, `WorkspaceView`'s, \
                    `EchoelSheetPanel`'s, and this claim.
                    """)
            }
        }
    }

    // MARK: - helpers

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath:
            root.appendingPathComponent("Sources/Echoelmusic").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    private func code(_ relativePath: String) throws -> String {
        SourceText.codeOnly(try String(contentsOf: try repoRoot().appendingPathComponent(relativePath),
                                       encoding: .utf8))
    }

    private func sourceFiles() throws -> [URL] {
        let sources = try repoRoot().appendingPathComponent("Sources")
        guard let e = FileManager.default.enumerator(at: sources,
                                                     includingPropertiesForKeys: nil) else {
            throw XCTSkip("could not enumerate \(sources.path)")
        }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
