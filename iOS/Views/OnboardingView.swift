import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: GameStore
    @State private var trainerName = ""
    @State private var look: String?
    @State private var starter: Int?
    @State private var nickname = ""
    @State private var starting = false
    /// Rolled fresh every time this page opens (each New Game), 1 in 4096 per starter.
    @State private var shinies = GameRules.rollStarterShinies()
    @State private var resets = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Walk with your Apple Watch to level up your buddy, find a wild Pokémon (Gen 1–3) about every 500 steps, and earn a ball every 1,000.")
                        .font(.rounded(15)).foregroundStyle(Theme.inkSoft)

                    Text("ARE YOU…").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(TrainerStyle.all) { t in
                            let chosen = look == t.id
                            Button { withAnimation(.spring) { look = t.id } } label: {
                                VStack(spacing: 4) {
                                    TrainerSprite(style: t, pose: .walk).frame(width: 70, height: 80)
                                    Text(t.name).font(.rounded(14, .heavy))
                                    Text(t.game).font(.rounded(9, .heavy)).foregroundStyle(Theme.inkSoft)
                                        .lineLimit(2).multilineTextAlignment(.center).frame(height: 24)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .glassCard(18, tint: chosen ? Color(hex: t.cardHex) : nil)
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(chosen ? Color(hex: t.cardHex) : .clear, lineWidth: 3))
                                .scaleEffect(chosen ? 1.04 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR NAME").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                        TextField("", text: $trainerName, prompt: Text(look.map { TrainerStyle.style($0).name } ?? "Trainer")
                            .foregroundStyle(Theme.inkSoft))
                            .font(.rounded(18)).padding(.horizontal, 14).frame(height: 50)
                            .glassCard(14)
                            .textInputAutocapitalization(.words)
                    }

                    HStack {
                        Text("CHOOSE YOUR PARTNER").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        // Shiny hunting: re-roll every starter (1 in 8192 each), like soft-resetting.
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring) {
                                shinies = GameRules.rollStarterShinies()
                                resets += 1
                            }
                        } label: {
                            Label(resets == 0 ? "Reset" : "Reset · \(resets)", systemImage: "arrow.clockwise")
                                .font(.rounded(13, .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(height: 32)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if !shinies.isEmpty {
                        Text("✨ A shiny partner appeared! ✨").font(.rounded(14, .black))
                            .foregroundStyle(Color(hex: 0xFFD54A))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                        ForEach(Dex.starterChoices, id: \.self) { id in
                            let sp = Dex.species(id)
                            let shiny = shinies.contains(id)
                            Button { withAnimation(.spring) { starter = id } } label: {
                                VStack(spacing: 4) {
                                    AnimatedSprite(speciesID: id, shiny: shiny).frame(width: 72, height: 72)
                                        .overlay(alignment: .topTrailing) {
                                            if shiny {
                                                Image(systemName: "sparkles").font(.system(size: 16, weight: .black))
                                                    .foregroundStyle(Color(hex: 0xFFD54A))
                                                    .symbolEffect(.pulse, options: .repeating)
                                            }
                                        }
                                    Text(sp.name + (shiny ? " ✨" : "")).font(.rounded(14, .heavy))
                                    TypeChip(type: sp.primaryType)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .glassCard(18, tint: starter == id ? Color(sp.primaryType) : nil)
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(starter == id ? Color(sp.primaryType) : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let starter {
                        TextField("", text: $nickname, prompt: Text("Nickname for \(Dex.species(starter).name) (optional)")
                            .foregroundStyle(Theme.inkSoft))
                            .font(.rounded(16)).padding(.horizontal, 14).frame(height: 48)
                            .glassCard(14)
                        GlassButton(title: starting ? "Getting ready…" : "Start walking", symbol: "figure.walk") {
                            guard !starting else { return }
                            starting = true
                            let name = trainerName.isEmpty ? TrainerStyle.style(look).name : trainerName
                            Task {
                                await store.newGame(trainerName: name, appearance: look ?? TrainerStyle.all[4].id,
                                                    starter: starter, nickname: nickname.isEmpty ? nil : nickname,
                                                    shiny: shinies.contains(starter))
                            }
                        }
                        .disabled(look == nil)
                        .opacity(look == nil ? 0.5 : 1)
                        if look == nil {
                            Text("Pick your trainer above first.").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }

                    Text("PokéWalk asks for Health (steps), Motion, Location and Notifications. Choose \"Allow While Using\" then \"Change to Always Allow\" for location so encounters work with the phone in your pocket.")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                }
                .padding()
            }
            .navigationTitle("Welcome to PokéWalk")
            .glassScreen()
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
    @State private var stopped = false

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

                Text(stopped ? "Huh? \(oldName) stopped evolving!"
                     : stage == 0 ? "\(oldName) is ready to evolve into \(newSpecies.name)!"
                     : stage == 1 ? "What? \(oldName) is evolving!"
                     : "Congratulations! Your \(oldName) evolved into \(newSpecies.name)!")
                    .font(.rounded(20, .black)).foregroundStyle(.white).multilineTextAlignment(.center).padding()
                Spacer()
                if stopped {
                    Button("Continue") { dismiss() }.buttonStyle(.borderedProminent).tint(Theme.teal)
                } else if stage == 0 {
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Button("Not now") { store.declineEvolution(candidate); dismiss() }
                                .buttonStyle(.bordered).tint(.white)
                            Button("Evolve!") { run() }.buttonStyle(.borderedProminent).tint(Theme.teal)
                        }
                        Text("You can evolve it any time from its Summary.")
                            .font(.rounded(13, .heavy)).foregroundStyle(.white.opacity(0.6))
                    }
                } else if stage == 1 {
                    Button("Stop (B)") { stopped = true; store.declineEvolution(candidate) }
                        .buttonStyle(.bordered).tint(.white)
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
                if stopped { withAnimation { flash = false; stage = 0 }; return }
                withAnimation(.easeInOut(duration: 0.18)) { flash.toggle() }
                try? await Task.sleep(for: .milliseconds(max(70, 260 - i * 15)))
            }
            if stopped { withAnimation { flash = false; stage = 0 }; return }
            store.evolve(candidate)
            withAnimation(.spring(duration: 0.6)) { stage = 2 }
        }
    }
}
