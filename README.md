<p align="center"><img src="art/logo/logo-512.png" width="320" alt="SafeLoot: an old horned treasure chest whose lock is an eye with a keyhole for a pupil"></p>

# SafeLoot

**Loot protection for groups with strangers in World of Warcraft: Forever.**

SafeLoot warns you, remembers and keeps evidence. It never blocks, punishes or publishes anyone. Everything works even if you are the only one in the group running it.

- **The Watcher** — an alarm (the game's own centre warning and raid-warning sound, plus an action panel) when the leader switches to master loot or changes the loot rules mid-run.
- **The Detector** — flags Need rolls on items the roller's class can never use, and rolls that break the agreed rules.
- **The Memory** — private notes on players: shown in the tooltip, in the Group Finder, when someone invites you and when someone joins your group. Your notes never leave your PC, and they expire.
- **The Rules** — agree on the rules before the run with one chat line everyone can read. "ok" replies are recorded with the time. Rules the leader writes (HR, SR, MS>OS…) are offered to you as a suggestion.
- **Loot by boss** — choose the dungeon and pick the items to reserve from each boss's list instead of typing their names. Items really seen dropping are marked as such; SafeLoot users in the same group exchange item numbers per boss (never names, notes or chat; it can be turned off).
- **The Summary** — after each run: whether the rules were kept, who got what, and a plain-text copy for Discord.

Native look (the game's own windows, fonts, icons and sounds), accessible (never colour alone, large text, voice alarm, no time limits), and available in English, Español, Deutsch, Français and Português (Brasil).

## Install from this repository
1. Copy this folder to `World of Warcraft/_forever_/Interface/AddOns/SafeLoot`.
2. Optional, for the loot lists: move its `SafeLoot_LootData` folder next to it, to `Interface/AddOns/SafeLoot_LootData`.
3. Restart the game.

## Commands
`/safeloot` (or `/sl`), or the button on the minimap, opens the window.

| Command | What it does |
|---|---|
| `test` | Self-test |
| `alarm` | Demo of the alarm |
| `mark` | Demo of a mark |
| `summary` | Demo of the run summary |
| `rules` | Open the Rules tab |
| `players` | Open the Players tab |
| `journal` | Open the Journal tab |
| `minimap` | Show or hide the minimap button |
| `settings` | Open the settings |
| `welcome` | Show the welcome card again |
| `help` | Open the Help tab |
| `exceptions` | Clear the detector exceptions |

Spanish aliases also work: `prueba`, `alarma`, `marca`, `resumen`, `reglas`, `jugadores`, `diario`, `minimapa`, `ajustes`, `bienvenida`, `ayuda`, `excepciones`.

## Development
- The rules of the project are in [`docs/PROMPT_MAESTRO.md`](docs/PROMPT_MAESTRO.md).
- Offline checks (Lua 5.1 with a simulated client): `uv run --with lupa python tests/run.py`
- Install into the game (copies and verifies the files): `python tools/install.py`

## License
MIT.

## Loot data and licences
- SafeLoot is MIT (see `LICENSE`).
- `SafeLoot_LootData/` is a separate, optional add-on with loot tables derived from
  [AtlasLoot Classic Forever](https://www.curseforge.com/wow/addons/atlasloot-forever) by sliccer, based on
  [AtlasLootClassic](https://github.com/Hoizame/AtlasLootClassic) by Hoizame and contributors. That folder is under the
  GNU GPL version 2 (see `SafeLoot_LootData/LICENSE`). SafeLoot works without it.
