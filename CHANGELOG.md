# Changelog

## 0.29.0

### Added

- Spacing option: the pixels between buttons, side by side and between rows, from 0 to 30 (2 as before). It's next to Width and Scale, or use `/occ spacing <n>`.

## 0.28.0

### Fixed

- The Spell alert dispel glow showed only a faint grey pulse: its marching ants needed a script, which the game doesn't allow in its aura buttons. It's now the action bar's own gold proc glow, the same animation the game plays on a proc, whatever the debuff's colour.
- The Spell alert, Glow and Corner dispel looks were drawn inside the button, or at the wrong size, instead of round its edges. They're now sized from the spell button, and follow a change of the Size option.

## 0.27.0

### Added

- Reminder only: a buff's button can leave the row under each member and only show beside their frame while they're missing the buff, so buffs you cast now and then don't take up room. Click it there to cast the buff on them. Like reminders, it shows out of combat only. Tick "Reminder only" on the button or use `/occ remindonly <n>`.
- Never downrank: a spell's button can always cast its own rank. Right-click (when set to a rank lower), shift-click on Auto and shift-right-click cast that rank too. A shift-click spell you picked and right-click a rank higher still work. Tick "Never downrank" on the button or use `/occ nodownrank <n>`.
- The dispel glow has a choice of looks: Border (as before), Thick border, Glow (the action bar's glowing edge), Tint (the colour over the whole icon) Corner (a square in the top right) or Spell alert (the look of a proc's glow: marching ants round the button and a pulsing glow, in the debuff's colour). Pick it with the button beside "Dispel glow" in the options, or `/occ dispelstyle <name>`.
- Class filter: a button can show only under members of the classes you pick, ex: Arcane Intellect under mana users. Frames keep the same width, and the target frame shows every button. Pick them with the "Classes" button beside Rank, or `/occ class <n> <class>` (`all` for everyone).
- Reminder glow: a button and its icon beside the frame glow, as in Buff Reminder, while a member is missing the buff, in place of the orange border. Pulse (the default), Flash, Steady, Spell alert or None. Pick it with the "Reminder glow" button in the options, or `/occ remindglow <name>`.
- `/occ reminders` prints why each member's buff reminders show or not.

### Fixed

- A member who just joined the group could get no buff reminder until something else changed, ex: they died. Reminders are now checked again every 2 seconds out of combat.

## 0.26.0

### Added

- Can't-cast marks: a red mark on a spell button while the member has a debuff that stops you casting it on them, with a swipe showing when it wears off. Weakened Soul marks Power Word: Shield, and Forbearance marks Blessing of Protection, Divine Protection and Divine Shield. Macro buttons get it too, by the macro's spell. A button's shift-click spell has its own mark, shown while you hold Shift. Out of combat it's read from the member's debuffs. In combat the game hides debuffs, so it shows for the debuff's length after you cast the spell on them from a button. Turn it off with the "Can't-cast marks" option or `/occ blocked`.
- Dispel button glow: a dispel spell's button gets a border in the debuff's colour while the member has a debuff it can remove: blue magic, purple curse, brown disease, green poison. Ex: Dispel Magic, Cure Disease, Remove Curse, Cure Poison, Purify, Cleanse. Works in combat. A shift-click dispel glows while you hold Shift. Turn it off with the "Dispel button glow" option or `/occ dispelglow`.
- Red when out of range: a red overlay on a member's buttons while they're out of range, as well as the faded bars. Works in combat. Turn it off with the "Red when out of range" option or `/occ rangered`.

### Fixed

- Clicking a button for a member who was out of range or out of sight could cast the spell on you, through the game's Auto Self Cast. A button now casts on its member or not at all: the game puts the spell on the cursor to pick a target instead, and right-click or Escape cancels it. Auto Self Cast still works everywhere else.
- The target frame could show a party member, a copy of their party frame, when you targeted them before a fight started. It now stays out of sight for party members in and out of combat.

## 0.25.0

First public release.

### Features

- A party frame of its own, with a row of spell and macro buttons under each member. A button casts on the member it sits under.
- Macros can be buttons. `@unit` in a macro is replaced with the member's unit when it's clicked.
- Left click casts the spell at the rank you pick, or your highest rank. Shift-click has its own action (auto: a rank lower). Right-click casts a rank lower or higher, and Shift-right can cast two ranks lower.
- Buttons can be self only (ex: racials), shown on your own frame only.
- Buff reminders: tick Remind on a buff's button and members missing it get an icon beside their frame and a glowing button, out of combat. Group versions count, ex: Prayer of Fortitude covers Power Word: Fortitude.
- Health, power, incoming heals, your buffs, dispellable debuff colours, threat, role icons, range fading and class colours. These all work in combat.
- A cooldown swipe on each button, and a swipe while your HoT is ticking on that member.
- A frame for a friendly target who isn't in your party.
- Button sets, shared between your characters of the same class.
- Size, width, bar height, scale, buttons per row, bar texture, sort order, and an option to hide Blizzard's party frames.
- A preview that shows made up party members, so you can set it up while solo.
- An options window (`/occ`, the minimap button or the addon compartment). Everything can be set from it.
