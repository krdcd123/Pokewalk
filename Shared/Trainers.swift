import Foundation

/// The playable protagonists from Red/Blue through Emerald.
struct TrainerStyle: Identifiable, Hashable {
    enum Sheet: Hashable {
        case gen3                 // 9 frames, 16×32, background = top-left pixel colour
        case gbc(accent: UInt32)  // 6 frames, 16×16 greyscale; coloured with the Game Boy Color palette
        case gb                   // same layout, left in the original Game Boy black and white
    }

    /// Game Boy trainers (Red from Red/Blue/Yellow, Gold, Kris): Gen 1/2 battle graphics.
    var isGameBoy: Bool { if case .gen3 = sheet { return false }; return true }

    let id: String              // file-name key: Sprites/trainers/<id>-walk.gif, <id>-card.png
    let name: String
    let game: String
    let showdownKey: String     // full battle sprite (trainer card) from Pokémon Showdown's sprite server
    let overworldPath: String   // walking sprite sheet from the pret decompilation projects on GitHub
    let sheet: Sheet
    let cardHex: UInt32

    static let all: [TrainerStyle] = [
        .init(id: "red1", name: "Red", game: "Red, Blue & Yellow", showdownKey: "red-gen1",
              overworldPath: "pret/pokered/master/gfx/sprites/red.png", sheet: .gb, cardHex: 0x8A8A8A),
        .init(id: "red", name: "Red", game: "FireRed & LeafGreen", showdownKey: "red-gen3",
              overworldPath: "pret/pokefirered/master/graphics/object_events/pics/people/red_normal.png", sheet: .gen3, cardHex: 0xE04A3F),
        .init(id: "leaf", name: "Leaf", game: "FireRed & LeafGreen", showdownKey: "leaf-gen3",
              overworldPath: "pret/pokefirered/master/graphics/object_events/pics/people/green_normal.png", sheet: .gen3, cardHex: 0x3FAE5A),
        .init(id: "gold", name: "Gold", game: "Gold & Silver", showdownKey: "ethan-gen2",
              overworldPath: "pret/pokecrystal/master/gfx/sprites/chris.png", sheet: .gbc(accent: 0xFF3A08), cardHex: 0xE0A93F),
        .init(id: "kris", name: "Kris", game: "Crystal", showdownKey: "kris-gen2",
              overworldPath: "pret/pokecrystal/master/gfx/sprites/kris.png", sheet: .gbc(accent: 0x524AFF), cardHex: 0x3D9BE0),
        .init(id: "brendan", name: "Brendan", game: "Ruby, Sapphire & Emerald", showdownKey: "brendan-gen3",
              overworldPath: "pret/pokeemerald/master/graphics/object_events/pics/people/brendan/walking.png", sheet: .gen3, cardHex: 0x3FAE5A),
        .init(id: "may", name: "May", game: "Ruby, Sapphire & Emerald", showdownKey: "may-gen3",
              overworldPath: "pret/pokeemerald/master/graphics/object_events/pics/people/may/walking.png", sheet: .gen3, cardHex: 0xE0577A),
    ]

    static func style(_ id: String?) -> TrainerStyle { all.first { $0.id == id } ?? all.first { $0.id == "brendan" }! }

    var remoteSpriteURL: URL { URL(string: "https://play.pokemonshowdown.com/sprites/trainers/\(showdownKey).png")! }
    var overworldURL: URL { URL(string: "https://raw.githubusercontent.com/\(overworldPath)")! }

    /// Bike sprite sheet from the same game (Mach Bike in Emerald, bike in FireRed/LeafGreen and Crystal).
    var bikePath: String {
        overworldPath
            .replacingOccurrences(of: "_normal.png", with: "_bike.png")       // red_normal → red_bike
            .replacingOccurrences(of: "walking.png", with: "mach_bike.png")   // brendan/may
            .replacingOccurrences(of: "chris.png", with: "chris_bike.png")
            .replacingOccurrences(of: "sprites/red.png", with: "sprites/red_bike.png")
            .replacingOccurrences(of: "kris.png", with: "kris_bike.png")
    }
    var bikeURL: URL { URL(string: "https://raw.githubusercontent.com/\(bikePath)")! }

    /// Battle back sprite (frames stacked vertically): Emerald's for the Gen 3 trainers, Crystal's for Gold/Kris.
    var backPicURL: URL {
        switch id {
        case "gold": return URL(string: "https://raw.githubusercontent.com/pret/pokecrystal/master/gfx/player/chris_back.png")!
        case "kris": return URL(string: "https://raw.githubusercontent.com/pret/pokecrystal/master/gfx/player/kris_back.png")!
        case "red1": return URL(string: "https://raw.githubusercontent.com/pret/pokered/master/gfx/player/redb.png")!
        default: return URL(string: "https://raw.githubusercontent.com/pret/pokeemerald/master/graphics/trainers/back_pics/\(id).png")!
        }
    }

    /// Back sprite frame shown while standing in battle.
    var backIdleFrame: Int { id == "brendan" || id == "may" ? 3 : 0 }

    /// The ball-throwing animation from Emerald's back_pic_anims (frame, seconds) and when the ball leaves the hand.
    /// Gold and Kris only have one back frame (Gen 2 had no throwing animation).
    var backThrow: (frames: [(Int, Double)], release: Double) {
        switch id {
        case "brendan", "may": return ([(0, 0.40), (1, 0.15), (2, 0.40), (0, 0.15), (3, 0)], 0.55)
        case "red", "leaf": return ([(1, 0.33), (2, 0.10), (3, 0.10), (4, 0.40), (0, 0)], 0.43)
        default: return ([], 0.1)
        }
    }
}
