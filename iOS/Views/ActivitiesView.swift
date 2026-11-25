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

    var body: some View {
        VStack(spacing: 0) {
            Picker("Activity", selection: $tab) {
                ForEach(Tab.allCases) { t in Label(t.rawValue, systemImage: t.symbol).tag(t) }
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
        .navigationTitle(tab.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .glassScreen(transparent: true)
    }
}
