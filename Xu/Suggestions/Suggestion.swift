import Foundation

enum PartOfDay: Equatable, Sendable {
    case morning, noon, afternoon, evening

    static func of(_ date: Date, calendar: Calendar) -> PartOfDay {
        switch calendar.component(.hour, from: date) {
        case 5..<11: .morning
        case 11..<14: .noon
        case 14..<18: .afternoon
        default: .evening
        }
    }

    var title: String {
        switch self {
        case .morning: String(localized: "sáng")
        case .noon: String(localized: "trưa")
        case .afternoon: String(localized: "chiều")
        case .evening: String(localized: "tối")
        }
    }
}

struct Coordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double

    /// Khoảng cách theo mét (công thức haversine).
    func distance(to other: Coordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

/// Một khoản chi nhìn từ phía bộ gợi ý.
struct SuggestionRecord: Equatable, Sendable {
    var name: String
    var amount: Int
    var categoryKey: String
    var date: Date
    var coordinate: Coordinate?
}

/// Một khoản đề xuất, chạm là ghi ngay.
struct Suggestion: Equatable, Sendable, Identifiable {
    var name: String
    var amount: Int
    var categoryKey: String

    var id: String { "\(TextNormalizer.keyword(name))|\(amount)" }
}

extension Sequence<SuggestionRecord> {
    /// Cặp (tên đã chuẩn hóa, số tiền) xuất hiện nhiều nhất; hòa thì lấy cặp ghi gần đây hơn.
    func mostFrequent(excluding excluded: Set<String> = []) -> (suggestion: Suggestion, count: Int)? {
        var table: [String: (suggestion: Suggestion, count: Int, latest: Date)] = [:]
        for record in self {
            let suggestion = Suggestion(name: record.name, amount: record.amount, categoryKey: record.categoryKey)
            guard !excluded.contains(suggestion.id) else { continue }
            var entry = table[suggestion.id] ?? (suggestion, 0, .distantPast)
            entry.count += 1
            if record.date >= entry.latest {
                entry.latest = record.date
                entry.suggestion = suggestion
            }
            table[suggestion.id] = entry
        }
        return table.values
            .max { ($0.count, $0.latest) < ($1.count, $1.latest) }
            .map { ($0.suggestion, $0.count) }
    }

    /// Các cặp đã ghi trong ngày `day`.
    func loggedIDs(on day: Date, calendar: Calendar) -> Set<String> {
        Set(filter { calendar.isDate($0.date, inSameDayAs: day) }
            .map { Suggestion(name: $0.name, amount: $0.amount, categoryKey: $0.categoryKey).id })
    }
}
