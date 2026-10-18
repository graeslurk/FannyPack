# Changelog

## 1.3.0

New:
- **Hide while on**: buff food, elixir, scroll and weapon stone, oil and poison buttons can stay off the bar while their buff is on you, and come back when it's gone or running out (glowing silver, ready to refresh). Elixir and scroll buttons first switch to one you carry whose buff isn't on you yet, and only hide when all of them are on. A switch per reminder on the Reminders page, off by default. The game doesn't let addons show or hide buttons in a fight, so changes during combat wait until it ends

## 1.2.1

Fixed:
- Scrolling the options with the mouse wheel no longer gets caught by a slider the pointer passes over. To change a slider with the wheel, stop for a moment over it first

Changed:
- The description in the game's AddOns list now mentions scrolls and the reminders

## 1.2.0

New buttons:
- **Rune**: Demonic Rune and Dark Rune, which have their own cooldown apart from potions
- **Mana gem** (mages): so a mana gem and a mana potion can both be ready. Mana gems no longer end up on the mana potion button
- **Other potion**: every potion that isn't a health or mana potion, such as protection, Free Action, Swiftness and Rage potions. Right-click it to pick which one
- **Eat & drink**: eats and drinks in one click, using your Food and Drink buttons' items. Its count is whichever runs out first

The new buttons are added at the end of your bar; move them with the arrows in the options.

Reminders:
- **Low-stock warning**: a button's count turns red when you're down to your last few (5 bandages, 3 potions and so on by default). Change the limit at the bottom of the button's right-click list or on the Reminders page, or turn the warning off altogether
- **Elixirs and scrolls** glow gold while their buff isn't on you
- **Running out**: buff food, elixirs, scrolls and weapon stones, oils and poisons glow silver shortly before they run out. Choose how long before, for each of them, on the Reminders page (2 minutes by default, or 0 for no silver glow)
- All reminder glows **pulse together**, and look the same on light and dark ground

Buttons and the bar:
- **In and out of combat**: each button has its own switch for each, so it can show always, only outside fights (food, drink and buff food by default, as before) or only in fights. The bar still closes up around hidden buttons. This replaces the "Hide food and drink in combat" switch
- **Use on your target**: bandages and scrolls can go on a friendly target instead of always on you. With no target, or an enemy targeted, they go on you. Off by default
- **Use up low-level items first**: a switch in each button's right-click list makes it pick the lowest-level item and smallest stack instead of the best, to free bag space while levelling

Options and profiles:
- **Options in pages**: a sidebar with Buttons, Bar, Look, Reminders and Profiles, instead of everything on one page
- **Profiles**: keep a whole bar setup per role or character, like one for tanking and one for healing. Switch, create, copy, reset and delete them on the Profiles page, or with `/fannypack profile <name>`. Your current settings become the Default profile, and which buttons show is now part of the profile instead of set per character

Fixed:
- With only one kind of elixir, it no longer shows on both the Elixir and Second elixir buttons when you had picked it for the second one. The second button now only shows when you carry two different elixirs

## 1.1.0

New:
- A **Scroll** button for Scrolls of Agility, Intellect, Protection, Spirit, Stamina and Strength. Like bandages, it always uses the scroll on you, even with a friend targeted. Right-click it to pick which scroll. It's added at the end of your bar; move it with the arrows in the options

## 1.0.1

Fixed:
- An error at login ("attempt to perform arithmetic on local 'top'") when the game keeps the player frame's position secret from addons. The bar now skips those numbers and still finds its place

## 1.0.0

First release:
- **One small bar** with buttons for healthstones, bandages, health potions, mana potions, two elixirs (and flasks), weapon stones and oils, food, drinks and buff food
- **Weapon stones and oils** go straight on your main hand weapon with one click, or your off-hand with Shift-click. The button glows softly while a weapon has nothing on it (can be turned off)
- **Rogue poisons**: Main-hand and Off-hand poison buttons, each with its own poison, that glow while their hand has nothing on it
- **Plain food and buff food are kept apart**: food that makes you Well Fed gets its own button, which glows softly while you're not Well Fed (can be turned off)
- Each button uses the **best item you carry that you can use**, with its count and cooldown. **Right-click** a button to pick a different item
- The bandage button shows how long you're **Recently Bandaged**, and always bandages you
- Buttons with nothing to use are **hidden**, or faded out if you prefer
- **Food, buff food and drink hide in combat**, since you can't eat or drink in a fight (can be turned off)
- The bar sits **above your player frame**, lined up with its right end and clear of the pet frame and cast bar; unlock it to drag it anywhere
- The bar is **attached to the player frame**, so it moves along when you move the player frame in Edit Mode. Turn this off to pin it to the screen
- **Sort the buttons** in any order and choose which way the bar **grows**: right, left, down or up. The first button stays put, and buttons hidden in combat leave no gaps
- **Rows**: choose how many buttons go in a row and where new rows go
- Choose the **button size**, the **spacing** and **which buttons** each character shows. Warriors and rogues don't get the drink and mana potion buttons by default
- Works **in combat**: changes to your bags during a fight reach the bar as soon as combat ends
- **Hotkeys** for every button, in the game's Key Bindings under Fanny Pack, shown in the button's corner
- **Button styles**: square, rounded or round, with no border or a thin silver or gold one
- **Fade out of combat**: the bar shows when you hover over it or a fight starts
- **Resizable options window** that fits small screens: one column when narrow, scrolling when short
- **Minimap button** that opens the options, with what you carry in its tooltip
- `/fannypack debug` lists the consumables in your bags and which button each one is on
