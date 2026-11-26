import SwiftUI

/// Garden, Ranch, Daycare and Contest Hall in one place: swap between them with the tabs at the top.
struct ActivitiesView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case garden = "Garden", ranch = "Ranch", daycare = "Daycare", contests = "Contests"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .garden: return "leaf.fill"
            case .ranch: return "house.lodge.fill"
            case .daycare: return "oval.portrait.fill"
            case .contests: return "rosette"
            }
        }
    }

    @State var tab: Tab
    @EnvironmentObject private var store: GameStore
    @State private var unlocked: String?

    /// The Daycare and Contest Hall only appear once the Ranch is far enough along to build them.
    private var tabs: [Tab] {
        Tab.allCases.filter { t in
            switch t {
            case .daycare: return DaycareRules.canStart(store.state) || store.state.daycare.open
            case .contests: return ContestRules.canStart(store.state) || store.state.contests.open
            default: return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Activity", selection: $tab) {
                ForEach(tabs) { t in Label(t.rawValue, systemImage: t.symbol).tag(t) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 6)
            .onChange(of: tab) { _, _ in SoundKit.shared.play(.select) }
            Group {
                switch tab {
                case .garden: GardenView()
                case .ranch: RanchView()
                case .daycare: DaycareView()
                case .contests: ContestHallView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onChange(of: tabs) { old, new in
            // a tab just appeared: say so
            if let t = new.first(where: { !old.contains($0) }) {
                unlocked = t == .daycare ? "Daycare" : "Contest Hall"
            }
            if !new.contains(tab) { tab = .ranch }
        }
        .alert("\(unlocked ?? "") unlocked!", isPresented: Binding(get: { unlocked != nil }, set: { if !$0 { unlocked = nil } })) {
            Button("Great!") { SoundKit.shared.play(.select) }
        } message: {
            Text("You can now build the \(unlocked ?? "") — find it in the tabs at the top of Activities.")
        }
        .navigationTitle(tab.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .glassScreen(transparent: true)
    }
}
