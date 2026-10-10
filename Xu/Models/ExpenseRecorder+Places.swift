import Foundation
import SwiftData

/// Nơi ghi của khoản chi.
extension ExpenseRecorder {
    /// App gắn vào đây để tra tên nơi (cần mạng) cho khoản vừa ghi mà chưa dùng lại được tên cũ.
    static var afterLocatedRecord: (@MainActor (UUID) -> Void)?

    private func locatedExpenses() -> [Expense] {
        (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.latitude != nil && $0.longitude != nil }))) ?? []
    }

    /// Mọi khoản có tọa độ, kể cả chưa có tên.
    func locatedItems() -> [LocatedItem] {
        locatedExpenses().compactMap { expense in
            guard let latitude = expense.latitude, let longitude = expense.longitude else { return nil }
            return LocatedItem(
                id: expense.id, coordinate: Coordinate(latitude: latitude, longitude: longitude),
                name: expense.placeName, date: expense.date
            )
        }
    }

    /// Các nơi đã có tên.
    func namedPlaces() -> [NamedPlaceRecord] {
        locatedItems().compactMap { item in
            item.name.map { NamedPlaceRecord(coordinate: item.coordinate, name: $0, date: item.date) }
        }
    }

    /// Đặt tên cho các khoản theo mã. Trả về số khoản đã đổi.
    @discardableResult
    func setPlaceName(_ name: String?, forExpensesWithIDs ids: [UUID]) -> Int {
        let wanted = Set(ids)
        let cleaned = PlaceNaming.clean(name)
        var changed = 0
        for expense in locatedExpenses() where wanted.contains(expense.id) && expense.placeName != cleaned {
            expense.placeName = cleaned
            changed += 1
        }
        if changed > 0 { commit() }
        return changed
    }

    /// Đặt hoặc xóa tên nơi của một khoản. Khoản chưa có tọa độ cũng đặt tên tay được.
    /// Với `applyingToSiblings`, các khoản khác ở cùng chỗ và còn mang tên cũ đổi theo. Trả về số khoản đã đổi, gồm cả khoản này.
    @discardableResult
    func setPlace(of expense: Expense, to name: String?, applyingToSiblings: Bool) -> Int {
        let cleaned = PlaceNaming.clean(name)
        let oldName = expense.placeName
        var ids = [expense.id]
        if applyingToSiblings, let latitude = expense.latitude, let longitude = expense.longitude {
            ids += PlaceNaming.siblings(
                of: Coordinate(latitude: latitude, longitude: longitude), among: locatedItems(),
                oldName: oldName, excluding: expense.id
            )
        }
        if expense.placeName != cleaned { expense.placeName = cleaned }
        let others = setPlaceName(cleaned, forExpensesWithIDs: Array(ids.dropFirst()))
        commit()
        return 1 + others
    }

    /// Số khoản khác sẽ đổi theo nếu đổi tên nơi của `expense` và áp cho cả chỗ này.
    func siblingCount(of expense: Expense) -> Int {
        guard let latitude = expense.latitude, let longitude = expense.longitude else { return 0 }
        return PlaceNaming.siblings(
            of: Coordinate(latitude: latitude, longitude: longitude), among: locatedItems(),
            oldName: expense.placeName, excluding: expense.id
        ).count
    }
}
