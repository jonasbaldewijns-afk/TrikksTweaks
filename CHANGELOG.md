# Trikks Tweaks

## 1.3

### New modules
Every module is off on a fresh install: turn on what you want in `/trikks`.

- **Loot Feed**: your loot and your group's in one feed. The item name is shown in its quality colour, with the count, who got it (class colour), and item level and sockets for gear. Identical drops merge into one line. Filters by quality and "only gear", plus a blacklist (Alt-right-click an entry). Entries fade out after a while, but not while your mouse is on the feed. Size, font, opacity and grow direction are adjustable, and you place it in Edit Mode.
- **Buff Reminders**: an icon for each class buff that is missing or about to run out, out of combat only. Click to cast it on yourself, right-click to cast it on your target. Can count group members in range who are missing it, and you can add your own reminders (food, flasks, ...). Placed in Edit Mode.
- **Centre Tracked Buffs**: keeps Blizzard's Cooldown Manager buff row ("Tracked Buffs" with "Hide when inactive") centred, with no gaps where inactive buffs would be. The Cooldown Manager is the one thing that can still show buffs gained in combat.
- **XP Bar Text**: the text on the XP / reputation bars is always visible, and the XP text is shorter: `45% · 2,750 to go · +20% rested`.
- **Solo Party Frame**: keeps the raid-style party frame (with you in it) on screen while you're solo, and can hide the player frame.

### Changes
- **Mouseover Bars**: the XP / reputation bars can fade out until you hover them too.
- **Minimap**: the square map can sit flush in the top-right corner of its Edit Mode box. The zone bar above the map is now faded out instead of moved, which works on this client. The addon buttons in the button bin are no longer hidden behind its background.
- **Delete Junk**: can also delete water and food (separate options), and always picks the item with the lowest vendor value.
- **Character Extras**: the durability text and the volume slider now only show on the gear tab. The volume slider works again (other parts of the window were covering it).
- **Defaults**: options that hide or move Blizzard's UI, or act on your behalf, now start off. Settings you already chose are kept.

### Performance
- Modules that are off create, hook and listen to nothing.
- Mouseover Bars and the minimap fade do no work while your mouse is still.
- `/trikks perf` shows how much memory the Trikks addons use and how fast that grows.
