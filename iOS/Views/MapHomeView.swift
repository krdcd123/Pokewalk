import SwiftUI
import MapKit

struct MapHomeView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var tracker: LocationTracker
    @EnvironmentObject private var tracks: TrackStore
    @StateObject private var walking = WalkingDetector.shared
    @ObservedObject private var sleepSvc = SleepService.shared
    @ObservedObject private var recorder = SleepRecorder.shared
    @ObservedObject private var workout = PhoneWorkout.shared
    @State private var workoutPicker = false
    @State private var trainerLongPressAt = Date.distantPast
    /// Steps by default; "Sleeping" only once the phone has sat still for 20 minutes while listening.
    private var sleeping: Bool { recorder.asleepSince != nil }
    @AppStorage("journalSleepView") private var sleepView = false

    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var refollowTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    /// We follow you ourselves (instead of MapKit's .userLocation, which resets the zoom every time),
    /// so the map keeps whatever zoom you chose when menus close or you come back to the app.
    @State private var following = true
    @AppStorage("mapZoomDistance") private var zoomDistance: Double = 900
    @State private var lastCamera: MapCamera?
    /// Set once the map has zoomed in on you after launch (until then it may be showing the whole country
    /// while it waits for your location, and that zoom mustn't be kept).
    @State private var didInitialZoom = false

    /// Tap the location button / menus close / app reopens: glide back to you at the same zoom.
    private func followMe(distance: Double? = nil, duration: Double = 0.6) {
        refollowTask?.cancel()
        if let distance { zoomDistance = distance } else if let d = lastCamera?.distance { zoomDistance = d }
        following = true
        guard let loc = tracker.currentLocation() else {
            camera = .userLocation(followsHeading: false, fallback: .automatic)
            return
        }
        let cam = MapCamera(centerCoordinate: loc.coordinate, distance: zoomDistance,
                            heading: lastCamera?.heading ?? 0, pitch: lastCamera?.pitch ?? 0)
        withAnimation(.smooth(duration: duration)) { camera = .camera(cam) }
    }

    /// Tap your buddy on the map: zoom right in on where you are.
    private func zoomInOnMe() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        followMe(distance: 350, duration: 0.7)
    }
    @State private var sheet: HomeSheet?
    @State private var showCard = false
    @AppStorage("showCaughtOnMap") private var showCaught = false
    @State private var infoID: UUID?
    @State private var panelSession = 0
    @ObservedObject private var sound = SoundKit.shared
    @ObservedObject private var weather = WeatherService.shared      // new identity each time a panel opens, so menus start at the top

    enum HomeSheet: Hashable, Identifiable {
        case menu, party, encounters, bag, journal, summary(UUID)
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
                // The 3D map is the biggest thing in memory: drop it while in the background so iOS doesn't
                // close PokéWalk to make room for other apps (it's rebuilt instantly when you come back).
                Group { if scenePhase == .background { Theme.ink.ignoresSafeArea() } else { map } }
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
                        .accessibilityLabel("Centre on my location")
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
                    case .party: NavigationStack { PartyView() }
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
        .overlay { ConfettiRain(start: store.confettiAt) }
        .overlay {
            if let w = store.workoutPopup {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                        .onTapGesture { store.dismissWorkoutPopup() }
                    WorkoutCompleteCard(record: w) { store.dismissWorkoutPopup() }
                        .padding(24)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.4), value: store.workoutPopup)
        .overlay {
            if let n = sleepSvc.popup {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                        .onTapGesture { SoundKit.shared.play(.select); sleepSvc.popup = nil }
                    SleepPopupCard(night: n, close: { sleepSvc.popup = nil }, more: {
                        sleepSvc.popup = nil
                        sleepView = true
                        withAnimation(.spring(duration: 0.4)) { sheet = .journal }
                    })
                    .padding(20)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.4), value: sleepSvc.popup)
        .overlay {
            if workoutPicker {
                WorkoutPickerPopup(close: { withAnimation(.spring(duration: 0.4)) { workoutPicker = false } })
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(.spring(duration: 0.4), value: workoutPicker)
        .onChange(of: workout.message) { _, m in if let m { store.toast = m; workout.message = nil } }
        // A pickup notification was tapped: show the Party
        .onChange(of: store.openPartyAt) { _, at in
            guard at != nil else { return }
            store.openPartyAt = nil
            withAnimation(.spring(duration: 0.4)) { sheet = .party }
        }
        .onAppear {
            if store.openPartyAt != nil { store.openPartyAt = nil; sheet = .party }
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
                Annotation("Wild Pokémon", coordinate: CLLocationCoordinate2D(latitude: enc.location!.latitude,
                                                                                          longitude: enc.location!.longitude)) {
                    Button { open(enc) } label: {
                        MapPin(speciesID: enc.speciesID, ring: Theme.teal, wild: true,
                               hidden: !store.state.dexCaught.contains(enc.speciesID))     // never caught one: silhouette
                    }
                }.annotationTitles(.hidden)
            }
            if let loc = tracker.lastLocation {
                Annotation("You", coordinate: loc.coordinate, anchor: .bottom) {
                    Button(action: zoomInOnMe) {
                        BuddyMarker(speciesID: store.state.buddy?.speciesID, shiny: store.state.buddy?.isShiny ?? false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zoom in on me")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        // Always keep you in view: if you pan away, it glides back to you after a few seconds
        .onMapCameraChange(frequency: .onEnd) { ctx in
            lastCamera = ctx.camera
            guard didInitialZoom else { return }
            // Pinch-zooming sets the zoom we keep from now on (sane range only, so a glitchy frame can't stick)
            if (80...20_000).contains(ctx.camera.distance) { zoomDistance = ctx.camera.distance }
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
        .onChange(of: tracker.lastLocation) { old, loc in
            guard following, sheet == nil, let loc, loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 50 else { return }
            // tiny GPS wobbles don't move the camera
            if let old, loc.distance(from: old) < 3 { return }
            let cam = MapCamera(centerCoordinate: loc.coordinate, distance: zoomDistance,
                                heading: lastCamera?.heading ?? 0, pitch: lastCamera?.pitch ?? 0)
            withAnimation(.linear(duration: 0.8)) { camera = .camera(cam) }
        }
        // Launch, and every time you come back to the app (the map is rebuilt after being in the background):
        // it starts on the whole country, so as soon as we know where you are, jump in to street level —
        // your usual zoom, never a country-sized one. Done twice, as MapKit can ignore the very first move.
        .task {
            didInitialZoom = false
            if zoomDistance > 20_000 || zoomDistance < 80 { zoomDistance = 900 }
            for _ in 0..<60 {
                if tracker.currentLocation() != nil { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            followMe(distance: zoomDistance, duration: 0)
            try? await Task.sleep(for: .milliseconds(600))
            followMe(distance: zoomDistance, duration: 0.3)
            try? await Task.sleep(for: .seconds(1))
            didInitialZoom = true
        }
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
                Button {
                    if workout.isActive { SoundKit.shared.play(.menuOpen); workoutPicker = true; return }
                    sleepView = sleeping            // the Journal opens on the night while you're asleep
                    withAnimation(.spring(duration: 0.4)) { sheet = .journal }
                } label: {
                card {
                    ZStack {
                        if let live = workout.live, let kind = workout.kind {
                            // During a workout: a live tracker like the watch's
                            WorkoutTrackerCard(kind: kind, live: live)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.blurReplace(.downUp))
                        } else if sleeping {
                            // Gone to bed (sleep listening is on): the card turns into "Sleeping"
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Image(systemName: "moon.zzz.fill").foregroundStyle(Color(hex: 0x9AA7FF))
                                        .symbolEffect(.pulse, options: .repeating)
                                    Text("SLEEPING").font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft)
                                }
                                Text(recorder.asleepSince.map { "Since \(SleepFormat.time($0))" } ?? "Goodnight")
                                    .font(.rounded(22, .black))
                                Text("Listening for sleep talking").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                                Text("\(store.stepsToday.formatted()) steps today").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.blurReplace(.downUp))
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TODAY").font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(store.stepsToday.formatted()).font(.rounded(22, .black))
                                    Text("steps").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                                }
                                Text("\(Distance.text(store.metersToday)) walked")
                                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                                Label("\(store.caloriesToday.formatted()) kcal burned", systemImage: "flame.fill")
                                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                                    .labelStyle(.titleAndIcon)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.blurReplace(.downUp))
                        }
                    }
                    .animation(.smooth(duration: 0.6), value: sleeping)
                    .animation(.smooth(duration: 0.6), value: workout.isActive)
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
                Button {
                    if Date().timeIntervalSince(trainerLongPressAt) < 0.8 { return }     // that was a long press
                    Haptics.tap(); SoundKit.shared.play(.menuOpen); withAnimation(.spring(duration: 0.4)) { sheet = .party }
                } label: {
                    // Your trainer's small overworld sprite, walking on the spot.
                    TrainerSprite(style: store.state.trainer.style,
                                  pose: workout.kind?.isCycling == true ? .bike
                                      : workout.kind?.isSwimming == true ? .surf
                                      : (walking.isDriving && !workout.isActive ? .bike : .walk),
                                  animating: workout.isActive || walking.isWalking || walking.isDriving)
                        .frame(width: 44, height: 46)
                        .frame(width: 64, height: 64, alignment: .center)
                        .contentShape(Circle())
                        .glassCircle()
                        // Hold your trainer: start a workout
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            trainerLongPressAt = .now
                            Haptics.hold()
                            SoundKit.shared.play(.menuOpen)
                            withAnimation(.spring(duration: 0.4)) { workoutPicker = true }
                        })
                        // red badge: how many of your party are holding something you can take
                        .overlay(alignment: .topTrailing) {
                            let holding = store.state.party.filter { !$0.heldItems.isEmpty }.count
                            if holding > 0 {
                                Text("\(holding)")
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
                .accessibilityLabel("Party")

                Spacer()

                Button { Haptics.tap(); SoundKit.shared.play(.menuOpen); withAnimation(.spring(duration: 0.4)) { sheet = .menu } } label: {
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

                Button { Haptics.tap(); withAnimation(.spring(duration: 0.4)) { sheet = .encounters } } label: {
                    WildGrassIcon()
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                        .glassCircle(tint: Color(hex: 0x3FAE5A))
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
                // A lure going: a little timer bubble above the wild Pokémon button
                .overlay(alignment: .top) {
                    if let lure = store.state.activeLure {
                        Button { withAnimation(.spring(duration: 0.4)) { sheet = .encounters } } label: {
                            LureTimerBubble(lure: lure)
                        }
                        .buttonStyle(.plain)
                        .offset(y: -66)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Lure timer")
                    }
                }
                .animation(.spring(duration: 0.35), value: store.state.activeLure)
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassCard(20)
    }
}

/// Counts down the lure: a ring that fills up, with the time left inside.
struct LureTimerBubble: View {
    let lure: ActiveLure

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let total = lure.endsAt.timeIntervalSince(lure.startedAt)
            let left = max(0, lure.endsAt.timeIntervalSince(tl.date))
            let done = 1 - left / max(1, total)
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 3)
                Circle().trim(from: 0, to: done)
                    .stroke(Theme.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    ItemSprite(key: Fishing.lureKey(berries: lure.berries)).frame(width: 18, height: 18)
                    Text(left > 0 ? String(format: "%d:%02d", Int(left) / 60, Int(left) % 60) : "Ready!")
                        .font(.rounded(10, .black)).monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .padding(4)
            .frame(width: 54, height: 54)
            .glassCircle(tint: Theme.teal.opacity(0.5))
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        }
    }
}

struct MapPin: View {
    let speciesID: Int
    var ring: Color
    var wild = false
    var shiny = false
    var hidden = false          // a species you've never caught: blacked-out silhouette

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(.white)
                AnimatedSprite(speciesID: speciesID, shiny: shiny && !hidden, kind: .icons).padding(5)
                    .colorMultiply(hidden ? .black : .white)
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
                // A lure that's been set: counts down 30 minutes, then a wild Pokémon appears in this list
                if let lure = store.state.activeLure {
                    HStack(spacing: 12) {
                        ItemSprite(key: Fishing.lureKey(berries: lure.berries)).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Fishing.lureName(berries: lure.berries)).font(.rounded(16, .heavy)).foregroundStyle(Theme.ink)
                            ProgressView(timerInterval: lure.startedAt...lure.endsAt, countsDown: false) { EmptyView() }
                                currentValueLabel: { EmptyView() }
                                .tint(Theme.teal)
                            Text("Something will be attracted when the timer runs out")
                                .font(.rounded(11)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(timerInterval: now...max(now, lure.endsAt), countsDown: true)
                                .font(.rounded(14, .heavy)).monospacedDigit().foregroundStyle(Theme.tealDark)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 64, alignment: .trailing)
                            Text("lure").font(.rounded(10)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .glassRow()
                }
                if live.isEmpty && store.state.activeLure == nil {
                    ContentUnavailableView("No wild Pokémon yet", systemImage: "leaf",
                                           description: Text("One appears about every \(store.state.settings.encounterSteps) steps. Keep walking!"))
                        .listRowBackground(Color.clear)
                }
                ForEach(live.reversed()) { enc in
                    Button { open(enc) } label: {
                        HStack(spacing: 12) {
                            let unknown = !store.state.dexCaught.contains(enc.speciesID)     // never caught one
                            AnimatedSprite(speciesID: enc.speciesID, shiny: enc.isShiny && !unknown, kind: .icons)
                                .colorMultiply(unknown ? .black : .white)
                                .frame(width: 48, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unknown ? "???  Lv. \(enc.level)" : "\(enc.species.name)\(enc.isShiny ? " ✨" : "")  Lv. \(enc.level)")
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
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { now = $0 }
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                if let lure = store.state.activeLure, Date() >= lure.endsAt { Task { await store.checkLure() } }
            }
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
                SoundKit.shared.play(.select)
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


/// A small vibration for button presses.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func hold() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}


/// "Workout complete!" — what a workout earned.
struct WorkoutCompleteCard: View {
    @EnvironmentObject private var store: GameStore
    let record: WorkoutRecord
    var close: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: record.symbol)
                .font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                .frame(width: 70, height: 70).glassCircle(tint: Theme.teal, interactive: false)
            VStack(spacing: 4) {
                Text("Workout complete!").font(.rounded(22, .black))
                Text("\(record.name) · \(WorkoutCompleteCard.length(record.duration))")
                    .font(.rounded(14, .heavy)).foregroundStyle(Theme.inkSoft)
            }
            VStack(spacing: 8) {
                rewardRow("flame.fill", "\(record.kcal.formatted()) kcal burned")
                rewardRow("yensign.circle.fill", "₽\(record.money.formatted()) earned")
                if record.exp > 0, let mon = store.state.mon(record.expMonID) {
                    HStack(spacing: 10) {
                        AnimatedSprite(speciesID: mon.speciesID, shiny: mon.isShiny, kind: .icons).frame(width: 34, height: 28)
                        Text("\(mon.name) gained \(record.exp.formatted()) Exp").font(.rounded(15, .heavy))
                        Spacer(minLength: 0)
                    }
                }
                if let up = record.levelUp {
                    rewardRow("arrow.up.circle.fill", up)
                }
                if record.meters > 50 { rewardRow("point.topleft.down.to.point.bottomright.curvepath", Distance.text(record.meters)) }
                if !record.countsSteps && record.stepsNotCounted > 0 {
                    Text("\(record.stepsNotCounted.formatted()) steps during the workout weren't counted as walking.")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                }
            }
            .padding(14)
            .glassCard(18)
            Button { SoundKit.shared.play(.select); close() } label: {
                Text("Nice!").font(.rounded(17, .black)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .glassCapsule(tint: Theme.teal, interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: 360)
        .glassCard(28)
    }

    private func rewardRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.teal).frame(width: 34)
            Text(text).font(.rounded(15, .heavy))
            Spacer(minLength: 0)
        }
    }

    static func length(_ s: TimeInterval) -> String {
        let mins = max(1, Int((s / 60).rounded()))
        return mins >= 60 ? "\(mins / 60) h \(mins % 60) min" : "\(mins) min"
    }
}


// MARK: - Workouts

/// Live workout tracker in the Today card (like the watch): time, calories, distance, heart rate.
struct WorkoutTrackerCard: View {
    let kind: WorkoutKind
    let live: WorkoutLive

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol).foregroundStyle(Color(hex: 0x9BE15D))
                Text(kind.name.uppercased()).font(.rounded(11, .heavy)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                if live.paused { Text("PAUSED").font(.rounded(10, .black)).foregroundStyle(.yellow) }
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                // the watch sends the time every few seconds; count on smoothly in between
                Text(WorkoutTrackerCard.clock(elapsedNow(ctx.date)))
                    .font(.rounded(22, .black)).monospacedDigit()
                    .foregroundStyle(live.paused ? .yellow : .white)
            }
            HStack(spacing: 10) {
                Label("\(Int(live.kcal))", systemImage: "flame.fill").foregroundStyle(Color(hex: 0xFF5A7A))
                if let hr = live.heartRate { Label("\(Int(hr))", systemImage: "heart.fill").foregroundStyle(.red) }
                if kind.tracksDistance && live.meters > 0 {
                    Text(kind.isSwimming ? "\(Int(live.meters)) m" : Distance.text(live.meters)).foregroundStyle(.cyan)
                }
            }
            .font(.rounded(12, .heavy))
            .labelStyle(.titleAndIcon)
        }
    }

    private func elapsedNow(_ now: Date) -> TimeInterval {
        let base = live.elapsed > 0 ? live.elapsed : now.timeIntervalSince(live.start)
        if live.paused || live.elapsed == 0 { return max(0, base) }
        return base + max(0, now.timeIntervalSince(PhoneWorkout.shared.liveAt))
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Hold your trainer: pick a workout (Liquid Glass, over a blurred map of where you are).
struct WorkoutPickerPopup: View {
    @ObservedObject private var workout = PhoneWorkout.shared
    var close: () -> Void

    var body: some View {
        ZStack {
            LocationBackdrop().blur(radius: 14).ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { SoundKit.shared.play(.select); close() }
            VStack(spacing: 14) {
                HStack {
                    Text(workout.isActive ? "Workout" : "Start a workout").font(.rounded(22, .black))
                    Spacer()
                    Button { SoundKit.shared.play(.select); close() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38).glassCircle()
                    }
                    .buttonStyle(.plain)
                }
                if let kind = workout.kind, let live = workout.live {
                    VStack(spacing: 14) {
                        WorkoutTrackerCard(kind: kind, live: live)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).glassCard(22)
                        HStack(spacing: 12) {
                            Button {
                                SoundKit.shared.play(.select)
                                workout.togglePause()
                            } label: {
                                Label(live.paused ? "Resume" : "Pause", systemImage: live.paused ? "play.fill" : "pause.fill")
                                    .font(.rounded(16, .heavy)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 50)
                                    .glassCapsule(tint: .yellow.opacity(0.6), interactive: true)
                            }
                            Button {
                                SoundKit.shared.play(.select)
                                workout.end()
                                close()
                            } label: {
                                Label("End", systemImage: "xmark")
                                    .font(.rounded(16, .heavy)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 50)
                                    .glassCapsule(tint: Color(hex: 0xE04A3F), interactive: true)
                            }
                        }
                        .buttonStyle(.plain)
                        Text(kind.countsSteps ? "Steps still count as walking during this workout."
                                              : "Step rewards are paused until you end it.")
                            .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                            ForEach(WorkoutKind.all) { k in
                                Button {
                                    SoundKit.shared.play(.select)
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    Task { await workout.start(k) }
                                    close()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: k.symbol).font(.system(size: 26, weight: .semibold))
                                            .foregroundStyle(Color(hex: 0x9BE15D))
                                            .frame(width: 66, height: 66)
                                            .glassCircle(tint: Color(hex: 0x9BE15D).opacity(0.25), interactive: true)
                                        Text(k.name).font(.rounded(12, .heavy)).multilineTextAlignment(.center)
                                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 460)
                    Text("Records on your Apple Watch and saves to Apple Health. Step rewards pause for anything that isn't walking, running or hiking.")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .frame(maxWidth: 400)
            .glassCard(30)
            .padding(18)
        }
    }
}
