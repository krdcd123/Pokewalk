package com.krdcd.pokewalk

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RulesTest {
    @Test fun walkingWorks() {
        Dex.loadText(File("../../Shared/Resources/dex.json").readText())
        val s = Rules.newGame("Ash", 1, null, false)
        repeat(50) { Rules.apply(1_000, s) }
        val buddy = s.buddy!!
        println("Lv ${buddy.level} balls ${s.totalBalls} items ${s.bag} pending ${s.pending.map { it.species.name + " " + it.level }} money ${s.money} swarm ${Rules.swarm().name}")
        assertTrue(buddy.level > 5)
        assertTrue(s.pending.isNotEmpty())
        val json = Dex.json.encodeToString(GameState.serializer(), s)
        val back = Dex.json.decodeFromString(GameState.serializer(), json)
        assertTrue(back.pokemon.size == s.pokemon.size)
        val w = s.pending.first()
        println("catch chance ${w.species.name}: ${Rules.catchChance(w, BallKind.POKE, 0, false)}")
        println("item evo eevee water: " + Rules.itemEvolution(Rules.makePokemon(133, 10, BallKind.POKE, 512), "water-stone"))
    }
}
