import SwiftUI

struct PCView: View {
    @State private var playedOpen = false
    @State private var showStorage = false
    @State private var releasing: OwnedPokemon?
    @EnvironmentObject private var store: GameStore
    @State private var boxIndex = 0
    @State private var moving = false
    @State private var held: PCSlot?
    @State private var open: UUID?
    @State private var renamingBox = false
    @State private var boxName = ""
    @State private var search = ""

    static let wallpapers: [[UInt32]] = [
        [0xBFE3B2, 0x9FD3C8], [0xCFE6F7, 0x9CC6EC], [0xF7E3C4, 0xF2B98A], [0xE5D9F6, 0xB9A9F0],
        [0xF6D5DE, 0xEFA7BC], [0xD9E4E2, 0xA9BCB9], [0xFFF1B8, 0xF2D06B], [0x2A3B4C, 0x1B2733],
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !search.isEmpty {
                    searchResults
                } else {
                    partyCard
                    boxHeader
                    boxGrid
                    Text(moving ? (held == nil ? "Tap a Pokémon to pick it up." : "Tap a slot to place or swap it.")
                                : "Tap a Pokémon for its summary (swipe to see the others). Hold one for more options.")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding()
        }
        .navigationTitle("PC")
        .navigationDestination(isPresented: $showStorage) { StorageView() }
        .onAppear { if !playedOpen { playedOpen = true; SoundKit.shared.play(.openPC) } }
        .onDisappear { if open == nil && !showStorage { SoundKit.shared.play(.closePC) } }
        .glassScreen()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search names, species, places")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showStorage = true } label: {
                    Image(systemName: "shippingbox.fill")
                }
                .accessibilityLabel("Storage")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(moving ? "Done" : "Move") { moving.toggle(); held = nil }
                    .font(.rounded(16, .heavy))
            }
        }
        .navigationDestination(item: $open) { id in
            PagedSummaryView(ids: browseOrder(startingNear: id), start: id)
        }
        .confirmationDialog(releasing.map { "Release \($0.name)? You'll never see it again." } ?? "",
                            isPresented: Binding(get: { releasing != nil }, set: { if !$0 { releasing = nil } }),
                            titleVisibility: .visible) {
            if let mon = releasing {
                Button("Release \(mon.name)", role: .destructive) {
                    store.release(mon.id)
                    store.toast = "\(mon.name) was released. Bye-bye, \(mon.name)!"
                }
            }
        }
        .alert("Rename box", isPresented: $renamingBox) {
            TextField("Box name", text: $boxName)
            Button("Save") { store.renameBox(boxIndex, to: boxName) }
            Button("Cancel", role: .cancel) {}
        }
            }

    // MARK: Party

    private var partyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PARTY · SHOWN ON YOUR WATCH").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Text("\(store.state.pokemon.count) Pokémon · Dex \(store.state.dexCaught.count)/\(Dex.count)")
                    .font(.rounded(11)).foregroundStyle(Theme.inkSoft)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<GameState.maxParty, id: \.self) { i in
                    let id = i < store.state.partyIDs.count ? store.state.partyIDs[i] : nil
                    slotView(id: id, slot: .party(i), tall: true)
                }
            }
        }
        .cardStyle()
    }

    // MARK: Box

    private var box: PCBox { store.state.boxes[min(boxIndex, store.state.boxes.count - 1)] }

    private var boxHeader: some View {
        HStack {
            Button { withAnimation { boxIndex = (boxIndex - 1 + store.state.boxes.count) % store.state.boxes.count } } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
                    .glassCircle()
            }
            .accessibilityLabel("Previous box")
            Spacer()
            Menu {
                Button("Rename box", systemImage: "pencil") { boxName = box.name; renamingBox = true }
                Menu("Wallpaper") {
                    ForEach(0..<Self.wallpapers.count, id: \.self) { w in
                        Button("Wallpaper \(w + 1)") { store.setWallpaper(boxIndex, w) }
                    }
                }
                Button("Add a box", systemImage: "plus") { store.addBox() }
            } label: {
                VStack(spacing: 0) {
                    Text(box.name).font(.rounded(20, .black))
                    Text("Box \(boxIndex + 1) of \(store.state.boxes.count) · \(box.count)/\(PCBox.capacity)")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer()
            Button { withAnimation { boxIndex = (boxIndex + 1) % store.state.boxes.count } } label: {
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
                    .glassCircle()
            }
            .accessibilityLabel("Next box")
        }
    }

    private var boxGrid: some View {
        let wp = Self.wallpapers[box.wallpaper % Self.wallpapers.count]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<PCBox.capacity, id: \.self) { i in
                slotView(id: box.slots[i], slot: .box(boxIndex, i), tall: false)
            }
        }
        .padding(12)
        .background(LinearGradient(colors: [Color(hex: wp[0]).opacity(0.55), Color(hex: wp[1]).opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22))
        .glassCard(22)
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            withAnimation {
                let n = store.state.boxes.count
                boxIndex = v.translation.width < 0 ? (boxIndex + 1) % n : (boxIndex - 1 + n) % n
            }
        })
    }

    @ViewBuilder
    private func slotView(id: UUID?, slot: PCSlot, tall: Bool) -> some View {
        let mon = store.state.mon(id)
        let isHeld = held == slot
        Button {
            tap(slot: slot, id: id)
        } label: {
            VStack(spacing: 1) {
                if let mon {
                    AnimatedSprite(speciesID: mon.speciesID, kind: .icons).frame(height: 30)
                    if tall { Text("Lv \(mon.level)").font(.rounded(10, .heavy)) }
                } else {
                    Color.clear.frame(height: 30)
                }
            }
            .frame(maxWidth: .infinity).frame(height: tall ? 56 : 50)
            .background(mon == nil ? Color.white.opacity(0.12) : Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isHeld ? Theme.orange : (mon?.id == store.state.buddyID ? Theme.teal : .clear), lineWidth: 3))
            .overlay(alignment: .topTrailing) { if mon?.isShiny == true { Text("✨").font(.system(size: 9)).padding(2) } }
            .scaleEffect(isHeld ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let mon, !moving { holdMenu(mon: mon, slot: slot) }
        }
        .accessibilityLabel(mon.map { "\($0.name), level \($0.level)" } ?? "Empty slot")
    }

    /// Hold a Pokémon: Liquid Glass menu with party / move / summary / storage / release.
    @ViewBuilder private func holdMenu(mon: OwnedPokemon, slot: PCSlot) -> some View {
        let party = store.state.partyIDs
        let isBuddy = mon.id == store.state.buddyID
        Button("Summary", systemImage: "info.circle") { open = mon.id }
        switch slot {
        case .party(let i):
            if isBuddy {
                Label("\(mon.name) is your buddy", systemImage: "star.fill")
            } else {
                Button("Make lead buddy", systemImage: "figure.walk") { Task { await store.setBuddy(mon.id) } }
                if party.count > 1, let free = firstFreeBoxSlot {
                    Button("Put in box", systemImage: "tray.and.arrow.down") { store.move(from: .party(i), to: free) }
                }
            }
        case .box:
            if party.count < 6 {
                Button("Add to party", systemImage: "person.badge.plus") { store.move(from: slot, to: .party(party.count)) }
            } else {
                Menu {
                    ForEach(Array(party.enumerated()), id: \.element) { idx, pid in
                        if pid != store.state.buddyID, let p = store.state.mon(pid) {
                            Button("\(p.name) · Lv \(p.level)") { store.move(from: slot, to: .party(idx)) }
                        }
                    }
                } label: {
                    Label("Add to party (swap…)", systemImage: "arrow.left.arrow.right")
                }
            }
            Button("Send to Storage", systemImage: "shippingbox") {
                if store.sendToStorage(mon.id) { store.toast = "\(mon.name) was sent to Storage." }
            }
        }
        Button("Move", systemImage: "hand.point.up.left") { moving = true; held = slot }
        if !isBuddy {
            Divider()
            Button("Release", systemImage: "leaf", role: .destructive) { releasing = mon }
        }
    }

    private var firstFreeBoxSlot: PCSlot? {
        for (b, box) in store.state.boxes.enumerated() {
            if let i = box.slots.firstIndex(where: { $0 == nil }) { return .box(b, i) }
        }
        return nil
    }

    /// Swipe order in the Summary: your party, then the box you're looking at.
    private func browseOrder(startingNear id: UUID) -> [UUID] {
        let party = store.state.partyIDs
        let box = boxIndex < store.state.boxes.count ? store.state.boxes[boxIndex].slots.compactMap { $0 } : []
        var ids = party + box.filter { !party.contains($0) }
        if !ids.contains(id) { ids = [id] }
        return ids
    }

    private func tap(slot: PCSlot, id: UUID?) {
        guard moving else { if let id { open = id }; return }
        if let from = held {
            withAnimation(.spring(duration: 0.3)) { store.move(from: from, to: slot) }
            held = nil
        } else if id != nil {
            held = slot
        }
    }

    // MARK: Search

    private var searchResults: some View {
        let q = search.lowercased()
        let hits = store.state.pokemon.filter {
            $0.name.lowercased().contains(q) || $0.species.name.lowercased().contains(q)
                || ($0.metLocation?.placeName?.lowercased().contains(q) ?? false)
        }
        return VStack(spacing: 8) {
            ForEach(hits) { mon in
                Button { open = mon.id } label: {
                    HStack(spacing: 12) {
                        AnimatedSprite(speciesID: mon.speciesID, kind: .icons).frame(width: 44, height: 34)
                        VStack(alignment: .leading) {
                            Text("\(mon.name)  Lv \(mon.level)").font(.rounded(15, .heavy))
                            Text(store.state.locationText(of: mon.id)).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                    }
                    .cardStyle()
                }
                .buttonStyle(.plain)
            }
            if hits.isEmpty { Text("No matches").foregroundStyle(Theme.inkSoft) }
        }
    }
}
