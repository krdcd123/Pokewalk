import SwiftUI

/// A Pokédex page like the games: category, height/weight, entry text, abilities, base stats, breeding,
/// evolution line — plus every one you've caught, swipeable, with where you met it.
struct DexEntryView: View {
    @EnvironmentObject private var store: GameStore
    let species: Species
    @State private var info: DexInfo?
    @State private var loading = true
    @State private var page = 0
    @State private var showShiny = false

    /// You have a shiny one of this species.
    private var hasShiny: Bool { store.state.pokemon.contains { $0.speciesID == species.id && $0.isShiny } }

    private var caught: Bool { store.state.dexCaught.contains(species.id) }
    private var yours: [OwnedPokemon] {
        store.state.pokemon.filter { $0.speciesID == species.id }.sorted { $0.metDate < $1.metDate }
    }
    private var tint: Color { Color(species.primaryType) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if caught {
                    entryCard
                    statsCard
                    detailsCard
                } else {
                    Text("Catch one to complete its Pokédex entry.")
                        .font(.rounded(14, .heavy)).foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity).padding().glassCard(18)
                }
                evolutionCard
                if !yours.isEmpty { yoursCard }
            }
            .padding()
        }
        .background(LinearGradient(stops: [.init(color: tint.opacity(0), location: 0),
                                           .init(color: tint.opacity(0.35), location: 0.12),
                                           .init(color: tint.opacity(0.08), location: 0.5),
                                           .init(color: .clear, location: 0.8)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationTitle(caught ? species.name : "???")
        .navigationBarTitleDisplayMode(.inline)
        .glassScreen()
        .task {
            info = await DexInfoService.shared.info(for: species.id)
            loading = false
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 6) {
            AnimatedSprite(speciesID: species.id, shiny: showShiny).frame(width: 130, height: 130)
                .id(showShiny)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .brightness(caught ? 0 : -1).opacity(caught ? 1 : 0.8)      // silhouette until caught
                .contentShape(Rectangle())
                .onTapGesture { CryPlayer.shared.play(species.id) }
                .overlay(alignment: .topTrailing) {
                    if hasShiny {
                        Button {
                            withAnimation(.spring(duration: 0.35)) { showShiny.toggle() }
                            if showShiny { SoundKit.shared.play(.shiny) }
                        } label: {
                            Image(systemName: showShiny ? "sparkles" : "sparkle")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(showShiny ? Color(hex: 0xFFD54A) : .white)
                                .frame(width: 38, height: 38)
                                .glassCircle(tint: showShiny ? Color(hex: 0xFFD54A).opacity(0.5) : nil)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 40, y: 4)
                        .accessibilityLabel(showShiny ? "Show normal colours" : "Show shiny colours")
                    }
                }
            Text(species.dexNumber).font(.rounded(14, .heavy)).foregroundStyle(Theme.inkSoft)
            Text(caught ? species.name : "???").font(.rounded(30, .black))
            if caught, let g = info?.genus, !g.isEmpty {
                Text(g).font(.rounded(15, .heavy)).foregroundStyle(.white.opacity(0.8))
            }
            if caught { HStack { ForEach(species.types, id: \.self) { TypeChip(type: $0) } } }
            if caught, let i = info {
                HStack(spacing: 10) {
                    pill("HT", height(i.heightDm))
                    pill("WT", weight(i.weightHg))
                }
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let i = info, !i.flavor.isEmpty {
                Text(i.flavor).font(.rounded(16, .heavy)).fixedSize(horizontal: false, vertical: true)
                if !i.flavorVersion.isEmpty {
                    Text("Pokémon \(i.flavorVersion)").font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft)
                }
            } else {
                Text(loading ? "Loading Pokédex entry…" : "Pokédex entry needs an internet connection the first time.")
                    .font(.rounded(14)).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).glassCard(20)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BASE STATS").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
            if let s = info?.stats, s.count == 6 {
                ForEach(Array(zip(["HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed"], s)), id: \.0) { label, v in
                    HStack(spacing: 10) {
                        Text(label).font(.rounded(13, .heavy)).frame(width: 64, alignment: .leading)
                        Text("\(v)").font(.rounded(13, .heavy)).monospacedDigit().frame(width: 32, alignment: .trailing)
                        GeometryReader { g in
                            Capsule().fill(.white.opacity(0.1))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(statColour(v)).frame(width: g.size.width * min(1, CGFloat(v) / 180))
                                }
                        }
                        .frame(height: 8)
                    }
                }
                HStack {
                    Text("Total").font(.rounded(13, .black))
                    Spacer()
                    Text("\(s.reduce(0, +))").font(.rounded(13, .black))
                }
            } else {
                Text(loading ? "Loading…" : "—").font(.rounded(13)).foregroundStyle(Theme.inkSoft)
            }
        }
        .foregroundStyle(.white)
        .padding(16).glassCard(20)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            if let i = info {
                row("Abilities", i.abilities.joined(separator: " / "))
                if let h = i.hiddenAbility { row("Hidden ability", h) }
                if let h = i.habitat { row("Habitat", h) }
                if !i.eggGroups.isEmpty { row("Egg groups", i.eggGroups.joined(separator: ", ")) }
                if let c = i.colour { row("Colour", c) }
            }
            row("Gender", gender)
            row("Catch rate", "\(species.captureRate)")
            row("Base friendship", "\(species.baseFriendship)")
            row("Growth", species.growth.rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized)
            row("Found near (PokéWalk)", species.habitats.map(\.displayName).joined(separator: ", "))
        }
        .foregroundStyle(.white)
        .glassCard(20)
    }

    private var evolutionCard: some View {
        let chain = evolutionChain
        return Group {
            if chain.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("EVOLUTION").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(chain.enumerated()), id: \.offset) { idx, step in
                                if idx > 0 {
                                    VStack(spacing: 2) {
                                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                                        Text(step.how).font(.rounded(9, .heavy)).foregroundStyle(Theme.inkSoft)
                                            .multilineTextAlignment(.center).frame(width: 64)
                                    }
                                }
                                let seen = store.state.dexSeen.contains(step.id)
                                let got = store.state.dexCaught.contains(step.id)
                                VStack(spacing: 2) {
                                    if seen {
                                        AnimatedSprite(speciesID: step.id, kind: .icons).frame(width: 44, height: 38)
                                            .brightness(got ? 0 : -1)
                                    } else {
                                        Image(systemName: "questionmark").frame(width: 44, height: 38).foregroundStyle(Theme.inkSoft)
                                    }
                                    Text(got ? Dex.species(step.id).name : "???").font(.rounded(11, .heavy))
                                }
                                .padding(6)
                                .background(.white.opacity(step.id == species.id ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(16).glassCard(20)
            }
        }
    }

    private var yoursCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(yours.count == 1 ? "YOUR \(species.name.uppercased())" : "YOUR \(species.name.uppercased()) · \(page + 1) OF \(yours.count)")
                    .font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                Spacer()
                if yours.count > 1 {
                    Text("Swipe").font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft)
                }
            }
            TabView(selection: $page) {
                ForEach(Array(yours.enumerated()), id: \.element.id) { idx, mon in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny, kind: .icons).frame(width: 34, height: 28)
                            Text(mon.name + (mon.isShiny ? " ✨" : "")).font(.rounded(15, .heavy))
                            Text("Lv \(mon.level)").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                        }
                        MetCard(mon: mon)
                    }
                    .tag(idx)
                    .padding(.bottom, yours.count > 1 ? 28 : 0)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: yours.count > 1 ? .always : .never))
            .frame(height: yours.count > 1 ? 290 : 262)
        }
        .foregroundStyle(.white)
    }

    // MARK: Helpers

    private struct ChainStep { let id: Int; let how: String }

    /// Whole family, base form first (branches listed one after another).
    private var evolutionChain: [ChainStep] {
        var root = species
        while let from = root.evolvesFrom { root = Dex.species(from) }
        var out = [ChainStep(id: root.id, how: "")]
        var queue = [root]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            for rule in cur.evolutions where !out.contains(where: { $0.id == rule.into }) {
                let how = rule.summary.replacingOccurrences(of: "\(Dex.species(rule.into).name) ", with: "")
                out.append(ChainStep(id: rule.into, how: how))
                queue.append(Dex.species(rule.into))
            }
        }
        return out
    }

    private var gender: String {
        switch species.genderRate {
        case -1: return "Genderless"
        case 0: return "♂ only"
        case 8: return "♀ only"
        default:
            let f = Double(species.genderRate) / 8 * 100
            return "♂ \(Int(100 - f))% · ♀ \(Int(f))%"
        }
    }

    private func height(_ dm: Int) -> String {
        let inches = Int((Double(dm) * 3.937).rounded())
        return "\(inches / 12)′\(String(format: "%02d", inches % 12))″"
    }
    private func weight(_ hg: Int) -> String { String(format: "%.1f lbs", Double(hg) * 0.220462) }

    private func statColour(_ v: Int) -> Color {
        v < 50 ? Color(hex: 0xF08030) : v < 80 ? Color(hex: 0xF8D030) : v < 110 ? Color(hex: 0x78C850) : Color(hex: 0x6890F0)
    }

    private func pill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.rounded(11, .black)).foregroundStyle(Theme.inkSoft)
            Text(value).font(.rounded(14, .heavy))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .glassCard(14)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.rounded(13, .heavy)).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 12)
            Text(value).font(.rounded(13, .heavy)).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
