import Observation
import UIKit

/// Một lần mở ô gõ, có thể điền sẵn chữ.
struct EntryRequest: Identifiable, Equatable {
    let id = UUID()
    var text = ""
}

/// Điều hướng gốc và trạng thái Hoàn tác, dùng chung cho các màn hình và intent.
@MainActor @Observable
final class AppState {
    static let shared = AppState()

    var entry: EntryRequest?
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

    func openEntry(text: String = "") {
        showsSettings = false
        showsSearch = false
        showsPaywall = false
        showsReceipt = false
        entry = EntryRequest(text: text)
    }
}
