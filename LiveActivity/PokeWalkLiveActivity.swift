import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen / Dynamic Island Live Activity. On watchOS 11+ it also appears in the
/// Apple Watch Smart Stack automatically, so you still see your buddy if the Watch app can't be installed.
struct PokeWalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(14)
                .activityBackgroundTint(Theme.ground)
                .activitySystemActionForegroundColor(Theme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LocalIcon(speciesID: context.state.speciesID).frame(width: 44, height: 34)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("×\(context.state.balls)").font(.rounded(16, .black))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.buddyName) Lv \(context.state.level)").font(.rounded(15, .black))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ExpBar(progress: context.state.progress, tint: Theme.teal, height: 6)
                        Text(encounterLine(context.state)).font(.rounded(12)).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                LocalIcon(speciesID: context.state.speciesID).frame(width: 26, height: 20)
            } compactTrailing: {
                Text("\(context.state.stepsToEncounter)").font(.rounded(13, .black)).monospacedDigit()
            } minimal: {
                LocalIcon(speciesID: context.state.speciesID).frame(width: 22, height: 18)
            }
        }
        .supplementalActivityFamilies([.small])   // Apple Watch Smart Stack / CarPlay
    }

    private func encounterLine(_ s: WalkActivityAttributes.ContentState) -> String {
        s.pendingEncounters > 0 ? "\(s.pendingEncounters) wild Pokémon waiting!" : "\(s.stepsToEncounter) steps to next encounter"
    }
}

private struct LockScreenView: View {
    @Environment(\.activityFamily) private var family
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        if family == .small {
            // Apple Watch Smart Stack
            HStack(spacing: 8) {
                LocalIcon(speciesID: state.speciesID).frame(width: 40, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.buddyName) Lv\(state.level)").font(.rounded(14, .black)).lineLimit(1)
                    ExpBar(progress: state.progress, tint: Theme.teal, height: 4)
                    Text(state.pendingEncounters > 0 ? "\(state.pendingEncounters) wild waiting" : "\(state.stepsToEncounter) to encounter")
                        .font(.rounded(11)).foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 12) {
                LocalIcon(speciesID: state.speciesID).frame(width: 56, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(state.buddyName).font(.rounded(17, .black))
                        Text("Lv \(state.level)").font(.rounded(15, .heavy)).foregroundStyle(Theme.tealDark)
                        Spacer()
                        Text("×\(state.balls) balls").font(.rounded(13, .heavy))
                    }
                    ExpBar(progress: state.progress, tint: Theme.teal, height: 6)
                    HStack {
                        Text(state.pendingEncounters > 0 ? "\(state.pendingEncounters) wild Pokémon waiting!"
                                                         : "\(state.stepsToEncounter) steps to next encounter")
                        Spacer()
                        Text("\(state.stepsToday.formatted()) steps · \(String(format: "%.1f", state.kmToday)) km")
                    }
                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .foregroundStyle(Theme.ink)
        }
    }
}

@main
struct PokeWalkLiveBundle: WidgetBundle {
    var body: some Widget { PokeWalkLiveActivity() }
}
