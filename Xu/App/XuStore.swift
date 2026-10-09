import Foundation
import SwiftData

enum XuStore {
    static let schema = Schema([Expense.self, Loan.self, CategoryRule.self])

    /// Kho dùng chung cho app, intent và widget, đặt trong App Group khi có.
    static let shared: ModelContainer = {
        let folder = AppGroup.containerURL ?? URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            schema: schema,
            url: folder.appending(path: "Xu.store"),
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Không mở được kho dữ liệu: \(error)")
        }
    }()

    static func inMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Không tạo được kho trong bộ nhớ: \(error)")
        }
    }
}
