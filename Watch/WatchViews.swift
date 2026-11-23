import SwiftUI
import MapKit
import ImageIO
import WatchKit

/// Screens in the watch app (also where a tapped notification can jump to).
enum WatchRoute: Hashable {
    case party, bag, wild, map
    case summary(String)    // party member id
    case battle(String)     // wild Pokémon id
}

// MARK: - Root: the condensed menu

struct WatchRootView: View {
    @ObservedObject private var model = WatchModel.shared

    var body: some View {
        NavigationStack(path: $model.path) {
            Group {
                if model.hasData {
                    MenuPage()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.and.arrow.forward").font(.largeTitle)
                        Text("Open PokéWalk on your iPhone and pick a partner.")
                            .multilineTextAlignment(.center).font(.footnote)
                    }
                }
            }
            .watchBackdrop()
            .navigationDestination(for: WatchRoute.self) { route in
                Group {
                    switch route {
                    case .party: PartyPage()
                    case .bag: BagPage()
                    case .wild: WildPage()
                    case .map: WatchMapPage()
                    case .summary(let id): SummaryPage(memberID: id)
                    case .battle(let id): BattlePage(wildID: id)
                    }
                }
                .watchBackdrop()
            }
        }
    }
}

struct MenuPage: View {
    @ObservedObject private var model = WatchModel.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let buddy = model.snapshot.buddy {
                    NavigationLink(value: WatchRoute.summary(buddy.id)) { BuddyHeader(member: buddy) }
                        .buttonStyle(.plain)
                }
                MenuTile(title: "Party", subtitle: "\(model.snapshot.party.count) Pokémon", system: "circle.grid.2x2.fill",
                         tint: Color(hex: 0x4FA3F7), badge: model.snapshot.party.contains { $0.heldItem != nil } ? -1 : 0,
                         route: .party)
                MenuTile(title: "Bag", subtitle: "₽\(model.snapshot.money.formatted())", system: "bag.fill",
                         tint: Color(hex: 0xE8A23A), badge: 0, route: .bag)
                MenuTile(title: "Wild", subtitle: model.snapshot.wild.isEmpty ? "\(model.liveStepsToEncounter) steps to go" : "Waiting to be caught",
                         system: "leaf.fill", tint: Color(hex: 0x4CC76E), badge: model.snapshot.wild.count, route: .wild)
                MenuTile(title: "Map", subtitle: "Where you are", system: "map.fill",
                         tint: Color(hex: 0x3FB8AF), badge: 0, route: .map)
                if let status = model.syncStatus {
                    Text(status).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button { model.requestPhoneSync() } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath").font(.footnote)
                }
                .glassButton()
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Menu")
    }
}

/// Your walking buddy at the top of the menu.
struct BuddyHeader: View {
    @ObservedObject private var model = WatchModel.shared
    let member: WatchSnapshot.Member

    var body: some View {
        let live = model.live(member)
        HStack(spacing: 8) {
            HoppingIcon(member: member, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(member.name).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("Lv\(live.level)").font(.footnote.weight(.semibold)).monospacedDigit()
                }
                ExpBar(progress: live.progress, tint: Color(hex: 0x4FA3F7), height: 5)
                Text(live.readyToEvolve ? "Ready to evolve!" : "\(live.stepsToNext.formatted()) steps to next")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(10)
        .glassCard()
    }
}

struct MenuTile: View {
    let title: String
    let subtitle: String
    let system: String
    let tint: Color
    let badge: Int          // -1 = red dot, 0 = none, n = number
    let route: WatchRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                Image(systemName: system).font(.title3).foregroundStyle(tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if badge > 0 {
                    Text("\(badge)").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                } else if badge < 0 {
                    HeldDot(size: 9)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard(tint: tint)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Party

struct PartyPage: View {
    @ObservedObject private var model = WatchModel.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(model.snapshot.party) { member in
                    NavigationLink(value: WatchRoute.summary(member.id)) { PartyRow(member: member) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Party")
    }
}

struct PartyRow: View {
    @ObservedObject private var model = WatchModel.shared
    let member: WatchSnapshot.Member

    var body: some View {
        let live = model.live(member)
        HStack(spacing: 8) {
            HoppingIcon(member: member, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text(member.name).font(.footnote.weight(.semibold)).lineLimit(1)
                    if member.isBuddy { Image(systemName: "figure.walk").font(.caption2).foregroundStyle(.green) }
                    Spacer(minLength: 0)
                    Text("Lv\(live.level)").font(.caption2.weight(.semibold)).monospacedDigit()
                }
                ExpBar(progress: live.progress, tint: Color(hex: 0x4FA3F7), height: 4)
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .glassCard(14)
    }
}

struct SummaryPage: View {
    @ObservedObject private var model = WatchModel.shared
    let memberID: String
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        if let member = model.snapshot.party.first(where: { $0.id == memberID }) {
            let live = model.live(member)
            ScrollView {
                VStack(spacing: 6) {
                    WatchAnimatedSprite(speciesID: member.speciesID, shiny: member.isShiny)
                        .frame(height: 76)
                    HStack(spacing: 4) {
                        Text(member.name).font(.headline).lineLimit(1)
                        if member.isShiny { Text("✨").font(.caption) }
                        genderMark(member.gender)
                    }
                    VStack(spacing: 5) {
                        infoRow("Level", "\(live.level)")
                        ExpBar(progress: live.progress, tint: Color(hex: 0x4FA3F7), height: 5)
                        infoRow("To next level", live.readyToEvolve ? "Ready to evolve!" : "\(live.stepsToNext.formatted()) steps")
                        infoRow("Steps walked", (member.stepsWalked + (member.isBuddy ? model.stepsSinceSync : 0)).formatted())
                        infoRow("Type", member.species.types.map(\.displayName).joined(separator: " / "))
                    }
                    .padding(10)
                    .glassCard()

                    if let item = member.heldItem {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                ItemIcon(key: item).frame(width: 22, height: 22)
                                Text(Dex.itemName(item)).font(.footnote).lineLimit(1)
                                Spacer(minLength: 0)
                                HeldDot(size: 8)
                            }
                            Button {
                                busy = true
                                Task { note = await model.takeItem(from: member); busy = false }
                            } label: {
                                Text(busy ? "Taking…" : "Take item").frame(maxWidth: .infinity)
                            }
                            .glassButton(tint: .red)
                            .disabled(busy)
                        }
                        .padding(10)
                        .glassCard()
                    }
                    if let note { Text(note).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                }
            }
            .navigationTitle(member.isBuddy ? "Buddy" : "Summary")
        } else {
            Text("Not in your party any more.").font(.footnote)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private func genderMark(_ g: Gender) -> some View {
        switch g {
        case .male: Text("♂").font(.caption.bold()).foregroundStyle(Color(hex: 0x4FA3F7))
        case .female: Text("♀").font(.caption.bold()).foregroundStyle(Color(hex: 0xF06292))
        default: EmptyView()
        }
    }
}

// MARK: - Bag

struct BagPage: View {
    @ObservedObject private var model = WatchModel.shared

    var body: some View {
        let pockets = ["Balls", "Berries", "Items", "Key items"].filter { p in model.snapshot.bag.contains { $0.pocket == p } }
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if pockets.isEmpty {
                    Text("Your Bag is empty.").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                ForEach(pockets, id: \.self) { pocket in
                    Text(pocket).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                    VStack(spacing: 0) {
                        let lines = model.snapshot.bag.filter { $0.pocket == pocket }
                        ForEach(lines) { line in
                            HStack(spacing: 8) {
                                ItemIcon(key: line.key).frame(width: 22, height: 22)
                                Text(line.name).font(.footnote).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("×\(line.count)").font(.footnote.weight(.semibold)).monospacedDigit()
                            }
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            if line.id != lines.last?.id { Divider().opacity(0.3) }
                        }
                    }
                    .glassCard(14)
                }
            }
        }
        .navigationTitle("Bag")
    }
}

// MARK: - Wild Pokémon

struct WildPage: View {
    @ObservedObject private var model = WatchModel.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if model.snapshot.wild.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "leaf").font(.title3)
                        Text("No wild Pokémon right now.").font(.footnote)
                        Text("\(model.liveStepsToEncounter.formatted()) steps to the next one").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(12).frame(maxWidth: .infinity).glassCard()
                }
                ForEach(model.snapshot.wild) { w in
                    NavigationLink(value: WatchRoute.battle(w.id)) {
                        HStack(spacing: 8) {
                            WildIcon(wild: w, size: 34, hop: true)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 3) {
                                    Text(w.species.name).font(.footnote.weight(.semibold)).lineLimit(1)
                                    if w.isShiny { Text("✨").font(.caption2) }
                                }
                                Text("Lv\(w.level) · leaves \(w.expiresAt, style: .relative)")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7).padding(.horizontal, 8)
                        .glassCard(14, tint: Color(hex: 0x4CC76E))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Wild")
    }
}

struct BattlePage: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.dismiss) private var dismiss
    let wildID: String

    @State private var wild: WatchSnapshot.Wild?
    @State private var message = ""
    @State private var ball: BallKind = .poke
    @State private var busy = false
    @State private var ended = false
    @State private var caught = false
    @State private var wobble = 0.0
    @State private var showBall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ZStack {
                    if let wild, !showBall, !caught {
                        WildIcon(wild: wild, size: 56, hop: !busy)
                            .transition(.scale.combined(with: .opacity))
                    }
                    if showBall || caught {
                        ItemIcon(key: ball.itemKey).frame(width: 30, height: 30)
                            .rotationEffect(.degrees(wobble))
                            .transition(.scale)
                    }
                }
                .frame(height: 60)

                if let wild {
                    HStack(spacing: 3) {
                        Text(wild.species.name).font(.headline).lineLimit(1)
                        if wild.isShiny { Text("✨").font(.caption) }
                        Text("Lv\(wild.level)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }

                Text(message.isEmpty ? " " : message)
                    .font(.caption2).multilineTextAlignment(.center).lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .padding(6).glassCard(12)

                if ended {
                    Button { dismiss() } label: { Text(caught ? "Done" : "Back").frame(maxWidth: .infinity) }
                        .glassButton(tint: caught ? Color(hex: 0x4CC76E) : nil)
                } else {
                    ballPicker
                    HStack(spacing: 6) {
                        Button { act("berry") } label: {
                            VStack(spacing: 0) {
                                Image(systemName: "leaf.circle.fill")
                                Text("\(model.berryCount)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            }.frame(maxWidth: .infinity)
                        }
                        .glassButton(tint: Color(hex: 0x4CC76E))
                        .disabled(busy || model.berryCount == 0)

                        Button { act("ball") } label: {
                            VStack(spacing: 0) {
                                ItemIcon(key: ball.itemKey).frame(width: 18, height: 18)
                                Text("Throw").font(.system(size: 10, weight: .semibold))
                            }.frame(maxWidth: .infinity)
                        }
                        .glassButton(tint: .red)
                        .disabled(busy || model.ballCount(ball) == 0)

                        Button { act("run") } label: {
                            VStack(spacing: 0) {
                                Image(systemName: "figure.run")
                                Text("Run").font(.system(size: 10, weight: .semibold))
                            }.frame(maxWidth: .infinity)
                        }
                        .glassButton(tint: .blue)
                        .disabled(busy)
                    }
                }
            }
        }
        .navigationTitle("Wild")
        .task {
            wild = model.snapshot.wild.first { $0.id == wildID }
            pickAvailableBall()
            guard wild != nil else { message = "It's gone…"; ended = true; return }
            busy = true
            let r = await model.battle(wildID, action: "start")
            message = r.message
            if r.ended { ended = true }
            busy = false
        }
    }

    /// Owned balls as a small row; tap one to choose it.
    private var ballPicker: some View {
        let owned = BallKind.allCases.filter { model.ballCount($0) > 0 }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(owned) { k in
                    Button { ball = k; WKInterfaceDevice.current().play(.click) } label: {
                        HStack(spacing: 2) {
                            ItemIcon(key: k.itemKey).frame(width: 16, height: 16)
                            Text("\(model.ballCount(k))").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(Capsule().strokeBorder(k == ball ? Color.white : .clear, lineWidth: 1.5))
                        .glassCard(20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func pickAvailableBall() {
        if model.ballCount(ball) == 0, let k = BallKind.allCases.first(where: { model.ballCount($0) > 0 }) { ball = k }
    }

    private func act(_ action: String) {
        guard !busy else { return }
        busy = true
        WKInterfaceDevice.current().play(.click)
        Task {
            if action == "ball" {
                message = "You threw a \(ball.name)!"
                withAnimation(.spring(duration: 0.35)) { showBall = true }
            }
            let r = await model.battle(wildID, action: action, ball: action == "ball" ? ball : nil)
            if action == "ball" && !r.unreachable {
                // Wobble once per shake, like the games
                for _ in 0..<min(r.shakes, 3) {
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeInOut(duration: 0.15)) { wobble = -22 }
                    try? await Task.sleep(for: .milliseconds(160))
                    withAnimation(.easeInOut(duration: 0.15)) { wobble = 22 }
                    try? await Task.sleep(for: .milliseconds(160))
                    withAnimation(.easeInOut(duration: 0.15)) { wobble = 0 }
                    WKInterfaceDevice.current().play(.click)
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            if r.caught {
                caught = true
                WKInterfaceDevice.current().play(.success)
            } else {
                withAnimation(.spring(duration: 0.35)) { showBall = false }
                if r.ended { WKInterfaceDevice.current().play(.failure) }
            }
            message = r.message
            ended = r.ended
            pickAvailableBall()
            busy = false
        }
    }
}

// MARK: - Map

/// Where you are, with your buddy in a circle — a small version of the phone's map, with today's route.
struct WatchMapPage: View {
    @ObservedObject private var model = WatchModel.shared
    @StateObject private var locator = WatchLocator()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $position) {
            ForEach(Array(model.snapshot.trail.enumerated()), id: \.offset) { _, seg in
                MapPolyline(coordinates: Self.coords(seg.coords))
                    .stroke(seg.drive ? Color(hex: 0xE05A4F) : Color(hex: 0x3FB8AF),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let here = locator.location?.coordinate ?? phoneCoordinate {
                Annotation("", coordinate: here, anchor: .center) { BuddyMarker() }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .navigationTitle("Map")
        .onAppear {
            locator.start()
            if let c = phoneCoordinate, locator.location == nil {
                position = .camera(MapCamera(centerCoordinate: c, distance: 600))
            }
        }
        .onDisappear { locator.stop() }
        .onChange(of: locator.location) { _, loc in
            guard let loc else { return }
            withAnimation { position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 600)) }
        }
    }

    private var phoneCoordinate: CLLocationCoordinate2D? {
        guard let lat = model.snapshot.latitude, let lon = model.snapshot.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static func coords(_ flat: [Double]) -> [CLLocationCoordinate2D] {
        stride(from: 0, to: flat.count - 1, by: 2).map { CLLocationCoordinate2D(latitude: flat[$0], longitude: flat[$0 + 1]) }
    }
}

/// Your buddy's box icon in a glassy circle, like on the phone's map.
struct BuddyMarker: View {
    @ObservedObject private var model = WatchModel.shared

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(.white, lineWidth: 2)
            if let buddy = model.snapshot.buddy {
                BoxIcon(speciesID: buddy.speciesID, shiny: buddy.isShiny)
                    .id("\(buddy.speciesID)-\(buddy.isShiny)-\(model.spriteVersion)")
                    .padding(5)
            } else {
                Image(systemName: "figure.walk").foregroundStyle(.white)
            }
        }
        .frame(width: 38, height: 38)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }
}

/// The watch's own location while the map is open (falls back to the phone's last position).
@MainActor
final class WatchLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy > 0, loc.horizontalAccuracy < 100 else { return }
        Task { @MainActor in self.location = loc }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Sprites

/// Box icon that hops while you're looking at it (stays still in always-on mode).
struct HoppingIcon: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    let member: WatchSnapshot.Member
    var size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let up = !dimmed && Self.hopUp(ctx.date)
            BoxIcon(speciesID: member.speciesID, shiny: member.isShiny)
                .id("\(member.speciesID)-\(member.isShiny)-\(model.spriteVersion)")
                .frame(width: size, height: size)
                .offset(y: up ? -size * 0.08 : 0)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) { if member.heldItem != nil { HeldDot(size: max(7, size * 0.22)) } }
    }

    /// Up for a quarter second, down for a quarter second. Worked out in Double on purpose:
    /// the watch is 32-bit, so turning "seconds since 2001 ÷ 0.25" into an Int overflows and crashes.
    static func hopUp(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.5) < 0.25
    }
}

struct WildIcon: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    let wild: WatchSnapshot.Wild
    var size: CGFloat
    var hop: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let up = hop && !dimmed && HoppingIcon.hopUp(ctx.date)
            BoxIcon(speciesID: wild.speciesID, shiny: wild.isShiny)
                .id("\(wild.speciesID)-\(wild.isShiny)-\(model.spriteVersion)")
                .frame(width: size, height: size)
                .offset(y: up ? -size * 0.08 : 0)
        }
        .frame(width: size, height: size)
    }
}

/// Cropped box icon (shiny when it's shiny).
struct BoxIcon: View {
    let speciesID: Int
    var shiny = false

    var body: some View {
        if let image = LocalIcon.trimmedImage(for: speciesID, shiny: shiny) {
            image.resizable().interpolation(.none).scaledToFit()
        } else {
            Image(systemName: "circle.dashed").resizable().scaledToFit().padding(6).foregroundStyle(.secondary)
        }
    }
}

struct ItemIcon: View {
    let key: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else if let ball = BallKind.allCases.first(where: { $0.itemKey == key }) {
                BallGlyph(kind: ball)
            } else {
                Image(systemName: "shippingbox.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(2)
            }
        }
        .task(id: key) {
            let file = SharedStore.itemFile(key)
            if let ui = UIImage(contentsOfFile: file.path) { image = ui; return }
            if await SharedStore.fetch(SharedStore.remoteItemURL(key), to: file) != nil {
                image = UIImage(contentsOfFile: file.path)
            }
        }
    }
}

/// Full animated Gen 5 sprite for the summary (falls back to the box icon).
struct WatchAnimatedSprite: View {
    let speciesID: Int
    let shiny: Bool
    @Environment(\.isLuminanceReduced) private var dimmed
    @State private var frames: [(image: UIImage, delay: Double)] = []

    var body: some View {
        Group {
            if frames.isEmpty {
                BoxIcon(speciesID: speciesID, shiny: shiny)
            } else if frames.count == 1 || dimmed {
                pixel(frames[0].image)
            } else {
                let total = frames.reduce(0) { $0 + $1.delay }
                TimelineView(.animation(minimumInterval: 0.05)) { ctx in
                    pixel(frame(at: ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)))
                }
            }
        }
        .task(id: "\(speciesID)-\(shiny)") {
            guard let remote = SharedStore.remoteFrontURL(speciesID, shiny: shiny),
                  let file = await SharedStore.fetch(remote, to: SharedStore.frontFile(speciesID, shiny: shiny)) else { return }
            frames = await Task.detached { Self.decode(file) }.value
        }
    }

    private func pixel(_ ui: UIImage) -> some View {
        Image(uiImage: ui).resizable().interpolation(.none).scaledToFit()
    }

    private func frame(at t: Double) -> UIImage {
        var acc = 0.0
        for f in frames { acc += f.delay; if t < acc { return f.image } }
        return frames[frames.count - 1].image
    }

    nonisolated static func decode(_ url: URL) -> [(image: UIImage, delay: Double)] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        return (0..<CGImageSourceGetCount(src)).compactMap { i in
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { return nil }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            return (UIImage(cgImage: cg), d < 0.02 ? 0.1 : d)
        }
    }
}

/// Red "holding an item" dot.
struct HeldDot: View {
    var size: CGFloat = 11
    var body: some View {
        Circle().fill(Color.red).overlay(Circle().stroke(.black, lineWidth: 1.5)).frame(width: size, height: size)
    }
}

// MARK: - Background & Liquid Glass

/// A blurred map of where you are, behind every screen (from your iPhone's last location).
struct WatchBackdrop: View {
    @ObservedObject private var model = WatchModel.shared

    var body: some View {
        ZStack {
            if let lat = model.snapshot.latitude, let lon = model.snapshot.longitude {
                let c = CLLocationCoordinate2D(latitude: (lat * 2000).rounded() / 2000, longitude: (lon * 2000).rounded() / 2000)
                Map(initialPosition: .camera(MapCamera(centerCoordinate: c, distance: 700, heading: 0, pitch: 0)),
                    interactionModes: [])
                    .id("\(c.latitude),\(c.longitude)")
                    .blur(radius: 7)
                    .allowsHitTesting(false)
            } else {
                LinearGradient(colors: [Color(hex: 0x1F4E46), Color(hex: 0x0C1F1C)], startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func watchBackdrop() -> some View {
        containerBackground(for: .navigation) { WatchBackdrop() }
    }

    @ViewBuilder func glassCard(_ radius: CGFloat = 16, tint: Color? = nil) -> some View {
        if #available(watchOS 26.0, *) {
            self.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.3)) } ?? .regular, in: .rect(cornerRadius: radius))
        } else {
            self.background(RoundedRectangle(cornerRadius: radius).fill(.ultraThinMaterial))
        }
    }

    @ViewBuilder func glassButton(tint: Color? = nil) -> some View {
        if #available(watchOS 26.0, *) {
            self.buttonStyle(.glass).tint(tint)
        } else {
            self.buttonStyle(.bordered).tint(tint)
        }
    }
}
