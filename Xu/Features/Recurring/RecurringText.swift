import Foundation

extension RecurringExpense {
    /// "mỗi Thứ Hai", "ngày 5 hàng tháng", "ngày 15/3 hàng năm".
    func scheduleText(calendar: Calendar) -> String {
        switch frequency {
        case .weekly:
            let names = calendar.weekdaySymbols
            let name = names.indices.contains(weekday - 1) ? names[weekday - 1] : ""
            return String(localized: "mỗi \(name)")
        case .monthly:
            return String(localized: "ngày \(dayOfMonth) hàng tháng")
        case .yearly:
            return String(localized: "ngày \(dayOfMonth)/\(monthOfYear) hàng năm")
        }
    }
}

extension RecurringFrequency {
    var title: String {
        switch self {
        case .weekly: String(localized: "Hàng tuần")
        case .monthly: String(localized: "Hàng tháng")
        case .yearly: String(localized: "Hàng năm")
        }
    }
}
