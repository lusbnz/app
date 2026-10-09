import AppIntents
import SwiftUI
import WidgetKit

/// Widget màn hình khóa: số còn được tiêu và một nút cộng cho khoản hay ghi nhất.
/// Hệ thống chỉ chạy nút sau khi máy được mở khóa.
struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockWidget", provider: XuTimelineProvider()) { entry in
            LockWidgetView(entry: entry)
                .fontDesign(.rounded)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Hôm nay trên màn hình khóa")
        .description("Số còn được tiêu và nút ghi nhanh khoản hay ghi nhất.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockWidgetView: View {
    let entry: XuEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(MoneyFormatter.short(entry.remaining))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(entry.remaining < 0 ? "vượt hôm nay" : "còn hôm nay")
                    .font(.caption)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.remaining < 0
                ? "Hôm nay vượt \(MoneyFormatter.spoken(-entry.remaining))"
                : "Còn được tiêu hôm nay \(MoneyFormatter.spoken(entry.remaining))")
            Spacer(minLength: 4)
            if let item = entry.quick.first {
                Button(intent: LogQuickExpenseIntent(name: item.name, amount: item.amount)) {
                    Label(item.name, systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .accessibilityLabel("Ghi \(item.name) \(MoneyFormatter.spoken(item.amount))")
            }
        }
    }
}

#Preview(as: .accessoryRectangular) {
    LockWidget()
} timeline: {
    XuEntry.sample
}
