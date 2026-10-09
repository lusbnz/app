import Foundation
import UserNotifications

/// Thông báo cục bộ: nhắc 21:00 và nhắc khi rời quán quen.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private static let dailyPrefix = "daily-"
    private static let dailySlots = 14
    private let center = UNUserNotificationCenter.current()

    func start() {
        center.delegate = self
    }

    /// Chỉ gọi khi người dùng bật một công tắc nhắc.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Xếp lại lịch nhắc 21:00 theo tình trạng hiện tại của kho dữ liệu.
    func refreshDailyReminder() {
        let now = Date()
        let calendar = Calendar.current
        let enabled = AppGroup.defaults.bool(forKey: SettingsKey.remindsAtNine)
        let hasLogged = ExpenseRecorder(context: XuStore.shared.mainContext).hasLogged(on: now, calendar: calendar)
        center.removePendingNotificationRequests(
            withIdentifiers: (0..<Self.dailySlots).map { "\(Self.dailyPrefix)\($0)" }
        )
        guard enabled else { return }
        let dates = ReminderPlanner.fireDates(now: now, hasLoggedToday: hasLogged, days: Self.dailySlots, calendar: calendar)
        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Hôm nay bạn chưa ghi gì")
            content.body = String(localized: "Gõ một dòng là xong, ví dụ “phở 45k, grab 32”.")
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(Self.dailyPrefix)\(index)", content: content, trigger: trigger))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        await MainActor.run {
            if identifier.hasPrefix(Self.dailyPrefix), action == UNNotificationDefaultActionIdentifier {
                AppState.shared.openEntry()
            }
        }
    }
}
