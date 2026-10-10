import Foundation

/// Danh sách các ngày có khoản chi, cho dải ngày kéo ở mép phải màn Hôm nay.
enum DayIndex {
    /// Hôm nay đứng đầu (kể cả chưa có khoản nào), rồi các ngày trước có khoản chi, mới nhất trước, mỗi ngày một lần.
    static func days(from dates: [Date], now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let past = Set(dates.map { calendar.startOfDay(for: $0) }.filter { $0 < today })
        return [today] + past.sorted(by: >)
    }

    /// Ngày ứng với vị trí `fraction` trên dải: 0 là trên cùng (mới nhất), 1 là dưới cùng (cũ nhất).
    static func day(atFraction fraction: Double, in days: [Date]) -> Date? {
        guard !days.isEmpty else { return nil }
        let clamped = min(max(fraction, 0), 1)
        return days[Int((clamped * Double(days.count - 1)).rounded())]
    }

    /// Vị trí trên dải của một ngày (ngày gần nhất trước đó nếu ngày này không có khoản).
    static func fraction(of day: Date, in days: [Date]) -> Double {
        guard days.count > 1 else { return 0 }
        let index = days.firstIndex { $0 <= day } ?? days.count - 1
        return Double(index) / Double(days.count - 1)
    }
}
