import Foundation

/// Luật của lời nhắc khi rời quán quen: mỗi nơi mỗi ngày không quá một lần,
/// và không nhắc khi khoản quen đã được ghi hôm nay.
enum LeaveReminderPolicy {
    static func shouldNotify(
        place: FamiliarPlace, lastNotified: [String: String], records: [SuggestionRecord], now: Date, calendar: Calendar
    ) -> Bool {
        if lastNotified[place.id] == SaveQuota.dayKey(now, calendar: calendar) { return false }
        return !records.loggedIDs(on: now, calendar: calendar).contains(place.usual.id)
    }

    /// Ghi nhận đã nhắc, đồng thời bỏ các dấu của ngày cũ.
    static func marking(_ placeID: String, in lastNotified: [String: String], now: Date, calendar: Calendar) -> [String: String] {
        let today = SaveQuota.dayKey(now, calendar: calendar)
        var kept = lastNotified.filter { $0.value == today }
        kept[placeID] = today
        return kept
    }

    /// "Vừa rời quán phở quen. Ghi phở 45k như mọi lần?"
    static func message(for place: FamiliarPlace) -> String {
        String(localized: "Vừa rời \(place.label). Ghi \(place.usual.name) \(MoneyFormatter.short(place.usual.amount)) như mọi lần?")
    }
}
