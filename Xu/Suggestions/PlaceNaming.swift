import Foundation

/// Một nơi đã có tên (từ một khoản đã ghi), dùng để đặt tên lại cho khoản ở cùng chỗ mà không cần hỏi lại.
struct NamedPlaceRecord: Equatable, Sendable {
    var coordinate: Coordinate
    var name: String
    var date: Date
}

/// Một quán hoặc địa điểm do hệ thống tìm được gần một tọa độ.
struct PlaceCandidate: Equatable, Sendable, Identifiable {
    var name: String
    var coordinate: Coordinate

    var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }
}

/// Một khoản có tọa độ, nhìn từ phía đặt tên nơi.
struct LocatedItem: Equatable, Sendable {
    var id: UUID
    var coordinate: Coordinate
    var name: String?
    var date: Date
}

/// Nhóm các khoản ở cùng một chỗ, để chỉ phải tra tên một lần cho cả nhóm.
struct PlaceGroup: Equatable, Sendable {
    var center: Coordinate
    var ids: [UUID]
}

/// Đặt tên nơi ghi. Mọi tính toán ở đây chạy trên máy; chỉ việc tìm quán gần một tọa độ mới cần mạng (xem `PlaceLookup`).
enum PlaceNaming {
    /// Khoản ở trong bán kính này coi như cùng một chỗ, dùng lại tên đã có.
    static let sameSpotRadius = 50.0
    /// Bán kính tìm quán quanh một tọa độ.
    static let searchRadius = 80.0
    static let maxNameLength = 60
    static let maxCandidates = 8

    /// Làm gọn tên người dùng gõ hoặc hệ thống trả về; nil khi trống.
    static func clean(_ name: String?) -> String? {
        guard let name else { return nil }
        let collapsed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxNameLength))
    }

    /// Tên đã đặt ở gần nhất trong `sameSpotRadius`; cùng khoảng cách thì lấy tên mới hơn.
    static func reusableName(near coordinate: Coordinate, in places: [NamedPlaceRecord]) -> String? {
        places
            .map { (place: $0, distance: $0.coordinate.distance(to: coordinate)) }
            .filter { $0.distance <= sameSpotRadius }
            .min { ($0.distance, $1.place.date) < ($1.distance, $0.place.date) }?
            .place.name
    }

    /// Các tên đã đặt quanh đây (trong `radius`), tên dùng nhiều nhất trước.
    static func nearbyNames(near coordinate: Coordinate, in places: [NamedPlaceRecord], radius: Double = 150) -> [String] {
        let near = places.filter { $0.coordinate.distance(to: coordinate) <= radius }
        let counts = Dictionary(grouping: near, by: \.name).mapValues(\.count)
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// Ứng viên gần nhất trước, bỏ trùng tên, bỏ tên trống, giữ tối đa `limit`.
    static func ranked(_ candidates: [PlaceCandidate], near coordinate: Coordinate, limit: Int = maxCandidates) -> [PlaceCandidate] {
        var seen = Set<String>()
        var result: [PlaceCandidate] = []
        let sorted = candidates.sorted { $0.coordinate.distance(to: coordinate) < $1.coordinate.distance(to: coordinate) }
        for candidate in sorted {
            guard let name = clean(candidate.name), seen.insert(TextNormalizer.keyword(name)).inserted else { continue }
            result.append(PlaceCandidate(name: name, coordinate: candidate.coordinate))
            if result.count == limit { break }
        }
        return result
    }

    /// Các khoản chưa có tên ở gần nhau gom thành nhóm trong `sameSpotRadius`, nhóm có khoản mới nhất đứng trước.
    static func unnamedGroups(_ items: [LocatedItem]) -> [PlaceGroup] {
        var groups: [(center: Coordinate, ids: [UUID])] = []
        for item in items.filter({ $0.name == nil }).sorted(by: { $0.date > $1.date }) {
            if let index = groups.firstIndex(where: { $0.center.distance(to: item.coordinate) <= sameSpotRadius }) {
                groups[index].ids.append(item.id)
            } else {
                groups.append((item.coordinate, [item.id]))
            }
        }
        return groups.map { PlaceGroup(center: $0.center, ids: $0.ids) }
    }

    /// Các khoản khác ở cùng chỗ với `coordinate` và còn mang tên cũ (hoặc chưa có tên): khi đổi tên nơi cho một khoản
    /// thì đổi luôn những khoản này.
    static func siblings(of coordinate: Coordinate, among items: [LocatedItem], oldName: String?, excluding id: UUID) -> [UUID] {
        items
            .filter { $0.id != id && $0.coordinate.distance(to: coordinate) <= sameSpotRadius && $0.name == oldName }
            .map(\.id)
    }
}
