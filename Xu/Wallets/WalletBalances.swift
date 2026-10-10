import Foundation

/// Một ví nhìn từ phía tính số dư: số dư ban đầu và ngày bắt đầu tính.
struct WalletSnapshot: Equatable, Sendable, Identifiable {
    var id: UUID
    var openingBalance: Int
    /// Chỉ tính các biến động từ ngày này: số dư ban đầu đã phản ánh mọi thứ trước đó.
    var startDate: Date
}

/// Một biến động tiền của một ví: âm là tiền ra (chi tiêu, cho mượn, chuyển đi), dương là tiền vào.
struct WalletMovement: Equatable, Sendable {
    var walletID: UUID
    var delta: Int
    var date: Date
}

/// Một lần chuyển tiền: giữa hai ví, hoặc từ bên ngoài vào (thu nhập, nạp tiền), hoặc từ ví ra bên ngoài (rút, chuyển cho người khác).
struct WalletTransferRecord: Equatable, Sendable {
    /// nil: tiền từ bên ngoài.
    var from: UUID?
    /// nil: tiền đi ra bên ngoài.
    var to: UUID?
    var amount: Int
    var date: Date

    /// Tối đa hai biến động: tiền ra khỏi ví nguồn và tiền vào ví đích.
    var movements: [WalletMovement] {
        var result: [WalletMovement] = []
        if let from { result.append(WalletMovement(walletID: from, delta: -amount, date: date)) }
        if let to { result.append(WalletMovement(walletID: to, delta: amount, date: date)) }
        return result
    }

    /// Hợp lệ khi số tiền dương, có ít nhất một ví, và hai ví khác nhau.
    var isValid: Bool {
        amount > 0 && (from != nil || to != nil) && from != to
    }
}

enum WalletBalances {
    /// Số dư hiện tại của từng ví: số dư ban đầu cộng mọi biến động từ ngày bắt đầu.
    static func balances(wallets: [WalletSnapshot], movements: [WalletMovement]) -> [UUID: Int] {
        var result = Dictionary(wallets.map { ($0.id, $0.openingBalance) }, uniquingKeysWith: { first, _ in first })
        let starts = Dictionary(wallets.map { ($0.id, $0.startDate) }, uniquingKeysWith: { first, _ in first })
        for movement in movements {
            guard let start = starts[movement.walletID], movement.date >= start else { continue }
            result[movement.walletID, default: 0] += movement.delta
        }
        return result
    }

    /// Đọc số tiền có thể mang dấu trừ ("-200k" cho dư nợ thẻ). Dùng bộ đọc tiền thường cho phần số.
    static func signedAmount(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("-") || trimmed.hasPrefix("−") {
            return AmountParser.amount(from: String(trimmed.dropFirst())).map { -$0 }
        }
        return AmountParser.amount(from: trimmed)
    }

    /// Ví khớp với một tin nhắn: từ khóa của ví (ngăn cách bằng dấu phẩy hoặc xuống dòng) xuất hiện trong tin nhắn,
    /// không phân biệt dấu và hoa thường. Từ khóa dài nhất thắng; nil khi không ví nào khớp.
    static func wallet(matching message: String, keywords: [(id: UUID, keywords: String)]) -> UUID? {
        let text = TextNormalizer.fold(message)
        var best: (id: UUID, length: Int)?
        for entry in keywords {
            for keyword in entry.keywords.split(whereSeparator: { ",;\n".contains($0) }) {
                let folded = TextNormalizer.fold(String(keyword)).trimmingCharacters(in: .whitespaces)
                guard folded.count >= 2, text.contains(folded), folded.count > (best?.length ?? 0) else { continue }
                best = (entry.id, folded.count)
            }
        }
        return best?.id
    }
}
