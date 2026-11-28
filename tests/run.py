"""SafeLoot offline checks (docs/PROMPT_MAESTRO.md §11).

Runs every check in real Lua 5.1 (WoW's version) via lupa:
  1. syntax of every .lua file;
  2. logic specs (pure modules);
  3. full-addon scenarios against a simulated WoW: Forever API (tests/wow_mock.lua);
  4. no leaked globals; no error swallowed by the addon's own error handler;
  5. every text key exists in all five languages.

Usage (no install needed):  uv run --with lupa python tests/run.py
This does NOT prove anything works in the real client: see the in-game tests (/safeloot test) in the PROMPT.
"""
import os
import re
import sys

try:
    from lupa import lua51
except ImportError:
    print("lupa is missing. Run: uv run --with lupa python tests/run.py")
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "SafeLoot"


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def toc_files():
    files = []
    for line in read(ADDON + ".toc").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def all_lua():
    out = []
    for base, _, names in os.walk(ROOT):
        if os.sep + "." in base:
            continue
        for n in names:
            if n.endswith(".lua"):
                out.append(os.path.relpath(os.path.join(base, n), ROOT).replace("\\", "/"))
    return sorted(out)


failures = []
passed = 0


def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
    else:
        failures.append(f"{name}: {detail}")


# 1. Syntax ---------------------------------------------------------------------------------------------------
def syntax():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    compile_ = lua.eval("function(src, name) local f, err = loadstring(src, '@' .. name); return err end")
    for path in all_lua():
        err = compile_(read(path), path)
        check("syntax " + path, err is None, err)
    for path in toc_files():
        check("toc lists existing file " + path, os.path.exists(os.path.join(ROOT, path)), "missing")


# 2-4. Runtime with the simulated client ------------------------------------------------------------------------
HARNESS = r"""
local results = {}
function test(name, fn)
  local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
  table.insert(results, { name = name, ok = ok, err = err })
end
function eq(a, b, msg)
  if a ~= b then error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
function ok(v, msg) if not v then error(msg or "expected true", 2) end end
function last(t) return t[#t] end
function contains(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
function RESULTS() return results end
"""


def runtime(prepare="", pack=False):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)
    lua.execute(read("tests/wow_mock.lua"))
    if prepare:
        lua.execute(prepare)
    lua.execute("BEFORE_GLOBALS = {}; for k in pairs(_G) do BEFORE_GLOBALS[k] = true end")
    lua.execute("NS = {}")
    runner = lua.eval("function(src, name) local f = assert(loadstring(src, '@' .. name)); f('" + ADDON + "', NS) end")
    for path in toc_files():
        if path.endswith(".lua"):
            runner(read(path), path)
    lua.execute("SIM.Fire('ADDON_LOADED', '" + ADDON + "')")
    if pack:  # the data add-on loads after SafeLoot, before login
        lua.execute(read("SafeLoot_LootData/Data.lua"))
    lua.execute("SIM.Fire('PLAYER_LOGIN'); SIM.RunTimers()")
    return lua


def run_spec(spec_path, prepare="", pack=False):
    lua = runtime(prepare, pack)
    lua.execute(read(spec_path))
    for r in lua.eval("RESULTS()").values():
        check(f"{os.path.basename(spec_path)} · {r.name}", r.ok, r.err)
    # no error swallowed by the addon's xpcall handler
    errs = lua.eval("SafeLootDB and SafeLootDB.errors or {}")
    texts = [e.text for e in errs.values()]
    check(f"{os.path.basename(spec_path)} · no internal errors", not texts, "; ".join(texts)[:2000])
    # no leaked globals
    leaked = lua.eval("""(function()
      local allowed = { SLASH_SAFELOOT1 = true, SLASH_SAFELOOT2 = true, BINDING_HEADER_SAFELOOT = true,
        BINDING_NAME_SAFELOOT_TOGGLE = true, NS = true, BEFORE_GLOBALS = true }
      local out = {}
      for k in pairs(_G) do
        if not BEFORE_GLOBALS[k] and not allowed[k] and not tostring(k):find('^SafeLoot') then out[#out + 1] = tostring(k) end
      end
      return table.concat(out, ',')
    end)()""")
    check(f"{os.path.basename(spec_path)} · no leaked globals", leaked == "", leaked)


# 5. Locales -----------------------------------------------------------------------------------------------------
def locales():
    key_re = re.compile(r'^L\.(\w+) = ', re.M)
    langs = {}
    for code in ["enUS", "esES", "deDE", "frFR", "ptBR"]:
        langs[code] = set(key_re.findall(read(f"Locales/{code}.lua")))
    base = langs["enUS"]
    for code, keys in langs.items():
        missing = sorted(base - keys)
        extra = sorted(keys - base)
        check(f"locale {code} complete", not missing, "missing " + ", ".join(missing))
        check(f"locale {code} has no unknown keys", not extra, "extra " + ", ".join(extra))
    used = set()
    for path in all_lua():
        if path.startswith("Locales/") or path.startswith("tests/"):
            continue
        src = re.sub(r"--[^\n]*", "", read(path))  # ignore comments
        used |= set(re.findall(r'\bL\.([A-Z][A-Z0-9_]*[A-Za-z0-9_]*)', src))
        used |= set(re.findall(r'\bL\["([A-Za-z0-9_]+)"\]', src))
    dynamic = (
        [f"METHOD_{i}" for i in range(6)]
        + [f"NEED_{r}" for r in ["msos", "greed", "free", "upgrade"]]
        + [f"NEED_TIP_{r}" for r in ["msos", "greed", "free"]]
        + ["REASON_" + r.upper() for r in ["class_armor", "class_weapon", "class_shield", "class_relic", "class_item",
                                             "contract_greed", "contract_boe", "reserved_hard", "reserved_soft",
                                             "stats_physical", "stats_caster"]]
        + ["EVENT_" + k.upper() for k in ["need_impossible", "need_doubtful", "rules_changed", "contract_broken",
                                           "grouped", "tag_ninja", "tag_extortion", "tag_quitter", "tag_rude",
                                           "tag_trusted", "tag_goodleader", "note"]]
        + ["TONE_" + t for t in ["BAD", "WARN", "MIXED", "GOOD", "NEUTRAL"]]
        + [p + c for p in ("CAT_", "CAT_TIP_") for c in ("ALL", "GROUP", "NINJA", "EXTORTION", "QUITTER", "WARNED", "TRUSTED", "NOTED", "SEEN")]
        + ["LABEL_WARNED", "LABEL_NOTED", "LABEL_SEEN"]
        + ["SORT_RECENT", "SORT_NAME", "SORT_TIMES"]
        + ["TAB_CONTRACT", "TAB_JOURNAL", "TAB_PLAYERS"]
        + ["LANG_" + c for c in ["auto", "enUS", "esES", "deDE", "frFR", "ptBR"]]
        + ["SOURCE_AUTO", "SOURCE_COPIED", "SOURCE_PROPOSED", "SOURCE_RECEIVED"]
    )
    settings_src = read("UI/Settings.lua")
    for k in re.findall(r'\{ key = "(\w+)"', settings_src):
        dynamic.append("OPT_" + k)
    for k in re.findall(r'\{ section = "(\w+)" \}', settings_src):
        dynamic.append(k)
    diag_src = read("Modules/Diagnostics.lua")
    obs_block = re.search(r'local keys = \{(.*?)\}', diag_src, re.S)
    for k in re.findall(r'"(\w+)"', obs_block.group(1)):
        dynamic.append("OBS_" + k)
    for k in sorted(used | set(dynamic)):
        check(f"key {k} exists", k in base, "not in enUS")


syntax()
run_spec("tests/specs/logic.lua")
run_spec("tests/specs/scenarios.lua")
run_spec("tests/specs/point2.lua")
run_spec("tests/specs/audit3.lua")
run_spec("tests/specs/lootbook.lua")
run_spec("tests/specs/lootpack.lua", pack=True)
run_spec("tests/specs/players.lua")
run_spec("tests/specs/notes.lua")
run_spec("tests/specs/demo.lua", pack=True)
run_spec("tests/specs/audit4.lua", pack=True)
run_spec("tests/specs/store_failure.lua", "SafeLootDB = { players = { ['Krag Hierro'] = { events = { { kind = 'tag_ninja', t = SIM.now } } } }, settings = setmetatable({}, { __newindex = function() error('damaged') end }) }")
# the game's xpcall passes extra arguments on (plain Lua 5.1 does not): the same scenarios through that path
GAME_XPCALL = """local real = xpcall
function xpcall(f, handler, ...)
  local n, args = select('#', ...), { ... }
  if n == 0 then return real(f, handler) end
  return real(function() return f(unpack(args, 1, n)) end, handler)
end"""
run_spec("tests/specs/scenarios.lua", GAME_XPCALL)
run_spec("tests/specs/audit4.lua", GAME_XPCALL, pack=True)
run_spec("tests/specs/minimap.lua")
run_spec("tests/specs/minimap_hidden.lua", "SafeLootDB = { settings = { showMinimap = false, minimapAngle = 'x' } }")
run_spec("tests/specs/locale_switch.lua", "SIM.locale = 'enUS'")
run_spec("tests/specs/locale_saved.lua", "SIM.locale = 'enUS'; SafeLootDB = { settings = { language = 'deDE' } }")
run_spec("tests/specs/corrupt_saved.lua", "SafeLootDB = { players = { ['Bad Record'] = 'x', ['Half Ok'] = { events = { 'junk', { kind = 'tag_ninja', t = SIM.now } } } }, settings = { alarmSound = 'yes' }, runs = { 'broken' } }")
locales()

print(f"{passed} checks passed, {len(failures)} failed")
for f in failures:
    print("FAIL", f)
sys.exit(1 if failures else 0)
