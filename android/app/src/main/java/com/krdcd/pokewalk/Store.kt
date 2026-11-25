package com.krdcd.pokewalk

import android.app.Application
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.neverEqualPolicy
import androidx.compose.runtime.setValue
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.decode.GifDecoder
import coil.decode.ImageDecoderDecoder
import coil.disk.DiskCache
import kotlin.math.min

class PokeWalkApp : Application(), ImageLoaderFactory {
    override fun onCreate() {
        super.onCreate()
        Dex.load(this)
        Store.init(this)
    }

    // Animated sprites (GIFs), cached on disk so they're only downloaded once
    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .components { if (Build.VERSION.SDK_INT >= 28) add(ImageDecoderDecoder.Factory()) else add(GifDecoder.Factory()) }
        .diskCache { DiskCache.Builder().directory(cacheDir.resolve("sprites")).maxSizeBytes(200L * 1024 * 1024).build() }
        .crossfade(false)
        .build()
}

/** Sprite and cry URLs: the same sources as the iOS app (PokéAPI and PokeSprite on GitHub). */
object Sprites {
    private const val BASE = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites"
    fun front(id: Int, shiny: Boolean) = "$BASE/pokemon/versions/generation-v/black-white/animated/${if (shiny) "shiny/" else ""}$id.gif"
    fun back(id: Int, shiny: Boolean) = "$BASE/pokemon/versions/generation-v/black-white/animated/back/${if (shiny) "shiny/" else ""}$id.gif"
    fun icon(id: Int, shiny: Boolean) =
        "https://raw.githubusercontent.com/msikma/pokesprite/master/pokemon-gen8/${if (shiny) "shiny" else "regular"}/${Dex.species(id).key}.png"
    fun item(key: String) = "$BASE/items/$key.png"
    fun cry(id: Int) = "https://raw.githubusercontent.com/PokeAPI/cries/main/cries/pokemon/legacy/$id.ogg"
}

object Cry {
    private var player: MediaPlayer? = null
    fun play(id: Int) {
        runCatching {
            player?.release()
            player = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).build())
                setDataSource(Sprites.cry(id))
                setVolume(0.6f, 0.6f)
                setOnPreparedListener { it.start() }
                setOnCompletionListener { it.release(); if (player === it) player = null }
                prepareAsync()
            }
        }
    }
}

/** The game, the step counter and the little pop-up messages. */
object Store : SensorEventListener {
    private lateinit var app: Context
    var state by mutableStateOf(GameState(), neverEqualPolicy())
        private set
    var toast by mutableStateOf<String?>(null)
    var evolution by mutableStateOf<Pair<String, Int>?>(null)    // mon id → new species
    var hasSensor by mutableStateOf(true)
    private var listening = false

    fun init(ctx: Context) {
        app = ctx.applicationContext
        state = Save.load(app)
    }

    /** Change the game and save it. */
    fun mutate(block: (GameState) -> Unit) {
        val s = state
        block(s)
        state = s
        Save.write(app, s)
    }

    fun newGame(name: String, starter: Int, nickname: String?, shiny: Boolean) {
        state = Rules.newGame(name, starter, nickname, shiny)
        Save.write(app, state)
        lastSensorSeen = -1
        startSteps(app)
    }

    // MARK: Steps (the phone's hardware step counter keeps counting while the app is closed)

    private var lastSensorSeen = -1L

    fun startSteps(ctx: Context) {
        if (listening || !state.started) return
        val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        hasSensor = sensor != null
        if (sensor == null) return
        listening = sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    fun stopSteps(ctx: Context) {
        if (!listening) return
        (ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager).unregisterListener(this)
        listening = false
    }

    override fun onSensorChanged(event: SensorEvent) {
        val total = event.values[0].toLong()
        val last = state.lastSensorValue
        val delta = when {
            last < 0 -> 0L                    // first reading: start counting from here
            total >= last -> total - last
            else -> total                     // the phone restarted (counter reset)
        }
        mutate { it.lastSensorValue = total }
        if (delta > 0) walk(min(delta, 200_000L).toInt())
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    fun walk(steps: Int) {
        var out = StepOutcome()
        mutate { out = Rules.apply(steps, it) }
        val lines = mutableListOf<String>()
        if (out.newLevel > out.oldLevel && out.oldLevel > 0) lines += "${state.buddy?.name} grew to Lv. ${out.newLevel}!"
        if (out.newEncounters.isNotEmpty()) {
            val w = out.newEncounters.last()
            lines += if (w.isShiny) "A shiny ${w.species.name} appeared! ✨" else "A wild ${w.species.name} appeared!"
        }
        out.ballsEarned.forEach { (b, n) -> lines += "Found $n × ${b.title}" }
        out.itemsFound.forEach { lines += "Found a ${Dex.itemName(it)}!" }
        if (lines.isNotEmpty()) toast = lines.joinToString("\n")
        out.evolutionReady?.let { if (evolution == null) evolution = it }
    }
}
