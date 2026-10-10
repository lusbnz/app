import Foundation

/// Một khoản có tọa độ, nhìn từ phía "chi ở đâu".
struct PlaceRecord: Equatable, Sendable {
    var coordinate: Coordinate
    var name: String?
    var amount: Int
    var date: Date
    var categoryKey: String
}

/// Tổng chi ở một chỗ (các khoản trong `PlaceNaming.sameSpotRadius`).
struct PlaceSpend: Identifiable, Equatable, Sendable {
    var id: String
    /// Tên hay gặp nhất ở chỗ này; nil khi chưa khoản nào có tên.
    var name: String?
    var coordinate: Coordinate
    var total: Int
    var count: Int
    var lastDate: Date
    /// Danh mục chi nhiều tiền nhất ở đây.
    var topCategoryKey: String
}

private struct PlaceCluster {
    var latitudeSum: Double
    var longitudeSum: Double
    var records: [PlaceRecord]

    var center: Coordinate {
        Coordinate(latitude: latitudeSum / Double(records.count), longitude: longitudeSum / Double(records.count))
    }
}

enum PlaceSpending {
    /// Gom các khoản theo chỗ, chỗ chi nhiều nhất đứng đầu.
    static func totals(_ records: [PlaceRecord]) -> [PlaceSpend] {
        var clusters: [PlaceCluster] = []
        for record in records.sorted(by: { ($0.date, $0.amount) > ($1.date, $1.amount) }) {
            if let index = clusters.firstIndex(where: { $0.center.distance(to: record.coordinate) <= PlaceNaming.sameSpotRadius }) {
                clusters[index].latitudeSum += record.coordinate.latitude
                clusters[index].longitudeSum += record.coordinate.longitude
                clusters[index].records.append(record)
            } else {
                clusters.append(PlaceCluster(
                    latitudeSum: record.coordinate.latitude, longitudeSum: record.coordinate.longitude, records: [record]
                ))
            }
        }
        return clusters.map(spend(from:)).sorted { ($0.total, $1.id) > ($1.total, $0.id) }
    }

    private static func spend(from cluster: PlaceCluster) -> PlaceSpend {
        let center = cluster.center
        // Tên hay gặp nhất ở chỗ này (không phân biệt dấu và hoa thường); hòa thì lấy tên của khoản mới hơn.
        var names: [String: (count: Int, latest: Date, label: String)] = [:]
        for record in cluster.records {
            guard let name = PlaceNaming.clean(record.name) else { continue }
            let key = TextNormalizer.keyword(name)
            var entry = names[key] ?? (0, .distantPast, name)
            entry.count += 1
            if record.date >= entry.latest { (entry.latest, entry.label) = (record.date, name) }
            names[key] = entry
        }
        let byCategory = Dictionary(grouping: cluster.records, by: \.categoryKey).mapValues { $0.reduce(0) { $0 + $1.amount } }
        return PlaceSpend(
            id: String(format: "%.5f,%.5f", center.latitude, center.longitude),
            name: names.values.max { ($0.count, $0.latest) < ($1.count, $1.latest) }?.label,
            coordinate: center,
            total: cluster.records.reduce(0) { $0 + $1.amount },
            count: cluster.records.count,
            lastDate: cluster.records.map(\.date).max() ?? .distantPast,
            topCategoryKey: byCategory.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? SpendingCategory.other.rawValue
        )
    }

    /// Vùng bản đồ vừa các chỗ, chừa lề; nil khi không có chỗ nào.
    static func region(of spends: [PlaceSpend]) -> (center: Coordinate, latitudeSpan: Double, longitudeSpan: Double)? {
        guard let first = spends.first else { return nil }
        var minLat = first.coordinate.latitude, maxLat = minLat
        var minLon = first.coordinate.longitude, maxLon = minLon
        for spend in spends {
            minLat = min(minLat, spend.coordinate.latitude)
            maxLat = max(maxLat, spend.coordinate.latitude)
            minLon = min(minLon, spend.coordinate.longitude)
            maxLon = max(maxLon, spend.coordinate.longitude)
        }
        let minimumSpan = 0.008          // khoảng 900 m, để một chỗ đơn lẻ không bị phóng quá gần
        return (
            Coordinate(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            max(minimumSpan, (maxLat - minLat) * 1.5),
            max(minimumSpan, (maxLon - minLon) * 1.5)
        )
    }
}
