#!/usr/bin/env python3
"""Builds Shared/Resources/moves.json from PokéAPI's CSVs: Gen 3 (Emerald) move data and level-up learnsets.

Usage: gen_moves.py <csv dir> <pogo_assets move sound list> <out.json>
Move data is rolled back to its Emerald values with move_changelog (power/accuracy/type changes in later games).
"""
import csv, json, sys, collections

d, sounds_list, out = sys.argv[1], sys.argv[2], sys.argv[3]
def rows(n): return list(csv.DictReader(open(f"{d}/{n}.csv", encoding="utf-8")))
def num(v): return int(v) if v not in ("", None) else None

types = {r["id"]: r["identifier"] for r in rows("types")}
names = {r["move_id"]: r["name"] for r in rows("move_names") if r["local_language_id"] == "9"}
meta = {r["move_id"]: r for r in rows("move_meta")}
stats = collections.defaultdict(list)
for r in rows("move_meta_stat_changes"): stats[r["move_id"]].append([int(r["stat_id"]), int(r["change"])])
changes = collections.defaultdict(list)
for r in rows("move_changelog"): changes[r["move_id"]].append(r)
EMERALD = 6

flags = collections.defaultdict(set)
for r in rows("move_flag_map"): flags[int(r["move_id"])].add(int(r["move_flag_id"]))

moves = {}
for r in rows("moves"):
    if int(r["id"]) > 354: continue          # Gen 1-3 moves only
    v = dict(r)
    # Roll later changes back: the earliest change after Emerald holds the value Emerald used
    for f in ("type_id", "power", "pp", "accuracy", "priority", "effect_id", "effect_chance"):
        later = sorted((c for c in changes[r["id"]] if int(c["changed_in_version_group_id"]) > EMERALD and c.get(f)),
                       key=lambda c: int(c["changed_in_version_group_id"]))
        if later: v[f] = later[0][f]
    m = meta.get(r["id"], {})
    moves[int(r["id"])] = {
        "id": int(r["id"]), "key": r["identifier"], "name": names.get(r["id"], r["identifier"]),
        "type": {"unknown": "ghost", "shadow": "dark"}.get(types[v["type_id"]], types[v["type_id"]]), "power": num(v["power"]), "pp": num(v["pp"]) or 1,
        "accuracy": num(v["accuracy"]), "priority": num(v["priority"]) or 0, "target": int(r["target_id"]),
        "status": r["damage_class_id"] == "1", "effect": num(v["effect_id"]) or 0, "chance": num(v["effect_chance"]) or 0,
        "cat": num(m.get("meta_category_id")) or 0, "ailment": num(m.get("meta_ailment_id")) or 0,
        "minHits": num(m.get("min_hits")), "maxHits": num(m.get("max_hits")),
        "drain": num(m.get("drain")) or 0, "healing": num(m.get("healing")) or 0, "crit": num(m.get("crit_rate")) or 0,
        "ailmentChance": num(m.get("ailment_chance")) or 0, "flinch": num(m.get("flinch_chance")) or 0,
        "statChance": num(m.get("stat_chance")) or 0, "stats": stats.get(r["id"], []),
        "contact": 1 in flags[int(r["id"])], "soundMove": 9 in flags[int(r["id"])],
    }

# Level-up learnsets in Emerald for #1-386
learn = collections.defaultdict(set)
for r in csv.DictReader(open(f"{d}/pokemon_moves.csv", encoding="utf-8")):
    if r["version_group_id"] == str(EMERALD) and r["pokemon_move_method_id"] == "1":
        p, mv = int(r["pokemon_id"]), int(r["move_id"])
        if p <= 386 and mv in moves: learn[p].add((int(r["level"]), mv))
learnsets = {str(p): sorted([lv, mv] for lv, mv in learn[p]) for p in range(1, 387)}

# Types before Fairy existed (Clefairy was Normal, Marill Water…)
gen3types = {}
past = collections.defaultdict(list)
for r in rows("pokemon_types_past"):
    if int(r["generation_id"]) >= 3 and int(r["pokemon_id"]) <= 386:
        past[r["pokemon_id"]].append((int(r["generation_id"]), int(r["slot"]), types[r["type_id"]]))
for p, lst in past.items():
    g = min(x[0] for x in lst)           # the first generation-range that covers Gen 3
    gen3types[p] = [t for gen, slot, t in sorted(lst, key=lambda x: x[1]) if gen == g]

# Pokémon GO move sounds (PokeMiners/pogo_assets): exact name match, else one of the same type
files = [l.strip().split("/")[-1] for l in open(sounds_list) if l.strip()]
by_slug = {}
for f in files:
    slug = f.split("_", 1)[1].rsplit(".", 1)[0]
    slug = slug.replace("_fast", "").replace("_", "-")
    by_slug.setdefault(slug, f)
by_type = collections.defaultdict(list)
for m in moves.values():
    if m["key"] in by_slug and not m["status"]: by_type[m["type"]].append(m["key"])
sound = {}
for m in moves.values():
    if m["key"] in by_slug: sound[m["key"]] = by_slug[m["key"]]
    elif by_type[m["type"]]:
        pool = sorted(by_type[m["type"]]); sound[m["key"]] = by_slug[pool[m["id"] % len(pool)]]
for m in moves.values(): m["sound"] = sound.get(m["key"])

# Weights (hectograms) for Low Kick
weights = {r["id"]: int(r["weight"]) for r in rows("pokemon") if int(r["id"]) <= 386}

json.dump({"moves": list(moves.values()), "learnsets": learnsets, "gen3Types": gen3types, "weights": weights},
          open(out, "w"), separators=(",", ":"))
print(len(moves), "moves;", sum(1 for m in moves.values() if m["key"] in by_slug), "exact sounds;", len(gen3types), "gen3 type fixes")
