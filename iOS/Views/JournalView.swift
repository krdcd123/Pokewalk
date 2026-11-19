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

    private var days: [Date] {
        (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: .now)) }
    }

    private var segments: [[TrackPoint]] {
        showAllTime ? tracks.daysWithTracks.flatMap { tracks.segments(for: $0) } : tracks.segments(for: day)
    }

    private var caught: [OwnedPokemon] {
        store.state.pokemon.filter { mon in
            mon.metLocation != nil && (showAllTime || Calendar.current.isDate(mon.metDate, inSameDayAs: day))
        }
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
                            }
                        }
                    }
                }

                Map(position: $camera) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        if seg.count > 1 {
                            MapPolyline(coordinates: seg.map(\.coordinate)).stroke(.white, lineWidth: 5)
                            MapPolyline(coordinates: seg.map(\.coordinate)).stroke(Theme.route, lineWidth: 2.5)
                        }
                    }
                    ForEach(caught) { mon in
                        Annotation(mon.name, coordinate: .init(latitude: mon.metLocation!.latitude, longitude: mon.metLocation!.longitude)) {
                            MapPin(speciesID: mon.speciesID, ring: Theme.orange)
                        }.annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    if segments.isEmpty && caught.isEmpty {
                        Text("No walks recorded").font(.rounded(15, .heavy)).foregroundStyle(Theme.inkSoft)
                            .padding(12).glassCapsule()
                    }
                }

                let gpsMeters = segments.reduce(0) { $0 + TrackStore.meters($1) }
                HStack(spacing: 10) {
                    stat(showAllTime ? Distance.text(gpsMeters) : Distance.text(max(gpsMeters, healthMeters)), "distance")
                    stat(showAllTime ? store.state.lifetimeSteps.formatted() : steps.formatted(), "steps")
                    stat("\(caught.count)", "caught")
                }

                if !showAllTime {
                    Text("WALKS").font(.rounded(13, .heavy)).foregroundStyle(Theme.inkSoft)
                    let walks = tracks.walks(on: day)
                    if walks.isEmpty {
                        Text("Walks show up here when location tracking is on.").font(.rounded(13)).foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(walks) { w in
                        let n = store.state.pokemon.filter { $0.metDate >= w.start && $0.metDate <= w.end.addingTimeInterval(600) }.count
                        Button {
                            withAnimation { camera = .rect(boundingRect(w.points)) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                                    .foregroundStyle(Theme.tealDark).frame(width: 40, height: 40)
                                    .background(Theme.teal.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(w.start.formatted(date: .omitted, time: .shortened)) – \(w.end.formatted(date: .omitted, time: .shortened))")
                                        .font(.rounded(15, .heavy))
                                    Text(String(format: "%.2f mi · %d min · %d caught", Distance.miles(w.meters),
                                                Int(w.end.timeIntervalSince(w.start) / 60), n))
                                        .font(.rounded(12)).foregroundStyle(Theme.inkSoft)
                                }
                                Spacer()
                            }
                            .cardStyle()
                        }
                        .buttonStyle(.plain)
                    }
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
        }
        .onChange(of: showAllTime) { _, _ in camera = .automatic }
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
