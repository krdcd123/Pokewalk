import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        CrashReporter.install()
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
                .preferredColorScheme(.dark)   // one consistent Liquid Glass look (dark map, white text)
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
    @State private var crashReport: String? = CrashReporter.takeLastReport()

    var body: some View {
        Group {
            if store.hasGame {
                MapHomeView()
            } else {
                OnboardingView()
            }
        }
        .fullScreenCover(item: $store.evolutionCandidate) { EvolutionView(candidate: $0) }
        .sheet(isPresented: Binding(get: { crashReport != nil }, set: { if !$0 { crashReport = nil } })) {
            CrashReportView(report: crashReport ?? "") { crashReport = nil }
        }
    }
}

/// Shown on the launch after a crash so the report can be copied and sent.
struct CrashReportView: View {
    let report: String
    let done: () -> Void
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PokéWalk crashed last time. Tap Copy and send this report so it can be fixed.")
                        .font(.rounded(15, .heavy))
                    Text(report).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("Crash report")
            .navigationBarTitleDisplayMode(.inline)
            .glassScreen()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "Copied" : "Copy") { UIPasteboard.general.string = report; copied = true }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done", action: done) }
            }
        }
    }
}
