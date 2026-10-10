import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Tệp CSV chỉ được tạo khi người dùng chọn nơi chia sẻ.
struct ExpenseCSVFile: Transferable {
    let records: [ExportRecord]
    let calendar: Calendar

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let name = CSVExporter.fileName(now: Date(), calendar: file.calendar)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try CSVExporter.csv(file.records, calendar: file.calendar).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

/// Dòng "Xuất dữ liệu" trong Tùy chỉnh: mọi khoản chi, không giới hạn 35 ngày.
struct ExportDataRow: View {
    @Environment(\.calendar) private var calendar
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @Query private var customCategories: [CustomCategory]

    var body: some View {
        let catalog = CategoryCatalog(custom: customCategories)
        let records = expenses.map {
            ExportRecord(
                date: $0.date, name: $0.name, amount: $0.amount, categoryTitle: catalog.info(for: $0.categoryKey).title,
                isOutsideBudget: $0.isOutsideBudget, placeName: $0.placeName
            )
        }
        ShareLink(
            item: ExpenseCSVFile(records: records, calendar: calendar),
            preview: SharePreview(CSVExporter.fileName(now: Date(), calendar: calendar))
        ) {
            HStack {
                Text("Xuất dữ liệu ra CSV").foregroundStyle(Color.xuTextPrimary)
                Spacer()
                Text("\(expenses.count) khoản").foregroundStyle(Color.xuTextSecondary)
            }
        }
        .disabled(expenses.isEmpty)
    }
}

#Preview {
    Form { ExportDataRow() }.xuPreview()
}
