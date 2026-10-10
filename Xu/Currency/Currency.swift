import Foundation

/// Ngoại tệ Xu nhận ra khi gõ ("20 usd", "$20", "5 euro", "1000 yên"). Tiền luôn lưu bằng đồng;
/// ngoại tệ chỉ để quy đổi lúc ghi và hiện lại số gốc.
enum Currency: String, CaseIterable, Identifiable, Sendable {
    case usd, eur, jpy, krw, cny, gbp, thb, sgd, aud

    var id: String { rawValue }
    var code: String { rawValue.uppercased() }

    /// Số chữ số lẻ của đơn vị nhỏ nhất: 2 với đô la (cent), 0 với yên và won.
    var minorDigits: Int {
        switch self {
        case .jpy, .krw: 0
        default: 2
        }
    }

    /// Tỷ giá gần đúng, đồng cho một đơn vị. Người dùng sửa được trong Tùy chỉnh.
    var defaultRate: Decimal {
        switch self {
        case .usd: 25_400
        case .eur: 29_500
        case .jpy: 170
        case .krw: 18
        case .cny: 3_500
        case .gbp: 34_000
        case .thb: 740
        case .sgd: 19_800
        case .aud: 16_500
        }
    }

    /// Ký hiệu đứng sát số: "$20", "20€". Dài nhất xếp trước để "us$" thắng "$".
    static let symbols: [(symbol: String, currency: Currency)] = [
        ("us$", .usd), ("s$", .sgd), ("a$", .aud),
        ("$", .usd), ("€", .eur), ("£", .gbp), ("¥", .jpy), ("₩", .krw),
    ]

    /// Từ gọi tên tiền, viết thường, có cả dạng bỏ dấu.
    var words: [String] {
        switch self {
        case .usd: ["usd", "đô", "dollar", "dollars", "đôla"]
        case .eur: ["eur", "euro"]
        case .jpy: ["jpy", "yên", "yen"]
        case .krw: ["krw", "won"]
        case .cny: ["cny", "rmb", "tệ", "te"]
        case .gbp: ["gbp", "bảng", "pound", "pounds"]
        case .thb: ["thb", "baht", "bạt"]
        case .sgd: ["sgd"]
        case .aud: ["aud"]
        }
    }
}

/// Một số tiền ngoại tệ đã gõ, tính bằng đơn vị nhỏ nhất (cent, hoặc yên, won) để không dùng số thực.
struct ForeignAmount: Equatable, Sendable {
    var currency: Currency
    var minor: Int

    /// "20 USD", "12,50 EUR", "1.000 JPY".
    func display(decimalSeparator: String = ",", groupingSeparator: String = ".") -> String {
        let digits = currency.minorDigits
        var divisor = 1
        for _ in 0..<digits { divisor *= 10 }
        let whole = minor / divisor
        let fraction = minor % divisor
        var text = Self.grouped(whole, separator: groupingSeparator)
        if fraction != 0 {
            let padded = String(fraction)
            text += decimalSeparator + String(repeating: "0", count: digits - padded.count) + padded
        }
        return "\(text) \(currency.code)"
    }

    private static func grouped(_ value: Int, separator: String) -> String {
        let digits = String(value)
        var result = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { result.append(contentsOf: separator.reversed()) }
            result.append(character)
        }
        return String(result.reversed())
    }
}

/// Tỷ giá quy đổi ra đồng.
struct ExchangeRates: Equatable, Sendable {
    /// Đồng cho một đơn vị ngoại tệ. Thiếu thì dùng `Currency.defaultRate`.
    var overrides: [Currency: Decimal] = [:]

    static let standard = ExchangeRates()

    func rate(for currency: Currency) -> Decimal {
        overrides[currency] ?? currency.defaultRate
    }

    /// Quy ra đồng, làm tròn tới 100đ. Nil khi kết quả không dương.
    func vnd(for amount: ForeignAmount) -> Int? {
        var divisor = Decimal(1)
        for _ in 0..<amount.currency.minorDigits { divisor *= 10 }
        let exact = Decimal(amount.minor) * rate(for: amount.currency) / divisor / 100
        var rounded = Decimal()
        var source = exact
        NSDecimalRound(&rounded, &source, 0, .plain)
        let result = NSDecimalNumber(decimal: rounded * 100).intValue
        return result > 0 ? result : nil
    }

    // MARK: - Lưu

    /// Dạng lưu được: mã tiền → tỷ giá viết bằng chữ ("25400").
    var stored: [String: String] {
        Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, "\($0.value)") })
    }

    init(overrides: [Currency: Decimal] = [:]) {
        self.overrides = overrides
    }

    init(stored: [String: String]) {
        var overrides: [Currency: Decimal] = [:]
        for (code, text) in stored {
            if let currency = Currency(rawValue: code), let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0 {
                overrides[currency] = value
            }
        }
        self.overrides = overrides
    }

    /// Đọc tỷ giá người dùng gõ ("25.400", "25400", "18,5"). Nil khi không hợp lệ.
    static func parseRate(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let separators = trimmed.filter { $0 == "." || $0 == "," }
        var normalized = trimmed
        if separators.count > 1 || (separators.count == 1 && trimmed.split(whereSeparator: { $0 == "." || $0 == "," }).last?.count == 3) {
            normalized = trimmed.filter { $0 != "." && $0 != "," }     // 25.400
        } else {
            normalized = trimmed.replacingOccurrences(of: ",", with: ".")  // 18,5
        }
        guard normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }
}
