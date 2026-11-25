package com.krdcd.pokewalk

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.util.Calendar
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt
import kotlin.random.Random

// MARK: - Species data (the same dex.json as the iOS app, generated from PokéAPI)

@Serializable
data class EvolutionRule(
    val kind: String, val into: Int, val level: Int? = null, val item: String? = null,
    val value: Int? = null, val time: String? = null, val gender: String? = null,
)

@Serializable
data class Species(
    val id: Int, val name: String, val key: String, val types: List<String>, val evolvesFrom: Int? = null,
    val evolutions: List<EvolutionRule> = emptyList(), val captureRate: Int, val baseFriendship: Int,
    val genderRate: Int, val growth: String, val isBaby: Boolean, val isLegendary: Boolean,
    val isMythical: Boolean, val habitats: List<String> = emptyList(), val generation: Int,
) {
    val minimumWildLevel: Int
        get() {
            val from = evolvesFrom ?: return 1
            val rule = Dex.species(from).evolutions.firstOrNull { it.into == id } ?: return 1
            return if (rule.kind == "level") rule.level ?: 1 else 1
        }
}

@Serializable data class ItemInfo(val key: String, val name: String)
@Serializable private data class DexFile(val species: List<Species>, val items: List<ItemInfo>)

object Dex {
    private lateinit var file: DexFile
    private lateinit var itemNames: Map<String, String>
    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun load(ctx: Context) {
        if (::file.isInitialized) return
        loadText(ctx.assets.open("dex.json").bufferedReader().readText())
    }

    fun loadText(text: String) {
        file = json.decodeFromString(text)
        itemNames = file.items.associate { it.key to it.name }
    }

    val all: List<Species> get() = file.species
    val count: Int get() = file.species.size
    fun species(id: Int): Species = file.species[id.coerceIn(1, count) - 1]

    fun itemName(key: String): String {
        if (key == "linking-cord") return "Link Cable"
        BallKind.entries.firstOrNull { it.itemKey == key }?.let { return it.title }
        return itemNames[key] ?: key.split("-").joinToString(" ") { it.replaceFirstChar(Char::uppercase) }
    }

    val starters = listOf(1, 4, 7, 152, 155, 158, 252, 255, 258, 25, 133)
    val natures = listOf("Hardy", "Lonely", "Brave", "Adamant", "Naughty", "Bold", "Docile", "Relaxed", "Impish",
        "Lax", "Timid", "Hasty", "Serious", "Jolly", "Naive", "Modest", "Mild", "Quiet",
        "Bashful", "Rash", "Calm", "Gentle", "Sassy", "Careful", "Quirky")
}

/** Real Gen 3+ growth formulas. */
object Growth {
    private val tables = HashMap<String, IntArray>()
    private fun formula(g: String, n: Int): Int {
        if (n <= 1) return 0
        val n3 = n * n * n
        return when (g) {
            "fast" -> 4 * n3 / 5
            "mediumSlow" -> max(0, 6 * n3 / 5 - 15 * n * n + 100 * n - 140)
            "slow" -> 5 * n3 / 4
            "erratic" -> when {
                n < 50 -> n3 * (100 - n) / 50
                n < 68 -> n3 * (150 - n) / 100
                n < 98 -> n3 * ((1911 - 10 * n) / 3) / 500
                else -> n3 * (160 - n) / 100
            }
            "fluctuating" -> when {
                n < 15 -> n3 * ((n + 1) / 3 + 24) / 50
                n < 36 -> n3 * (n + 14) / 50
                else -> n3 * (n / 2 + 32) / 50
            }
            else -> n3
        }
    }
    private fun table(g: String) = tables.getOrPut(g) { IntArray(101) { formula(g, it) } }
    fun exp(g: String, level: Int) = table(g)[level.coerceIn(0, 100)]
    fun maxExp(g: String) = exp(g, 100)
    fun level(g: String, exp: Int): Int {
        val t = table(g)
        var lo = 1; var hi = 100
        while (lo < hi) { val mid = (lo + hi + 1) / 2; if (t[mid] <= exp) lo = mid else hi = mid - 1 }
        return lo
    }
    fun progress(g: String, exp: Int): Float {
        val l = level(g, exp)
        if (l >= 100) return 1f
        val a = exp(g, l); val b = exp(g, l + 1)
        return if (b > a) (exp - a).toFloat() / (b - a) else 1f
    }
}

enum class BallKind(val title: String, val itemKey: String, val bonus: Double) {
    POKE("Poké Ball", "poke-ball", 1.0), GREAT("Great Ball", "great-ball", 1.5), ULTRA("Ultra Ball", "ultra-ball", 2.0),
    NET("Net Ball", "net-ball", 1.0), DIVE("Dive Ball", "dive-ball", 1.0), NEST("Nest Ball", "nest-ball", 1.0),
    REPEAT("Repeat Ball", "repeat-ball", 1.0), TIMER("Timer Ball", "timer-ball", 1.0), LUXURY("Luxury Ball", "luxury-ball", 1.0),
    PREMIER("Premier Ball", "premier-ball", 1.0), MASTER("Master Ball", "master-ball", 255.0);

    val isStepBall get() = this == POKE || this == GREAT || this == ULTRA

    /** Gen 3 rules for the conditional balls. */
    fun bonus(sp: Species, level: Int, turn: Int, caughtBefore: Boolean): Double = when (this) {
        NET -> if ("water" in sp.types || "bug" in sp.types) 3.0 else 1.0
        DIVE -> if ("water" in sp.types) 3.5 else 1.0
        NEST -> max(1.0, (40 - level) / 10.0)
        REPEAT -> if (caughtBefore) 3.0 else 1.0
        TIMER -> min(4.0, (turn + 10) / 10.0)
        else -> bonus
    }

    val effect: String
        get() = when (this) {
            POKE, PREMIER -> "A standard ball."
            GREAT -> "Better than a Poké Ball (1.5×)."
            ULTRA -> "Better than a Great Ball (2×)."
            NET -> "3× on Water and Bug types."
            DIVE -> "3.5× on Water types."
            NEST -> "Better the lower the Pokémon's level."
            REPEAT -> "3× on species you've caught before."
            TIMER -> "Gets better the longer the encounter goes on."
            LUXURY -> "The Pokémon grows friendly twice as fast."
            MASTER -> "Catches without fail."
        }
}

// MARK: - Save data

@Serializable
data class Mon(
    val id: String = UUID.randomUUID().toString(),
    var speciesID: Int,
    var nickname: String? = null,
    var exp: Int,
    var expRemainder: Double = 0.0,
    val gender: String,
    val isShiny: Boolean,
    val nature: String,
    val personality: Long,
    var friendship: Int,
    var friendRemainder: Int = 0,
    val ball: String,
    val metDate: Long,
    val metLevel: Int,
    var stepsWalked: Int = 0,
    var declinedAtLevel: Int? = null,
) {
    val species get() = Dex.species(speciesID)
    val name get() = nickname ?: species.name
    val level get() = Growth.level(species.growth, exp)
    val genderSymbol get() = if (gender == "male") "♂" else if (gender == "female") "♀" else ""
}

@Serializable
data class Wild(
    val id: String = UUID.randomUUID().toString(),
    val speciesID: Int, val level: Int, val gender: String, val isShiny: Boolean,
    val nature: String, val personality: Long, val appearedAt: Long, val expiresAt: Long,
) {
    val species get() = Dex.species(speciesID)
}

@Serializable
data class GameState(
    var trainerName: String = "",
    var money: Int = 0,
    var lifetimeSteps: Int = 0,
    var stepsToday: Int = 0,
    var todayKey: String = "",
    var pokemon: MutableList<Mon> = mutableListOf(),
    var partyIDs: MutableList<String> = mutableListOf(),
    var buddyID: String? = null,
    var balls: MutableMap<String, Int> = mutableMapOf(),
    var bag: MutableMap<String, Int> = mutableMapOf(),
    var pending: MutableList<Wild> = mutableListOf(),
    var dexSeen: MutableSet<Int> = mutableSetOf(),
    var dexCaught: MutableSet<Int> = mutableSetOf(),
    var encounterProgress: Int = 0,
    var nextEncounterAt: Int = 500,
    var ballProgress: Int = 0,
    var ballsEarnedTotal: Int = 0,
    var itemProgress: Int = 0,
    var moneyProgress: Int = 0,
    var lastSensorValue: Long = -1,
    var shinyOdds: Int = 512,
) {
    val started get() = pokemon.isNotEmpty()
    fun mon(id: String?) = pokemon.firstOrNull { it.id == id }
    val party get() = partyIDs.mapNotNull { mon(it) }
    val boxed get() = pokemon.filter { it.id !in partyIDs }
    val buddy get() = mon(buddyID)
    fun ballCount(b: BallKind) = balls[b.name] ?: 0
    val totalBalls get() = balls.values.sum()
    val stepsToEncounter get() = max(0, nextEncounterAt - encounterProgress)
}

/** What a batch of steps did, for the toasts. */
data class StepOutcome(
    var steps: Int = 0, var oldLevel: Int = 0, var newLevel: Int = 0,
    var ballsEarned: MutableMap<BallKind, Int> = mutableMapOf(),
    var itemsFound: MutableList<String> = mutableListOf(),
    var newEncounters: MutableList<Wild> = mutableListOf(),
    var evolutionReady: Pair<String, Int>? = null,
)

// MARK: - Rules (ported from the iOS app's Shared/GameRules.swift)

object Rules {
    const val EXP_PER_STEP = 0.25
    const val PARTY_SHARE = 0.2
    const val ENCOUNTER_STEPS = 500
    const val BALL_STEPS = 1_000
    const val ITEM_STEPS = 1_500
    const val MAX_PENDING = 5
    const val ENCOUNTER_HOURS = 4
    const val MAX_PARTY = 6
    const val LEGENDARY_CHANCE = 0.0001

    fun rollGender(sp: Species) = if (sp.genderRate < 0) "genderless" else if (Random.nextInt(8) < sp.genderRate) "female" else "male"

    fun makePokemon(id: Int, level: Int, ball: BallKind, shinyOdds: Int, now: Long = System.currentTimeMillis()): Mon {
        val sp = Dex.species(id)
        return Mon(
            speciesID = id, exp = Growth.exp(sp.growth, level), gender = rollGender(sp),
            isShiny = Random.nextInt(max(1, shinyOdds)) == 0, nature = Dex.natures.random(),
            personality = Random.nextLong(0, 0xFFFFFFFFL), friendship = sp.baseFriendship,
            ball = ball.name, metDate = now, metLevel = level,
        )
    }

    fun newGame(trainer: String, starter: Int, nickname: String?, shiny: Boolean): GameState {
        val s = GameState(trainerName = trainer.ifBlank { "Trainer" })
        val mon = makePokemon(starter, 5, BallKind.POKE, 8192).copy(nickname = nickname?.ifBlank { null }, isShiny = shiny)
        store(mon, s)
        s.buddyID = mon.id
        s.balls = mutableMapOf(BallKind.POKE.name to 10, BallKind.GREAT.name to 2)
        s.nextEncounterAt = rollEncounterGap()
        s.todayKey = todayKey()
        return s
    }

    fun store(mon: Mon, s: GameState) {
        s.pokemon.add(mon)
        s.dexSeen.add(mon.speciesID); s.dexCaught.add(mon.speciesID)
        if (s.partyIDs.size < MAX_PARTY) s.partyIDs.add(mon.id)
    }

    fun rollEncounterGap() = Random.nextInt(ENCOUNTER_STEPS * 8 / 10, ENCOUNTER_STEPS * 12 / 10 + 1)

    fun todayKey(): String {
        val c = Calendar.getInstance()
        return "${c.get(Calendar.YEAR)}-${c.get(Calendar.DAY_OF_YEAR)}"
    }

    private fun grantExp(amount: Double, mon: Mon): Int {
        val total = mon.expRemainder + amount
        val whole = total.toInt()
        mon.expRemainder = total - whole
        val before = mon.exp
        mon.exp = min(mon.exp + whole, Growth.maxExp(mon.species.growth))
        return mon.exp - before
    }

    fun apply(steps: Int, s: GameState, now: Long = System.currentTimeMillis()): StepOutcome {
        val out = StepOutcome()
        if (todayKey() != s.todayKey) { s.todayKey = todayKey(); s.stepsToday = 0 }
        if (steps <= 0) return out
        out.steps = steps
        s.lifetimeSteps += steps
        s.stepsToday += steps

        // Buddy: Exp and friendship
        val buddyExp = steps * EXP_PER_STEP
        s.buddy?.let { mon ->
            out.oldLevel = mon.level
            grantExp(buddyExp, mon)
            mon.stepsWalked += steps
            val f = mon.friendRemainder + steps * (if (mon.ball == BallKind.LUXURY.name) 2 else 1)
            mon.friendship = min(255, mon.friendship + f / 100)
            mon.friendRemainder = f % 100
            out.newLevel = mon.level
            pendingEvolution(mon)?.let { out.evolutionReady = mon.id to it }
        }
        // Exp Share for the rest of the party
        for (mon in s.party) {
            if (mon.id == s.buddyID) continue
            grantExp(buddyExp * PARTY_SHARE, mon)
            val f = mon.friendRemainder + steps
            mon.friendship = min(255, mon.friendship + f / 200)
            mon.friendRemainder = f % 200
            if (out.evolutionReady == null) pendingEvolution(mon)?.let { out.evolutionReady = mon.id to it }
        }

        // Balls every 1,000 steps (every 10th a Great Ball, every 50th an Ultra Ball)
        s.ballProgress += steps
        while (s.ballProgress >= BALL_STEPS) {
            s.ballProgress -= BALL_STEPS
            s.ballsEarnedTotal += 1
            val kind = when {
                s.ballsEarnedTotal % 50 == 0 -> BallKind.ULTRA
                s.ballsEarnedTotal % 10 == 0 -> BallKind.GREAT
                else -> BallKind.POKE
            }
            s.balls[kind.name] = s.ballCount(kind) + 1
            out.ballsEarned[kind] = (out.ballsEarned[kind] ?: 0) + 1
        }

        // Items
        s.itemProgress += steps
        while (s.itemProgress >= ITEM_STEPS) {
            s.itemProgress -= ITEM_STEPS
            val item = rollItem()
            val ball = BallKind.entries.firstOrNull { it.itemKey == item }
            if (ball != null) s.balls[ball.name] = s.ballCount(ball) + 1 else s.bag[item] = (s.bag[item] ?: 0) + 1
            out.itemsFound.add(item)
        }

        // Pocket money: ₽1 every 100 steps
        s.moneyProgress += steps
        s.money += s.moneyProgress / 100
        s.moneyProgress %= 100

        // Wild Pokémon
        s.pending.removeAll { it.expiresAt < now }
        s.encounterProgress += steps
        while (s.encounterProgress >= s.nextEncounterAt) {
            s.encounterProgress -= s.nextEncounterAt
            s.nextEncounterAt = rollEncounterGap()
            val enc = generateEncounter(s.lifetimeSteps, s.shinyOdds, now)
            if (s.pending.size >= MAX_PENDING) s.pending.removeAt(0)
            s.pending.add(enc)
            s.dexSeen.add(enc.speciesID)
            out.newEncounters.add(enc)
        }
        return out
    }

    // Seasons and swarms (UK months, like the iOS app)
    fun seasonTypes(): List<String> = when (Calendar.getInstance().get(Calendar.MONTH) + 1) {
        in 3..5 -> listOf("grass", "bug", "fairy", "flying")
        in 6..8 -> listOf("fire", "water", "electric", "ground")
        in 9..11 -> listOf("ghost", "dark", "normal", "poison")
        else -> listOf("ice", "steel", "psychic", "dragon")
    }
    fun seasonName(): String = when (Calendar.getInstance().get(Calendar.MONTH) + 1) {
        in 3..5 -> "Spring"; in 6..8 -> "Summer"; in 9..11 -> "Autumn"; else -> "Winter"
    }

    fun swarm(): Species {
        val types = seasonTypes()
        val pool = Dex.all.filter {
            !it.isLegendary && !it.isMythical && !it.isBaby && it.generation <= 4 && it.evolvesFrom == null &&
                it.types.any { t -> t in types }
        }
        if (pool.isEmpty()) return Dex.species(25)
        // weeks since Monday 1 Jan 2024
        val start = Calendar.getInstance().apply { set(2024, 0, 1, 0, 0, 0) }.timeInMillis
        val week = max(0L, (System.currentTimeMillis() - start) / (7L * 86_400_000))
        var x = (week.toULong() * 2_654_435_761uL + 97uL)
        x = x xor (x shr 13)
        return pool[(x % pool.size.toULong()).toInt()]
    }

    private fun rarityWeight(sp: Species) = when {
        sp.captureRate >= 190 -> 100.0
        sp.captureRate >= 120 -> 45.0
        sp.captureRate >= 75 -> 18.0
        sp.captureRate >= 45 -> 6.0
        sp.captureRate >= 11 -> 1.5
        else -> 0.4
    }

    private fun encounterWeight(sp: Species, night: Boolean): Double {
        if (sp.isLegendary || sp.isMythical) return 0.0
        var w = rarityWeight(sp)
        sp.evolvesFrom?.let { w *= if (Dex.species(it).evolvesFrom != null) 0.05 else 0.2 }
        if (sp.isBaby) w *= 0.5
        if ("ghost" in sp.types || "dark" in sp.types) w *= if (night) 1.5 else 0.8
        return w
    }

    private fun isNight() = Calendar.getInstance().get(Calendar.HOUR_OF_DAY) !in 6 until 20

    fun pickSpecies(): Species {
        if (Random.nextDouble() < LEGENDARY_CHANCE) {
            return weightedPick(Dex.all.filter { it.isLegendary || it.isMythical }.map { it to if (it.isMythical) 0.25 else 1.0 })
        }
        if (Random.nextDouble() < 0.2) return swarm()
        val types = seasonTypes(); val night = isNight()
        val options = Dex.all.map { sp ->
            val w = encounterWeight(sp, night)
            sp to if (sp.types.any { it in types }) w * 1.6 else w
        }.filter { it.second > 0 }
        return weightedPick(options)
    }

    fun generateEncounter(lifetimeSteps: Int, shinyOdds: Int, now: Long): Wild {
        val sp = pickSpecies()
        val base = min(55, 3 + lifetimeSteps / 6_000)
        val level = max(base + Random.nextInt(-2, 4), sp.minimumWildLevel).coerceIn(1, 100)
        return Wild(
            speciesID = sp.id, level = level, gender = rollGender(sp),
            isShiny = Random.nextInt(max(1, shinyOdds)) == 0, nature = Dex.natures.random(),
            personality = Random.nextLong(0, 0xFFFFFFFFL), appearedAt = now,
            expiresAt = now + ENCOUNTER_HOURS * 3_600_000L,
        )
    }

    val sellPrice = mapOf(
        "shoal-salt" to 20, "shoal-shell" to 20, "tiny-mushroom" to 50, "heart-scale" to 50, "pearl" to 100,
        "stardust" to 150, "big-mushroom" to 250, "big-pearl" to 400, "star-piece" to 500, "nugget" to 1_000,
    )
    val berries = listOf("pomeg-berry", "kelpsy-berry", "qualot-berry", "hondew-berry", "grepa-berry", "tamato-berry")
    val shop = listOf(BallKind.POKE to 400, BallKind.GREAT to 1_200, BallKind.ULTRA to 2_400,
        BallKind.NET to 2_000, BallKind.DIVE to 2_000, BallKind.NEST to 2_000, BallKind.REPEAT to 2_000,
        BallKind.TIMER to 2_000, BallKind.LUXURY to 2_000)

    fun rollItem(): String {
        val table = mutableListOf(
            "rare-candy" to 8.0, "fire-stone" to 4.0, "water-stone" to 4.0, "thunder-stone" to 4.0, "leaf-stone" to 4.0,
            "moon-stone" to 3.5, "sun-stone" to 2.0, "linking-cord" to 0.8,
        )
        berries.forEach { table.add(it to 3.0) }
        sellPrice.forEach { (k, p) -> table.add(k to if (p <= 50) 6.0 else if (p <= 250) 3.5 else if (p <= 500) 1.5 else 0.6) }
        BallKind.entries.filter { !it.isStepBall }.forEach { table.add(it.itemKey to if (it == BallKind.MASTER) 0.08 else 2.5) }
        listOf("kings-rock", "metal-coat", "dragon-scale", "up-grade", "deep-sea-tooth", "deep-sea-scale").forEach { table.add(it to 0.12) }
        return weightedPick(table)
    }

    fun <T> weightedPick(options: List<Pair<T, Double>>): T {
        val total = options.sumOf { it.second }
        var roll = Random.nextDouble() * total
        for ((v, w) in options) { if (roll < w) return v; roll -= w }
        return options.last().first
    }

    // Evolution

    fun pendingEvolution(mon: Mon, ignoringDecline: Boolean = false): Int? {
        if (!ignoringDecline) mon.declinedAtLevel?.let { if (it >= mon.level) return null }
        val tod = if (isNight()) "night" else "day"
        val ready = mon.species.evolutions.filter { r ->
            (r.time == null || r.time == tod) && (r.gender == null || r.gender == mon.gender) && when (r.kind) {
                "level" -> mon.level >= (r.level ?: 101)
                "friendship" -> mon.friendship >= (r.value ?: 220)
                else -> false
            }
        }
        if (ready.isEmpty()) return null
        return ready[(mon.personality % ready.size).toInt()].into
    }

    fun itemEvolution(mon: Mon, item: String): Int? {
        val tod = if (isNight()) "night" else "day"
        return mon.species.evolutions.firstOrNull {
            it.kind == "item" && it.item == item && (it.time == null || it.time == tod) && (it.gender == null || it.gender == mon.gender)
        }?.into
    }

    fun evolve(mon: Mon, into: Int, s: GameState) {
        mon.speciesID = into
        mon.declinedAtLevel = null
        s.dexSeen.add(into); s.dexCaught.add(into)
    }

    fun canUse(item: String, mon: Mon): Boolean = when {
        item == "rare-candy" -> mon.level < 100
        item in berries -> mon.friendship < 255
        sellPrice.containsKey(item) -> false
        else -> itemEvolution(mon, item) != null
    }

    fun describe(item: String): String {
        if (item == "rare-candy") return "Raises a Pokémon by one level."
        if (item in berries) return "Makes a Pokémon more friendly."
        sellPrice[item]?.let { return "A valuable. Sells for ₽$it." }
        val users = Dex.all.flatMap { sp ->
            sp.evolutions.filter { it.kind == "item" && it.item == item }.map { "${sp.name} → ${Dex.species(it.into).name}" }
        }
        return if (users.isEmpty()) "No use yet." else "Evolves: " + users.joinToString(", ")
    }

    fun price(item: String): Int? = sellPrice[item] ?: if (item in berries) 20 else if (item == "rare-candy") 2_400 else 3_000

    // Catching (Gen 3/4 shake checks, with the iOS app's Safari bonus)

    fun shakeProbability(a: Double): Double {
        if (a >= 255) return 1.0
        val b = 1_048_560 / sqrt(sqrt(16_711_680 / max(a, 0.01)))
        return min(1.0, b / 65_536)
    }

    fun modifiedRate(wild: Wild, ball: BallKind, turn: Int, caughtBefore: Boolean): Double {
        if (ball == BallKind.MASTER) return 255.0
        return wild.species.captureRate * ball.bonus(wild.species, wild.level, turn, caughtBefore) * 1.5 / 3
    }

    fun catchChance(wild: Wild, ball: BallKind, turn: Int, caughtBefore: Boolean) =
        shakeProbability(modifiedRate(wild, ball, turn, caughtBefore)).pow(4)

    fun fleeChance(wild: Wild): Double {
        val sp = wild.species
        val rarity = if (sp.isLegendary || sp.isMythical) 0.30 else when {
            sp.captureRate >= 190 -> 0.06; sp.captureRate >= 120 -> 0.09; sp.captureRate >= 75 -> 0.13
            sp.captureRate >= 45 -> 0.18; else -> 0.24
        }
        return min(0.45, rarity + max(0, wild.level - 5) * 0.002)
    }
}

/** Load/save the game as JSON in the app's files. */
object Save {
    private fun file(ctx: Context) = File(ctx.filesDir, "save.json")
    fun load(ctx: Context): GameState =
        runCatching { Dex.json.decodeFromString<GameState>(file(ctx).readText()) }.getOrElse { GameState() }
    fun write(ctx: Context, s: GameState) {
        runCatching {
            val f = file(ctx); val tmp = File(f.path + ".tmp")
            tmp.writeText(Dex.json.encodeToString(GameState.serializer(), s)); tmp.renameTo(f)
        }
    }
}
