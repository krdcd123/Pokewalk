import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        NavigationStack {
            if model.hasData {
                TabView {
                    if let buddy = model.snapshot.buddy { BuddyPage(member: buddy) }
                    PartyPage()
                }
                .tabViewStyle(.verticalPage)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.and.arrow.forward").font(.largeTitle)
                    Text("Open PokéWalk on your iPhone and pick a partner.")
                        .multilineTextAlignment(.center).font(.footnote)
                }
            }
        }
    }
}

struct BuddyPage: View {
    @EnvironmentObject private var model: WatchModel
    let member: WatchSnapshot.Member

    var body: some View {
        let live = model.live(member)
        let tint = Color(member.species.primaryType)
        ScrollView {
            VStack(spacing: 6) {
                // Hops like the selected Pokémon on the party screen in the games.
                TimelineView(.periodic(from: .now, by: 0.22)) { ctx in
                    let up = Int(ctx.date.timeIntervalSinceReferenceDate / 0.22) % 2 == 0
                    LocalIcon(speciesID: member.speciesID)
                        .id("\(member.speciesID)-\(model.spriteVersion)")
                        .frame(width: 80, height: 60)
                        .overlay(alignment: .topTrailing) { if member.heldItem != nil { HeldDot() } }
                        .offset(y: up ? -5 : 0)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(member.name).font(.headline).lineLimit(1)
                    Text("Lv \(live.level)").font(.caption.monospacedDigit()).foregroundStyle(tint)
                }
                ExpBar(progress: live.progress, tint: tint, height: 6)
                Text("\(live.stepsToNext.formatted()) steps to next").font(.caption2).foregroundStyle(.secondary)

                if live.level > live.syncedLevel {
                    Label("Level up! Sync to claim", systemImage: "arrow.up.circle.fill").font(.caption2).foregroundStyle(.yellow)
                }
                if live.readyToEvolve {
                    Label("Ready to evolve!", systemImage: "sparkles").font(.caption2).foregroundStyle(.yellow)
                }
                if model.snapshot.pendingEncounters > 0 {
                    Label("\(model.snapshot.pendingEncounters) wild Pokémon on your phone", systemImage: "leaf.fill")
                        .font(.caption2).foregroundStyle(Theme.orange)
                }

                Grid(horizontalSpacing: 8, verticalSpacing: 4) {
                    GridRow {
                        stat(model.stepsToday.formatted(), "today")
                        stat("×\(model.liveBalls)", "balls")
                    }
                    GridRow {
                        stat(model.liveStepsToEncounter.formatted(), "to encounter")
                        stat(String(format: "%.1f", model.snapshot.distanceTodayKm / 1.609344), "mi")
                    }
                }
                .padding(.top, 4)

                Button { model.requestPhoneSync() } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(tint).padding(.top, 4)

                if let status = model.syncStatus {
                    Text(status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Buddy")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PartyPage: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        List(model.snapshot.party) { member in
            let live = model.live(member)
            HStack {
                LocalIcon(speciesID: member.speciesID).id("\(member.speciesID)-\(model.spriteVersion)")
                    .frame(width: 36, height: 28)
                    .overlay(alignment: .topTrailing) { if member.heldItem != nil { HeldDot(size: 8) } }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(member.name).font(.footnote.weight(.semibold)).lineLimit(1)
                        if member.isBuddy { Image(systemName: "figure.walk").font(.caption2).foregroundStyle(.green) }
                        if member.isShiny { Text("✨").font(.caption2) }
                        Spacer()
                        Text("\(live.level)").font(.footnote.monospacedDigit())
                    }
                    ExpBar(progress: live.progress, tint: Color(member.species.primaryType), height: 4)
                }
            }
        }
        .navigationTitle("Party")
    }
}

/// Red "holding an item" dot.
struct HeldDot: View {
    var size: CGFloat = 11
    var body: some View {
        Circle().fill(Color.red).overlay(Circle().stroke(.black, lineWidth: 1.5)).frame(width: size, height: size)
    }
}
