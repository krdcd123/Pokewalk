# PokéWalk v2: a Pokéwalker × Safari Zone for iPhone and Apple Watch

Walk with your Apple Watch and your buddy levels up. A wild Pokémon appears about every **500 steps** and you get a notification. You catch it **Safari Zone-style**: tap to throw a ball and the odds decide, or give bait, or run. You earn a ball every **100 steps**. A clean map shows **where you've walked** and **where each Pokémon was caught**. A full **PC** keeps track of nicknames, Trainer ID, met location and more.

## What's in it

| | |
|---|---|
| **Map home** | Today's route drawn on the map, your buddy's animated sprite where you are, pins for the Pokémon you caught today and for wild ones waiting. Shows today's steps and km, your ball count, and progress to the next encounter and the next ball. |
| **Encounters** | Every ~500 steps (randomised 400–600, adjustable). Random, weighted by each species' real catch rate: common Pokémon make up about 86% of encounters, rare ones like Snorlax or Chansey about 0.003% each, and **legendaries about 0.01%** (1 in 10,000) per encounter. Nearby places give a gentle nudge (parks → Grass/Bug, water → Water), and Ghost/Dark types are a bit more common at night. Up to 5 can wait for you; each lasts 4 hours. |
| **Catching** | **Tap the ball** to throw it. Whether it's caught is pure chance, using the real Gen 3 shake-check formula with each species' catch rate and the ball's bonus, so you see 0–3 wobbles. The screen shows your current % chance. **Bait** makes it much less likely to flee (slightly harder to catch while it eats). **Run** leaves. |
| **Rewards** | 1 Poké Ball per 100 steps (every 10th is a Great Ball, every 50th an Ultra Ball). 1 item per 1,500 steps: Rare Candy, Exp. Candies, all evolution stones, trade items. |
| **Buddy** | 1 Exp per step (1×/2×/5×/10×). Real growth-rate curves per species. Friendship rises as you walk (+1 per 100 steps). |
| **Evolution** | All Gen 1–3 methods: level, stones, friendship (with day/night, e.g. Espeon/Umbreon), held items (used from the bag), and trades (use a **Linking Cord** or the trade item). Branching evolutions such as Wurmple and Tyrogue use the Pokémon's personality value, as in the games. Nincada gives you a Shedinja too. Evolutions into Gen 4 Pokémon (Magnezone, Togekiss…) aren't included yet. |
| **PC** | Party of 6 plus boxes of 30 (box names, wallpapers, add boxes). **Move** mode to pick up and swap anywhere. Search by name, species or place. |
| **Summary** | Nickname, gender, shiny, OT, **ID No.**, met date and level, **met location with a map**, ball, nature, characteristic, friendship, steps walked, where it's stored. |
| **Journal** | A map of any day's walks (or all time) with catch pins, distance, steps and a list of walks. |
| **Pokédex** | 386 species (Gen 1–3: Kanto, Johto, Hoenn). Seen/caught, filter by generation, habitats and evolution info. |
| **Shinies** | Every wild Pokémon (and your starter) has a random **1 in 1,000 chance** to be shiny. It's a fresh roll each time, not a guaranteed shiny every 1,000th, so you could get two in a row or none for a long while. Adjustable in Settings. |
| **Trainer card** | Name, 5-digit Trainer ID, start date, dex counts, lifetime steps, distance tracked. |
| **Apple Watch** | **Comes inside the iPhone app, like Spotify's.** Install PokéWalk on your iPhone and the Watch app installs itself on your paired Watch. Buddy page (live level, Exp, balls, steps to next encounter) and party list, both using each Pokémon's **party icon**. **Complications**: circular (icon + level ring), rectangular, corner and inline. One option per party member plus "Walking Buddy". |
| **Live Activity** | On the Lock Screen and in the Dynamic Island. On watchOS 11+ it also appears in the Watch **Smart Stack**. |

Mockups of the screens: see the design canvas linked in the chat.

---

## Building on Windows (no Mac needed)

Apple's tools only run on macOS, so a **free GitHub-hosted Mac** builds the app for you. You then install it from Windows with **Sideloadly**.

### 1. Put the project on GitHub
1. Create a free account at github.com, then **New repository** (e.g. `pokewalk`).
   - **Public** repos get unlimited free Mac build minutes.
   - **Private** repos get 2,000 free minutes a month, but Mac minutes count 10×. That's roughly 12–15 builds a month.
2. Upload this whole folder, including the hidden `.github` folder. The easiest ways:
   - **GitHub Desktop**: clone the empty repo, copy these files in, then commit and push.
   - The website: **Add file › Upload files**, then drag in everything. Check that `.github/workflows/build-ipa.yml` arrived.

### 2. Build the IPA
1. Open your repo's **Actions** tab, then **Build IPA**, then **Run workflow**.
2. Enter a **bundle ID prefix** unique to you, e.g. `com.yourname`. Click **Run**.
3. After about 10–15 minutes, open the finished run and download the **PokeWalk-ipa** artifact (a zip). Inside are:
   - `PokeWalk.ipa`: the iPhone app plus the Watch app and complications.
   - `PokeWalk-iPhone-only.ipa`: a fallback without the Watch app.

If a build fails, download the `build-log` artifact and send it to me. I'll fix the error.

### 3. Install with Sideloadly (Windows)
1. Install **iTunes** and **iCloud** from Apple's website (*not* the Microsoft Store versions), then install **Sideloadly** from sideloadly.io.
2. Plug in your iPhone and tap **Trust**. Turn on **Settings › Privacy & Security › Developer Mode** (the phone restarts).
3. Drag `PokeWalk.ipa` into Sideloadly, enter your Apple ID and click **Start**. A spare Apple ID is a good idea.
4. On the iPhone: **Settings › General › VPN & Device Management**, then trust your Apple ID.
5. Open PokéWalk and allow Health, Motion, Notifications and Location. Choose **Allow While Using App**, then **Change to Always Allow** when asked.

With a free Apple ID, apps expire after **7 days**. Re-sideload the same IPA to refresh it; your save data is kept. This app uses 4 App IDs: the app, Live Activity, Watch app and complications. Free accounts can create 10 a week.

### About the Watch app
The Watch app is **bundled inside the iPhone app**, the same way Spotify's is. There's nothing separate to install: when PokéWalk lands on your iPhone, watchOS installs the Watch app automatically, as long as **Watch app on iPhone › General › Automatic App Install** is on. Otherwise, find PokéWalk under **Available Apps** in the Watch app and tap **Install**. **Settings › Apple Watch** in PokéWalk shows whether it's installed.

The one difference from Spotify is signing. App Store apps are trusted everywhere. A sideloaded app is signed with your own Apple ID, and Sideloadly is built mainly for iPhone apps, so it may not sign the bundled Watch app properly. If the Watch app doesn't appear:
- The Watch may need **Developer Mode** (Watch › Settings › Privacy & Security). On some watches that switch only appears after the watch has been connected to Xcode on a Mac once.
- You still get your buddy on your wrist: the **Live Activity** (buddy icon, level, steps to the next encounter, wild Pokémon waiting) shows in the Watch Smart Stack on watchOS 11+, and encounter notifications show on the Watch.
- Use `PokeWalk-iPhone-only.ipa` if Sideloadly refuses the full IPA.
- For guaranteed Watch complications, run the project from Xcode on a Mac once (a friend's Mac or a rented cloud Mac). Xcode installs the iPhone and Watch apps together, just like the App Store.

---

## Your Gen 5 animated sprites

Use whichever way is easiest:
- **In the app**: **Menu › Settings › Sprites › Import … folder** and pick a folder from Files (iCloud Drive, On My iPhone, etc.).
- **Files app**: copy into **On My iPhone › PokéWalk › Sprites** (`front/`, `shiny/`, `icons/`, `items/`).
- **Bundled at build time**: put them in this repo's `Sprites/` folder before running the workflow.

File names can be the Pokédex number (`25.gif`, `025.gif`) or the name (`pikachu.gif`, `mrmime.gif`, `nidoranf.gif`). Showdown-style names work.

| Folder | Used for |
|---|---|
| `front/` | Animated sprites everywhere on the phone: map buddy, encounters, summary, Pokédex. Only #1–386 are used for now. |
| `shiny/` | Shiny versions |
| `icons/` | **Party/box icons**: the Watch app, complications, Live Activity, PC grid and map pins |
| `items/` | `poke-ball.png`, `great-ball.png`, `ultra-ball.png`, `rare-candy.png`, `fire-stone.png` … |

Anything you don't provide is downloaded once from the PokeAPI sprite repo (the Gen 5 Black/White animated set and Gen 7 icons) and cached.

Want Gen 4 or 5 later? Change `MAX = 386` in `tools/gen_dex.py` to 493 or 649, run `python tools/gen_dex.py <pokeapi csv folder> Shared/Resources/dex.json`, and rebuild.

---

## Location, steps and battery

- **Tracking modes** (Settings):
  - **Always (Adventure mode)** records your walks all day. It uses iOS's walking-tuned location updates, which pause automatically when you're still.
  - **Only during walks** adds a Start/End walk button to the map.
  - **Off** turns tracking off.
- Steps come from two places, and the higher count is used for each day:
  - the iPhone's motion chip, which works with the phone locked in your pocket, so encounters pop up live mid-walk;
  - **HealthKit**, which includes Apple Watch steps when you leave the phone behind. Those steps turn into rewards the next time the app wakes (opening it, or HealthKit's roughly hourly background update).
- Driving and GPS noise are filtered out of your tracks: points faster than ~16 km/h, or with poor accuracy, aren't recorded.
- Walk tracks are stored only on your phone (`Tracks/` in the app's Files folder).

## Notes on the Pokémon data
- Species, types, catch rates, growth rates, gender ratios, habitats and evolutions come from **PokeAPI's open data** (`Shared/Resources/dex.json`, generated by `tools/gen_dex.py`).
- A few game-only evolution conditions are adapted for walking:
  - "level up knowing a move" or "with a party member" → Lv 33;
  - location-based evolutions → the modern stone (Magnezone/Probopass: Thunder Stone, Leafeon: Leaf Stone, Glaceon: Ice Stone);
  - trades → Linking Cord or the trade item.

## Project layout
```
Shared/              game engine + data, used by every target
  Dex.swift          species, growth-rate formulas, evolution rules (loads Resources/dex.json)
  GameModels.swift   trainer, Pokémon (OT/ID/met data), PC boxes, balls, settings
  GameRules.swift    steps → Exp/balls/items/encounters, evolution, PC moves, Safari catch maths
  WatchSnapshot.swift, StepCounter.swift, SharedUI.swift, WalkActivity.swift
iOS/                 iPhone app
  GameStore.swift    the save game and step processing
  Services/          location tracking + walk tracks, step engine, places/habitats, sprites (GIF), Live Activity
  Views/             map home, Safari encounter, caught, PC, summary, journal, Pokédex, bag, trainer, settings
LiveActivity/        Lock Screen / Dynamic Island / Watch Smart Stack
Watch/, Complications/   Watch app + WidgetKit complications
Sprites/             optional sprites bundled at build time
.github/workflows/   the Windows-friendly cloud build
ci/package-ipa.sh    signs bundles with their entitlements and zips the IPAs
tools/gen_dex.py     regenerates dex.json from PokeAPI CSVs
```

*Pokémon is © Nintendo / Creatures / GAME FREAK. This is an unofficial fan project for personal use.*
