import Foundation
import UserNotifications

/// Thông báo cục bộ: nhắc 21:00 và nhắc khi rời quán quen.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private static let dailyPrefix = "daily-"
    private static let dailySlots = 14
    private static let leavePrefix = "leave."
    private static let logAction = "leave.log"
    private static let editAction = "leave.edit"
    private static let skipAction = "leave.skip"
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

    // MARK: - Rời quán quen

    /// Mỗi nơi một nhóm hành động, vì nút "Ghi 45k" mang số tiền của nơi đó.
    func registerLeaveCategories(for places: [FamiliarPlace]) {
        let categories = places.map { place in
            UNNotificationCategory(
                identifier: Self.leavePrefix + place.id,
                actions: [
                    UNNotificationAction(
                        identifier: Self.logAction,
                        title: String(localized: "Ghi \(MoneyFormatter.short(place.usual.amount))")
                    ),
                    UNNotificationAction(identifier: Self.editAction, title: String(localized: "Sửa"), options: [.foreground]),
                    UNNotificationAction(identifier: Self.skipAction, title: String(localized: "Bỏ qua")),
                ],
                intentIdentifiers: []
            )
        }
        center.setNotificationCategories(Set(categories))
    }

    func notifyLeaving(_ place: FamiliarPlace) {
        let content = UNMutableNotificationContent()
        content.body = LeaveReminderPolicy.message(for: place)
        content.sound = .default
        content.categoryIdentifier = Self.leavePrefix + place.id
        content.userInfo = [
            "name": place.usual.name, "amount": place.usual.amount,
            "latitude": place.center.latitude, "longitude": place.center.longitude,
        ]
        center.add(UNNotificationRequest(identifier: Self.leavePrefix + place.id, content: content, trigger: nil))
    }

    private func handleLeaveAction(_ action: String, name: String, amount: Int, coordinate: Coordinate?) {
        let text = "\(name) \(MoneyFormatter.short(amount))"
        switch action {
        case Self.logAction:
            // Lưu không mở app. Hết lượt miễn phí thì mở ô gõ, nơi sẽ hiện Xu Pro.
            let now = Date()
            guard SaveGate.canSave(now: now, calendar: .current) else {
                AppState.shared.openEntry(text: text)
                return
            }
            let budget = AppGroup.defaults.integer(forKey: SettingsKey.monthlyBudget)
            let batch = ExpenseRecorder(context: XuStore.shared.mainContext).recordQuick(
                name: name, amount: amount, monthlyBudget: budget, now: now, calendar: .current, coordinate: coordinate
            )
            AppState.shared.didSave(batch)
        case Self.editAction, UNNotificationDefaultActionIdentifier:
            AppState.shared.openEntry(text: text)
        default:
            break
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
        let info = response.notification.request.content.userInfo
        let name = info["name"] as? String
        let amount = info["amount"] as? Int
        var coordinate: Coordinate?
        if let latitude = info["latitude"] as? Double, let longitude = info["longitude"] as? Double {
            coordinate = Coordinate(latitude: latitude, longitude: longitude)
        }
        await MainActor.run {
            if identifier.hasPrefix(Self.dailyPrefix), action == UNNotificationDefaultActionIdentifier {
                AppState.shared.openEntry()
            } else if identifier.hasPrefix(Self.leavePrefix), let name, let amount {
                handleLeaveAction(action, name: name, amount: amount, coordinate: coordinate)
            }
        }
    }
}
