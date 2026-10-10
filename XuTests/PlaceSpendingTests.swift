import Foundation
import Testing
@testable import Xu

struct PlaceSpendingTests {
    private let here = Coordinate(latitude: 10.7769, longitude: 106.7009)

    private func north(_ meters: Double) -> Coordinate {
        Coordinate(latitude: here.latitude + meters / 111_320, longitude: here.longitude)
    }

    private func record(_ amount: Int, at coordinate: Coordinate, name: String? = nil, category: String = "food", day: Int = 1) -> PlaceRecord {
        PlaceRecord(coordinate: coordinate, name: name, amount: amount, date: TestClock.date(2026, 10, day), categoryKey: category)
    }

    @Test func groupsNearbyRecordsAndSortsByTotal() {
        let spends = PlaceSpending.totals([
            record(50_000, at: here, name: "Phở Thìn"),
            record(60_000, at: north(20), name: "Phở Thìn", day: 2),
            record(500_000, at: north(800), name: "Siêu thị"),
            record(30_000, at: north(2_000)),
        ])
        #expect(spends.count == 3)
        #expect(spends.map(\.total) == [500_000, 110_000, 30_000])
        #expect(spends[1].count == 2)
        #expect(spends[1].name == "Phở Thìn")
        #expect(spends[2].name == nil)
    }

    @Test func nameIsTheMostCommonOneIgnoringCaseAndAccents() {
        let spends = PlaceSpending.totals([
            record(10_000, at: here, name: "pho thin", day: 1),
            record(10_000, at: here, name: "Phở Thìn", day: 2),
            record(10_000, at: here, name: "Quán khác", day: 3),
        ])
        #expect(spends.count == 1)
        #expect(spends[0].name == "Phở Thìn")                 // hai tên cùng khóa, lấy cách viết của khoản mới hơn
    }

    @Test func unnamedRecordsDoNotHideANamedOne() {
        let spends = PlaceSpending.totals([record(10_000, at: here), record(10_000, at: here, name: "Cà phê X")])
        #expect(spends[0].name == "Cà phê X")
    }

    @Test func topCategoryIsTheOneWithTheMostMoney() {
        let spends = PlaceSpending.totals([
            record(10_000, at: here, category: "food", day: 1),
            record(10_000, at: here, category: "food", day: 2),
            record(300_000, at: here, category: "shopping", day: 3),
        ])
        #expect(spends[0].topCategoryKey == "shopping")
        #expect(spends[0].lastDate == TestClock.date(2026, 10, 3))
    }

    @Test func emptyInputGivesNothing() {
        #expect(PlaceSpending.totals([]).isEmpty)
        #expect(PlaceSpending.region(of: []) == nil)
    }

    @Test func regionFramesAllPlacesWithAMinimumSpan() throws {
        let one = PlaceSpending.totals([record(10_000, at: here)])
        let single = try #require(PlaceSpending.region(of: one))
        #expect(single.latitudeSpan >= 0.008 && single.longitudeSpan >= 0.008)
        #expect(abs(single.center.latitude - here.latitude) < 1e-9)

        let many = PlaceSpending.totals([record(10_000, at: here), record(10_000, at: north(5_000))])
        let region = try #require(PlaceSpending.region(of: many))
        #expect(region.latitudeSpan > 0.04)                    // 5 km ≈ 0,045 độ, cộng lề
        #expect(region.center.latitude > here.latitude && region.center.latitude < north(5_000).latitude)
    }
}
