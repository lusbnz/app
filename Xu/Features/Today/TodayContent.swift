import SwiftData
import SwiftUI

/// Nội dung màn Hôm nay: hôm nay còn được tiêu bao nhiêu, rồi các ngày trước theo từng tuần.
/// `TodayView` giữ cửa sổ các ngày đang tải; ở đây chỉ vẽ.
struct TodayContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Query private var expenses: [Expense]
    @Query private var customCategories: [CustomCategory]
    @Query private var recurring: [RecurringExpense]
    @Query private var budgets: [CategoryBudget]
    @State private var selected: Expense?
    @State private var reapply: ReapplyOffer?
    @State private var isScrolling = false
    @State private var hapticDay: Date?
    /// Theo dõi vị trí cuộn. Cố ý là lớp tham chiếu: cập nhật từng khung hình không được làm dựng lại cả màn hình,
    /// chỉ `ScrollingBarHost` đọc nó.
    @State private var scroll = TodayScrollTracker()
    /// Ngày cần cuộn tới sau khi cửa sổ tải xong (kéo dải ngày tới một ngày chưa tải).
    @State private var pendingJump: Date?
    @State private var openedWeek: WeekRef?

    let now: Date
    /// Đầu cửa sổ đang hiện, luôn là đầu một tuần.
    let windowStart: Date
    let hasOlder: Bool
    /// Hôm nay rồi các ngày có khoản chi, cho dải ngày kéo.
    let scrubDays: [Date]
    let loadMore: () -> Void
    let ensureLoaded: (Date) -> Void
    let dataChanged: () -> Void
    private static let topID = "today.top"

    /// Một tuần được mở ở màn Chi tiết tuần.
    private struct WeekRef: Hashable {
        let start: Date
    }

    /// Mốc cuộn tới một ngày; bọc `Date` cho khỏi lẫn với mã định danh của `ForEach`.
    private struct DayAnchor: Hashable {
        let day: Date
    }

    init(
        now: Date, windowStart: Date, hasOlder: Bool, scrubDays: [Date],
        loadMore: @escaping () -> Void, ensureLoaded: @escaping (Date) -> Void, dataChanged: @escaping () -> Void
    ) {
        self.now = now
        self.windowStart = windowStart
        self.hasOlder = hasOlder
        self.scrubDays = scrubDays
        self.loadMore = loadMore
        self.ensureLoaded = ensureLoaded
        self.dataChanged = dataChanged
        // Tải thêm một tuần trước cửa sổ để so tuần cũ nhất đang hiện với tuần trước nó.
        let since = HistoryWindow.comparisonStart(for: windowStart, calendar: Calendar.current)
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= since }, sort: \Expense.createdAt, order: .reverse)
    }

    private var status: BudgetStatus {
        BudgetCalculator.status(
            settings.budgetSetting, entries: expenses.map(\.budgetEntry),
            categoryLimits: settings.dailyLimits(budgets), now: now, calendar: calendar
        )
    }

    private var todays: [Expense] {
        expenses.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// Khoản định kỳ đã đến hạn tháng này mà chưa ghi hay bỏ qua.
    private var dueRecurring: [RecurringExpense] {
        recurring
            .filter { RecurringPlanner.isDue($0.item, now: now, calendar: calendar) }
            .sorted { ($0.dayOfMonth, $0.name) < ($1.dayOfMonth, $1.name) }
    }

    var body: some View {
        @Bindable var appState = appState
        let status = status
        let catalog = CategoryCatalog(custom: customCategories)
        ScrollViewReader { proxy in
        List {
            Group {
                header(status).id(Self.topID)
                ForEach(dueRecurring) { item in
                    DueRecurringRow(item: item) { recordRecurring(item) } skip: { skipRecurring(item) }
                }
                history(catalog: catalog)
                if hasOlder { loadMoreRow }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Nút kéo của dải ngày đã đóng vai thanh cuộn (hiện khi cuộn, ẩn sau một lúc), nên tắt thanh cuộn của hệ thống
        // để không hiện hai thanh cùng lúc. Ít ngày quá thì không có dải ngày, giữ thanh cuộn của hệ thống.
        .scrollIndicators(scrubDays.count > 5 ? .hidden : .automatic)
        .animation(.default, value: todays.map(\.id))
        .onScrollPhaseChange { _, phase in
            isScrolling = phase.isScrolling
            scroll.setScrolling(phase.isScrolling)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Vị trí trong cả danh sách (0 đến 1) để đặt nút kéo của dải ngày.
            let range = geometry.contentSize.height - geometry.containerSize.height
                + geometry.contentInsets.top + geometry.contentInsets.bottom
            guard range > 1 else { return 0 }
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            return (min(max(offset / range, 0), 1) * 500).rounded() / 500
        } action: { _, newValue in
            scroll.setFraction(newValue)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Từ 80 đến 160 điểm cuộn thì thanh nhỏ hiện dần; làm tròn để không cập nhật từng điểm ảnh.
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            return (min(max((offset - 80) / 80, 0), 1) * 20).rounded() / 20
        } action: { _, newValue in
            scroll.setCollapse(newValue)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { scroll.setTopInset($0) }
        .overlay(alignment: .top) {
            ScrollingBarHost(
                tracker: scroll, now: now, calendar: calendar,
                amountText: MoneyFormatter.short(status.remainingToday), fraction: status.todayFraction,
                accessibilityText: accessibilitySummary(status),
                openSearch: { appState.showsSearch = true },
                openSettings: { appState.showsSettings = true },
                scrollToToday: { withAnimation(.smooth) { proxy.scrollTo(Self.topID, anchor: .top) } }
            )
        }
        .overlay(alignment: .trailing) {
            DayScrubber(tracker: scroll, days: scrubDays, now: now, calendar: calendar) { jump(to: $0, proxy: proxy) }
                .padding(.top, 64)
                .padding(.bottom, 12)
        }
        .onChange(of: windowStart) { _, _ in
            // Cửa sổ vừa mở rộng tới ngày cần nhảy tới: chờ danh sách dựng xong rồi mới cuộn.
            guard let day = pendingJump else { return }
            pendingJump = nil
            Task {
                try? await Task.sleep(for: .milliseconds(80))
                proxy.scrollTo(DayAnchor(day: day), anchor: .top)
            }
        }
        .onChange(of: expenses.count) { dataChanged() }
        #if DEBUG
        .onChange(of: appState.debugOpensWeek) { _, opens in
            // Cờ chạy thử `-open week`.
            guard opens else { return }
            appState.debugOpensWeek = false
            openedWeek = WeekRef(start: HistoryWindow.weekStart(of: now, calendar: calendar))
        }
        #endif
        .sensoryFeedback(.selection, trigger: hapticDay)
        .xuScreen()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationDestination(isPresented: $appState.showsMonth) {
            MonthView(now: now)
        }
        .navigationDestination(item: $openedWeek) { week in
            WeekDetailView(weekStart: week.start, now: now)
        }
        .sheet(item: $selected) { expense in
            ExpenseDetailView(expense: expense)
        }
        .reapplyDialog($reapply)
        .sheet(isPresented: $appState.showsSettings) {
            SettingsView()
        }
        .sheet(isPresented: $appState.showsSearch) {
            SearchView(now: now)
        }
        }
    }

    /// Ghi lại một khoản y như cũ. Bản miễn phí vẫn bị giới hạn số lần ghi mỗi ngày.
    private func repeatExpense(_ expense: Expense) {
        guard SaveGate.canSave(now: Date(), calendar: calendar) else {
            appState.showsPaywall = true
            return
        }
        let batch = ExpenseRecorder(context: modelContext).repeatExpense(expense, now: Date())
        appState.didSave(batch)
    }

    private func recordRecurring(_ item: RecurringExpense) {
        guard SaveGate.canSave(now: Date(), calendar: calendar) else {
            appState.showsPaywall = true
            return
        }
        withAnimation {
            if let batch = ExpenseRecorder(context: modelContext).recordRecurring(item, now: Date(), calendar: calendar) {
                appState.didSave(batch)
            }
        }
    }

    private func skipRecurring(_ item: RecurringExpense) {
        withAnimation { ExpenseRecorder(context: modelContext).skipRecurring(item, now: Date(), calendar: calendar) }
    }

    // MARK: - Phần đầu

    private func header(_ status: BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(VietnameseDate.dayTitle(now, calendar: calendar))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.xuTextSecondary)
                Spacer()
                Button { appState.showsSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tìm khoản chi")
                Button { appState.showsSettings = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tùy chỉnh")
            }
            Button { appState.showsMonth = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HighlightedNumber(
                        text: MoneyFormatter.short(status.remainingToday),
                        fraction: status.todayFraction
                    )
                    Text(subtitle(status))
                        .font(.subheadline)
                        .foregroundStyle(Color.xuTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(status))
            .accessibilityHint("Mở màn hình Tháng")
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private func subtitle(_ status: BudgetStatus) -> String {
        if status.remainingToday < 0 {
            if let tomorrow = status.allowanceTomorrow, tomorrow > 0 {
                return String(localized: "vượt hôm nay · mai vẫn còn \(MoneyFormatter.short(tomorrow))")
            }
            return String(localized: "vượt hôm nay")
        }
        return String(localized: "còn được tiêu hôm nay · đã tiêu \(MoneyFormatter.short(status.spentToday))")
    }

    private func accessibilitySummary(_ status: BudgetStatus) -> String {
        if status.remainingToday < 0 {
            let over = MoneyFormatter.spoken(-status.remainingToday)
            if let tomorrow = status.allowanceTomorrow, tomorrow > 0 {
                return String(localized: "Hôm nay vượt \(over), mai vẫn còn \(MoneyFormatter.spoken(tomorrow))")
            }
            return String(localized: "Hôm nay vượt \(over)")
        }
        return String(localized: "Còn được tiêu hôm nay \(MoneyFormatter.spoken(status.remainingToday)), đã tiêu \(MoneyFormatter.spoken(status.spentToday))")
    }

    /// Một dòng khoản chi, kèm các nút vuốt nhanh. Dùng cho hôm nay và các ngày trước.
    private func expenseRow(_ expense: Expense, catalog: CategoryCatalog) -> some View {
        Button { selected = expense } label: { ExpenseRow(expense: expense, category: catalog.info(for: expense.categoryKey)) }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading) {
                Button("Ghi lại", systemImage: "plus.circle") { repeatExpense(expense) }
                    .tint(Color.xuToggle)
                Button(
                    expense.isOutsideBudget ? "Tính vào ngân sách" : "Ngoài ngân sách",
                    systemImage: expense.isOutsideBudget ? "arrow.uturn.backward" : "tray.and.arrow.up"
                ) {
                    withAnimation { ExpenseRecorder(context: modelContext).toggleOutsideBudget(expense) }
                }
                .tint(Color.gray)
            }
            .swipeActions(edge: .trailing) {
                Button("Xóa", systemImage: "trash", role: .destructive) {
                    ExpenseRecorder(context: modelContext).delete(expense)
                }
                Menu {
                    ForEach(catalog.all) { category in
                        Button(category.title) {
                            let recorder = ExpenseRecorder(context: modelContext)
                            recorder.setCategory(of: expense, to: category.key)
                            reapply = recorder.reapplyOffer(keyword: expense.name, categoryKey: category.key)
                        }
                    }
                } label: {
                    Label("Danh mục", systemImage: "tag")
                }
                .tint(Color.gray)
            }
    }

    // MARK: - Các ngày trước

    /// Các ngày trước hôm nay có khoản chi trong cửa sổ, mới nhất trước. Cuộn xuống là xem tiếp, không cần bấm.
    private var pastGroups: [(day: Date, expenses: [Expense])] {
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: expenses.filter { $0.date >= windowStart && $0.date < today }) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped
            .map { (day: $0.key, expenses: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    /// Một tuần trên màn hình: các ngày của tuần đó, và với tuần này thì cả hôm nay.
    private struct WeekBlock: Identifiable {
        var start: Date
        var isCurrent: Bool
        var summary: WeekSummary?
        /// `depth` là thứ tự ngày tính từ ngày gần nhất, để ngày càng cũ càng nhạt.
        var days: [(day: Date, expenses: [Expense], depth: Int)]

        var id: Date { start }
    }

    private func weekBlocks() -> [WeekBlock] {
        let summaries = WeekSummaries.make(records: expenses.map(\.record), now: now, calendar: calendar)
        let currentStart = HistoryWindow.weekStart(of: now, calendar: calendar)
        var blocks: [WeekBlock] = [WeekBlock(start: currentStart, isCurrent: true, summary: summaries[currentStart], days: [])]
        for (index, group) in pastGroups.enumerated() {
            let start = HistoryWindow.weekStart(of: group.day, calendar: calendar)
            if blocks.last?.start != start {
                blocks.append(WeekBlock(start: start, isCurrent: false, summary: summaries[start], days: []))
            }
            blocks[blocks.count - 1].days.append((group.day, group.expenses, index))
        }
        return blocks
    }

    @ViewBuilder
    private func history(catalog: CategoryCatalog) -> some View {
        ForEach(weekBlocks()) { block in
            // Tuần này chỉ có hôm nay thì tiêu đề tuần trùng với tiêu đề hôm nay, nên bỏ.
            if !block.days.isEmpty, let summary = block.summary { weekHeader(summary, topPadding: block.isCurrent ? 12 : 36) }
            if block.isCurrent {
                if !todays.isEmpty { todayHeader }
                ForEach(todays) { expenseRow($0, catalog: catalog) }
            }
            ForEach(block.days, id: \.day) { group in
                let total = group.expenses.filter { !$0.isOutsideBudget }.reduce(0) { $0 + $1.amount }
                dayHeader(group.day, total: total, depth: group.depth)
                ForEach(group.expenses) { expenseRow($0, catalog: catalog).dayDepth(group.depth) }
            }
        }
    }

    /// Tiêu đề một tuần: tên tuần, tổng chi, và so với tuần trước. Chạm để xem chi tiết tuần đó.
    private func weekHeader(_ summary: WeekSummary, topPadding: CGFloat) -> some View {
        Button { openedWeek = WeekRef(start: summary.start) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(VietnameseDate.weekTitle(start: summary.start, now: now, calendar: calendar))
                    Spacer()
                    Text(MoneyFormatter.short(summary.total)).money(summary.total)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.xuTextSecondary)
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                if let comparison = WeekText.comparison(summary) {
                    Text(comparison)
                        .font(.caption)
                        .foregroundStyle(summary.delta > 0 ? Color.red : Color.xuTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, topPadding)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Xem chi tiết tuần")
    }

    private var loadMoreRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Đang tải thêm")
        }
        .font(.footnote)
        .foregroundStyle(Color.xuTextSecondary)
        .frame(maxWidth: .infinity, minHeight: 56)
        // Chạy khi dòng này hiện ra, và chạy lại sau mỗi lần cửa sổ mở rộng nếu nó vẫn còn trên màn hình.
        .task(id: windowStart) { loadMore() }
    }

    /// Nhảy tới một ngày ở dải ngày. Ngày chưa tải thì mở rộng cửa sổ rồi mới cuộn.
    private func jump(to day: Date, proxy: ScrollViewProxy) {
        if day >= calendar.startOfDay(for: now) {
            proxy.scrollTo(Self.topID, anchor: .top)
        } else if day >= windowStart {
            proxy.scrollTo(DayAnchor(day: day), anchor: .top)
        } else {
            pendingJump = day
            ensureLoaded(day)
        }
    }

    /// Tiêu đề và tổng của hôm nay, cùng kiểu với các ngày trước. Không tính khoản ngoài ngân sách.
    private var todayHeader: some View {
        let total = todays.filter { !$0.isOutsideBudget }.reduce(0) { $0 + $1.amount }
        return groupTitle(
            VietnameseDate.relativeDay(now, now: now, calendar: calendar), total: total,
            load: DayLoad.make(spent: total, allowance: status.allowanceToday)
        )
        .padding(.top, 8)
    }

    private func groupTitle(_ title: String, total: Int, load: DayLoad? = nil) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(MoneyFormatter.short(total)).money(total)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.xuTextSecondary)
            if let load { DayLoadBar(load: load) }
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(load?.isOver == true ? Text("vượt hạn mức ngày") : Text(verbatim: ""))
        .accessibilityAddTraits(.isHeader)
    }

    private func dayHeader(_ day: Date, total: Int, depth: Int) -> some View {
        let allowance = DayLoad.pastDayAllowance(settings.budgetSetting, day: day, calendar: calendar)
        return groupTitle(
            VietnameseDate.relativeDay(day, now: now, calendar: calendar), total: total,
            load: DayLoad.make(spent: total, allowance: allowance)
        )
        .padding(.top, 24)
        .dayDepth(depth)
        .id(DayAnchor(day: day))
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { scroll.headerMoved(day: day, minY: $0) }
        // Rung nhẹ mỗi khi một ngày mới trượt vào màn hình, chỉ khi người dùng đang cuộn.
        .onScrollVisibilityChange(threshold: 0.9) { visible in
            if visible, isScrolling { hapticDay = day }
        }
    }

    // MARK: - Đáy màn hình

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let batch = appState.undoable {
                UndoBar(batch: batch) {
                    ExpenseRecorder(context: modelContext).undo(batch)
                    appState.undoable = nil
                } dismiss: {
                    appState.undoable = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                Button { appState.openEntry() } label: {
                    Text("phở 45k")
                        .foregroundStyle(Color.xuTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .padding(.horizontal, 20)
                        .background(Color.xuSurface, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ghi khoản chi")
                if VoiceInput.hasUsageDescriptions {
                    Button { appState.openEntry(startsListening: true) } label: {
                        Image(systemName: "mic")
                            .font(.title3)
                            .frame(width: 50, height: 50)
                            .background(Color.xuSurface, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Nói khoản chi")
                }
                Button {
                    appState.receiptImage = nil
                    appState.showsReceipt = true
                } label: {
                    Image(systemName: "camera")
                        .font(.title3)
                        .frame(width: 50, height: 50)
                        .background(Color.xuSurface, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chụp hóa đơn")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.xuBackground)
        .animation(.snappy, value: appState.undoable)
    }
}
