-- Macros for your own action bars: for each button you pick (Items page),
-- Fanny Pack keeps a character macro that always uses the item that button
-- would use, like the Buffet addon. Macros can't be changed in combat, so
-- they follow along when the bar does (ns.UpdateBar, out of combat).

local ADDON_NAME, ns = ...
local L = ns.L

local QUESTION_MARK = 134400 -- the icon while there's no item; #showtooltip shows the item's
local MAX_NAME = 16 -- the game's limit for a macro name

-- The macro's name: "FP " and the button's name, in the game's language.
function ns.MacroName(key)
    return ("FP " .. ns.KIND_BY_KEY[key].name):sub(1, MAX_NAME)
end

-- The macro text for a button: what a click on the button does.
local function MacroBody(key)
    local kind = ns.KIND_BY_KEY[key]
    local lines = { "#showtooltip" }
    if kind.combo then
        for _, part in ipairs(kind.combo) do
            local entry = ns.ItemFor(part)
            if entry then lines[#lines + 1] = "/use item:" .. entry.itemID end
        end
        return table.concat(lines, "\n")
    end
    local entry = ns.ItemFor(key)
    if not entry then return lines[1] end
    local item = "item:" .. entry.itemID
    if kind.slot then
        -- Stones, oils and poisons go on the weapon (Shift: the off-hand,
        -- with a stone of its own if it's another kind of weapon).
        local off = kind.shiftSlot and ns.OffHandItemFor(key)
        if off and off ~= entry then
            lines[#lines + 1] = "/use [mod:shift] item:" .. off.itemID .. "; " .. item
        else
            lines[#lines + 1] = "/use " .. item
        end
        lines[#lines + 1] = kind.shiftSlot and ("/use [mod:shift] " .. kind.shiftSlot .. "; " .. kind.slot)
            or ("/use " .. kind.slot)
    elseif kind.self then
        lines[#lines + 1] = ns.db.useOnTarget and ("/use [@target,help,nodead][@player] " .. item)
            or ("/use [@player] " .. item)
    else
        lines[#lines + 1] = "/use " .. item
    end
    return table.concat(lines, "\n")
end

local written = {} -- [macro name] = the text last written, so unchanged macros aren't rewritten
local warnedFull = false

-- Creates or updates this character's Fanny Pack macros. Not in combat.
-- charDB.macroNames remembers the name each macro was given, so a custom
-- button renamed or deleted while playing another character takes this
-- character's macro along, or deletes it, instead of leaving it behind.
function ns.UpdateMacros()
    if InCombatLockdown() or not ns.charDB or not CreateMacro then return end
    local names = ns.charDB.macroNames
    for key in pairs(ns.charDB.macros) do
        local had = names[key]
        if not ns.KIND_BY_KEY[key] then
            -- Only custom buttons go away. (Clearing a field while looping is allowed.)
            if key:find("^custom%d+$") then
                local index = had and GetMacroIndexByName(had) or 0
                if index > 0 then DeleteMacro(index) end
                if had then written[had] = nil end
                ns.charDB.macros[key], names[key] = nil, nil
            end
        else
            local name, body = ns.MacroName(key), MacroBody(key)
            local index = GetMacroIndexByName(name)
            if index == 0 and had and had ~= name then
                -- Renamed elsewhere: the old macro takes the new name, and
                -- stays where it sits on your action bars.
                index = GetMacroIndexByName(had)
                if index > 0 then
                    EditMacro(index, name, QUESTION_MARK, body)
                    written[had], written[name] = nil, body
                end
            end
            if index == 0 then
                -- Just try: the limit the game reports doesn't always match
                -- what it allows. It refuses (an error) when the slots are full.
                local ok, created = pcall(CreateMacro, name, QUESTION_MARK, body, true)
                if ok and created and created > 0 then
                    written[name] = body
                    names[key] = name
                elseif not warnedFull then
                    warnedFull = true
                    local _, perCharacter = GetNumMacros()
                    ns.Print(L["The game wouldn't make the macro %s (this character has %d macros). Delete one in /macro and try again."],
                        name, perCharacter or 0)
                end
            else
                if written[name] ~= body then
                    EditMacro(index, name, QUESTION_MARK, body)
                    written[name] = body
                end
                names[key] = name
            end
        end
    end
end

-- Adds a button's macro (on = true) or removes it again.
function ns.SetMacro(key, on)
    warnedFull = false
    if InCombatLockdown() then
        ns.Refuse(L["Macros can't be changed in combat."])
        return
    end
    local name = ns.MacroName(key)
    if on then
        ns.charDB.macros[key] = true
        ns.UpdateMacros()
    else
        ns.charDB.macros[key] = nil
        ns.charDB.macroNames[key] = nil
        local index = GetMacroIndexByName(name)
        if index > 0 then DeleteMacro(index) end
        written[name] = nil
    end
    if ns.RefreshWindow then ns.RefreshWindow() end
end

-- A custom button was renamed (Custom.lua): its macro takes the new name,
-- and stays wherever it sits on your action bars. Not in combat.
function ns.RenameMacro(oldName, key)
    written[oldName] = nil
    if InCombatLockdown() or not EditMacro then return end
    local index = GetMacroIndexByName(oldName)
    if index > 0 then
        local name, body = ns.MacroName(key), MacroBody(key)
        EditMacro(index, name, QUESTION_MARK, body)
        written[name] = body
        ns.charDB.macroNames[key] = name
    end
end

-- Puts a button's macro on the cursor, to drop on an action bar.
function ns.PickupMacro(key)
    if InCombatLockdown() then return end
    ns.UpdateMacros()
    local index = GetMacroIndexByName(ns.MacroName(key))
    if index > 0 then PickupMacro(index) end
end
