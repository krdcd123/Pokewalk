import SwiftUI

struct SummaryView: View {
    @Environment(\.summaryActive) private var summaryActive
    @Environment(\.summaryPaged) private var summaryPaged
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let pokemonID: UUID

    @State private var renaming = false
    @State private var newName = ""
    @State private var showItems = false
    @State private var message: String?
    @State private var confirmRelease = false
    @Environment(\.overMap) private var overMap

    private var mon: OwnedPokemon? { store.state.mon(pokemonID) }

    var body: some View {
        if let mon {
            let tint = Color(mon.species.primaryType)
            let isBuddy = mon.id == store.state.buddyID
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        BallSendOut(speciesID: mon.speciesID, shiny: mon.isShiny, ball: mon.ball, skip: isBuddy, interactive: true) {
                            CryPlayer.shared.play(mon.speciesID)
                        }
                        .id(mon.speciesID)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(mon.name).font(.rounded(28, .black))
                            Text(mon.gender.symbol).font(.rounded(18, .heavy))
                                .foregroundStyle(mon.gender == .female ? Color(hex: 0xD6457A) : Color(hex: 0x3D7BE0))
                            Text("Lv \(mon.level)").font(.rounded(18, .heavy)).foregroundStyle(Theme.inkSoft)
                        }
                        Text("\(mon.species.dexNumber) \(mon.species.name)\(mon.isShiny ? " ✨" : "")")
                            .font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                        HStack { ForEach(mon.species.types, id: \.self) { TypeChip(type: $0) } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(mon.level < 100 ? "Exp to Lv \(mon.level + 1)" : "Max level").font(.rounded(13, .heavy))
                            Spacer()
                            Text(mon.expToNext.formatted()).font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
                        }
                        ExpBar(progress: mon.levelProgress, tint: tint)
                        Text(evolutionText(mon)).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                    .cardStyle().padding(.horizontal)

                    VStack(spacing: 0) {
                        row("OT", mon.otName)
                        row("ID No.", mon.otIDString)
                        row("Met", "\(mon.metDate.formatted(date: .abbreviated, time: .omitted)) at Lv \(mon.metLevel)")
                        row("Caught in", mon.ball.name)
                        row("Nature", mon.nature)
                        row("Characteristic", mon.characteristic)
                        row("Friendship", friendshipText(mon.friendship))
                        row("Steps walked", mon.stepsWalked.formatted())
                        row("Location", store.state.locationText(of: mon.id), last: true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .glassCard(20)
                    .padding(.horizontal)

                    if !mon.heldItems.isEmpty {
                        HeldItemsCard(mon: mon) {
                            let taken = store.takeHeldItems(mon.id)
                            if let first = taken.first { store.toast = "Took the \(Dex.itemName(first)) from \(mon.name). It's in your Bag." }
                        }
                        .padding(.horizontal)
                    } else if store.state.partyIDs.contains(mon.id) {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.raised.fill").foregroundStyle(Theme.teal)
                            Text("Next pickup in about \(max(0, mon.nextPickupAt - mon.pickupSteps).formatted()) steps")
                                .font(.rounded(14, .heavy))
                            Spacer()
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                        .glassCard(18)
                        .padding(.horizontal)
                    }

                    MetCard(mon: mon).padding(.horizontal)

                    VStack(spacing: 10) {
                        if let into = GameRules.pendingEvolution(for: mon, ignoringDecline: true) {
                            actionButton(store.state.dexCaught.contains(into) ? "Evolve into \(Dex.species(into).name)"
                                                                              : "Evolve \(mon.name)", "sparkles", filled: true) {
                                store.evolutionCandidate = .init(pokemonID: mon.id, into: into)
                            }
                        }
                        if !isBuddy {
                            actionButton("Walk with \(mon.name)", "figure.walk", filled: true) {
                                Task { await store.setBuddy(mon.id) }
                            }
                        } else {
                            Label("Your walking buddy", systemImage: "figure.walk.circle.fill")
                                .font(.rounded(15, .heavy)).foregroundStyle(Theme.tealDark)
                        }
                        HStack(spacing: 10) {
                            actionButton("Rename", "pencil") { newName = mon.nickname ?? ""; renaming = true }
                            actionButton("Use item", "bag") { showItems = true }
                        }
                        if !isBuddy {
                            Button("Release", role: .destructive) { confirmRelease = true }
                                .font(.rounded(15, .heavy)).padding(.top, 4)
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 30)
                }
            }
            .navigationTitle(mon.name)
            .glassScreen(transparent: true)
            .onAppear { if isBuddy && summaryActive { CryPlayer.shared.play(mon.speciesID) } }
            .onChange(of: summaryActive) { _, now in if now && isBuddy { CryPlayer.shared.play(mon.speciesID) } }
            .background {
                // In the swipeable summary the pager draws this itself (full height, behind the title bar)
                if !summaryPaged { SummaryBackdrop(tint: tint, overMap: overMap) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Nickname", isPresented: $renaming) {
                TextField(mon.species.name, text: $newName)
                Button("Save") { store.rename(mon.id, to: newName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            }
            .confirmationDialog("Release \(mon.name)? This can't be undone.", isPresented: $confirmRelease, titleVisibility: .visible) {
                Button("Release", role: .destructive) { store.release(mon.id); dismiss() }
            }
            .sheet(isPresented: $showItems) {
                ItemPicker { item in
                    showItems = false
                    let outcome = store.use(item, on: mon.id)
                    if outcome != .noEffect { SoundKit.shared.play(.useItem) }
                    switch outcome {
                    case .noEffect: message = "It won't have any effect."
                    case .leveled(let l): message = "\(mon.name) is now Lv \(l)!"
                    case .evolves: break
                    case .friendship(let up): message = up ? "\(mon.name) became more friendly!" : "\(mon.name) looks bitter…"
                    }
                }
                .presentationDetents([.medium, .large])
            }
        } else {
            ContentUnavailableView("Pokémon not found", systemImage: "questionmark")
        }
    }

    private func row(_ k: String, _ v: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(k).font(.rounded(13)).foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 12)
                Text(v).font(.rounded(14, .heavy)).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)
            if !last { Divider() }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.rounded(15, .heavy))
                .frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(.white)
                .contentShape(Capsule())
                .glassCapsule(tint: filled ? Theme.teal : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func evolutionText(_ mon: OwnedPokemon) -> String {
        let evos = mon.species.evolutions
        guard !evos.isEmpty else { return "Fully evolved · \(mon.stepsWalked.formatted()) steps walked together" }
        // Don't spoil what it becomes until you've caught that Pokémon yourself
        return "Evolves: " + evos.map { $0.summary(revealName: store.state.dexCaught.contains($0.into)) }
            .joined(separator: "; ")
    }

    private func friendshipText(_ f: Int) -> String {
        switch f {
        case 220...: return "Best friends (\(f))"
        case 150..<220: return "Very friendly (\(f))"
        case 70..<150: return "Friendly (\(f))"
        default: return "Getting to know you (\(f))"
        }
    }
}

struct ItemPicker: View {
    @EnvironmentObject private var store: GameStore
    let pick: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                let keys = store.state.bag.keys.sorted { Dex.itemName($0) < Dex.itemName($1) }
                if keys.isEmpty {
                    ContentUnavailableView("Bag is empty", systemImage: "bag",
                                           description: Text("You find an item every \(store.state.settings.itemSteps.formatted()) steps."))
                }
                ForEach(keys, id: \.self) { key in
                    Button { pick(key) } label: {
                        HStack(spacing: 12) {
                            ItemSprite(key: key).frame(width: 30, height: 30)
                            Text(Dex.itemName(key)).font(.rounded(16, .heavy)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("×\(store.state.bag[key] ?? 0)").font(.rounded(15, .heavy)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .glassRow()
                }
            }
            .navigationTitle("Use an item")
            .glassScreen()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


/// The item a Pokémon picked up on a walk; "Take" moves it into the Bag.
private struct HeldItemsCard: View {
    let mon: OwnedPokemon
    var take: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let key = mon.heldItems.first {
                ItemSprite(key: key).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Holding").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                    Text(Dex.itemName(key)).font(.rounded(16, .heavy))
                }
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                take()
            } label: {
                Label("Take", systemImage: "arrow.down.to.line")
                    .font(.rounded(15, .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(Theme.teal.opacity(0.75), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .glassCard(20)
    }
}

/// Swipe left/right between Pokémon summaries (from the PC).
struct PagedSummaryView: View {
    let ids: [UUID]
    @State private var current: UUID

    init(ids: [UUID], start: UUID) {
        self.ids = ids
        _current = State(initialValue: start)
    }

    @EnvironmentObject private var store: GameStore
    @Environment(\.overMap) private var overMap

    var body: some View {
        TabView(selection: $current) {
            ForEach(ids, id: \.self) { id in
                SummaryView(pokemonID: id).tag(id)
                    .environment(\.summaryActive, id == current)
                    .environment(\.summaryPaged, true)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .bottom)
        // The type colour sits behind the whole page (pages of a TabView stop at the title bar, which cut it off)
        .background {
            SummaryBackdrop(tint: store.state.mon(current).map { Color($0.species.primaryType) } ?? Theme.teal,
                            overMap: overMap)
                .animation(.easeInOut(duration: 0.35), value: current)
        }
        .containerBackground(.clear, for: .navigation)
    }
}

/// The Summary's background: the Pokémon's type colour fading down the screen.
struct SummaryBackdrop: View {
    let tint: Color
    var overMap: Bool

    var body: some View {
        ZStack {
            if !overMap { AppBackground() }
            // Fades in from clear at the top, so there's no hard edge under the panel's handle.
            LinearGradient(stops: [.init(color: tint.opacity(0), location: 0),
                                   .init(color: tint.opacity(0.42), location: 0.16),
                                   .init(color: tint.opacity(0.24), location: 0.38),
                                   .init(color: tint.opacity(0.07), location: 0.6),
                                   .init(color: .clear, location: 0.85)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

private struct SummaryPagedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var summaryPaged: Bool {
        get { self[SummaryPagedKey.self] }
        set { self[SummaryPagedKey.self] = newValue }
    }
}


private struct SummaryActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    /// False for the neighbouring pages a swipeable summary pre-loads, so only the page you're on animates and cries.
    var summaryActive: Bool {
        get { self[SummaryActiveKey.self] }
        set { self[SummaryActiveKey.self] = newValue }
    }
}
