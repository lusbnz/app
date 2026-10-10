import CoreLocation
import MapKit
import SwiftData

/// Tìm quán và địa điểm gần một tọa độ. Đây là chỗ duy nhất Nhẩm gửi vị trí ra khỏi máy (cho Apple), nên chỉ được gọi
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

    static var isEnabled: Bool {
        AppGroup.defaults.bool(forKey: SettingsKey.placeLookup)
    }

    /// Đặt tên cho các khoản vừa ghi cùng một lần (chung một tọa độ) mà chưa có tên.
    func nameBatch(_ batchID: UUID, context: ModelContext) async {
        guard Self.isEnabled else { return }
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.batchID == batchID && $0.placeName == nil && $0.latitude != nil })
        let items = (try? context.fetch(descriptor)) ?? []
        guard let first = items.first, let latitude = first.latitude, let longitude = first.longitude else { return }
        let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        let candidates = await searcher.candidates(near: coordinate)
        guard let best = PlaceNaming.ranked(candidates, near: coordinate, limit: 1).first else { return }
        // Trong lúc chờ mạng người dùng có thể đã tự đặt tên, nên chỉ điền chỗ còn trống.
        for expense in items where expense.placeName == nil { expense.placeName = best.name }
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
            if name == nil {
                let candidates = await searcher.candidates(near: group.center)
                name = PlaceNaming.ranked(candidates, near: group.center, limit: 1).first?.name
            }
            guard let name else { continue }
            named += recorder.setPlaceName(name, forExpensesWithIDs: group.ids)
        }
        return named
    }
}
