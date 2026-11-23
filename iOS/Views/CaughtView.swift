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
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)

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
            .background(LocationBackdrop(fallback: mon.metLocation))
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
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let met = mon.metLocation {
                let coord = CLLocationCoordinate2D(latitude: met.latitude, longitude: met.longitude)
                Map(initialPosition: .camera(MapCamera(centerCoordinate: coord, distance: 900))) {
                    Annotation(mon.name, coordinate: coord) {
                        MapPin(speciesID: mon.speciesID, ring: Theme.orange, shiny: mon.isShiny)
                    }.annotationTitles(.hidden)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .allowsHitTesting(false)
                .frame(height: 140)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold)).padding(7)
                        .background(.ultraThinMaterial, in: Circle()).padding(8)
                }
                .contentShape(Rectangle())
                .onTapGesture { expanded = true }
                .fullScreenCover(isPresented: $expanded) { MetMapFull(mon: mon, coord: coord) }
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


/// The place you met a Pokémon, full screen: pinch to zoom, drag around, switch to satellite.
struct MetMapFull: View {
    let mon: OwnedPokemon
    let coord: CLLocationCoordinate2D
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var satellite = false

    init(mon: OwnedPokemon, coord: CLLocationCoordinate2D) {
        self.mon = mon
        self.coord = coord
        _position = State(initialValue: .camera(MapCamera(centerCoordinate: coord, distance: 500)))
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                Annotation(mon.name, coordinate: coord) {
                    MapPin(speciesID: mon.speciesID, ring: Theme.orange, shiny: mon.isShiny)
                }.annotationTitles(.hidden)
            }
            .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
            .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(mon.metLocation?.displayName ?? "Where you met")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { position = .camera(MapCamera(centerCoordinate: coord, distance: 500)) }
                    } label: { Image(systemName: "scope") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Picker("Map", selection: $satellite) {
                        Text("Map").tag(false); Text("Satellite").tag(true)
                    }
                    .pickerStyle(.segmented).frame(width: 220)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
