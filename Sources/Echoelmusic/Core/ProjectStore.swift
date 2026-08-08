// ProjectStore.swift
// Echoel — the saved-projects library. Persists Projects as one JSON array in the
// App Group container (survives relaunch, shared with extensions). Newest first.

import Foundation

@MainActor
@Observable
public final class ProjectStore {

    /// Saved projects, newest first.
    public private(set) var projects: [Project] = []

    @ObservationIgnored private let store: AppGroupStore
    @ObservationIgnored private let fileName = "projects.json"

    public init(store: AppGroupStore = AppGroupStore()) {
        self.store = store
        // Element-tolerant (see AppGroupStore.loadLossyArray): one unreadable project is
        // dropped instead of taking the whole library down with it — the previous decode
        // returned nil for the entire file and the next save wrote the emptied list back.
        // These are re-sorted anyway, so a hole cannot mean anything positional.
        projects = (store.loadLossyArray(Project.self, name: fileName) ?? [])
            .compactMap { $0 }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// Insert or update a project (matched by id), then persist. Returns the saved
    /// project (with a refreshed `savedAt`).
    @discardableResult
    public func save(_ project: Project) -> Project {
        var p = project
        p.savedAt = Date()
        projects.removeAll { $0.id == p.id }
        projects.insert(p, at: 0)
        persist()
        return p
    }

    public func delete(id: UUID) {
        projects.removeAll { $0.id == id }
        persist()
    }

    public func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    // MARK: - Sharing (cross-device / community)

    /// Encode a project to portable, human-diffable JSON for sharing (AirDrop,
    /// Files, Messages) or cross-device transfer. Self-contained: style, key, tempo,
    /// the synth patch, the notes and the drum grid all travel in one document.
    ///
    /// ⛔ THE FORMAT IS NO LONGER DECIDED HERE (#519). It moved to
    /// `Project.sharedDocumentData()`, because this method had ZERO production callers —
    /// measured, not assumed — while the path a user actually reaches (`SharedEchoelProject`,
    /// the `ShareLink` in every library row) printed its own bare `JSONEncoder()`. The
    /// "human-diffable" promise in the line above was made here and broken there. Read that
    /// method for what the decision is and, just as importantly, what it is NOT the decision
    /// for (the on-disk library and the colab wire payload are separate and must stay so).
    ///
    /// ⚠️ THE `Data?` CONTRACT IS UNCHANGED ON PURPOSE. This method's only callers are two
    /// round-trip tests in the non-blocking suite; widening its signature in the same slice
    /// would touch a second surface for no behavioural gain. What a caller LOSES by using
    /// this form rather than the throwing one is the field name inside `EncodingError` —
    /// which is exactly why the reachable share path uses the throwing one.
    public func exportData(_ project: Project) -> Data? {
        try? project.sharedDocumentData()
    }

    /// Import a shared project document. The decoded project gets a FRESH id (so
    /// importing your own export never overwrites the original) and is saved to the
    /// top of the library.
    ///
    /// ⭐ THIS IS THE RECEIVING TWIN OF `Project.sharedDocumentData()` (#520), and it exists
    /// because #519's own prose named a message this app never printed. That doc block says
    /// an empty share "surfaces on SOMEONE ELSE'S device, days later, as `importProject`
    /// returning `nil` — 'not a valid Echoel session'." Measured: that sentence lives in TWO
    /// doc comments and NOWHERE else. `git grep "importFailure\|importError\|showImport"` over
    /// `Sources/` returned nothing; the one production call site discarded the return value
    /// AND ignored `case .failure` entirely. The receiving device said nothing at all — pick a
    /// file, the sheet closes, the library is unchanged, and the only available reading is
    /// "I must have tapped wrong".
    ///
    /// ⚠️ IT THROWS FOR THE #514/#518/#519 REASON: `DecodingError` names the FIELD through
    /// `codingPath`. "This isn't an Echoel session at all", "it is one, but from a build that
    /// writes a field this one cannot read" and "the file could not be read off disk" are
    /// three different problems with three different answers, and `try?` folds all three onto
    /// `nil`. The `Data(contentsOf:)` throw is kept separate for the same reason — a
    /// permission/IO failure must not read as a corrupt document.
    ///
    /// ⛔ THE `Project?` FORMS BELOW ARE KEPT DELIBERATELY, and NOT because they are pretty.
    /// They have four callers in `Tests/EchoelmusicTests/ProjectStoreTests.swift` — the suite
    /// **no gate compiles** (#208) — so changing their signature is a break no CI run can show
    /// (#494 shipped exactly that, undetected). This is the same split `exportData` carries
    /// one screen up: the yes/no form stays for its existing callers, the throwing form is
    /// what the reachable door uses.
    public func importProject(fromDocument data: Data) throws -> Project {
        var p = try JSONDecoder().decode(Project.self, from: data)
        p.id = UUID()
        return save(p)
    }

    /// Import from a (security-scoped) file URL — the `fileImporter` path, throwing.
    public func importProject(fromDocument url: URL) throws -> Project {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // NOT `guard scoped else { throw }`: a document picked with `.import` is copied to a
        // temp location the app already owns, where `startAccessingSecurityScopedResource()`
        // returns false and reading succeeds anyway. Failing on the Bool would reject the
        // ordinary case. Behaviour unchanged from the `Project?` form on purpose — this slice
        // surfaces the error, it does not re-decide when to read.
        let data = try Data(contentsOf: url)
        return try importProject(fromDocument: data)
    }

    /// Yes/no import. See the throwing twin above for what a caller gives up by using this.
    @discardableResult
    public func importProject(from data: Data) -> Project? {
        try? importProject(fromDocument: data)
    }

    /// Yes/no import from a URL. See the throwing twin above.
    @discardableResult
    public func importProject(from url: URL) -> Project? {
        try? importProject(fromDocument: url)
    }

    /// The one sentence the Import door shows when a file could not become a take.
    ///
    /// ⭐ `nonisolated` so the blocking bundle can drive it end to end. `ProjectStore` is
    /// `@MainActor @Observable` and its init touches the App Group container, so a test that
    /// had to instantiate the store to reach this decision would be a source scan wearing a
    /// behaviour test's clothes. A `static` member of a `@MainActor` type is main-actor
    /// isolated unless it says otherwise — that is the documented Xcode-vs-SwiftPM trap in
    /// CLAUDE.md's build-error table, and the reason the keyword is written out here.
    ///
    /// ⚠️ IT NAMES THE FIELD WHERE ONE EXISTS AND INVENTS NOTHING WHERE ONE DOES NOT.
    /// `DecodingError.keyNotFound`/`.typeMismatch`/`.valueNotFound` carry a `codingPath`;
    /// `.dataCorrupted` on a non-JSON file has an EMPTY path (there is no field — the bytes
    /// were never a document), and printing "field: " with nothing after it would be the
    /// fabricated-detail defect this repo has paid for repeatedly (#424/#426/#433/#461).
    nonisolated public static func importFailureNote(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            // Everything that is not a decode problem: unreadable file, revoked permission,
            // a deleted iCloud placeholder. Deliberately NOT called "invalid session" — the
            // document may be perfect and simply unreachable.
            return "Couldn't read that file."
        }
        // ⚠️ AN `if case` CHAIN RATHER THAN A `switch`, AND THAT IS A BUILD DECISION, not a
        // style one. A `switch` over `DecodingError` needs either `default` or
        // `@unknown default`, and which one warns depends on whether the stdlib ships that
        // enum as frozen — the wrong guess is a WARNING, and this project builds with
        // `-warnings-as-errors`. There is no local Swift toolchain in this environment, so a
        // coin-flip there costs a full CI round trip. This form has no exhaustiveness
        // question at all and reads the same.
        var path: [CodingKey] = []
        if case .keyNotFound(_, let c) = decoding { path = c.codingPath }
        else if case .typeMismatch(_, let c) = decoding { path = c.codingPath }
        else if case .valueNotFound(_, let c) = decoding { path = c.codingPath }
        else if case .dataCorrupted(let c) = decoding { path = c.codingPath }
        // `stringValue` covers both keyed and unkeyed containers; an array index arrives as
        // "Index 3", which reads correctly in this sentence.
        let field = path.map(\.stringValue).joined(separator: " › ")
        return field.isEmpty
            ? "That file isn't an Echoel session."
            : "That file isn't a readable Echoel session — \(field)."
    }

    private func persist() {
        _ = store.save(projects, name: fileName)
    }
}
