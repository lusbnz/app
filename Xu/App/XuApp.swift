import SwiftData
import SwiftUI

@main
struct XuApp: App {
    @State private var settings = AppSettings()
    @State private var appState = AppState.shared
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

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
                .environment(lock)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    lock.scenePhaseChanged(phase)
                }
                .onChange(of: lock.shouldCover, initial: true) { _, covering in
                    LockWindowPresenter.shared.update(covering: covering, lock: lock, appearance: settings.appearance)
                }
                .environment(settings)
                .environment(appState)
                .environment(LocationProvider.shared)
                .environment(EntitlementStore.shared)
                .fontDesign(.rounded)
                .tint(Color.xuToggle)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .modelContainer(XuStore.shared)
    }
}
