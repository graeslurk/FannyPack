# Fanny Pack

One small bar on your hip for everything you reach for between and during
fights: bandages, healthstones, potions, elixirs, scrolls, weapon stones and
oils, food, drinks and buff food. Plain food and Well Fed food get separate
buttons, so you never waste a feast just to heal up. Made for **WoW Forever**.

## Why Fanny Pack

- **A bandage button** that bandages you (or your friendly target, if you
  like) and shows how long you're *Recently Bandaged*
- **Plain food and buff food apart**, with a soft glow on the buff food
  while you're not Well Fed
- **Stones, oils and poisons in one click**: no more clicking the item and
  then your weapon
- **Neat in combat**: food and drink step aside during a fight and the rest
  of the bar closes up
- **Picks the right item for you**: each button uses the best one you carry
  that you can use, and you can always choose another

## The buttons

- **Healthstone**
- **Bandages**: bandages you, and shows how long you're *Recently Bandaged*,
  so you know when the next one is ready
- **Health potion** and **Mana potion**
- **Rune**: Demonic Rune and Dark Rune, on their own cooldown apart from potions
- **Mana gem** (mages only): your conjured mana gem, also on its own cooldown,
  so you can keep it and a mana potion ready
- **Other potion**: every potion that isn't a health or mana potion, such as
  protection, Free Action, Swiftness and Rage potions
- **Elixir** and **Second elixir**: elixirs and flasks. The second one takes
  the best elixir the first doesn't use. They glow while their buff isn't on
  you
- **Scroll**: Scrolls of Agility, Intellect, Protection, Spirit, Stamina and
  Strength, used on you

Turn on **Use on your target** to put bandages and scrolls on a friendly
target instead; with no target, or an enemy targeted, they still go on you.
- **Weapon stone or oil**: sharpening stones, weightstones, wizard oils and
  mana oils. Click to put one on your main hand weapon, Shift-click for your
  off-hand. It glows gold while a weapon in your hands has nothing on it, and
  silver when it's running out
- **Main-hand poison** and **Off-hand poison** (rogues only): one click puts
  the poison on that hand. Each button has its own poison, and glows while
  its hand has nothing on it
- **Food**: ordinary food that only restores health
- **Drink**: water and other drinks that restore mana
- **Eat & drink**: eats and drinks in one click, with the items of your Food
  and Drink buttons
- **Buff food**: food that makes you *Well Fed*, kept apart from your
  everyday food. It glows gold while you're not Well Fed, and silver when
  Well Fed is running out

Turn on **Hide while on** for a reminder and its buttons stay off the bar
while the buff is on you, coming back when it's gone or running out.

The silver glow starts 2 minutes before a buff or weapon stone runs out. On
the options' Reminders page you can set it separately for Well Fed (up to 15
minutes), elixirs (60), scrolls (30) and weapons (30), or 0 for none.

Each button uses the best item you carry that you can use: the highest level
first, and conjured food and water before anything you'd keep. It shows how
many you have left and its cooldown. **Right-click** a button to pick a
different item from your bags, to use up low-level items first instead, and to choose when its count turns **red** as
you run low (5 bandages, 3 potions and so on, by default). All the low-stock
limits are also listed together on the options' Reminders page, where you
can turn the warning off altogether.

Buttons for things you don't carry are hidden (or faded, if you prefer).
Warriors and rogues don't get the drink and mana potion buttons by default.

## In combat

- Every button works in combat, and so do their **hotkeys**: bind a key to
  any button in the game's Key Bindings, under Fanny Pack. The key shows in
  the button's corner
- **Choose which buttons show in and out of combat.** Food, drink and buff
  food hide during a fight by default, since you can't eat or drink then; a
  button can also show only in fights. The bar closes up around whatever is
  hidden, and switches back when the fight is over
- The reminder glows wait until the fight is over
- If your bags change mid-fight, the bar catches up as soon as combat ends
  (the game doesn't let addons change their buttons during combat)

## Setting up the bar

Type `/fannypack` (or click the minimap button) to open the options.

**Where it sits**
- **Above your player frame** by default, lined up with its right end, clear
  of the pet frame and the cast bar. If your player frame is at the top of
  the screen, it goes below it instead
- **Attached to the player frame**: it moves along when you move the player
  frame in Edit Mode, also after you've dragged it. Turn this off to pin it
  to the screen
- **Unlock** it to drag it anywhere, and **reset** it to put it back

**How it's laid out**
- **Sort the buttons** in any order, and turn each one on or off per character
- Let the bar **grow** right, left, down or up from its first button. The
  first button always stays put: turning buttons on or off, or hiding them
  in combat, never moves it
- **Split it into rows**: choose how many buttons go in a row, and whether
  new rows go above or below (or left or right of a bar growing up or down)

**How it looks**
- **Shape**: square, rounded or round
- **Border**: none, or a thin silver or gold line
- **Button size** and **spacing**
- **Fade out of combat**: the bar disappears outside combat and comes back
  when you hover over it or a fight starts. A glowing reminder stays visible
- The buff food and weapon **reminders** can each be turned off

**Profiles**
- Keep a whole bar setup per role, say one for tanking and one for healing:
  which buttons show, their order, the layout, the look and the low-stock
  limits
- Each character uses a profile (Default to start). Switch, create, copy,
  reset and delete them in the options, or type `/fannypack profile <name>`
  (handy in a macro)

The options are split into pages (Buttons, Bar, Look, Reminders and
Profiles), and the window can be resized to fit small screens.

## Commands

| Command | |
|---|---|
| `/fannypack` | Open the options |
| `/fannypack lock` | Lock or unlock the bar |
| `/fannypack reset` | Put the bar back above your player frame |
| `/fannypack profile [name]` | Show or switch this character's profile |
| `/fannypack minimap` | Show or hide the minimap button |
| `/fannypack debug` | List the consumables in your bags and which button each one is on |

## Reporting bugs

Open an issue on GitHub. Please include what you did and what happened, the
Fanny Pack version (shown next to the title in the options, `/fannypack`)
and any error message you got. If an item is on the wrong button, or on
none, include the text from `/fannypack debug`.

## About me

Hi, I'm Graeslurk! I play WoW Forever and make addons in my spare time. I also
made [Pocket Goblin](https://www.curseforge.com/wow/addons/pocketgoblinforever)
and Soul Warden.

Bug reports and ideas are very welcome: open an issue on GitHub.

If Fanny Pack saves you a trip into your bags and you'd like to say thanks,
you can [buy me a coffee](https://buymeacoffee.com/Graeslurk). It's completely
optional: the addon is and will stay free.

## License

All rights reserved, see `LICENSE`.
