# Changelog

## Unreleased

Fixed:
- **Scrolls no longer glow while a class buff covers them**: with Power Word: Fortitude or Prayer of Fortitude on you, a Scroll of Stamina can't be used (the game says a more powerful spell is already active), so its button stays quiet. The same goes for Scrolls of Intellect under Arcane Intellect or Arcane Brilliance, and Scrolls of Spirit under Divine Spirit or Prayer of Spirit. With **Hide while on**, the button switches to another scroll you can use, or hides if there is none

## 1.8.1

1.8.0 was published by mistake without its new features; this is the release it should have been.

New:
- **Custom buttons**: make your own buttons, like AutoBar's custom categories, for any items you like: raid potions, Holy Water, a trinket, a fishing pole. On the new **Custom** page, name a button and add items by dragging them from your bags, Shift-clicking them or typing a name or ID. A button uses the first item in its list that you carry; drag the items to sort them, or right-click the button to pick another item. You can also drop an item from your bags straight onto a custom button on the bar. An item on a custom button leaves its usual button, so you can give, say, Free Action Potions a button of their own. Your custom buttons are shared by all your characters, and like the other buttons each profile turns them on or off and sorts them on the Buttons page. They get a count, a cooldown, a low-stock warning, a macro for your action bars and a hover key binding (`/fannypack bind`) like the other buttons. Turn on **Glow while its buff is missing** for a button of items that give you a buff, like juju or a flask: it glows like Other buffs, silver when the buff runs low
- **Masque support**: with the Masque addon installed, Fanny Pack's buttons (the bar, the camp gear row and the glow preview) are a Masque group called "Fanny Pack", and wear the skin you pick for it in Masque's options (`/msq`), like your action bars. While a skin is on, the Look page's Shape and Border step aside for it; turn the group off in Masque to get Fanny Pack's own look back

Changed:
- **Smoother dragging** on the Buttons page: a row now moves the moment you press on it and stays right under the pointer, instead of starting late and trailing behind it

## 1.7.0

New:
- **Macros for your own action bars**, like the Buffet addon: on the Items page, add a macro for any button (Food, Drink, Bandages, a potion...). Fanny Pack keeps it up to date with the item that button would use, so you can drag it onto Bartender, Dominos or the game's bars and still get the best item. The macros are per character, named "FP" and the button's name, and change out of combat (the game doesn't allow it in a fight)
- **Bind keys by hovering**, like Bartender's /kb: click **Bind keys** on the Buttons page (or type `/fannypack bind`), hover a button on the bar and press a key, with Shift, Ctrl or Alt if you like. The middle mouse button, the side buttons and the mouse wheel work too. Escape over a button clears its key. If the key did something else before, chat says what it was

Changed:
- **Less in chat**: "not in combat" messages (moving the bar, key bindings, macros, a button switching items after the fight) now show in the game's error text at the top of the screen, like its own "you can't do that now" messages. Switching, copying, resetting and deleting profiles in the options no longer repeats itself in chat (`/fannypack profile` still answers there), and a profile name that's already taken is pointed out under the name field

## 1.6.0

New:
- **Russian translation**, thanks to Anemun. Fanny Pack now also matches Russian item names and tooltips regardless of capital letters
- **Glow look**, at the top of the Reminders page: choose how the reminder glow looks. **Soft** is the halo from before, **Border** a frame tight around the button that's easy to see on any ground, **Both** shows the two together, and **Sparkle** is the action bars' sparkling proc glow. **Strength** sets how strongly it shows (50 to 200%), and **Pulse** turns the slow fade in and out off for a steady glow. A preview with a gold (missing) and a silver (running out) sample shows the result as you change it
- **Exact position** on the Bar page: type the bar's X and Y to place it to the point. While the bar is attached they're measured from the player frame's top left, otherwise from the middle of the screen. They follow along when you drag the bar. While the bar is unlocked, small arrows around it (and your arrow keys, while the mouse is over the bar) move it one pixel at a time, or ten with Shift
- **A short tour** on your first login: four small speech bubbles beside the bar explain what it holds, clicking and right-clicking, the reminder glows, and where to find the options. It never starts in combat (a fight pauses it), and **Skip tour** or Escape ends it. Play it again with `/fannypack tour` or **Show the tour** on the Bar page
- **What's new**: after an update with new features, one line in chat says what's new (turn it off on the Bar page with **Tell me about new features**). The first time you open the options after the update, a card at the top lists the new features, each with a **Show me** link to its page, until you click **Got it**. A gold dot marks the pages with something new until you've visited them. Bug-fix updates stay quiet, and a first install shows none of it
- **Items page** in the options: the Hidden items list, and the settings for how items are used (Use on your target, Hide empty buttons, Camp gear only where you can camp), which used to sit under the button list
- **Drag and drop** to order the buttons: on the Buttons page, drag a row by its grip (or anywhere on it) to move its button. The other rows make room, and the page scrolls when you drag near its top or bottom. The arrows still move a button one place. The list's rows are a little tighter, and the Key Bindings button sits beside it, so the Buttons page is much shorter

## 1.5.0

New:
- **Hide items** from the buttons: each item in a button's right-click list has a small **x** that hides it, so no button uses it, not even when your pick runs out. Handy for a flask you're saving for a raid, a drink you don't want on Other buffs, or camp gear you carry for someone else. Hidden items are listed under **Hidden** at the bottom of the right-click list (click one to show it again) and in a new **Hidden items** card on the Buttons page. They're saved per profile

Changed:
- **Camp gear**: a right-click now opens its list (to hide items), and a click still opens the row

## 1.4.2

Fixed:
- **Buff reminders** (buff food, elixirs, scrolls, other buffs) look through all your buffs when the game's lookup by name doesn't find the buff, so a buff you have doesn't keep its button glowing

Changed:
- **`/fannypack debug`** now also lists your buffs as the game gives them to addons, and what each buff reminder looks for and finds, to help with reports about glows

## 1.4.1

Fixed:
- **"Auras cannot be accessed when secret" errors** in combat with an Anti-venom button on the bar. WoW Forever keeps your buffs and debuffs hidden from addons during a fight, so the cure glows now wait until the fight is over, like the other reminders. Every other buff and debuff check (Recently Bandaged, the reminders) is protected the same way

## 1.4.0

New:
- **Anti-venom**, **Poultice** and **Tourniquet** buttons for Forever's First Aid cures: poisons, diseases and bleeds. Each picks your best one (the highest level it cures) and glows gold while you have something it cures. Anti-venom works and glows in combat too; poultices and tourniquets can't be used in combat, so their buttons are off the bar then by default. Out of combat a cure is only used while you have something for it to cure, so a stray click doesn't waste it; Shift-click uses it anyway. In combat the game doesn't let addons change their buttons, so Anti-venom is always used there. With **Hide while on** (Reminders page, Cures row) they stay off the bar until you need one. Bleeds are known by the debuff's name (Rend, Deep Wound, Garrote and anything with "bleed" in it), since the game doesn't mark them
- **Other buffs** button: anything else whose use effect raises a stat for a while, like Rumsey Rum Black Label, juju and buff drinks from fishing. It glows while its buff isn't on you, and has its own Reminders row with **Running out** (up to 60 minutes), **Hide while on** and **Glow**
- **Camp gear** button: click it and a row opens beside it with all the camp gear in your bags (your campfire kit first, then your sleeping bag and camp objects like the Toxin Study), each with its cooldown. Click one to use it. The row opens out of combat only, and the button is off the bar in combat by default. It also hides in dungeons, raids, cities and inns, where you can't camp (**Camp gear only where you can camp** on the Buttons page turns that off)
- Key bindings for the new buttons, under Fanny Pack in the game's Key Bindings
- **`/fannypack debug`** now opens a window with the report selected, ready to copy into a bug report with Ctrl+C, instead of printing it in chat. It also lists camp gear and other items you can use, and fills in items the game hadn't loaded yet

Fixed:
- **Best available food** is now the food that heals the most, read from its tooltip, instead of the one with the highest required level. Before, Tough Jerky could win over Snapvine Watermelon. Drinks (by mana restored), bandages, health and mana potions and healthstones are ranked the same way, and "Use up low-level ones first" uses up the ones that restore least first

## 1.3.1

Fixed:
- **EllesmereUI's player frame**: with EllesmereUI's unit frames, "Attach to player frame" now attaches the bar to EllesmereUI's player frame instead of the game's hidden one. The bar's default spot is just above it, lined up with its left edge (its right edge for a bar growing left), and it moves along when you move the frame in EllesmereUI's unlock mode. A position you saved against the game's player frame starts over at that default spot, since the two frames sit in different places

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
