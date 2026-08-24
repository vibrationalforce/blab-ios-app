//  TheStoreTextClaimsOnlyWhatShipsTests.swift
//
//  THE FOURTH SURFACE. A user-visible claim in this repo has four homes — the app's own copy
//  (Swift), `docs/**`, `ContentPipeline/CLAIMS.md`, and `fastlane/metadata`. #496 struck three
//  producerless bio channels (`breathDepth`, `lfHf`, `coherenceTrend`) and left three guards
//  behind it; all three read Swift. #755 found the same claim still shipping on the WEBSITE and
//  guarded that. This file is the fourth home, and it is the one where being wrong is not a
//  stale sentence but an App Store 2.3 rejection — the failure #184 already paid for once by
//  removing twelve false claims from this very text.
//
//  ⛔ WHAT IT CAUGHT ON ITS FIRST RUN (#757). `fastlane/metadata/en-US/description.txt` read
//  "Breath shapes the amplitude envelope and filter movement". The swell half is real
//  (`breathPhase` → `amplitude`, every profile). The filter half rides `breathDepth`, whose two
//  `BioParams` construction sites both pass the literal `0.5`, so the factor is exactly 1.0 on
//  every frame the shipped app can produce. `applyBioReactive` says so at that line in words:
//  *"must not be claimed as live in any user-facing copy."*
//
//  ⭐ AND THE GERMAN LOCALE OF THE SAME LISTING WAS ALREADY HONEST — "Atem formt die
//  Hüllkurve", no filter. Two locales of ONE store listing disagreed, and the wrong one was
//  English, the primary market. That is the sharpest form of the multi-surface lesson: the
//  surfaces are not only different FILES, they are different LOCALES of the same file.
//
//  ⚠️ THE RULE IS PROXIMITY, NOT A WORD-BAN (#364). "Filter" on its own is a TRUE claim here —
//  coherence really does drive `filterCutoff`, and the audited in-app truth table
//  (`AlwaysOnBioChannel.shapedParameters`) says so. Banning the word would forbid honest copy.
//  What is false is specifically BREATH attached to a FILTER, so that is what is measured: the
//  two words inside one short window, in either language.
//
//  ⛔ #768 — THE GUARD READ SIX OF THE TEN FILES, AND THE FOUR IT SKIPPED WERE CARRYING A CLAIM
//  #758 BELIEVED IT HAD FIXED. `release_notes.txt` still said "numeric entry for every
//  parameter" in BOTH locales three weeks after the same sentence was narrowed in
//  `description.txt`. Third instance of one lesson in three cycles — #765 the app's own copy,
//  #766 the routing screen, this one two leaves of the directory the file already walks.
//  **The enumeration is the defect, not the care taken over it.** The walk now covers all five
//  leaves; `keywords.txt` is the sharper of the two additions, because ASO is exactly where an
//  unbuilt capability gets stuffed for reach.
//
//  ⭐ GRADING FOR #768 (parent `5cb1506`). Claim 4 is a REGRESSION — red on the parent in two
//  files, green here. Claim 3 (removed capabilities) is PREVENTIVE and green on both trees; all
//  twenty-three of its needles score zero either way, and booking it as a catch would be the
//  flattering direction (#464). It is justified anyway by a failure this repo has already paid
//  for: #184 removed TWELVE false capability claims from this exact text and nothing has
//  guarded the return since. Claims 1 and 2 are unchanged counterweights.
//
//  ⛔ AND CLAIM 5 DID NOT COMPILE ON ITS FIRST PUSH (#792). It wrote `file.rel`; the tuple
//  `storeCopy()` returns is labelled `path`, and the four sibling claims in THIS FILE all say
//  `file.path`. I took the name from a message inside the helper — where `rel` is a local — and
//  never read the signature four lines above it. **The correct label was in the same file, four
//  times.** That is #783's rule (a label is COPIED from source, never retyped) applied to an
//  API member instead of a UI string, and `dead-needles.py` cannot catch it: it resolves
//  `Self.x` references, not tuple members. The gate that caught it is `Build for Testing`, which
//  is exactly what it is for — but it costs a full cycle, so read the signature, not the
//  neighbouring prose.
//
//  ⭐ GRADING FOR #791 (parent `278fd2d`). Claim 5 is a REGRESSION, red on the parent in BOTH
//  locales, and it is the FIRST claim in this file that points the other way. Every other claim
//  here asks *is something SOLD that does not ship* — the 2.3 direction. Claim 5 asks *does
//  something SHIP that is not sold*, and found it: CONNECT listed Art-Net and not sACN while the
//  PRIVACY block of the same file named "Art-Net or sACN". A listing contradicting itself about
//  a live, doored capability, in the block a lighting professional reads.
//
//  ⛔ AND THE FIRST DRAFT OF CLAIM 5 CAUGHT ONLY ENGLISH. It split on "privacy"/"datenschutz";
//  the German listing's heading is **PRIVATSPHÄRE**, so de-DE hit a `continue` and was skipped
//  IN SILENCE while carrying the identical defect. Two lessons, both already law here and both
//  paid for again inside one cycle: a hand-typed needle for a corpus nobody looked at
//  (#679/#738 — the headings are now `grep`ed, and the command is next to the list), and a
//  guard that cannot find its anchor must FAIL rather than pass (#454 — the skip is now a
//  separate assertion with its own message). The file header above already warned that the
//  surfaces are LOCALES of one file; the draft still typed one locale's word.
//
//  ⭐ GRADING FOR #769 (parent `f8c23fb`). STRUCTURAL, no regression caught: the locale walk
//  now READS `fastlane/metadata/` instead of naming two directories, so every claim already in
//  the file follows a third locale automatically. Green on both trees — booking it as a catch
//  would be the flattering direction (#464). Justified by two incidents rather than a hunch:
//  #768 (three of five leaves hand-typed, in THIS file) and the note in
//  `WebsitePagesAreFindableAndHonestTests` recording that "only en-US was scanned until the
//  de-DE notes were caught stale a week after the roster changed" — where the repair was to
//  type the second locale in, which leaves the third to be skipped in the same silence.
//
//  ⚠️ WHAT IT CANNOT DO. It reads the text that is COMMITTED, not what is live on App Store
//  Connect — a claim edited in the web UI never passes through this file. And it judges three
//  named channels, not truthfulness in general; a fresh false claim about something else walks
//  straight past it.
import XCTest

final class TheStoreTextClaimsOnlyWhatShipsTests: XCTestCase {

    /// Every locale's long-form and short-form store copy, by path.
    ///
    /// ⚠️ ANCHOR, NOT A CONVENIENCE (#454). A missing or empty file FAILS rather than yielding
    /// an empty set that every assertion below would pass vacuously. The whole point of this
    /// file is that nobody was reading this text; a guard that silently reads nothing would be
    /// the same defect wearing a green tick.
    private func storeCopy() throws -> [(path: String, text: String)] {
        let root = try repoRoot()
        var out: [(String, String)] = []
        // ⛔ AND THE LOCALES WERE HAND-TYPED TOO (#769) — the same defect as the leaf list
        // above, one level out, and #768 repaired only the inner half. `fastlane/metadata/`
        // is a DIRECTORY: a third locale would be skipped in silence, and its false claim
        // would ship unguarded. `WebsitePagesAreFindableAndHonestTests` had already paid for
        // exactly this once — its own comment records that "only en-US was scanned until the
        // de-DE notes were caught stale a week after the roster changed", and the repair then
        // was to type the second locale in. That repair does not scale; this one does.
        for locale in try localeDirectories() {
            // ⛔ THIS LIST HELD THREE LEAVES AND THE DIRECTORY HAS FIVE (#768). `keywords.txt`
            // and `release_notes.txt` were unread — and `release_notes.txt` was carrying a claim
            // #758 believed it had corrected: "numeric entry for every parameter", in BOTH
            // locales, three weeks after the same sentence was fixed in `description.txt`. The
            // rule is app-wide and reads "every adjustable NUMERIC parameter"; a named choice
            // (filter mode, delay mode, harmony interval) is a `Picker` by design and by an
            // explicit founder ask. **Keywords are the sharper omission of the two**: ASO is
            // exactly where an unbuilt capability gets stuffed for reach, and it is submitted
            // with the build like any other metadata.
            for leaf in ["description.txt", "promotional_text.txt", "subtitle.txt",
                         "keywords.txt", "release_notes.txt"] {
                let rel = "fastlane/metadata/\(locale)/\(leaf)"
                let url = root.appendingPathComponent(rel)
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    XCTFail("""
                        \(rel) is missing or empty, so this guard checked nothing. The App Store \
                        text is the surface where a false capability claim is a 2.3 rejection; \
                        if the metadata layout moved, point this test at its new home in the \
                        same commit.
                        """)
                    continue
                }
                out.append((rel, text))
            }
        }
        XCTAssertFalse(out.isEmpty, "no store copy was read at all — the walk is broken")
        return out
    }

    /// 5 — REGRESSION, and the FIRST claim in this file that points the other way (#791).
    /// Every other claim here asks "is something sold that does not ship". This one asks
    /// "does something ship that is not sold", and it found one in the shipped text: the
    /// CONNECT block listed Art-Net and NOT sACN, while the PRIVACY block of the SAME file
    /// named "Art-Net or sACN light output". A store description that contradicts itself, in
    /// both locales, about a capability that is live and doored (`sacn.out` route → the
    /// routing panel's target fields → `SACNSender.start(subscribing:)`).
    ///
    /// ⭐ WHY AN UNDER-CLAIM IS WORTH GUARDING AT ALL, given 2.3 punishes the opposite: the
    /// reader this block is written for is a lighting professional, and sACN is what a large
    /// rig actually speaks (it has the priority field Art-Net lacks). Someone scanning CONNECT
    /// concludes the app cannot talk to their console. #184 removed twelve over-claims from
    /// this text and nobody has ever looked the other way; #788 found the same shape one
    /// surface out, in the integrator docs.
    ///
    /// THE RULE IS SELF-ANCHORING, which is what keeps it from going stale: whatever network
    /// output the PRIVACY block names as sending bio values outward must also appear in the
    /// CONNECT block. No hand-typed capability list to maintain — the text checks itself, so a
    /// FIFTH output added tomorrow is covered without touching this file.
    ///
    /// ⚠️ #364: this does not mandate wording or force a capability to be sold. Removing sACN
    /// from BOTH blocks would pass — that is a legitimate copy decision. What it forbids is the
    /// two blocks disagreeing.
    /// Lower-cased privacy headings across the shipped locales. ⛔ THE FIRST DRAFT OF THIS CLAIM
    /// ASSUMED THE GERMAN ONE WAS "DATENSCHUTZ" AND IT IS "PRIVATSPHÄRE" — a hand-typed needle
    /// for a corpus nobody looked at, the #679/#738 shape. Measured from the files, not recalled:
    /// `grep -n '^[A-ZÄÖÜ][A-ZÄÖÜ ]\{3,\}$' fastlane/metadata/*/description.txt`.
    private static let privacyHeadings = ["privacy", "privatsphäre", "datenschutz"]

    /// Words that make an "MPE" line say which WAY it goes. Deliberately short and literal:
    /// a bare "out" would also match "routing" and "about", so the tokens are the whole word
    /// forms the copy actually uses. Re-derive with `git grep -i mpe -- fastlane/metadata`.
    private static let mpeDirectionWords = ["output", "mpe out", "ausgang", "raus an"]

    /// The exact phrasings that claim the half that does not exist. Adjacent phrases, not
    /// "any input word": "MPE output ... the input side stays plain MIDI notes" is honest copy
    /// and must not trip (#486 — one finding per real defect, not one per nearby word).
    private static let mpeInputClaims = ["mpe input", "mpe-eingang", "mpe eingang", "mpe in from"]

    /// Phrasings that SELL the voice capture (#592a/#593). Both locales, both the long-form
    /// description and the release notes — the door is the Sound panel's "Voice timbre" row.
    private static let voiceCaptureClaims = ["voice timbre", "voice becomes the instrument",
                                             "stimmfarbe", "stimme wird die klangfarbe"]

    /// The qualifier that must travel with it. Measured at the source, not assumed:
    /// `SynthPatch` embeds `voiceProfileTaps` — about 64 floats of max-normalized spectral
    /// envelope — and its own comment states "NO AUDIO is persisted here". Neither
    /// `VoiceAnalyzer` nor `VoiceCaptureEngine` touches `AVAudioFile`, `FileManager` or
    /// `write(to:)`. So the honest sentence is "measured, not recorded", and the envelope
    /// itself IS stored inside a saved patch — which is why the store line says both halves.
    private static let voiceNoAudioQualifiers = ["no audio recorded", "no audio is recorded",
                                                  "never recorded", "nie aufgenommen",
                                                  "kein ton wird aufgenommen", "nicht aufgenommen"]

    func testEveryOutputThePrivacyBlockNamesIsAlsoSold() throws {
        let outputs = ["osc", "adm-osc", "art-net", "sacn"]
        var offenders: [String] = []
        var unreadable: [String] = []
        for file in try storeCopy() {
            let flat = file.text.lowercased()
            guard flat.contains("sacn") || flat.contains("art-net") else { continue }
            guard let heading = Self.privacyHeadings.first(where: { flat.contains($0) }),
                  let split = flat.range(of: heading) else {
                // ⛔ THIS WAS A `continue` FOR ONE DRAFT, which is the #454 defect this repo
                // names most often: a guard that cannot find its boundary must FAIL, not
                // quietly pass the file. It cost a real miss INSIDE this cycle — the draft
                // looked for "privacy"/"datenschutz", the German listing's heading is
                // PRIVATSPHÄRE, so de-DE was skipped in silence while carrying the identical
                // defect en-US was caught for.
                unreadable.append(file.path)
                continue
            }
            let sold = String(flat[..<split.lowerBound])
            let warned = String(flat[split.upperBound...])
            for name in outputs where warned.contains(name) && !sold.contains(name) {
                offenders.append("\(file.path): \(name)")
            }
        }
        XCTAssertTrue(unreadable.isEmpty, """
            No privacy heading found in \(unreadable.joined(separator: ", ")), so this claim could
            not locate the boundary between what the listing SELLS and what it WARNS about — and
            a guard that cannot find its anchor reports a pass it did not earn (#454). Known
            headings: \(Self.privacyHeadings). Add a renamed one here in the SAME commit.
            """)
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) network output(s) are named in the PRIVACY block but never in the
            CONNECT block: \(offenders.joined(separator: ", ")).
            The listing contradicts itself: it warns a reader that this output sends bio values
            outward, while the capability list says the app does not have it. A lighting
            professional scanning CONNECT for their protocol concludes it is unsupported. If the
            capability was deliberately DROPPED, remove it from the privacy sentence too — this
            claim forbids the disagreement, not either choice (#364).
            """)
    }

    /// Breath must not be sold as driving a filter, in any locale.
    ///
    /// The window is 80 characters because these are bullet lines, not paragraphs: the English
    /// offender put the two words 34 apart on one line. A window that spans paragraphs would
    /// pair an honest coherence→filter bullet with an honest breath→amplitude bullet and fail
    /// on correct copy.
    func testBreathIsNotSoldAsDrivingAFilter() throws {
        let breath = ["breath", "atem"]
        let filter = ["filter"]
        var offenders: [String] = []
        for file in try storeCopy() {
            let flat = file.text.lowercased()
            for b in breath {
                var search = flat.startIndex..<flat.endIndex
                while let hit = flat.range(of: b, range: search) {
                    let lo = flat.index(hit.lowerBound, offsetBy: -80, limitedBy: flat.startIndex)
                        ?? flat.startIndex
                    let hi = flat.index(hit.upperBound, offsetBy: 80, limitedBy: flat.endIndex)
                        ?? flat.endIndex
                    let window = String(flat[lo..<hi])
                    if filter.contains(where: { window.contains($0) }) {
                        offenders.append("\(file.path): …\(window)…")
                    }
                    search = hit.upperBound..<flat.endIndex
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) place(s) in the store text put breath next to a filter: \
            \(offenders.prefix(2).joined(separator: " | ")).

            Measured: the filter half of that claim rides `breathDepth`, and BOTH `BioParams` \
            construction sites pass the literal `0.5` — the factor is exactly 1.0 on every \
            frame the shipped app can produce. `applyBioReactive` says at that line that it \
            "must not be claimed as live in any user-facing copy". Breath drives the AMPLITUDE \
            swell; the filter cutoff belongs to COHERENCE. If a real producer for breath depth \
            appears, wire it, then change the copy and this test together.
            """)
    }

    /// The three producerless channels must not be named as drivers anywhere in the store text.
    ///
    /// ⚠️ Unlike the website guard (#755), there is no "not mapped yet" row to protect here —
    /// store copy sells what ships, it does not carry a roadmap table. So the channel NAMES are
    /// banned outright in this surface, and that is deliberate rather than an oversight: if the
    /// text ever wants to say "breath depth is coming", it should say it in the release notes,
    /// which this guard does not read.
    func testTheProducerlessChannelsAreNotNamedAsDrivers() throws {
        let dead = ["breath depth", "atemtiefe", "lf/hf", "lf-hf", "coherence trend",
                    "kohärenz-trend", "spectral tilt", "spektrale neigung"]
        var offenders: [String] = []
        for file in try storeCopy() {
            let flat = file.text.lowercased()
            for term in dead where flat.contains(term) {
                offenders.append("\(file.path): \(term)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            The store text names a bio channel that drives nothing: \
            \(offenders.joined(separator: ", ")). All three are pinned to literals at both \
            `BioParams`/`PolyBioParams` construction sites (`breathDepth: 0.5`, `lfHf: 0.5`, \
            `coherenceTrend: 0`). The audited in-app truth table is \
            `AlwaysOnBioChannel.shapedParameters`: coherence → filter cutoff · brightness · \
            harmonicity · noise; HRV → brightness; heart rate → vibrato · brightness; \
            breath phase → amplitude. Claim from that list.
            """)
    }

    /// Capabilities this repo has REMOVED must not reappear in the listing.
    ///
    /// ⛔ THE FAILURE THIS PREVENTS ALREADY HAPPENED HERE, TWELVE TIMES. #184 removed twelve
    /// false capability claims from this exact text, and #158/#192 spent two whole cycles taking
    /// ONE of them off the website. Nothing has guarded the return since. On the App Store a
    /// false capability claim is not a stale sentence — it is a 2.3 rejection of the build.
    ///
    /// ⚠️ GRADED HONESTLY (#464): this is PREVENTIVE, not a catch. All twenty-two needles score
    /// zero on this tree and on the parent; the slice's real finding is the release-notes line
    /// fixed alongside it. Booking a green preventive guard as a caught regression is the
    /// flattering direction.
    ///
    /// ⚠️ WHY THESE WORDS AND NOT MORE (#364). Every needle names a capability that provably does
    /// not exist: the AUv3 target was deleted (#121 Slice 2), RTMP was never linked
    /// (`Package.swift` has no dependencies), the drum engine and step grid went with #166/#167,
    /// the note editor with #475, video EDIT with #121 Slice 3, and multitrack is built but
    /// flag-gated off and doorless. Deliberately NOT banned, and each for a measured reason:
    ///   · "trim" — `SingleExport.trimLengthSeconds` is real, so a loop-trim claim could be
    ///     honest; only VIDEO trim is gone, and the word alone cannot tell them apart.
    ///   · "timeline", "arrangement", "clips", "video" — ordinary words with honest uses
    ///     ("video capture" ships: `VisualRecorder` plus an mp4 share sheet).
    ///   · "sampler" — `SamplerVoice` exists and sounds.
    ///   · "MPE" — MPE **out** is real and switchable (#713); only the input half is absent.
    ///     ⛔ This note ended "and the store text already says 'MIDI note input and output'
    ///     without claiming it" — true until #794, which ADDED an MPE-output line to both
    ///     locales. The word is now guarded by claim 6, not merely left unbanned here.
    /// A ban that catches honest copy gets deleted, and the law goes with it.
    func testNoRemovedCapabilityIsSoldAgain() throws {
        let removed = [
            "auv3", "audio unit",                                   // target deleted 2026-07-24
            "rtmp", "live stream", "livestream", "broadcast", "srt", // never linked
            "multitrack", "multi-track", "mehrspur",                 // built, flag-gated off, doorless
            "beat maker", "beatmaker", "drum machine", "drumcomputer",
            "step sequencer", "step-sequencer", "schrittsequenzer",  // #166/#167
            "piano roll", "pianoroll", "note editor", "noten-editor", // #475
            "video edit", "videoschnitt"                             // #121 Slice 3
        ]
        var offenders: [String] = []
        for file in try storeCopy() {
            let flat = file.text.lowercased()
            for term in removed where flat.contains(term) {
                offenders.append("\(file.path): \"\(term)\"")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            The App Store listing names a capability this repo removed: \
            \(offenders.joined(separator: ", ")).

            #184 already removed twelve such claims from this text; a false capability claim \
            here is a 2.3 rejection, not a stale sentence. If one of these was genuinely built, \
            that is welcome — delete its needle in the SAME commit as the code, and pull \
            `ContentPipeline/CLAIMS.md`, `docs/**` and the app's own copy along with it. Do not \
            delete the needle to get the gate green.
            """)
    }

    /// "Numeric entry for every parameter" overstates a rule that says NUMERIC on purpose.
    ///
    /// ⛔ WHAT IT CAUGHT (#768). #758 corrected this sentence in `description.txt` for both
    /// locales. `release_notes.txt` kept the un-narrowed form in BOTH — "numeric entry for every
    /// parameter" / "numerische Eingabe für jeden Parameter" — because the guard walked three of
    /// the directory's five leaves. The claim is false as written: `EchoelValueField` covers
    /// every adjustable NUMERIC parameter, and CLAUDE.md's own rule shouts *READ THE WORD
    /// "NUMERIC"* — the filter mode, the delay mode and the two harmony intervals are `Picker`s,
    /// the last by an explicit founder ask ("keine semitone Schritte sondern sinnvolle
    /// harmonische"). A blind user choosing the app on "numeric entry for every parameter" finds
    /// menus where the sentence promised a keypad.
    ///
    /// ⚠️ THE NEEDLE CANNOT HIT THE CORRECTED SENTENCE. "every numeric parameter" does not
    /// contain the substring "every parameter" — the word sits between — and the same holds for
    /// "jeden numerischen Parameter" against "jeden Parameter". Checked before it was written,
    /// because a ban that also forbids the repair is the #491 shape.
    func testNumericEntryIsNotClaimedForEveryParameter() throws {
        let overclaims = ["every parameter", "each parameter",
                          "jeden parameter", "alle parameter"]
        var offenders: [String] = []
        for file in try storeCopy() {
            let flat = file.text.lowercased()
            for term in overclaims where flat.contains(term) {
                offenders.append("\(file.path): \"\(term)\"")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            The store text promises numeric entry for EVERY parameter: \
            \(offenders.joined(separator: ", ")).

            The app-wide rule is "every adjustable NUMERIC parameter" and says so in capitals: a \
            parameter whose values have NAMES is a `Picker` by design — filter mode, delay mode, \
            and the two harmony intervals, that last one by an explicit founder ask. Write \
            "every numeric parameter" (the correction #758 already made in `description.txt`), \
            and keep the two locales in step.
            """)
    }

    /// Claim 6 (#794) — "MPE" in the store text always carries its DIRECTION.
    ///
    /// MPE **out** is real and switchable (#713): the zone is announced, notes are spread over
    /// member channels 2-16, and each carries glide (14-bit bend), slide (CC 74) and pressure.
    /// MPE **in** is not: `MIDIBusPublisher` parses MPE traffic but tells no zones apart, and
    /// `BioReactiveSynthVoice.apply(controller:)` runs into a single `break` for slide, air and
    /// channel pressure — the three dimensions that make MPE MPE (#548). Channel pressure is not
    /// merely unwired: `MIDIEventParse` has no case for 0xD0/0xD at all, so the byte never
    /// arrives (#770). A directionless "MPE" therefore promises exactly the missing half.
    /// `ContentPipeline/CLAIMS.md` section 6 states the rule; this is the store text's copy of it.
    ///
    /// ⚠️ GRADED HONESTLY (#464): PREVENTIVE, and until this very commit it was also VACUOUS —
    /// `git grep -i mpe -- fastlane/metadata` returned NOTHING, so a guard written a day earlier
    /// would have scanned a corpus with no occurrence of its own subject and gone green on air.
    /// The slice's real finding is the UNDER-claim it repairs (the fourth in a row: #788 the
    /// integrator tables, #791 sACN in the store text, #793 the claim ledger, now this) — a
    /// shipped, doored capability that never reached the surface that SELLS it. An under-claim
    /// is invisible to every check that looks for false statements, which is why nobody looked.
    /// The guard earns its keep only because the same commit creates the line it protects.
    ///
    /// ⚠️ WHY A DIRECTION WORD AND NOT A BAN (#364). Banning "mpe" outright would forbid the
    /// honest half and delete a live selling point; a ban that catches correct copy gets deleted,
    /// and the law goes with it. And the day someone builds MPE input — starting at
    /// `MIDIEventParse`, not at the bus publisher — the second assertion here must be lifted in
    /// the SAME commit, together with `ContentPipeline/CLAIMS.md` section 6 and
    /// `docs/architecture.html`. Its message says so rather than leaving it to be discovered.
    func testMPEIsNeverWrittenWithoutItsDirection() throws {
        var directionless: [String] = []
        var inputClaims: [String] = []
        for file in try storeCopy() {
            let lines = file.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, raw) in lines.enumerated() {
                let line = raw.lowercased()
                guard line.contains("mpe") else { continue }
                if !Self.mpeDirectionWords.contains(where: { line.contains($0) }) {
                    directionless.append("\(file.path):\(index + 1)")
                }
                for phrase in Self.mpeInputClaims where line.contains(phrase) {
                    inputClaims.append("\(file.path):\(index + 1) — \"\(phrase)\"")
                }
            }
        }
        XCTAssertTrue(directionless.isEmpty, """
            The store text writes "MPE" without saying which way it goes: \
            \(directionless.joined(separator: ", ")).

            MPE OUT ships and is switchable (#713). MPE IN does not exist (#548/#770), so a \
            directionless "MPE" sells the half that is missing — and a wrong capability claim \
            in this text is an App Store 2.3 rejection, not a stale sentence. Write \
            "MPE output" / "MPE-Ausgang", never a bare "MPE". The rule and its reason live in \
            `ContentPipeline/CLAIMS.md` section 6.
            """)
        XCTAssertTrue(inputClaims.isEmpty, """
            The store text claims MPE INPUT: \(inputClaims.joined(separator: ", ")).

            `MIDIEventParse` has no case for channel pressure in either protocol branch, and \
            the voice runs into a single `break` for slide, air and pressure (#548/#770). If \
            that changed, this assertion is WRONG and must be lifted in the same commit as the \
            parser work — together with `ContentPipeline/CLAIMS.md` section 6, \
            `docs/architecture.html` and the MPE line in `docs/dev/FEATURE_MATRIX.md`.
            """)
    }

    /// Claim 7 (#795) — the voice capture is never sold without its no-audio qualifier.
    ///
    /// A microphone feature is the one place where a vague sentence costs more than a wrong
    /// one: it drives the privacy nutrition label and the 2.3 review, and a reader assumes the
    /// worst reading. What actually happens is narrow and provable — a held tone is reduced to
    /// about 64 floats of spectral envelope, no audio is written anywhere, and a saved patch
    /// carries that envelope under a name the player gives it. The claim and the qualifier must
    /// therefore live in the SAME file: a later edit that moves the selling line into a
    /// different leaf and leaves the qualifier behind is exactly the failure this catches.
    ///
    /// ⚠️ GRADED HONESTLY (#464): PREVENTIVE, and GREEN ON BOTH TREES — the parent's release
    /// notes already carried claim and qualifier together, and #795 only adds a second, equally
    /// qualified home. It catches nothing today and is booked as catching nothing.
    ///
    /// ⭐ The slice's real finding is again an UNDER-claim, the fifth in a row: "your voice
    /// becomes the instrument's timbre" lived ONLY in `release_notes.txt`, in both locales.
    /// Release notes are per-version and scroll away; `description.txt` is the permanent sales
    /// surface, and it did not mention the voice at all. The measurement that found it was a
    /// directory-driven sweep of the ✅ rows in `ContentPipeline/CLAIMS.md` against the whole
    /// metadata corpus — not another lucky read.
    ///
    /// ⛔ AND THAT SWEEP PRODUCED TWO FALSE ALARMS I ALMOST ACTED ON. Probing the German text
    /// for "generativ" and "pitch" reported both missing; the German copy says "erzeugt" and
    /// "Kammerton" and is complete. A probe measures the WORD, not the capability (#679/#738) —
    /// the two hits were read against the source before either was called a gap.
    func testTheVoiceCaptureAlwaysCarriesItsNoAudioQualifier() throws {
        var unqualified: [String] = []
        for file in try storeCopy() {
            let flat = file.text.lowercased()
            guard Self.voiceCaptureClaims.contains(where: { flat.contains($0) }) else { continue }
            if !Self.voiceNoAudioQualifiers.contains(where: { flat.contains($0) }) {
                unqualified.append(file.path)
            }
        }
        XCTAssertTrue(unqualified.isEmpty, """
            The store text sells the voice capture without saying that no audio is kept: \
            \(unqualified.joined(separator: ", ")).

            `SynthPatch` says it in its own comment — "NO AUDIO is persisted here": what is \
            stored is about 64 floats of spectral envelope, and neither `VoiceAnalyzer` nor \
            `VoiceCaptureEngine` writes a file. A microphone claim without that sentence \
            drives the privacy nutrition label and the 2.3 review on the reader's worst \
            assumption. Keep the qualifier in the SAME file as the claim, in every locale.
            """)
    }

    /// Every locale directory under `fastlane/metadata/`, read rather than assumed.
    ///
    /// ⚠️ ANCHOR (#454): an empty or unreadable directory FAILS. A locale walk that silently
    /// finds nothing would make every claim in this file pass vacuously — the same green-on-
    /// nothing shape the whole file exists to prevent.
    private func localeDirectories() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("fastlane/metadata")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        let locales = names.filter { name in
            var isDir: ObjCBool = false
            let path = base.appendingPathComponent(name).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                && isDir.boolValue
        }.sorted()
        XCTAssertFalse(locales.isEmpty, """
            `fastlane/metadata/` holds no locale directory, so every claim in this file \
            checked nothing. If the metadata layout moved, point this walk at its new home \
            in the same commit.
            """)
        return locales
    }

    // MARK: - file access

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath:
                dir.appendingPathComponent("CLAUDE.md").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        throw NSError(domain: "TheStoreTextClaimsOnlyWhatShips", code: 1, userInfo: [
            NSLocalizedDescriptionKey:
                "could not find the repo root from \(#filePath) — the guard read nothing"
        ])
    }
}
