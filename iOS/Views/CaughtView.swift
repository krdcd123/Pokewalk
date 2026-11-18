import SwiftUI
import MapKit

struct CaughtView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let pokemonID: UUID
    let safari: SafariEncounter
    @State private var nickname = ""

    private var mon: OwnedPokemon? { store.state.mon(pokemonID) }

    var body: some View {
        if let mon {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Text("GOTCHA!").font(.rounded(14, .heavy)).foregroundStyle(.white.opacity(0.85))
                        AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny).frame(width: 150, height: 150)
                        Text("\(mon.species.name) was caught!").font(.rounded(26, .black)).foregroundStyle(.white)
                        if mon.isShiny { Text("✨ Shiny!").font(.rounded(15, .heavy)).foregroundStyle(.yellow) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60).padding(.bottom, 24)
                    .background(LinearGradient(colors: [Theme.teal, Theme.tealDark], startPoint: .top, endPoint: .bottom))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("GIVE IT A NICKNAME?").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                        TextField(mon.species.name, text: $nickname)
                            .font(.rounded(17)).padding(.horizontal, 12).frame(height: 46)
                            .glassCard(12)
                            .submitLabel(.done)
                    }
                    .cardStyle()
                    .padding(.horizontal)

                    MetCard(mon: mon).padding(.horizontal)

                    HStack(spacing: 10) {
                        stat("\(safari.throwCount)", safari.throwCount == 1 ? "throw" : "throws")
                        stat(mon.ball.name, "caught in")
                        stat(store.state.partyIDs.contains(mon.id) ? "Party" : "PC", "sent to")
                    }
                    .padding(.horizontal)

                    GlassButton(title: "OK") {
                        if !nickname.isEmpty { store.rename(mon.id, to: nickname) }
                        dismiss()
                    }
                    .padding(.horizontal).padding(.bottom, 30)
                }
            }
            .background(AppBackground())
            .scrollContentBackground(.hidden)
            .ignoresSafeArea(edges: .top)
            .foregroundStyle(Theme.ink)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.rounded(17, .black)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.rounded(11)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .glassCard(14)
    }
}

/// Mini map + "Met at …" line, used on the caught screen and the summary.
struct MetCard: View {
    let mon: OwnedPokemon

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let met = mon.metLocation {
                let coord = CLLocationCoordinate2D(latitude: met.latitude, longitude: met.longitude)
                Map(initialPosition: .camera(MapCamera(centerCoordinate: coord, distance: 900))) {
                    Annotation(mon.name, coordinate: coord) {
                        MapPin(speciesID: mon.speciesID, ring: Theme.orange)
                    }.annotationTitles(.hidden)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .allowsHitTesting(false)
                .frame(height: 140)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(mon.metLocation.map { "Met at \($0.displayName)" } ?? (mon.metNote ?? "Met on your travels"))
                    .font(.rounded(16, .black))
                Text("\(mon.metDate.formatted(date: .abbreviated, time: .shortened)) · Met at Lv \(mon.metLevel) · \(mon.ball.name)")
                    .font(.rounded(13)).foregroundStyle(Theme.inkSoft)
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .glassCard(20)
    }
}
