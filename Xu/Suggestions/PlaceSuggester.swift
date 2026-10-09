import Foundation

/// Một nơi đã ghi nhiều lần.
struct FamiliarPlace: Equatable, Sendable, Identifiable {
    var center: Coordinate
    var visits: Int
    var lastVisit: Date
    /// Khoản hay ghi nhất ở đây.
    var usual: Suggestion

    /// Ổn định giữa các lần chạy, dùng làm định danh vùng theo dõi.
    var id: String {
        "\((center.latitude * 10_000).rounded() / 10_000),\((center.longitude * 10_000).rounded() / 10_000)"
    }

    /// "quán phở quen", "chỗ đổ xăng quen"
    var label: String {
        usual.categoryKey == SpendingCategory.food.rawValue
            ? String(localized: "quán \(usual.name) quen")
            : String(localized: "chỗ \(usual.name) quen")
    }
}

/// Gợi ý theo vị trí. Mọi tính toán nằm trên máy.
enum PlaceSuggester {
    static let radius = 100.0
    /// Hệ thống chỉ cho theo dõi tối đa 20 vùng.
    static let monitorLimit = 20

    /// Gom các khoản có tọa độ thành từng nơi trong bán kính 100 mét, nơi ghi gần đây đứng trước.
    static func places(records: [SuggestionRecord], minimumVisits: Int = 2) -> [FamiliarPlace] {
        var clusters: [(center: Coordinate, records: [SuggestionRecord])] = []
        for record in records.sorted(by: { $0.date > $1.date }) {
            guard let coordinate = record.coordinate else { continue }
            if let index = clusters.firstIndex(where: { $0.center.distance(to: coordinate) <= radius }) {
                clusters[index].records.append(record)
            } else {
                clusters.append((coordinate, [record]))
            }
        }
        return clusters.compactMap { cluster in
            guard cluster.records.count >= minimumVisits,
                  let usual = cluster.records.mostFrequent(),
                  let lastVisit = cluster.records.first?.date else { return nil }
            return FamiliarPlace(
                center: cluster.center, visits: cluster.records.count, lastVisit: lastVisit, usual: usual.suggestion
            )
        }
    }

    /// Nơi quen gần nhất trong bán kính, cùng khoản hay ghi ở đó. Bỏ qua khoản đã ghi hôm nay.
    static func suggestion(
        near coordinate: Coordinate, records: [SuggestionRecord], now: Date, calendar: Calendar
    ) -> (place: FamiliarPlace, suggestion: Suggestion)? {
        let nearest = places(records: records)
            .map { ($0, $0.center.distance(to: coordinate)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }
        guard let place = nearest?.0 else { return nil }
        let there = records.filter { $0.coordinate.map { place.center.distance(to: $0) <= radius } ?? false }
        let loggedToday = records.loggedIDs(on: now, calendar: calendar)
        guard let usual = there.mostFrequent(excluding: loggedToday) else { return nil }
        return (place, usual.suggestion)
    }

    /// Các nơi được nhắc khi rời đi: đã ghi từ 3 lần, tối đa 20 nơi, ưu tiên nơi ghi gần đây.
    static func monitoredPlaces(records: [SuggestionRecord]) -> [FamiliarPlace] {
        Array(places(records: records, minimumVisits: 3).prefix(monitorLimit))
    }
}
