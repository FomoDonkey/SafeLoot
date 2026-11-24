"""Generate Data/Instances.lua: the dungeons and raids of WoW: Forever with their bosses, in the five languages.

Source: the client's own data tables (DB2 `Map`, `DungeonEncounter`, `GroupFinderActivity`) as published by wago.tools
for the Forever product (`wowf`). The Encounter Journal (and its loot tables) does not exist in Forever, so only the
instances and bosses come from here; which items each boss drops is learned in game (Modules/Catalog.lua) or comes
from the optional SafeLoot_LootData pack (tools/gen_lootpack.py).

    python tools/gen_instances.py --build 1.60.1.71091             # downloads into tools/.db2cache/

The client data still carries Season of Discovery content (Karazhan Crypts, Scarlet Enclave, Demon Fall Canyon, world
bosses as instances, raid versions of Blackfathom Deeps / Gnomeregan / Sunken Temple). None of it is in Forever: it is
left out. Raids that exist in the data but are not open in Forever are kept for recognition (live = false) but are not
offered in the list.
"""
import argparse
import csv
import io
import os
import sys
import urllib.request

LOCALES = ["enUS", "esES", "deDE", "frFR", "ptBR"]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Data", "Instances.lua")

# Season of Discovery leftovers, test maps, scenarios
EXCLUDE = {13, 29, 2720, 2921, 2784, 2789, 2791, 2804, 2832, 2856, 2875}
# Season of Discovery difficulties: their encounter IDs are kept for a boss that also exists in the normal version,
# but bosses that only exist there are not listed
SOD_DIFFICULTIES = {"198", "201", "215"}
# Raids Blizzard has dated for Forever (Dec 9, 2026). Barrow Deeps and Hyjal Summit are not in the client data of
# build 71091 yet: run this again when a newer build has them.
LIVE_RAIDS = {249}
# Group finder entries that belong to Season of Discovery (they reuse the same maps)
SOD_ACTIVITIES = set(range(1604, 1616)) | {1693, 1710}


def fetch(table, build, locale, cache):
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, "%s_%s_%s.csv" % (table, build, locale))
    if not os.path.exists(path):
        url = "https://wago.tools/db2/%s/csv?build=%s" % (table, build)
        if locale != "enUS":
            url += "&locale=" + locale
        request = urllib.request.Request(url, headers={"User-Agent": "SafeLoot-datagen"})
        with urllib.request.urlopen(request, timeout=180) as response:
            data = response.read()
        if data.startswith(b"{"):
            raise SystemExit("wago.tools refused %s %s: %s" % (table, locale, data[:200]))
        with open(path, "wb") as f:
            f.write(data)
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(io.StringIO(f.read())))


def lua_string(text):
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")
    return '"' + text + '"'


def names(values):
    """One string when every language says the same, else { enUS, esES, deDE, frFR, ptBR }."""
    cleaned = [v.strip() if v and v.strip() else values[0].strip() for v in values]
    if len(set(cleaned)) == 1:
        return lua_string(cleaned[0])
    return "{ " + ", ".join(lua_string(v) for v in cleaned) + " }"


def build_instances(build, cache):
    """{ mapID: { raid, size, min, max, live, names[5], bosses: [ { ids, names[5] } ] } }"""
    maps = {loc: {r["ID"]: r for r in fetch("Map", build, loc, cache)} for loc in LOCALES}
    encounters = {loc: {r["ID"]: r for r in fetch("DungeonEncounter", build, loc, cache)} for loc in LOCALES}
    levels = {}
    for act in fetch("GroupFinderActivity", build, "enUS", cache):
        if int(act["ID"]) in SOD_ACTIVITIES or act["MapID"] == "0":
            continue
        lo, hi, size = int(act["MinLevel"]), int(act["MaxLevelSuggestion"]), int(act["MaxPlayers"])
        have = levels.get(act["MapID"])
        levels[act["MapID"]] = (min(lo, have[0]), max(hi, have[1]), max(size, have[2])) if have else (lo, hi, size)

    by_map = {}
    for enc in encounters["enUS"].values():
        by_map.setdefault(enc["MapID"], []).append(enc)

    result = {}
    for map_id, row in maps["enUS"].items():
        if row["InstanceType"] not in ("1", "2") or int(map_id) in EXCLUDE or map_id not in by_map:
            continue
        encs = sorted(by_map[map_id], key=lambda e: (e["DifficultyID"] in SOD_DIFFICULTIES, e["DifficultyID"] != "0",
                                                      int(e["OrderIndex"]), int(e["ID"])))
        has_normal = any(e["DifficultyID"] == "0" for e in encs)
        bosses, seen = [], {}
        for enc in encs:
            key = enc["Name_lang"].strip().lower()
            if key in seen:
                seen[key]["ids"].append(int(enc["ID"]))
            elif not (has_normal and enc["DifficultyID"] in SOD_DIFFICULTIES):
                boss = {"ids": [int(enc["ID"])], "names": [encounters[loc][enc["ID"]]["Name_lang"] for loc in LOCALES]}
                seen[key] = boss
                bosses.append(boss)
        raid = row["InstanceType"] == "2"
        lo, hi, size = levels.get(map_id, (0, 0, int(row["MaxPlayers"] or 0)))
        result[int(map_id)] = {
            "raid": raid, "size": size, "min": lo, "max": hi,
            "live": (int(map_id) in LIVE_RAIDS) if raid else (map_id in levels),
            "names": [maps[loc][map_id]["MapName_lang"] for loc in LOCALES], "bosses": bosses,
        }
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", required=True)
    parser.add_argument("--cache", default=os.path.join(HERE, ".db2cache"))
    args = parser.parse_args()
    instances = build_instances(args.build, args.cache)

    out = []
    for map_id in sorted(instances):
        inst = instances[map_id]
        out.append("  { id = %d, raid = %s, live = %s, size = %d, min = %d, max = %d, name = %s, bosses = {" % (
            map_id, "true" if inst["raid"] else "false", "true" if inst["live"] else "false", inst["size"], inst["min"],
            inst["max"], names(inst["names"])))
        for boss in inst["bosses"]:
            out.append("    { ids = { %s }, name = %s }," % (", ".join(map(str, boss["ids"])), names(boss["names"])))
        out.append("  } },")

    text = (
        "-- GENERATED by tools/gen_instances.py from the WoW: Forever client data (build %s). Do not edit by hand.\n"
        "-- Dungeons and raids with their bosses; names in %s.\n"
        "-- Boss \"ids\" are the game's encounter IDs (the ones the loot history reports), so a drop can be put under the\n"
        "-- right boss. live = false: in the data but not open in Forever (recognised, not offered).\n"
        "local _, SL = ...\n"
        "SL.InstanceData = {\n"
        "build = \"%s\",\n"
        "locales = { %s },\n"
        "list = {\n" % (args.build, ", ".join(LOCALES), args.build, ", ".join('"%s"' % l for l in LOCALES))
    ) + "\n".join(out) + "\n},\n}\n"
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    live = [i for i in instances.values() if i["live"]]
    print("instances: %d (live %d), bosses: %d (live %d), bytes: %d" % (
        len(instances), len(live), sum(len(i["bosses"]) for i in instances.values()), sum(len(i["bosses"]) for i in live),
        len(text.encode("utf-8"))))
    for map_id, inst in sorted(instances.items(), key=lambda kv: (kv[1]["raid"], kv[1]["min"])):
        print("  %s %-5d %-28s %d-%d (%d) bosses %d" % ("live" if inst["live"] else "----", map_id, inst["names"][0],
                                                          inst["min"], inst["max"], inst["size"], len(inst["bosses"])))


if __name__ == "__main__":
    sys.exit(main())
