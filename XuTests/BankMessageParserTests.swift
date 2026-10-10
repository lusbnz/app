import Foundation
import Testing
@testable import Xu

struct BankMessageParserTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.date(2026, 10, 10, 18)

    private func parse(_ text: String) -> BankTransaction? {
        BankMessageParser.parse(text, now: now, calendar: calendar)
    }

    @Test func vietcombankDebit() throws {
        let tx = try #require(parse("VCB Digibank thong bao: TK 0011004123456 GD: -450,000VND luc 10-10-2026 14:22. SD: 12,345,678VND. ND: MB NGUYEN VAN A chuyen tien"))
        #expect(tx.direction == .debit)
        #expect(tx.amount == 450_000)
        #expect(tx.balanceAfter == 12_345_678)
        #expect(tx.accountSuffix == "3456")
        #expect(tx.date == TestClock.date(2026, 10, 10, 14) .addingTimeInterval(22 * 60))
        #expect(tx.description == "MB Nguyen Van A chuyen tien" || tx.description == "Mb Nguyen Van A Chuyen Tien" || tx.description?.lowercased() == "mb nguyen van a chuyen tien")
    }

    @Test func techcombankCreditWithSpaceBeforeVND() throws {
        let tx = try #require(parse("TK 19031234567890 +1,000,000 VND luc 10/10/2026 12:05. So du 5,000,000 VND. ND: LUONG THANG 10"))
        #expect(tx.direction == .credit)
        #expect(tx.amount == 1_000_000)
        #expect(tx.balanceAfter == 5_000_000)
        #expect(tx.description == "Luong Thang 10")
    }

    @Test func mbBankDebitWithDecimalAmount() throws {
        let tx = try #require(parse("TK 0123456789 -200,000.00VND luc 10/10/2026 13:00. So du 3,000,000VND."))
        #expect(tx.direction == .debit)
        #expect(tx.amount == 200_000)
        #expect(tx.balanceAfter == 3_000_000)
    }

    @Test func bidvShortYear() throws {
        let tx = try #require(parse("BIDV: TK 1234567890 -150,000VND 10/10/26 08:20 ND: THANH TOAN QR HIGHLANDS COFFEE"))
        #expect(tx.amount == 150_000)
        #expect(tx.date == TestClock.date(2026, 10, 10, 8).addingTimeInterval(20 * 60))
        #expect(tx.description == "Thanh Toan Qr Highlands Coffee")
    }

    @Test func eWalletPaymentUsesAccentedMerchantName() throws {
        let tx = try #require(parse("Bạn đã thanh toán thành công 45.000đ cho Phở Thìn. Cảm ơn bạn đã sử dụng ví."))
        #expect(tx.direction == .debit)
        #expect(tx.amount == 45_000)
        #expect(tx.description == "Phở Thìn")
        #expect(tx.balanceAfter == nil)
    }

    @Test func eWalletTransferOutAndIn() throws {
        let out = try #require(parse("Bạn đã chuyển 200.000đ tới Nguyễn Văn A"))
        #expect(out.direction == .debit && out.amount == 200_000)
        #expect(out.description == "Nguyễn Văn A")
        let received = try #require(parse("Bạn đã nhận 100.000đ từ Trần Thị B"))
        #expect(received.direction == .credit && received.amount == 100_000)
        #expect(received.description == "Trần Thị B")
    }

    @Test func atMerchantPhrase() throws {
        let tx = try #require(parse("Thanh toán thành công 59.000đ tại Grab. Mã GD 123456"))
        #expect(tx.amount == 59_000)
        #expect(tx.description == "Grab")
    }

    @Test func plainAmountsInThousandsGroupsAndNoSeparators() throws {
        #expect(try #require(parse("TK 1234 -1.250.000VND luc 10/10/2026 09:00")).amount == 1_250_000)
        #expect(try #require(parse("TK 1234 -250000VND luc 10/10/2026 09:00")).amount == 250_000)
        #expect(try #require(parse("TK 1234 -2,500,000d")).amount == 2_500_000)
    }

    @Test func accountNumbersAndDatesAreNotAmounts() {
        // Chỉ có số tài khoản, ngày và giờ: không có số tiền nào.
        #expect(parse("TK 0011004123456 luc 10/10/2026 14:22") == nil)
    }

    @Test func directionFromKeywordsWhenThereIsNoSign() throws {
        #expect(try #require(parse("Ghi co TK 1234 500,000 VND")).direction == .credit)
        #expect(try #require(parse("Rut tien ATM 2,000,000 VND tai TK 1234")).direction == .debit)
    }

    @Test func ambiguousMessagesAreRejectedInsteadOfGuessed() {
        #expect(parse("Giao dich 500,000 VND") == nil)
        #expect(parse("") == nil)
        #expect(parse("Xin chào, hẹn gặp lại") == nil)
    }

    @Test func futureDatesAreIgnored() throws {
        let tx = try #require(parse("TK 1234 -50,000VND luc 10/10/2027 09:00"))
        #expect(tx.date == nil)
        let impossible = try #require(parse("TK 1234 -50,000VND luc 31/02/2026 09:00"))
        #expect(impossible.date == nil)
    }

    @Test func balanceNeverBecomesTheAmount() throws {
        let tx = try #require(parse("So du TK 1234 la 9,999,999VND. GD -10,000VND"))
        #expect(tx.amount == 10_000)
        #expect(tx.balanceAfter == 9_999_999)
    }

    @Test func vndValueParsing() {
        #expect(BankMessageParser.vndValue("450,000") == 450_000)
        #expect(BankMessageParser.vndValue("450.000") == 450_000)
        #expect(BankMessageParser.vndValue("450,000.00") == 450_000)
        #expect(BankMessageParser.vndValue("1.234.567") == 1_234_567)
        #expect(BankMessageParser.vndValue("45000") == 45_000)
        #expect(BankMessageParser.vndValue("1,2345") == nil)
        #expect(BankMessageParser.vndValue("") == nil)
    }
}
