# SafeLoot

**Loot protection for groups with strangers in World of Warcraft: Forever.**

SafeLoot warns you, remembers and keeps evidence. It never blocks, punishes or publishes anyone. Everything works even if you are the only one in the group running it.

- **The Watcher** — an alarm (the game's own centre warning and raid-warning sound, plus an action panel) when the leader switches to master loot or changes the loot rules mid-run.
- **The Detector** — flags Need rolls on items the roller's class can never use, and rolls that break the agreed rules.
- **The Memory** — private notes on players: shown in the tooltip, in the Group Finder, when someone invites you and when someone joins your group. Nothing leaves your PC, and notes expire.
- **The Rules** — agree on the rules before the run with one chat line everyone can read. "ok" replies are recorded with the time. Rules the leader writes (HR, SR, MS>OS…) are offered to you as a suggestion.
- **The Summary** — after each run: whether the rules were kept, who got what, and a plain-text copy for Discord.

Native look (the game's own windows, fonts, icons and sounds), accessible (never colour alone, large text, voice alarm, no time limits), and available in English, Español, Deutsch, Français and Português (Brasil).

## Commands
`/safeloot` (or `/sl`) opens the window.

| Command | What it does |
|---|---|
| `test` | Self-test |
| `alarm` | Demo of the alarm |
| `mark` | Demo of a mark |
| `summary` | Demo of the run summary |
| `rules` | Open the Rules tab |
| `players` | Open the Players tab |
| `journal` | Open the Journal tab |
| `settings` | Open the settings |
| `welcome` | Show the welcome card again |
| `help` | Open the Help tab |
| `exceptions` | Clear the detector exceptions |

Spanish aliases also work: `prueba`, `alarma`, `marca`, `resumen`, `reglas`, `jugadores`, `diario`, `ajustes`, `bienvenida`, `ayuda`, `excepciones`.

## Development
- The rules of the project are in [`docs/PROMPT_MAESTRO.md`](docs/PROMPT_MAESTRO.md).
- Offline checks (Lua 5.1 with a simulated client): `uv run --with lupa python tests/run.py`
- Install into the game (copies and verifies the files): `python tools/install.py`

## License
MIT.
