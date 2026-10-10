import MapKit
import SwiftData
import SwiftUI

/// Bản đồ chi tiêu: mỗi chỗ đã ghi là một chấm có số tiền, chấm to theo số tiền; chạm để xem chỗ đó.
struct PlacesMapView: View {
    private enum Span: String, CaseIterable, Identifiable {
        case month, all

        var id: String { rawValue }
    }

    private struct SearchRequest: Identifiable {
        let id = UUID()
        var filter: ExpenseFilter
    }

    @Environment(\.calendar) private var calendar
    /// Không lọc trong `@Query`: màn hình nằm trong `navigationDestination` sẽ truy vấn lại liên tục (xem `MonthView`).
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]
    @Query private var customCategories: [CustomCategory]
    @State private var span = Span.month
    @State private var selection: String?
    @State private var camera = MapCameraPosition.automatic
    @State private var searchRequest: SearchRequest?

    let now: Date
    private let initialSelection: String?

    /// `initialSelection` là mã của một chỗ (`PlaceSpend.id`) để mở sẵn và đưa bản đồ về đó.
    init(now: Date, initialSelection: String? = nil) {
        self.now = now
        self.initialSelection = initialSelection
        _selection = State(initialValue: initialSelection)
    }

    /// Chỉ khoản trong ngân sách và có vị trí, như các con số khác ở màn Tháng.
    private var spends: [PlaceSpend] {
        let start = span == .month ? calendar.dateInterval(of: .month, for: now)?.start : nil
        let records = allExpenses.compactMap { expense -> PlaceRecord? in
            guard !expense.isOutsideBudget, let latitude = expense.latitude, let longitude = expense.longitude,
                  start.map({ expense.date >= $0 }) ?? true else { return nil }
            return PlaceRecord(
                coordinate: Coordinate(latitude: latitude, longitude: longitude), name: expense.placeName,
                amount: expense.amount, date: expense.date, categoryKey: expense.categoryKey
            )
        }
        return PlaceSpending.totals(records)
    }

    var body: some View {
        let spends = spends
        let maxTotal = spends.map(\.total).max() ?? 1
        Map(position: $camera) {
            ForEach(spends) { spend in
                Annotation(
                    spend.name ?? String(localized: "Chưa đặt tên"),
                    coordinate: CLLocationCoordinate2D(latitude: spend.coordinate.latitude, longitude: spend.coordinate.longitude),
                    anchor: .bottom
                ) {
                    PlacePin(spend: spend, maxTotal: maxTotal, isSelected: spend.id == selection)
                        .onTapGesture { withAnimation(.snappy) { selection = spend.id } }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(spend.name ?? String(localized: "Chưa đặt tên")), \(MoneyFormatter.spoken(spend.total))"))
                        .accessibilityAddTraits(.isButton)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onTapGesture { withAnimation(.snappy) { selection = nil } }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Khoảng thời gian", selection: $span) {
                Text("Tháng này").tag(Span.month)
                Text("Tất cả").tag(Span.all)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let spend = spends.first(where: { $0.id == selection }) {
                card(spend)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if spends.isEmpty {
                Text("Chưa có khoản nào kèm vị trí. Bật “Gợi ý theo vị trí và giờ” ở Tùy chỉnh để Pennyline lưu nơi bạn ghi.")
                    .font(.subheadline)
                    .foregroundStyle(Color.xuTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
                    .padding(32)
            }
        }
        .navigationTitle("Bản đồ chi tiêu")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fit(spends) }
        .onChange(of: span) { fit(self.spends) }
        .sheet(item: $searchRequest) { request in
            SearchView(now: now, initialFilter: request.filter)
        }
    }

    /// Đưa bản đồ về vừa các chỗ, hoặc về chỗ đang được chọn từ màn Tháng.
    private func fit(_ spends: [PlaceSpend]) {
        let focused = initialSelection.flatMap { id in spends.first { $0.id == id } }
        let target = focused.map { [$0] } ?? spends
        guard let region = PlaceSpending.region(of: target) else { return }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
            span: MKCoordinateSpan(latitudeDelta: region.latitudeSpan, longitudeDelta: region.longitudeSpan)
        ))
    }

    private func card(_ spend: PlaceSpend) -> some View {
        let category = CategoryCatalog(custom: customCategories).info(for: spend.topCategoryKey)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(spend.name ?? String(localized: "Chưa đặt tên"))
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(MoneyFormatter.short(spend.total))
                    .font(.title3.weight(.bold))
                    .money(spend.total)
            }
            HStack(spacing: 6) {
                Text("\(spend.count) lần")
                Text("·")
                Text("gần nhất \(VietnameseDate.relativeDay(spend.lastDate, now: now, calendar: calendar))")
                Text("·")
                CategoryLabel(category: category, spacing: 4)
            }
            .font(.footnote)
            .foregroundStyle(Color.xuTextSecondary)
            .lineLimit(1)
            if let name = spend.name {
                Button("Xem các khoản") {
                    searchRequest = SearchRequest(filter: ExpenseFilter(text: name))
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Text("Mở một khoản ở đây và chạm “Nơi ghi” để đặt tên.")
                    .font(.footnote)
                    .foregroundStyle(Color.xuTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }
}

/// Chấm trên bản đồ: nhãn số tiền và một chấm tròn to theo số tiền so với chỗ chi nhiều nhất.
private struct PlacePin: View {
    let spend: PlaceSpend
    let maxTotal: Int
    let isSelected: Bool

    var body: some View {
        let ratio = maxTotal > 0 ? Double(spend.total) / Double(maxTotal) : 0
        let diameter = 10 + 16 * ratio.squareRoot()
        VStack(spacing: 3) {
            Text(MoneyFormatter.short(spend.total))
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Color.xuTextPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.xuButton : Color.xuHighlight, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.xuTextPrimary.opacity(isSelected ? 0.8 : 0.25), lineWidth: isSelected ? 1.5 : 1))
            Circle()
                .fill(Color.xuTextPrimary)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
        }
        .scaleEffect(isSelected ? 1.12 : 1)
        .animation(.snappy, value: isSelected)
    }
}

#Preview {
    NavigationStack {
        PlacesMapView(now: Date())
    }
    .xuPreview()
}
