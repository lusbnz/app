import Foundation
import SwiftData
import Testing
@testable import Xu

struct CategoryNamingTests {
    @Test func trimsAndCollapsesSpaces() {
        #expect(CategoryNaming.validate("  Thú   cưng ", existing: []) == .success("Thú cưng"))
    }

    @Test func rejectsEmpty() {
        #expect(CategoryNaming.validate("   ", existing: []) == .failure(.empty))
    }

    @Test func rejectsTooLong() {
        #expect(CategoryNaming.validate(String(repeating: "a", count: 21), existing: []) == .failure(.tooLong))
        #expect(CategoryNaming.validate(String(repeating: "a", count: 20), existing: []) == .success(String(repeating: "a", count: 20)))
    }

    @Test func rejectsDuplicateIgnoringCaseAndAccents() {
        #expect(CategoryNaming.validate("an uong", existing: ["ăn uống"]) == .failure(.duplicate))
        #expect(CategoryNaming.validate("ĂN UỐNG", existing: ["ăn uống"]) == .failure(.duplicate))
        #expect(CategoryNaming.validate("Thú cưng", existing: ["ăn uống"]) == .success("Thú cưng"))
    }

    @Test func customKeysAreRecognized() {
        let key = CategoryNaming.makeKey(id: UUID())
        #expect(CategoryNaming.isCustom(key))
        #expect(!CategoryNaming.isCustom("food"))
    }

    @Test func unknownKeyFallsBackToOther() {
        // Danh mục đã xóa không làm khoản chi cũ biến mất khỏi giao diện.
        #expect(SpendingCategory(key: "custom-deleted") == .other)
    }
}

@MainActor
struct CategoryRecorderTests {
    /// Phải giữ `container` sống suốt bài test: ModelContext crash khi container đã bị giải phóng.
    private func makeRecorder() -> (ExpenseRecorder, ModelContext, ModelContainer) {
        let container = XuStore.inMemory()
        return (ExpenseRecorder(context: container.mainContext), container.mainContext, container)
    }

    @Test func addRejectsDuplicateOfBuiltIn() {
        let (recorder, _, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let result = recorder.addCategory(name: "Ăn uống", existing: ["ăn uống"])
        #expect(result.failure == .duplicate)
    }

    @Test func customCategoryCanBeTaughtAndUsed() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let category = try recorder.addCategory(name: "Thú cưng", existing: []).get()
        #expect(recorder.setRule(keyword: "Cát mèo", categoryKey: category.key))
        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        #expect(rules.first?.keyword == TextNormalizer.keyword("Cát mèo"))
        #expect(CategoryClassifier.categoryKey(for: "cát mèo 80k", rules: recorder.rules()) == category.key)
    }

    @Test func emptyRuleKeywordIsRejected() {
        let (recorder, _, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        #expect(!recorder.setRule(keyword: "  ", categoryKey: "food"))
    }

    @Test func settingRuleTwiceUpdatesInsteadOfDuplicating() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        recorder.setRule(keyword: "Phở", categoryKey: "fun")
        recorder.setRule(keyword: "pho", categoryKey: "health")
        let rules = try context.fetch(FetchDescriptor<CategoryRule>())
        #expect(rules.count == 1)
        #expect(rules.first?.categoryKey == "health")
    }

    @Test func renameKeepsKeyAndAllowsSameNameDifferentCase() throws {
        let (recorder, _, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let category = try recorder.addCategory(name: "Thú cưng", existing: []).get()
        let key = category.key
        #expect(recorder.renameCategory(category, to: "THÚ CƯNG", existing: ["Thú cưng"]).failure == nil)
        #expect(category.key == key)
        #expect(category.name == "THÚ CƯNG")
    }

    @Test func deleteMovesExpensesToOtherAndRemovesRules() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let category = try recorder.addCategory(name: "Thú cưng", existing: []).get()
        let key = category.key
        context.insert(Expense(name: "cát mèo", amount: 80_000, categoryKey: key))
        context.insert(Expense(name: "phở", amount: 45_000, categoryKey: "food"))
        recorder.setRule(keyword: "cát mèo", categoryKey: key)
        recorder.setRule(keyword: "phở", categoryKey: "food")

        recorder.deleteCategory(category)

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(expenses.first { $0.name == "cát mèo" }?.categoryKey == "other")
        #expect(expenses.first { $0.name == "phở" }?.categoryKey == "food")
        #expect(try context.fetch(FetchDescriptor<CustomCategory>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CategoryRule>()).map(\.keyword) == [TextNormalizer.keyword("phở")])
    }

    @Test func deleteRuleRemovesOnlyThatRule() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        recorder.setRule(keyword: "phở", categoryKey: "fun")
        recorder.setRule(keyword: "grab", categoryKey: "fun")
        let rule = try #require(try context.fetch(FetchDescriptor<CategoryRule>()).first { $0.keyword == "pho" })
        recorder.deleteRule(rule)
        #expect(try context.fetch(FetchDescriptor<CategoryRule>()).map(\.keyword) == ["grab"])
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { failure } else { nil }
    }
}
