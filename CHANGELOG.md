# Changelog

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
