import SwiftData
import SwiftUI

/// Xem trước một tệp CSV trước khi nhập: bao nhiêu khoản sẽ vào, bao nhiêu bị bỏ và vì sao. Nhập xong vẫn hoàn tác được.
struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query private var rules: [CategoryRule]
    @Query private var customCategories: [CustomCategory]
    @State private var parsed: Result<CSVImportResult, CSVImportFailure>?
    @State private var imported: Imported?
    let source: CSVImportSource

    /// Lô vừa nhập, để hoàn tác.
    private struct Imported {
        var batchID: UUID
        var count: Int
        var isUndone = false
    }

    var body: some View {
        NavigationStack {
            List {
                switch parsed {
                case nil:
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                case .failure(let failure):
                    failureSection(failure)
                case .success(let result):
                    if let imported {
                        doneSection(imported)
                    } else {
                        summarySection(result)
                        if !result.rows.isEmpty { previewSection(result) }
                        if !result.rejected.isEmpty { rejectedSection(result) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle("Nhập từ CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(imported == nil ? "Hủy" : "Xong") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if imported == nil, case .success(let result)? = parsed, !result.rows.isEmpty {
                    Button { runImport(result.rows) } label: {
                        Text("Nhập \(result.rows.count) khoản")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            }
        }
        .task { await parse() }
        .fontDesign(.rounded)
    }

    // MARK: - Các phần

    private func summarySection(_ result: CSVImportResult) -> some View {
        Section {
            row("Sẽ nhập", String(localized: "\(result.rows.count) khoản"))
            if let first = result.firstDate, let last = result.lastDate {
                row("Thời gian", VietnameseDate.range(first, last, now: Date(), calendar: calendar))
                row("Tổng", MoneyFormatter.short(result.total))
            }
            if result.duplicates > 0 { row("Đã có trên máy, bỏ qua", "\(result.duplicates)") }
            if result.skippedIncome > 0 { row("Tiền vào, bỏ qua", "\(result.skippedIncome)") }
            if !result.rejected.isEmpty { row("Dòng không đọc được", "\(result.rejected.count)") }
        } header: {
            Text(verbatim: source.name)
        } footer: {
            if result.rows.isEmpty {
                Text("Không có khoản nào mới để nhập từ tệp này.")
            }
        }
        .listRowBackground(Color.xuSurface)
    }

    private func previewSection(_ result: CSVImportResult) -> some View {
        let catalog = CategoryCatalog(custom: customCategories)
        let now = Date()
        return Section {
            ForEach(Array(result.rows.prefix(5).enumerated()), id: \.offset) { _, expense in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(expense.name.isEmpty ? String(localized: "khoản chi") : expense.name)
                        Text("\(VietnameseDate.relativeDay(expense.date, now: now, calendar: calendar)) · \(catalog.info(for: expense.categoryKey).title)")
                            .font(.caption)
                            .foregroundStyle(Color.xuTextSecondary)
                    }
                    Spacer()
                    Text(MoneyFormatter.short(expense.amount))
                        .foregroundStyle(Color.xuTextSecondary)
                }
            }
        } header: {
            Text("Xem trước")
        } footer: {
            if result.rows.count > 5 {
                Text("Và \(result.rows.count - 5) khoản nữa.")
            }
        }
        .listRowBackground(Color.xuSurface)
    }

    private func rejectedSection(_ result: CSVImportResult) -> some View {
        Section {
            ForEach(Array(result.rejected.prefix(10).enumerated()), id: \.offset) { _, rejected in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dòng \(rejected.line): \(reason(rejected.reason))")
                    Text(verbatim: rejected.text)
                        .font(.caption)
                        .foregroundStyle(Color.xuTextSecondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("Dòng bị bỏ")
        } footer: {
            if result.rejected.count > 10 {
                Text("Và \(result.rejected.count - 10) dòng nữa.")
            }
        }
        .listRowBackground(Color.xuSurface)
    }

    private func failureSection(_ failure: CSVImportFailure) -> some View {
        Section {
            switch failure {
            case .empty:
                Text("Tệp trống.")
            case .missingColumns(let date, let amount):
                VStack(alignment: .leading, spacing: 6) {
                    if date { Text("Không thấy cột ngày.") }
                    if amount { Text("Không thấy cột số tiền.") }
                    Text("Dòng tiêu đề cần có cột “Ngày” và cột “Số tiền” (hoặc “Ghi nợ”). Cột “Tên”, “Danh mục”, “Nơi” có thì càng đầy đủ.")
                        .font(.footnote)
                        .foregroundStyle(Color.xuTextSecondary)
                }
            }
        } header: {
            Text(verbatim: source.name)
        }
        .listRowBackground(Color.xuSurface)
    }

    private func doneSection(_ imported: Imported) -> some View {
        Section {
            if imported.isUndone {
                Text("Đã hoàn tác, \(imported.count) khoản đã được gỡ.")
            } else {
                Text("Đã nhập \(imported.count) khoản.")
                Button("Hoàn tác", role: .destructive) { undo(imported) }
            }
        }
        .listRowBackground(Color.xuSurface)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value).foregroundStyle(Color.xuTextSecondary)
        }
    }

    private func reason(_ reason: ImportRejection) -> String {
        switch reason {
        case .badDate: String(localized: "ngày không đọc được")
        case .badAmount: String(localized: "số tiền không đọc được")
        case .futureDate: String(localized: "ngày ở tương lai")
        }
    }

    // MARK: - Việc làm

    private func parse() async {
        let options = CSVImporter.Options(
            rules: rules.lookup,
            customCategories: customCategories.map { CSVImporter.CategoryName(key: $0.key, name: $0.name) },
            existing: ExpenseRecorder(context: modelContext).existingSignatures(),
            now: Date(), calendar: calendar
        )
        let text = source.text
        parsed = await Task.detached(priority: .userInitiated) { CSVImporter.importExpenses(from: text, options: options) }.value
    }

    private func runImport(_ rows: [ImportedExpense]) {
        let batchID = ExpenseRecorder(context: modelContext).importExpenses(rows, now: Date())
        imported = Imported(batchID: batchID, count: rows.count)
    }

    private func undo(_ batch: Imported) {
        ExpenseRecorder(context: modelContext).undoImport(batchID: batch.batchID)
        imported?.isUndone = true
    }
}
