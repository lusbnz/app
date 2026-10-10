import Foundation

extension RecurringExpense {
    /// "mỗi Thứ Hai", "mỗi hai tuần vào Thứ Hai", "ngày 5 hàng tháng", "ngày 5 các tháng 2, 5, 8, 11", "ngày 15/3 hàng năm".
    func scheduleText(calendar: Calendar) -> String {
        let names = calendar.weekdaySymbols
        let weekdayName = names.indices.contains(weekday - 1) ? names[weekday - 1] : ""
        switch frequency {
        case .weekly:
            return String(localized: "mỗi \(weekdayName)")
        case .biweekly:
            return String(localized: "mỗi hai tuần vào \(weekdayName)")
        case .monthly:
            return String(localized: "ngày \(dayOfMonth) hàng tháng")
        case .quarterly:
            let months = RecurringPlanner.quarterMonths(startingAt: monthOfYear).map(String.init).joined(separator: ", ")
            return String(localized: "ngày \(dayOfMonth) các tháng \(months)")
        case .yearly:
            return String(localized: "ngày \(dayOfMonth)/\(monthOfYear) hàng năm")
        }
    }
}

extension RecurringFrequency {
    var title: String {
        switch self {
        case .weekly: String(localized: "Hàng tuần")
        case .biweekly: String(localized: "Hai tuần một lần")
        case .monthly: String(localized: "Hàng tháng")
        case .quarterly: String(localized: "Hàng quý")
        case .yearly: String(localized: "Hàng năm")
        }
    }
}
