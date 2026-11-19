import ActivityKit
import WidgetKit
import SwiftUI
import UIKit

/// Lock Screen card: buddy sprite, name, level and Exp. Dynamic Island: just the buddy's box icon.
struct PokeWalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(.horizontal, 16).padding(.vertical, 12)
                // iOS paints untinted third-party cards solid black; a light, mostly-clear neutral tint
                // lets the system blur through, matching the music player's glass.
                .activityBackgroundTint(Color(white: 0.62).opacity(0.28))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    LockScreenView(state: context.state)
                }
            } compactLeading: {
                BuddyIcon(data: context.state.iconPNG).frame(width: 30, height: 24)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                BuddyIcon(data: context.state.iconPNG).frame(width: 24, height: 20)
            }
            .keylineTint(Theme.teal)
        }
        .supplementalActivityFamilies([.small])   // Apple Watch Smart Stack
    }
}

private struct BuddyImage: View {
    let data: Data?
    var body: some View {
        if let data, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().interpolation(.none).scaledToFit()
        } else {
            Image(systemName: "figure.walk").resizable().scaledToFit().padding(6)
        }
    }
}

private struct BuddyIcon: View {
    let data: Data?
    var body: some View {
        if let data, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().interpolation(.none).scaledToFit()
        } else {
            Image(systemName: "pawprint.fill").resizable().scaledToFit().foregroundStyle(Theme.teal)
        }
    }
}

private struct LockScreenView: View {
    @Environment(\.activityFamily) private var family
    let state: WalkActivityAttributes.ContentState

    var body: some View {
        if family == .small {
            HStack(spacing: 8) {
                BuddyImage(data: state.spritePNG).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.buddyName) Lv\(state.level)").font(.system(size: 14, weight: .heavy, design: .rounded)).lineLimit(1)
                    ExpBar(progress: state.progress, tint: Theme.teal, height: 4)
                }
            }
        } else {
            HStack(spacing: 14) {
                BuddyImage(data: state.spritePNG).frame(width: 64, height: 64)
                    .id(state.level)
                    .transition(.push(from: .bottom))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(state.buddyName).font(.system(size: 19, weight: .black, design: .rounded))
                        Text("Lv \(state.level)").font(.system(size: 16, weight: .heavy, design: .rounded))
                            .contentTransition(.numericText(value: Double(state.level)))
                            .foregroundStyle(Theme.teal)
                        Spacer()
                    }
                    ExpBar(progress: state.progress, tint: Theme.teal, height: 8)
                    HStack {
                        Text("\(state.expToNext.formatted()) Exp to next")
                            .contentTransition(.numericText(value: Double(state.expToNext)))
                        Spacer()
                        Text(state.pendingEncounters > 0 ? "\(state.pendingEncounters) wild waiting"
                                                         : "\(state.stepsToEncounter) steps to encounter")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                }
            }
            .foregroundStyle(.white)
        }
    }
}

@main
struct PokeWalkLiveBundle: WidgetBundle {
    var body: some Widget { PokeWalkLiveActivity() }
}
