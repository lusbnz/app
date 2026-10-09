import AppIntents
import SwiftUI
import WidgetKit

/// Widget màn hình chính: cỡ nhỏ hiện số còn được tiêu, cỡ vừa thêm hai nút ghi nhanh.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: XuTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
                .fontDesign(.rounded)
                .containerBackground(Color.xuBackground, for: .widget)
        }
        .configurationDisplayName("Hôm nay")
        .description("Hôm nay còn được tiêu bao nhiêu.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: XuEntry

    var body: some View {
        if !entry.hasBudget {
            Text("Mở Xu để đặt ngân sách tháng.")
                .font(.subheadline)
                .foregroundStyle(Color.xuTextSecondary)
        } else if family == .systemMedium {
            HStack(spacing: 12) {
                number
                Spacer(minLength: 0)
                quickButtons
            }
        } else {
            number
        }
    }

    private var number: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            HighlightedNumber(text: MoneyFormatter.short(entry.remaining), fraction: entry.fraction, size: 40)
            Text(entry.remaining < 0 ? "vượt hôm nay" : "còn được tiêu hôm nay")
                .font(.caption)
                .foregroundStyle(Color.xuTextSecondary)
        }
        .foregroundStyle(Color.xuTextPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.remaining < 0
            ? "Hôm nay vượt \(MoneyFormatter.spoken(-entry.remaining))"
            : "Còn được tiêu hôm nay \(MoneyFormatter.spoken(entry.remaining))")
    }

    @ViewBuilder
    private var quickButtons: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !entry.canSave {
                Text("Hết 5 lần hôm nay.\nMở Xu để dùng Xu Pro.")
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Color.xuTextSecondary)
            } else if entry.quick.isEmpty {
                Text("Ghi vài khoản để có nút ghi nhanh.")
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Color.xuTextSecondary)
            } else {
                ForEach(entry.quick) { item in
                    Button(intent: LogQuickExpenseIntent(name: item.name, amount: item.amount)) {
                        Text("\(item.name) \(MoneyFormatter.short(item.amount))")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(Color.xuOnButton)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(Color.xuButton, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ghi \(item.name) \(MoneyFormatter.spoken(item.amount))")
                }
            }
        }
    }
}

#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    XuEntry.sample
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    XuEntry.sample
}
