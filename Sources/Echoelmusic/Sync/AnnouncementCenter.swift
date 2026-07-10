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

    private enum Key { static let enabled = "echoel.announcements.enabled" }

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
            Task { [weak self] in
                if self?.enabled == true { await self?.activate() }
                else { await self?.deactivate() }
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: Key.enabled)
        if enabled {
            // Re-assert on launch: registration is cheap and idempotent, and
            // the subscription save is keyed (same ID overwrites, never dupes).
            Task { [weak self] in await self?.activate() }
        }
    }

    // MARK: - Activation

    private func activate() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
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
        info.soundName = "default"
        subscription.notificationInfo = info

        do {
            let db = CKContainer(identifier: Self.containerID).publicCloudDatabase
            _ = try await db.save(subscription)
            status = "on"
            log.log(.info, category: .system, "Announcements: subscription saved")
        } catch {
            status = "error"
            log.log(.error, category: .system,
                    "Announcements: subscription failed — \(error.localizedDescription)")
        }
    }

    private func deactivate() async {
        do {
            let db = CKContainer(identifier: Self.containerID).publicCloudDatabase
            _ = try await db.deleteSubscription(withID: Self.subscriptionID)
            log.log(.info, category: .system, "Announcements: subscription removed")
        } catch {
            // Deleting a non-existent subscription is fine — stay quiet.
            log.log(.info, category: .system,
                    "Announcements: unsubscribe note — \(error.localizedDescription)")
        }
        status = ""
    }
}
#endif
