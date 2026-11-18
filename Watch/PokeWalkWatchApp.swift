import SwiftUI
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in WatchModel.shared.activate() }
        Self.scheduleRefresh()
    }

    /// Ask watchOS to wake us about every 15 minutes so complications keep up with your steps.
    static func scheduleRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(15 * 60), userInfo: nil) { _ in }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refresh as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    await WatchModel.shared.refreshSteps()
                    Self.scheduleRefresh()
                    refresh.setTaskCompletedWithSnapshot(false)
                }
            case let connectivity as WKWatchConnectivityRefreshBackgroundTask:
                Task { @MainActor in WatchModel.shared.handle(connectivity) }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

@main
struct PokeWalkWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var model = WatchModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
                .task { await model.requestHealth() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refreshSteps() } }
                }
        }
    }
}
