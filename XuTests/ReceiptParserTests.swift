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

struct ReceiptImprovementTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private func parse(_ text: String) -> ReceiptReading {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!
        return ReceiptParser.parse(lines: text.components(separatedBy: "\n"), now: now, calendar: calendar)
    }

    // MARK: Tên cửa hàng

    @Test func merchantSkipsTitleAndAddressLines() {
        #expect(parse("HÓA ĐƠN BÁN HÀNG\nQuán Cơm Ba Ghiền\n84 Đặng Văn Ngữ").merchant == "Quán Cơm Ba Ghiền")
        #expect(parse("84 Đặng Văn Ngữ, Phú Nhuận\nPhở Thìn").merchant == "Phở Thìn")
        #expect(parse("Địa chỉ: 12 Lê Lợi\nĐT: 0903 123 456\nCafe Cộng").merchant == "Cafe Cộng")
        #expect(parse("PHIẾU THANH TOÁN\nHighlands Coffee").merchant == "Highlands Coffee")
    }

    @Test func merchantNamedWithQuanIsNotTreatedAsAddress() {
        #expect(parse("Quán Phở 24\nTổng 45.000").merchant == "Quán Phở 24")
    }

    @Test func merchantFallsBackWhenEverythingLooksLikeNoise() {
        #expect(parse("HÓA ĐƠN\nĐT: 0903123456").merchant == "HÓA ĐƠN")
    }

    // MARK: Các món

    @Test func itemsOfTypicalBill() {
        let reading = parse("""
        QUÁN CƠM TẤM BA GHIỀN
        84 Đặng Văn Ngữ, Phú Nhuận
        Ngày: 07/10/2026 19:42
        Cơm sườn bì chả   2   150.000
        Trà đá x2    10.000
        Tổng cộng:            160.000
        Tiền khách đưa:       200.000
        Tiền thừa:             40.000
        """)
        #expect(reading.items.map(\.name) == ["Cơm sườn bì chả", "Trà đá"])
        #expect(reading.items.map(\.amount) == [150_000, 10_000])
        #expect(reading.items.map(\.id) == [0, 1])
    }

    @Test func itemsExcludeTotalsTaxAndDiscount() {
        let reading = parse("Phở bò 60.000\nGiảm giá 10.000\nVAT 10% 5.000\nTạm tính 60.000\nThanh toán 55.000")
        #expect(reading.items.map(\.name) == ["Phở bò"])
    }

    @Test func linesWithoutAmountAreNotItems() {
        #expect(parse("Cảm ơn quý khách\nHẹn gặp lại").items.isEmpty)
    }

    // MARK: Độ tin cậy

    @Test func totalNextToKeywordIsConfident() {
        #expect(parse("Phở 45.000\nTổng cộng 45.000").isTotalConfident)
    }

    @Test func totalWithoutKeywordIsNotConfident() {
        let reading = parse("Phở 45.000\nTrà 10.000")
        #expect(reading.total == 45_000)
        #expect(!reading.isTotalConfident)
    }

    @Test func totalSmallerThanAnItemIsNotConfident() {
        #expect(!parse("Phở 45.000\nTổng cộng 10.000").isTotalConfident)
    }

    @Test func discountedTotalBelowItemSumIsStillConfident() {
        // Giảm giá làm tổng nhỏ hơn tổng các món, nhưng vẫn lớn hơn mọi món lẻ.
        #expect(parse("Phở 45.000\nTrà 30.000\nGiảm giá 10.000\nTổng cộng 65.000").isTotalConfident)
    }

    @Test func missingTotalIsNotConfident() {
        #expect(!parse("Cảm ơn quý khách").isTotalConfident)
    }
}
