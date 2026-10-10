import Foundation
import SwiftData

/// Sao lưu, khôi phục và nhập CSV: chuyển dữ liệu giữa SwiftData và tệp. Phần quyết định nằm ở `BackupMerger` và `CSVImporter` (logic thuần).
/// Đây là chuyển dữ liệu chứ không phải ghi mới, nên không qua `SaveGate` và không tính vào 5 lần ghi mỗi ngày.
extension ExpenseRecorder {
    private func all<Model: PersistentModel>(_ type: Model.Type, sortedBy sort: [SortDescriptor<Model>] = []) -> [Model] {
        (try? context.fetch(FetchDescriptor<Model>(sortBy: sort))) ?? []
    }

    // MARK: - Sao lưu

    func backupFile(settings: BackupSettings, includesPhotos: Bool, now: Date) -> BackupFile {
        BackupFile(
            createdAt: now,
            settings: settings,
            expenses: all(Expense.self, sortedBy: [SortDescriptor(\.date), SortDescriptor(\.createdAt)]).map { expense in
                BackupExpense(
                    id: expense.id, name: expense.name, amount: expense.amount, categoryKey: expense.categoryKey,
                    date: expense.date, createdAt: expense.createdAt, rawText: expense.rawText, batchID: expense.batchID,
                    isOutsideBudget: expense.isOutsideBudget, originalAmount: expense.originalAmount, splitCount: expense.splitCount,
                    foreignCurrency: expense.foreignCurrency, foreignMinor: expense.foreignMinor,
                    latitude: expense.latitude, longitude: expense.longitude, placeName: expense.placeName,
                    photo: includesPhotos ? expense.photo : nil
                )
            },
            loans: all(Loan.self, sortedBy: [SortDescriptor(\.date)]).map {
                BackupLoan(id: $0.id, person: $0.person, amount: $0.amount, date: $0.date, isRepaid: $0.isRepaid)
            },
            rules: all(CategoryRule.self, sortedBy: [SortDescriptor(\.keyword)]).map {
                BackupRule(keyword: $0.keyword, categoryKey: $0.categoryKey, updatedAt: $0.updatedAt)
            },
            customCategories: all(CustomCategory.self, sortedBy: [SortDescriptor(\.createdAt)]).map {
                BackupCategory(key: $0.key, name: $0.name, createdAt: $0.createdAt, iconName: $0.iconName)
            },
            categoryLimits: all(CategoryBudget.self, sortedBy: [SortDescriptor(\.categoryKey)]).map {
                BackupLimit(categoryKey: $0.categoryKey, amount: $0.amount, updatedAt: $0.updatedAt)
            },
            recurring: all(RecurringExpense.self, sortedBy: [SortDescriptor(\.createdAt)]).map {
                BackupRecurring(
                    id: $0.id, name: $0.name, amount: $0.amount, categoryKey: $0.categoryKey, dayOfMonth: $0.dayOfMonth,
                    isOutsideBudget: $0.isOutsideBudget, createdAt: $0.createdAt, handledMonth: $0.handledMonth,
                    frequency: $0.frequencyRaw, weekday: $0.weekday, monthOfYear: $0.monthOfYear,
                    autoRecord: $0.autoRecord, remindDayBefore: $0.remindDayBefore
                )
            },
            goals: all(SavingsGoal.self, sortedBy: [SortDescriptor(\.createdAt)]).map {
                BackupGoal(id: $0.id, name: $0.name, targetAmount: $0.targetAmount, createdAt: $0.createdAt, deadline: $0.deadline)
            },
            deposits: all(SavingsDeposit.self, sortedBy: [SortDescriptor(\.date)]).map {
                BackupDeposit(id: $0.id, goalID: $0.goalID, amount: $0.amount, date: $0.date, note: $0.note)
            }
        )
    }

    // MARK: - Khôi phục

    func backupExisting() -> BackupExisting {
        BackupExisting(
            expenseIDs: Set(all(Expense.self).map(\.id)),
            loanIDs: Set(all(Loan.self).map(\.id)),
            ruleKeywords: Set(all(CategoryRule.self).map(\.keyword)),
            customCategoryKeys: Set(all(CustomCategory.self).map(\.key)),
            limitKeys: Set(all(CategoryBudget.self).map(\.categoryKey)),
            recurringIDs: Set(all(RecurringExpense.self).map(\.id)),
            goalIDs: Set(all(SavingsGoal.self).map(\.id)),
            depositIDs: Set(all(SavingsDeposit.self).map(\.id))
        )
    }

    /// Thêm các mục trong kế hoạch vào máy. Cài đặt (`plan.settings`) do nơi gọi áp vào `AppSettings`. Trả về số mục đã thêm.
    @discardableResult
    func restore(_ plan: BackupPlan) -> Int {
        for dto in plan.customCategories {
            let category = CustomCategory(name: dto.name, createdAt: dto.createdAt, iconName: dto.iconName)
            category.key = dto.key
            context.insert(category)
        }
        for dto in plan.rules {
            // Luật luôn lưu khóa đã chuẩn hóa; tệp sửa tay có thể chưa.
            let keyword = TextNormalizer.keyword(dto.keyword)
            guard !keyword.isEmpty else { continue }
            context.insert(CategoryRule(keyword: keyword, categoryKey: dto.categoryKey, updatedAt: dto.updatedAt))
        }
        for dto in plan.limits {
            let limit = CategoryBudget(categoryKey: dto.categoryKey, amount: dto.amount)
            limit.updatedAt = dto.updatedAt
            context.insert(limit)
        }
        for dto in plan.expenses {
            let expense = Expense(name: dto.name, amount: dto.amount, categoryKey: dto.categoryKey, date: dto.date)
            expense.id = dto.id
            expense.createdAt = dto.createdAt
            expense.rawText = dto.rawText
            expense.batchID = dto.batchID
            expense.isOutsideBudget = dto.isOutsideBudget
            expense.originalAmount = dto.originalAmount
            expense.splitCount = dto.splitCount
            expense.foreignCurrency = dto.foreignCurrency
            expense.foreignMinor = dto.foreignMinor
            expense.latitude = dto.latitude
            expense.longitude = dto.longitude
            expense.placeName = dto.placeName
            expense.photo = dto.photo
            context.insert(expense)
        }
        for dto in plan.loans {
            let loan = Loan(person: dto.person, amount: dto.amount, date: dto.date)
            loan.id = dto.id
            loan.isRepaid = dto.isRepaid
            context.insert(loan)
        }
        for dto in plan.recurring {
            let item = RecurringExpense(
                name: dto.name, amount: dto.amount, categoryKey: dto.categoryKey, dayOfMonth: dto.dayOfMonth,
                isOutsideBudget: dto.isOutsideBudget, createdAt: dto.createdAt,
                frequency: RecurringFrequency(rawValue: dto.frequency) ?? .monthly, weekday: dto.weekday,
                monthOfYear: dto.monthOfYear, autoRecord: dto.autoRecord, remindDayBefore: dto.remindDayBefore
            )
            item.id = dto.id
            item.handledMonth = dto.handledMonth
            context.insert(item)
        }
        for dto in plan.goals {
            let goal = SavingsGoal(name: dto.name, targetAmount: dto.targetAmount, deadline: dto.deadline, createdAt: dto.createdAt)
            goal.id = dto.id
            context.insert(goal)
        }
        for dto in plan.deposits {
            let deposit = SavingsDeposit(goalID: dto.goalID, amount: dto.amount, date: dto.date, note: dto.note)
            deposit.id = dto.id
            context.insert(deposit)
        }
        commit()
        return plan.newItemCount
    }

    // MARK: - Nhập CSV

    /// Dấu vân tay các khoản đã có, để `CSVImporter` bỏ dòng trùng.
    func existingSignatures() -> [ImportSignature] {
        all(Expense.self).map { ImportSignature(date: $0.date, name: $0.name, amount: $0.amount) }
    }

    /// Ghi các khoản đọc từ CSV thành một lô; trả về mã lô để `undoImport` gỡ lại.
    @discardableResult
    func importExpenses(_ rows: [ImportedExpense], now: Date) -> UUID {
        let batchID = UUID()
        for row in rows {
            let expense = Expense(name: row.name, amount: row.amount, categoryKey: row.categoryKey, date: row.date)
            expense.createdAt = now
            expense.batchID = batchID
            expense.isOutsideBudget = row.isOutsideBudget
            expense.placeName = row.placeName
            context.insert(expense)
        }
        commit()
        return batchID
    }

    /// Gỡ cả lô vừa nhập. Không trả lại lượt ghi trong ngày vì nhập CSV không tốn lượt nào.
    @discardableResult
    func undoImport(batchID: UUID) -> Int {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.batchID == batchID }))) ?? []
        expenses.forEach(context.delete)
        commit()
        return expenses.count
    }
}
