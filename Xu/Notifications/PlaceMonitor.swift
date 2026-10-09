import CoreLocation
import Foundation
import SwiftData

/// Theo dõi các quán quen bằng CLMonitor và nhắc khi người dùng rời đi. Tắt sẵn.
@MainActor
final class PlaceMonitor {
    static let shared = PlaceMonitor()

    private static let monitorName = "XuFamiliarPlaces"
    private static let lastNotifiedKey = "leaveReminderLastNotified"

    private var monitor: CLMonitor?
    private var session: CLServiceSession?
    private var listener: Task<Void, Never>?
    private var places: [String: FamiliarPlace] = [:]

    private var isEnabled: Bool {
        AppGroup.defaults.bool(forKey: SettingsKey.leaveReminderEnabled)
            && LocationProvider.shared.authorization == .authorizedAlways
    }

    /// Đồng bộ danh sách vùng theo dõi với dữ liệu hiện có. Gọi khi mở app, khi đổi công tắc và sau khi lưu.
    func refresh() async {
        guard isEnabled else {
            await stop()
            return
        }
        let monitor = await ensureMonitor()
        let wanted = PlaceSuggester.monitoredPlaces(records: records())
        places = Dictionary(wanted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for identifier in await monitor.identifiers where places[identifier] == nil {
            await monitor.remove(identifier)
        }
        let existing = Set(await monitor.identifiers)
        for place in wanted where !existing.contains(place.id) {
            let center = CLLocationCoordinate2D(latitude: place.center.latitude, longitude: place.center.longitude)
            let condition = CLMonitor.CircularGeographicCondition(center: center, radius: PlaceSuggester.radius)
            await monitor.add(condition, identifier: place.id)
        }
        NotificationManager.shared.registerLeaveCategories(for: wanted)
    }

    private func ensureMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let created = await CLMonitor(Self.monitorName)
        monitor = created
        session = CLServiceSession(authorization: .always)
        listener = Task { [weak self] in
            do {
                for try await event in await created.events where event.state == .unsatisfied {
                    self?.didLeave(event.identifier)
                }
            } catch {
                // Luồng sự kiện đóng khi hệ thống thu hồi quyền; refresh() lần sau sẽ dựng lại.
            }
        }
        return created
    }

    private func stop() async {
        listener?.cancel()
        listener = nil
        session = nil
        if let monitor {
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
            }
        }
        monitor = nil
        places = [:]
    }

    private func didLeave(_ identifier: String) {
        guard isEnabled, let place = places[identifier] else { return }
        let now = Date()
        let calendar = Calendar.current
        let lastNotified = AppGroup.defaults.dictionary(forKey: Self.lastNotifiedKey) as? [String: String] ?? [:]
        guard LeaveReminderPolicy.shouldNotify(
            place: place, lastNotified: lastNotified, records: records(), now: now, calendar: calendar
        ) else { return }
        AppGroup.defaults.set(
            LeaveReminderPolicy.marking(identifier, in: lastNotified, now: now, calendar: calendar),
            forKey: Self.lastNotifiedKey
        )
        NotificationManager.shared.notifyLeaving(place)
    }

    /// Mọi khoản có tọa độ.
    private func records() -> [SuggestionRecord] {
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.latitude != nil })
        return ((try? XuStore.shared.mainContext.fetch(descriptor)) ?? []).map(\.suggestionRecord)
    }
}
