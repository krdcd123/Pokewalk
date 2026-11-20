import Foundation

/// Extra Pokédex details (category, height, weight, entry text, abilities, base stats, egg groups…),
/// downloaded from PokeAPI the first time you open an entry and kept on the phone for offline use.
struct DexInfo: Codable {
    var genus: String
    var flavor: String
    var flavorVersion: String
    var heightDm: Int
    var weightHg: Int
    var abilities: [String]
    var hiddenAbility: String?
    var stats: [Int]               // HP, Atk, Def, SpA, SpD, Spe
    var eggGroups: [String]
    var habitat: String?
    var colour: String?
}

@MainActor
final class DexInfoService {
    static let shared = DexInfoService()
    private var memory: [Int: DexInfo] = [:]

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DexInfo", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func info(for id: Int) async -> DexInfo? {
        if let m = memory[id] { return m }
        let file = Self.dir.appendingPathComponent("\(id).json")
        if let data = try? Data(contentsOf: file), let i = try? JSONDecoder().decode(DexInfo.self, from: data) {
            memory[id] = i; return i
        }
        guard let i = await fetch(id) else { return nil }
        memory[id] = i
        if let data = try? JSONEncoder().encode(i) { try? data.write(to: file, options: .atomic) }
        return i
    }

    private func json(_ s: String) async -> [String: Any]? {
        guard let url = URL(string: s), let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func fetch(_ id: Int) async -> DexInfo? {
        async let speciesJ = json("https://pokeapi.co/api/v2/pokemon-species/\(id)")
        async let pokemonJ = json("https://pokeapi.co/api/v2/pokemon/\(id)")
        guard let sp = await speciesJ, let pk = await pokemonJ else { return nil }

        func name(_ o: Any?) -> String? { (o as? [String: Any])?["name"] as? String }
        func pretty(_ s: String) -> String { s.split(separator: "-").map { $0.capitalized }.joined(separator: " ") }

        let genus = (sp["genera"] as? [[String: Any]])?
            .first { name($0["language"]) == "en" }?["genus"] as? String ?? ""
        // Prefer the Gen 3 entries (Emerald, then Ruby/Sapphire, FireRed/LeafGreen), else any English one
        let entries = (sp["flavor_text_entries"] as? [[String: Any]] ?? []).filter { name($0["language"]) == "en" }
        let order = ["emerald", "ruby", "sapphire", "firered", "leafgreen", "crystal", "gold", "silver", "yellow", "red", "blue"]
        let entry = order.lazy.compactMap { v in entries.first { name($0["version"]) == v } }.first ?? entries.last
        let flavor = (entry?["flavor_text"] as? String ?? "")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\u{0C}", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        let abilities = pk["abilities"] as? [[String: Any]] ?? []
        let stats = (pk["stats"] as? [[String: Any]] ?? []).compactMap { $0["base_stat"] as? Int }

        return DexInfo(
            genus: genus,
            flavor: flavor,
            flavorVersion: pretty(name(entry?["version"]) ?? ""),
            heightDm: pk["height"] as? Int ?? 0,
            weightHg: pk["weight"] as? Int ?? 0,
            abilities: abilities.filter { ($0["is_hidden"] as? Bool) != true }.compactMap { name($0["ability"]).map(pretty) },
            hiddenAbility: abilities.first { ($0["is_hidden"] as? Bool) == true }.flatMap { name($0["ability"]).map(pretty) },
            stats: stats,
            eggGroups: (sp["egg_groups"] as? [[String: Any]] ?? []).compactMap { name($0).map(pretty) },
            habitat: name(sp["habitat"]).map(pretty),
            colour: name(sp["color"]).map(pretty))
    }
}
