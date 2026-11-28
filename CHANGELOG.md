# Changelog

## 0.5.3 — 2026-11-28 — clear notes
- Notes say only what you wrote. On the player card every note, mark and alert now shows on its own, with when in grey under it ("today", "3 days ago"): the zone and the exact time came with every line and cut the note short (seen in the real client). Hover a line to read it whole, with the exact date and the place. Alerts recorded by the addon keep where they happened.
- The player tooltip and the notices about someone show your newest note and the newest thing the addon saw, instead of repeating your mark under the big word.
- The screenshot mode is fully in the add-on's language, whatever the language of the game (class, quality and the OK button came from the game).

## 0.5.2 — 2026-11-25 — performance, code and security audit
Checked offline and against the Forever UI source; not yet seen in the real client.

Security and privacy:
- What you only heard from a SafeLoot user in your group is never shared again (a false report can no longer travel from player to player), is marked "reported in your group" until you see it drop or the loot lists back it up, never pushes out, moves or refreshes what you saw yourself, and is only taken about where the group is going, with a limit per player.
- Asking for loot over and over can no longer make you flood the group.
- A leader switching the loot method over and over warns every time but no longer makes the game scream; one writing rules line after line no longer fills the queue of notices, and a bad notice always gets in.
- If the saved data cannot be read, the session starts empty but what was saved is NOT replaced (before, a failure there would have erased every mark and note at logout). Damaged saved data is cleaned field by field.
- The self-test only counts its own echo and saves nothing about who sent it.

Performance:
- Lists are drawn once instead of once per line (the game lays the whole list out again for every inserted line).
- Sorting 2000 players A-Z: 97 ms -> 5 ms; searching them: 7.8 -> 1.8 ms (offline benchmark, tests/bench.py).
- The game's events create no garbage on their own; the events of items the game loads for others are only listened to while waiting for one; a drop is read once instead of twice, and learned once instead of with every roll; only the tab that shows a change is drawn again.

Fixed:
- Choosing a player (or an item finishing to load) no longer moves the list back to the top.
- "Copy report" in the self-test window (it was promised and missing), without your character's name.
- "Defaults" in the options restores the real defaults (it restored the values of the moment you logged in).
- Adopting other rules forgets the "ok" answers to the old ones.
- A loading screen without a place name no longer ends the run; a whole day in the same group keeps 300 drops at most.

## 0.5.1 — 2026-11-25 — seen in the real client
- The arrow before a name was drawn as an empty box (the game's font does not have it): it is a ">" now, also in the published chat line.
- The opinion buttons and the owner button can be read: no more red or purple words on red buttons.
- The journal and the summary list the drops in the order they fell, with the time (the order changed every time).
- The chat line no longer starts with a loose dot when nothing has been chosen.
- The demos use real items of the game in the game's language.
- Screenshot mode for the add-on's page (`/safeloot shots`): an invented group, on this screen only.

## 0.5.0 — 2026-11-24 — the address book
Not yet seen in the real client.
- Players tab rebuilt as three panes: categories with icon and number (in my group, ninja, sells loot, quits, alerts, trusted, with notes, met before), the list (two lines, class icon, coloured bar, order by recent / A-Z / most runs) and the card (opinion, notes that can be removed one by one). Searching looks in every category.
- Recognise them at a glance: icon + word in big in the tooltip, a badge under the target's portrait, the Group Finder, invitations, people joining and (new) whispers.
- Mark anyone with a right click: portrait, party, chat, friends, guild, or a row of the list.
- Marks and notes you make never expire (they used to after 90 days); automatic alerts still do. "Forget" asks twice.
- Every window can be dragged and remembers its place (the main window could not be moved: it never received the mouse). `/safeloot reset` puts them back.

## 0.4.1 — 2026-11-24 — minimap button
- A round button on the edge of the minimap: click opens or closes SafeLoot, right click gives a quick menu (tabs, loot by boss, settings, hide), drag moves it. It shows a warning mark while your group's loot rules are not the agreed ones. Works with round and square minimaps. Hide it from the settings, its menu or `/safeloot minimap`.

## 0.4.0 — 2026-11-24 — pick instead of type, and the full audit
Not yet seen in the real client: everything below is checked offline and against the Forever UI source (build 71091).

New:
- Choose the dungeon or raid, sorted by level: the 28 dungeons of Forever (nine new ones included) and Onyxia's Lair, with their bosses, from the Forever client data in the five languages. Inside a dungeon it is set on its own. Season of Discovery leftovers in the client data are left out; the other raids are recognised but not offered until they open.
- "Loot..." opens the bosses of that dungeon with their items: hover for the tooltip, click to pick, Shift/Ctrl-click as in the game.
- Forever does not ship loot tables, so items are LEARNED from real drops (roll history, boss corpses) and exchanged with SafeLoot users in your group: item numbers only, never names or chat; can be turned off. A dungeon nobody has seen yet shows its bosses without items.
- Optional second add-on SafeLoot_LootData (GPL-2.0, derived from AtlasLoot Classic Forever 1.4.9): loot of the 28 dungeons of Forever, the nine new ones included, and Onyxia from the first day. Every item is marked "not seen yet" until it is really seen dropping; items the server does not know are hidden.
- Who the reserve is for: menu with your group. HR / SR switch. Each reserve is a real item link and has its own remove button.
- The published chat line carries real item links when they fit (255 bytes; links are never cut).
- Rules prepared alone (dungeon, reserves) are kept when the group forms.
- "Accept the change" on the alarm makes the new loot method the agreed one.
- Players tab: your group and recent groups are listed, with or without notes.
- Toasts have a close button.
- Own logo and in-game icon: "the chest that watches", original hand-painted-style artwork (art/logo: Blender scene and painter, as code).

Fixed:
- Item links in the addon's texts can be hovered and clicked.
- Tags went to the previously selected player and piled up into "Mixed": one opinion per player, and the typed name wins.
- Shift-click into the reserve box never worked: Forever calls ChatFrameUtil.InsertLink, not ChatEdit_InsertLink.
- Item links of the real client ("|cnIQ3:") left junk in cleaned text and in the copied summary.
- The rules bar stayed red after using the game's rules; the place outside instances was the continent; people from quiet groups were not remembered; a player with only a written note looked empty.
- "ya voy" no longer counts as agreeing, "res pls" is not a reserve, "estoy libre" is not a loot rule.
- Editing published rules makes a draft; publishing during the anti-spam pause records nothing; "Save evidence" twice writes one note.
- Header lines of the Rules tab and button labels never spill over other controls.

Checks: 543 offline, plus 34 deliberate breakages, all caught.

## 0.3.0 — 2026-11-24 — polish after the first real test (desktop PC: saved data + screenshots)
Confirmed in the real client:
- 0 internal errors.
- 28/28 functions, 13/13 native templates and 10/10 events present.
- Names read correctly with their surname.
- Addon messages echo in 252 ms (whisper and party).
- PARTY_LOOT_METHOD_CHANGED fires outside instances (3 times) and the loot method is readable (7/7).
- The real alarm fired when the leader switched to master loot, and "Save evidence" noted it.
- Party chat is readable outside instances (19 lines).

Fixed and improved:
- Free for all now raises a red alarm with its own text: anyone can loot anything without a roll.
- More ways of saying yes are understood: "yap", "ya", "va", "okis", "kk", "yeah"… In the real test the friend's "yap" was not counted.
- Rules bar:
  - darker background and white, normal-size text (it was lost over bright scenery);
  - short form (MS>OS) with "2/3 agreed".
- Rules tab:
  - new "In the game now" line: method, rolls-from quality (in its colour) and leader;
  - no empty gap above "Propose rules".
- The published chat line uses the short labels.
- The journal also records groups in the open world: the real alarm happened outside an instance and was only in the player's card. Entering an instance turns the group session into that instance's run.

Checks: 421 offline.

## 0.2.1 — 2026-11-24 — first fixes from the real game client (desktop PC, screenshots)
Seen working in the client:
- the welcome card;
- the demo alarm panel;
- the main window (portrait, title, Settings button);
- the rules bar, which shows on joining a group ("Botín de grupo");
- the automatic snapshot of the rules.

Fixed:
- No tab was drawn. Blizzard's PanelTemplates_AnchorTabs only chains tabs 2..n, so the first tab is now anchored to the bottom of the window.
- "BoE on Greed" overlapped the long first rule label; it now has its own row.
- SharedEditBoxTemplate drew its art outside small boxes and had no hint text. It is replaced by our own input: a classic tooltip-border box, the game's font, and a grey hint while the box is empty.
- The tip about agreeing at the meeting stone moved into the Publish button's tooltip.

Checks: 408 offline.

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
