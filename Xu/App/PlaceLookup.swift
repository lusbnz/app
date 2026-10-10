import CoreLocation
import MapKit
import SwiftData

/// Tìm quán và địa điểm gần một tọa độ. Đây là chỗ duy nhất Pennyline gửi vị trí ra khỏi máy (cho Apple), nên chỉ được gọi
/// khi người dùng đã bật "Tự nhận tên nơi ghi" hoặc tự bấm tìm trong màn chọn nơi.
protocol PlaceSearching: Sendable {
    func candidates(near coordinate: Coordinate) async -> [PlaceCandidate]
}

struct ApplePlaceSearch: PlaceSearching {
    func candidates(near coordinate: Coordinate) async -> [PlaceCandidate] {
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: PlaceNaming.searchRadius)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let location: CLLocationCoordinate2D
            if #available(iOS 26.0, *) {
                location = item.location.coordinate
            } else {
                location = item.placemark.coordinate
            }
            return PlaceCandidate(name: name, coordinate: Coordinate(latitude: location.latitude, longitude: location.longitude))
        }
    }
}

/// Đặt tên nơi ghi cho các khoản đã có tọa độ. Ưu tiên dùng lại tên đã có ở cùng chỗ (không cần mạng).
@MainActor
final class PlaceLookup {
    static let shared = PlaceLookup()

    var searcher: any PlaceSearching = ApplePlaceSearch()
    /// Tên đã tra được trong lúc app chạy, theo ô lưới khoảng 10 m, để mở ô gõ nhiều lần ở cùng chỗ không phải hỏi lại.
    private var cache: [String: (name: String, date: Date)] = [:]
    private static let cacheLifetime: TimeInterval = 600

    static var isEnabled: Bool {
        AppGroup.defaults.bool(forKey: SettingsKey.placeLookup)
    }

    /// Tên quán gần nhất quanh `coordinate`, hoặc nil khi không tìm thấy. Chỉ nhớ kết quả tìm được, không nhớ lần thất bại
    /// (mất mạng chẳng hạn) để lần sau còn thử lại.
    func bestName(near coordinate: Coordinate) async -> String? {
        let key = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        if let hit = cache[key], -hit.date.timeIntervalSinceNow < Self.cacheLifetime { return hit.name }
        let candidates = await searcher.candidates(near: coordinate)
        guard let name = PlaceNaming.ranked(candidates, near: coordinate, limit: 1).first?.name else { return nil }
        cache[key] = (name, Date())
        return name
    }

    func clearCache() {
        cache.removeAll()
    }

    /// Đặt tên cho các khoản vừa ghi cùng một lần (chung một tọa độ) mà chưa có tên.
    func nameBatch(_ batchID: UUID, context: ModelContext) async {
        guard Self.isEnabled else { return }
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.batchID == batchID && $0.placeName == nil && $0.latitude != nil })
        let items = (try? context.fetch(descriptor)) ?? []
        guard let first = items.first, let latitude = first.latitude, let longitude = first.longitude else { return }
        let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        guard let name = await bestName(near: coordinate) else { return }
        // Trong lúc chờ mạng người dùng có thể đã tự đặt tên, nên chỉ điền chỗ còn trống.
        for expense in items where expense.placeName == nil { expense.placeName = name }
        try? context.save()
    }

    /// Đặt tên cho các khoản cũ chưa có tên, mỗi chỗ tra một lần, chỗ gần đây nhất trước. Trả về số khoản đã đặt tên.
    @discardableResult
    func backfill(context: ModelContext, groupLimit: Int) async -> Int {
        guard Self.isEnabled else { return 0 }
        let recorder = ExpenseRecorder(context: context)
        var named = 0
        for group in PlaceNaming.unnamedGroups(recorder.locatedItems()).prefix(groupLimit) {
            // Có thể một chỗ gần đó vừa được đặt tên ở vòng trước.
            var name = PlaceNaming.reusableName(near: group.center, in: recorder.namedPlaces())
            if name == nil { name = await bestName(near: group.center) }
            guard let name else { continue }
            named += recorder.setPlaceName(name, forExpensesWithIDs: group.ids)
        }
        return named
    }
}
