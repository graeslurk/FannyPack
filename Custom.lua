-- Custom buttons: buttons you make yourself, each with a list of items you
-- choose (a raid potion, Holy Water, a trinket, a fishing pole...). A custom
-- button uses the first item in its list that you carry, unless you pick
-- another in its right-click list. An item on a custom button leaves its
-- usual button, so it never shows twice.
--
-- The buttons themselves are shared by all your characters (FannyPackDB.custom);
-- whether each one shows, where it sits and the rest are part of a profile,
-- like every other button's. Their keys ("custom1", "custom2"...) are never
-- used again after a button is deleted, so a key binding or a setting left
-- behind somewhere can't land on a new button.

local ADDON_NAME, ns = ...
local L = ns.L

local GetItemSpell = C_Item.GetItemSpell or GetItemSpell
local IsEquippableItem = C_Item.IsEquippableItem or IsEquippableItem
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local QUESTION_MARK = 134400 -- the icon of a button with no items yet

-- [itemID] = the key of the custom button it's on (see Classify).
ns.customItems = {}

-- FannyPackDB.custom: buttons = { { key, name, items = { itemID, ... }, glow }, ... }
-- in the order they were made; next = the number in the next button's key.
local function Store()
    local account = ns.account
    account.custom = account.custom or { buttons = {}, next = 1 }
    return account.custom
end

-- The custom buttons, in the order they were made.
function ns.CustomButtons()
    return Store().buttons
end

local function Definition(key)
    for i, def in ipairs(Store().buttons) do
        if def.key == key then return def, i end
    end
end

-- A kind (see ns.KINDS) follows its definition: the name, and the first
-- item's icon while you carry none.
local function UpdateKind(kind, def)
    kind.name = def.name
    kind.icon = def.items[1]
    kind.texture = not def.items[1] and QUESTION_MARK or nil
    kind.buff = def.glow and true or nil -- glows while the item's buff isn't on you (Bar.lua)
    _G["BINDING_NAME_CLICK " .. ns.ButtonName(kind.key) .. ":LeftButton"] = def.name
end

local function AddKind(def)
    local kind = { key = def.key, custom = true, items = def.items }
    UpdateKind(kind, def)
    ns.KINDS[#ns.KINDS + 1] = kind
    ns.KIND_BY_KEY[def.key] = kind
    ns.items[def.key] = {}
    ns.hiddenItems[def.key] = {}
    return kind
end

local function RebuildItemMap()
    wipe(ns.customItems)
    for _, def in ipairs(Store().buttons) do
        for _, itemID in ipairs(def.items) do ns.customItems[itemID] = def.key end
    end
end

-- At load, before the profile is filled in: the custom buttons join the
-- built-in ones at the end of ns.KINDS.
function ns.RegisterCustomKinds()
    for _, def in ipairs(Store().buttons) do AddKind(def) end
    RebuildItemMap()
end

-- After any change: the items move between buttons, and everything that
-- shows them catches up.
local function Changed()
    RebuildItemMap()
    ns.Scan()
    ns.UpdateBar()
    if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
    if ns.RefreshWindow then ns.RefreshWindow() end
end

local function RemoveValue(list, value)
    for i = #list, 1, -1 do
        if list[i] == value then table.remove(list, i) end
    end
end

-- Makes a new custom button, at the end of the bar and switched on in the
-- active profile. Returns its key, or nil in combat (the bar's buttons
-- can't be made then).
function ns.CreateCustomButton(name)
    if InCombatLockdown() then
        ns.Refuse(L["You can't add buttons in combat."])
        return nil
    end
    local store = Store()
    name = strtrim(name or "")
    if name == "" then name = L["Custom %d"]:format(store.next) end
    local def = { key = "custom" .. store.next, name = name, items = {} }
    store.next = store.next + 1
    store.buttons[#store.buttons + 1] = def
    local kind = AddKind(def)
    ns.FillProfile(ns.db) -- adds it to the order, switched on
    ns.AddBarButton(kind)
    Changed()
    return def.key
end

-- Deletes a custom button: from the bar, every profile, this character's
-- macros and the key bindings. Not in combat.
function ns.DeleteCustomButton(key)
    local def, index = Definition(key)
    if not def then return false end
    if InCombatLockdown() then
        ns.Refuse(L["You can't delete buttons in combat."])
        return false
    end
    -- This character's macro for it goes now; other characters' at their
    -- next login (ns.UpdateMacros).
    if ns.charDB.macros[key] then ns.SetMacro(key, false) end
    local store = Store()
    local command = "CLICK " .. ns.ButtonName(key) .. ":LeftButton"
    local unbound = false
    for _, bound in ipairs({ GetBindingKey(command) }) do
        SetBinding(bound, nil)
        unbound = true
    end
    if unbound and SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
    ns.RemoveBarButton(key)

    table.remove(store.buttons, index)
    for i, kind in ipairs(ns.KINDS) do
        if kind.key == key then
            table.remove(ns.KINDS, i)
            break
        end
    end
    ns.KIND_BY_KEY[key] = nil
    ns.items[key], ns.hiddenItems[key] = nil, nil
    _G["BINDING_NAME_" .. command] = nil
    for _, profile in pairs(ns.account.profiles) do
        if profile.order then RemoveValue(profile.order, key) end
        for _, field in ipairs({ "buttons", "combat", "lowStock", "preferLow" }) do
            if profile[field] then profile[field][key] = nil end
        end
    end
    ns.charDB.chosen[key] = nil
    Changed()
    return true
end

-- Renames a custom button, and its macro if it has one. Not in combat (the
-- macro can't change then). Returns true if the name changed.
function ns.RenameCustomButton(key, name)
    local def = Definition(key)
    name = strtrim(name or "")
    if not def or name == "" or name == def.name then return false end
    if InCombatLockdown() then
        ns.Refuse(L["You can't rename buttons in combat."])
        return false
    end
    local oldMacro = ns.MacroName(key)
    def.name = name
    UpdateKind(ns.KIND_BY_KEY[key], def)
    if ns.charDB.macros[key] then ns.RenameMacro(oldMacro, key) end
    Changed()
    return true
end

-- Whether a custom button glows while its item's buff isn't on you, like
-- Other buffs (and silver when it's running out, as set for them).
function ns.SetCustomGlow(key, on)
    local def = Definition(key)
    if not def then return end
    def.glow = on and true or nil
    UpdateKind(ns.KIND_BY_KEY[key], def)
    ns.UpdateBar()
end

-- Adds an item at the end of a custom button's list. An item is on one
-- custom button at most: one from another custom button moves here.
-- Returns true and the name of the button it came from (if any), or false
-- and why not.
function ns.AddCustomItem(key, itemID)
    local def = Definition(key)
    itemID = tonumber(itemID)
    if not def then return false end
    if not itemID or not C_Item.GetItemInfoInstant(itemID) then
        return false, L["Couldn't find that item. Drag it here from your bags, or Shift-click it."]
    end
    for _, listed in ipairs(def.items) do
        if listed == itemID then return false, L["It's already on this button."] end
    end
    -- Anything you can use, or put on (a trinket, a fishing pole, a weapon to swap to).
    if C_Item.IsItemDataCachedByID(itemID) and not GetItemSpell(itemID)
        and not (IsEquippableItem and IsEquippableItem(itemID)) then
        return false, L["%s can't be used."]:format(C_Item.GetItemInfo(itemID) or ("#" .. itemID))
    end
    C_Item.RequestLoadItemDataByID(itemID) -- named in the options once it arrives

    local from = ns.customItems[itemID] and Definition(ns.customItems[itemID])
    if from then
        RemoveValue(from.items, itemID)
        UpdateKind(ns.KIND_BY_KEY[from.key], from)
    end
    def.items[#def.items + 1] = itemID
    UpdateKind(ns.KIND_BY_KEY[key], def)
    Changed()
    return true, from and from.name
end

function ns.RemoveCustomItem(key, itemID)
    local def = Definition(key)
    if not def then return end
    RemoveValue(def.items, itemID)
    UpdateKind(ns.KIND_BY_KEY[key], def)
    if ns.charDB.chosen[key] == itemID then ns.charDB.chosen[key] = nil end
    Changed()
end

-- Moves an item one place up (-1) or down (1) its button's list.
function ns.MoveCustomItem(key, itemID, delta)
    local def = Definition(key)
    if not def then return end
    for i, listed in ipairs(def.items) do
        if listed == itemID then
            local j = i + delta
            if def.items[j] then
                def.items[i], def.items[j] = def.items[j], def.items[i]
                UpdateKind(ns.KIND_BY_KEY[key], def)
                Changed()
            end
            return
        end
    end
end

-- Moves an item to just before another one in its button's list (before =
-- nil: to the end), for dragging in the options. Returns true if it moved.
function ns.MoveCustomItemTo(key, itemID, before)
    local def = Definition(key)
    if not def or itemID == before then return false end
    local from
    for i, listed in ipairs(def.items) do
        if listed == itemID then from = i end
    end
    if not from then return false end
    table.remove(def.items, from)
    local at = #def.items + 1
    for i, listed in ipairs(def.items) do
        if listed == before then
            at = i
            break
        end
    end
    table.insert(def.items, at, itemID)
    if at == from then return false end -- dropped where it was
    UpdateKind(ns.KIND_BY_KEY[key], def)
    Changed()
    return true
end

-- The item typed into the options: an item link (Shift-click one), an item
-- ID, or the name of an item in your bags or one the game has seen this
-- session. nil if none matches.
function ns.FindItem(text)
    text = strtrim(text or "")
    if text == "" then return nil end
    local id = text:match("item:(%d+)") or text:match("^#?(%d+)$")
    if id then return tonumber(id) end
    local wanted = ns.Lower(text)
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local name = info and C_Item.GetItemInfo(info.itemID)
            if name and ns.Lower(name) == wanted then return info.itemID end
        end
    end
    local _, link = C_Item.GetItemInfo(text)
    return link and tonumber(link:match("item:(%d+)"))
end
