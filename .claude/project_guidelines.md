# SafeLoot — project guidelines
Read and follow `docs/PROMPT_MAESTRO.md` before any change. Key rules:
- Nothing "works" until it was seen working in the real WoW: Forever client. Offline tests ≠ in-game.
- Every game API call goes through `Core/API.lua`; pure logic in `Logic/` has no game API and is unit-tested.
- Tests must stay green: `uv run --with lupa python tests/run.py`. Install to the game: `python tools/install.py`.
- English is the base language; every key must exist in enUS, esES, deDE, frFR, ptBR.
- In-game truth comes from `/safeloot test` and the observations saved in `WTF/Account/<acc>/SavedVariables/SafeLoot.lua`.
