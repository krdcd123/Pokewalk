import Foundation

/// The playable protagonists from Red/Blue through Emerald.
struct TrainerStyle: Identifiable, Hashable {
    let id: String              // file-name key: Sprites/trainers/<id>-walk.gif, <id>-card.png, <id>-head.gif
    let name: String
    let game: String
    let showdownKey: String     // fallback battle sprite from Pokémon Showdown's sprite server
    let cardHex: UInt32         // accent for the trainer card

    static let all: [TrainerStyle] = [
        .init(id: "red", name: "Red", game: "FireRed & LeafGreen", showdownKey: "red-gen3", cardHex: 0xE04A3F),
        .init(id: "leaf", name: "Leaf", game: "FireRed & LeafGreen", showdownKey: "leaf-gen3", cardHex: 0x3FAE5A),
        .init(id: "gold", name: "Gold", game: "Gold & Silver", showdownKey: "ethan-gen2", cardHex: 0xE0A93F),
        .init(id: "kris", name: "Kris", game: "Crystal", showdownKey: "kris-gen2", cardHex: 0x3D9BE0),
        .init(id: "brendan", name: "Brendan", game: "Ruby, Sapphire & Emerald", showdownKey: "brendan-gen3", cardHex: 0x3FAE5A),
        .init(id: "may", name: "May", game: "Ruby, Sapphire & Emerald", showdownKey: "may-gen3", cardHex: 0xE0577A),
    ]

    static func style(_ id: String?) -> TrainerStyle { all.first { $0.id == id } ?? all[4] }

    var remoteSpriteURL: URL { URL(string: "https://play.pokemonshowdown.com/sprites/trainers/\(showdownKey).png")! }
}
