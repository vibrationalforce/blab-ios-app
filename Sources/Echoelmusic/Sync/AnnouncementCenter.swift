// AnnouncementCenter.swift
// Echoel — E4: push without an account. ONE CloudKit public-database record
// type ("Announcement") + a CKQuerySubscription on every opted-in device =
// broadcast push for features and live events with ZERO servers and ZERO
// login (decision 2026-07-10: serverless, no Sign-in; CloudKit rides the
// user's iCloud account invisibly).
//
// The founder posts announcements in the CloudKit Dashboard
// (docs/dev/CLOUDKIT_ANNOUNCEMENTS.md); every device with the opt-in toggle
// ON receives a visible push carrying the record's title/body via the
// localization-args mechanism. Opt-in only — never requested at first launch.
//
// Privacy: the push token goes to Apple (APNs), never to us; no analytics,
// no read receipts, nothing is collected. Privacy labels stay
// "Data Not Collected".

#if canImport(CloudKit) && canImport(UserNotifications)
import Foundation
import CloudKit
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class AnnouncementCenter {

    public static let containerID = "iCloud.com.echoelmusic.app"
    public static let recordType = "Announcement"
    static let subscriptionID = "echoel-announcements-v1"

    /// v1.0 SHIP GATE (v10.79.148 — the DEFINITIVE launch-crash fix). The v145
    /// AND v147 device logs both show a main-thread EXC_BREAKPOINT *inside* the
    /// CloudKit framework (`_os_crash` at CloudKit+46272), reached from this
    /// class's launch call — NOT in the Swift async thunk (so v147's safe
    /// wrapper could not help). CloudKit hard-traps because its container /
    /// "Announcement" schema is NOT yet deployed to PRODUCTION. Until it is
    /// (v1.1 "Echoel Live"), Echoel makes ZERO CloudKit calls: no launch
    /// re-assert, and the News toggle only stores the preference. Flip to
    /// `true` in the same change that deploys the CloudKit schema to production.
    /// This mirrors the business model — v1.0 is the free instrument NOW; push
    /// ships with Echoel Live in v1.1. (ProGate/EchoelStore are dormant the
    /// same way.)
    public static let cloudKitConfigured = false

    private enum Key {
        static let enabled = "echoel.announcements.enabled"
        /// Set while a CloudKit call is in flight; still true at next launch =
        /// the process DIED inside CloudKit (v10.79.145 device log: main-thread
        /// EXC_BREAKPOINT inside the CloudKit framework ~5 s after launch, from
        /// this class's launch re-assert). The circuit breaker below then skips
        /// the automatic re-assert so a CloudKit-internal trap can never become
        /// a crash-at-every-launch loop; a manual toggle retries deliberately.
        static let ckInflight = "echoel.announcements.ck-inflight"
    }

    /// Honest UI state: "", "on", "denied" (notifications off in Settings),
    /// "error" (subscription save failed — e.g. no iCloud account).
    public private(set) var status: String = ""

    @ObservationIgnored private let defaults: UserDefaults

    /// Opt-in (default OFF). Turning it on requests notification permission
    /// and saves the CloudKit subscription; off deletes the subscription.
    public var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: Key.enabled)
            // v1.0: store the preference only — no CloudKit until it is
            // provisioned (see `cloudKitConfigured`). The toggle stays honest:
            // it remembers the user's choice for when Echoel Live ships.
            guard Self.cloudKitConfigured else {
                status = enabled ? "coming-soon" : ""
                return
            }
            Task { [weak self] in
                if self?.enabled == true { await self?.activate() }
                else { await self?.deactivate() }
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: Key.enabled)
        // v1.0 SHIP GATE: never touch CloudKit at launch — it hard-traps until
        // the container schema is deployed to production (v145/v147 crash).
        guard Self.cloudKitConfigured else {
            if enabled { status = "coming-soon" }
            return
        }
        if defaults.bool(forKey: Key.ckInflight) {
            // CIRCUIT BREAKER: the previous launch died inside the CloudKit
            // call (see Key.ckInflight). Do NOT re-enter automatically —
            // the app must open. Toggling News off→on retries once.
            status = "error"
            log.log(.error, category: .system,
                    "Announcements: previous launch died in CloudKit — auto re-assert skipped")
        } else if enabled {
            // Re-assert on launch: registration is cheap and idempotent, and
            // the subscription save is keyed (same ID overwrites, never dupes).
            Task { [weak self] in await self?.activate() }
        }
    }

    // MARK: - Activation

    private func activate() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
        guard granted else {
            status = "denied"
            log.log(.info, category: .system, "Announcements: notification permission denied")
            return
        }
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif

        let subscription = CKQuerySubscription(
            recordType: Self.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: Self.subscriptionID,
            options: .firesOnRecordCreation
        )
        let info = CKSubscription.NotificationInfo()
        // Format-string-as-key: when the key has no Localizable.strings entry,
        // the system uses the key itself as the format — the standard CloudKit
        // way to surface record fields in a visible push.
        info.titleLocalizationKey = "%1$@"
        info.titleLocalizationArgs = ["title"]
        info.alertLocalizationKey = "%1$@"
        info.alertLocalizationArgs = ["body"]
        // SILENT banner — founder rule: the app makes NO sound except the music.
        // (A notification tone would also interrupt a live audio session mid-
        // performance.) The notificationInfo lives SERVER-SIDE in the saved
        // subscription: existing devices must toggle off→on once to re-save.
        subscription.notificationInfo = info

        do {
            let db = CKContainer(identifier: Self.containerID).publicCloudDatabase
            defaults.set(true, forKey: Key.ckInflight)
            try await Self.saveSubscription(subscription, to: db)
            defaults.set(false, forKey: Key.ckInflight)
            status = "on"
            log.log(.info, category: .system, "Announcements: subscription saved")
        } catch {
            defaults.set(false, forKey: Key.ckInflight)
            status = "error"
            log.log(.error, category: .system,
                    "Announcements: subscription failed — \(error.localizedDescription)")
        }
    }

    private func deactivate() async {
        do {
            let db = CKContainer(identifier: Self.containerID).publicCloudDatabase
            defaults.set(true, forKey: Key.ckInflight)
            try await Self.deleteSubscription(id: Self.subscriptionID, from: db)
            defaults.set(false, forKey: Key.ckInflight)
            log.log(.info, category: .system, "Announcements: subscription removed")
        } catch {
            // Deleting a non-existent subscription is fine — stay quiet.
            defaults.set(false, forKey: Key.ckInflight)
            log.log(.info, category: .system,
                    "Announcements: unsubscribe note — \(error.localizedDescription)")
        }
        status = ""
    }

    // MARK: - Safe CloudKit bridging (v10.79.147 crash fix)

    // The v145 device log shows a main-thread EXC_BREAKPOINT INSIDE the
    // CloudKit framework during this class's subscription call, with a
    // CheckedContinuation witness table in the crashing registers — the
    // signature of CloudKit's AUTO-GENERATED async thunk trapping (e.g. on a
    // pathological nil-result/nil-error completion). These wrappers bypass
    // that thunk entirely: the classic completion-handler API + our own
    // continuation, which tolerates every (result, error) combination and
    // resumes exactly once. We never need the returned value → resume Void
    // (also keeps non-Sendable CK types off the continuation).

    private static func saveSubscription(_ subscription: CKSubscription,
                                         to db: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            db.save(subscription) { saved, error in
                if let error {
                    cont.resume(throwing: error)
                } else if saved != nil {
                    cont.resume()
                } else {
                    // nil result AND nil error — the case the auto-thunk traps on.
                    cont.resume(throwing: CKError(.internalError))
                }
            }
        }
    }

    private static func deleteSubscription(id: CKSubscription.ID,
                                           from db: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            db.delete(withSubscriptionID: id) { deleted, error in
                if let error {
                    cont.resume(throwing: error)
                } else if deleted != nil {
                    cont.resume()
                } else {
                    cont.resume(throwing: CKError(.internalError))
                }
            }
        }
    }
}
#endif
