import Foundation
import SwiftData

/// Loại ví, chỉ để chọn biểu tượng.
enum WalletKind: String, CaseIterable, Identifiable, Sendable {
    case cash, bank, card, ewallet

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cash: "banknote"
        case .bank: "building.columns"
        case .card: "creditcard"
        case .ewallet: "iphone"
        }
    }
}

/// Một ví (tiền mặt, tài khoản ngân hàng, thẻ, ví điện tử). Ví không ảnh hưởng ngân sách: ngân sách tính mọi khoản chi của mọi ví.
/// Khoản chi, khoản ứng và lần chuyển tiền nối với ví bằng mã, không dùng quan hệ SwiftData, cho tương thích CloudKit.
@Model final class Wallet {
    var id: UUID = UUID()
    var name: String = ""
    /// `WalletKind.rawValue`.
    var kindRaw: String = "cash"
    /// Số dư lúc tạo ví (âm cho dư nợ thẻ). Số dư hiện tại = số này cộng mọi biến động từ `startDate`.
    var openingBalance: Int = 0
    var startDate: Date = Date()
    /// Từ khóa để nhận tin nhắn ngân hàng thuộc ví này, ngăn cách bằng dấu phẩy ("vcb, vietcombank, 1234").
    var keywords: String = ""
    var createdAt: Date = Date()

    init(name: String, kind: WalletKind = .cash, openingBalance: Int = 0, keywords: String = "", createdAt: Date = Date()) {
        self.name = name
        kindRaw = kind.rawValue
        self.openingBalance = openingBalance
        self.keywords = keywords
        self.createdAt = createdAt
        startDate = createdAt
    }

    var kind: WalletKind {
        get { WalletKind(rawValue: kindRaw) ?? .cash }
        set { kindRaw = newValue.rawValue }
    }

    var snapshot: WalletSnapshot {
        WalletSnapshot(id: id, openingBalance: openingBalance, startDate: startDate)
    }
}

/// Một lần chuyển tiền: giữa hai ví, từ bên ngoài vào (lương, nạp tiền; `fromID` nil) hoặc từ ví ra ngoài (`toID` nil).
/// Không phải chi tiêu nên không bao giờ tính vào ngân sách.
@Model final class WalletTransfer {
    var id: UUID = UUID()
    var fromID: UUID?
    var toID: UUID?
    var amount: Int = 0
    var date: Date = Date()
    var note: String = ""

    init(fromID: UUID?, toID: UUID?, amount: Int, date: Date = Date(), note: String = "") {
        self.fromID = fromID
        self.toID = toID
        self.amount = amount
        self.date = date
        self.note = note
    }

    var record: WalletTransferRecord {
        WalletTransferRecord(from: fromID, to: toID, amount: amount, date: date)
    }
}
