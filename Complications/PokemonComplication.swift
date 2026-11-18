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
}

struct PokemonQuery: EntityQuery {
    private var all: [PokemonEntity] {
        let party = SharedStore.loadSnapshot()?.party ?? []
        return [.walkingBuddy] + party.map { PokemonEntity(id: $0.id, name: $0.name) }
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
                                     exp: GrowthRate.mediumFast.exp(forLevel: 12) + 600, isBuddy: true, canEvolve: false)
        return PokemonEntry(date: .now, member: m, live: LiveMember(m, stepsSinceSync: 420, multiplier: 1),
                            stepsSinceSync: 420, stepsToEncounter: 188)
    }()
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PokemonEntry { .placeholder }

    func snapshot(for configuration: TrackPokemonIntent, in context: Context) async -> PokemonEntry {
        if context.isPreview && SharedStore.loadSnapshot() == nil { return .placeholder }
        return await entry(for: configuration)
    }

    func timeline(for configuration: TrackPokemonIntent, in context: Context) async -> Timeline<PokemonEntry> {
        let e = await entry(for: configuration)
        return Timeline(entries: [e], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    /// watchOS has no complication config UI: each recommendation appears as its own option in the face editor.
    func recommendations() -> [AppIntentRecommendation<TrackPokemonIntent>] {
        let party = SharedStore.loadSnapshot()?.party ?? []
        var recs = [AppIntentRecommendation(intent: TrackPokemonIntent(pokemon: .walkingBuddy),
                                            description: Text("Walking Buddy"))]
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

        let live = member.map { LiveMember($0, stepsSinceSync: steps, multiplier: snap.expMultiplier) }
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
                switch family {
                case .accessoryCircular: circular(member, live)
                case .accessoryRectangular: rectangular(member, live)
                case .accessoryCorner: corner(member, live)
                case .accessoryInline: inline(member, live)
                default: circular(member, live)
                }
            } else {
                Image(systemName: "figure.walk.circle")
                    .font(.title2)
                    .widgetLabel { Text("Open PokéWalk") }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private func sprite(_ id: Int) -> some View {
        if let image = LocalIcon.image(for: id) {
            image.resizable().interpolation(.none).widgetAccentedRenderingMode(.fullColor).scaledToFit()
        } else {
            Image(systemName: "circle.circle.fill").resizable().scaledToFit().padding(3)
        }
    }

    private func circular(_ m: WatchSnapshot.Member, _ live: LiveMember) -> some View {
        Gauge(value: live.progress) {
            Text("Lv")
        } currentValueLabel: {
            VStack(spacing: -2) {
                sprite(m.speciesID).frame(width: 30, height: 23)
                Text("\(live.level)").font(.system(size: 11, weight: .bold, design: .rounded))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private func rectangular(_ m: WatchSnapshot.Member, _ live: LiveMember) -> some View {
        HStack(spacing: 6) {
            sprite(m.speciesID).frame(width: 44, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(m.name).font(.headline).lineLimit(1).widgetAccentable()
                    Spacer(minLength: 0)
                    Text("Lv\(live.level)").font(.system(.body, design: .rounded).weight(.semibold))
                }
                ProgressView(value: live.progress).tint(Color(m.species.primaryType))
                Group {
                    if live.readyToEvolve {
                        Text("✨ Ready to evolve!")
                    } else if m.isBuddy {
                        Text("\(entry.stepsToEncounter) steps to encounter")
                    } else {
                        Text("\(live.expToNext.formatted()) Exp to Lv\(min(live.level + 1, 100))")
                    }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
    }
}
