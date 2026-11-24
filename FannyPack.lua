-- Fanny Pack: one small bar for bandages, food, buff food, drinks and
-- potions. This file finds them in your bags and picks the item each
-- button uses. Bar.lua draws the buttons, UI.lua the options window.

local ADDON_NAME, ns = ...
local L = ns.L

local PREFIX = "|cff5fb48eFanny Pack|r: "
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local CONSUMABLE = Enum.ItemClass and Enum.ItemClass.Consumable or 0

local GetItemSpell = C_Item.GetItemSpell or GetItemSpell
local IsUsableItem = C_Item.IsUsableItem or IsUsableItem
local GetItemCount = C_Item.GetItemCount or GetItemCount

-- The buttons, left to right. Items are recognised by their use effect:
-- spell is that effect's spell ID (its name comes from the game, so it's
-- in the client's language) and fallback its English name, in case the
-- spell isn't known. Classic items are plain "Consumable", without a food
-- or bandage subtype to go by. icon is an item whose icon the button shows
-- when you carry none (texture: an icon file to show instead). eating: food and drink, which hide in combat unless
-- the player turns them on there (see ns.ShowsInCombat).
-- list: the button shares another button's items (the second elixir takes
-- the best one the first doesn't use); allowSame: it may use the same one
-- when there's no other. slot: the item goes on the weapon in that slot
-- (16 main hand, 17 off-hand), shiftSlot with Shift held. class: only that
-- class gets the button. self: used on you, even with a friend targeted
-- (unless "Use on your target" is on). lowStock: the count turns red at this many or fewer, unless
-- changed in the button's right-click list (none: no warning). The order
-- here is the default order on the bar. buff: glows while the buff from its
-- item isn't on you. combo: uses the items of these buttons in one press.
-- cure: the kind of debuff its items cure (Poison, Disease or Bleed); it
-- glows while you have one. flyout: a click opens a row with all its items
-- (see Bar.lua) instead of using one. noCombat: off the bar in combat by
-- default.
ns.KINDS = {
    { key = "healthstone", name = L["Healthstone"], icon = 5509 }, -- see HEALTHSTONES
    { key = "bandage", name = L["Bandages"], spell = 746, fallback = "First Aid", icon = 1251, self = true,
        lowStock = 5 },
    -- Forever's First Aid cures, recognised by their names (see Classify).
    { key = "antiVenom", name = L["Anti-venom"], icon = 6452, self = true, cure = "Poison", lowStock = 2 },
    -- Poultices and tourniquets can't be used in combat.
    { key = "poultice", name = L["Poultice"], icon = 2447, self = true, cure = "Disease", noCombat = true,
        lowStock = 2 },
    { key = "tourniquet", name = L["Tourniquet"], icon = 2318, self = true, cure = "Bleed", noCombat = true,
        lowStock = 2 },
    { key = "healthPotion", name = L["Health potion"], spell = 439, fallback = "Healing Potion", icon = 118,
        lowStock = 3 },
    { key = "manaPotion", name = L["Mana potion"], spell = 437, fallback = "Restore Mana", icon = 2455, lowStock = 3 },
    { key = "rune", name = L["Rune"], icon = 12662, lowStock = 2 }, -- see RUNES
    { key = "manaGem", name = L["Mana gem"], icon = 5514, class = "MAGE" }, -- see MANA_GEMS
    { key = "otherPotion", name = L["Other potion"], icon = 5634 }, -- potions that aren't health or mana, see Classify
    { key = "elixir", name = L["Elixir"], icon = 2454, buff = true }, -- elixirs and flasks, see Classify
    { key = "elixir2", name = L["Second elixir"], icon = 5997, list = "elixir", buff = true },
    { key = "scroll", name = L["Scroll"], icon = 1181, self = true, buff = true }, -- see SCROLLS
    -- Anything else that gives a timed buff, like Rumsey Rum or juju (see Classify).
    { key = "otherBuff", name = L["Other buffs"], icon = 21151, buff = true, lowStock = 2 },
    { key = "weapon", name = L["Weapon stone or oil"], icon = 2862, slot = 16, shiftSlot = 17 }, -- see WEAPON_ITEMS
    { key = "poison", name = L["Main-hand poison"], icon = 6947, slot = 16, class = "ROGUE", lowStock = 5 }, -- see POISONS
    { key = "poison2", name = L["Off-hand poison"], icon = 2892, slot = 17, class = "ROGUE",
        list = "poison", allowSame = true, lowStock = 5 },
    { key = "food", name = L["Food"], spell = 433, fallback = "Food", icon = 117, eating = true, lowStock = 5 },
    { key = "drink", name = L["Drink"], spell = 430, fallback = "Drink", icon = 159, eating = true, lowStock = 5 },
    { key = "eatDrink", name = L["Eat & drink"], icon = 117, combo = { "food", "drink" }, eating = true, lowStock = 5 },
    -- food whose tooltip mentions Well Fed
    { key = "buffFood", name = L["Buff food"], icon = 6888, eating = true, lowStock = 2 },
    -- Forever's camp gear, and other things you set up at a camp (see IsCamp).
    -- outdoors: hidden where you can't camp (see ns.SetCampOutdoorsOnly).
    { key = "camp", name = L["Camp gear"], icon = 211527, texture = 135805, flyout = true, noCombat = true,
        outdoors = true }, -- a campfire
}

-- Warlock healthstones, Minor to Major, each with its two improved versions
-- from the warlock talent. Their use effects all have different names.
local HEALTHSTONES = {
    [5512] = true, [19004] = true, [19005] = true, -- Minor
    [5511] = true, [19006] = true, [19007] = true, -- Lesser
    [5509] = true, [19008] = true, [19009] = true, -- Healthstone
    [5510] = true, [19010] = true, [19011] = true, -- Greater
    [9421] = true, [19012] = true, [19013] = true, -- Major
}

ns.KIND_BY_KEY = {}
for _, kind in ipairs(ns.KINDS) do ns.KIND_BY_KEY[kind.key] = kind end

-- Sharpening stones, weightstones and oils that go on a weapon for half an
-- hour. Newer ones are caught by their names (see Classify).
local WEAPON_ITEMS = {
    [2862] = true, [2863] = true, [2871] = true, [7964] = true, [12404] = true, -- sharpening stones, Rough to Dense
    [18262] = true, [23122] = true, -- Elemental and Consecrated Sharpening Stone
    [3239] = true, [3240] = true, [3241] = true, [7965] = true, [12643] = true, -- weightstones, Rough to Dense
    [20744] = true, [20746] = true, [20750] = true, [20749] = true, [23123] = true, -- wizard oils, Minor to Blessed
    [20745] = true, [20747] = true, [20748] = true, -- mana oils, Minor to Brilliant
    [3824] = true, [3829] = true, -- Shadow Oil, Frost Oil
}

-- Demonic Rune and Dark Rune: mana for health, on their own cooldown, apart
-- from potions.
local RUNES = { [12662] = true, [20520] = true }

-- Mage mana gems, Agate to Ruby: also on their own cooldown, and their use
-- effect shares its name with mana potions', so they're sorted out first.
local MANA_GEMS = { [5514] = true, [5513] = true, [8007] = true, [8008] = true }

-- Scrolls of Agility, Intellect, Protection, Spirit, Stamina and Strength,
-- ranks I to IV. Newer ones are caught by their names (see Classify).
local SCROLLS = {
    [3012] = true, [1477] = true, [4425] = true, [10309] = true, -- Agility
    [955] = true, [2290] = true, [4419] = true, [10308] = true, -- Intellect
    [3013] = true, [1478] = true, [4421] = true, [10305] = true, -- Protection
    [1181] = true, [1712] = true, [4424] = true, [10306] = true, -- Spirit
    [1180] = true, [1711] = true, [4422] = true, [10307] = true, -- Stamina
    [954] = true, [2289] = true, [4426] = true, [10310] = true, -- Strength
}

-- Rogue poisons. Newer ones are caught by their names (see Classify).
local POISONS = {
    [6947] = true, [6949] = true, [6950] = true, [8926] = true, [8927] = true, [8928] = true, -- Instant I-VI
    [2892] = true, [2893] = true, [8984] = true, [8985] = true, [20844] = true, -- Deadly I-V
    [3775] = true, [3776] = true, -- Crippling I-II
    [5237] = true, [6951] = true, [9186] = true, -- Mind-numbing I-III
    [10918] = true, [10920] = true, [10921] = true, [10922] = true, -- Wound I-IV
}

-- The icon a button shows when it has no item of its own.
function ns.KindIcon(kind)
    return kind.texture or select(5, C_Item.GetItemInfoInstant(kind.icon))
end

-- Whether this character gets a button: some are for one class only.
function ns.IsAvailable(key)
    local kind = ns.KIND_BY_KEY[key]
    if not kind then return false end -- a deleted custom button
    local class = kind.class
    return not class or class == select(2, UnitClass("player"))
end

local CONSUMABLE_SUBCLASS = Enum.ItemConsumableSubclass or {}
local SCROLL_SUBCLASS = CONSUMABLE_SUBCLASS.Scroll or 4
local POTION_SUBCLASS = CONSUMABLE_SUBCLASS.Potion or 1
local ELIXIR_SUBCLASSES = {
    [CONSUMABLE_SUBCLASS.Elixir or 2] = true,
    [CONSUMABLE_SUBCLASS.Flask or 3] = true,
}

-- Each button's global name, which its key binding (Bindings.xml) clicks.
function ns.ButtonName(key)
    return "FannyPack" .. key:sub(1, 1):upper() .. key:sub(2) .. "Button"
end

-- Names for the key bindings, under Fanny Pack in the game's Key Bindings.
for _, kind in ipairs(ns.KINDS) do
    _G["BINDING_NAME_CLICK " .. ns.ButtonName(kind.key) .. ":LeftButton"] = kind.name
end

-- Settings shared by all your characters, outside profiles.
local ACCOUNT_DEFAULTS = {
    locked = true,
    minimapButton = true,
    minimapAngle = 200, -- degrees around the minimap, 0 = right, 90 = top
    -- window = the options window's place and size
}

-- A profile is the whole bar setup. Each character uses one; all start on
-- Default. Tables here are copied into each profile.
local PROFILE_DEFAULTS = {
    buttonSize = 26,
    spacing = 2,
    hideEmpty = true, -- false: empty buttons are faded instead
    combat = {}, -- [button key] = shown in combat; unset: all but food and drink
    shape = "square", -- square, rounded or round
    border = "none", -- none, silver or gold
    buffFoodGlow = true, -- the buff food button glows while you're not Well Fed
    weaponGlow = true, -- the weapon stone or oil button glows while a weapon has none on it
    elixirGlow = true, -- the elixir buttons glow while their buff isn't on you
    -- scrollGlow: the same for the scroll button; starts as elixirGlow, which it was part of
    otherBuffGlow = true, -- the Other buffs button glows while its buff isn't on you
    cureGlow = true, -- the cure buttons glow while you have a debuff they cure
    campOutdoorsOnly = true, -- the Camp gear button hides in dungeons, raids, cities and inns
    glowStyle = "soft", -- the reminder glow: soft (a halo), border, both, or proc (the action bars' sparkle)
    glowStrength = 100, -- how strongly it shows, in percent (50 to 200)
    glowPulse = true, -- false: a steady glow
    preferLow = {}, -- [button key] = true: pick the lowest-level item and smallest stack first
    fadeOutOfCombat = false, -- hide the bar out of combat until you hover over it
    useOnTarget = false, -- bandages and scrolls go on a friendly target instead of always on you
    attached = true, -- the bar moves along with the player frame
    direction = "LEFT", -- the way the bar grows from its first button: RIGHT, LEFT, DOWN or UP
    perRow = 12, -- buttons per row before the bar wraps; 12 or more keeps one row
    order = {}, -- button keys from the first button on; filled in from ns.KINDS
    lowStock = {}, -- [button key] = warn at this many or fewer; unset: the kind's default
    hideWhileOn = {}, -- [reminder: wellFed, elixir, scroll, otherBuff, weapon] = true: its buttons hide
    -- while the buff is on; [cure] = true: the cure buttons hide while you have nothing to cure
    lowStockWarning = true, -- false: no count turns red, whatever the limits
    hidden = {}, -- [itemID] = true: no button uses it (see ns.SetHidden)
    buttons = {}, -- [button key] = shown out of combat; filled in for the character's class
}
-- Also part of a profile, but unset by default:
--   rowsToward = where new rows go: UP or DOWN for a bar growing sideways,
--     LEFT or RIGHT for one growing up or down (see ns.RowsToward)
--   position = { frame = "player" or "screen", x, y } once the bar is
--     dragged; until then it sits above the player frame
--   wellFedMinutes, elixirMinutes, scrollMinutes, otherBuffMinutes, weaponMinutes = how long
--     before each runs out its reminder glows silver (0: never); see
--     ns.RUNNING_OUT
-- And from 1.1.0, carried into the first profile and then converted (see
-- FillProfile): hideEatingInCombat.
local PROFILE_ONLY = { rowsToward = true, position = true, hideEatingInCombat = true }

-- The "running out" settings, each up to how long that kind of buff lasts,
-- in minutes. Saved as <name>Minutes in the profile.
ns.RUNNING_OUT = { wellFed = 15, elixir = 60, scroll = 30, otherBuff = 60, weapon = 30 }
local DEFAULT_RUNNING_OUT = 2

local DEFAULT_PROFILE = "Default"
ns.DEFAULT_PROFILE = DEFAULT_PROFILE

-- Classes without mana don't get the drink and mana potion buttons by default.
local NO_MANA = { WARRIOR = true, ROGUE = true }
local MANA_KINDS = { drink = true, manaPotion = true, rune = true, eatDrink = true }

local account -- FannyPackDB: account-wide settings and the profiles
local db -- the active profile (account.profiles[name])
local charDB -- FannyPackCharDB: this character's chosen items
local characterKey -- "Name - Realm", for account.profileKeys

local function DeepCopy(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and DeepCopy(value) or value
    end
    return copy
end

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version")
if not ns.VERSION or ns.VERSION:find("^@") then
    ns.VERSION = "dev" -- running from source; the CurseForge packager fills in the real version
else
    ns.VERSION = ns.VERSION:gsub("^v", "") -- the packager uses the tag name, e.g. "v1.0.0"
end

local function Print(msg, ...)
    print(PREFIX .. (select("#", ...) > 0 and msg:format(...) or msg))
end
ns.Print = Print

-- "Not now" messages, like the game's own: in the error text at the top of
-- the screen (red), where they're seen at the moment, instead of in chat.
-- notice: yellow, for "it happens later" rather than "it can't happen".
function ns.Refuse(msg, notice)
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(msg, 1, notice and 0.82 or 0.1, notice and 0 or 0.1)
    else
        Print(msg)
    end
end

------------------------------------------------------------------------
-- Recognising items
------------------------------------------------------------------------

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    return GetSpellInfo and GetSpellInfo(spellID)
end
ns.SpellName = SpellName

local kindBySpell -- [use effect name] = kind key

local function BuildSpellMap()
    kindBySpell = {}
    for _, kind in ipairs(ns.KINDS) do
        if kind.spell then
            kindBySpell[SpellName(kind.spell) or kind.fallback] = kind.key
        end
    end
end

-- Hidden tooltip for reading item text, for clients without C_TooltipInfo.
local scanTooltip

local function TooltipLines(itemID)
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local data = C_TooltipInfo.GetItemByID(itemID)
        if not data then return nil end
        local lines = {}
        for _, line in ipairs(data.lines or {}) do lines[#lines + 1] = line.leftText end
        return lines
    end
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "FannyPackScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTooltip:SetItemByID(itemID)
    local lines = {}
    for i = 1, scanTooltip:NumLines() do
        local text = _G["FannyPackScanTooltipTextLeft" .. i]
        lines[#lines + 1] = text and text:GetText()
    end
    scanTooltip:Hide()
    return lines
end

-- true if a line of the item's tooltip contains text (any case), nil if
-- the tooltip isn't loaded yet. With needsUse, the tooltip only counts as
-- loaded once its "Use:" line is there: the game can return an item's
-- tooltip before the text of its use effect has arrived.
local function TooltipHas(itemID, text, needsUse)
    local lines = TooltipLines(itemID)
    if not lines then return nil end
    local useLabel = needsUse and ns.Lower(ITEM_SPELL_TRIGGER_ONUSE or "Use:")
    local found, hasUse = false, not needsUse
    text = ns.Lower(text)
    for _, line in pairs(lines) do
        line = line and ns.Lower(line)
        if line then
            if line:find(text, 1, true) then found = true end
            if useLabel and line:find(useLabel, 1, true) == 1 then hasUse = true end
        end
    end
    if not hasUse then return nil end
    return found
end

-- The red lines of an item's tooltip (what keeps you from using it), joined.
local function RedLines(itemID)
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    local data = C_TooltipInfo.GetItemByID(itemID)
    local red = {}
    for _, line in ipairs(data and data.lines or {}) do
        local color = line.leftColor
        if color and line.leftText and color.r > 0.9 and color.g < 0.3 and color.b < 0.3 then
            red[#red + 1] = line.leftText
        end
    end
    return #red > 0 and table.concat(red, "; ") or nil
end

-- The item's "Use:" line, in lower case, or nil if the tooltip (or the
-- text of its use effect) isn't loaded yet.
local function UseLine(itemID)
    local lines = TooltipLines(itemID)
    if not lines then return nil end
    local useLabel = ns.Lower(ITEM_SPELL_TRIGGER_ONUSE or "Use:")
    for _, line in pairs(lines) do
        line = line and ns.Lower(line)
        if line and line:find(useLabel, 1, true) == 1 then return line end
    end
end

-- Buttons whose items are ranked by how much they heal or restore, read
-- from the "Use:" line of their tooltips ("Restores 294 health over 21
-- sec."). Required and item levels don't say it: a low-level food can heal
-- more than a higher one.
local RANK_BY_AMOUNT = {
    food = true, drink = true, bandage = true, healthPotion = true, manaPotion = true, healthstone = true,
    -- Cures: "cured of poisons up to level 45".
    antiVenom = true, poultice = true, tourniquet = true,
}
local amounts = {} -- [itemID] = the largest number in its "Use:" line (cached once known)

-- How much an item heals or restores, 0 if its "Use:" line has no number,
-- or nil if the tooltip isn't loaded yet.
local function Amount(itemID)
    if amounts[itemID] then return amounts[itemID] end
    local line = UseLine(itemID)
    if not line then return nil end
    -- Thousands separators ("1,344", "1.344") between digits go first.
    line = line:gsub("(%d)[,.](%d%d%d)", "%1%2")
    local amount = 0
    for number in line:gmatch("%d+") do amount = math.max(amount, tonumber(number)) end
    amounts[itemID] = amount
    return amount
end

local itemKinds = {} -- [itemID] = kind key, or false (cached once known)
local conjured = {}  -- [itemID] = true/false (cached once known)
local undecided = false -- the last scan met items it couldn't sort yet

-- [itemID] = whether you can use it, from the last check out of combat.
-- In combat the game calls food and drink unusable, which would turn
-- their buttons red after the fight.
local usableOutOfCombat = {}

-- Camp gear: Forever's campfires and camp objects (a tent, a chair, a
-- Toxin Study...), which aren't all consumables. Known by "campfire",
-- "camping" or "camp feature" in the name or the "Use:" line, or a name
-- starting with "Camp ", and a few by their IDs. Not just "camp": the
-- Hearthstone "returns you to Camp Taurajo".
local CAMP_ITEMS = {
    [211527] = true, -- Cozy Sleeping Bag
}
-- Never camp gear, whatever their text says: gear, quest items, and the
-- recipes that teach camp objects.
local NOT_CAMP_CLASSES = {
    [Enum.ItemClass and Enum.ItemClass.Weapon or 2] = true,
    [Enum.ItemClass and Enum.ItemClass.Armor or 4] = true,
    [Enum.ItemClass and Enum.ItemClass.Recipe or 9] = true,
    [Enum.ItemClass and Enum.ItemClass.Questitem or 12] = true,
}

-- true or false, or nil if the item's text isn't loaded yet.
local function IsCamp(itemID)
    if CAMP_ITEMS[itemID] then return true end
    local name = C_Item.GetItemInfo(itemID)
    if not name then return nil end
    name = ns.Lower(name)
    if name:find(L["camp "], 1, true) == 1 then return true end
    local line = UseLine(itemID)
    if not line then return nil end
    if line:find(L["teaches you"], 1, true) then return false end
    for _, word in ipairs({ L["campfire"], L["camping"], L["camp feature"] }) do
        if name:find(word, 1, true) or line:find(word, 1, true) then return true end
    end
    return false
end

-- First Aid's cures, by name: Anti-Venom, and Forever's poultices and
-- tourniquets (filed as trade goods, not consumables).
local function CureKind(itemID)
    local name = ns.Lower(C_Item.GetItemInfo(itemID) or "")
    return (name:find(L["anti-venom"], 1, true) and "antiVenom")
        or (name:find(L["poultice"], 1, true) and "poultice")
        or (name:find(L["tourniquet"], 1, true) and "tourniquet")
end

-- The kind of button an item belongs on, or nil. Items the game hasn't
-- loaded yet are requested and get sorted on the next scan.
local function Classify(itemID)
    -- Items you put on a custom button go there, whatever they are.
    local custom = ns.customItems and ns.customItems[itemID]
    if custom then return custom end
    local cached = itemKinds[itemID]
    if cached ~= nil then return cached or nil end

    -- Forever can report a mana gem as Armor (e.g. Mana Agate, item 5514).
    if MANA_GEMS[itemID] then
        itemKinds[itemID] = "manaGem"
        return "manaGem"
    end

    local classID, subClassID = select(6, C_Item.GetItemInfoInstant(itemID))
    if classID ~= CONSUMABLE then
        -- Only cures and camp gear get a button among the other items you can use.
        if not classID or NOT_CAMP_CLASSES[classID] then
            itemKinds[itemID] = false
            return nil
        end
        if not CAMP_ITEMS[itemID] and not C_Item.IsItemDataCachedByID(itemID) then
            C_Item.RequestLoadItemDataByID(itemID)
            undecided = true
            return nil
        end
        if not CAMP_ITEMS[itemID] and not GetItemSpell(itemID) then
            itemKinds[itemID] = false -- nothing to use
            return nil
        end
        local cure = CureKind(itemID)
        if cure then
            itemKinds[itemID] = cure
            return cure
        end
        local camp = IsCamp(itemID)
        if camp == nil then
            undecided = true
            return nil
        end
        itemKinds[itemID] = camp and "camp" or false
        return camp and "camp" or nil
    end
    local listed = (HEALTHSTONES[itemID] and "healthstone") or (WEAPON_ITEMS[itemID] and "weapon")
        or (POISONS[itemID] and "poison") or (SCROLLS[itemID] and "scroll")
        or (RUNES[itemID] and "rune")
    if listed then
        itemKinds[itemID] = listed
        return listed
    end
    if not C_Item.IsItemDataCachedByID(itemID) then
        C_Item.RequestLoadItemDataByID(itemID)
        undecided = true
        return nil
    end
    local spell = GetItemSpell(itemID)
    if not spell then return nil end -- no use effect

    -- First Aid's cures go by their names, before their use effects: some
    -- may share First Aid's with bandages.
    local name = ns.Lower(C_Item.GetItemInfo(itemID) or "")
    local cure = CureKind(itemID)
    if cure then
        itemKinds[itemID] = cure
        return cure
    end
    local camp = IsCamp(itemID)
    if camp == nil then
        undecided = true
        return nil
    elseif camp then
        itemKinds[itemID] = "camp"
        return "camp"
    end

    if not kindBySpell then BuildSpellMap() end
    local key = kindBySpell[spell] or false
    if key == false then
        -- Not one of the use effects above: go by the item's type and name.
        -- The names catch healthstones, stones, oils and poisons newer than
        -- the lists, and elixirs and flasks the game files as plain
        -- consumables. Elixirs go first, for Elixir of Poison Resistance.
        local paddedName = " " .. name .. " " -- some locales match whole words
        if name:find(L["healthstone"], 1, true) then
            key = "healthstone"
        elseif ELIXIR_SUBCLASSES[subClassID] or name:find(L["elixir"], 1, true) or paddedName:find(L["flask"], 1, true) then
            key = "elixir"
        elseif subClassID == SCROLL_SUBCLASS or name:find(L["scroll of"], 1, true) then
            key = "scroll"
        elseif name:find(L["sharpening stone"], 1, true) or name:find(L["weightstone"], 1, true)
            or name:find(L["wizard oil"], 1, true) or name:find(L["mana oil"], 1, true) then
            key = "weapon"
        elseif paddedName:find(L["poison"], 1, true) then
            key = "poison"
        elseif name:find(L["demonic rune"], 1, true) or name:find(L["dark rune"], 1, true) then
            key = "rune"
        elseif subClassID == POTION_SUBCLASS or name:find(L["potion"], 1, true) then
            key = "otherPotion" -- health and mana potions were found by their use effects above
        end
    end
    if key == "food" or key == false then
        -- Buff food says "...you will become well fed..." in its tooltip.
        -- Checked for any use effect, in case some buff food isn't plain "Food".
        local buff = TooltipHas(itemID, L["well fed"], true)
        if buff == nil then
            undecided = true
            return nil
        end
        if buff then key = "buffFood" end
    end
    if key == false then
        -- Anything else whose use effect raises a stat for a while ("Increases
        -- Stamina by 15 for 15 min."): Rumsey Rum, juju, fishing finds.
        local line = UseLine(itemID) or "" -- loaded: the Well Fed check needed it
        local alternateIncrease = rawget(L, "increases (alternate)")
        local raisesStat = line:find(L["increases"], 1, true)
            or (alternateIncrease and line:find(alternateIncrease, 1, true))
        if raisesStat and (line:find(L["%d+ min"]) or line:find(L["%d+ hour"])) then
            key = "otherBuff"
        end
    end
    itemKinds[itemID] = key
    return key or nil
end

-- Conjured food and water vanish when you log out, so they're eaten first.
local function IsConjured(itemID)
    if conjured[itemID] == nil then
        local found = ITEM_CONJURED and TooltipHas(itemID, ITEM_CONJURED)
        if found == nil then return false end -- not loaded yet; check again later
        conjured[itemID] = found
    end
    return conjured[itemID]
end

------------------------------------------------------------------------
-- Scanning the bags
------------------------------------------------------------------------

-- [kind key] = list of { itemID, count, name, quality, icon, level,
-- itemLevel, amount, conjured, usable }, best first. amount: how much it
-- heals or restores, on the RANK_BY_AMOUNT buttons (0 on the others).
ns.items = {}
-- [kind key] = the same for items you've hidden: no button uses them, and
-- they're listed under Hidden in the right-click list.
ns.hiddenItems = {}
for _, kind in ipairs(ns.KINDS) do
    if not kind.list and not kind.combo then
        ns.items[kind.key] = {}
        ns.hiddenItems[kind.key] = {}
    end
end

-- The items a button picks from: its own, or the button's it shares.
local NO_ITEMS = {} -- for Eat & drink, which has no items of its own

function ns.ListFor(key)
    local kind = ns.KIND_BY_KEY[key]
    if kind.combo then return NO_ITEMS end
    return ns.items[kind.list or key]
end

-- The hidden items a button would otherwise pick from.
function ns.HiddenFor(key)
    local kind = ns.KIND_BY_KEY[key]
    if kind.combo then return NO_ITEMS end
    return ns.hiddenItems[kind.list or key]
end

-- For "use up low-level items first": conjured ones (they vanish anyway),
-- then the one that restores least, then the lowest level, then the
-- smallest stack.
local function Lower(a, b)
    if a.conjured ~= b.conjured then return a.conjured end
    if a.amount ~= b.amount then return a.amount < b.amount end
    if a.level ~= b.level then return a.level < b.level end
    if a.count ~= b.count then return a.count < b.count end
    return a.itemID < b.itemID
end

-- Best first: items you can use, then the one that heals or restores
-- most, then the highest required level, then conjured items (they vanish
-- anyway), then the highest item level.
local function Better(a, b)
    if a.usable ~= b.usable then return a.usable end
    if a.amount ~= b.amount then return a.amount > b.amount end
    if a.level ~= b.level then return a.level > b.level end
    if a.conjured ~= b.conjured then return a.conjured end
    if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
    return a.itemID < b.itemID
end

-- The camp gear row: campfires first, then by name.
local function CampFirst(a, b)
    local aFire = ns.Lower(a.name):find(L["campfire"], 1, true) ~= nil
    local bFire = ns.Lower(b.name):find(L["campfire"], 1, true) ~= nil
    if aFire ~= bFire then return aFire end
    if a.name ~= b.name then return a.name < b.name end
    return a.itemID < b.itemID
end

-- Custom buttons: items you can use first, then in the order of the
-- button's list (Custom.lua).
local function YourOrder(kind)
    local rank = {}
    for i, itemID in ipairs(kind.items) do rank[itemID] = i end
    return function(a, b)
        if a.usable ~= b.usable then return a.usable end
        local x, y = rank[a.itemID] or math.huge, rank[b.itemID] or math.huge
        if x ~= y then return x < y end
        return a.itemID < b.itemID
    end
end

local retries = 0

function ns.Scan()
    undecided = false
    local found = {} -- [itemID] = kind key
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local key = info and Classify(info.itemID)
            if key then found[info.itemID] = key end
        end
    end

    for _, list in pairs(ns.items) do wipe(list) end
    for _, list in pairs(ns.hiddenItems) do wipe(list) end
    local playerLevel = UnitLevel("player")
    for itemID, key in pairs(found) do
        local name, _, quality, itemLevel, minLevel, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
        if name then
            local usable = (minLevel or 0) <= playerLevel
            if usable and IsUsableItem then
                if InCombatLockdown() then
                    usable = usableOutOfCombat[itemID] ~= false
                else
                    usable = IsUsableItem(itemID) and true or false
                    -- The game calls some items unusable with nothing in their
                    -- tooltip to say why, like the old Anti-Venom (Potent
                    -- Anti-Venom works): only a red requirement counts.
                    if not usable and C_TooltipInfo and not RedLines(itemID) then usable = true end
                    usableOutOfCombat[itemID] = usable
                end
            end
            local amount = 0
            if RANK_BY_AMOUNT[key] then
                amount = Amount(itemID)
                if not amount then
                    undecided = true -- ranked by level until its tooltip arrives
                    amount = 0
                end
            end
            local lists = db and db.hidden[itemID] and ns.hiddenItems or ns.items
            table.insert(lists[key], {
                itemID = itemID,
                count = GetItemCount(itemID),
                name = name,
                quality = quality,
                icon = icon,
                level = minLevel or 0,
                itemLevel = itemLevel or 0,
                amount = amount,
                conjured = IsConjured(itemID),
                usable = usable,
            })
        end
    end
    for key, list in pairs(ns.items) do
        local kind = ns.KIND_BY_KEY[key]
        if kind.custom then
            table.sort(list, YourOrder(kind))
        else
            table.sort(list, key == "camp" and CampFirst or Better)
        end
    end
    for _, list in pairs(ns.hiddenItems) do
        table.sort(list, function(a, b) return a.name < b.name end)
    end

    -- Some item text arrives without an event, so look again in a moment.
    if undecided and retries < 10 then
        retries = retries + 1
        ns.QueueScan(2)
    elseif not undecided then
        retries = 0
    end
end

-- The item a button should use: the one you picked if you still carry it,
-- otherwise the best one you can use (or, if you can't use any, the best
-- one anyway, shown in red).
-- The second button sharing a button's items: [elixir] = elixir2.
local SECOND = {}
for _, kind in ipairs(ns.KINDS) do
    if kind.list then SECOND[kind.list] = kind.key end
end

-- The item picked by hand for a button, if it's in your bags (and wanted:
-- see ns.ItemFor).
local function HandPicked(key, list, wanted)
    local chosen = charDB and charDB.chosen[key]
    if not chosen then return nil end
    for _, entry in ipairs(list) do
        if entry.itemID == chosen then return (not wanted or wanted(entry)) and entry or nil end
    end
end

-- The best wanted item other than skip, or with "use up low-level items
-- first" on, the lowest usable one.
local function AutoPick(key, list, skip, wanted)
    local function ok(entry)
        return entry ~= skip and (not wanted or wanted(entry))
    end
    if db and db.preferLow[key] then
        local pick
        for _, entry in ipairs(list) do
            if ok(entry) and entry.usable and (not pick or Lower(entry, pick)) then pick = entry end
        end
        if pick then return pick end
    end
    for _, entry in ipairs(list) do
        if ok(entry) then return entry end
    end
end

-- The item a button uses, among the wanted ones (all if wanted is nil).
local function Pick(key, wanted)
    local kind = ns.KIND_BY_KEY[key]
    local list = ns.ListFor(key)
    local picked = HandPicked(key, list, wanted)

    if kind.list then
        -- A second button (second elixir, off-hand poison) never uses the
        -- first one's item, so with one kind of elixir there's no second
        -- elixir. Poisons may share, when picked so or there's no other.
        local first = ns.ItemFor(kind.list)
        if picked and (picked ~= first or kind.allowSame) then return picked end
        return AutoPick(key, list, first, wanted) or (kind.allowSame and first or nil)
    end

    if picked then return picked end
    -- What you picked by hand for the second button beats this button's
    -- automatic pick, unless there's nothing else.
    local reserved = SECOND[key] and HandPicked(SECOND[key], list, wanted)
    return AutoPick(key, list, reserved, wanted) or reserved
end

-- With "Hide while on", these buttons skip items whose buff is already on
-- you, so they show one you can still use; only with all of them on do they
-- hide. Two elixirs with one drunk: Elixir shows the other, Second elixir hides.
local SKIPS_ACTIVE = { elixir = "elixir", elixir2 = "elixir", scroll = "scroll", otherBuff = "otherBuff" }

function ns.ItemFor(key)
    local kind = ns.KIND_BY_KEY[key]
    if kind.combo then -- something to eat or drink, if either button has it
        return ns.ItemFor(kind.combo[1]) or ns.ItemFor(kind.combo[2])
    end
    local reminder = SKIPS_ACTIVE[key]
    if reminder and db and db.hideWhileOn[reminder] and ns.BuffIsOn then
        local pick = Pick(key, function(entry) return not ns.BuffIsOn(key, entry.itemID) end)
        if pick then return pick end
        -- All of them are on: the usual pick, which then hides.
    end
    return Pick(key)
end

-- Total carried of a kind, for the minimap tooltip.
function ns.CountKind(key)
    local total = 0
    for _, entry in ipairs(ns.ListFor(key)) do total = total + entry.count end
    return total
end

-- Item data arrives in bursts; scan once after it settles.
local scanQueued = false
local function QueueScan(delay)
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(delay or 0.1, function()
        scanQueued = false
        ns.Scan()
        ns.UpdateBar()
        if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
    end)
end
ns.QueueScan = QueueScan

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------

-- itemID, or nil to go back to the best one automatically.
function ns.SetChoice(key, itemID)
    charDB.chosen[key] = itemID
    if InCombatLockdown() then
        ns.Refuse(L["The button will switch to it when combat ends."], true)
    end
    ns.UpdateBar()
end

function ns.SetButtonShown(key, show)
    db.buttons[key] = show and true or false
    ns.UpdateBar()
end

function ns.SetButtonSize(value)
    db.buttonSize = math.floor(value + 0.5)
    ns.UpdateBar()
end

function ns.SetSpacing(value)
    db.spacing = math.floor(value + 0.5)
    ns.UpdateBar()
end

function ns.SetHideEmpty(value)
    db.hideEmpty = value and true or false
    ns.UpdateBar()
end

-- Whether a button stays on the bar in combat. Food and drink don't by
-- default, since you can't eat or drink in a fight. A deleted custom button
-- (its row in the options may still ask) doesn't.
function ns.ShowsInCombat(key)
    local kind = ns.KIND_BY_KEY[key]
    if not kind then return false end
    local shown = db.combat[key]
    if shown == nil then return not (kind.eating or kind.noCombat) end
    return shown
end

function ns.SetShowsInCombat(key, value)
    db.combat[key] = value and true or false
    ns.UpdateBar()
end

function ns.SetShape(shape)
    db.shape = shape
    ns.UpdateBar()
end

function ns.SetBorder(border)
    db.border = border
    ns.UpdateBar()
end

function ns.SetFadeOutOfCombat(value)
    db.fadeOutOfCombat = value and true or false
    ns.UpdateBar()
end

-- name: a key of ns.RUNNING_OUT.
function ns.SetRunningOut(name, value)
    db[name .. "Minutes"] = math.floor(value + 0.5)
    ns.UpdateBar()
end

function ns.SetElixirGlow(value)
    db.elixirGlow = value and true or false
    ns.UpdateBar()
end

function ns.SetScrollGlow(value)
    db.scrollGlow = value and true or false
    ns.UpdateBar()
end

function ns.SetOtherBuffGlow(value)
    db.otherBuffGlow = value and true or false
    ns.UpdateBar()
end

function ns.SetCureGlow(value)
    db.cureGlow = value and true or false
    ns.UpdateBar()
end

function ns.SetCampOutdoorsOnly(value)
    db.campOutdoorsOnly = value and true or false
    ns.UpdateBar()
end

-- Hides an item from every button (hidden = true), or brings it back.
function ns.SetHidden(itemID, hidden)
    db.hidden[itemID] = hidden and true or nil
    ns.Scan()
    ns.UpdateBar()
    if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
    if ns.RefreshWindow then ns.RefreshWindow() end
end

-- The button key an item belongs on, or nil (for the options' list of
-- hidden items, which may not be in your bags).
function ns.KindOf(itemID)
    return Classify(itemID)
end

function ns.SetGlowStyle(style)
    db.glowStyle = style
    ns.UpdateBar()
    if ns.RefreshWindow then ns.RefreshWindow() end -- the preview, and dims Pulse
end

function ns.SetGlowStrength(value)
    db.glowStrength = math.floor(value + 0.5)
    ns.UpdateBar()
    if ns.RefreshWindow then ns.RefreshWindow() end
end

function ns.SetGlowPulse(value)
    db.glowPulse = value and true or false
    ns.UpdateBar()
end

function ns.SetPreferLow(key, value)
    db.preferLow[key] = value and true or nil
    ns.UpdateBar()
end

function ns.SetWeaponGlow(value)
    db.weaponGlow = value and true or false
    ns.UpdateBar()
end

function ns.SetBuffFoodGlow(value)
    db.buffFoodGlow = value and true or false
    ns.UpdateBar()
end

function ns.SetDirection(direction)
    db.direction = direction
    ns.UpdateBar()
    if ns.RefreshWindow then ns.RefreshWindow() end -- the New rows choices depend on it
end

-- The count turns red at this many or fewer; 0 is no warning.
function ns.LowStock(key)
    local kind = ns.KIND_BY_KEY[key]
    return db.lowStock[key] or (kind and kind.lowStock) or 0
end

function ns.SetLowStock(key, value)
    db.lowStock[key] = math.max(0, math.min(99, value))
    ns.UpdateBar()
    if ns.RefreshWindow then ns.RefreshWindow() end -- set from the right-click list, it's on a page too
end

-- reminder: wellFed, elixir, scroll, otherBuff or weapon (as in
-- ns.RUNNING_OUT), or cure.
function ns.SetHideWhileOn(reminder, value)
    db.hideWhileOn[reminder] = value and true or nil
    ns.UpdateBar()
end

function ns.SetLowStockWarning(value)
    db.lowStockWarning = value and true or false
    ns.UpdateBar()
    if ns.RefreshWindow then ns.RefreshWindow() end -- dims the limits
end

function ns.SetUseOnTarget(value)
    db.useOnTarget = value and true or false
    ns.UpdateBar()
end

function ns.SetPerRow(value)
    db.perRow = math.floor(value + 0.5)
    ns.UpdateBar()
end

-- Where new rows go: above or below a bar growing sideways (above by
-- default, away from the player frame), left or right of one growing up or
-- down (right by default).
function ns.RowsToward()
    local horizontal = db.direction == "LEFT" or db.direction == "RIGHT"
    local rows = db.rowsToward
    if horizontal then
        return (rows == "DOWN") and "DOWN" or "UP"
    end
    return (rows == "LEFT") and "LEFT" or "RIGHT"
end

function ns.SetRowsToward(value)
    db.rowsToward = value
    ns.UpdateBar()
end

-- The button keys in bar order, starting with the first button.
function ns.Order()
    return db.order
end

-- Opens the game's Key Bindings, where Fanny Pack has its own section.
function ns.OpenKeyBindings()
    if InCombatLockdown() then
        ns.Refuse(L["You can't change key bindings in combat."])
        return
    end
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
    else
        Print(L["Open the game menu, then Key Bindings, and look for the Fanny Pack section."])
    end
end

-- Moves a button one place towards the start (-1) or the end (1), past
-- buttons this character doesn't get.
function ns.MoveButton(key, delta)
    local order = db.order
    for i, k in ipairs(order) do
        if k == key then
            local j = i + delta
            while order[j] and not ns.IsAvailable(order[j]) do j = j + delta end
            if order[j] then
                order[i], order[j] = order[j], order[i]
                ns.UpdateBar()
            end
            return
        end
    end
end

-- Moves a button to just before another one (before = nil: to the end),
-- for dragging in the options.
function ns.MoveButtonTo(key, before)
    if key == before then return end
    local order = db.order
    for i, k in ipairs(order) do
        if k == key then
            table.remove(order, i)
            break
        end
    end
    local at = #order + 1
    for i, k in ipairs(order) do
        if k == before then
            at = i
            break
        end
    end
    table.insert(order, at, key)
    ns.UpdateBar()
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

-- Lists every consumable in your bags, its use effect and the button it
-- went on, for bug reports. out(line) adds a line to the report.
local function ShowDebug(out)
    out(L["Items you can use in your bags:"])
    local loading = false
    local seen = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID
            local classID, subClassID
            if itemID then classID, subClassID = select(6, C_Item.GetItemInfoInstant(itemID)) end
            local spell, spellID
            if itemID then spell, spellID = GetItemSpell(itemID) end
            if itemID and not spell and not C_Item.IsItemDataCachedByID(itemID) then
                C_Item.RequestLoadItemDataByID(itemID) -- its use effect isn't known until it loads
                loading = true
            end
            -- Consumables, and anything else you can use (such as camp gear),
            -- with its item class, for finding new kinds of items.
            if itemID and not seen[itemID] and (classID == CONSUMABLE or spell) then
                seen[itemID] = true
                local key = Classify(itemID)
                local amount = key and RANK_BY_AMOUNT[key] and Amount(itemID)
                local name = C_Item.GetItemInfo(itemID)
                if not name then
                    C_Item.RequestLoadItemDataByID(itemID)
                    loading = true
                end
                out(("  %s (%d, %s/%s): %s %s -> %s%s"):format(name or "?", itemID,
                    tostring(classID), tostring(subClassID),
                    tostring(spell), spellID and ("(" .. spellID .. ")") or "", key or L["no button"],
                    amount and (", " .. amount) or ""))
                if IsUsableItem and not IsUsableItem(itemID) then
                    out("      can't use: " .. (RedLines(itemID) or "no reason in its tooltip"))
                end
                -- What camp gear and unsorted items say they do.
                local line = (key == "camp" or not key) and UseLine(itemID)
                if line then out("      " .. line:gsub("%s*\n+%s*", " ")) end
            end
        end
    end
    return loading
end

-- Where the player frame's parts are, in screen pixels, for working out
-- the bar's default spot on clients whose player frame differs.
local function ShowFrameDebug(out)
    out(L["Player frame parts (left, right, top, bottom):"])
    local names = { "PlayerFrame", "PlayerFrame.portrait", "PlayerName", "PlayerFrame.healthbar",
        "PlayerFrame.manabar", "PlayerLevelText", "PetFrame", "PlayerCastingBarFrame",
        "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Player.Health", "EllesmereUIUnitFrames_Player.Power",
        "EllesmereUIUnitFrames_Player.Portrait", "EllesmereUIUnitFrames_Player.Castbar", "FannyPackBar" }
    for _, name in ipairs(names) do
        local frameName, field = name:match("^([%w_]+)%.(%w+)$")
        local region = field and _G[frameName] and _G[frameName][field] or _G[name]
        local left = region and region:GetLeft()
        if not region then
            out(("  %s: missing"):format(name))
        elseif issecretvalue and (issecretvalue(left) or issecretvalue(region:GetTop())) then
            out(("  %s: secret"):format(name)) -- the client hides its place from addons just now
        elseif not left then
            out(("  %s: not placed"):format(name))
        else
            local scale = region:GetEffectiveScale()
            local function px(value) return math.floor(value * scale + 0.5) end
            out(("  %s: %d, %d, %d, %d"):format(name, px(left), px(region:GetRight()),
                px(region:GetTop()), px(region:GetBottom())))
        end
    end
end

-- The debug report, in a window to copy from. Items the game hasn't
-- loaded yet show as "?": the report fills in again once they arrive.
function ns.ShowDebugReport(retry)
    local lines = {}
    local function out(line) lines[#lines + 1] = line end
    local version, build = GetBuildInfo()
    out(("Fanny Pack %s, game %s (%s), %s"):format(ns.VERSION or "?", tostring(version), tostring(build),
        GetLocale()))
    out(("%s level %d, profile %s"):format(select(2, UnitClass("player")) or "?", UnitLevel("player"),
        ns.GetProfileName()))
    out("")
    local loading = ShowDebug(out)
    out("")
    if ns.CustomButtons and #ns.CustomButtons() > 0 then
        out("Custom buttons (key: item IDs, first used first):")
        for _, def in ipairs(ns.CustomButtons()) do
            out(("  %s (%s): %s"):format(def.name, def.key, #def.items > 0 and table.concat(def.items, ", ") or "none"))
        end
        out("")
    end
    if ns.AuraDebug then
        ns.AuraDebug(out)
        out("")
    end
    ShowFrameDebug(out)
    ns.ShowCopyWindow(L["Fanny Pack debug report"], table.concat(lines, "\n"),
        L["Copy this into your bug report: it lists the items in your bags, which button each went on, and where your player frame is."])
    if loading and (retry or 0) < 3 then
        C_Timer.After(1, function()
            if FannyPackCopyWindow and FannyPackCopyWindow:IsShown() then ns.ShowDebugReport((retry or 0) + 1) end
        end)
    end
end

local function ShowHelp()
    Print(L["Commands:"])
    print(L["  /fannypack - open the options"])
    print(L["  /fannypack lock - lock or unlock the bar"])
    print(L["  /fannypack reset - put the bar back above your player frame"])
    print(L["  /fannypack profile [name] - show or switch this character's profile"])
    print(L["  /fannypack minimap - show or hide the minimap button"])
    print(L["  /fannypack tour - a short tour of the bar"])
    print(L["  /fannypack bind - bind keys by hovering the buttons"])
    print(L["  /fannypack debug - a report to copy into bug reports: your items and their buttons"])
end

SLASH_FANNYPACK1 = "/fannypack"
SlashCmdList.FANNYPACK = function(msg)
    local command, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" then
        ns.ToggleWindow()
    elseif command == "lock" or command == "unlock" then
        local lock = command == "lock" and not account.locked -- "lock" toggles, "unlock" unlocks
        if ns.SetLocked(lock) then
            Print(account.locked and L["The bar is locked."] or L["The bar is unlocked: drag it anywhere, right-click it to lock it."])
        end
    elseif command == "reset" then
        if ns.ResetPosition() then
            Print(L["The bar is back above your player frame."])
        end
    elseif command == "bind" or command == "kb" then
        ns.StartKeyBinding()
    elseif command == "tour" then
        ns.StartTour()
    elseif command == "debug" then
        ns.ShowDebugReport()
    elseif command == "profile" then
        if rest == "" then
            Print(L["Profile: %s. Profiles: %s"], ns.GetProfileName(), table.concat(ns.GetProfileNames(), ", "))
        elseif account.profiles[rest] then
            ns.SetProfile(rest, true)
        else
            Print(L["No profile called %s. Create one in the options (/fannypack)."], rest)
        end
    elseif command == "minimap" then
        ns.SetMinimapButton(not account.minimapButton)
        if ns.RefreshWindow then ns.RefreshWindow() end
        Print(account.minimapButton and L["Minimap button: on"] or L["Minimap button: off"])
    else
        ShowHelp()
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

-- Fills in a profile's missing settings, and brings older ones up to date.
local function FillProfile(profile)
    if profile.position and not profile.position.frame then
        profile.position = nil -- saved by a test version in another format
    end
    if profile.border == "dark" then profile.border = "none" end -- a test version's border
    for key, value in pairs(PROFILE_DEFAULTS) do
        if profile[key] == nil then profile[key] = type(value) == "table" and DeepCopy(value) or value end
    end

    -- Before per-button combat settings, one switch hid food and drink in
    -- combat; turned off, they stay shown.
    if profile.hideEatingInCombat == false then
        for _, kind in ipairs(ns.KINDS) do
            if kind.eating then profile.combat[kind.key] = true end
        end
    end
    profile.hideEatingInCombat = nil

    -- "Running out" settings, each no longer than its buff lasts. They
    -- start from the single setting of earlier test versions.
    for name, longest in pairs(ns.RUNNING_OUT) do
        local key = name .. "Minutes"
        profile[key] = math.min(profile[key] or profile.runningOutMinutes or DEFAULT_RUNNING_OUT, longest)
    end
    profile.runningOutMinutes = nil
    if profile.scrollGlow == nil then profile.scrollGlow = profile.elixirGlow end

    -- Keep the order to known buttons, each once, and add any new ones at the end.
    local known, order = {}, {}
    for _, kind in ipairs(ns.KINDS) do known[kind.key] = true end
    for _, key in ipairs(profile.order) do
        if known[key] then
            order[#order + 1] = key
            known[key] = nil
        end
    end
    for _, kind in ipairs(ns.KINDS) do
        if known[kind.key] then order[#order + 1] = kind.key end
    end
    profile.order = order

    -- Buttons new to the profile: all on, except mana buttons for classes
    -- without mana, which are off in and out of combat.
    local noMana = NO_MANA[select(2, UnitClass("player"))]
    for _, kind in ipairs(ns.KINDS) do
        if profile.buttons[kind.key] == nil then
            local on = not (noMana and MANA_KINDS[kind.key])
            profile.buttons[kind.key] = on
            if not on then profile.combat[kind.key] = false end
        end
    end

    -- The first switch used to hide a button altogether; now it's only out
    -- of combat. Buttons switched off before stay off in combat too.
    if not profile.separateCombat then
        for key, shown in pairs(profile.buttons) do
            if shown == false and profile.combat[key] == nil then profile.combat[key] = false end
        end
        profile.separateCombat = true
    end
end
ns.FillProfile = FillProfile -- also when a custom button is made (Custom.lua)

local function LoadProfile(name)
    local profile = account.profiles[name] or {}
    account.profiles[name] = profile
    FillProfile(profile)
    account.profileKeys[characterKey] = name
    db = profile
    ns.db = profile
end

local function LoadSettings()
    ns.freshInstall = FannyPackDB == nil -- no "what's new" on a first install
    FannyPackDB = FannyPackDB or {}
    account = FannyPackDB
    FannyPackCharDB = FannyPackCharDB or {}
    charDB = FannyPackCharDB

    -- Before profiles, the settings sat directly in FannyPackDB, and which
    -- buttons show was kept per character: together they become Default.
    if not account.profiles then
        local profile = {}
        for key in pairs(PROFILE_DEFAULTS) do profile[key], account[key] = account[key], nil end
        for key in pairs(PROFILE_ONLY) do profile[key], account[key] = account[key], nil end
        profile.buttons = charDB.buttons
        account.profiles = { [DEFAULT_PROFILE] = profile }
    end
    charDB.buttons = nil -- now part of the profile
    account.profileKeys = account.profileKeys or {}
    for key, value in pairs(ACCOUNT_DEFAULTS) do
        if account[key] == nil then account[key] = value end
    end

    charDB.chosen = charDB.chosen or {}
    charDB.macros = charDB.macros or {} -- [button key] = true: keep a macro for it (Macros.lua)
    charDB.macroNames = charDB.macroNames or {} -- [button key] = the name its macro was given
    characterKey = UnitName("player") .. " - " .. GetRealmName()
    ns.account, ns.charDB = account, charDB
    ns.RegisterCustomKinds() -- before the profile, which fills in their settings
    LoadProfile(account.profileKeys[characterKey] or DEFAULT_PROFILE)
end

------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------

-- Redraws everything after the active profile changed. The bar's buttons
-- can't change in combat, so they follow when it ends.
local function ProfileChanged()
    if InCombatLockdown() then
        ns.Refuse(L["The bar will change when combat ends."], true)
    end
    ns.UpdateBar()
    if ns.RefreshWindow then ns.RefreshWindow() end
    if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
end

function ns.GetProfileName()
    return account.profileKeys[characterKey]
end

function ns.GetProfileNames()
    local names = {}
    for name in pairs(account.profiles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- Other characters that use the profile.
function ns.GetProfileUsers(name)
    local users = {}
    for key, profileName in pairs(account.profileKeys) do
        if profileName == name and key ~= characterKey then users[#users + 1] = key end
    end
    table.sort(users)
    return users
end

-- announce: say so in chat (for /fannypack profile; the options window
-- shows it itself).
function ns.SetProfile(name, announce)
    if not account.profiles[name] or name == ns.GetProfileName() then return end
    LoadProfile(name)
    if announce then Print(L["Using profile %s."], name) end
    ProfileChanged()
end

-- Creates a profile as a copy of the current one and switches to it.
-- Returns false if the name is empty or already taken.
function ns.CreateProfile(name)
    name = name and strtrim(name)
    if not name or name == "" or account.profiles[name] then return false end
    account.profiles[name] = DeepCopy(db)
    ns.SetProfile(name)
    return true
end

-- Replaces the current profile's settings with a copy of another profile's.
function ns.CopyProfile(source)
    local from = account.profiles[source]
    if not from or from == db then return end
    wipe(db)
    for key, value in pairs(DeepCopy(from)) do db[key] = value end
    FillProfile(db) -- the source may not have been loaded since an update
    ProfileChanged()
end

function ns.ResetProfile()
    wipe(db)
    FillProfile(db)
    ProfileChanged()
end

-- Deletes a profile other than the active one or Default. Characters that
-- used it go back to Default.
function ns.DeleteProfile(name)
    if name == DEFAULT_PROFILE or name == ns.GetProfileName() or not account.profiles[name] then return end
    account.profiles[name] = nil
    for key, profileName in pairs(account.profileKeys) do
        if profileName == name then account.profileKeys[key] = DEFAULT_PROFILE end
    end
    if ns.RefreshWindow then ns.RefreshWindow() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then LoadSettings() end
    elseif event == "PLAYER_LOGIN" then
        if ns.InitNews then ns.InitNews() end
        ns.CreateBar()
        ns.Scan()
        ns.UpdateBar()
        if ns.InitTour then ns.InitTour() end
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("PLAYER_LEVEL_UP")
        self:RegisterEvent("SKILL_LINES_CHANGED") -- First Aid skill decides which bandages you can use
    elseif event == "PLAYER_LEVEL_UP" then
        QueueScan(1) -- UnitLevel can lag behind the event
    else
        QueueScan()
    end
end)
