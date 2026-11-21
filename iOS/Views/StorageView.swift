import SwiftUI

/// Storage: a box shared by every game on this phone. Starting a New Game (e.g. to reset for a shiny
/// starter) keeps everything in here. Move Pokémon in from your PC boxes, and back out into any game.
struct StorageView: View {
    @EnvironmentObject private var store: GameStore
    @State private var tab = 0
    @State private var picked: OwnedPokemon?

    private var boxed: [OwnedPokemon] {
        let party = Set(store.state.partyIDs)
        let order = store.state.boxes.flatMap { $0.slots.compactMap { $0 } }
        return order.compactMap { id in party.contains(id) ? nil : store.state.mon(id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $tab) {
                    Text("Storage (\(store.storage.count))").tag(0)
                    Text("Your PC boxes (\(boxed.count))").tag(1)
                }
                .pickerStyle(.segmented)

                Text(tab == 0
                     ? "Kept on this phone when you start a New Game. Tap one to move it into this game's PC."
                     : "Tap a Pokémon to send it to Storage. Party Pokémon have to be put in a box first.")
                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft)

                let list = tab == 0 ? store.storage : boxed
                if list.isEmpty {
                    Text(tab == 0 ? "Storage is empty." : "No Pokémon in your boxes.")
                        .font(.rounded(14, .heavy)).foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(list) { mon in
                            Button { picked = mon } label: {
                                VStack(spacing: 2) {
                                    AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny, kind: .icons).frame(width: 46, height: 40)
                                    Text(mon.name + (mon.isShiny ? "✨" : "")).font(.rounded(11, .heavy)).lineLimit(1)
                                    Text("Lv \(mon.level)").font(.rounded(10, .heavy)).foregroundStyle(Theme.inkSoft)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
        .navigationTitle("Storage")
        .glassScreen()
        .confirmationDialog(picked.map { mon in
                                tab == 0 ? "Move \(mon.name) into your PC?" : "Send \(mon.name) to Storage?"
                            } ?? "",
                            isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }),
                            titleVisibility: .visible) {
            if let mon = picked {
                if tab == 0 {
                    Button("Move to PC") {
                        store.takeFromStorage(mon.id)
                        store.toast = "\(mon.name) was moved to your PC."
                    }
                } else {
                    Button("Send to Storage") {
                        if store.sendToStorage(mon.id) { store.toast = "\(mon.name) was sent to Storage." }
                    }
                }
            }
        }
    }
}
