import Foundation

enum MoneyFormatter {
    /// Dạng gọn: `194k`, `7,1tr`, `9tr`, `-56k`.
    static func short(_ amount: Int) -> String {
        let sign = amount < 0 ? "-" : ""
        let magnitude = abs(amount)
        let thousands = (magnitude + 500) / 1_000
        if thousands < 1_000 {
            return thousands == 0 ? "0k" : "\(sign)\(thousands)k"
        }
        let tenths = (magnitude + 50_000) / 100_000
        let whole = tenths / 10
        let decimal = tenths % 10
        return decimal == 0 ? "\(sign)\(whole)tr" : "\(sign)\(whole),\(decimal)tr"
    }

    /// Số đầy đủ: `9.000.000đ`.
    static func full(_ amount: Int) -> String {
        grouped(amount) + "đ"
    }

    /// Cho VoiceOver: `194.000 đồng`, `âm 56.000 đồng`.
    static func spoken(_ amount: Int) -> String {
        (amount < 0 ? "âm " : "") + grouped(abs(amount)) + " đồng"
    }

    /// Chữ số nhóm ba bằng dấu chấm: `9.000.000`.
    static func grouped(_ amount: Int) -> String {
        let digits = Array(String(abs(amount)))
        var result = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result.append(".") }
            result.append(digit)
        }
        return (amount < 0 ? "-" : "") + result
    }
}
