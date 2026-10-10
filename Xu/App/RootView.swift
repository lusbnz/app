import SwiftData
import SwiftUI

/// Điều hướng gốc: lần đầu mở app, rồi Hôm nay và các sheet.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var now = Date()

    var body: some View {
        @Bindable var appState = appState
        Group {
            if settings.monthlyBudget > 0 {
                NavigationStack {
                    TodayView(now: now)
                }
                .sheet(item: $appState.entry) { request in
                    EntryView(request: request, now: now)
                }
                .sheet(isPresented: $appState.showsReceipt) {
                    ReceiptView(now: now, image: appState.receiptImage)
                }
            } else {
                OnboardingView()
            }
        }
        .sheet(isPresented: $appState.showsPaywall) {
            PaywallView()
        }
        .tint(Color.xuToggle)
        .sensoryFeedback(.success, trigger: appState.saveCount)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
                NotificationManager.shared.refreshDailyReminder()
                recordAutomaticRecurring()
                // Thử lại các khoản chưa tra được tên nơi (lúc đó mất mạng, chẳng hạn).
                Task { await PlaceLookup.shared.backfill(context: modelContext, groupLimit: 5) }
                NotificationManager.shared.refreshRecurringReminders()
                NotificationManager.shared.refreshSummaryReminders()
            }
        }
        .onAppear { recordAutomaticRecurring() }
    }
}

extension RootView {
    /// Khoản định kỳ đặt "tự ghi" đã đến hạn thì ghi khi mở app; lần ghi cuối hiện ở thanh Hoàn tác.
    @MainActor
    fileprivate func recordAutomaticRecurring() {
        guard settings.monthlyBudget > 0 else { return }
        let batches = ExpenseRecorder(context: modelContext).recordAutomaticRecurring(now: Date(), calendar: .current)
        if let last = batches.last { appState.didSave(last) }
    }
}

#Preview("Hôm nay") {
    RootView().xuPreview()
}

#Preview("Lần đầu") {
    RootView().xuPreview(budget: 0)
}
