import Foundation
import UserNotifications
import os
#if canImport(UIKit)
import UIKit
#endif

/// Schedules Curio-owned "remind me to read later" notifications in-house.
///
/// Reminders used to be delegated entirely to the companion ChronosFlow app (`ChronosFlowBridge`);
/// Curio now owns them so they fire whether or not ChronosFlow is installed. This is the iOS twin of
/// Android's `ReminderScheduler` (there: a delayed WorkManager job; here: a local
/// `UNUserNotificationCenter` request). One request per bookmark (`reminder-<id>`), so re-scheduling
/// the same bookmark replaces the previous reminder instead of stacking.
///
/// Stateless and thread-safe (`UNUserNotificationCenter` is), so `Sendable`.
final class ReminderScheduler: Sendable {

    private static let logger = Logger(subsystem: "com.curio.app", category: "ReminderScheduler")

    init() {}

    /// Requests notification authorization once (no-op if already asked). Best-effort: a denial just
    /// means reminders (and the Live Activity's alerts) stay silent.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Schedules a reminder for `bookmarkId` at `atEpochMillis`. A time already in the past fires a
    /// couple of seconds out. Payload carries the URL so a tap can open it (see the delegate).
    func schedule(bookmarkId: String, title: String?, url: String?, atEpochMillis: Int64) async {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let delaySeconds = max(1.0, Double(atEpochMillis - nowMs) / 1000.0)

        let content = UNMutableNotificationContent()
        content.title = "Time to read 📖"
        content.body = (title?.isEmpty == false ? title! : "Something you saved to read")
        content.sound = .default
        if let url { content.userInfo = ["url": url] }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delaySeconds, repeats: false)
        let request = UNNotificationRequest(identifier: Self.identifier(bookmarkId), content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Self.logger.error("Reminder schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Cancels a pending reminder for `bookmarkId` (e.g. when the bookmark is deleted).
    func cancel(bookmarkId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.identifier(bookmarkId)])
    }

    private static func identifier(_ bookmarkId: String) -> String { "reminder-\(bookmarkId)" }
}

/// `UNUserNotificationCenterDelegate` that (a) shows reminder banners even when Curio is foreground,
/// and (b) opens the saved link when the user taps a reminder. Retained by `AppEnvironment` and set as
/// the notification-center delegate in `CurioApp`.
final class ReminderNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard
            let urlString = userInfo["url"] as? String,
            let url = URL(string: urlString),
            url.scheme == "http" || url.scheme == "https"
        else { return }
        #if canImport(UIKit)
        await MainActor.run { UIApplication.shared.open(url) }
        #endif
    }
}
