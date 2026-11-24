import SwiftUI
import WatchKit
import UserNotifications

final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in WatchModel.shared.activate() }
        Self.scheduleRefresh()
    }

    /// Tapping a PokéWalk notification on the watch opens the watch app on the right screen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let encounter = info["encounterID"] as? String
        let open = info["open"] as? String
        Task { @MainActor in
            let model = WatchModel.shared
            if let encounter {
                model.path = [.wild, .battle(encounter)]
            } else if open == "pickup" {
                model.path = [.party]
            } else {
                model.path = []
            }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
                    if phase == .active { model.becameActive() } else { model.resignedActive() }
                }
                .onAppear { model.becameActive() }
                .onOpenURL { model.open($0) }
        }
    }
}
