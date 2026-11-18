import csv, json, sys, os
src = sys.argv[1]; out = sys.argv[2]
R = lambda f: list(csv.DictReader(open(os.path.join(src, f + '.csv'), encoding='utf-8')))
MAX = 386  # Gen 1–3 (Hoenn). Raise to 493 (Gen 4) or 649 (Gen 5) later.
types = {r['id']: r['identifier'] for r in R('types')}
names = {r['pokemon_species_id']: r['name'] for r in R('pokemon_species_names') if r['local_language_id'] == '9'}
items = {r['id']: r['identifier'] for r in R('items')}
item_names = {r['item_id']: r['name'] for r in R('item_names') if r['local_language_id'] == '9'}
habitats = {r['id']: r['identifier'] for r in R('pokemon_habitats')}
ptypes = {}
for r in R('pokemon_types'):
    if int(r['pokemon_id']) <= MAX:
        ptypes.setdefault(int(r['pokemon_id']), []).append((int(r['slot']), types[r['type_id']]))
growth = {'1': 'slow', '2': 'mediumFast', '3': 'fast', '4': 'mediumSlow', '5': 'erratic', '6': 'fluctuating'}

# type -> habitat affinities (used for Gen 4/5 species that have no habitat data, and as extra signal)
TYPE_HAB = {
 'water': ['sea', 'watersEdge'], 'grass': ['forest', 'grassland'], 'bug': ['forest', 'grassland'],
 'rock': ['mountain', 'cave', 'roughTerrain'], 'ground': ['roughTerrain', 'cave', 'mountain'],
 'electric': ['urban'], 'steel': ['urban', 'mountain'], 'poison': ['urban', 'forest'], 'normal': ['urban', 'grassland'],
 'ice': ['mountain', 'sea'], 'ghost': ['urban', 'cave'], 'dark': ['urban', 'forest'], 'psychic': ['urban', 'grassland'],
 'fairy': ['grassland', 'urban'], 'fire': ['roughTerrain', 'urban'], 'flying': ['grassland', 'forest', 'mountain'],
 'fighting': ['urban', 'mountain'], 'dragon': ['watersEdge', 'mountain'],
}
HAB_MAP = {'cave': 'cave', 'forest': 'forest', 'grassland': 'grassland', 'mountain': 'mountain', 'rare': 'rare',
           'rough-terrain': 'roughTerrain', 'sea': 'sea', 'urban': 'urban', 'waters-edge': 'watersEdge'}

FALLBACK_LEVEL = 33
used_items = set(['rare-candy', 'exp-candy-s', 'exp-candy-m', 'poke-ball', 'great-ball', 'ultra-ball'])

def method_for(rows, frm, sid):
    """Pick the most walk-friendly evolution method for one evolved species."""
    best = None
    for r in rows:
        if r['required_pokemon_form_id'] not in ('', str(frm)) or r['evolved_pokemon_form_id'] not in ('', str(sid)):
            continue  # regional / alternate forms
        trig = r['evolution_trigger_id']
        tod = r['time_of_day'] or None
        gender = {'1': 'female', '2': 'male'}.get(r['gender_id'])
        m = None; score = 0
        if trig == '3' and r['trigger_item_id']:
            m = {'kind': 'item', 'item': items[r['trigger_item_id']]}; score = 100
        elif trig == '1' and r['held_item_id']:
            m = {'kind': 'item', 'item': items[r['held_item_id']]}; score = 90
        elif trig == '1' and r['minimum_level'] and not r['known_move_id'] and not r['party_species_id'] and not r['location_id']:
            m = {'kind': 'level', 'level': int(r['minimum_level'])}; score = 80
        elif trig == '1' and r['minimum_happiness']:
            m = {'kind': 'friendship', 'value': int(r['minimum_happiness'])}; score = 70
        elif trig == '2' and r['held_item_id']:
            m = {'kind': 'item', 'item': items[r['held_item_id']]}; score = 60
        elif trig == '2':
            m = {'kind': 'item', 'item': 'linking-cord'}; score = 50
        elif trig == '1':  # known move, party member, location, beauty...: approximate with a level
            m = {'kind': 'level', 'level': int(r['minimum_level'] or FALLBACK_LEVEL)}; score = 10
        if m is None:
            continue
        if tod: m['time'] = tod
        if gender: m['gender'] = gender
        if r['is_default'] == '1': score += 1
        if best is None or score > best[0]:
            best = (score, m)
    return best[1] if best else None

evo_rows = {}
for r in R('pokemon_evolution'):
    sid = int(r['evolved_species_id'])
    if sid <= MAX:
        evo_rows.setdefault(sid, []).append(r)

species = []
evolutions = {}
for r in R('pokemon_species'):
    sid = int(r['id'])
    if sid > MAX: continue
    frm = r['evolves_from_species_id']
    if frm and int(frm) <= MAX and sid in evo_rows:
        m = method_for(evo_rows[sid], int(frm), sid)
        if m:
            if m['kind'] == 'item': used_items.add(m['item'])
            m['into'] = sid
            evolutions.setdefault(int(frm), []).append(m)

for r in R('pokemon_species'):
    sid = int(r['id'])
    if sid > MAX: continue
    t = [x[1] for x in sorted(ptypes[sid])]
    habs = []
    if r['habitat_id']: habs.append(HAB_MAP[habitats[r['habitat_id']]])
    for ty in t:
        for h in TYPE_HAB.get(ty, []):
            if h not in habs: habs.append(h)
    species.append({
        'id': sid, 'name': names[str(sid)], 'key': r['identifier'], 'types': t,
        'evolvesFrom': int(r['evolves_from_species_id']) if r['evolves_from_species_id'] else None,
        'evolutions': evolutions.get(sid, []),
        'captureRate': int(r['capture_rate']), 'baseFriendship': int(r['base_happiness'] or 70),
        'genderRate': int(r['gender_rate']), 'growth': growth[r['growth_rate_id']],
        'isBaby': r['is_baby'] == '1', 'isLegendary': r['is_legendary'] == '1', 'isMythical': r['is_mythical'] == '1',
        'habitats': habs, 'generation': int(r['generation_id']),
    })
species.sort(key=lambda s: s['id'])

item_ids = {v: k for k, v in items.items()}
item_list = []
for key in sorted(used_items):
    nm = item_names.get(item_ids.get(key, ''), key.replace('-', ' ').title())
    if key == 'exp-candy-s' and key not in item_ids: nm = 'Exp. Candy S'
    item_list.append({'key': key, 'name': nm})

json.dump({'species': species, 'items': item_list}, open(out, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print(len(species), 'species,', len(item_list), 'items,', os.path.getsize(out), 'bytes')
print([i['key'] for i in item_list])
