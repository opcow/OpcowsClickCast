# Opcow's Click Cast

**Click casting for WoW: Forever.** A party frame with your spells and macros as buttons under each member. Click a button and it casts on that member, in combat too. No key bindings to learn, and macros work as buttons.

## Buttons

- **Spells at any rank.** Left click casts the rank you pick, or **Highest**, which follows new ranks as you learn them.
- **Shift-click** has its own action. By default it's the same spell a rank lower. Hold Shift and the buttons show what they'll cast.
- **Right-click** casts a rank lower, or a rank higher. There's also an option for Shift-right to cast two ranks lower.
- **Macros as buttons.** Write `@unit` where the target goes, ex: `/cast [@unit] Renew`, and it becomes the member you clicked.
- **Self only** buttons cast on you and show on your own frame only, ex: racials.
- **Buff reminders.** Tick **Remind** on a buff's button. Out of combat, members missing that buff get its icon beside their frame, and the button glows. Group buffs count too, ex: Prayer of Fortitude for Power Word: Fortitude. Tick **Reminder only** too and the button leaves the row, showing beside the frame only while the member needs it. Pick the reminder glow: Pulse, Flash, Steady or Spell alert.
- **Class filter.** Show a button only under the classes you pick, ex: Arcane Intellect under mana users.
- **Cooldowns** show on each button, along with a swipe while your HoT or buff from that spell is on the member. A button turns red while a debuff stops its spell on that member, ex: Weakened Soul for Power Word: Shield.
- **Dispel glow.** Your dispel button lights up in the debuff's colour while the member has something it can remove, ex: Dispel Magic glows blue on magic. In combat too. Pick its look: Border, Thick border, Glow, Tint, Corner or Spell alert.

## The frame

- Health, power, incoming heals, your buffs, dispellable debuff colours, threat, role icons, range fading and class colours. All of these work in combat.
- **Out of range** members get red buttons, and a button never casts on you instead.
- A **target frame** for a friendly player who isn't in your party, with the same buttons. It's outlined in purple so it's never mistaken for a party member.
- Set the button size, buttons per row, width, bar height, scale, bar texture and sort order (group, role or name).
- Optionally hide Blizzard's party frames, or show your own frame when you're not in a group.
- **Preview** shows made up party members, so you can set everything up while solo.

## Button sets

Save your buttons as a set and load it on any of your characters of the same class. Right-click the minimap button for a quick set menu.

## Getting started

1. Type `/occ`, or click the minimap button or the addon compartment, to open the options window.
2. Click **Add spell** or **Add macro**, or drag spells and macros from your spellbook or macro window onto the list.
3. Click **Preview** to see the result, or join a group.

Everything can be set in the options window. `/occ help` lists the slash commands.

## Notes

- The game doesn't let addons change clickable frames during combat, so changes made in a fight apply as soon as it ends.
- Other players' buffs can't be read in combat, so buff reminders hide during fights and come back afterward.
