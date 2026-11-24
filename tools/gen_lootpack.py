"""Generate SafeLoot_LootData/Data.lua from AtlasLoot's dungeon and raid tables (GPL-2.0).

    python tools/gen_lootpack.py --source DIR --credit "AtlasLootClassic by Hoizame and contributors" --build 1.60.1.71091

DIR is the folder holding AtlasLoot's `data.lua` (AtlasLootClassic_DungeonsAndRaids). The file is read as TEXT: its
table constructors are tokenised and parsed, nothing in it is executed.
Every item is checked against the Forever client's own item tables (DB2 `Item`, wago.tools `wowf`): an ID that the
client does not have is dropped. (`ItemSparse` is only partly published: the server sends the rest, so it is used for
quality and name checks when it has the item, never to decide that an item does not exist.)
"""
import argparse
import csv
import io
import os
import re
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "SafeLoot_LootData", "Data.lua")
sys.path.insert(0, HERE)
import gen_instances  # noqa: E402

TOKEN = re.compile(r"""
    (?P<comment>--\[\[.*?\]\]|--[^\n]*) | (?P<ws>\s+) |
    (?P<str>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*') |
    (?P<num>0x[0-9a-fA-F]+|\d+\.?\d*) | (?P<name>[A-Za-z_]\w*) |
    (?P<op>\.\.\.|\.\.|==|~=|<=|>=|[-+*/%^\#<>=(){}\[\];:,.])
""", re.X | re.S)


def tokenize(text):
    out, pos = [], 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise SystemExit("cannot read the source near: " + text[pos:pos + 60])
        if m.lastgroup not in ("comment", "ws"):
            out.append((m.lastgroup, m.group()))
        pos = m.end()
    return out


class Ref(str):
    """A bare identifier (a variable of the source), kept apart from strings."""


class Parser:
    def __init__(self, tokens, i):
        self.t, self.i = tokens, i

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else ("eof", "")

    def take(self, value=None):
        tok = self.peek()
        if value is not None and tok[1] != value:
            raise SystemExit("expected %s, found %s" % (value, self.t[self.i:self.i + 6]))
        self.i += 1
        return tok

    def expr(self):
        left = self.primary()
        while self.peek()[1] in ("..", "+", "-", "*", "/", "or", "and", "==", "~="):
            op = self.take()[1]
            right = self.primary()
            if op == "..":
                left = str(left if left is not None else "") + str(right if right is not None else "")
        return left

    def primary(self):
        kind, value = self.peek()
        if kind == "str":
            self.take()
            return re.sub(r"\\(.)", r"\1", value[1:-1])
        if kind == "num":
            self.take()
            return int(value, 0) if re.fullmatch(r"0x[0-9a-fA-F]+|\d+", value) else float(value)
        if value == "-":
            self.take()
            v = self.primary()
            return -v if isinstance(v, (int, float)) else v
        if value in ("not", "#"):
            self.take()
            return self.primary()
        if value == "{":
            return self.table()
        if value == "(":
            self.take()
            v = self.expr()
            self.take(")")
            return v
        if value == "function":
            depth = 0
            while True:
                tok = self.take()[1]
                if tok in ("function", "if", "do"):
                    depth += 1
                elif tok == "end":
                    depth -= 1
                    if depth == 0:
                        return None
        if kind != "name":
            raise SystemExit("unexpected %s" % (self.t[self.i:self.i + 6],))
        self.take()
        if value in ("true", "false", "nil"):
            return {"true": True, "false": False, "nil": None}[value]
        result = Ref(value)
        while True:
            nxt = self.peek()[1]
            if nxt == "[":
                self.take()
                key = self.expr()
                self.take("]")
                result = key if result in ("AL", "ALIL") and isinstance(key, str) else Ref(value)
            elif nxt == ".":
                self.take()
                self.take()
                result = Ref(value)
            elif nxt in ("(", ":"):
                if nxt == ":":
                    self.take()
                    self.take()
                self.take("(")
                args = []
                while self.peek()[1] != ")":
                    args.append(self.expr())
                    if self.peek()[1] == ",":
                        self.take()
                self.take(")")
                if value == "format" and args and isinstance(args[0], str):
                    result = args[0]
                    for a in args[1:]:
                        result = re.sub(r"%[sd]", lambda _m, a=a: str(a), result, count=1)
                elif value == "GetForVersion" and args:
                    result = args[0]  # the Classic (vanilla) value
                else:
                    result = Ref(value)
            else:
                return result

    def table(self):
        self.take("{")
        positional, named = [], {}
        while self.peek()[1] != "}":
            if self.peek()[1] == "[" :
                self.take()
                key = self.expr()
                self.take("]")
                self.take("=")
                named[key] = self.expr()
            elif self.peek()[0] == "name" and self.peek(1)[1] == "=":
                key = self.take()[1]
                self.take("=")
                named[key] = self.expr()
            else:
                positional.append(self.expr())
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return {"list": positional, "map": named}


def parse_source(text):
    tokens = tokenize(text)
    result = {}
    for i in range(len(tokens) - 5):
        if tokens[i][1] == "data" and tokens[i + 1][1] == "[" and tokens[i + 2][0] == "str" and tokens[i + 4][1] == "=" \
                and tokens[i + 5][1] == "{":
            result[tokens[i + 2][1][1:-1]] = Parser(tokens, i + 5).table()
    return result


def entry_items(entry):
    ids = []
    if isinstance(entry["map"].get("TableType"), Ref) and "SET" in entry["map"]["TableType"]:
        return ids
    for key, value in entry["map"].items():
        if isinstance(key, Ref) and key.endswith("_DIFF") and isinstance(value, dict):
            for row in value["list"]:
                if not isinstance(row, dict):
                    continue
                found = row["list"][1:2]
                # { 11, [ATLASLOOT_IT_HORDE] = 18422, [ATLASLOOT_IT_ALLIANCE] = 18423 }: one item per faction
                found += [v for k, v in row["map"].items() if isinstance(k, Ref) and k.startswith("ATLASLOOT_IT_")]
                for item_id in found:
                    if isinstance(item_id, int) and not isinstance(item_id, bool) and item_id > 0 and item_id not in ids:
                        ids.append(item_id)
    return ids


def clean_name(name):
    name = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(name))
    name = re.sub(r"\s+-\s+Tier.*$", "", name)
    return re.sub(r"^.*?:\s*", "", name).strip() if name.startswith("Ring of Law") else name.strip()


def norm(name):
    return re.sub(r"[^a-z0-9]", "", clean_name(name).lower().replace("the ", ""))


# Names the source and the client write differently (source name -> client boss name)
ALIASES = {
    "gelihast": "geilhast",  # (the client spells it "Geilhast")
    "baelog": "lostdwarves", "ericswift": "lostdwarves", "olaf": "lostdwarves",
    "bugtrio": "silithidroyalty",
    "overlordmugg": "overseermugg",  # (same boss, title changed)
}
# Sections of the source without a plain instance ID
SECTION_MAPS = {
    "DireMaulEast": 429, "DireMaulWest": 429, "DireMaulNorth": 429, "Naxxramas": 533,
    # the dungeons that only exist in Forever (AtlasLoot Classic Forever)
    "TheHallOfThanes": 3065, "TheRuinsOfLordaeron": 2999, "ExcavationSiteWetlands": 2998, "TheCityOfDalaran": 2959,
    "TheDrownedCity": 2970, "TheKrolDokStronghold": 3039, "TheAlcazPrison": 2994, "TheBlackmawHold": 2974,
    "ShapersTerrace": 3001, "OnyxiasLairNew": 249,
}


def extra_key(map_id, name, npc):
    """Stable negative key of a boss the client's list does not have: its NPC ID, or a hash of its name."""
    return -npc if isinstance(npc, int) else -(100000000 + zlib.crc32(("%d:%s" % (map_id, norm(name))).encode()) % 900000000)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source", required=True)
    p.add_argument("--credit", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--cache", default=os.path.join(HERE, ".db2cache"))
    p.add_argument("--report", action="store_true")
    a = p.parse_args()

    text = open(os.path.join(a.source, "data.lua"), encoding="utf-8").read()
    comments = {}
    for m in re.finditer(r"\{\s*\d+\s*,\s*(\d+)[^}\n]*\}\s*,?\s*--\s*([^\n]+)", text):
        comments.setdefault(int(m.group(1)), m.group(2).strip())
    source = parse_source(text)

    sparse = {int(r["ID"]): r for r in gen_instances.fetch("ItemSparse", a.build, "enUS", a.cache)}
    item = {int(r["ID"]): r for r in gen_instances.fetch("Item", a.build, "enUS", a.cache)}
    instances = gen_instances.build_instances(a.build, a.cache)

    loot, extras = {}, {}
    stats = dict(kept=0, missing=0, filtered=0, renamed=[], loose=[], matched=0, extra=0, unmatched_maps=[])
    for key, inst in source.items():
        map_id = inst["map"].get("InstanceID")
        if not isinstance(map_id, int):
            map_id = SECTION_MAPS.get(key)
        if not isinstance(map_id, int) or map_id not in instances:
            stats["unmatched_maps"].append((key, map_id))
            continue
        bosses = {norm(b["names"][0]): b for b in instances[map_id]["bosses"]}
        for entry in (inst["map"].get("items") or {"list": []})["list"]:
            if not isinstance(entry, dict) or entry["map"].get("ExtraList") and not entry["map"].get("npcID"):
                name0 = isinstance(entry, dict) and clean_name(entry["map"].get("name", ""))
                if not name0 or not re.search(r"trash", name0, re.I):
                    continue
            ids = []
            for item_id in entry_items(entry):
                if item_id not in item:
                    stats["missing"] += 1
                    continue
                row, cls = sparse.get(item_id), int(item[item_id]["ClassID"])
                # what people reserve: no keys; below uncommon is left out here or, when the quality is not
                # published, in the game (the picker hides it once the client knows the item)
                if cls == 13 or (row and int(row["OverallQualityID"]) < 2):
                    stats["filtered"] += 1
                    continue
                expected = comments.get(item_id)
                if row and expected and norm(expected) != norm(row["Display_lang"]):
                    stats["renamed"].append((item_id, expected, row["Display_lang"]))
                ids.append(item_id)
            if not ids:
                continue
            stats["kept"] += len(ids)
            name = clean_name(entry["map"].get("name", "?"))
            npc = entry["map"].get("npcID")
            if isinstance(npc, dict):
                npc = next((n for n in npc["list"] if isinstance(n, int)), None)
            boss = bosses.get(ALIASES.get(norm(name), norm(name)))
            if not boss:  # "Interrogator Vishas" vs "Vishas", "Bosses & co"
                close = [b for n, b in bosses.items() if len(n) > 4 and (n in norm(name) or norm(name) in n)]
                boss = close[0] if len(close) == 1 else None
                if boss:
                    stats["loose"].append((map_id, name, boss["names"][0]))
            if boss:
                stats["matched"] += 1
                bucket = boss["ids"][0]
            elif not re.search(r"trash|shared|set", name, re.I) and name not in ("?", ""):
                stats["extra"] += 1
                bucket = extra_key(map_id, name, npc)
                extras.setdefault(map_id, {})[bucket] = name
            else:
                bucket = 0
            lst = loot.setdefault(map_id, {}).setdefault(bucket, [])
            lst.extend(i for i in ids if i not in lst)

    q = gen_instances.lua_string
    lines = [
        "-- GENERATED by SafeLoot's tools/gen_lootpack.py. Do not edit by hand.",
        "-- Loot tables derived from %s," % a.credit,
        "-- licensed under the GNU GPL version 2 (see LICENSE).",
        "-- Items checked against the WoW: Forever client item table, build %s." % a.build,
        "SafeLootDataPack = {",
        "  credit = %s," % q(a.credit),
        "  build = %s," % q(a.build),
        "  -- [instance map ID] = { [boss encounter ID, -npcID of a rare or extra boss, 0 = other drops] = { item IDs } }",
        "  loot = {",
    ]
    for map_id in sorted(loot):
        lines.append("    [%d] = {" % map_id)
        for bucket in sorted(loot[map_id]):
            lines.append("      [%d] = { %s }," % (bucket, ", ".join(map(str, loot[map_id][bucket]))))
        lines.append("    },")
    lines += ["  },", "  -- bosses the client's encounter list does not have (rares, summons): names as in the source", "  extra = {"]
    for map_id in sorted(extras):
        lines.append("    [%d] = { %s }," % (map_id, ", ".join("[%d] = %s" % (k, q(v)) for k, v in sorted(extras[map_id].items(), reverse=True))))
    lines += ["  },", "}", ""]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    print("instances with loot: %d | bosses matched: %d | extra bosses: %d" % (len(loot), stats["matched"], stats["extra"]))
    print("items kept: %d | not in Forever (dropped): %d | filtered (grey, keys...): %d | renamed: %d" % (
        stats["kept"], stats["missing"], stats["filtered"], len(stats["renamed"])))
    print("source sections not used:", stats["unmatched_maps"])
    if a.report:
        for r in stats["loose"]:
            print("  loose match", r)
        for r in stats["renamed"]:
            print("  renamed", r)
        for map_id in sorted(instances):
            inst = instances[map_id]
            have = loot.get(map_id, {})
            without = [b["names"][0] for b in inst["bosses"] if b["ids"][0] not in have]
            print("  %-5d %-28s live=%s bosses %d, without loot %d: %s" % (
                map_id, inst["names"][0], inst["live"], len(inst["bosses"]), len(without), ", ".join(without)[:150]))
        for map_id in extras:
            print("  extra", map_id, ", ".join(extras[map_id].values())[:200])


if __name__ == "__main__":
    sys.exit(main())
