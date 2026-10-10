import Foundation
import SwiftData
import Testing
@testable import Xu

struct PlaceNamingTests {
    private let here = Coordinate(latitude: 10.7769, longitude: 106.7009)
    /// Cách `here` khoảng `meters` mét về phía bắc.
    private func north(_ meters: Double) -> Coordinate {
        Coordinate(latitude: here.latitude + meters / 111_320, longitude: here.longitude)
    }

    @Test func cleanTrimsCollapsesAndLimits() {
        #expect(PlaceNaming.clean("  Phở   Thìn \n 13 Lò Đúc ") == "Phở Thìn 13 Lò Đúc")
        #expect(PlaceNaming.clean("   ") == nil)
        #expect(PlaceNaming.clean(nil) == nil)
        #expect(PlaceNaming.clean(String(repeating: "a", count: 200))?.count == PlaceNaming.maxNameLength)
    }

    @Test func reusesNearestNameWithinTheSameSpotRadius() {
        let places = [
            NamedPlaceRecord(coordinate: north(40), name: "Quán A", date: Date(timeIntervalSince1970: 100)),
            NamedPlaceRecord(coordinate: north(10), name: "Quán B", date: Date(timeIntervalSince1970: 50)),
            NamedPlaceRecord(coordinate: north(200), name: "Quán C", date: Date(timeIntervalSince1970: 200)),
        ]
        #expect(PlaceNaming.reusableName(near: here, in: places) == "Quán B")
        #expect(PlaceNaming.reusableName(near: north(500), in: places) == nil)
        #expect(PlaceNaming.reusableName(near: here, in: []) == nil)
    }

    @Test func equalDistanceTakesTheNewerName() {
        let places = [
            NamedPlaceRecord(coordinate: north(20), name: "Cũ", date: Date(timeIntervalSince1970: 1)),
            NamedPlaceRecord(coordinate: north(20), name: "Mới", date: Date(timeIntervalSince1970: 2)),
        ]
        #expect(PlaceNaming.reusableName(near: here, in: places) == "Mới")
    }

    @Test func nearbyNamesAreOrderedByUse() {
        let places = [
            NamedPlaceRecord(coordinate: north(10), name: "Phở Thìn", date: Date()),
            NamedPlaceRecord(coordinate: north(20), name: "Phở Thìn", date: Date()),
            NamedPlaceRecord(coordinate: north(30), name: "Cà phê X", date: Date()),
            NamedPlaceRecord(coordinate: north(900), name: "Xa", date: Date()),
        ]
        #expect(PlaceNaming.nearbyNames(near: here, in: places) == ["Phở Thìn", "Cà phê X"])
    }

    @Test func rankedSortsByDistanceAndDropsDuplicates() {
        let candidates = [
            PlaceCandidate(name: "Xa", coordinate: north(70)),
            PlaceCandidate(name: "Gần", coordinate: north(5)),
            PlaceCandidate(name: "gan", coordinate: north(6)),       // trùng tên (không phân biệt dấu, hoa thường)
            PlaceCandidate(name: "  ", coordinate: north(1)),
            PlaceCandidate(name: "Giữa", coordinate: north(30)),
        ]
        #expect(PlaceNaming.ranked(candidates, near: here).map(\.name) == ["Gần", "Giữa", "Xa"])
        #expect(PlaceNaming.ranked(candidates, near: here, limit: 2).map(\.name) == ["Gần", "Giữa"])
    }

    @Test func unnamedGroupsClusterNearbyItemsAndSkipNamedOnes() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let items = [
            LocatedItem(id: a, coordinate: here, name: nil, date: Date(timeIntervalSince1970: 10)),
            LocatedItem(id: b, coordinate: north(20), name: nil, date: Date(timeIntervalSince1970: 30)),
            LocatedItem(id: c, coordinate: north(400), name: nil, date: Date(timeIntervalSince1970: 20)),
            LocatedItem(id: d, coordinate: here, name: "Đã có", date: Date(timeIntervalSince1970: 40)),
        ]
        let groups = PlaceNaming.unnamedGroups(items)
        #expect(groups.count == 2)
        #expect(Set(groups[0].ids) == [a, b])            // nhóm có khoản mới nhất (b) đứng trước
        #expect(groups[1].ids == [c])
    }

    @Test func siblingsShareSpotAndOldName() {
        let me = UUID(), same = UUID(), other = UUID(), far = UUID(), unnamed = UUID()
        let items = [
            LocatedItem(id: me, coordinate: here, name: "Tên cũ", date: Date()),
            LocatedItem(id: same, coordinate: north(10), name: "Tên cũ", date: Date()),
            LocatedItem(id: other, coordinate: north(10), name: "Quán khác", date: Date()),
            LocatedItem(id: far, coordinate: north(300), name: "Tên cũ", date: Date()),
            LocatedItem(id: unnamed, coordinate: north(5), name: nil, date: Date()),
        ]
        #expect(PlaceNaming.siblings(of: here, among: items, oldName: "Tên cũ", excluding: me) == [same])
        #expect(PlaceNaming.siblings(of: here, among: items, oldName: nil, excluding: me) == [unnamed])
    }
}

private final class CallCounter: @unchecked Sendable {
    var count = 0
}

private struct FakeSearch: PlaceSearching {
    var results: [PlaceCandidate]
    var counter: CallCounter?
    func candidates(near coordinate: Coordinate) async -> [PlaceCandidate] {
        counter?.count += 1
        return results
    }
}

@MainActor
struct PlaceRecorderTests {
    private let here = Coordinate(latitude: 10.7769, longitude: 106.7009)

    private func make() -> (ExpenseRecorder, ModelContext, ModelContainer) {
        let container = XuStore.inMemory()
        return (ExpenseRecorder(context: container.mainContext), container.mainContext, container)
    }

    private func draft(_ name: String = "phở") -> RecordItem {
        .expense(ExpenseDraft(name: name, amount: 45_000, categoryKey: "food"))
    }

    private func info(_ coordinate: Coordinate, name: String? = nil) -> RecordContext {
        RecordContext(rawText: "x", date: Date(), latitude: coordinate.latitude, longitude: coordinate.longitude, placeName: name)
    }

    /// Bật tra cứu và thay bộ tìm bằng bản giả; trả về hàm khôi phục.
    private func enableLookup(_ results: [PlaceCandidate]) -> () -> Void {
        let key = SettingsKey.placeLookup
        let before = AppGroup.defaults.object(forKey: key)
        let searcher = PlaceLookup.shared.searcher
        AppGroup.defaults.set(true, forKey: key)
        PlaceLookup.shared.searcher = FakeSearch(results: results)
        PlaceLookup.shared.clearCache()
        return {
            PlaceLookup.shared.clearCache()
            if let before { AppGroup.defaults.set(before, forKey: key) } else { AppGroup.defaults.removeObject(forKey: key) }
            PlaceLookup.shared.searcher = searcher
        }
    }

    @Test func recordingNearANamedPlaceReusesTheNameWithoutLookup() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        var lookups = 0
        ExpenseRecorder.afterLocatedRecord = { _ in lookups += 1 }
        defer { ExpenseRecorder.afterLocatedRecord = nil }

        recorder.record([draft()], in: info(here, name: "Phở Thìn"))
        recorder.record([draft()], in: info(Coordinate(latitude: here.latitude + 0.0002, longitude: here.longitude)))
        let all = try context.fetch(FetchDescriptor<Expense>())
        #expect(all.count == 2 && all.allSatisfy { $0.placeName == "Phở Thìn" })
        #expect(lookups == 0)
    }

    @Test func recordingAtANewPlaceAsksForALookupOnce() {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, _, container) = make()
        defer { withExtendedLifetime(container) {} }
        var requested: [UUID] = []
        ExpenseRecorder.afterLocatedRecord = { requested.append($0) }
        defer { ExpenseRecorder.afterLocatedRecord = nil }

        let batch = recorder.record([draft(), draft("cf")], in: info(here))
        #expect(requested == [batch.batchID])
        recorder.record([draft()], in: RecordContext(rawText: "x"))      // không có vị trí: không tra
        #expect(requested.count == 1)
    }

    @Test func lookupNamesTheWholeBatchWithTheNearestPlace() async throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let restore = enableLookup([
            PlaceCandidate(name: "Xa", coordinate: Coordinate(latitude: here.latitude + 0.0005, longitude: here.longitude)),
            PlaceCandidate(name: "Phở Thìn", coordinate: Coordinate(latitude: here.latitude + 0.0001, longitude: here.longitude)),
        ])
        defer { restore() }
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        let batch = recorder.record([draft(), draft("cf")], in: info(here))

        await PlaceLookup.shared.nameBatch(batch.batchID, context: context)
        let all = try context.fetch(FetchDescriptor<Expense>())
        #expect(all.allSatisfy { $0.placeName == "Phở Thìn" })
    }

    @Test func lookupDoesNothingWhenDisabledOrNothingFound() async throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let restore = enableLookup([])
        defer { restore() }
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        let batch = recorder.record([draft()], in: info(here))
        await PlaceLookup.shared.nameBatch(batch.batchID, context: context)
        #expect(try context.fetch(FetchDescriptor<Expense>()).first?.placeName == nil)

        AppGroup.defaults.set(false, forKey: SettingsKey.placeLookup)
        PlaceLookup.shared.clearCache()
        PlaceLookup.shared.searcher = FakeSearch(results: [PlaceCandidate(name: "Có", coordinate: here)])
        await PlaceLookup.shared.nameBatch(batch.batchID, context: context)
        #expect(try context.fetch(FetchDescriptor<Expense>()).first?.placeName == nil)
    }

    @Test func lookupDoesNotOverwriteANameTheUserSetMeanwhile() async throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let restore = enableLookup([PlaceCandidate(name: "Tự động", coordinate: here)])
        defer { restore() }
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        let batch = recorder.record([draft(), draft("cf")], in: info(here))
        let first = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        first.placeName = "Do tôi đặt"
        await PlaceLookup.shared.nameBatch(batch.batchID, context: context)
        let all = try context.fetch(FetchDescriptor<Expense>())
        #expect(Set(all.compactMap(\.placeName)) == ["Do tôi đặt", "Tự động"])
        #expect(first.placeName == "Do tôi đặt")
    }

    @Test func backfillNamesEachSpotOnceAndSkipsLookupForKnownSpots() async throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let restore = enableLookup([PlaceCandidate(name: "Quán mới", coordinate: here)])
        defer { restore() }
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        let far = Coordinate(latitude: here.latitude + 0.01, longitude: here.longitude)
        recorder.record([draft()], in: info(here))
        recorder.record([draft()], in: info(Coordinate(latitude: here.latitude + 0.0001, longitude: here.longitude)))
        recorder.record([draft()], in: info(far))
        recorder.record([draft()], in: RecordContext(rawText: "không vị trí"))

        let named = await PlaceLookup.shared.backfill(context: context, groupLimit: 10)
        #expect(named == 3)
        let all = try context.fetch(FetchDescriptor<Expense>())
        #expect(all.filter { $0.placeName == "Quán mới" }.count == 3)
        #expect(all.filter { $0.latitude == nil }.allSatisfy { $0.placeName == nil })
    }

    @Test func changingAPlaceCanCarryItsSiblingsAlong() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        recorder.record([draft()], in: info(here, name: "Tên cũ"))
        recorder.record([draft()], in: info(here, name: "Tên cũ"))
        recorder.record([draft()], in: info(here, name: "Quán khác"))
        let all = try context.fetch(FetchDescriptor<Expense>())
        let target = try #require(all.first { $0.placeName == "Tên cũ" })
        #expect(recorder.siblingCount(of: target) == 1)

        #expect(recorder.setPlace(of: target, to: "  Tên   mới ", applyingToSiblings: true) == 2)
        let after = try context.fetch(FetchDescriptor<Expense>())
        #expect(after.filter { $0.placeName == "Tên mới" }.count == 2)
        #expect(after.filter { $0.placeName == "Quán khác" }.count == 1)
    }

    @Test func changingOnlyThisExpenseLeavesSiblings() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        recorder.record([draft()], in: info(here, name: "Tên cũ"))
        recorder.record([draft()], in: info(here, name: "Tên cũ"))
        let all = try context.fetch(FetchDescriptor<Expense>())
        recorder.setPlace(of: all[0], to: "Riêng", applyingToSiblings: false)
        #expect(Set(try context.fetch(FetchDescriptor<Expense>()).compactMap(\.placeName)) == ["Riêng", "Tên cũ"])
    }

    @Test func clearingANameAndNamingAnExpenseWithoutLocationWork() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        recorder.record([draft()], in: RecordContext(rawText: "x"))
        let expense = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        recorder.setPlace(of: expense, to: "Quán quen", applyingToSiblings: true)
        #expect(expense.placeName == "Quán quen")
        recorder.setPlace(of: expense, to: "   ", applyingToSiblings: true)
        #expect(expense.placeName == nil)
    }
}

@MainActor
struct PlaceLookupCacheTests {
    private let here = Coordinate(latitude: 10.7769, longitude: 106.7009)

    @Test func foundNamesAreRememberedAndMissesAreNot() async {
        let searcher = PlaceLookup.shared.searcher
        defer { PlaceLookup.shared.searcher = searcher; PlaceLookup.shared.clearCache() }
        PlaceLookup.shared.clearCache()

        let counter = CallCounter()
        PlaceLookup.shared.searcher = FakeSearch(results: [], counter: counter)
        #expect(await PlaceLookup.shared.bestName(near: here) == nil)
        #expect(await PlaceLookup.shared.bestName(near: here) == nil)
        #expect(counter.count == 2)                               // lần thất bại không được nhớ

        let hits = CallCounter()
        PlaceLookup.shared.searcher = FakeSearch(results: [PlaceCandidate(name: "Phở Thìn", coordinate: here)], counter: hits)
        #expect(await PlaceLookup.shared.bestName(near: here) == "Phở Thìn")
        #expect(await PlaceLookup.shared.bestName(near: here) == "Phở Thìn")
        let nearby = Coordinate(latitude: here.latitude + 0.00002, longitude: here.longitude)     // cùng ô lưới 10 m
        #expect(await PlaceLookup.shared.bestName(near: nearby) == "Phở Thìn")
        #expect(hits.count == 1)
        let far = Coordinate(latitude: here.latitude + 0.01, longitude: here.longitude)
        #expect(await PlaceLookup.shared.bestName(near: far) == "Phở Thìn")
        #expect(hits.count == 2)
    }
}
