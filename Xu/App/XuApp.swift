import SwiftData
import SwiftUI

@main
struct XuApp: App {
    @State private var settings = AppSettings()
    @State private var appState = AppState.shared

    init() {
        EntitlementStore.shared.start()
        NotificationManager.shared.start()
        ExpenseRecorder.afterCommit = {
            NotificationManager.shared.refreshDailyReminder()
            NotificationManager.shared.refreshRecurringReminders()
            Task { await PlaceMonitor.shared.refresh() }
        }
        // Dựng lại CLMonitor mỗi lần app chạy, kể cả khi hệ thống mở app ngầm vì một vùng theo dõi.
        Task { await PlaceMonitor.shared.refresh() }
        #if DEBUG
        DebugLaunch.apply(settings: settings, appState: appState, container: XuStore.shared)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(appState)
                .environment(LocationProvider.shared)
                .environment(EntitlementStore.shared)
                .fontDesign(.rounded)
                .tint(Color.xuToggle)
        }
        .modelContainer(XuStore.shared)
    }
}
