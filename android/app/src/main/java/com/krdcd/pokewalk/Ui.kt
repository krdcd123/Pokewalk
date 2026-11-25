package com.krdcd.pokewalk

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

// MARK: - Look

val Teal = Color(0xFF2E6F86)
val Ink = Color(0xFFFFFFFF)
val Soft = Color(0xB3FFFFFF)
fun typeColor(t: String) = Color(
    when (t) {
        "normal" -> 0xFFA8A77A; "fire" -> 0xFFEE8130; "water" -> 0xFF6390F0; "grass" -> 0xFF7AC74C
        "electric" -> 0xFFF7D02C; "ice" -> 0xFF96D9D6; "fighting" -> 0xFFC22E28; "poison" -> 0xFFA33EA1
        "ground" -> 0xFFE2BF65; "flying" -> 0xFFA98FF3; "psychic" -> 0xFFF95587; "bug" -> 0xFFA6B91A
        "rock" -> 0xFFB6A136; "ghost" -> 0xFF735797; "dragon" -> 0xFF6F35FC; "dark" -> 0xFF705746
        "steel" -> 0xFFB7B7CE; else -> 0xFFD685AD
    }
)

/** Frosted-glass card. */
@Composable
fun Glass(modifier: Modifier = Modifier, radius: Dp = 22.dp, tint: Color = Color.White, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .clip(RoundedCornerShape(radius))
            .background(Brush.verticalGradient(listOf(tint.copy(alpha = 0.20f), tint.copy(alpha = 0.09f))))
            .border(BorderStroke(1.dp, Color.White.copy(alpha = 0.28f)), RoundedCornerShape(radius))
            .padding(14.dp),
        content = content,
    )
}

@Composable
fun GlassButton(text: String, modifier: Modifier = Modifier, tint: Color = Color.White, enabled: Boolean = true, icon: ImageVector? = null, onClick: () -> Unit) {
    Row(
        modifier
            .alpha(if (enabled) 1f else 0.45f)
            .clip(RoundedCornerShape(50))
            .background(tint.copy(alpha = if (tint == Color.White) 0.16f else 0.55f))
            .border(BorderStroke(1.dp, Color.White.copy(alpha = 0.3f)), RoundedCornerShape(50))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) { Icon(icon, null, tint = Ink, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)) }
        Text(text, color = Ink, fontWeight = FontWeight.Bold, fontSize = 15.sp)
    }
}

@Composable
fun Pixel(url: String, modifier: Modifier = Modifier, silhouette: Boolean = false) {
    AsyncImage(
        model = url, contentDescription = null, modifier = modifier, contentScale = ContentScale.Fit,
        filterQuality = FilterQuality.None,
        colorFilter = if (silhouette) ColorFilter.tint(Color.Black.copy(alpha = 0.75f)) else null,
    )
}

@Composable
fun TypeChip(t: String) {
    Text(
        t.replaceFirstChar(Char::uppercase), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(typeColor(t)).padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

@Composable
fun Backdrop(content: @Composable BoxScope.() -> Unit) {
    Box(
        Modifier.fillMaxSize().background(
            Brush.linearGradient(listOf(Color(0xFF2E6F86), Color(0xFF1E4C5A), Color(0xFF16302A), Color(0xFF101C1A)))
        ),
        content = content,
    )
}

// MARK: - Root

@Composable
fun PokeWalkRoot(onStarted: () -> Unit) {
    MaterialTheme(colorScheme = darkColorScheme(primary = Color(0xFF7FD4E8))) {
        val s = Store.state
        Backdrop {
            if (!s.started) Onboarding(onStarted) else {
                LaunchedEffect(Unit) { onStarted() }
                MainTabs()
            }
            ToastHost()
            EvolutionHost()
        }
    }
}

@Composable
fun BoxScope.ToastHost() {
    val t = Store.toast
    LaunchedEffect(t) { if (t != null) { delay(3_500); Store.toast = null } }
    AnimatedVisibility(
        t != null, modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(12.dp),
        enter = slideInVertically() + fadeIn(), exit = slideOutVertically() + fadeOut(),
    ) {
        Glass(Modifier.fillMaxWidth().clickable { Store.toast = null }, tint = Teal) {
            Text(t ?: "", color = Ink, fontWeight = FontWeight.Bold)
        }
    }
}

// MARK: - Onboarding

@Composable
fun Onboarding(onStarted: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var nickname by remember { mutableStateOf("") }
    var pick by remember { mutableIntStateOf(0) }
    val shinies = remember { Dex.starters.filter { Random.nextInt(8192) == 0 }.toSet() }
    Column(
        Modifier.fillMaxSize().systemBarsPadding().verticalScroll(rememberScrollState()).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("PokéWalk", color = Ink, fontSize = 34.sp, fontWeight = FontWeight.Black)
        Text("Walk with your Pokémon. Every step gives it Exp, finds Poké Balls and items, and brings wild Pokémon your way.", color = Soft)
        Glass {
            Text("Your name", color = Soft, fontSize = 13.sp)
            OutlinedTextField(name, { name = it.take(12) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        }
        Glass {
            Text("Choose your partner", color = Ink, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Spacer(Modifier.height(8.dp))
            val rows = Dex.starters.chunked(4)
            rows.forEach { row ->
                Row(Modifier.fillMaxWidth()) {
                    row.forEach { id ->
                        val sel = pick == id
                        Column(
                            Modifier.weight(1f).padding(3.dp).clip(RoundedCornerShape(16.dp))
                                .background(if (sel) Color.White.copy(alpha = 0.25f) else Color.Transparent)
                                .clickable { pick = id; Cry.play(id) }.padding(4.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Pixel(Sprites.icon(id, id in shinies), Modifier.size(56.dp))
                            Text(Dex.species(id).name, color = Ink, fontSize = 11.sp, maxLines = 1)
                        }
                    }
                    repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
        if (pick != 0) {
            Glass(Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Pixel(Sprites.front(pick, pick in shinies), Modifier.size(110.dp))
                    Column(Modifier.padding(start = 10.dp)) {
                        Text(Dex.species(pick).name + if (pick in shinies) " ✨" else "", color = Ink, fontSize = 22.sp, fontWeight = FontWeight.Black)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { Dex.species(pick).types.forEach { TypeChip(it) } }
                    }
                }
                Text("Nickname (optional)", color = Soft, fontSize = 13.sp)
                OutlinedTextField(nickname, { nickname = it.take(12) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            }
            GlassButton("Start walking", Modifier.fillMaxWidth(), tint = Color(0xFFF5A623)) {
                Store.newGame(name, pick, nickname, pick in shinies)
                onStarted()
            }
        }
    }
}

// MARK: - Tabs

enum class Tab(val title: String, val icon: ImageVector) {
    HOME("Walk", Icons.Filled.DirectionsWalk), WILD("Wild", Icons.Filled.Grass), PARTY("Party", Icons.Filled.CatchingPokemon),
    BAG("Bag", Icons.Filled.Backpack), DEX("Pokédex", Icons.Filled.MenuBook)
}

@Composable
fun MainTabs() {
    var tab by remember { mutableStateOf(Tab.HOME) }
    var catching by remember { mutableStateOf<Wild?>(null) }
    val s = Store.state
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when (tab) {
                Tab.HOME -> HomeScreen()
                Tab.WILD -> WildScreen { id -> catching = Store.state.pending.firstOrNull { it.id == id } }
                Tab.PARTY -> PartyScreen()
                Tab.BAG -> BagScreen()
                Tab.DEX -> DexScreen()
            }
        }
        NavigationBar(containerColor = Color.Black.copy(alpha = 0.35f)) {
            Tab.entries.forEach { t ->
                NavigationBarItem(
                    selected = tab == t, onClick = { tab = t },
                    icon = {
                        BadgedBox(badge = {
                            if (t == Tab.WILD && s.pending.isNotEmpty()) Badge { Text("${s.pending.size}") }
                        }) { Icon(t.icon, null) }
                    },
                    label = { Text(t.title) },
                )
            }
        }
    }
    // keep the encounter itself, so "Gotcha!" stays on screen after it leaves the list
    catching?.let { w -> CatchScreen(w) { catching = null } }
}

@Composable
fun ScreenColumn(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title, color = Ink, fontSize = 30.sp, fontWeight = FontWeight.Black)
        content()
    }
}

// MARK: - Home

@Composable
fun HomeScreen() {
    val s = Store.state
    val buddy = s.buddy
    ScreenColumn("Walk") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Stat("Today", "%,d".format(s.stepsToday), Modifier.weight(1f))
            Stat("Money", "₽%,d".format(s.money), Modifier.weight(1f))
            Stat("Balls", "${s.totalBalls}", Modifier.weight(1f))
        }
        if (buddy != null) {
            Glass(Modifier.fillMaxWidth()) {
                Box(Modifier.fillMaxWidth().height(210.dp), contentAlignment = Alignment.BottomCenter) {
                    Canvas(Modifier.fillMaxWidth(0.75f).height(40.dp)) {
                        drawOval(Color.White.copy(alpha = 0.14f), Offset.Zero, Size(size.width, size.height))
                    }
                    Pixel(Sprites.front(buddy.speciesID, buddy.isShiny),
                        Modifier.size(190.dp).padding(bottom = 14.dp).clickable { Cry.play(buddy.speciesID) })
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(buddy.name + if (buddy.isShiny) " ✨" else "", color = Ink, fontSize = 24.sp, fontWeight = FontWeight.Black)
                    Text(" " + buddy.genderSymbol, color = if (buddy.gender == "female") Color(0xFFFF8FA8) else Color(0xFF7FB8FF), fontSize = 20.sp)
                    Spacer(Modifier.weight(1f))
                    Text("Lv. ${buddy.level}", color = Color(0xFF9FE3F0), fontSize = 20.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(6.dp))
                LinearProgressIndicator(
                    progress = { Growth.progress(buddy.species.growth, buddy.exp) },
                    modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)),
                    color = Color(0xFF58C8F8), trackColor = Color.Black.copy(alpha = 0.3f),
                )
                Spacer(Modifier.height(6.dp))
                Text("Walked %,d steps together · Friendship ${buddy.friendship}/255".format(buddy.stepsWalked), color = Soft, fontSize = 13.sp)
            }
        }
        Glass(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Grass, null, tint = Color(0xFF7AC74C))
                Text("  Next wild Pokémon in %,d steps".format(s.stepsToEncounter), color = Ink, fontWeight = FontWeight.Bold)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.CatchingPokemon, null, tint = Color(0xFFE8423A))
                Text("  Next Poké Ball in %,d steps".format(Rules.BALL_STEPS - s.ballProgress), color = Ink, fontWeight = FontWeight.Bold)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Backpack, null, tint = Color(0xFFE8A23A))
                Text("  Next item in %,d steps".format(Rules.ITEM_STEPS - s.itemProgress), color = Ink, fontWeight = FontWeight.Bold)
            }
        }
        val swarm = remember { Rules.swarm() }
        Glass(Modifier.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Pixel(Sprites.icon(swarm.id, false), Modifier.size(48.dp))
                Column(Modifier.padding(start = 8.dp)) {
                    Text("${Rules.seasonName()} · swarm: ${swarm.name}", color = Ink, fontWeight = FontWeight.Bold)
                    Text("More " + Rules.seasonTypes().joinToString(", ") { it.replaceFirstChar(Char::uppercase) } + " types this season",
                        color = Soft, fontSize = 13.sp)
                }
            }
        }
        Text("Lifetime: %,d steps".format(s.lifetimeSteps), color = Soft, fontSize = 13.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        if (!Store.hasSensor) {
            Glass(Modifier.fillMaxWidth(), tint = Color(0xFFE0703A)) {
                Text("This phone has no step counter, so steps can't be counted. You can add test steps instead:", color = Ink)
                Spacer(Modifier.height(6.dp))
                GlassButton("+500 test steps", Modifier.fillMaxWidth()) { Store.walk(500) }
            }
        }
    }
}

@Composable
fun Stat(label: String, value: String, modifier: Modifier) {
    Glass(modifier, radius = 18.dp) {
        Text(label, color = Soft, fontSize = 12.sp)
        Text(value, color = Ink, fontSize = 18.sp, fontWeight = FontWeight.Black, maxLines = 1)
    }
}

// MARK: - Wild

@Composable
fun WildScreen(onCatch: (String) -> Unit) {
    val s = Store.state
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); now = System.currentTimeMillis() } }
    ScreenColumn("Wild Pokémon") {
        val list = s.pending.filter { it.expiresAt > now }
        if (list.isEmpty()) {
            Glass(Modifier.fillMaxWidth()) {
                Text("No wild Pokémon nearby.", color = Ink, fontWeight = FontWeight.Bold)
                Text("Keep walking — one appears in about %,d steps.".format(s.stepsToEncounter), color = Soft)
            }
        }
        list.forEach { w ->
            Glass(Modifier.fillMaxWidth().clickable { onCatch(w.id) }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Pixel(Sprites.front(w.speciesID, w.isShiny), Modifier.size(80.dp))
                    Column(Modifier.weight(1f).padding(start = 8.dp)) {
                        Text(w.species.name + if (w.isShiny) " ✨" else "", color = Ink, fontSize = 19.sp, fontWeight = FontWeight.Black)
                        Text("Lv. ${w.level}" + if (w.speciesID in s.dexCaught) " · Caught before" else " · New!", color = Soft)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { w.species.types.forEach { TypeChip(it) } }
                        val mins = ((w.expiresAt - now) / 60_000).coerceAtLeast(0)
                        Text("Leaves in ${mins / 60}h ${mins % 60}m", color = Soft, fontSize = 12.sp)
                    }
                    Icon(Icons.Filled.ChevronRight, null, tint = Ink)
                }
            }
        }
    }
}

/** The catching screen: your buddy's back, the wild Pokémon, and a ball that arcs, shakes and clicks. */
@Composable
fun CatchScreen(w: Wild, close: () -> Unit) {
    val s = Store.state
    val scope = rememberCoroutineScope()
    var message by remember { mutableStateOf(if (w.isShiny) "A shiny ${w.species.name} appeared!" else "A wild ${w.species.name} appeared!") }
    var ball by remember { mutableStateOf(BallKind.entries.firstOrNull { s.ballCount(it) > 0 && it != BallKind.MASTER } ?: BallKind.POKE) }
    var busy by remember { mutableStateOf(false) }
    var turn by remember { mutableIntStateOf(0) }
    var done by remember { mutableStateOf(false) }
    var hidden by remember { mutableStateOf(false) }
    var ballVisible by remember { mutableStateOf(false) }
    val t = remember { Animatable(0f) }          // 0 → 1 flight
    val wobble = remember { Animatable(0f) }
    val caughtBefore = w.speciesID in s.dexCaught
    LaunchedEffect(Unit) { Cry.play(w.speciesID) }

    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF7FB8D8), Color(0xFFBFE3C8), Color(0xFF3E6B4A)))).clickable(enabled = false) {}) {
        Column(Modifier.fillMaxSize().systemBarsPadding().padding(16.dp)) {
            // The scene
            BoxWithConstraints(Modifier.fillMaxWidth().weight(1f)) {
                val W = maxWidth; val H = maxHeight
                // platforms
                Canvas(Modifier.fillMaxSize()) {
                    drawOval(Color.White.copy(alpha = 0.35f), Offset(size.width * 0.42f, size.height * 0.36f), Size(size.width * 0.56f, size.height * 0.1f))
                    drawOval(Color.White.copy(alpha = 0.35f), Offset(-size.width * 0.05f, size.height * 0.86f), Size(size.width * 0.62f, size.height * 0.12f))
                }
                if (!hidden) {
                    Pixel(Sprites.front(w.speciesID, w.isShiny),
                        Modifier.size(W * 0.42f).offset(x = W * 0.49f, y = H * 0.41f - W * 0.40f))
                }
                s.buddy?.let { b ->
                    Pixel(Sprites.back(b.speciesID, b.isShiny), Modifier.size(W * 0.5f).offset(x = W * 0.04f, y = H * 0.93f - W * 0.47f))
                }
                if (ballVisible) {
                    val p = t.value
                    val x0 = W.value * 0.2f; val y0 = H.value * 0.8f
                    val x1 = W.value * 0.70f; val y1 = H.value * 0.36f
                    val x = x0 + (x1 - x0) * p
                    val y = y0 + (y1 - y0) * p - 4 * p * (1 - p) * H.value * 0.25f
                    Pixel(Sprites.item(ball.itemKey), Modifier.size(34.dp).offset(x = x.dp - 17.dp, y = y.dp - 17.dp)
                        .rotate(if (p < 1f) p * 720 else wobble.value))
                }
                Glass(Modifier.align(Alignment.TopStart).fillMaxWidth(0.6f), radius = 16.dp) {
                    Text(w.species.name + " " + if (w.gender == "female") "♀" else if (w.gender == "male") "♂" else "", color = Ink, fontWeight = FontWeight.Black, fontSize = 18.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Lv. ${w.level}", color = Soft)
                        w.species.types.forEach { TypeChip(it) }
                    }
                }
            }
            // Text box
            Glass(Modifier.fillMaxWidth().heightIn(min = 70.dp), tint = Teal) {
                Text(message, color = Ink, fontWeight = FontWeight.Bold, fontSize = 17.sp)
            }
            Spacer(Modifier.height(10.dp))
            if (!done) {
                // Ball picker
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BallKind.entries.filter { s.ballCount(it) > 0 }.take(5).forEach { b ->
                        Column(
                            Modifier.weight(1f).clip(RoundedCornerShape(14.dp))
                                .background(if (b == ball) Color.White.copy(alpha = 0.35f) else Color.White.copy(alpha = 0.12f))
                                .clickable { ball = b }.padding(6.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Pixel(Sprites.item(b.itemKey), Modifier.size(30.dp))
                            Text("×${s.ballCount(b)}", color = Ink, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                val chance = (Rules.catchChance(w, ball, turn, caughtBefore) * 100).toInt().coerceIn(1, 100)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    GlassButton("Run", Modifier.weight(1f), icon = Icons.Filled.DirectionsRun, enabled = !busy) { close() }
                    GlassButton("Throw ${ball.title} · $chance%", Modifier.weight(2f), tint = Color(0xFFE8423A),
                        enabled = !busy && s.ballCount(ball) > 0) {
                        busy = true
                        scope.launch {
                            Store.mutate { it.balls[ball.name] = it.ballCount(ball) - 1 }
                            message = "${s.trainerName} threw a ${ball.title}!"
                            turn += 1
                            ballVisible = true
                            t.snapTo(0f); wobble.snapTo(0f)
                            t.animateTo(1f, tween(600))
                            hidden = true
                            delay(400)
                            val p = Rules.shakeProbability(Rules.modifiedRate(w, ball, turn - 1, caughtBefore))
                            var passes = 0
                            while (passes < 4 && Random.nextDouble() < p) passes++
                            repeat(minOf(passes, 3)) {
                                wobble.animateTo(-25f, tween(150)); wobble.animateTo(25f, tween(250)); wobble.animateTo(0f, tween(150))
                                delay(450)
                            }
                            if (passes == 4) {
                                message = "Gotcha! ${w.species.name} was caught!"
                                Store.mutate { st ->
                                    val sp = w.species
                                    val mon = Mon(
                                        speciesID = w.speciesID, exp = Growth.exp(sp.growth, w.level), gender = w.gender,
                                        isShiny = w.isShiny, nature = w.nature, personality = w.personality,
                                        friendship = sp.baseFriendship, ball = ball.name, metDate = System.currentTimeMillis(), metLevel = w.level,
                                    )
                                    Rules.store(mon, st)
                                    st.pending.removeAll { it.id == w.id }
                                }
                                done = true
                            } else {
                                ballVisible = false; hidden = false
                                Cry.play(w.speciesID)
                                message = listOf("Oh no! It broke free!", "Aww! It appeared to be caught!", "Aargh! Almost had it!", "Shoot! It was so close too!")[minOf(passes, 3)]
                                delay(900)
                                if (Random.nextDouble() < Rules.fleeChance(w)) {
                                    message = "Wild ${w.species.name} fled!"
                                    hidden = true
                                    Store.mutate { st -> st.pending.removeAll { it.id == w.id } }
                                    done = true
                                } else if (Store.state.totalBalls == 0) {
                                    message = "You're out of balls! Walk to earn more."
                                }
                            }
                            busy = false
                        }
                    }
                }
            } else {
                GlassButton("Done", Modifier.fillMaxWidth(), tint = Color(0xFFF5A623)) { close() }
            }
        }
    }
}

// MARK: - Party & PC

@Composable
fun PartyScreen() {
    val s = Store.state
    var open by remember { mutableStateOf<String?>(null) }
    ScreenColumn("Party") {
        s.party.forEach { m -> MonRow(m, m.id == s.buddyID) { open = m.id } }
        if (s.boxed.isNotEmpty()) {
            Text("PC Box · ${s.boxed.size}", color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Black)
            s.boxed.chunked(5).forEach { row ->
                Row(Modifier.fillMaxWidth()) {
                    row.forEach { m ->
                        Column(Modifier.weight(1f).clickable { open = m.id }, horizontalAlignment = Alignment.CenterHorizontally) {
                            Pixel(Sprites.icon(m.speciesID, m.isShiny), Modifier.size(56.dp))
                            Text("Lv${m.level}", color = Soft, fontSize = 11.sp)
                        }
                    }
                    repeat(5 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
    open?.let { id -> Store.state.mon(id)?.let { SummaryDialog(it) { open = null } } ?: run { open = null } }
}

@Composable
fun MonRow(m: Mon, isBuddy: Boolean, onClick: () -> Unit) {
    Glass(Modifier.fillMaxWidth().clickable(onClick = onClick), radius = 18.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Pixel(Sprites.icon(m.speciesID, m.isShiny), Modifier.size(56.dp))
            Column(Modifier.weight(1f).padding(start = 8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(m.name + if (m.isShiny) " ✨" else "", color = Ink, fontWeight = FontWeight.Black, fontSize = 17.sp)
                    if (isBuddy) Text("  BUDDY", color = Color(0xFFF5A623), fontWeight = FontWeight.Black, fontSize = 11.sp)
                }
                LinearProgressIndicator(
                    progress = { Growth.progress(m.species.growth, m.exp) },
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp).height(5.dp).clip(RoundedCornerShape(3.dp)),
                    color = Color(0xFF58C8F8), trackColor = Color.Black.copy(alpha = 0.3f),
                )
            }
            Text("  Lv. ${m.level}", color = Color(0xFF9FE3F0), fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun SummaryDialog(m: Mon, close: () -> Unit) {
    val s = Store.state
    val inParty = m.id in s.partyIDs
    val evo = Rules.pendingEvolution(m, ignoringDecline = true)
    AlertDialog(
        onDismissRequest = close,
        containerColor = Color(0xFF1E3A44),
        confirmButton = { TextButton(onClick = close) { Text("Close") } },
        title = { Text(m.name + if (m.isShiny) " ✨" else "", fontWeight = FontWeight.Black) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Pixel(Sprites.front(m.speciesID, m.isShiny), Modifier.size(110.dp).clickable { Cry.play(m.speciesID) })
                    Column(Modifier.padding(start = 8.dp)) {
                        Text("${m.species.name} · Lv. ${m.level} ${m.genderSymbol}", fontWeight = FontWeight.Bold)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { m.species.types.forEach { TypeChip(it) } }
                        Text("${m.nature} nature", fontSize = 13.sp)
                        Text("Friendship ${m.friendship}/255", fontSize = 13.sp)
                        Text("%,d steps walked".format(m.stepsWalked), fontSize = 13.sp)
                        Text("Caught in a ${BallKind.valueOf(m.ball).title} at Lv. ${m.metLevel}", fontSize = 12.sp)
                    }
                }
                val next = m.species.evolutions.joinToString("\n") { r ->
                    val n = if (r.into in s.dexCaught) Dex.species(r.into).name else "???"
                    when (r.kind) {
                        "level" -> "→ $n at Lv. ${r.level}"
                        "item" -> "→ $n with ${Dex.itemName(r.item ?: "")}"
                        else -> "→ $n with high friendship" + (r.time?.let { " ($it)" } ?: "")
                    }
                }
                if (next.isNotEmpty()) Text(next, fontSize = 13.sp)
                if (inParty && m.id != s.buddyID) {
                    Button(onClick = { Store.mutate { it.buddyID = m.id }; Store.toast = "${m.name} is your walking buddy!" }, modifier = Modifier.fillMaxWidth()) {
                        Text("Walk with ${m.name}")
                    }
                }
                if (evo != null) {
                    Button(onClick = { Store.evolution = m.id to evo; close() }, modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF5A623))) { Text("Evolve!") }
                }
                if (inParty && m.id != s.buddyID && s.party.size > 1) {
                    OutlinedButton(onClick = { Store.mutate { it.partyIDs.remove(m.id) } }, modifier = Modifier.fillMaxWidth()) { Text("Send to the PC") }
                }
                if (!inParty) {
                    OutlinedButton(onClick = { Store.mutate { it.partyIDs.add(m.id) } }, enabled = s.partyIDs.size < Rules.MAX_PARTY,
                        modifier = Modifier.fillMaxWidth()) { Text(if (s.partyIDs.size < Rules.MAX_PARTY) "Add to party" else "Party is full") }
                }
            }
        },
    )
}

@Composable
fun BoxScope.EvolutionHost() {
    val e = Store.evolution ?: return
    val m = Store.state.mon(e.first) ?: run { Store.evolution = null; return }
    var stage by remember(e) { mutableIntStateOf(0) }     // 0 asking, 1 evolving, 2 done
    val flash = remember(e) { Animatable(0f) }
    LaunchedEffect(stage) {
        if (stage == 1) {
            repeat(6) { flash.animateTo(1f, tween(180)); flash.animateTo(0f, tween(180)) }
            val old = m.name
            Store.mutate { Rules.evolve(it.mon(m.id)!!, e.second, it) }
            Cry.play(e.second)
            Store.toast = "Congratulations! $old evolved into ${Dex.species(e.second).name}!"
            stage = 2
        }
    }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.75f)).clickable(enabled = false) {}, contentAlignment = Alignment.Center) {
        Glass(Modifier.padding(24.dp).fillMaxWidth()) {
            val shown = if (stage == 2) e.second else m.speciesID
            Box(Modifier.fillMaxWidth().height(180.dp), contentAlignment = Alignment.Center) {
                Pixel(Sprites.front(shown, m.isShiny), Modifier.size(170.dp))
                Box(Modifier.size(150.dp).alpha(flash.value).clip(CircleShape).background(Color.White))
            }
            Text(
                when (stage) { 0 -> "What? ${m.name} is evolving!"; 1 -> "…"; else -> "${m.name} became ${Dex.species(e.second).name}!" },
                color = Ink, fontWeight = FontWeight.Black, fontSize = 18.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))
            when (stage) {
                0 -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    GlassButton("Not now", Modifier.weight(1f)) {
                        Store.mutate { it.mon(m.id)?.declinedAtLevel = m.level }; Store.evolution = null
                    }
                    GlassButton("Evolve", Modifier.weight(1f), tint = Color(0xFFF5A623)) { stage = 1 }
                }
                2 -> GlassButton("Great!", Modifier.fillMaxWidth(), tint = Color(0xFFF5A623)) { Store.evolution = null }
                else -> {}
            }
        }
    }
}

// MARK: - Bag & shop

@Composable
fun BagScreen() {
    val s = Store.state
    var using by remember { mutableStateOf<String?>(null) }
    ScreenColumn("Bag") {
        Glass(Modifier.fillMaxWidth()) {
            Text("Money  ₽%,d".format(s.money), color = Ink, fontWeight = FontWeight.Black, fontSize = 18.sp)
        }
        Text("Balls", color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Black)
        BallKind.entries.filter { s.ballCount(it) > 0 }.forEach { b ->
            Glass(Modifier.fillMaxWidth(), radius = 16.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Pixel(Sprites.item(b.itemKey), Modifier.size(36.dp))
                    Column(Modifier.weight(1f).padding(start = 8.dp)) {
                        Text(b.title, color = Ink, fontWeight = FontWeight.Bold)
                        Text(b.effect, color = Soft, fontSize = 12.sp)
                    }
                    Text("×${s.ballCount(b)}", color = Ink, fontWeight = FontWeight.Black)
                }
            }
        }
        Text("Items", color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Black)
        if (s.bag.isEmpty()) Text("Nothing yet — items turn up every 1,500 steps.", color = Soft)
        s.bag.entries.sortedBy { Dex.itemName(it.key) }.forEach { (k, n) ->
            Glass(Modifier.fillMaxWidth(), radius = 16.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Pixel(Sprites.item(k), Modifier.size(36.dp))
                    Column(Modifier.weight(1f).padding(start = 8.dp)) {
                        Text("${Dex.itemName(k)} ×$n", color = Ink, fontWeight = FontWeight.Bold)
                        Text(Rules.describe(k), color = Soft, fontSize = 12.sp)
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
                    if (!Rules.sellPrice.containsKey(k)) GlassButton("Use", Modifier.weight(1f)) { using = k }
                    val price = Rules.price(k) ?: 0
                    GlassButton("Sell ₽$price", Modifier.weight(1f)) {
                        Store.mutate { st ->
                            st.bag[k] = (st.bag[k] ?: 1) - 1
                            if ((st.bag[k] ?: 0) <= 0) st.bag.remove(k)
                            st.money += price
                        }
                    }
                }
            }
        }
        Text("Poké Mart", color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Black)
        Rules.shop.forEach { (b, price) ->
            Glass(Modifier.fillMaxWidth(), radius = 16.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Pixel(Sprites.item(b.itemKey), Modifier.size(36.dp))
                    Column(Modifier.weight(1f).padding(start = 8.dp)) {
                        Text(b.title, color = Ink, fontWeight = FontWeight.Bold)
                        Text("₽%,d".format(price), color = Soft, fontSize = 12.sp)
                    }
                    GlassButton("Buy", enabled = s.money >= price) {
                        Store.mutate { it.money -= price; it.balls[b.name] = it.ballCount(b) + 1 }
                        Store.toast = "Bought a ${b.title}."
                    }
                }
            }
        }
    }
    using?.let { item ->
        AlertDialog(
            onDismissRequest = { using = null }, containerColor = Color(0xFF1E3A44),
            confirmButton = { TextButton(onClick = { using = null }) { Text("Cancel") } },
            title = { Text("Use ${Dex.itemName(item)} on…") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    s.party.forEach { m ->
                        val able = Rules.canUse(item, m)
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).alpha(if (able) 1f else 0.4f)
                                .clickable(enabled = able) {
                                    using = null
                                    useItem(item, m)
                                }.padding(6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Pixel(Sprites.icon(m.speciesID, m.isShiny), Modifier.size(44.dp))
                            Text("${m.name}  Lv. ${m.level}", Modifier.weight(1f))
                            Text(if (able) "ABLE" else "NOT ABLE", fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            },
        )
    }
}

fun useItem(item: String, m: Mon) {
    var evolveInto: Int? = null
    Store.mutate { st ->
        val mon = st.mon(m.id) ?: return@mutate
        when {
            item == "rare-candy" -> {
                mon.exp = Growth.exp(mon.species.growth, mon.level + 1)
                mon.friendship = minOf(255, mon.friendship + 3)
                Store.toast = "${mon.name} grew to Lv. ${mon.level}!"
                evolveInto = Rules.pendingEvolution(mon)
            }
            item in Rules.berries -> {
                mon.friendship = minOf(255, mon.friendship + if (mon.friendship < 100) 10 else if (mon.friendship < 200) 5 else 2)
                Store.toast = "${mon.name} enjoyed the berry!"
            }
            else -> evolveInto = Rules.itemEvolution(mon, item)
        }
        st.bag[item] = (st.bag[item] ?: 1) - 1
        if ((st.bag[item] ?: 0) <= 0) st.bag.remove(item)
    }
    evolveInto?.let { Store.evolution = m.id to it }
}

// MARK: - Pokédex

@Composable
fun DexScreen() {
    val s = Store.state
    var open by remember { mutableStateOf<Species?>(null) }
    Column(Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = 16.dp)) {
        Text("Pokédex", color = Ink, fontSize = 30.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(top = 16.dp))
        Text("Seen ${s.dexSeen.size} · Caught ${s.dexCaught.size} / ${Dex.count}", color = Soft)
        Spacer(Modifier.height(8.dp))
        LazyVerticalGrid(GridCells.Adaptive(76.dp), verticalArrangement = Arrangement.spacedBy(6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items(Dex.all, key = { it.id }) { sp ->
                val caught = sp.id in s.dexCaught; val seen = sp.id in s.dexSeen
                Column(
                    Modifier.clip(RoundedCornerShape(14.dp)).background(Color.White.copy(alpha = if (caught) 0.16f else 0.06f))
                        .clickable(enabled = seen) { open = sp }.padding(4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (seen) Pixel(Sprites.icon(sp.id, false), Modifier.size(52.dp), silhouette = !caught)
                    else Box(Modifier.size(52.dp), contentAlignment = Alignment.Center) { Text("?", color = Soft, fontSize = 22.sp) }
                    Text("%03d".format(sp.id), color = Soft, fontSize = 10.sp)
                }
            }
        }
    }
    open?.let { sp ->
        val caught = sp.id in s.dexCaught
        AlertDialog(
            onDismissRequest = { open = null }, containerColor = Color(0xFF1E3A44),
            confirmButton = { TextButton(onClick = { open = null }) { Text("Close") } },
            title = { Text("No. %03d  %s".format(sp.id, sp.name)) },
            text = {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Pixel(Sprites.front(sp.id, false), Modifier.size(140.dp).clickable { Cry.play(sp.id) }, silhouette = !caught)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { sp.types.forEach { TypeChip(it) } }
                    Spacer(Modifier.height(6.dp))
                    Text(if (caught) "Caught" else "Seen, not caught yet", fontSize = 13.sp)
                    Text("Catch rate ${sp.captureRate}" + if (sp.isLegendary) " · Legendary" else if (sp.isMythical) " · Mythical" else "", fontSize = 13.sp)
                }
            },
        )
    }
}
