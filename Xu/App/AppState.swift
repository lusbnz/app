import Observation
import UIKit

/// Một lần mở ô gõ, có thể điền sẵn chữ.
struct EntryRequest: Identifiable, Equatable {
    let id = UUID()
    var text = ""
    /// Mở ô gõ và bắt đầu nghe ngay (nút micro ở màn Hôm nay).
    var startsListening = false
}

/// Điều hướng gốc và trạng thái Hoàn tác, dùng chung cho các màn hình và intent.
@MainActor @Observable
final class AppState {
    static let shared = AppState()

    var entry: EntryRequest?
    #if DEBUG
    /// Chỉ để chạy thử: màn con của màn Tháng cần mở ngay (`-open map|goals|goal`).
    var debugMonthDestination: String?
    /// Chỉ để chạy thử (`-open week`): mở ngay màn Chi tiết tuần này.
    var debugOpensWeek = false
    #endif
    var showsMonth = false
    var showsSettings = false
    var showsSearch = false
    var showsPaywall = false
    var showsReceipt = false
    /// Ảnh đưa sẵn cho màn hình hóa đơn; nil thì màn hình tự mở camera hoặc chờ chọn ảnh.
    var receiptImage: UIImage?
    /// Câu hỏi vừa gõ ở ô gõ, chờ màn hình Tháng trả lời.
    var pendingQuestion: String?
    var undoable: SavedBatch?
    /// Tăng sau mỗi lần lưu, để phát haptic.
    var saveCount = 0

    func didSave(_ batch: SavedBatch) {
        undoable = batch
        saveCount += 1
    }

    func ask(_ question: String) {
        pendingQuestion = question
        showsMonth = true
    }

    /// Mở màn Tháng (từ thông báo tổng kết), đóng các màn đang phủ lên.
    func openMonth() {
        showsSettings = false
        showsSearch = false
        showsPaywall = false
        showsReceipt = false
        entry = nil
        showsMonth = true
    }

    func openEntry(text: String = "", startsListening: Bool = false) {
        showsSettings = false
        showsSearch = false
        showsPaywall = false
        showsReceipt = false
        entry = EntryRequest(text: text, startsListening: startsListening)
    }
}
