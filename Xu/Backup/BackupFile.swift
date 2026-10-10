import Foundation

// Bản sao lưu là một tệp JSON đọc được, chứa dữ liệu của người dùng. Không chứa cài đặt riêng của máy
// (giao diện, ngôn ngữ, thông báo, khóa app) vì những thứ đó đặt lại theo máy mới.

struct BackupExpense: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var amount: Int
    var categoryKey: String
    var date: Date
    var createdAt: Date
    var rawText: String
    var batchID: UUID
    var isOutsideBudget: Bool
    var originalAmount: Int?
    var splitCount: Int?
    var foreignCurrency: String?
    var foreignMinor: Int?
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    /// JPEG đã nén, viết bằng base64. Nil khi bản sao lưu không kèm ảnh.
    var photo: Data?
}

struct BackupLoan: Codable, Equatable, Sendable {
    var id: UUID
    var person: String
    var amount: Int
    var date: Date
    var isRepaid: Bool
}

struct BackupRule: Codable, Equatable, Sendable {
    var keyword: String
    var categoryKey: String
    var updatedAt: Date
}

struct BackupCategory: Codable, Equatable, Sendable {
    var key: String
    var name: String
    var createdAt: Date
    var iconName: String
}

struct BackupLimit: Codable, Equatable, Sendable {
    var categoryKey: String
    var amount: Int
    var updatedAt: Date
}

struct BackupRecurring: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var amount: Int
    var categoryKey: String
    var dayOfMonth: Int
    var isOutsideBudget: Bool
    var createdAt: Date
    var handledMonth: String
    /// `RecurringFrequency.rawValue`.
    var frequency: String
    var weekday: Int
    var monthOfYear: Int
    var autoRecord: Bool
    var remindDayBefore: Bool
}

struct BackupGoal: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var targetAmount: Int
    var createdAt: Date
    var deadline: Date?
}

struct BackupDeposit: Codable, Equatable, Sendable {
    var id: UUID
    var goalID: UUID
    var amount: Int
    var date: Date
    var note: String
}

/// Phần cài đặt thuộc về dữ liệu: ngân sách và tỷ giá người dùng đã chỉnh.
struct BackupSettings: Codable, Equatable, Sendable {
    var monthlyBudget: Int = 0
    var weeklyBudget: Int = 0
    /// `BudgetPeriod.rawValue`.
    var budgetPeriod: String = "month"
    /// Mã tiền (chữ thường) → tỷ giá viết bằng chữ, đúng như `ExchangeRates.stored`.
    var exchangeRates: [String: String] = [:]
}

struct BackupFile: Codable, Equatable, Sendable {
    static let appName = "Pennyline"
    static let currentVersion = 1

    var app = BackupFile.appName
    var version = BackupFile.currentVersion
    var createdAt: Date
    var settings = BackupSettings()
    var expenses: [BackupExpense] = []
    var loans: [BackupLoan] = []
    var rules: [BackupRule] = []
    var customCategories: [BackupCategory] = []
    var categoryLimits: [BackupLimit] = []
    var recurring: [BackupRecurring] = []
    var goals: [BackupGoal] = []
    var deposits: [BackupDeposit] = []

    init(
        createdAt: Date, settings: BackupSettings = BackupSettings(), expenses: [BackupExpense] = [], loans: [BackupLoan] = [],
        rules: [BackupRule] = [], customCategories: [BackupCategory] = [], categoryLimits: [BackupLimit] = [],
        recurring: [BackupRecurring] = [], goals: [BackupGoal] = [], deposits: [BackupDeposit] = []
    ) {
        self.createdAt = createdAt
        self.settings = settings
        self.expenses = expenses
        self.loans = loans
        self.rules = rules
        self.customCategories = customCategories
        self.categoryLimits = categoryLimits
        self.recurring = recurring
        self.goals = goals
        self.deposits = deposits
    }

    /// Thiếu mục nào thì coi là rỗng, để tệp sửa tay hoặc từ bản cũ vẫn đọc được.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(String.self, forKey: .app)
        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        settings = try container.decodeIfPresent(BackupSettings.self, forKey: .settings) ?? BackupSettings()
        expenses = try container.decodeIfPresent([BackupExpense].self, forKey: .expenses) ?? []
        loans = try container.decodeIfPresent([BackupLoan].self, forKey: .loans) ?? []
        rules = try container.decodeIfPresent([BackupRule].self, forKey: .rules) ?? []
        customCategories = try container.decodeIfPresent([BackupCategory].self, forKey: .customCategories) ?? []
        categoryLimits = try container.decodeIfPresent([BackupLimit].self, forKey: .categoryLimits) ?? []
        recurring = try container.decodeIfPresent([BackupRecurring].self, forKey: .recurring) ?? []
        goals = try container.decodeIfPresent([BackupGoal].self, forKey: .goals) ?? []
        deposits = try container.decodeIfPresent([BackupDeposit].self, forKey: .deposits) ?? []
    }

    var itemCount: Int {
        expenses.count + loans.count + rules.count + customCategories.count + categoryLimits.count
            + recurring.count + goals.count + deposits.count
    }
}

enum BackupError: Error, Equatable, Sendable {
    /// Không phải tệp sao lưu của Pennyline.
    case notABackup
    /// Tệp tạo bởi bản Pennyline mới hơn bản này.
    case newerVersion(Int)
    /// Đúng là tệp sao lưu nhưng hỏng hoặc thiếu phần bắt buộc.
    case unreadable
}

enum BackupCodec {
    /// Tệp lớn hơn mức này bị từ chối khi khôi phục (ảnh nén chiếm phần lớn dung lượng).
    static let maxBytes = 300_000_000

    /// `pretty` cho tệp người dùng có thể mở đọc; tắt đi cho bản tự động để nhẹ hơn.
    static func encode(_ file: BackupFile, pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        struct Header: Decodable {
            var app: String?
            var version: Int?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data),
              header.app == BackupFile.appName, let version = header.version else { throw BackupError.notABackup }
        guard version <= BackupFile.currentVersion else { throw BackupError.newerVersion(version) }
        do {
            return try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
    }
}
