import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PhoneConnectivity.shared.activate()
        // Also runs when iOS relaunches us in the background for location or HealthKit updates.
        Task { @MainActor in GameStore.shared.start() }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["encounterID"] as? String {
            Task { @MainActor in GameStore.shared.openEncounter(id: id) }
        }
        completionHandler()
    }
}

@main
struct PokeWalkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = GameStore.shared
    @StateObject private var tracker = LocationTracker.shared
    @StateObject private var tracks = TrackStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(tracker)
                .environmentObject(tracks)
                .tint(Theme.tealDark)
                .task { await store.requestPermissions() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task {
                            await store.tick()
                            store.checkPendingEvolutions()
                            LiveActivityManager.shared.startIfNeeded(with: store)
                        }
                    case .background:
                        TrackStore.shared.flush()
                    default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        Group {
            if store.hasGame {
                MapHomeView()
            } else {
                OnboardingView()
            }
        }
        .fullScreenCover(item: $store.evolutionCandidate) { EvolutionView(candidate: $0) }
    }
}
