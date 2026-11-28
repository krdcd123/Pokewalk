import SwiftUI
import MapKit
import Photos

struct JournalView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var tracks: TrackStore
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var steps = 0
    @State private var healthMeters: Double = 0
    @State private var camera: MapCameraPosition = .automatic
    @State private var showAllTime = false
    @State private var selected: UUID?
    @ObservedObject private var places = PlaceLog.shared
    @ObservedObject private var photos = JournalPhotos.shared
    @State private var renaming: Stay?
    @State private var renamingGroup: [Stay] = []
    @State private var choosingGroup: [Stay] = []
    @State private var expanded: Set<UUID> = []
    @State private var newName = ""
    @State private var dayWorkouts: [StepCounter.WorkoutInfo] = []
    @State private var calendarMode = false
    @AppStorage("journalSleepView") private var sleepView = false
    @AppStorage("journalEncountersOpen2") private var encountersOpen = false
    @AppStorage("journalPlacesOpen") private var placesOpen = false

    private var days: [Date] {
        // Oldest on the left, today on the right
        (0..<14).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: .now)) }
    }

    private var segments: [[TrackPoint]] {
        showAllTime ? tracks.daysWithTracks.flatMap { tracks.segments(for: $0) } : tracks.segments(for: day)
    }

    private var caught: [OwnedPokemon] {
        store.state.pokemon.filter { mon in
            mon.metLocation != nil && (showAllTime || Calendar.current.isDate(mon.metDate, inSameDayAs: day))
        }
    }

    /// Everything you met on the day: wild Pokémon you caught, that fled, that you ran from, or still waiting.
    private var encounters: [JournalEncounter] {
        let cal = Calendar.current
        let inRange: (Date) -> Bool = { showAllTime || cal.isDate($0, inSameDayAs: day) }
        var out: [JournalEncounter] = store.state.encounterLog.filter { inRange($0.date) }.map {
            JournalEncounter(id: $0.id, speciesID: $0.speciesID, level: $0.level, isShiny: $0.isShiny, date: $0.date,
                             location: $0.location, status: $0.outcomeText, caught: $0.outcome == .caught,
                             hidden: $0.outcome == .left && $0.seen != true)
        }
        let logged = Set(store.state.encounterLog.compactMap(\.caughtID))
        // Pokémon caught before the Journal kept an encounter log
        for mon in store.state.pokemon where mon.metNote == nil && !logged.contains(mon.id) && inRange(mon.metDate) {
            out.append(JournalEncounter(id: mon.id, speciesID: mon.speciesID, level: mon.metLevel, isShiny: mon.isShiny,
                                        date: mon.metDate, location: mon.metLocation, status: "Caught", caught: true, hidden: false))
        }
        for p in store.state.pending where inRange(p.appearedAt) {
            out.append(JournalEncounter(id: p.id, speciesID: p.speciesID, level: p.level, isShiny: p.isShiny,
                                        date: p.appearedAt, location: p.location, status: "Waiting", caught: false,
                                        hidden: !store.state.openedEncounters.contains(p.id)))
        }
        return out.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Range", selection: Binding(get: { showAllTime ? 2 : (calendarMode ? 1 : 0) },
                                                   set: { showAllTime = $0 == 2; calendarMode = $0 == 1 })) {
                    Text("Recent").tag(0)
                    Text("Calendar").tag(1)
                    Text("All time").tag(2)
                }
                .pickerStyle(.segmented)

                if calendarMode && !showAllTime {
                    // Any day of your life: photos, steps from Apple Health, sleep… (walks and places since you started PokéWalk)
                    DatePicker("Day", selection: Binding(get: { day }, set: { day = Calendar.current.startOfDay(for: $0) }),
                               in: Date(timeIntervalSince1970: 0)...Date.now, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Theme.teal)
                        .padding(8)
                        .glassCard(20)
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        .font(.rounded(18, .black))
                } else if !showAllTime {
                    ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(days, id: \.self) { d in
                                let selected = Calendar.current.isDate(d, inSameDayAs: day)
                                Button { day = d } label: {
                                    VStack(spacing: 0) {
                                        Text(d.formatted(.dateTime.weekday(.abbreviated))).font(.rounded(11, .heavy))
                                        Text(d.formatted(.dateTime.day())).font(.rounded(18, .black))
                                    }
                                    .frame(width: 48, height: 54)
                                    .foregroundStyle(.white)
                                    .glassCard(14, tint: selected ? Theme.teal : nil)
                                }
                                .id(d)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(days.last, anchor: .trailing) }
                    }
                }

                if !showAllTime {
                    HStack {
                        Text(sleepView ? "Your night" : "Your day").font(.rounded(15, .heavy)).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        DayNightToggle(sleep: $sleepView)
                    }
                }

                if sleepView && !showAllTime {
                    // Today's moon page shows the latest night PokéWalk has registered (last night),
                    // and only moves on once tonight's sleep has been worked out in the morning.
                    Group {
                    if Calendar.current.isDateInToday(day) {
                        SleepSection(day: SleepService.shared.lastNight?.day
                                        ?? Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day)
                    } else {
                        SleepSection(day: day)
                    }
                    }
                        .transition(.blurReplace.combined(with: .opacity))
                } else {
                VStack(alignment: .leading, spacing: 14) {
                Map(position: $camera) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        if seg.count > 1 {
                            MapPolyline(coordinates: seg.map(\.coordinate)).stroke(.white, lineWidth: 5)
                            MapPolyline(coordinates: seg.map(\.coordinate))
                                .stroke(TrackStore.isDrive(seg) ? Theme.driveRoute : Theme.route, lineWidth: 2.5)
                        }
                    }
                    if !showAllTime {
                        ForEach(stays) { st in
                            Annotation(st.shownName ?? "Place", coordinate: st.coordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white, Theme.teal)
                                    .shadow(radius: 3)
                                    .scaleEffect(selected == st.id ? 1.35 : 1)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                    ForEach(encounters.filter { $0.location != nil }) { e in
                        Annotation(e.species.name, coordinate: .init(latitude: e.location!.latitude, longitude: e.location!.longitude)) {
                            MapPin(speciesID: e.speciesID, ring: e.caught ? Theme.orange : Color.white.opacity(0.7), shiny: e.isShiny)
                                .scaleEffect(selected == e.id ? 1.3 : 1)
                                .animation(.spring(duration: 0.3), value: selected)
                                .onTapGesture { select(e) }
                        }.annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    if segments.isEmpty && encounters.isEmpty {
                        Text("No walks recorded").font(.rounded(15, .heavy)).foregroundStyle(Theme.inkSoft)
                            .padding(12).glassCapsule()
                    }
                }

                let gpsMeters = segments.filter { !TrackStore.isDrive($0) }.reduce(0) { $0 + TrackStore.meters($1) }
                let drivenMeters = segments.filter(TrackStore.isDrive).reduce(0) { $0 + TrackStore.meters($1) }
                HStack(spacing: 10) {
                    stat(showAllTime ? Distance.text(gpsMeters) : Distance.text(max(gpsMeters, healthMeters)), "distance")
                    stat(showAllTime ? store.state.lifetimeSteps.formatted() : steps.formatted(), "steps")
                    stat("\(encounters.filter(\.caught).count)/\(encounters.count)", "caught")
                }

                if drivenMeters > 0 {
                    HStack(spacing: 8) {
                        Capsule().fill(Theme.driveRoute).frame(width: 18, height: 4)
                        Text("\(Distance.text(drivenMeters)) driven · not counted as walking")
                            .font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                    }
                }
                if !showAllTime {
                    placesSection
                    workoutsSection
                    photosSection
                }
                // Encounters: tap the header to fold the list away
                Button {
                    SoundKit.shared.play(.select)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { encountersOpen.toggle() }
                } label: {
                    HStack {
                        Text("ENCOUNTERS · \(encounters.count)").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.inkSoft)
                            .rotationEffect(.degrees(encountersOpen ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if encounters.isEmpty {
                    Text(showAllTime ? "No wild Pokémon yet — keep walking!" : "No wild Pokémon met this day.")
                        .font(.rounded(13)).foregroundStyle(Theme.inkSoft)
                }
                // Folded: just the latest one (tap it to see them all). Open: every encounter.
                if true {
                ForEach(encountersOpen ? encounters : Array(encounters.prefix(1))) { e in
                    Button {
                        if !encountersOpen && encounters.count > 1 {
                            SoundKit.shared.play(.select)
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { encountersOpen = true }
                        } else {
                            select(e)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            AnimatedSprite(speciesID: e.speciesID, shiny: e.isShiny && !e.hidden, kind: .icons)
                                .colorMultiply(e.hidden ? .black : .white)            // never seen up close: silhouette
                                .opacity(e.hidden ? 0.85 : 1)
                                .frame(width: 44, height: 40)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.hidden ? "???  Lv \(e.level)" : "\(e.species.name)\(e.isShiny ? " ✨" : "")  Lv \(e.level)")
                                    .font(.rounded(15, .heavy))
                                Text("\(showAllTime ? e.date.formatted(date: .abbreviated, time: .shortened) : e.date.formatted(date: .omitted, time: .shortened)) · \(e.location?.displayName ?? "No location")")
                                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            }
                            Spacer()
                            if !encountersOpen && encounters.count > 1 {
                                Text("+\(encounters.count - 1) more").font(.rounded(12, .black)).foregroundStyle(Theme.tealDark)
                            } else {
                                Text(e.status).font(.rounded(12, .black))
                                    .foregroundStyle(e.caught ? Theme.orange : Theme.inkSoft)
                            }
                            if e.location != nil { Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.teal) }
                        }
                        .cardStyle()
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.teal, lineWidth: selected == e.id ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                }
                }
                }
                .transition(.blurReplace.combined(with: .opacity))
                }
            }
            .padding()
            .animation(.smooth(duration: 0.5), value: sleepView)
        }
        .navigationTitle("Journal")
        .glassScreen()
        .task(id: day) {
            places.refineNames(on: day)
            steps = max(0, await StepEngine.shared.steps(onDay: day) - (await StepCounter.shared.nonWalkingWorkoutSteps(onDay: day)))
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
            dayWorkouts = await StepCounter.shared.workouts(from: day, to: min(.now, dayEnd))
            let end = min(Date(), day.addingTimeInterval(86_400))
            healthMeters = (try? await StepCounter.shared.distance(from: day, to: end)) ?? 0
            camera = .automatic
            selected = nil
        }
        .onChange(of: showAllTime) { _, _ in camera = .automatic }
    }

    private var stays: [Stay] { _ = places.revision; return places.stays(on: day) }

    /// "Places" timeline: where you spent time today, in order.
    @ViewBuilder private var placesSection: some View {
        let list = stays
        VStack(alignment: .leading, spacing: 10) {
            let placeCount = PlaceGroup.make(list).count
            Button {
                guard placeCount > 1 else { return }
                SoundKit.shared.play(.select)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { placesOpen.toggle() }
            } label: {
                HStack {
                    Text("PLACES · \(placeCount)").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    if placeCount > 1 {
                        if !placesOpen {
                            Text("+\(placeCount - 1) more").font(.rounded(12, .black)).foregroundStyle(Theme.tealDark)
                        }
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.inkSoft)
                            .rotationEffect(.degrees(placesOpen ? 0 : -90))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if list.isEmpty {
                Text("Places you stay at for 10 minutes or more show up here, with how long you were there.")
                    .font(.rounded(13)).foregroundStyle(Theme.inkSoft)
            } else {
                if PlaceGroup.make(list).count > 1 {
                    Text(list.map { $0.shownName ?? "Somewhere" }.removingDuplicatesInARow().joined(separator: " → "))
                        .font(.rounded(15, .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                }
                let allGroups = PlaceGroup.make(list)
                // Folded: just the first place (tap it to see the rest). Open: every place.
                let groups = placesOpen ? allGroups : Array(allGroups.prefix(1))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { idx, g in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle().fill(g.isOpen ? Theme.orange : Theme.teal).frame(width: 12, height: 12)
                                    .padding(.top, 4)
                                if idx < groups.count - 1 {
                                    Rectangle().fill(.white.opacity(0.25)).frame(width: 2).frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name ?? "Finding the name…").font(.rounded(15, .heavy))
                                Text(groupTimes(g)).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                                if selected == g.id && photos.allowed {
                                    PlacePhotos(group: g).padding(.top, 6)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                                // Tap to see each time you were there
                                if expanded.contains(g.id) && g.visits.count > 1 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(g.visits, id: \.stay.id) { v in
                                            HStack(spacing: 6) {
                                                Circle().fill(.white.opacity(0.4)).frame(width: 5, height: 5)
                                                Text(visitTimes(v)).font(.rounded(12, .heavy))
                                            }
                                        }
                                    }
                                    .padding(.top, 6)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            Spacer()
                            if g.visits.count > 1 {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.inkSoft)
                                    .rotationEffect(.degrees(expanded.contains(g.id) ? 180 : 0))
                                    .padding(.top, 4)
                            }
                            Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.teal)
                                .onTapGesture { selectStay(g.visits[0].stay) }
                        }
                        .padding(.bottom, idx < groups.count - 1 ? 14 : 0)
                        .contentShape(Rectangle())
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                        .onTapGesture {
                            if !placesOpen && allGroups.count > 1 {
                                SoundKit.shared.play(.select)
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { placesOpen = true }
                                return
                            }
                            if g.visits.count > 1 {
                                withAnimation(.snappy) {
                                    if expanded.contains(g.id) { expanded.remove(g.id) } else { expanded.insert(g.id) }
                                }
                            }
                            selectStay(g.visits[0].stay)
                        }
                        .contextMenu {
                            if let opts = g.visits[0].stay.options, opts.count > 1 {
                                Button("Where was this?", systemImage: "mappin.and.ellipse") { choosingGroup = g.visits.map(\.stay) }
                            }
                            Button("Rename", systemImage: "pencil") { newName = g.name ?? ""; renaming = g.visits[0].stay; renamingGroup = g.visits.map(\.stay) }
                        }
                    }
                }
                .padding(14)
                .glassCard(18)
            }
        }
        // Pick the right place from what was nearby; PokéWalk remembers it for next time
        .confirmationDialog("Where were you?", isPresented: Binding(get: { !choosingGroup.isEmpty }, set: { if !$0 { choosingGroup = [] } }),
                            titleVisibility: .visible) {
            ForEach(choosingGroup.first?.options ?? [], id: \.self) { name in
                Button(name) {
                    SoundKit.shared.play(.select)
                    for st in choosingGroup { places.rename(st, to: name) }
                    choosingGroup = []
                }
            }
            Button("Type a name…") {
                newName = choosingGroup.first?.name ?? ""
                renaming = choosingGroup.first; renamingGroup = choosingGroup
                choosingGroup = []
            }
            Button("Cancel", role: .cancel) { choosingGroup = [] }
        } message: {
            Text("Places near where your phone was. Your choice is remembered next time you're there.")
        }
        .alert("Rename place", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") {
                let all = renamingGroup.isEmpty ? (renaming.map { [$0] } ?? []) : renamingGroup
                for st in all { places.rename(st, to: newName) }
                renamingGroup = []
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Workouts this day (from Apple Health) and what each one earned.
    @ViewBuilder private var workoutsSection: some View {
        var seenIDs = Set<String>()
        let recorded = store.state.workouts.filter { Calendar.current.isDate($0.start, inSameDayAs: day) && seenIDs.insert($0.id).inserted }
        let ids = Set(recorded.map(\.id))
        let others = dayWorkouts.filter { !ids.contains($0.id) }
        if !recorded.isEmpty || !others.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("WORKOUTS").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                ForEach(recorded) { r in
                    workoutRow(symbol: r.symbol, name: r.name, start: r.start, end: r.end, kcal: r.kcal, meters: r.meters,
                               earned: earnedText(r), note: (!r.countsSteps && r.stepsNotCounted > 0)
                                   ? "\(r.stepsNotCounted.formatted()) steps not counted as walking" : (r.countsSteps ? "Steps counted as walking" : nil))
                }
                ForEach(others) { w in
                    workoutRow(symbol: w.symbol, name: w.name, start: w.start, end: w.end, kcal: Int(w.kcal), meters: w.meters,
                               earned: nil, note: "Before workout rewards were added")
                }
            }
        }
    }

    private func earnedText(_ r: WorkoutRecord) -> String {
        var parts = ["₽\(r.money.formatted())"]
        if r.exp > 0 {
            let who = store.state.mon(r.expMonID)?.name ?? "Buddy"
            parts.append("+\(r.exp.formatted()) Exp for \(who)")
        }
        return parts.joined(separator: " · ")
    }

    private func workoutRow(symbol: String, name: String, start: Date, end: Date, kcal: Int, meters: Double,
                            earned: String?, note: String?) -> some View {
        let t = Date.FormatStyle(date: .omitted, time: .shortened)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).glassCircle(tint: Theme.teal, interactive: false)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(name).font(.rounded(16, .heavy))
                    Spacer()
                    Text(WorkoutCompleteCard.length(end.timeIntervalSince(start))).font(.rounded(14, .heavy))
                }
                Text("\(start.formatted(t)) – \(end.formatted(t)) · \(kcal.formatted()) kcal\(meters > 50 ? " · \(Distance.text(meters))" : "")")
                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                if let earned {
                    Label(earned, systemImage: "gift.fill").font(.rounded(13, .heavy)).foregroundStyle(Theme.tealDark)
                }
                if let note { Text(note).font(.rounded(11)).foregroundStyle(Theme.inkSoft) }
            }
        }
        .padding(12)
        .glassCard(18)
    }

    /// Photos you took this day (from your photo library). Tap a place above to see just the ones from there.
    @ViewBuilder private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHOTOS").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
            if photos.allowed {
                let list = photos.assets(onDay: day)
                if list.isEmpty {
                    Text("No photos taken this day.").font(.rounded(13)).foregroundStyle(Theme.inkSoft)
                } else {
                    PhotoStrip(assets: list)
                    Text("\(list.count) from this day · tap a place to see the ones taken there")
                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                }
            } else {
                Button {
                    if photos.undecided { Task { await photos.requestAccess() } }
                    else if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label(photos.undecided ? "Show photos from your library" : "Allow photo access in Settings",
                          systemImage: "photo.on.rectangle.angled")
                        .font(.rounded(14, .heavy)).frame(maxWidth: .infinity).padding(12)
                }
                .buttonStyle(.plain)
                .glassCard(16)
                Text("PokéWalk only reads your photos to show them here — it never changes or uploads them.")
                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func groupTimes(_ g: PlaceGroup) -> String {
        let t = Date.FormatStyle(date: .omitted, time: .shortened)
        let len = Self.length(g.duration)
        let visits = g.visits.count > 1 ? " · \(g.visits.count) visits" : ""
        if let end = g.end { return "\(g.start.formatted(t)) – \(end.formatted(t)) · \(len)\(visits)" }
        return "Since \(g.start.formatted(t)) · \(len) so far\(visits)"
    }

    private func visitTimes(_ v: PlaceGroup.Visit) -> String {
        let t = Date.FormatStyle(date: .omitted, time: .shortened)
        let len = Self.length((v.end ?? .now).timeIntervalSince(v.stay.arrived))
        if let end = v.end { return "\(v.stay.arrived.formatted(t)) – \(end.formatted(t)) · \(len)" }
        return "\(v.stay.arrived.formatted(t)) – now · \(len)"
    }

    private static func length(_ s: TimeInterval) -> String {
        let mins = max(0, Int(s / 60))
        return mins >= 60 ? "\(mins / 60) h \(mins % 60) min" : "\(mins) min"
    }

    private func stayTimes(_ st: Stay) -> String {
        let t = Date.FormatStyle(date: .omitted, time: .shortened)
        let mins = Int(st.duration() / 60)
        let len = mins >= 60 ? "\(mins / 60) h \(mins % 60) min" : "\(mins) min"
        if let left = st.left { return "\(st.arrived.formatted(t)) – \(left.formatted(t)) · \(len)" }
        return "Since \(st.arrived.formatted(t)) · \(len) so far"
    }

    private func selectStay(_ st: Stay) {
        selected = st.id
        withAnimation(.smooth(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(center: st.coordinate, latitudinalMeters: 400, longitudinalMeters: 400))
        }
    }

    private func select(_ e: JournalEncounter) {
        selected = e.id
        guard let loc = e.location else { return }
        withAnimation(.smooth(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(center: .init(latitude: loc.latitude, longitude: loc.longitude),
                                                latitudinalMeters: 350, longitudinalMeters: 350))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.rounded(20, .black)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.rounded(12)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(16)
    }

    private func boundingRect(_ pts: [TrackPoint]) -> MKMapRect {
        let rects = pts.map { MKMapRect(origin: MKMapPoint($0.coordinate), size: MKMapSize(width: 1, height: 1)) }
        let r = rects.dropFirst().reduce(rects.first ?? .null) { $0.union($1) }
        return r.insetBy(dx: -r.width * 0.25 - 200, dy: -r.height * 0.25 - 200)
    }
}


/// Back-to-back stays at the same place, shown as one row (tap to see each visit).
struct PlaceGroup: Identifiable {
    struct Visit { var stay: Stay; var end: Date? }
    var visits: [Visit]
    var id: UUID { visits[0].stay.id }
    var name: String? { visits.lazy.compactMap(\.stay.shownName).first }
    var start: Date { visits[0].stay.arrived }
    var end: Date? { visits.last?.end }
    var isOpen: Bool { end == nil }
    var duration: TimeInterval { (end ?? .now).timeIntervalSince(start) }

    static func make(_ stays: [Stay]) -> [PlaceGroup] {
        let list = stays.sorted { $0.arrived < $1.arrived }
        var groups: [PlaceGroup] = []
        for (i, st) in list.enumerated() {
            // An old stay still marked "here" ended when the next one began
            var end = st.left
            if end == nil, i < list.count - 1 { end = list[i + 1].arrived }
            let v = Visit(stay: st, end: end)
            if let last = groups.last?.visits.last?.stay,
               (last.shownName != nil && last.shownName == st.shownName) || last.location.distance(from: st.location) < PlaceLog.radius * 1.5 {
                groups[groups.count - 1].visits.append(v)
            } else {
                groups.append(PlaceGroup(visits: [v]))
            }
        }
        return groups
    }
}

private struct JournalEncounter: Identifiable {
    let id: UUID
    let speciesID: Int
    let level: Int
    let isShiny: Bool
    let date: Date
    let location: MetLocation?
    let status: String
    let caught: Bool
    let hidden: Bool            // never opened: a blacked-out silhouette, name unknown
    var species: Species { Dex.species(speciesID) }
}


private extension Array where Element == String {
    /// "Home → Home → Park" becomes "Home → Park".
    func removingDuplicatesInARow() -> [String] {
        reduce(into: []) { out, x in if out.last != x { out.append(x) } }
    }
}


/// Photos taken at one place (shown under it when you tap it).
private struct PlacePhotos: View {
    let group: PlaceGroup
    @State private var assets: [PHAsset]?

    var body: some View {
        Group {
            if let assets {
                if assets.isEmpty {
                    Text("No photos taken here").font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                } else {
                    PhotoStrip(assets: assets, size: 60)
                }
            }
        }
        .task(id: group.id) { assets = JournalPhotos.shared.assets(for: group) }
    }
}
