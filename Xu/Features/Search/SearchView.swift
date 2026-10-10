import SwiftData
import SwiftUI

/// Tìm và lọc mọi khoản chi đã ghi, không giới hạn 35 ngày như màn Hôm nay.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var customCategories: [CustomCategory]
    @State private var filter = ExpenseFilter()
    @State private var preset = DatePreset.all
    @State private var selected: Expense?

    let now: Date

    private var results: [Expense] {
        guard filter.isActive else { return [] }
        return expenses.filter { filter.matches($0.record, calendar: calendar) }
    }

    private var groups: [(day: Date, expenses: [Expense])] {
        Dictionary(grouping: results) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, expenses: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        let results = results
        NavigationStack {
            List {
                Section {
                    categoryChips
                    dateControls
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
                if filter.isActive {
                    resultList(results)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .xuScreen()
            .navigationTitle("Tìm khoản chi")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "phở, grab, cf…")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .sheet(item: $selected) { expense in
                ExpenseDetailView(expense: expense)
            }
        }
        .fontDesign(.rounded)
    }

    // MARK: - Bộ lọc

    private var categoryChips: some View {
        let catalog = CategoryCatalog(custom: customCategories)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(catalog.all) { category in
                    let isOn = filter.categoryKeys.contains(category.key)
                    Button {
                        if isOn { filter.categoryKeys.remove(category.key) } else { filter.categoryKeys.insert(category.key) }
                    } label: {
                        CategoryLabel(category: category, spacing: 5)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isOn ? Color.xuOnButton : Color.xuTextPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(isOn ? Color.xuButton : Color.xuSurface, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }

    private var dateControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Khoảng ngày", selection: $preset) {
                ForEach(DatePreset.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .onChange(of: preset) { _, newValue in
                if newValue == .custom, filter.from == nil, filter.to == nil {
                    filter.from = calendar.dateInterval(of: .month, for: now)?.start
                    filter.to = now
                }
                filter.apply(newValue, now: now, calendar: calendar)
            }
            if preset == .custom {
                HStack {
                    DatePicker("Từ", selection: Binding { filter.from ?? now } set: { filter.from = $0 }, in: ...now, displayedComponents: .date)
                    DatePicker("đến", selection: Binding { filter.to ?? now } set: { filter.to = $0 }, in: ...now, displayedComponents: .date)
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Kết quả

    @ViewBuilder
    private func resultList(_ results: [Expense]) -> some View {
        let catalog = CategoryCatalog(custom: customCategories)
        Section {
            if results.isEmpty {
                Text("Không có khoản nào khớp.")
                    .foregroundStyle(Color.xuTextSecondary)
                    .padding(.top, 8)
            } else {
                summary(results)
                ForEach(groups, id: \.day) { group in
                    dayHeader(group.day)
                    ForEach(group.expenses) { expense in
                        Button { selected = expense } label: { ExpenseRow(expense: expense, category: catalog.info(for: expense.categoryKey)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
    }

    /// Tổng các khoản khớp, kể cả khoản ngoài ngân sách, vì đây là kết quả tìm chứ không phải hạn mức.
    private func summary(_ results: [Expense]) -> some View {
        let total = results.reduce(0) { $0 + $1.amount }
        return Text("\(results.count) khoản · \(MoneyFormatter.short(total))")
            .font(.subheadline.weight(.medium))
            .padding(.top, 8)
            .accessibilityLabel("\(results.count) khoản, tổng \(MoneyFormatter.spoken(total))")
    }

    private func dayHeader(_ day: Date) -> some View {
        var title = VietnameseDate.relativeDay(day, now: now, calendar: calendar)
        let year = calendar.component(.year, from: day)
        if year != calendar.component(.year, from: now) { title += " \(year)" }
        return Text(title)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.xuTextSecondary)
            .padding(.top, 20)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private extension DatePreset {
    var title: LocalizedStringResource {
        switch self {
        case .all: "Mọi lúc"
        case .thisWeek: "Tuần này"
        case .thisMonth: "Tháng này"
        case .lastMonth: "Tháng trước"
        case .custom: "Chọn ngày…"
        }
    }
}

#Preview {
    SearchView(now: Date())
        .xuPreview()
}
