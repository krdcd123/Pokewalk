import SwiftUI
import MapKit

struct MapHomeView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var tracker: LocationTracker
    @EnvironmentObject private var tracks: TrackStore
    @StateObject private var walking = WalkingDetector.shared

    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var refollowTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    /// We follow you ourselves (instead of MapKit's .userLocation, which resets the zoom every time),
    /// so the map keeps whatever zoom you chose when menus close or you come back to the app.
    @State private var following = true
    @AppStorage("mapZoomDistance") private var zoomDistance: Double = 900
    @State private var lastCamera: MapCamera?

    /// Tap the location button / menus close / app reopens: glide back to you at the same zoom.
    private func followMe(distance: Double? = nil, duration: Double = 0.6) {
        refollowTask?.cancel()
        if let distance { zoomDistance = distance }
        following = true
        guard let loc = tracker.currentLocation() else {
            camera = .userLocation(followsHeading: false, fallback: .automatic)
            return
        }
        let cam = MapCamera(centerCoordinate: loc.coordinate, distance: zoomDistance,
                            heading: lastCamera?.heading ?? 0, pitch: lastCamera?.pitch ?? 0)
        withAnimation(.smooth(duration: duration)) { camera = .camera(cam) }
    }

    /// Long-press the location button: zoom out for an overview (long-press again to come back in).
    private func zoomOutOverview() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        followMe(distance: zoomDistance < 3_000 ? max(4_000, zoomDistance * 4) : 900, duration: 0.8)
    }
    @State private var sheet: HomeSheet?
    @State private var showCard = false
    @AppStorage("showCaughtOnMap") private var showCaught = false
    @State private var infoID: UUID?
    @State private var panelSession = 0
    @ObservedObject private var sound = SoundKit.shared
    @ObservedObject private var weather = WeatherService.shared      // new identity each time a panel opens, so menus start at the top

    enum HomeSheet: Hashable, Identifiable {
        case menu, encounters, bag, journal, summary(UUID)
        var id: Self { self }
    }

    /// Every Pokémon you caught on a walk, pinned where you caught it (only while the eye is on).
    private var caughtOnMap: [OwnedPokemon] {
        guard showCaught else { return [] }
        return store.state.pokemon.filter { $0.metLocation != nil && $0.metNote == nil }
    }

    var body: some View {
        ZStack {
            ZStack {
                map
                    .onAppear {
                        SoundKit.shared.setScene(.map)
                        WeatherService.shared.update(for: tracker.currentLocation())
                    }
                VStack(spacing: 10) {
                    topCards
                    if let toast = store.toast { toastView(toast) }
                    HStack(alignment: .top) {
                        if let w = weather.condition {
                            WeatherPill(condition: w, isDay: weather.isDay, temperature: weather.temperature)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Spacer()
                        Button { withAnimation(.snappy) { showCaught.toggle() } } label: {
                            Image(systemName: showCaught ? "eye.fill" : "eye.slash.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 48, height: 48)
                                .contentShape(Circle())
                                .glassCircle(tint: showCaught ? Theme.orange : nil)
                                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showCaught ? "Hide caught Pokémon" : "Show caught Pokémon")
                    }
                    HStack {
                        Spacer()
                        Button {
                            followMe()
                        } label: {
                            Image(systemName: following ? "location.fill" : "location")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .contentShape(Circle())
                                .glassCircle(tint: following ? Theme.teal : nil)
                                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in zoomOutOverview() })
                        .accessibilityLabel("Show my location")
                        .accessibilityHint("Hold to zoom out")
                    }
                    Spacer()
                    bottomBar
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .blur(radius: showCard || sheet != nil || infoID != nil ? 16 : 0)
            .allowsHitTesting(!showCard && sheet == nil && infoID == nil)

            // Menu / Wild Pokémon: our own panel over the live, blurred map (a system sheet dims it to grey)
            if let which = sheet {
                Color.black.opacity(0.2).ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                MapPanel(close: close) {
                    switch which {
                    case .menu: MainMenuView(close: close)
                    case .encounters: EncounterListView(open: { enc in close(); open(enc) })
                    case .bag: NavigationStack { BagView() }
                    case .journal: NavigationStack { JournalView() }
                    case .summary(let id): NavigationStack { SummaryView(pokemonID: id) }
                    }
                }
                .id(panelSession)
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }

            if let id = infoID, let mon = store.state.mon(id) {
                // Tapped a caught Pokémon on the map: where and when you caught it.
                Color.black.opacity(0.25).ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(duration: 0.35)) { infoID = nil } }
                CaughtPinCard(mon: mon) {
                    withAnimation(.spring(duration: 0.35)) { infoID = nil }
                    withAnimation(.spring(duration: 0.4)) { sheet = .summary(mon.id) }
                }
                .padding(.horizontal, 22)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .onAppear { CryPlayer.shared.play(mon.speciesID) }
            }

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
        .fullScreenCover(item: $store.activeEncounter) { SafariView(wild: $0) }
        .animation(.spring(duration: 0.4), value: store.toast)
    }

    private func close() {
        NotificationCenter.default.post(name: .menuPanelClosing, object: nil)
        withAnimation(.spring(duration: 0.4)) { sheet = nil }
        panelSession += 1
    }

    private func open(_ enc: PendingEncounter) {
        Task { try? await Task.sleep(for: .milliseconds(350)); store.activeEncounter = enc }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera) {
            ForEach(Array(tracks.today.enumerated()), id: \.offset) { _, seg in
                if seg.count > 1 {
                    MapPolyline(coordinates: seg.map(\.coordinate)).stroke(.white, lineWidth: 6)
                    MapPolyline(coordinates: seg.map(\.coordinate))
                        .stroke(TrackStore.isDrive(seg) ? Theme.driveRoute : Theme.route, lineWidth: 3)
                }
            }
            ForEach(caughtOnMap) { mon in
                Annotation(mon.name, coordinate: CLLocationCoordinate2D(latitude: mon.metLocation!.latitude,
                                                                        longitude: mon.metLocation!.longitude)) {
                    Button { withAnimation(.spring(duration: 0.35)) { infoID = mon.id } } label: {
                        MapPin(speciesID: mon.speciesID, ring: Theme.orange, shiny: mon.isShiny)
                    }
                    .buttonStyle(.plain)
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
        // Always keep you in view: if you pan away, it glides back to you after a few seconds
        .onMapCameraChange(frequency: .onEnd) { ctx in
            lastCamera = ctx.camera
            zoomDistance = ctx.camera.distance          // pinch-zooming sets the zoom we keep from now on
            // Did you pan away from yourself? Then stop following, and glide back after a few seconds.
            if let me = tracker.currentLocation() {
                let centre = CLLocation(latitude: ctx.camera.centerCoordinate.latitude, longitude: ctx.camera.centerCoordinate.longitude)
                following = centre.distance(from: me) < max(25, ctx.camera.distance * 0.05)
            }
            refollowTask?.cancel()
            guard !following else { return }
            refollowTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                followMe(duration: 0.8)
            }
        }
        // Keep you in the middle as you walk (same zoom)
        .onChange(of: tracker.lastLocation) { _, loc in
            guard following, sheet == nil, let loc else { return }
            let cam = MapCamera(centerCoordinate: loc.coordinate, distance: zoomDistance,
                                heading: lastCamera?.heading ?? 0, pitch: lastCamera?.pitch ?? 0)
            withAnimation(.linear(duration: 0.8)) { camera = .camera(cam) }
        }
        .onChange(of: sheet) { _, now in if now == nil && following { followMe() } }
        .onChange(of: scenePhase) { _, p in if p == .active { followMe() } }
        .onAppear { if tracker.currentLocation() != nil { followMe(duration: 0) } }
        .ignoresSafeArea()
    }

    // MARK: Overlays

    private var musicOffText: String {
        if sound.routeFiles.isEmpty { return "No music added" }
        if !sound.routeMusicOn { return "Sound off" }
        return sound.otherAudioPlaying ? "Your music is on" : "Sound off"
    }

    private var topCards: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { withAnimation(.spring(duration: 0.4)) { sheet = .journal } } label: {
                card {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY").font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(store.stepsToday.formatted()).font(.rounded(22, .black))
                            Text("steps").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                        }
                        Text("\(Distance.text(store.metersToday)) walked")
                            .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Today's journal")

                // Now playing: tap to mute / play the route music
                Button {
                    withAnimation(.snappy) { sound.routeMusicOn.toggle() }
                } label: {
                card {
                    HStack(spacing: 8) {
                        Image(systemName: sound.nowPlaying != nil ? "music.note" : "speaker.slash.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(sound.nowPlaying != nil ? Theme.teal : Theme.inkSoft)
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: sound.nowPlaying != nil)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sound.nowPlaying != nil ? "NOW PLAYING" : "MUSIC").font(.rounded(10, .heavy)).foregroundStyle(Theme.inkSoft)
                            Text(sound.nowPlaying ?? musicOffText)
                                .font(.rounded(13, .heavy)).lineLimit(2).minimumScaleFactor(0.75)
                                .contentTransition(.opacity)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(width: 150)
                .contentShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sound.nowPlaying.map { "Now playing \($0). Tap to mute." } ?? "Music off. Tap to play.")
            }
            .fixedSize(horizontal: false, vertical: true)      // music card matches the steps card's height
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
                Button { SoundKit.shared.play(.trainerCard); withAnimation(.spring(duration: 0.35)) { showCard = true } } label: {
                    // Your trainer's small overworld sprite, walking on the spot.
                    TrainerSprite(style: store.state.trainer.style, pose: walking.isDriving ? .bike : .walk,
                                  animating: walking.isWalking || walking.isDriving)
                        .frame(width: 44, height: 46)
                        .frame(width: 64, height: 64, alignment: .center)
                        .contentShape(Circle())
                        .glassCircle()
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Trainer card")

                Spacer()

                Button { SoundKit.shared.play(.menuOpen); withAnimation(.spring(duration: 0.4)) { sheet = .menu } } label: {
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

                Button { withAnimation(.spring(duration: 0.4)) { sheet = .encounters } } label: {
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
    var shiny = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(.white)
                AnimatedSprite(speciesID: speciesID, shiny: shiny, kind: .icons).padding(5)
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
                // Hops up and down like a party icon in the games.
                // Map pins are rebuilt on every location update, which kills SwiftUI's repeating
                // animations, so drive the hop from the clock instead: two frames, like the games.
                if let speciesID {
                    TimelineView(.periodic(from: .now, by: 0.22)) { tl in
                        let up = Int(tl.date.timeIntervalSinceReferenceDate / 0.22) % 2 == 0
                        AnimatedSprite(speciesID: speciesID, shiny: shiny, kind: .icons).padding(6)
                            .offset(y: up ? -4 : 0)
                    }
                }
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
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            List {
                let live = store.state.pending.filter { $0.expiresAt > now }
                if live.isEmpty {
                    ContentUnavailableView("No wild Pokémon yet", systemImage: "leaf",
                                           description: Text("One appears about every \(store.state.settings.encounterSteps) steps. Keep walking!"))
                        .listRowBackground(Color.clear)
                }
                ForEach(live.reversed()) { enc in
                    Button { open(enc) } label: {
                        HStack(spacing: 12) {
                            AnimatedSprite(speciesID: enc.speciesID, shiny: enc.isShiny, kind: .icons).frame(width: 48, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(enc.species.name)\(enc.isShiny ? " ✨" : "")  Lv. \(enc.level)")
                                    .font(.rounded(16, .heavy)).foregroundStyle(Theme.ink)
                                Text(enc.location?.placeName ?? "Somewhere on your walk")
                                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(timerInterval: now...max(now, enc.expiresAt), countsDown: true, showsHours: true)
                                    .font(.rounded(13, .heavy)).monospacedDigit()
                                    .foregroundStyle(enc.expiresAt.timeIntervalSince(now) < 900 ? Theme.orange : Theme.ink)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70, alignment: .trailing)
                                Text("left").font(.rounded(10)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                    }
                    .glassRow()
                }
            }
            .navigationTitle("Wild Pokémon")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { t in
                now = t
                store.pruneExpiredEncounters()
            }
            .glassScreen(transparent: true)
        }
    }
}


/// A pull-down-to-close panel that floats over the blurred map.
struct MapPanel<Content: View>: View {
    let close: () -> Void
    @ViewBuilder let content: Content
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.5)).frame(width: 40, height: 5)
                .padding(.top, 12).padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { v in
                        // follow the finger 1:1 downwards, resist a little upwards
                        let dy = v.translation.height
                        drag = dy >= 0 ? dy : dy / 6
                    }
                    .onEnded { v in
                        if v.translation.height > 110 || v.predictedEndTranslation.height > 260 {
                            close()                          // slides away from where you let go
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { drag = 0 }
                        }
                    })
            content
                .overMap()
                // Close button at the bottom middle, within thumb reach; content scrolls clear of it.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .contentShape(Circle())
                            .glassCircle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.18), in: UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34))
        .padding(.top, 54)
        .ignoresSafeArea(edges: .bottom)
        .offset(y: drag)
    }
}


/// Pop-up for a caught Pokémon's map pin: sprite, level, where/when you caught it, and who caught it.
struct CaughtPinCard: View {
    let mon: OwnedPokemon
    var openSummary: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny)
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(mon.name + (mon.isShiny ? " ✨" : "")).font(.rounded(24, .black))
                        Text(mon.gender.symbol).font(.rounded(16, .heavy))
                    }
                    if mon.nickname?.isEmpty == false {
                        Text(mon.species.name).font(.rounded(13, .heavy)).foregroundStyle(.white.opacity(0.7))
                    }
                    Text("Lv \(mon.level)").font(.rounded(16, .heavy)).foregroundStyle(Theme.teal)
                    HStack { ForEach(mon.species.types, id: \.self) { TypeChip(type: $0) } }
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                info("mappin.and.ellipse", "Caught at", mon.metLocation?.displayName ?? mon.metNote ?? "Unknown")
                info("calendar", "Caught on", mon.metDate.formatted(date: .abbreviated, time: .shortened))
                info("star.circle", "Met at", "Lv \(mon.metLevel)")
                info("circle.circle", "Ball", mon.ball.name)
                info("person.fill", "OT", "\(mon.otName) · ID \(mon.otIDString)")
                info("figure.walk", "Walked together", Distance.text(mon.metersWalked))
            }
            .glassCard(16)
            Button(action: openSummary) {
                Text("View summary").font(.rounded(16, .heavy))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .glassCapsule(tint: Theme.teal, interactive: true)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(18)
        .glassCard(28)
    }

    private func info(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(Theme.teal)
            Text(label).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .font(.rounded(14, .heavy))
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}


/// Animated weather badge: live conditions where you are, which nudge the wild Pokémon you meet.
struct WeatherPill: View {
    let condition: WeatherCondition
    let isDay: Bool
    let temperature: Double?
    @State private var showInfo = false

    private var symbol: String {
        switch condition {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
                icon
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(temperature.map { "\(Int($0.rounded()))°" } ?? condition.name).font(.rounded(15, .heavy))
                    if showInfo {
                        Text(condition.name).font(.rounded(11, .heavy)).foregroundStyle(.white.opacity(0.8))
                        Text("More " + condition.boostedTypes.map(\.rawValue.capitalized).sorted().joined(separator: ", ") + " types")
                            .font(.rounded(11)).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassCard(18)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onTapGesture {
                withAnimation(.snappy) { showInfo.toggle() }
                if showInfo {
                    Task { try? await Task.sleep(for: .seconds(6)); withAnimation(.snappy) { showInfo = false } }
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Weather: \(condition.name)")
    }

    @ViewBuilder private var icon: some View {
        let img = Image(systemName: symbol)
        switch condition {
        case .clear where isDay:
            img.symbolEffect(.rotate.byLayer, options: .repeat(.periodic(delay: 2)))
        case .drizzle, .rain, .snow, .fog:
            img.symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
        case .thunder:
            img.symbolEffect(.bounce.byLayer, options: .repeat(.periodic(delay: 1.2)))
        default:
            img.symbolEffect(.breathe.pulse.byLayer, options: .repeating)
        }
    }
}
