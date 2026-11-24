import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Which Pokémon a complication tracks

struct PokemonEntity: AppEntity {
    static let buddyID = "buddy"

    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Pokémon"
    static var defaultQuery = PokemonQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static let walkingBuddy = PokemonEntity(id: buddyID, name: "Walking Buddy")
    static let partyID = "party"
    static let wholeParty = PokemonEntity(id: partyID, name: "Whole Party")
    static let partyNoBuddyID = "party-nobuddy"
    static let partyNoBuddy = PokemonEntity(id: partyNoBuddyID, name: "Party (not buddy)")
}

struct PokemonQuery: EntityQuery {
    private var all: [PokemonEntity] {
        let party = SharedStore.loadSnapshot()?.party ?? []
        return [.walkingBuddy, .wholeParty, .partyNoBuddy] + party.map { PokemonEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [PokemonEntity] {
        let known = all
        return identifiers.map { id in known.first { $0.id == id } ?? PokemonEntity(id: id, name: "Pokémon") }
    }

    func suggestedEntities() async throws -> [PokemonEntity] { all }
    func defaultResult() async -> PokemonEntity? { .walkingBuddy }
}

struct TrackPokemonIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Track Pokémon"
    static var description = IntentDescription("Choose which Pokémon this complication follows.")

    @Parameter(title: "Pokémon")
    var pokemon: PokemonEntity?

    init() {}
    init(pokemon: PokemonEntity) { self.pokemon = pokemon }
}

// MARK: - Timeline

struct PokemonEntry: TimelineEntry {
    let date: Date
    let member: WatchSnapshot.Member?
    let live: LiveMember?
    let stepsSinceSync: Int
    let stepsToEncounter: Int

    static let placeholder: PokemonEntry = {
        let m = WatchSnapshot.Member(id: "preview", speciesID: 25, name: "Pikachu",
                                     exp: GrowthRate.mediumFast.exp(forLevel: 12) + 600, isBuddy: true, canEvolve: false,
                                     heldItem: "candy-s")
        return PokemonEntry(date: .now, member: m, live: LiveMember(m, stepsSinceSync: 420, expPerStep: 0.25, partyShare: 0.2),
                            stepsSinceSync: 420, stepsToEncounter: 188)
    }()
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PokemonEntry { .placeholder }

    func snapshot(for configuration: TrackPokemonIntent, in context: Context) async -> PokemonEntry {
        if context.isPreview && SharedStore.loadSnapshot() == nil { return .placeholder }
        return await entry(for: configuration)
    }

    /// Seconds each party member stays on screen in "Whole Party" mode.
    static let partyCycle: TimeInterval = 60

    func timeline(for configuration: TrackPokemonIntent, in context: Context) async -> Timeline<PokemonEntry> {
        let e = await entry(for: configuration)
        let mode = configuration.pokemon?.id
        guard mode == PokemonEntity.partyID || mode == PokemonEntity.partyNoBuddyID,
              let snap = SharedStore.loadSnapshot() else {
            return Timeline(entries: [e], policy: .after(.now.addingTimeInterval(15 * 60)))
        }
        var members = snap.party
        if mode == PokemonEntity.partyNoBuddyID, members.count > 1 { members.removeAll { $0.isBuddy } }
        guard members.count > 1 else {
            let m = members.first
            return Timeline(entries: [PokemonEntry(date: .now, member: m, live: m.map { LiveMember($0, in: snap, stepsSinceSync: e.stepsSinceSync) },
                                                   stepsSinceSync: e.stepsSinceSync, stepsToEncounter: e.stepsToEncounter)],
                            policy: .after(.now.addingTimeInterval(15 * 60)))
        }
        // Whole Party: plan the next 15 minutes, a new member every minute (fades between them).
        // Lined up to the clock so every face showing it changes together.
        let start = Date(timeIntervalSinceReferenceDate:
                            (Date.now.timeIntervalSinceReferenceDate / Self.partyCycle).rounded(.down) * Self.partyCycle)
        let first = Int(((start.timeIntervalSinceReferenceDate / Self.partyCycle)
                            .truncatingRemainder(dividingBy: Double(members.count))).rounded(.down))
        let entries = (0..<15).map { i -> PokemonEntry in
            let m = members[(first + i) % members.count]
            return PokemonEntry(date: start.addingTimeInterval(Double(i) * Self.partyCycle), member: m,
                                live: LiveMember(m, in: snap, stepsSinceSync: e.stepsSinceSync),
                                stepsSinceSync: e.stepsSinceSync, stepsToEncounter: e.stepsToEncounter)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// watchOS has no complication config UI: each recommendation appears as its own option in the face editor.
    func recommendations() -> [AppIntentRecommendation<TrackPokemonIntent>] {
        let party = SharedStore.loadSnapshot()?.party ?? []
        var recs = [AppIntentRecommendation(intent: TrackPokemonIntent(pokemon: .walkingBuddy),
                                            description: Text("Walking Buddy"))]
        // Always offered (even before the watch has your party), so they show up in the face editor.
        recs.append(AppIntentRecommendation(intent: TrackPokemonIntent(pokemon: .wholeParty),
                                            description: Text("Whole Party")))
        recs.append(AppIntentRecommendation(intent: TrackPokemonIntent(pokemon: .partyNoBuddy),
                                            description: Text("Party (not buddy)")))
        recs += party.map {
            AppIntentRecommendation(intent: TrackPokemonIntent(pokemon: PokemonEntity(id: $0.id, name: $0.name)),
                                    description: Text($0.name))
        }
        return recs
    }

    private func entry(for configuration: TrackPokemonIntent) async -> PokemonEntry {
        guard let snap = SharedStore.loadSnapshot(), !snap.party.isEmpty else {
            return PokemonEntry(date: .now, member: nil, live: nil, stepsSinceSync: 0, stepsToEncounter: 0)
        }
        let wanted = configuration.pokemon?.id ?? PokemonEntity.buddyID
        let member = wanted == PokemonEntity.buddyID
            ? snap.buddy
            : (snap.party.first { $0.id == wanted } ?? snap.buddy)

        // Prefer a fresh HealthKit read; fall back to what the watch app cached in the background.
        let cached = SharedStore.cachedLiveSteps(forSync: snap.syncDate)
        let fresh = (try? await StepCounter.shared.steps(from: snap.syncDate)) ?? 0
        let steps = max(cached, fresh)

        let live = member.map { LiveMember($0, in: snap, stepsSinceSync: steps) }
        return PokemonEntry(date: .now, member: member, live: live, stepsSinceSync: steps,
                            stepsToEncounter: max(0, snap.stepsToEncounter - steps))
    }
}

// MARK: - Views

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PokemonEntry

    var body: some View {
        Group {
            if let member = entry.member, let live = entry.live {
                Group {
                    switch family {
                    case .accessoryCircular: circular(member, live)
                    case .accessoryRectangular: rectangular(member, live)
                    case .accessoryCorner: corner(member, live)
                    case .accessoryInline: inline(member, live)
                    default: circular(member, live)
                    }
                }
                .id(member.id)                       // a different member → cross-fade
                .transition(.opacity)
                .widgetURL(URL(string: "pokewalk://summary/\(member.id)"))    // tap → its summary in the watch app
            } else {
                Image(systemName: "figure.walk.circle")
                    .font(.title2)
                    .widgetLabel { Text("Open PokéWalk") }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private func sprite(_ id: Int) -> some View {
        if let image = LocalIcon.image(for: id, shiny: entry.member?.isShiny ?? false) {
            image.resizable().interpolation(.none).widgetAccentedRenderingMode(.fullColor).scaledToFit()
        } else {
            Image(systemName: "circle.circle.fill").resizable().scaledToFit().padding(3)
        }
    }

    /// Cropped to the Pokémon so it fills the slot.
    @ViewBuilder private func bigSprite(_ id: Int) -> some View {
        if let image = LocalIcon.trimmedImage(for: id, shiny: entry.member?.isShiny ?? false) {
            image.resizable().interpolation(.none).widgetAccentedRenderingMode(.fullColor).scaledToFit()
        } else {
            sprite(id)
        }
    }

    /// Small round slot: the Pokémon inside a blue Exp ring, with its level underneath.
    private func circular(_ m: WatchSnapshot.Member, _ live: LiveMember) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, live.progress))
                .stroke(Color(hex: 0x4FA3F7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: -1) {
                bigSprite(m.speciesID).frame(width: 30, height: 24)
                Text("Lv\(live.level)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            .padding(.top, 2)
            if m.heldItem != nil {
                Circle().fill(Color.red).overlay(Circle().stroke(.black, lineWidth: 1))
                    .frame(width: 8, height: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
            }
        }
        .padding(1)
    }

    /// Large middle slot: party box icon, name, level and an Exp bar, like the party screen in the games.
    /// A red dot on the icon means it's holding something to take on the phone.
    private func rectangular(_ m: WatchSnapshot.Member, _ live: LiveMember) -> some View {
        HStack(spacing: 8) {
            bigSprite(m.speciesID)
                .frame(width: 50, height: 50)
                .overlay(alignment: .topTrailing) {
                    if m.heldItem != nil {
                        Circle().fill(Color.red)
                            .overlay(Circle().stroke(.black, lineWidth: 1.5))
                            .frame(width: 11, height: 11)
                            .offset(x: 1, y: -1)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.name).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1).widgetAccentable()
                    Spacer(minLength: 0)
                    Text("Lv\(live.level)").font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                ExpBar(progress: live.progress, tint: Color(hex: 0x4FD1C5), height: 6)
                Text(live.readyToEvolve ? "Ready to evolve!" : "\(live.stepsToNext.formatted()) steps to next")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }


    private func corner(_ m: WatchSnapshot.Member, _ live: LiveMember) -> some View {
        sprite(m.speciesID)
            .padding(2)
            .widgetLabel {
                Gauge(value: live.progress) {
                    Text(m.name)
                } currentValueLabel: {
                    Text("\(live.level)")
                } minimumValueLabel: {
                    Text("\(live.level)")
                } maximumValueLabel: {
                    Text("\(min(live.level + 1, 100))")
                }
                .tint(Color(m.species.primaryType))
            }
    }

    private func inline(_ m: WatchSnapshot.Member, _ live: LiveMember) -> some View {
        Text("\(m.name) Lv\(live.level) · \(Int(live.progress * 100))%")
    }
}


// MARK: - Widget

struct PokemonComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PokemonComplication", intent: TrackPokemonIntent.self, provider: Provider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("PokéWalk")
        .description("Track a Pokémon's level and Exp as you walk.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct PokeWalkComplications: WidgetBundle {
    var body: some Widget {
        PokemonComplication()
        WorkoutShortcut()
    }
}

// MARK: - Workout shortcut: tap to open PokéWalk's workout list on the watch

struct WorkoutShortcutEntry: TimelineEntry { let date: Date }

struct WorkoutShortcutProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutShortcutEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (WorkoutShortcutEntry) -> Void) { completion(.init(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutShortcutEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now)], policy: .never))
    }
}

struct WorkoutShortcutView: View {
    @Environment(\.widgetFamily) private var family
    private let green = Color(red: 0.61, green: 0.88, blue: 0.36)

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner:
                Image(systemName: "figure.run").font(.system(size: 22, weight: .semibold))
                    .widgetLabel("Workout")
            case .accessoryInline:
                Label("Start workout", systemImage: "figure.run")
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "figure.run").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(green)
                        .widgetAccentable()
                }
            }
        }
        .widgetURL(URL(string: "pokewalk://workouts"))
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WorkoutShortcut: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorkoutShortcut", provider: WorkoutShortcutProvider()) { _ in
            WorkoutShortcutView()
        }
        .configurationDisplayName("PokéWalk Workout")
        .description("Tap to start a workout.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}
