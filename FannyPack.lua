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
-- when you carry none. eating: food and drink, which hide in combat.
-- list: the button shares another button's items (the second elixir takes
-- the best one the first doesn't use); allowSame: it may use the same one
-- when there's no other. slot: the item goes on the weapon in that slot
-- (16 main hand, 17 off-hand), shiftSlot with Shift held. class: only that
-- class gets the button. The order here is the default order on the bar.
ns.KINDS = {
    { key = "healthstone", name = L["Healthstone"], icon = 5509 }, -- see HEALTHSTONES
    { key = "bandage", name = L["Bandages"], spell = 746, fallback = "First Aid", icon = 1251 },
    { key = "healthPotion", name = L["Health potion"], spell = 439, fallback = "Healing Potion", icon = 118 },
    { key = "manaPotion", name = L["Mana potion"], spell = 437, fallback = "Restore Mana", icon = 2455 },
    { key = "elixir", name = L["Elixir"], icon = 2454 }, -- elixirs and flasks, see Classify
    { key = "elixir2", name = L["Second elixir"], icon = 5997, list = "elixir" },
    { key = "weapon", name = L["Weapon stone or oil"], icon = 2862, slot = 16, shiftSlot = 17 }, -- see WEAPON_ITEMS
    { key = "poison", name = L["Main-hand poison"], icon = 6947, slot = 16, class = "ROGUE" }, -- see POISONS
    { key = "poison2", name = L["Off-hand poison"], icon = 2892, slot = 17, class = "ROGUE",
        list = "poison", allowSame = true },
    { key = "food", name = L["Food"], spell = 433, fallback = "Food", icon = 117, eating = true },
    { key = "drink", name = L["Drink"], spell = 430, fallback = "Drink", icon = 159, eating = true },
    { key = "buffFood", name = L["Buff food"], icon = 6888, eating = true }, -- food whose tooltip mentions Well Fed
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

local DEFAULTS = {
    locked = true,
    buttonSize = 26,
    spacing = 2,
    hideEmpty = true, -- false: empty buttons are faded instead
    hideEatingInCombat = true, -- hide food, buff food and drink in combat
    shape = "square", -- square, rounded or round
    border = "none", -- none, silver or gold
    buffFoodGlow = true, -- the buff food button glows while you're not Well Fed
    weaponGlow = true, -- the weapon stone or oil button glows while a weapon has none on it
    fadeOutOfCombat = false, -- hide the bar out of combat until you hover over it
    attached = true, -- the bar moves along with the player frame
    direction = "LEFT", -- the way the bar grows from its first button: RIGHT, LEFT, DOWN or UP
    perRow = 12, -- buttons per row before the bar wraps; 12 or more keeps one row
    -- rowsToward = where new rows go: UP or DOWN for a bar growing sideways,
    -- LEFT or RIGHT for one growing up or down (see ns.RowsToward)
    order = {}, -- button keys from the first button on; filled in from ns.KINDS
    minimapButton = true,
    minimapAngle = 200, -- degrees around the minimap, 0 = right, 90 = top
    -- position = { frame = "player" or "screen", x, y } once the bar is
    -- dragged; until then it sits above the player frame
}

-- Classes without mana don't get the drink and mana potion buttons by default.
local NO_MANA = { WARRIOR = true, ROGUE = true }

local db, charDB -- FannyPackDB (account), FannyPackCharDB (this character)

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
        or (POISONS[itemID] and "poison")
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
        elseif name:find(L["sharpening stone"], 1, true) or name:find(L["weightstone"], 1, true)
            or name:find(L["wizard oil"], 1, true) or name:find(L["mana oil"], 1, true) then
            key = "weapon"
        elseif name:find(L["poison"], 1, true) then
            key = "poison"
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
    if not kind.list then ns.items[kind.key] = {} end
end

-- The items a button picks from: its own, or the button's it shares.
function ns.ListFor(key)
    return ns.items[ns.KIND_BY_KEY[key].list or key]
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
function ns.ItemFor(key)
    local list = ns.ListFor(key)
    local chosen = charDB and charDB.chosen[key]
    if chosen then
        for _, entry in ipairs(list) do
            if entry.itemID == chosen then return entry end
        end
    end
    -- A button sharing another's items skips the one that button uses,
    -- unless it may use the same one and there's nothing else.
    local kind = ns.KIND_BY_KEY[key]
    local taken = kind.list and ns.ItemFor(kind.list)
    for _, entry in ipairs(list) do
        if entry ~= taken then return entry end
    end
    if kind.allowSame then return taken end
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
    charDB.buttons[key] = show and true or false
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

function ns.SetHideEatingInCombat(value)
    db.hideEatingInCombat = value and true or false
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
    print(L["  /fannypack minimap - show or hide the minimap button"])
    print(L["  /fannypack debug - list the consumables in your bags and their buttons"])
end

SLASH_FANNYPACK1 = "/fannypack"
SlashCmdList.FANNYPACK = function(msg)
    local command = (msg or ""):lower():match("^%s*(%S*)")
    if command == "" then
        ns.ToggleWindow()
    elseif command == "lock" or command == "unlock" then
        local lock = command == "lock" and not db.locked -- "lock" toggles, "unlock" unlocks
        if ns.SetLocked(lock) then
            Print(db.locked and L["The bar is locked."] or L["The bar is unlocked: drag it anywhere, right-click it to lock it."])
        end
    elseif command == "reset" then
        if ns.ResetPosition() then
            Print(L["The bar is back above your player frame."])
        end
    elseif command == "debug" then
        ShowDebug()
        ShowFrameDebug()
    elseif command == "minimap" then
        ns.SetMinimapButton(not db.minimapButton)
        if ns.RefreshWindow then ns.RefreshWindow() end
        Print(db.minimapButton and L["Minimap button: on"] or L["Minimap button: off"])
    else
        ShowHelp()
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local function LoadSettings()
    FannyPackDB = FannyPackDB or {}
    db = FannyPackDB
    if db.position and not db.position.frame then
        db.position = nil -- saved by a test version in another format
    end
    if db.border == "dark" then db.border = "none" end -- a test version's border
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end

    -- Keep the order to known buttons, each once, and add any new ones at the end.
    local known, order = {}, {}
    for _, kind in ipairs(ns.KINDS) do known[kind.key] = true end
    for _, key in ipairs(db.order) do
        if known[key] then
            order[#order + 1] = key
            known[key] = nil
        end
    end
    for _, kind in ipairs(ns.KINDS) do
        if known[kind.key] then order[#order + 1] = kind.key end
    end
    db.order = order

    FannyPackCharDB = FannyPackCharDB or {}
    charDB = FannyPackCharDB
    charDB.chosen = charDB.chosen or {}
    charDB.buttons = charDB.buttons or {}
    local noMana = NO_MANA[select(2, UnitClass("player"))]
    for _, kind in ipairs(ns.KINDS) do
        if charDB.buttons[kind.key] == nil then
            charDB.buttons[kind.key] = not (noMana and (kind.key == "drink" or kind.key == "manaPotion"))
        end
    end

    ns.db, ns.charDB = db, charDB
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
