import Foundation

/// Bộ đếm số lần lưu trong ngày của bản miễn phí.
struct SaveQuota: Equatable, Sendable {
    static let freeDailyLimit = 5

    /// "2026-10-09"
    var day: String
    var count: Int

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// Số lần đã lưu trong ngày `date`; sang ngày mới thì về 0.
    func used(on date: Date, calendar: Calendar) -> Int {
        day == Self.dayKey(date, calendar: calendar) ? count : 0
    }

    func canSave(on date: Date, calendar: Calendar) -> Bool {
        used(on: date, calendar: calendar) < Self.freeDailyLimit
    }

    func adding(_ delta: Int, on date: Date, calendar: Calendar) -> SaveQuota {
        SaveQuota(day: Self.dayKey(date, calendar: calendar), count: max(0, used(on: date, calendar: calendar) + delta))
    }
}

/// Giới hạn bản miễn phí, lưu trong App Group để app và intent cùng đếm.
enum SaveGate {
    private static let quotaKey = "saveQuota"
    private static let proKey = "isPro"

    /// EntitlementStore ghi vào đây để intent đọc được mà không cần StoreKit.
    static var isPro: Bool {
        get { AppGroup.defaults.bool(forKey: proKey) }
        set { AppGroup.defaults.set(newValue, forKey: proKey) }
    }

    static var quota: SaveQuota {
        get {
            let stored = AppGroup.defaults.dictionary(forKey: quotaKey)
            return SaveQuota(day: stored?["day"] as? String ?? "", count: stored?["count"] as? Int ?? 0)
        }
        set { AppGroup.defaults.set(["day": newValue.day, "count": newValue.count], forKey: quotaKey) }
    }

    static func canSave(now: Date, calendar: Calendar) -> Bool {
        isPro || quota.canSave(on: now, calendar: calendar)
    }

    static func didSave(now: Date, calendar: Calendar) {
        quota = quota.adding(1, on: now, calendar: calendar)
    }

    /// Hoàn tác thì trả lại một lần.
    static func didUndo(now: Date, calendar: Calendar) {
        quota = quota.adding(-1, on: now, calendar: calendar)
    }
}
