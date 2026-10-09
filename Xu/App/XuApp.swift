import SwiftData
import SwiftUI

@main
struct XuApp: App {
    @State private var settings = AppSettings()
    @State private var appState = AppState.shared

    init() {
        NotificationManager.shared.start()
        ExpenseRecorder.afterCommit = { NotificationManager.shared.refreshDailyReminder() }
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
                .fontDesign(.rounded)
                .tint(Color.xuToggle)
        }
        .modelContainer(XuStore.shared)
    }
}
