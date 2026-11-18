import SwiftUI
import MapKit

struct MapHomeView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var tracker: LocationTracker
    @EnvironmentObject private var tracks: TrackStore

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var sheet: HomeSheet?
    @State private var showCard = false

    enum HomeSheet: String, Identifiable { case menu, encounters; var id: String { rawValue } }

    private var caughtToday: [OwnedPokemon] {
        store.state.pokemon.filter { Calendar.current.isDateInToday($0.metDate) && $0.metLocation != nil && $0.metNote == nil }
    }

    var body: some View {
        ZStack {
            ZStack {
                map
                VStack(spacing: 10) {
                    topCards
                    if let toast = store.toast { toastView(toast) }
                    Spacer()
                    bottomBar
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .blur(radius: showCard ? 16 : 0)
            .allowsHitTesting(!showCard)

            if showCard {
                // Trainer card pops up over the blurred map; tap anywhere outside to close.
                Color.black.opacity(0.25).ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(duration: 0.35)) { showCard = false } }
                TrainerCardView(popup: true)
                    .padding(.horizontal, 14)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .onTapGesture { withAnimation(.spring(duration: 0.35)) { showCard = false } }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .menu: MainMenuView()
            case .encounters: EncounterListView(open: { enc in sheet = nil; open(enc) })
                    .presentationDetents([.medium, .large])
            }
        }
        .fullScreenCover(item: $store.activeEncounter) { SafariView(wild: $0) }
        .animation(.spring(duration: 0.4), value: store.toast)
    }

    private func open(_ enc: PendingEncounter) {
        Task { try? await Task.sleep(for: .milliseconds(350)); store.activeEncounter = enc }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            ForEach(Array(tracks.today.enumerated()), id: \.offset) { _, seg in
                if seg.count > 1 {
                    MapPolyline(coordinates: seg.map(\.coordinate)).stroke(.white, lineWidth: 10)
                    MapPolyline(coordinates: seg.map(\.coordinate)).stroke(Theme.route, lineWidth: 5)
                }
            }
            ForEach(caughtToday) { mon in
                Annotation(mon.name, coordinate: CLLocationCoordinate2D(latitude: mon.metLocation!.latitude,
                                                                        longitude: mon.metLocation!.longitude)) {
                    MapPin(speciesID: mon.speciesID, ring: Theme.orange)
                }.annotationTitles(.hidden)
            }
            ForEach(store.state.pending.filter { $0.location != nil }) { enc in
                Annotation("Wild \(enc.species.name)", coordinate: CLLocationCoordinate2D(latitude: enc.location!.latitude,
                                                                                          longitude: enc.location!.longitude)) {
                    Button { open(enc) } label: { MapPin(speciesID: enc.speciesID, ring: Theme.teal, wild: true) }
                }.annotationTitles(.hidden)
            }
            if let loc = tracker.lastLocation {
                Annotation("You", coordinate: loc.coordinate, anchor: .bottom) {
                    BuddyMarker(speciesID: store.state.buddy?.speciesID, shiny: store.state.buddy?.isShiny ?? false)
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .ignoresSafeArea()
    }

    // MARK: Overlays

    private var topCards: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                card {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY").font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(store.stepsToday.formatted()).font(.rounded(22, .black))
                            Text("steps").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                        }
                        Text(String(format: "%.1f km walked", store.metersToday / 1000))
                            .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                card {
                    HStack(spacing: 10) {
                        ItemSprite(key: BallKind.poke.itemKey).frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("×\(store.state.totalBalls)").font(.rounded(22, .black))
                            Text("balls").font(.rounded(11)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                .frame(width: 120)
            }
            card {
                VStack(spacing: 6) {
                    let c = store.state.counters
                    HStack {
                        Text("Next encounter").font(.rounded(13, .heavy))
                        Spacer()
                        Text("\(c.encounterProgress.formatted()) / \(c.nextEncounterAt.formatted()) steps")
                            .font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
                    }
                    ExpBar(progress: Double(c.encounterProgress) / Double(max(1, c.nextEncounterAt)), tint: Theme.teal, height: 8)
                    HStack {
                        Text("Next ball in \(max(0, store.state.settings.ballSteps - c.ballProgress)) steps")
                        Spacer()
                        trackingLabel
                    }
                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder private var trackingLabel: some View {
        if tracker.isRunning {
            Label("Tracking on", systemImage: "location.fill").labelStyle(.titleAndIcon)
        } else {
            Label("Tracking off", systemImage: "location.slash").labelStyle(.titleAndIcon)
        }
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.rounded(14, .heavy))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(.white)
            .glassCapsule(tint: Theme.teal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { store.toast = nil }
            .task(id: text) {
                try? await Task.sleep(for: .seconds(4))
                if store.toast == text { store.toast = nil }
            }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if store.state.settings.trackingMode == .walks {
                Button {
                    tracker.walkStartedAt == nil ? store.startWalk() : store.endWalk()
                } label: {
                    Label(tracker.walkStartedAt == nil ? "Start a walk" : "End walk",
                          systemImage: tracker.walkStartedAt == nil ? "figure.walk" : "stop.fill")
                        .font(.rounded(15, .heavy))
                        .padding(.horizontal, 18).frame(height: 44)
                        .foregroundStyle(.white)
                        .glassCapsule(interactive: true)
                }
            }
            HStack(alignment: .bottom) {
                Button { withAnimation(.spring(duration: 0.35)) { showCard = true } } label: {
                    // Your trainer's small overworld sprite, walking on the spot.
                    TrainerSprite(style: store.state.trainer.style, pose: .walk)
                        .frame(width: 34, height: 46)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                        .glassCircle(tint: Theme.teal)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Trainer card")

                Spacer()

                Button { sheet = .menu } label: {
                    BallOutline(lineWidth: 3.5)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .frame(width: 80, height: 80)
                        .contentShape(Circle())          // the whole circle is tappable, not just the outline
                        .glassCircle(tint: Color(hex: 0xE04A3F))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Main menu")

                Spacer()

                Button { sheet = .encounters } label: {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                        .glassCircle(tint: Theme.orange)
                        .overlay(alignment: .topTrailing) {
                            if !store.state.pending.isEmpty {
                                Text("\(store.state.pending.count)")
                                    .font(.rounded(12, .black)).foregroundStyle(.white)
                                    .frame(minWidth: 22, minHeight: 22)
                                    .background(Color(hex: 0xD63B3B), in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wild Pokémon waiting: \(store.state.pending.count)")
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassCard(20)
    }
}

struct MapPin: View {
    let speciesID: Int
    var ring: Color
    var wild = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(.white)
                AnimatedSprite(speciesID: speciesID, kind: .icons).padding(5)
            }
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(ring, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                if wild {
                    Text("!").font(.rounded(12, .black)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Theme.teal, in: Circle())
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            Rectangle().fill(ring).frame(width: 3, height: 10)
        }
    }
}

/// Your walking buddy's icon in a small circle at your location.
/// Takes plain values: map annotation content doesn't reliably receive environment objects.
struct BuddyMarker: View {
    let speciesID: Int?
    var shiny = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(.white)
                if let speciesID { AnimatedSprite(speciesID: speciesID, kind: .icons).padding(6) }
            }
            .frame(width: 52, height: 52)
            .overlay(Circle().stroke(Theme.orange, lineWidth: 4))
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            Rectangle().fill(Theme.orange).frame(width: 3, height: 10)
            Circle().fill(Theme.route).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2.5))
        }
    }
}

// MARK: - Pending encounters

struct EncounterListView: View {
    @EnvironmentObject private var store: GameStore
    let open: (PendingEncounter) -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.state.pending.isEmpty {
                    ContentUnavailableView("No wild Pokémon yet", systemImage: "leaf",
                                           description: Text("One appears about every \(store.state.settings.encounterSteps) steps. Keep walking!"))
                        .listRowBackground(Color.clear)
                }
                ForEach(store.state.pending.reversed()) { enc in
                    Button { open(enc) } label: {
                        HStack(spacing: 12) {
                            AnimatedSprite(speciesID: enc.speciesID, kind: .icons).frame(width: 48, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(enc.species.name)\(enc.isShiny ? " ✨" : "")  Lv. \(enc.level)")
                                    .font(.rounded(16, .heavy)).foregroundStyle(Theme.ink)
                                Text(enc.location?.placeName ?? "Somewhere on your walk")
                                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            Text(enc.expiresAt, style: .relative)
                                .font(.rounded(11)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.trailing)
                        }
                    }
                    .glassRow()
                }
            }
            .navigationTitle("Wild Pokémon")
            .navigationBarTitleDisplayMode(.inline)
            .glassScreen()
        }
    }
}
