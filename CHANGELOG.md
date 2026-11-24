# Changelog

## 0.2.0 — 2026-11-24 — rules bar, welcome, "It's a mistake", notes, help (not yet tested in the game client)
- **Rules bar**: while you are in a group, a small bar (the game's tooltip border) shows the rules in force.
  - It turns red with "Rules changed!" when they deviate from what was agreed, and goes back when they are restored.
  - Hover for the full rules, the reserves and who agreed; click to open the Rules tab; drag to move it.
  - Option: "Rules bar while in a group".
- **Welcome card**: three steps shown once at the first login (never in combat), with "Try the alarm" and Settings. `/safeloot welcome` shows it again.
- **"It's a mistake"** on class-based marks: the detector never flags that class with that item type again, and the automatic note is taken back. `/safeloot exceptions` (or the Settings button) clears these exceptions.
- **Notes**: free text (up to 200 characters, cleaned) on any player.
- **New players**: someone who is not in your memory yet can be added by typing their name in the search box.
- **Help tab**: what SafeLoot does, a glossary (Need, Greed, master loot, group loot, HR, SR, MS>OS, BoE, PUG), the commands and the privacy rules. `/safeloot help`.
- Toasts can carry a second button.
- Checks: 405 offline (45 new).

## 0.1.1 — 2026-11-24 — security, performance and robustness audit (still not tested in the game client)
Security:
- Text from other players (chat, Group Finder listings) is cleaned before it is stored or re-sent: no UI escape codes (|c |H |T |A |K), no stray "|", no control bytes, and the length is capped.
- Chat lines are cut without splitting an accented letter, so the line stays valid UTF-8 and the game does not reject it.
- Anti-spam: at most one message to the group every 4 s, however many times a button is clicked.
- "ok" counts as agreeing only for 3 minutes after the rules are published.
- Damaged SavedVariables are validated and cleaned. If loading still fails, the addon runs this session with in-memory defaults.
- Values the game marks as secret (in instances) are never compared or saved, and rolls with a hidden class are skipped.

Performance:
- GROUP_ROSTER_UPDATE bursts (40-player raids) are handled once per burst.
- Diagnostics observations sample their context, so player tooltips stay almost free.
- Text normalisation takes a single pass, with a fast path for plain ASCII.
- Item facts and Group Finder listing texts are cached, and the internal tables are bounded.

Behaviour:
- Dying and running back as a ghost (or briefly leaving the instance) no longer ends the run. It ends after 10 minutes outside, on entering another instance, or on leaving the group.
- The summary pops up only when something happened. A new option shows it always, and every run is still saved in the journal.
- You are told when you join a group that already uses master loot.
- The agreed rules survive a /reload in the same group.
- When rules are agreed, the loot method recorded is the one the group has at that moment.
- The same rules pasted several times in chat are suggested only once.
- Toasts queue instead of replacing each other.
- Fallback detection of Need rolls from the group-loot chat line, only if the game provides that text.
- Locale-independent text handling: no string.lower, %s or %c on UTF-8 text.

Checks: 360 offline checks (13 new for this audit).

## 0.1.0 — 2026-11-24 — first build (not yet tested in the game client)
- The Watcher:
  - snapshot of the loot rules when you join a group;
  - alarm when the method changes to master loot, the master looter changes, the threshold rises, or a new leader takes over with master loot on;
  - the alarm uses the native centre warning, the raid-warning sound, optional voice, and an action panel (Ask the group · Save evidence · Got it);
  - during combat the check waits until combat ends;
  - no alarm when you lead and make the change yourself.
- The Detector: reads loot history roll states and flags:
  - impossible Need rolls, using conservative vanilla class proficiencies (to be verified in Forever);
  - doubtful Need rolls: on another player's reserved item, against "everything on Greed", or BoE on Greed.
- The Memory: private, with a 90-day default expiry. It shows in:
  - the player tooltip;
  - Group Finder rows and their tooltip;
  - invitations;
  - players joining your group.

  Players can be marked trusted, ninja or "sold loot", or forgotten.
- The Rules:
  - automatic snapshot, or rules copied from the leader's chat line or Group Finder listing (as a suggestion);
  - your own proposal, published as one normal chat line; "ok" / "sí" / "+1" / "oui" / "ja" / "sim" replies are recorded.
- The run journal and end-of-run summary, with copy-to-Discord.
- Self-test (`/safeloot test`), plus live observations stored in SavedVariables for the developer.
- Options > AddOns panel (the game's Settings API), with a language selector: Automatic, English, Español, Deutsch, Français, Português (Brasil).
- Native UI only: PortraitFrameTemplate window with tabs, Dialog cards, ready-check icons, SOUNDKIT sounds.
- Offline checks: 338 (syntax, logic, 29 full scenarios, globals, internal errors, five complete languages).
