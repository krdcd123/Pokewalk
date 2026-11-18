import Foundation

/// The playable protagonists from Red/Blue through Emerald.
struct TrainerStyle: Identifiable, Hashable {
    enum Sheet: Hashable {
        case gen3                 // 9 frames, 16×32, background = top-left pixel colour
        case gbc(accent: UInt32)  // 6 frames, 16×16 greyscale; coloured with the Game Boy Color palette
    }

    let id: String              // file-name key: Sprites/trainers/<id>-walk.gif, <id>-card.png
    let name: String
    let game: String
    let showdownKey: String     // full battle sprite (trainer card) from Pokémon Showdown's sprite server
    let overworldPath: String   // walking sprite sheet from the pret decompilation projects on GitHub
    let sheet: Sheet
    let cardHex: UInt32

    static let all: [TrainerStyle] = [
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

    static func style(_ id: String?) -> TrainerStyle { all.first { $0.id == id } ?? all[4] }

    var remoteSpriteURL: URL { URL(string: "https://play.pokemonshowdown.com/sprites/trainers/\(showdownKey).png")! }
    var overworldURL: URL { URL(string: "https://raw.githubusercontent.com/\(overworldPath)")! }
}
