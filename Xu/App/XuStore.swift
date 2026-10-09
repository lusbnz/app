import Foundation
import SwiftData

enum XuStore {
    static let schema = Schema([Expense.self, Loan.self, CategoryRule.self, CustomCategory.self])

    /// Kho dùng chung cho app và intent, đặt trong App Group khi có.
    static let shared: ModelContainer = {
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeFolder().appending(path: "Xu.store"),
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Không mở được kho dữ liệu: \(error)")
        }
    }()

    /// Thư mục App Group nếu dùng được, không thì Application Support.
    /// `containerURL` có thể trả về đường dẫn không tạo được (ví dụ app chạy trên Mac mà chưa có entitlement).
    private static func storeFolder() -> URL {
        for folder in [AppGroup.containerURL, URL.applicationSupportDirectory].compactMap({ $0 }) {
            if (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil {
                return folder
            }
        }
        return URL.applicationSupportDirectory
    }

    static func inMemory()-> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Không tạo được kho trong bộ nhớ: \(error)")
        }
    }
}
