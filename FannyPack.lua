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
-- when you carry none. eating: food and drink, which hide in combat unless
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
ns.KINDS = {
    { key = "healthstone", name = L["Healthstone"], icon = 5509 }, -- see HEALTHSTONES
    { key = "bandage", name = L["Bandages"], spell = 746, fallback = "First Aid", icon = 1251, self = true,
        lowStock = 5 },
    { key = "healthPotion", name = L["Health potion"], spell = 439, fallback = "Healing Potion", icon = 118,
        lowStock = 3 },
    { key = "manaPotion", name = L["Mana potion"], spell = 437, fallback = "Restore Mana", icon = 2455, lowStock = 3 },
    { key = "rune", name = L["Rune"], icon = 12662, lowStock = 2 }, -- see RUNES
    { key = "manaGem", name = L["Mana gem"], icon = 5514, class = "MAGE" }, -- see MANA_GEMS
    { key = "otherPotion", name = L["Other potion"], icon = 5634 }, -- potions that aren't health or mana, see Classify
    { key = "elixir", name = L["Elixir"], icon = 2454, buff = true }, -- elixirs and flasks, see Classify
    { key = "elixir2", name = L["Second elixir"], icon = 5997, list = "elixir", buff = true },
    { key = "scroll", name = L["Scroll"], icon = 1181, self = true, buff = true }, -- see SCROLLS
    { key = "weapon", name = L["Weapon stone or oil"], icon = 2862, slot = 16, shiftSlot = 17 }, -- see WEAPON_ITEMS
    { key = "poison", name = L["Main-hand poison"], icon = 6947, slot = 16, class = "ROGUE", lowStock = 5 }, -- see POISONS
    { key = "poison2", name = L["Off-hand poison"], icon = 2892, slot = 17, class = "ROGUE",
        list = "poison", allowSame = true, lowStock = 5 },
    { key = "food", name = L["Food"], spell = 433, fallback = "Food", icon = 117, eating = true, lowStock = 5 },
    { key = "drink", name = L["Drink"], spell = 430, fallback = "Drink", icon = 159, eating = true, lowStock = 5 },
    { key = "eatDrink", name = L["Eat & drink"], icon = 117, combo = { "food", "drink" }, eating = true, lowStock = 5 },
    -- food whose tooltip mentions Well Fed
    { key = "buffFood", name = L["Buff food"], icon = 6888, eating = true, lowStock = 2 },
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

-- Whether this character gets a button: some are for one class only.
function ns.IsAvailable(key)
    local class = ns.KIND_BY_KEY[key].class
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
    preferLow = {}, -- [button key] = true: pick the lowest-level item and smallest stack first
    fadeOutOfCombat = false, -- hide the bar out of combat until you hover over it
    useOnTarget = false, -- bandages and scrolls go on a friendly target instead of always on you
    attached = true, -- the bar moves along with the player frame
    direction = "LEFT", -- the way the bar grows from its first button: RIGHT, LEFT, DOWN or UP
    perRow = 12, -- buttons per row before the bar wraps; 12 or more keeps one row
    order = {}, -- button keys from the first button on; filled in from ns.KINDS
    lowStock = {}, -- [button key] = warn at this many or fewer; unset: the kind's default
    lowStockWarning = true, -- false: no count turns red, whatever the limits
    buttons = {}, -- [button key] = shown out of combat; filled in for the character's class
}
-- Also part of a profile, but unset by default:
--   rowsToward = where new rows go: UP or DOWN for a bar growing sideways,
--     LEFT or RIGHT for one growing up or down (see ns.RowsToward)
--   position = { frame = "player" or "screen", x, y } once the bar is
--     dragged; until then it sits above the player frame
--   wellFedMinutes, elixirMinutes, scrollMinutes, weaponMinutes = how long
--     before each runs out its reminder glows silver (0: never); see
--     ns.RUNNING_OUT
-- And from 1.1.0, carried into the first profile and then converted (see
-- FillProfile): hideEatingInCombat.
local PROFILE_ONLY = { rowsToward = true, position = true, hideEatingInCombat = true }

-- The "running out" settings, each up to how long that kind of buff lasts,
-- in minutes. Saved as <name>Minutes in the profile.
ns.RUNNING_OUT = { wellFed = 15, elixir = 60, scroll = 30, weapon = 30 }
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
    local useLabel = needsUse and (ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower()
    local found, hasUse = false, not needsUse
    text = text:lower()
    for _, line in pairs(lines) do
        line = line and line:lower()
        if line then
            if line:find(text, 1, true) then found = true end
            if useLabel and line:find(useLabel, 1, true) == 1 then hasUse = true end
        end
    end
    if not hasUse then return nil end
    return found
end

local itemKinds = {} -- [itemID] = kind key, or false (cached once known)
local conjured = {}  -- [itemID] = true/false (cached once known)
local undecided = false -- the last scan met items it couldn't sort yet

-- [itemID] = whether you can use it, from the last check out of combat.
-- In combat the game calls food and drink unusable, which would turn
-- their buttons red after the fight.
local usableOutOfCombat = {}

-- The kind of button an item belongs on, or nil. Items the game hasn't
-- loaded yet are requested and get sorted on the next scan.
local function Classify(itemID)
    local cached = itemKinds[itemID]
    if cached ~= nil then return cached or nil end

    local classID, subClassID = select(6, C_Item.GetItemInfoInstant(itemID))
    if classID ~= CONSUMABLE then
        itemKinds[itemID] = false
        return nil
    end
    local listed = (HEALTHSTONES[itemID] and "healthstone") or (WEAPON_ITEMS[itemID] and "weapon")
        or (POISONS[itemID] and "poison") or (SCROLLS[itemID] and "scroll")
        or (RUNES[itemID] and "rune") or (MANA_GEMS[itemID] and "manaGem")
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

    if not kindBySpell then BuildSpellMap() end
    local key = kindBySpell[spell] or false
    if key == false then
        -- Not one of the use effects above: go by the item's type and name.
        -- The names catch healthstones, stones, oils and poisons newer than
        -- the lists, and elixirs and flasks the game files as plain
        -- consumables. Elixirs go first, for Elixir of Poison Resistance.
        local name = (C_Item.GetItemInfo(itemID) or ""):lower()
        if name:find(L["healthstone"], 1, true) then
            key = "healthstone"
        elseif ELIXIR_SUBCLASSES[subClassID] or name:find(L["elixir"], 1, true) or name:find(L["flask"], 1, true) then
            key = "elixir"
        elseif subClassID == SCROLL_SUBCLASS or name:find(L["scroll of"], 1, true) then
            key = "scroll"
        elseif name:find(L["sharpening stone"], 1, true) or name:find(L["weightstone"], 1, true)
            or name:find(L["wizard oil"], 1, true) or name:find(L["mana oil"], 1, true) then
            key = "weapon"
        elseif name:find(L["poison"], 1, true) then
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
-- itemLevel, conjured, usable }, best first.
ns.items = {}
for _, kind in ipairs(ns.KINDS) do
    if not kind.list and not kind.combo then ns.items[kind.key] = {} end
end

-- The items a button picks from: its own, or the button's it shares.
local NO_ITEMS = {} -- for Eat & drink, which has no items of its own

function ns.ListFor(key)
    local kind = ns.KIND_BY_KEY[key]
    if kind.combo then return NO_ITEMS end
    return ns.items[kind.list or key]
end

-- For "use up low-level items first": conjured ones (they vanish anyway),
-- then the lowest level, then the smallest stack.
local function Lower(a, b)
    if a.conjured ~= b.conjured then return a.conjured end
    if a.level ~= b.level then return a.level < b.level end
    if a.count ~= b.count then return a.count < b.count end
    return a.itemID < b.itemID
end

-- Best first: items you can use, then the highest required level, then
-- conjured items (they vanish anyway), then the highest item level.
local function Better(a, b)
    if a.usable ~= b.usable then return a.usable end
    if a.level ~= b.level then return a.level > b.level end
    if a.conjured ~= b.conjured then return a.conjured end
    if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
    return a.itemID < b.itemID
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
                    usableOutOfCombat[itemID] = usable
                end
            end
            table.insert(ns.items[key], {
                itemID = itemID,
                count = GetItemCount(itemID),
                name = name,
                quality = quality,
                icon = icon,
                level = minLevel or 0,
                itemLevel = itemLevel or 0,
                conjured = IsConjured(itemID),
                usable = usable,
            })
        end
    end
    for _, list in pairs(ns.items) do table.sort(list, Better) end

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

-- The item picked by hand for a button, if it's in your bags.
local function HandPicked(key, list)
    local chosen = charDB and charDB.chosen[key]
    if not chosen then return nil end
    for _, entry in ipairs(list) do
        if entry.itemID == chosen then return entry end
    end
end

-- The best item other than skip, or with "use up low-level items first" on,
-- the lowest usable one.
local function AutoPick(key, list, skip)
    if db and db.preferLow[key] then
        local pick
        for _, entry in ipairs(list) do
            if entry ~= skip and entry.usable and (not pick or Lower(entry, pick)) then pick = entry end
        end
        if pick then return pick end
    end
    for _, entry in ipairs(list) do
        if entry ~= skip then return entry end
    end
end

function ns.ItemFor(key)
    local kind = ns.KIND_BY_KEY[key]
    if kind.combo then -- something to eat or drink, if either button has it
        return ns.ItemFor(kind.combo[1]) or ns.ItemFor(kind.combo[2])
    end
    local list = ns.ListFor(key)
    local picked = HandPicked(key, list)

    if kind.list then
        -- A second button (second elixir, off-hand poison) never uses the
        -- first one's item, so with one kind of elixir there's no second
        -- elixir. Poisons may share, when picked so or there's no other.
        local first = ns.ItemFor(kind.list)
        if picked and (picked ~= first or kind.allowSame) then return picked end
        return AutoPick(key, list, first) or (kind.allowSame and first or nil)
    end

    if picked then return picked end
    -- What you picked by hand for the second button beats this button's
    -- automatic pick, unless there's nothing else.
    local reserved = SECOND[key] and HandPicked(SECOND[key], list)
    return AutoPick(key, list, reserved) or reserved
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
        Print(L["The button will switch to it when combat ends."])
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
-- default, since you can't eat or drink in a fight.
function ns.ShowsInCombat(key)
    local shown = db.combat[key]
    if shown == nil then return not ns.KIND_BY_KEY[key].eating end
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
    return db.lowStock[key] or ns.KIND_BY_KEY[key].lowStock or 0
end

function ns.SetLowStock(key, value)
    db.lowStock[key] = math.max(0, math.min(99, value))
    ns.UpdateBar()
    if ns.RefreshWindow then ns.RefreshWindow() end -- set from the right-click list, it's on a page too
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
        Print(L["You can't change key bindings in combat."])
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

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

-- Lists every consumable in your bags, its use effect and the button it
-- went on, for bug reports.
local function ShowDebug()
    Print(L["Consumables in your bags:"])
    local seen = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID
            if itemID and not seen[itemID] and select(6, C_Item.GetItemInfoInstant(itemID)) == CONSUMABLE then
                seen[itemID] = true
                local key = Classify(itemID)
                local spell, spellID = GetItemSpell(itemID)
                print(("  %s (%d): %s %s -> %s"):format(info.hyperlink or itemID, itemID,
                    tostring(spell), spellID and ("(" .. spellID .. ")") or "", key or L["no button"]))
            end
        end
    end
end

-- Where the player frame's parts are, in screen pixels, for working out
-- the bar's default spot on clients whose player frame differs.
local function ShowFrameDebug()
    Print(L["Player frame parts (left, right, top, bottom):"])
    local names = { "PlayerFrame", "PlayerFrame.portrait", "PlayerName", "PlayerFrame.healthbar",
        "PlayerFrame.manabar", "PlayerLevelText", "PetFrame", "PlayerCastingBarFrame", "FannyPackBar" }
    for _, name in ipairs(names) do
        local frameName, field = name:match("^(%w+)%.(%w+)$")
        local region = field and _G[frameName] and _G[frameName][field] or _G[name]
        local left = region and region:GetLeft()
        if not region then
            print(("  %s: missing"):format(name))
        elseif issecretvalue and (issecretvalue(left) or issecretvalue(region:GetTop())) then
            print(("  %s: secret"):format(name)) -- the client hides its place from addons just now
        elseif not left then
            print(("  %s: not placed"):format(name))
        else
            local scale = region:GetEffectiveScale()
            local function px(value) return math.floor(value * scale + 0.5) end
            print(("  %s: %d, %d, %d, %d"):format(name, px(left), px(region:GetRight()),
                px(region:GetTop()), px(region:GetBottom())))
        end
    end
end

local function ShowHelp()
    Print(L["Commands:"])
    print(L["  /fannypack - open the options"])
    print(L["  /fannypack lock - lock or unlock the bar"])
    print(L["  /fannypack reset - put the bar back above your player frame"])
    print(L["  /fannypack profile [name] - show or switch this character's profile"])
    print(L["  /fannypack minimap - show or hide the minimap button"])
    print(L["  /fannypack debug - list the consumables in your bags and their buttons"])
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
    elseif command == "debug" then
        ShowDebug()
        ShowFrameDebug()
    elseif command == "profile" then
        if rest == "" then
            Print(L["Profile: %s. Profiles: %s"], ns.GetProfileName(), table.concat(ns.GetProfileNames(), ", "))
        elseif account.profiles[rest] then
            ns.SetProfile(rest)
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

local function LoadProfile(name)
    local profile = account.profiles[name] or {}
    account.profiles[name] = profile
    FillProfile(profile)
    account.profileKeys[characterKey] = name
    db = profile
    ns.db = profile
end

local function LoadSettings()
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
    characterKey = UnitName("player") .. " - " .. GetRealmName()
    LoadProfile(account.profileKeys[characterKey] or DEFAULT_PROFILE)
    ns.account, ns.charDB = account, charDB
end

------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------

-- Redraws everything after the active profile changed. The bar's buttons
-- can't change in combat, so they follow when it ends.
local function ProfileChanged()
    if InCombatLockdown() then
        Print(L["The bar will change when combat ends."])
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

function ns.SetProfile(name)
    if not account.profiles[name] or name == ns.GetProfileName() then return end
    LoadProfile(name)
    Print(L["Using profile %s."], name)
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
    Print(L["Copied profile %s into %s."], source, ns.GetProfileName())
    ProfileChanged()
end

function ns.ResetProfile()
    wipe(db)
    FillProfile(db)
    Print(L["Profile %s was reset."], ns.GetProfileName())
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
    Print(L["Deleted profile %s."], name)
    if ns.RefreshWindow then ns.RefreshWindow() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then LoadSettings() end
    elseif event == "PLAYER_LOGIN" then
        ns.CreateBar()
        ns.Scan()
        ns.UpdateBar()
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
