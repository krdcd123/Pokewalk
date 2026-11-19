import SwiftUI
import MapKit

struct JournalView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var tracks: TrackStore
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var steps = 0
    @State private var healthMeters: Double = 0
    @State private var camera: MapCameraPosition = .automatic
    @State private var showAllTime = false
    @State private var selected: UUID?

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
                             location: $0.location, status: $0.outcomeText, caught: $0.outcome == .caught)
        }
        let logged = Set(store.state.encounterLog.compactMap(\.caughtID))
        // Pokémon caught before the Journal kept an encounter log
        for mon in store.state.pokemon where mon.metNote == nil && !logged.contains(mon.id) && inRange(mon.metDate) {
            out.append(JournalEncounter(id: mon.id, speciesID: mon.speciesID, level: mon.metLevel, isShiny: mon.isShiny,
                                        date: mon.metDate, location: mon.metLocation, status: "Caught", caught: true))
        }
        for p in store.state.pending where inRange(p.appearedAt) {
            out.append(JournalEncounter(id: p.id, speciesID: p.speciesID, level: p.level, isShiny: p.isShiny,
                                        date: p.appearedAt, location: p.location, status: "Waiting", caught: false))
        }
        return out.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Range", selection: $showAllTime) {
                    Text("Day").tag(false)
                    Text("All time").tag(true)
                }
                .pickerStyle(.segmented)

                if !showAllTime {
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

                Map(position: $camera) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        if seg.count > 1 {
                            MapPolyline(coordinates: seg.map(\.coordinate)).stroke(.white, lineWidth: 5)
                            MapPolyline(coordinates: seg.map(\.coordinate)).stroke(Theme.route, lineWidth: 2.5)
                        }
                    }
                    ForEach(encounters.filter { $0.location != nil }) { e in
                        Annotation(e.species.name, coordinate: .init(latitude: e.location!.latitude, longitude: e.location!.longitude)) {
                            MapPin(speciesID: e.speciesID, ring: e.caught ? Theme.orange : Color.white.opacity(0.7))
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

                let gpsMeters = segments.reduce(0) { $0 + TrackStore.meters($1) }
                HStack(spacing: 10) {
                    stat(showAllTime ? Distance.text(gpsMeters) : Distance.text(max(gpsMeters, healthMeters)), "distance")
                    stat(showAllTime ? store.state.lifetimeSteps.formatted() : steps.formatted(), "steps")
                    stat("\(encounters.filter(\.caught).count)/\(encounters.count)", "caught")
                }

                Text("ENCOUNTERS").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                if encounters.isEmpty {
                    Text(showAllTime ? "No wild Pokémon yet — keep walking!" : "No wild Pokémon met this day.")
                        .font(.rounded(13)).foregroundStyle(Theme.inkSoft)
                }
                ForEach(encounters) { e in
                    Button { select(e) } label: {
                        HStack(spacing: 12) {
                            AnimatedSprite(speciesID: e.speciesID, kind: .icons)
                                .frame(width: 44, height: 40)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(e.species.name)\(e.isShiny ? " ✨" : "")  Lv \(e.level)").font(.rounded(15, .heavy))
                                Text("\(showAllTime ? e.date.formatted(date: .abbreviated, time: .shortened) : e.date.formatted(date: .omitted, time: .shortened)) · \(e.location?.displayName ?? "No location")")
                                    .font(.rounded(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            }
                            Spacer()
                            Text(e.status).font(.rounded(12, .black))
                                .foregroundStyle(e.caught ? Theme.orange : Theme.inkSoft)
                            if e.location != nil { Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.teal) }
                        }
                        .cardStyle()
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.teal, lineWidth: selected == e.id ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Journal")
        .glassScreen()
        .task(id: day) {
            steps = await StepEngine.shared.steps(onDay: day)
            let end = min(Date(), day.addingTimeInterval(86_400))
            healthMeters = (try? await StepCounter.shared.distance(from: day, to: end)) ?? 0
            camera = .automatic
            selected = nil
        }
        .onChange(of: showAllTime) { _, _ in camera = .automatic }
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


private struct JournalEncounter: Identifiable {
    let id: UUID
    let speciesID: Int
    let level: Int
    let isShiny: Bool
    let date: Date
    let location: MetLocation?
    let status: String
    let caught: Bool
    var species: Species { Dex.species(speciesID) }
}
