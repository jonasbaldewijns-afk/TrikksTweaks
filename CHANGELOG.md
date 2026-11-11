# Trikks Tweaks

## 1.5

### New modules
Every module is off on a fresh install: turn on what you want in `/trikks`.

- **Interact Glow**: ore, herbs, quest objects, chests, fishing spots and anything else you can interact with sparkle when you come near: little sparks over a soft glow, in a colour per type (grey when your skill is too low). Choose which types sparkle, the size, height, number of sparks, brightness and range. It turns on the game's soft-target settings for interactables and puts your own values back when you switch it off. Don't use it together with another glow addon such as Lueur.
- **Poison Reminder** (rogues): an icon per weapon (main hand, off hand) when its poison is missing or about to run out. Click, Shift-click, Ctrl-click and Alt-click each put a poison of your choice on that weapon, using the highest rank in your bags. Can also stay on screen as a quick re-apply bar. Placed in Edit Mode.

### Changes
- **XP Bar** (was XP Bar Text): the bar stays blue, a pale band shows how far your rested XP reaches, and a gold band (plus `+12% from quests` in the text) shows the XP waiting in quests that are ready to hand in.
- **Buff Reminders**: rogue poisons moved to the new Poison Reminder.
- **Movable Windows**: the Looking For Group window can be moved too.
- Every "press a key" button in the settings now works the same: click it, press the key; Esc or a second click cancels.
- **Bulk Buy**: also works on vendors whose Shift-click pop-up is opened another way (it was still stopping at one stack).
- **Automation**: selling grey items no longer depends on Blizzard's vendor window already being on screen, and a problem with auto repair can't stop it. It also checks that the first sale went through. If the game refuses it, it switches to Blizzard's own "sell all junk", and tells you if that is blocked too instead of doing nothing.

### Fixes
- **Dialog Keys, Delete Junk, IDs & Links**: your keyboard could stop responding for a whole fight if combat started right after one of these used a key (Space on a quest, Backspace, the copy key). Fixed.
- **Export / import**: the string no longer contains your chat history, or the notes modules keep of your own game settings (to put them back when switched off). Importing a string keeps yours.
- **Mail to Alts**: no more error when typing a name on its settings page while the module is off.
- **Minimap**: ticking FPS / latency / coordinates / durability shows the stats row right away. The addon buttons in the button bin keep the same order.
- **Vendor & Bags**: switching it off puts Blizzard's "free bag slots" setting back to what you had.
- **Hide Blizzard Frames**: does far less work while addons load at login.
- **Centre Tracked Buffs**: a vertical row uses the right padding.
- Old `/trikks dump` output is dropped after a day (it made the settings file slow to load). `/trikks dump clear` empties it at once.

### Performance
- **Buff Reminders, Poison Reminder**: the once-a-second check no longer asks the game about every spell and no longer re-sets the icons' click settings each time: only when something changed.
- **Dark Mode**: a target, focus, group or pet change only redoes the unit frames, and does far less work doing it.

## 1.4

### New modules
Every module is off on a fresh install: turn on what you want in `/trikks`.

- **Mail to Alts**: set up two characters (your main and your bank alt), each with what it should get: item types (cloth, leather, ore, herbs, ...), unbound BoE gear from a chosen quality, an always-send item list (drop an item on it) and all gold above an amount you keep. At a mailbox each character gets a button that opens a send panel. Tick item types (it shows how many you have of each) and type an amount of gold for this one send, or **Quick send** everything you set up. 12 items per mail, one mail after another, gold in the last one. Soulbound, locked and quest items are never sent. You choose per character which buttons show.
- **Bulk Buy**: Shift-click an item at a vendor to buy any amount, not just one stack. Shows the total price, what fits in your bags and what you can afford, and buys one stack at a time. Items that cost tokens or currency keep Blizzard's own pop-up.
- **Auction House Keys**: on the auction house sell page, Space = Create Auction and Shift-Space = Max quantity. Both can be rebound. They only work there, and not while you type in a price box.

### Changes
- **Buff Reminders**: rogues get a poison reminder per weapon (main hand and off hand). Clicking it puts a poison from your bags on that weapon.
- **Chat**: the copy window works again. It now keeps its own record of each chat tab and tells you when the game hid lines.

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
