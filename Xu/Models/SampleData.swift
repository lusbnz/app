import Foundation

/// Khoản chi mẫu để xem màn hình khi có nhiều dữ liệu. Sinh theo hạt giống cố định nên lần nào cũng như nhau.
struct SampleExpense: Equatable, Sendable {
    var name: String
    var amount: Int
    var date: Date
    var isOutsideBudget: Bool
}

enum SampleData {
    /// Gắn vào `Expense.rawText` để xóa đúng các khoản mẫu, không đụng dữ liệu thật.
    static let marker = "[dữ liệu mẫu]"

    private struct Template {
        var name: String
        var range: ClosedRange<Int>
        var step: Int
    }

    private static let everyday: [Template] = [
        Template(name: "phở", range: 40...60, step: 5),
        Template(name: "cơm tấm", range: 45...65, step: 5),
        Template(name: "cf", range: 25...45, step: 5),
        Template(name: "trà sữa", range: 35...55, step: 5),
        Template(name: "bún chả", range: 50...70, step: 5),
        Template(name: "grab", range: 25...95, step: 5),
        Template(name: "đổ xăng", range: 60...150, step: 10),
        Template(name: "siêu thị", range: 120...450, step: 10),
        Template(name: "ăn trưa", range: 45...85, step: 5),
        Template(name: "thuốc", range: 60...220, step: 10),
        Template(name: "xem phim", range: 90...200, step: 10),
        Template(name: "gửi xe", range: 5...10, step: 5),
    ]

    private static let big: [Template] = [
        Template(name: "nhậu", range: 450...900, step: 50),
        Template(name: "mua quần áo", range: 400...1_200, step: 50),
        Template(name: "ăn tiệc", range: 500...1_000, step: 50),
    ]

    private static let outside: [Template] = [
        Template(name: "sửa xe", range: 1_500...3_500, step: 100),
        Template(name: "mua điện thoại", range: 8_000...15_000, step: 500),
    ]

    /// Các khoản của `days` ngày trước hôm nay (không gồm hôm nay), một vài ngày để trống,
    /// một vài ngày tiêu vượt, thỉnh thoảng có khoản lớn ngoài ngân sách.
    static func expenses(days: Int, now: Date, calendar: Calendar) -> [SampleExpense] {
        var random = SplitMix64(seed: 2026)
        let today = calendar.startOfDay(for: now)
        var result: [SampleExpense] = []
        for offset in 1...max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if random.next(below: 100) < 12 { continue }          // ngày không ghi gì
            var names: [(Template, Bool)] = []
            for _ in 0..<(1 + random.next(below: 5)) {
                names.append((everyday[random.next(below: everyday.count)], false))
            }
            if random.next(below: 100) < 8 { names.append((big[random.next(below: big.count)], false)) }
            if random.next(below: 100) < 4 { names.append((outside[random.next(below: outside.count)], true)) }
            for (template, isOutside) in names {
                let steps = (template.range.upperBound - template.range.lowerBound) / template.step
                let thousands = template.range.lowerBound + random.next(below: steps + 1) * template.step
                let hour = 7 + random.next(below: 15)
                let minute = random.next(below: 60)
                let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                result.append(SampleExpense(name: template.name, amount: thousands * 1_000, date: date, isOutsideBudget: isOutside))
            }
        }
        return result
    }
}

/// Bộ sinh số ngẫu nhiên có hạt giống, để dữ liệu mẫu lặp lại được.
private struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(max(1, bound)))
    }
}
