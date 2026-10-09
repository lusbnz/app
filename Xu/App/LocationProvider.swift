import CoreLocation
import Observation

/// Vị trí hiện tại, chỉ dùng trên máy. Không xin quyền cho tới khi người dùng bật công tắc.
@MainActor @Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private(set) var authorization: CLAuthorizationStatus
    private(set) var current: CLLocation?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// Tọa độ còn mới (trong 5 phút), để lưu kèm khoản chi.
    var freshCoordinate: Coordinate? {
        guard isAuthorized, let current, current.timestamp.timeIntervalSinceNow > -300 else { return nil }
        return Coordinate(latitude: current.coordinate.latitude, longitude: current.coordinate.longitude)
    }

    /// Thiếu khóa mô tả trong Info thì hệ thống không hiện hộp xin quyền.
    static func hasUsageDescription(_ key: String) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: key) != nil
    }

    func requestWhenInUse() {
        guard Self.hasUsageDescription("NSLocationWhenInUseUsageDescription") else { return }
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        guard Self.hasUsageDescription("NSLocationAlwaysAndWhenInUseUsageDescription") else { return }
        manager.requestAlwaysAuthorization()
    }

    func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            refresh()
            await PlaceMonitor.shared.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in current = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
