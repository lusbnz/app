import Foundation
import Testing
@testable import Xu

struct ReceiptParserTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func parse(_ text: String) -> ReceiptReading {
        ReceiptParser.parse(lines: text.components(separatedBy: "\n"), now: date(8), calendar: calendar)
    }

    @Test func typicalRestaurantBill() {
        let reading = parse("""
        QUÁN CƠM TẤM BA GHIỀN
        84 Đặng Văn Ngữ, Phú Nhuận
        ĐT: 0903123456
        Ngày: 07/10/2026 19:42
        Cơm sườn bì chả   2   150.000
        Trà đá            2    10.000
        Tổng cộng:            160.000
        Tiền khách đưa:       200.000
        Tiền thừa:             40.000
        """)
        #expect(reading.merchant == "QUÁN CƠM TẤM BA GHIỀN")
        #expect(reading.total == 160_000)
        #expect(reading.date == date(7, hour: 19, minute: 42))
    }

    @Test func paidAmountBeatsTotalBeforeDiscount() {
        let reading = parse("""
        HIGHLANDS COFFEE
        Tổng cộng 150.000
        Giảm giá 25.000
        Thanh toán 125.000đ
        """)
        #expect(reading.total == 125_000)
    }

    @Test func totalOnTheNextLine() {
        let reading = parse("""
        Siêu thị Co.opmart
        Thành tiền
        1.250.000
        Thanh toán: Tiền mặt
        Mã số thuế 0301234567
        """)
        #expect(reading.total == 1_250_000)
    }

    @Test func englishTotalIgnoresSubtotal() {
        let reading = parse("""
        The Coffee House
        Subtotal 90,000
        VAT 8% 7,200
        TOTAL 97,200
        """)
        #expect(reading.total == 97_200)
    }

    @Test func fallsBackToLargestAmount() {
        let reading = parse("""
        Tạp hóa Cô Ba
        Mì gói 12.000
        Nước mắm 48.000
        60.000
        Hotline 19001234
        """)
        #expect(reading.total == 60_000)
    }

    @Test func noAmountAtAll() {
        #expect(parse("Cảm ơn quý khách\nHẹn gặp lại").total == nil)
    }

    @Test(arguments: [
        ("125.000", [125_000]), ("125,000 VND", [125_000]), ("1.250.000đ", [1_250_000]), ("125.000,00", [125_000]),
        ("45k", [45_000]), ("SL 2 x 75.000 = 150.000", [75_000, 150_000]),
        ("07/10/2026 19:42", []), ("ĐT 0903123456", []), ("Bàn 12", []), ("HD2026100712", []),
    ])
    func amounts(line: String, expected: [Int]) {
        #expect(ReceiptParser.amounts(in: line) == expected)
    }

    @Test(arguments: ["Ngày 07/10/2026", "07-10-2026", "07.10.26", "2026-10-07"])
    func dateFormats(line: String) {
        #expect(parse(line).date == date(7))
    }

    @Test func timeOnAnotherLine() {
        #expect(parse("Ngày: 07/10/2026\nGiờ vào: 19:42").date == date(7, hour: 19, minute: 42))
    }

    @Test func implausibleDatesAreIgnored() {
        #expect(parse("Ngày 31/02/2026").date == nil)
        #expect(parse("Ngày 07/10/2020").date == nil)
        #expect(parse("HSD 07/10/2027").date == nil)
        #expect(parse("Tổng 1.250.000").date == nil)
    }

    @Test func merchantSkipsLinesWithoutLetters() {
        #expect(parse("----------\n0903 123 456\nPhở Thìn").merchant == "Phở Thìn")
    }
}
