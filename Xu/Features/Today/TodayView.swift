import SwiftData
import SwiftUI

/// Màn hình gốc. Giữ cửa sổ các ngày đang tải: lúc đầu là bốn tuần gần nhất, cuộn tới cuối thì tải thêm,
/// kéo dải ngày tới một ngày xa thì mở rộng tới ngày đó.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    let now: Date
    /// nil cho tới khi người dùng tải thêm; lúc đó dùng cửa sổ ban đầu.
    @State private var loadedStart: Date?
    @State private var hasOlder = false
    @State private var scrubDays: [Date] = []

    private var windowStart: Date {
        loadedStart ?? HistoryWindow.initialStart(now: now, calendar: calendar)
    }

    var body: some View {
        TodayContent(
            now: now, windowStart: windowStart, hasOlder: hasOlder, scrubDays: scrubDays,
            loadMore: loadMore, ensureLoaded: ensureLoaded, dataChanged: refresh
        )
        .task(id: windowStart) { refresh() }
    }

    /// Còn khoản nào cũ hơn cửa sổ không, và các ngày có khoản chi cho dải ngày.
    private func refresh() {
        let start = windowStart
        hasOlder = ((try? modelContext.fetchCount(FetchDescriptor<Expense>(predicate: #Predicate { $0.date < start }))) ?? 0) > 0
        var descriptor = FetchDescriptor<Expense>()
        descriptor.propertiesToFetch = [\.date]
        let dates = ((try? modelContext.fetch(descriptor)) ?? []).map(\.date)
        scrubDays = DayIndex.days(from: dates, now: now, calendar: calendar)
    }

    private func loadMore() {
        let start = windowStart
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date < start }, sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = HistoryWindow.pageSize
        let older = ((try? modelContext.fetch(descriptor)) ?? []).map(\.date)
        guard let next = HistoryWindow.nextStart(olderDates: older, currentStart: start, calendar: calendar) else {
            hasOlder = false
            return
        }
        loadedStart = next
    }

    private func ensureLoaded(_ day: Date) {
        loadedStart = HistoryWindow.start(including: day, currentStart: windowStart, calendar: calendar)
    }
}

#Preview {
    NavigationStack {
        TodayView(now: Date())
    }
    .xuPreview()
}

#Preview("Vượt hạn mức") {
    NavigationStack {
        TodayView(now: Date())
    }
    .xuPreview(budget: 3_000_000)
}
