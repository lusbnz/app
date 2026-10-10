import Foundation
import SwiftData
import Testing
@testable import Xu

struct CategoryIconTests {
    @Test func everyBuiltInCategoryHasItsOwnSymbol() {
        let symbols = SpendingCategory.allCases.map(CategoryIcon.symbol(for:))
        #expect(Set(symbols).count == SpendingCategory.allCases.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    @Test func paletteHasNoDuplicatesAndContainsFallback() {
        #expect(Set(CategoryIcon.palette).count == CategoryIcon.palette.count)
        #expect(CategoryIcon.palette.contains(CategoryIcon.fallback))
    }

    @Test func everySuggestionIsInThePalette() {
        let names = ["thú cưng", "tiền nhà", "học phí", "du lịch", "quà tặng", "cắt tóc", "xe đạp", "cà phê", "sinh nhật", "tiết kiệm"]
        for name in names {
            #expect(CategoryIcon.palette.contains(CategoryIcon.suggest(for: name)), "\(name)")
        }
    }

    @Test func suggestsByNameIgnoringCaseAndAccents() {
        #expect(CategoryIcon.suggest(for: "Thú cưng") == "pawprint")
        #expect(CategoryIcon.suggest(for: "thu cung") == "pawprint")
        #expect(CategoryIcon.suggest(for: "Sách vở") == "book")
        #expect(CategoryIcon.suggest(for: "Gym") == "dumbbell")
    }

    @Test func longerPhraseBeatsShorterOne() {
        // "học phí" (2 từ) thắng "học" (1 từ) nhưng cùng biểu tượng; "xe đạp" thắng "xe".
        #expect(CategoryIcon.suggest(for: "xe đạp") == "bicycle")
        #expect(CategoryIcon.suggest(for: "xe buýt") == "bus")
        #expect(CategoryIcon.suggest(for: "tiền nhà") == "house")
    }

    @Test func unknownOrEmptyNameFallsBack() {
        #expect(CategoryIcon.suggest(for: "") == CategoryIcon.fallback)
        #expect(CategoryIcon.suggest(for: "zzz") == CategoryIcon.fallback)
    }

    @Test func resolvedRejectsStrangeValues() {
        #expect(CategoryIcon.resolved("") == CategoryIcon.fallback)
        #expect(CategoryIcon.resolved("không.tồn.tại") == CategoryIcon.fallback)
        #expect(CategoryIcon.resolved("pawprint") == "pawprint")
    }
}

@MainActor
struct CategoryIconRecorderTests {
    @Test func customCategoryKeepsItsIconAndCatalogShowsIt() throws {
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let recorder = ExpenseRecorder(context: container.mainContext)
        let pets = try recorder.addCategory(name: "Thú cưng", existing: [], iconName: "pawprint").get()
        let plain = try recorder.addCategory(name: "Linh tinh", existing: []).get()

        let catalog = CategoryCatalog(custom: [pets, plain])
        #expect(catalog.info(for: pets.key).symbol == "pawprint")
        #expect(catalog.info(for: plain.key).symbol == CategoryIcon.fallback)
        #expect(catalog.info(for: "food").symbol == CategoryIcon.symbol(for: .food))
        #expect(catalog.info(for: "custom-đã-xóa").symbol == CategoryIcon.symbol(for: .other))
    }

    @Test func renameChangesIconOnlyWhenGiven() throws {
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let recorder = ExpenseRecorder(context: container.mainContext)
        let category = try recorder.addCategory(name: "Mèo", existing: [], iconName: "pawprint").get()
        try recorder.renameCategory(category, to: "Mèo con", existing: ["Mèo"]).get()
        #expect(category.iconName == "pawprint")
        try recorder.renameCategory(category, to: "Mèo con", existing: [], iconName: "heart").get()
        #expect(category.iconName == "heart")
    }
}
