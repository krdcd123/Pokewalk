import Foundation

/// Secret Base decorations from Emerald, for furnishing the ranch house. Furniture is drawn with the Secret
/// Base metatiles (`tiles`, w×h, left to right, top to bottom); dolls and cushions are sprites.
struct RanchDecor: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case desk, chair, plant, ornament, mat, poster, doll, cushion
        var id: String { rawValue }
        var name: String { rawValue == "desk" ? "Desks" : rawValue.capitalized + "s" }
        var symbol: String {
            switch self {
            case .desk: return "table.furniture.fill"
            case .chair: return "chair.fill"
            case .plant: return "leaf.fill"
            case .ornament: return "star.fill"
            case .mat: return "rectangle.fill"
            case .poster: return "photo.fill"
            case .doll: return "teddybear.fill"
            case .cushion: return "square.fill"
            }
        }
    }
    /// solid/pass/behind sit on the floor, wall goes on the back wall, sprite is a doll or cushion.
    enum Placement: String { case solid, pass, behind, wall, sprite }

    let key: String
    let name: String
    let category: Category
    let placement: Placement
    let w: Int
    let h: Int
    let price: Int
    let tiles: [Int]
    let sprite: String?
    var id: String { key }

    static func find(_ key: String) -> RanchDecor? { byKey[key] }
    private static let byKey: [String: RanchDecor] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    static let all: [RanchDecor] = [
        .init(key: "small_desk", name: "Small Desk", category: .desk, placement: .solid, w: 1, h: 1, price: 3000, tiles: [0x287], sprite: nil),
        .init(key: "pokemon_desk", name: "Pokémon Desk", category: .desk, placement: .solid, w: 1, h: 1, price: 3000, tiles: [0x28F], sprite: nil),
        .init(key: "heavy_desk", name: "Heavy Desk", category: .desk, placement: .solid, w: 3, h: 2, price: 6000, tiles: [0x290, 0x291, 0x292, 0x298, 0x299, 0x29A], sprite: nil),
        .init(key: "ragged_desk", name: "Ragged Desk", category: .desk, placement: .solid, w: 3, h: 2, price: 6000, tiles: [0x293, 0x294, 0x295, 0x29B, 0x29C, 0x29D], sprite: nil),
        .init(key: "comfort_desk", name: "Comfort Desk", category: .desk, placement: .solid, w: 3, h: 2, price: 6000, tiles: [0x296, 0x297, 0x2A3, 0x29E, 0x29F, 0x2AB], sprite: nil),
        .init(key: "pretty_desk", name: "Pretty Desk", category: .desk, placement: .solid, w: 3, h: 3, price: 9000, tiles: [0x2BD, 0x2BE, 0x2BF, 0x2C5, 0x2C6, 0x2C7, 0x2CD, 0x2CE, 0x2CF], sprite: nil),
        .init(key: "brick_desk", name: "Brick Desk", category: .desk, placement: .solid, w: 3, h: 3, price: 9000, tiles: [0x2A0, 0x2A1, 0x2A2, 0x2A8, 0x2A9, 0x2AA, 0x2B0, 0x2B1, 0x2B2], sprite: nil),
        .init(key: "camp_desk", name: "Camp Desk", category: .desk, placement: .solid, w: 3, h: 3, price: 9000, tiles: [0x2A4, 0x2A5, 0x2A6, 0x2AC, 0x2AD, 0x2AE, 0x2B4, 0x2B5, 0x2B6], sprite: nil),
        .init(key: "hard_desk", name: "Hard Desk", category: .desk, placement: .solid, w: 3, h: 3, price: 9000, tiles: [0x2A7, 0x2BB, 0x2BC, 0x2AF, 0x2C3, 0x2C4, 0x2B7, 0x2CB, 0x2CC], sprite: nil),
        .init(key: "small_chair", name: "Small Chair", category: .chair, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x2B8], sprite: nil),
        .init(key: "pokemon_chair", name: "Pokémon Chair", category: .chair, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x2B9], sprite: nil),
        .init(key: "heavy_chair", name: "Heavy Chair", category: .chair, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x2BA], sprite: nil),
        .init(key: "pretty_chair", name: "Pretty Chair", category: .chair, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x2C0], sprite: nil),
        .init(key: "comfort_chair", name: "Comfort Chair", category: .chair, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x2C1], sprite: nil),
        .init(key: "ragged_chair", name: "Ragged Chair", category: .chair, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x2C2], sprite: nil),
        .init(key: "brick_chair", name: "Brick Chair", category: .chair, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x2C8], sprite: nil),
        .init(key: "camp_chair", name: "Camp Chair", category: .chair, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x2C9], sprite: nil),
        .init(key: "hard_chair", name: "Hard Chair", category: .chair, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x2CA], sprite: nil),
        .init(key: "red_plant", name: "Red Plant", category: .plant, placement: .behind, w: 1, h: 2, price: 3000, tiles: [0x2D0, 0x2D8], sprite: nil),
        .init(key: "tropical_plant", name: "Tropical Plant", category: .plant, placement: .behind, w: 1, h: 2, price: 3000, tiles: [0x2D2, 0x2DA], sprite: nil),
        .init(key: "pretty_flowers", name: "Pretty Flowers", category: .plant, placement: .behind, w: 1, h: 2, price: 3000, tiles: [0x2D4, 0x2DC], sprite: nil),
        .init(key: "colorful_plant", name: "Colorful Plant", category: .plant, placement: .behind, w: 2, h: 2, price: 5000, tiles: [0x2E0, 0x2E2, 0x2E8, 0x2E9], sprite: nil),
        .init(key: "big_plant", name: "Big Plant", category: .plant, placement: .behind, w: 2, h: 2, price: 5000, tiles: [0x2E4, 0x2E6, 0x2EC, 0x2ED], sprite: nil),
        .init(key: "gorgeous_plant", name: "Gorgeous Plant", category: .plant, placement: .behind, w: 2, h: 2, price: 5000, tiles: [0x2F0, 0x2F2, 0x2F8, 0x2F9], sprite: nil),
        .init(key: "red_brick", name: "Red Brick", category: .ornament, placement: .solid, w: 1, h: 2, price: 500, tiles: [0x225, 0x22D], sprite: nil),
        .init(key: "yellow_brick", name: "Yellow Brick", category: .ornament, placement: .solid, w: 1, h: 2, price: 500, tiles: [0x226, 0x22E], sprite: nil),
        .init(key: "blue_brick", name: "Blue Brick", category: .ornament, placement: .solid, w: 1, h: 2, price: 500, tiles: [0x227, 0x22F], sprite: nil),
        .init(key: "red_balloon", name: "Red Balloon", category: .ornament, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x338], sprite: nil),
        .init(key: "blue_balloon", name: "Blue Balloon", category: .ornament, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x33C], sprite: nil),
        .init(key: "yellow_balloon", name: "Yellow Balloon", category: .ornament, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x340], sprite: nil),
        .init(key: "red_tent", name: "Red Tent", category: .ornament, placement: .pass, w: 3, h: 3, price: 10000, tiles: [0x230, 0x231, 0x232, 0x238, 0x239, 0x23A, 0x240, 0x241, 0x23B], sprite: nil),
        .init(key: "blue_tent", name: "Blue Tent", category: .ornament, placement: .pass, w: 3, h: 3, price: 10000, tiles: [0x248, 0x249, 0x268, 0x250, 0x251, 0x270, 0x258, 0x259, 0x269], sprite: nil),
        .init(key: "solid_board", name: "Solid Board", category: .ornament, placement: .pass, w: 1, h: 2, price: 3000, tiles: [0x234, 0x23C], sprite: nil),
        .init(key: "slide", name: "Slide", category: .ornament, placement: .pass, w: 2, h: 4, price: 8000, tiles: [0x235, 0x236, 0x23D, 0x23E, 0x263, 0x264, 0x26F, 0x277], sprite: nil),
        .init(key: "fence_length", name: "Fence Length", category: .ornament, placement: .solid, w: 1, h: 1, price: 500, tiles: [0x233], sprite: nil),
        .init(key: "fence_width", name: "Fence Width", category: .ornament, placement: .solid, w: 1, h: 1, price: 500, tiles: [0x22C], sprite: nil),
        .init(key: "tire", name: "Tire", category: .ornament, placement: .solid, w: 2, h: 2, price: 800, tiles: [0x280, 0x281, 0x288, 0x289], sprite: nil),
        .init(key: "stand", name: "Stand", category: .ornament, placement: .pass, w: 4, h: 2, price: 7000, tiles: [0x26A, 0x26B, 0x26C, 0x26D, 0x272, 0x273, 0x274, 0x275], sprite: nil),
        .init(key: "mud_ball", name: "Mud Ball", category: .ornament, placement: .pass, w: 1, h: 1, price: 200, tiles: [0x228], sprite: nil),
        .init(key: "breakable_door", name: "Breakable Door", category: .ornament, placement: .pass, w: 1, h: 2, price: 3000, tiles: [0x237, 0x23F], sprite: nil),
        .init(key: "sand_ornament", name: "Sand Ornament", category: .ornament, placement: .behind, w: 1, h: 2, price: 3000, tiles: [0x285, 0x28D], sprite: nil),
        .init(key: "silver_shield", name: "Silver Shield", category: .ornament, placement: .behind, w: 1, h: 2, price: 0, tiles: [0x2D6, 0x2DE], sprite: nil),
        .init(key: "gold_shield", name: "Gold Shield", category: .ornament, placement: .behind, w: 1, h: 2, price: 0, tiles: [0x32E, 0x336], sprite: nil),
        .init(key: "glass_ornament", name: "Glass Ornament", category: .ornament, placement: .behind, w: 1, h: 2, price: 0, tiles: [0x282, 0x28A], sprite: nil),
        .init(key: "tv", name: "Tv", category: .ornament, placement: .solid, w: 1, h: 1, price: 3000, tiles: [0x2F4], sprite: nil),
        .init(key: "round_tv", name: "Round Tv", category: .ornament, placement: .solid, w: 1, h: 1, price: 4000, tiles: [0x2F5], sprite: nil),
        .init(key: "cute_tv", name: "Cute Tv", category: .ornament, placement: .solid, w: 1, h: 1, price: 4000, tiles: [0x2F6], sprite: nil),
        .init(key: "glitter_mat", name: "Glitter Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x260], sprite: nil),
        .init(key: "jump_mat", name: "Jump Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x261], sprite: nil),
        .init(key: "spin_mat", name: "Spin Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 2000, tiles: [0x262], sprite: nil),
        .init(key: "c_low_note_mat", name: "C Low Note Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x278], sprite: nil),
        .init(key: "d_note_mat", name: "D Note Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x279], sprite: nil),
        .init(key: "e_note_mat", name: "E Note Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x27A], sprite: nil),
        .init(key: "f_note_mat", name: "F Note Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x27B], sprite: nil),
        .init(key: "g_note_mat", name: "G Note Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x27C], sprite: nil),
        .init(key: "a_note_mat", name: "A Note Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x27D], sprite: nil),
        .init(key: "b_note_mat", name: "B Note Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x27E], sprite: nil),
        .init(key: "c_high_note_mat", name: "C High Note Mat", category: .mat, placement: .pass, w: 1, h: 1, price: 500, tiles: [0x2B3], sprite: nil),
        .init(key: "surf_mat", name: "Surf Mat", category: .mat, placement: .pass, w: 3, h: 3, price: 4000, tiles: [0x242, 0x243, 0x244, 0x24A, 0x24B, 0x24C, 0x252, 0x253, 0x254], sprite: nil),
        .init(key: "thunder_mat", name: "Thunder Mat", category: .mat, placement: .pass, w: 3, h: 3, price: 4000, tiles: [0x245, 0x246, 0x247, 0x24D, 0x24E, 0x24F, 0x255, 0x256, 0x257], sprite: nil),
        .init(key: "fire_blast_mat", name: "Fire Blast Mat", category: .mat, placement: .pass, w: 3, h: 3, price: 4000, tiles: [0x25A, 0x25B, 0x25C, 0x25D, 0x25E, 0x25F, 0x265, 0x266, 0x267], sprite: nil),
        .init(key: "powder_snow_mat", name: "Powder Snow Mat", category: .mat, placement: .pass, w: 3, h: 3, price: 4000, tiles: [0x300, 0x301, 0x302, 0x308, 0x309, 0x30A, 0x310, 0x311, 0x312], sprite: nil),
        .init(key: "attract_mat", name: "Attract Mat", category: .mat, placement: .pass, w: 3, h: 3, price: 4000, tiles: [0x303, 0x304, 0x305, 0x30B, 0x30C, 0x30D, 0x313, 0x314, 0x315], sprite: nil),
        .init(key: "fissure_mat", name: "Fissure Mat", category: .mat, placement: .pass, w: 3, h: 3, price: 4000, tiles: [0x306, 0x307, 0x318, 0x30E, 0x30F, 0x320, 0x316, 0x317, 0x328], sprite: nil),
        .init(key: "spikes_mat", name: "Spikes Mat", category: .mat, placement: .pass, w: 3, h: 3, price: 4000, tiles: [0x319, 0x31A, 0x31B, 0x321, 0x322, 0x323, 0x329, 0x32A, 0x32B], sprite: nil),
        .init(key: "ball_poster", name: "Ball Poster", category: .poster, placement: .wall, w: 1, h: 1, price: 1000, tiles: [0x330], sprite: nil),
        .init(key: "green_poster", name: "Green Poster", category: .poster, placement: .wall, w: 1, h: 1, price: 1000, tiles: [0x331], sprite: nil),
        .init(key: "red_poster", name: "Red Poster", category: .poster, placement: .wall, w: 1, h: 1, price: 1000, tiles: [0x332], sprite: nil),
        .init(key: "blue_poster", name: "Blue Poster", category: .poster, placement: .wall, w: 1, h: 1, price: 1000, tiles: [0x333], sprite: nil),
        .init(key: "cute_poster", name: "Cute Poster", category: .poster, placement: .wall, w: 1, h: 1, price: 1000, tiles: [0x334], sprite: nil),
        .init(key: "pika_poster", name: "Pika Poster", category: .poster, placement: .wall, w: 2, h: 1, price: 1500, tiles: [0x31C, 0x31D], sprite: nil),
        .init(key: "long_poster", name: "Long Poster", category: .poster, placement: .wall, w: 2, h: 1, price: 1500, tiles: [0x31E, 0x31F], sprite: nil),
        .init(key: "sea_poster", name: "Sea Poster", category: .poster, placement: .wall, w: 2, h: 1, price: 1500, tiles: [0x324, 0x325], sprite: nil),
        .init(key: "sky_poster", name: "Sky Poster", category: .poster, placement: .wall, w: 2, h: 1, price: 1500, tiles: [0x326, 0x327], sprite: nil),
        .init(key: "kiss_poster", name: "Kiss Poster", category: .poster, placement: .wall, w: 2, h: 1, price: 1500, tiles: [0x32C, 0x32D], sprite: nil),
        .init(key: "pichu_doll", name: "Pichu Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/pichu_doll.png"),
        .init(key: "pikachu_doll", name: "Pikachu Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/pikachu_doll.png"),
        .init(key: "marill_doll", name: "Marill Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/marill_doll.png"),
        .init(key: "togepi_doll", name: "Togepi Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/togepi_doll.png"),
        .init(key: "cyndaquil_doll", name: "Cyndaquil Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/cyndaquil_doll.png"),
        .init(key: "chikorita_doll", name: "Chikorita Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/chikorita_doll.png"),
        .init(key: "totodile_doll", name: "Totodile Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/totodile_doll.png"),
        .init(key: "jigglypuff_doll", name: "Jigglypuff Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/jigglypuff_doll.png"),
        .init(key: "meowth_doll", name: "Meowth Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/meowth_doll.png"),
        .init(key: "clefairy_doll", name: "Clefairy Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/clefairy_doll.png"),
        .init(key: "ditto_doll", name: "Ditto Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/ditto_doll.png"),
        .init(key: "smoochum_doll", name: "Smoochum Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/smoochum_doll.png"),
        .init(key: "treecko_doll", name: "Treecko Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/treecko_doll.png"),
        .init(key: "torchic_doll", name: "Torchic Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/torchic_doll.png"),
        .init(key: "mudkip_doll", name: "Mudkip Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/mudkip_doll.png"),
        .init(key: "duskull_doll", name: "Duskull Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/duskull_doll.png"),
        .init(key: "wynaut_doll", name: "Wynaut Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/wynaut_doll.png"),
        .init(key: "baltoy_doll", name: "Baltoy Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/baltoy_doll.png"),
        .init(key: "kecleon_doll", name: "Kecleon Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/kecleon_doll.png"),
        .init(key: "azurill_doll", name: "Azurill Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/azurill_doll.png"),
        .init(key: "skitty_doll", name: "Skitty Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/skitty_doll.png"),
        .init(key: "swablu_doll", name: "Swablu Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/swablu_doll.png"),
        .init(key: "gulpin_doll", name: "Gulpin Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/gulpin_doll.png"),
        .init(key: "lotad_doll", name: "Lotad Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/lotad_doll.png"),
        .init(key: "seedot_doll", name: "Seedot Doll", category: .doll, placement: .sprite, w: 1, h: 1, price: 3000, tiles: [], sprite: "graphics/object_events/pics/dolls/seedot_doll.png"),
        .init(key: "pika_cushion", name: "Pika Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/pika_cushion.png"),
        .init(key: "round_cushion", name: "Round Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/round_cushion.png"),
        .init(key: "kiss_cushion", name: "Kiss Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/kiss_cushion.png"),
        .init(key: "zigzag_cushion", name: "Zigzag Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/zigzag_cushion.png"),
        .init(key: "spin_cushion", name: "Spin Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/spin_cushion.png"),
        .init(key: "diamond_cushion", name: "Diamond Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/diamond_cushion.png"),
        .init(key: "ball_cushion", name: "Ball Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/ball_cushion.png"),
        .init(key: "grass_cushion", name: "Grass Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/grass_cushion.png"),
        .init(key: "fire_cushion", name: "Fire Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/fire_cushion.png"),
        .init(key: "water_cushion", name: "Water Cushion", category: .cushion, placement: .sprite, w: 1, h: 1, price: 2000, tiles: [], sprite: "graphics/object_events/pics/cushions/water_cushion.png"),
        .init(key: "snorlax_doll", name: "Snorlax Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_snorlax_doll.png"),
        .init(key: "rhydon_doll", name: "Rhydon Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_rhydon_doll.png"),
        .init(key: "lapras_doll", name: "Lapras Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_lapras_doll.png"),
        .init(key: "venusaur_doll", name: "Venusaur Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_venusaur_doll.png"),
        .init(key: "charizard_doll", name: "Charizard Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_charizard_doll.png"),
        .init(key: "blastoise_doll", name: "Blastoise Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_blastoise_doll.png"),
        .init(key: "wailmer_doll", name: "Wailmer Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_wailmer_doll.png"),
        .init(key: "regirock_doll", name: "Regirock Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_regirock_doll.png"),
        .init(key: "regice_doll", name: "Regice Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_regice_doll.png"),
        .init(key: "registeel_doll", name: "Registeel Doll", category: .doll, placement: .sprite, w: 1, h: 2, price: 10000, tiles: [], sprite: "graphics/object_events/pics/dolls/big_registeel_doll.png"),
    ]
}
