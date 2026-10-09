import Foundation

/// Khoảng ngày chọn nhanh ở màn Tìm.
enum DatePreset: String, CaseIterable, Sendable, Identifiable {
    case all, thisWeek, thisMonth, lastMonth, custom

    var id: String { rawValue }

    /// Khoảng [from, to) theo ngày; nil nghĩa là không giới hạn. `custom` do người dùng tự chọn nên cũng nil.
    func range(now: Date, calendar: Calendar) -> Range<Date>? {
        switch self {
        case .all, .custom:
            return nil
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now).map { $0.start..<$0.end }
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now).map { $0.start..<$0.end }
        case .lastMonth:
            guard let previous = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: previous).map { $0.start..<$0.end }
        }
    }
}

/// Điều kiện tìm và lọc khoản chi. Điều kiện nào trống thì không lọc theo điều kiện đó.
struct ExpenseFilter: Equatable, Sendable {
    var text = ""
    var categoryKeys: Set<String> = []
    /// Ngày đầu và ngày cuối (tính cả ngày cuối), theo ngày.
    var from: Date?
    var to: Date?

    var isActive: Bool {
        !TextNormalizer.keyword(text).isEmpty || !categoryKeys.isEmpty || from != nil || to != nil
    }

    /// Đặt khoảng ngày từ mốc chọn nhanh. `custom` giữ nguyên khoảng đang có.
    mutating func apply(_ preset: DatePreset, now: Date, calendar: Calendar) {
        switch preset {
        case .all:
            from = nil
            to = nil
        case .custom:
            break
        case .thisWeek, .thisMonth, .lastMonth:
            guard let range = preset.range(now: now, calendar: calendar) else { return }
            from = range.lowerBound
            to = calendar.date(byAdding: .day, value: -1, to: range.upperBound)
        }
    }

    func matches(_ record: SpendingRecord, calendar: Calendar) -> Bool {
        if !categoryKeys.isEmpty, !categoryKeys.contains(record.categoryKey) { return false }
        if let from, record.date < calendar.startOfDay(for: from) { return false }
        if let to,
           let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)),
           record.date >= end { return false }
        return matchesText(record.name)
    }

    /// Mọi từ gõ vào phải có trong tên khoản, không phân biệt dấu và hoa thường ("pho" tìm ra "phở bò").
    private func matchesText(_ name: String) -> Bool {
        let query = TextNormalizer.words(TextNormalizer.keyword(text))
        guard !query.isEmpty else { return true }
        let target = TextNormalizer.keyword(name)
        return query.allSatisfy { target.contains($0) }
    }
}
