import Foundation
import SwiftData
import UserNotifications

/// Thông báo cục bộ: nhắc 21:00, nhắc khi rời quán quen, nhắc khoản định kỳ đến hạn, và tổng kết cuối tuần, cuối tháng.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private static let dailyPrefix = "daily-"
    private static let dailySlots = 14
    private static let leavePrefix = "leave."
    private static let logAction = "leave.log"
    private static let editAction = "leave.edit"
    private static let skipAction = "leave.skip"
    private static let summaryPrefix = "summary."
    private static let recurringPrefix = "recurring."
    private static let recurringLogAction = "recurring.log"
    private static let recurringSkipAction = "recurring.skip"
    private static let recurringCategory = "recurring.due"
    private let center = UNUserNotificationCenter.current()
    private var leaveCategories: Set<UNNotificationCategory> = []

    func start() {
        center.delegate = self
        applyCategories()
    }

    /// `setNotificationCategories` thay cả bộ, nên luôn đặt lại gộp cả nhóm của quán quen lẫn của khoản định kỳ.
    private func applyCategories() {
        let recurring = UNNotificationCategory(
            identifier: Self.recurringCategory,
            actions: [
                UNNotificationAction(identifier: Self.recurringLogAction, title: String(localized: "Ghi")),
                UNNotificationAction(identifier: Self.recurringSkipAction, title: String(localized: "Bỏ qua")),
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories(leaveCategories.union([recurring]))
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

    // MARK: - Tổng kết cuối tuần, cuối tháng

    /// Xếp lại thông báo tổng kết kế tiếp (tối ngày cuối tuần, tối ngày cuối tháng) theo công tắc trong Tùy chỉnh.
    /// Nội dung tính từ dữ liệu lúc này; vì mọi lần ghi, sửa, xóa đều gọi lại hàm này (`ExpenseRecorder.afterCommit`)
    /// nên lúc thông báo đến, số liệu vẫn là mới nhất. Kỳ chưa chi gì thì không gửi.
    func refreshSummaryReminders() {
        let now = Date()
        let calendar = Calendar.current
        let defaults = AppGroup.defaults
        var kinds: [SummaryKind] = []
        if defaults.bool(forKey: SettingsKey.weeklySummary) { kinds.append(.week) }
        if defaults.bool(forKey: SettingsKey.monthlySummary) { kinds.append(.month) }
        let budget = BudgetSetting.load(from: defaults)
        let recorder = ExpenseRecorder(context: XuStore.shared.mainContext)

        var requests: [UNNotificationRequest] = []
        for kind in kinds {
            let component: Calendar.Component = kind == .week ? .weekOfYear : .month
            guard let fire = SummaryPlanner.nextFire(kind: kind, now: now, calendar: calendar),
                  let period = calendar.dateInterval(of: component, for: fire),
                  let previousStart = calendar.date(byAdding: component, value: -1, to: period.start) else { continue }
            let records = recorder.expenses(since: previousStart).map(\.record)
            guard let summary = SummaryComposer.make(
                kind: kind, records: records, budget: budget, containing: fire, calendar: calendar
            ) else { continue }
            let text = SummaryText.compose(summary, categoryTitle: { recorder.categoryTitle(for: $0) }, calendar: calendar)
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            requests.append(UNNotificationRequest(
                identifier: Self.summaryPrefix + kind.rawValue, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            ))
        }
        Task {
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.summaryPrefix) }
            )
            for request in requests { try? await center.add(request) }
        }
    }

    // MARK: - Khoản định kỳ

    /// Xếp lại lời nhắc 9:00 vào ngày đến hạn của mọi khoản định kỳ (vài kỳ tới), và 9:00 ngày hôm trước với khoản bật nhắc trước.
    /// Xóa hết lời nhắc cũ rồi xếp lại, nên khoản đã ghi, bỏ qua hay xóa tự biến mất khỏi lịch.
    func refreshRecurringReminders() {
        let now = Date()
        let calendar = Calendar.current
        let items = ((try? XuStore.shared.mainContext.fetch(FetchDescriptor<RecurringExpense>())) ?? [])
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Lịch cục bộ giữ tối đa 64 thông báo; lời nhắc 21:00 đã chiếm 14.
        let dates = RecurringPlanner.fireDates(for: items.map(\.item), now: now, calendar: calendar).prefix(40)
        Task {
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.recurringPrefix) }
            )
            for (id, date, isDayBefore) in dates {
                guard let item = byID[id] else { continue }
                let content = UNMutableNotificationContent()
                content.sound = .default
                if isDayBefore {
                    // Chỉ báo trước: không có nút và không mang mã khoản, ghi hay bỏ qua vẫn làm vào ngày đến hạn.
                    content.title = String(localized: "Ngày mai: \(item.name)")
                    content.body = String(localized: "\(MoneyFormatter.short(item.amount)). Đến hạn vào ngày mai.")
                } else {
                    content.title = String(localized: "Đến hạn: \(item.name)")
                    content.body = item.autoRecord
                        ? String(localized: "\(MoneyFormatter.short(item.amount)). Mở Pennyline để tự ghi, hoặc chạm Bỏ qua kỳ này.")
                        : String(localized: "\(MoneyFormatter.short(item.amount)). Chạm Ghi để ghi, hoặc Bỏ qua kỳ này.")
                    content.categoryIdentifier = Self.recurringCategory
                    content.userInfo = ["recurringID": id.uuidString]
                }
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                // Khoản theo tuần có nhiều lần trong một tháng, nên mã theo ngày nhắc.
                let key = RecurringPlanner.dayKey(date, calendar: calendar)
                try? await center.add(UNNotificationRequest(
                    identifier: "\(Self.recurringPrefix)\(id.uuidString).\(key)\(isDayBefore ? ".before" : "")",
                    content: content, trigger: trigger
                ))
            }
        }
    }

    private func handleRecurringAction(_ action: String, id: UUID) {
        let now = Date()
        let calendar = Calendar.current
        let recorder = ExpenseRecorder(context: XuStore.shared.mainContext)
        guard let item = recorder.recurring(id: id) else { return }
        switch action {
        case Self.recurringLogAction:
            guard SaveGate.canSave(now: now, calendar: calendar) else {
                AppState.shared.showsPaywall = true
                return
            }
            if let batch = recorder.recordRecurring(item, now: now, calendar: calendar) {
                AppState.shared.didSave(batch)
            }
        case Self.recurringSkipAction:
            recorder.skipRecurring(item, now: now, calendar: calendar)
        default:
            break
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
        leaveCategories = Set(categories)
        applyCategories()
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
            // Lưu không mở app. Hết lượt miễn phí thì mở ô gõ, nơi sẽ hiện Pennyline Pro.
            let now = Date()
            guard SaveGate.canSave(now: now, calendar: .current) else {
                AppState.shared.openEntry(text: text)
                return
            }
            let batch = ExpenseRecorder(context: XuStore.shared.mainContext).recordQuick(
                name: name, amount: amount, budget: BudgetSetting.load(), now: now, calendar: .current, coordinate: coordinate
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
        let recurringID = (info["recurringID"] as? String).flatMap(UUID.init(uuidString:))
        let name = info["name"] as? String
        let amount = info["amount"] as? Int
        var coordinate: Coordinate?
        if let latitude = info["latitude"] as? Double, let longitude = info["longitude"] as? Double {
            coordinate = Coordinate(latitude: latitude, longitude: longitude)
        }
        await MainActor.run {
            if identifier.hasPrefix(Self.dailyPrefix), action == UNNotificationDefaultActionIdentifier {
                AppState.shared.openEntry()
            } else if identifier.hasPrefix(Self.summaryPrefix), action == UNNotificationDefaultActionIdentifier {
                AppState.shared.openMonth()
            } else if identifier.hasPrefix(Self.recurringPrefix), let recurringID {
                handleRecurringAction(action, id: recurringID)
            } else if identifier.hasPrefix(Self.leavePrefix), let name, let amount {
                handleLeaveAction(action, name: name, amount: amount, coordinate: coordinate)
            }
        }
    }
}
