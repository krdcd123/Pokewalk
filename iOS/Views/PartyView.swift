import SwiftUI

/// Your party as big boxes (like the menu's tiles): hopping box sprite, name, level, Exp and what it's holding.
/// Tap a box for its Summary; tap "Take" to put its held item in the Bag.
struct PartyView: View {
    @EnvironmentObject private var store: GameStore
    @State private var open: UUID?
    enum Tab { case party, gyms }
    @State private var tab: Tab = .party

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Label("Party", systemImage: "circle.grid.2x2.fill").tag(Tab.party)
                Label("Gyms", systemImage: "flag.2.crossed.fill").tag(Tab.gyms)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 6)
            .onChange(of: tab) { _, _ in SoundKit.shared.play(.select) }
            switch tab {
            case .party: partyGrid
            case .gyms: FrontierView(mode: .gym).frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(tab == .party ? "Party" : "Gym Challenge")
        .glassScreen(transparent: true)
        .navigationDestination(item: $open) { id in
            PagedSummaryView(ids: store.state.partyIDs, start: id)
        }
    }

    private var partyGrid: some View {
        let party = store.state.party
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(party.enumerated()), id: \.element.id) { i, mon in
                    let isBuddy = mon.id == store.state.buddyID
                    PartyBox(mon: mon, index: i, isBuddy: isBuddy,
                             open: { open = mon.id },
                             take: { take(mon) })
                        // Hold: Summary, take its item, move it (the buddy always leads)
                        .contextMenu {
                            Button("Summary", systemImage: "info.circle") { open = mon.id }
                            if let key = mon.heldItems.first {
                                Button("Take \(Dex.itemName(key))", systemImage: "arrow.down.to.line") { take(mon) }
                            }
                            if !isBuddy {
                                if i > 1 {
                                    Button("Move earlier", systemImage: "arrow.left") { move(mon, to: i - 1) }
                                }
                                if i < party.count - 1 {
                                    Button("Move later", systemImage: "arrow.right") { move(mon, to: i + 1) }
                                }
                                Menu("Move to slot…", systemImage: "arrow.up.arrow.down") {
                                    ForEach(1..<party.count, id: \.self) { slot in
                                        Button("Slot \(slot + 1)") { move(mon, to: slot) }.disabled(slot == i)
                                    }
                                }
                            }
                        }
                }
                ForEach(party.count..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                        .frame(height: 172)
                }
            }
            .padding()
            .opacity(open == nil ? 1 : 0)                      // see-through panel: fade under the summary
            .animation(.easeInOut(duration: 0.22), value: open == nil)
        }
    }
}

extension PartyView {
    private func take(_ mon: OwnedPokemon) {
        SoundKit.shared.play(.select)
        let taken = store.takeHeldItems(mon.id)
        if let first = taken.first {
            store.toast = "Took the \(Dex.itemName(first)) from \(mon.name). It's in your Bag."
        }
    }

    private func move(_ mon: OwnedPokemon, to slot: Int) { move(mon.id, to: slot) }

    private func move(_ id: UUID, to slot: Int) {
        guard id != store.state.buddyID else { return }
        SoundKit.shared.play(.select)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(duration: 0.35)) { store.reorderParty(id, to: slot) }
    }
}

private struct PartyBox: View {
    let mon: OwnedPokemon
    let index: Int
    let isBuddy: Bool
    var open: () -> Void
    var take: () -> Void

    var body: some View {
        let tint = Color(mon.species.primaryType)
        Button(action: open) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    // The PC box sprite, bobbing between two frames like the games' party menu
                    // (driven by the clock, each box slightly out of step with the others)
                    TimelineView(.periodic(from: .now, by: 0.25)) { tl in
                        let tick = Int(tl.date.timeIntervalSinceReferenceDate / 0.25) + index
                        AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny, kind: .icons)
                            .frame(width: 72, height: 72)
                            .offset(y: tick % 2 == 0 ? -4 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    if isBuddy {
                        Image(systemName: "star.fill").font(.system(size: 13, weight: .black))
                            .foregroundStyle(Theme.orange)
                            .padding(6).background(.white.opacity(0.85), in: Circle())
                    }
                }
                HStack(spacing: 4) {
                    Text(mon.name).font(.rounded(16, .black)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(mon.gender.symbol).font(.rounded(13, .heavy))
                        .foregroundStyle(mon.gender == .female ? Color(hex: 0xFF8FA8) : Color(hex: 0x7FB8FF))
                    if mon.isShiny { Text("✨").font(.system(size: 11)) }
                }
                HStack {
                    Text("Lv \(mon.level)").font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
                    Spacer(minLength: 0)
                }
                ExpBar(progress: mon.levelProgress, tint: tint, height: 6)
                held
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(height: 172)
            .foregroundStyle(.white)
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .glassCard(24, tint: tint)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var held: some View {
        if let key = mon.heldItems.first {
            HStack(spacing: 6) {
                ItemSprite(key: key).frame(width: 22, height: 22)
                Text(Dex.itemName(key)).font(.rounded(11, .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 2)
                Button(action: take) {
                    Text("Take").font(.rounded(12, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Theme.teal.opacity(0.8), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.teal)
                Text("Pickup in \(max(0, mon.nextPickupAt - mon.pickupSteps).formatted()) · \(Int((GameRules.Pickup.chance(friendship: mon.friendship) * 100).rounded()))%")
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .font(.rounded(11, .heavy))
            .foregroundStyle(Theme.inkSoft)
            .frame(height: 26)
        }
    }
}
