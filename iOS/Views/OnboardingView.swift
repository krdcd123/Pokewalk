import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: GameStore
    @State private var trainerName = ""
    @State private var starter: Int?
    @State private var nickname = ""
    @State private var starting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Walk with your Apple Watch to level up your buddy, find a wild Pokémon (Gen 1–3) about every 500 steps, and earn a ball every 100.")
                        .font(.rounded(15)).foregroundStyle(Theme.inkSoft)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR NAME").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                        TextField("Trainer", text: $trainerName)
                            .font(.rounded(18)).padding(.horizontal, 14).frame(height: 50)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .textInputAutocapitalization(.words)
                    }

                    Text("CHOOSE YOUR PARTNER").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                        ForEach(Dex.starterChoices, id: \.self) { id in
                            let sp = Dex.species(id)
                            Button { starter = id } label: {
                                VStack(spacing: 4) {
                                    AnimatedSprite(speciesID: id).frame(width: 72, height: 72)
                                    Text(sp.name).font(.rounded(14, .heavy)).foregroundStyle(Theme.ink)
                                    TypeChip(type: sp.primaryType)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(starter == id ? Color(sp.primaryType).opacity(0.2) : .white, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(starter == id ? Color(sp.primaryType) : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let starter {
                        TextField("Nickname for \(Dex.species(starter).name) (optional)", text: $nickname)
                            .font(.rounded(16)).padding(.horizontal, 14).frame(height: 48)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        Button {
                            starting = true
                            Task {
                                await store.newGame(trainerName: trainerName, starter: starter,
                                                    nickname: nickname.isEmpty ? nil : nickname)
                            }
                        } label: {
                            Text(starting ? "Getting ready…" : "Start walking")
                                .font(.rounded(18, .black)).frame(maxWidth: .infinity).frame(height: 56)
                                .background(Theme.ink, in: Capsule()).foregroundStyle(.white)
                        }
                        .disabled(starting)
                    }

                    Text("PokéWalk asks for Health (steps), Motion, Location and Notifications. Choose \"Allow While Using\" then \"Change to Always Allow\" for location so encounters work with the phone in your pocket.")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                }
                .padding()
            }
            .background(Theme.ground)
            .navigationTitle("Welcome to PokéWalk")
        }
    }
}

struct EvolutionView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let candidate: GameStore.EvolutionCandidate

    @State private var stage = 0
    @State private var flash = false
    @State private var originalName: String?

    private var mon: OwnedPokemon? { store.state.mon(candidate.pokemonID) }

    var body: some View {
        let oldName = originalName ?? mon?.name ?? "?"
        let newSpecies = Dex.species(candidate.into)
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                ZStack {
                    if stage < 2, let mon {
                        AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny).opacity(flash ? 0 : 1)
                    }
                    AnimatedSprite(speciesID: candidate.into, shiny: mon?.isShiny ?? false)
                        .opacity(stage == 2 ? 1 : (flash ? 1 : 0))
                }
                .frame(width: 220, height: 220)
                .brightness(stage == 1 ? 0.9 : 0)
                .scaleEffect(stage == 2 ? 1.1 : 1)

                Text(stage < 2 ? "What? \(oldName) is evolving!" : "Congratulations! Your \(oldName) evolved into \(newSpecies.name)!")
                    .font(.rounded(20, .black)).foregroundStyle(.white).multilineTextAlignment(.center).padding()
                Spacer()
                if stage == 0 {
                    HStack(spacing: 16) {
                        Button("Stop (B)") { store.declineEvolution(candidate); dismiss() }
                            .buttonStyle(.bordered).tint(.white)
                        Button("Evolve!") { run() }.buttonStyle(.borderedProminent).tint(Theme.teal)
                    }
                } else if stage == 2 {
                    Button("Continue") { dismiss() }.buttonStyle(.borderedProminent).tint(Theme.teal)
                }
            }
            .padding()
        }
        .onAppear { if originalName == nil { originalName = mon?.name } }
    }

    private func run() {
        stage = 1
        Task {
            for i in 0..<14 {
                withAnimation(.easeInOut(duration: 0.18)) { flash.toggle() }
                try? await Task.sleep(for: .milliseconds(max(70, 260 - i * 15)))
            }
            store.evolve(candidate)
            withAnimation(.spring(duration: 0.6)) { stage = 2 }
        }
    }
}
