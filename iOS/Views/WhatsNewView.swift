import SwiftUI

/// "What's new" — shown once, the first time you open PokéWalk after an update.
/// Add an entry at the top of `notes` with every update (keyed by the TestFlight build number).
enum WhatsNew {
    struct Note { let build: Int; let items: [String] }

    static let notes: [Note] = [
        Note(build: 205, items: [
            "While something's being built on the Ranch, the ranch blurs and Machokes carry boxes across it.",
            "Your ranchers are busy helping build, so shifts can't start until the work is finished.",
        ]),
        Note(build: 204, items: [
            "Fixed red \"drive\" lines appearing while you're sat at home — GPS wandering indoors no longer counts as a journey, and the stray lines are cleaned up.",
        ]),
        Note(build: 203, items: [
            "The Daycare and Contest Hall stay hidden until your Ranch is ready for them, then pop up with a message (on the watch too).",
        ]),
        Note(build: 202, items: [
            "Catching is harder: no more free catch bonus, and higher-level Pokémon are tougher to catch. Great and Ultra Balls really matter now.",
            "Wild Pokémon flee more often, especially rare ones — berries still calm them down.",
            "Fewer free balls: a Poké Ball every 2,500 steps (was 1,000), and smaller ball rewards from stamps, achievements and item finds.",
        ]),
        Note(build: 201, items: [
            "The music card on the map now shows where you are (street and area) in big text, with the song playing underneath. Tap it to play or mute music as before.",
        ]),
        Note(build: 200, items: [
            "The map turns as you walk: in a straight line, the way you're heading is always up the screen.",
            "Tap the compass to put north back at the top (it stays that way until you tap the location button). Switch the turning off in Settings › Walking.",
        ]),
        Note(build: 198, items: [
            "A \"What's new\" popup like this one after every update.",
        ]),
        Note(build: 197, items: [
            "Trains, buses and cars: GPS stays on in a vehicle, so the red line keeps going — even with no signal or through tunnels.",
            "Better battery life and less heat: saving, backups, the map line and the hop animations do far less work. Nothing removed.",
        ]),
        Note(build: 196, items: [
            "Battle Frontier moved to the Menu once you're Champion, with a popup when it unlocks.",
            "The Contest Hall now has to be built on the Ranch (plus Deluxe Blender and Grand Stage upgrades).",
        ]),
    ]

    static var currentBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }
    private static let seenKey = "whatsNewSeenBuild"

    /// Notes you haven't seen yet (nil on a brand-new install, or when there's nothing new).
    static func pending(hasGame: Bool) -> [Note]? {
        let current = currentBuild
        guard current > 0 else { return nil }
        let seen = UserDefaults.standard.integer(forKey: seenKey)
        if !hasGame && seen == 0 { markSeen(); return nil }          // first install: nothing to announce
        guard seen < current else { return nil }
        // Before this popup existed nothing was recorded: show just the latest few updates
        let from = seen == 0 ? current - 2 : seen
        let new = notes.filter { $0.build > from && $0.build <= current }
        if new.isEmpty { markSeen(); return nil }
        return new
    }

    static func markSeen() { UserDefaults.standard.set(currentBuild, forKey: seenKey) }
}

struct WhatsNewView: View {
    let notes: [WhatsNew.Note]
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 24, weight: .bold)).foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's new").font(.rounded(24, .black)).foregroundStyle(.white)
                    Text("Build \(WhatsNew.currentBuild)").font(.rounded(12, .heavy)).foregroundStyle(Theme.inkSoft)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(notes, id: \.build) { note in
                        if notes.count > 1 {
                            Text("Build \(note.build)").font(.rounded(12, .heavy)).foregroundStyle(Theme.tealDark)
                        }
                        ForEach(note.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(Theme.teal).frame(width: 7, height: 7).padding(.top, 6)
                                Text(item).font(.rounded(15, .bold)).foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            Button {
                SoundKit.shared.play(.select)
                done()
            } label: {
                Text("Got it").font(.rounded(17, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .glassCapsule(tint: Theme.teal, interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }
}
