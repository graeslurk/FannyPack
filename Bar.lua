-- The bar: one button per kind of consumable. Left-click uses the item,
-- right-click opens a list to pick another one.
--
-- The buttons are secure, so they work in combat, but the game doesn't let
-- addons change them during a fight: which item they use, showing, hiding,
-- sizing or moving them. Those changes wait until combat ends. Counts,
-- cooldowns and fading still update mid-fight.
--
-- The one exception is LAYOUT below: a snippet the game itself runs when
-- combat starts and ends, which hides food and drink and closes up the gaps.

local ADDON_NAME, ns = ...
local L = ns.L
local C = ns.C

local GetItemCount = C_Item.GetItemCount or GetItemCount
local GetItemCooldown = C_Container.GetItemCooldown or GetItemCooldown
local GetItemSpell = C_Item.GetItemSpell or GetItemSpell
local RECENTLY_BANDAGED = 11196 -- the debuff that stops you bandaging again for a minute
local WELL_FED = 19705 -- one of the many Well Fed buffs; they all share the name
local EATING = 433 -- the "Food" buff you have while eating

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

-- Button looks: the texture that cuts each shape (a square needs none),
-- and each border's colour and width in screen pixels.
local SHAPE_MASKS = { rounded = "mask-rounded", round = "mask-round" }
local BORDERS = {
    silver = { color = { 0.66, 0.67, 0.71, 1 }, pixels = 1 },
    gold = { color = { 0.94, 0.69, 0.24, 1 }, pixels = 1 },
}
-- Reminder glows: gold when the buff (or the stone on the weapon) is
-- missing, a calmer silver when it's about to run out (the last few
-- minutes, as set on the Reminders page). They're painted over the ground
-- rather than added to it, so they look the same on dark and light ground;
-- strength scales how strongly each shows.
local GLOW_MISSING = { 0.94, 0.69, 0.24, strength = 1 } -- the gold of the logo's ring
local GLOW_EXPIRING = { 0.82, 0.86, 0.94, strength = 0.33 }

local LOW_STOCK_COLOR = { 1, 0.3, 0.3 }

local NUMBER_FONT = NumberFontNormal and NumberFontNormal:GetFont() or STANDARD_TEXT_FONT
local countdownFont = CreateFont("FannyPackCountdownFont") -- cooldown numbers, sized in ApplyStyle

local ROW_HEIGHT = 26 -- rows in the item list

local bar, mover, picker
local flyout -- the camp gear row (see "The camp gear row")
local buttons = {} -- [kind key] = button
local pending = false -- a change to the buttons is waiting for combat to end
local createAfterCombat = false
local moving = false
local inCombat = false -- from the combat events, which come just before the lockdown starts
local stateDriver = false -- the combat snippet is hooked up

-- Places the shown buttons one after another from the bar's first-button
-- corner, in order, wrapping to a new row after fp-perrow buttons. Each
-- button shows in combat (fp-incombat), out of it (fp-outofcombat) or both. Runs in the game's secure environment,
-- so it works in combat too. The bar keeps the size of its out-of-combat
-- buttons; the first button stays put and the rest close in on it.
local LAYOUT = [[
    local inCombat = self:GetAttribute("state-combat") == "combat"
    local step = self:GetAttribute("fp-size") + self:GetAttribute("fp-spacing")
    local perRow = self:GetAttribute("fp-perrow")
    local horizontal = self:GetAttribute("fp-horizontal")
    local corner = self:GetAttribute("fp-corner")
    local xSign, ySign = self:GetAttribute("fp-xsign"), self:GetAttribute("fp-ysign")
    local n = 0
    for i = 1, self:GetAttribute("fp-count") do
        local button = self:GetFrameRef("button" .. i)
        local shown = button:GetAttribute(inCombat and "fp-incombat" or "fp-outofcombat")
        if button:GetAttribute("fp-enabled") and shown then
            local column = n % perRow
            local along, across = column * step, (n - column) / perRow * step
            local x, y = across, along
            if horizontal then x, y = along, across end
            button:ClearAllPoints()
            button:SetPoint(corner, self, corner, xSign * x, ySign * y)
            button:Show()
            n = n + 1
        else
            button:Hide()
        end
    end
]]

-- The bar's layout: whether it runs sideways, which way new rows go, and
-- the corner its first button sits in ("BOTTOMRIGHT" for a bar growing
-- left with new rows above it).
local function Shape()
    local direction = ns.db.direction
    local horizontal = direction == "LEFT" or direction == "RIGHT"
    local rows = ns.RowsToward()
    local vertical = (direction == "UP" or rows == "UP") and "BOTTOM" or "TOP"
    local side = (direction == "LEFT" or rows == "LEFT") and "RIGHT" or "LEFT"
    return horizontal, vertical, side
end

local KindIcon = ns.KindIcon

------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------

-- Classes with a pet frame under the player frame.
local PET_CLASSES = { HUNTER = true, WARLOCK = true }
local GAP = 6 -- between the player frame (or what hangs under it) and the bar

-- How far the pet frame's bottom is below the player frame's top, in
-- screen pixels, once known.
local petFrameDepth

-- Newer clients keep some numbers secret from addons, such as the edges of
-- the player frame's health bar at times: an addon may pass them on, but
-- doing maths with them is an error. Here they count as unknown, like a
-- frame part that isn't placed, and the code falls back to the next part.
local function Known(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

-- A frame part's edge ("Top", "Bottom", "Left" or "Right") in screen
-- pixels, or nil if the part is missing, not placed or secret.
local function ScreenEdge(region, edge)
    local get = region and region["Get" .. edge]
    if not get then return nil end
    local value, scale = Known(get(region)), Known(region:GetEffectiveScale())
    return value and scale and value * scale
end

-- A frame part's height in screen pixels, or nil.
local function ScreenHeight(region)
    if not region then return nil end
    local height, scale = Known(region:GetHeight()), Known(region:GetEffectiveScale())
    return height and scale and height * scale
end

-- How high an anchor point sits in a frame: 1 at the top, 0 at the bottom.
local function PointHeight(point)
    if point:find("TOP") then return 1 end
    if point:find("BOTTOM") then return 0 end
    return 0.5
end

-- The pet frame's bottom in screen pixels. With no pet out (as at login)
-- the game doesn't place it, so then it's worked out from where the pet
-- frame is attached to the player frame.
local function PetFrameBottom(frameTop)
    local bottom = ScreenEdge(PetFrame, "Bottom")
    if bottom then
        petFrameDepth = frameTop - bottom
    elseif not petFrameDepth and PetFrame then
        local point, relativeTo, relativePoint, _, y = PetFrame:GetPoint(1)
        point, relativePoint, y = Known(point), Known(relativePoint), Known(y)
        local frameBottom, frameHeight = ScreenEdge(PlayerFrame, "Bottom"), ScreenHeight(PlayerFrame)
        local petHeight, petScale = ScreenHeight(PetFrame), Known(PetFrame:GetEffectiveScale())
        if point and relativePoint and y and relativeTo == PlayerFrame and frameBottom and frameHeight
            and petHeight and petScale then
            local anchor = frameBottom + frameHeight * PointHeight(relativePoint)
            petFrameDepth = frameTop - (anchor + y * petScale - petHeight * PointHeight(point))
        end
    end
    return petFrameDepth and frameTop - petFrameDepth
end

-- The player frame the bar attaches to, and which UI it's from: EllesmereUI's
-- ("eui") while it shows its own player frame instead of the game's, which
-- it then hides (the game's stays where it was, out of sight), otherwise the
-- game's ("blizzard").
local function PlayerFrameToUse()
    local ellesmere = _G.EllesmereUIUnitFrames_Player
    if ellesmere and ellesmere.GetTop then return ellesmere, "eui" end
    return PlayerFrame, "blizzard"
end

-- The bar's default spot on EllesmereUI's player frame, like DefaultOffset
-- does it for the game's: above its highest part (health bar, power bar,
-- portrait), lined up with its left edge, or its right edge for a bar
-- growing left; below it, and its cast bar if that hangs right under it,
-- when there's no room above or the bar grows down.
local function EllesmereOffset(frame)
    local db = ns.db
    local size = db.buttonSize
    local frameLeft, frameTop = ScreenEdge(frame, "Left"), ScreenEdge(frame, "Top")
    if not (frameLeft and frameTop) then return 0, GAP + size end
    local scale = Known(frame:GetEffectiveScale()) or 1
    local barScale = bar:GetEffectiveScale()

    local parts = { frame, frame.Health, frame.Power }
    if frame.Portrait and frame.Portrait:IsShown() then parts[#parts + 1] = frame.Portrait end
    local left, right, highest, lowest
    for _, part in ipairs(parts) do
        local l, r = ScreenEdge(part, "Left"), ScreenEdge(part, "Right")
        local t, b = ScreenEdge(part, "Top"), ScreenEdge(part, "Bottom")
        if l and (not left or l < left) then left = l end
        if r and (not right or r > right) then right = r end
        if t and (not highest or t > highest) then highest = t end
        if b and (not lowest or b < lowest) then lowest = b end
    end

    local x
    if db.direction == "LEFT" then
        x = ((right or frameLeft + 200 * scale) - frameLeft) / barScale - size
    else
        x = ((left or frameLeft) - frameLeft) / barScale
    end

    highest = highest or frameTop
    local _, vertical = Shape()
    local height = bar:GetHeight()
    local screenTop = UIParent:GetTop() * UIParent:GetEffectiveScale()
    if (vertical == "BOTTOM" or height <= size + 0.5) and highest + (GAP + height) * barScale <= screenTop then
        return x, (highest - frameTop) / barScale + GAP + size
    end

    lowest = lowest or frameTop - 60 * scale
    -- Its cast bar can sit anywhere; it only counts when it hangs right under.
    local castBar = frame.Castbar
    if castBar and castBar:IsShown() then
        local castTop, castBottom = ScreenEdge(castBar, "Top"), ScreenEdge(castBar, "Bottom")
        if castTop and castBottom and castTop <= lowest + 2 * scale and castTop >= lowest - 40 * scale then
            lowest = castBottom
        end
    end
    return x, (lowest - frameTop) / barScale - GAP
end

-- The cast bar, when Edit Mode's "Lock to Player Frame" hangs it under the
-- player frame.
local function AttachedCastBar()
    local castBar = PlayerCastingBarFrame
    if castBar and castBar.IsAttachedToPlayerFrame and castBar:IsAttachedToPlayerFrame() then
        return castBar
    end
end

-- Where the bar's first button goes by default, as an offset from the
-- player frame's top left. Above the player frame, where the game attaches
-- nothing (the pet frame, a locked cast bar, totems and class resources
-- all hang below it), lined up with the portrait's left edge; a bar growing
-- left starts at the frame's right end instead. With no room above (the
-- frame is at the top of the screen), or for a bar growing down, it goes
-- below everything that hangs under the frame.
local function DefaultOffset()
    local ellesmere, ui = PlayerFrameToUse()
    if ui == "eui" then return EllesmereOffset(ellesmere) end
    local db = ns.db
    local size = db.buttonSize
    local frameLeft, frameTop = ScreenEdge(PlayerFrame, "Left"), ScreenEdge(PlayerFrame, "Top")
    if not (frameLeft and frameTop) then return 40, GAP + size end
    local scale = Known(PlayerFrame:GetEffectiveScale()) or 1
    local barScale = bar:GetEffectiveScale()

    -- Forever's player frame is the newer, retail-style one: its portrait
    -- and bars have no global names, but the frame keeps them as fields.
    local portrait = PlayerFrame.portrait
    local healthBar = PlayerFrame.healthbar
    local manaBar = PlayerFrame.manabar
    local name = PlayerName

    local x
    if db.direction == "LEFT" then
        local right = ScreenEdge(manaBar, "Right") or ScreenEdge(healthBar, "Right")
            or ScreenEdge(PlayerFrame, "Right") or frameLeft + 225 * scale
        x = (right - frameLeft) / barScale - size
    else
        local left = ScreenEdge(portrait, "Left") or frameLeft
        x = (left - frameLeft) / barScale
    end

    -- Above: just over the highest part of the frame you can see.
    local highest
    local parts = { name, healthBar, manaBar } -- any may be missing
    for i = 1, 3 do
        local top = ScreenEdge(parts[i], "Top")
        if top and (not highest or top > highest) then highest = top end
    end
    local portraitTop = ScreenEdge(portrait, "Top") -- includes its round border
    if portraitTop and (not highest or portraitTop > highest) then highest = portraitTop end
    highest = highest or frameTop
    -- Above works for a bar that grows upwards from its first button, or
    -- is only one button high.
    local _, vertical = Shape()
    local height = bar:GetHeight()
    local screenTop = UIParent:GetTop() * UIParent:GetEffectiveScale()
    if (vertical == "BOTTOM" or height <= size + 0.5) and highest + (GAP + height) * barScale <= screenTop then
        return x, (highest - frameTop) / barScale + GAP + size
    end

    -- Below: under the lowest part of the frame and what hangs under it.
    local lowest
    local function Consider(bottom)
        if bottom and (not lowest or bottom < lowest) then lowest = bottom end
    end
    Consider(ScreenEdge(manaBar, "Bottom"))
    Consider(ScreenEdge(portrait, "Bottom"))
    local levelTop, levelBottom = ScreenEdge(PlayerLevelText, "Top"), ScreenEdge(PlayerLevelText, "Bottom")
    if levelTop and levelBottom then
        -- The level sits in a round badge that reaches below the text.
        Consider((levelTop + levelBottom) / 2 - 15 * scale)
    end
    if PET_CLASSES[select(2, UnitClass("player"))] then Consider(PetFrameBottom(frameTop)) end
    lowest = lowest or frameTop - 100 * scale
    local castBar = AttachedCastBar()
    local castBarHeight = castBar and ScreenHeight(castBar)
    if castBarHeight then
        -- It hangs under all of that, with its spell name below it.
        lowest = lowest - castBarHeight - 14 * scale
    end
    return x, (lowest - frameTop) / barScale - GAP
end

-- Places the bar so its first button's top left corner is at x, y from
-- the given point. The first button is the bar's fixed point: it stays
-- put when buttons come and go, and when the bar changes direction or size.
local function PlaceFirstButton(relativeTo, relativePoint, x, y)
    local size = ns.db.buttonSize
    local _, vertical, side = Shape()
    bar:ClearAllPoints()
    bar:SetPoint(vertical .. side, relativeTo, relativePoint,
        x + (side == "RIGHT" and size or 0), y - (vertical == "BOTTOM" and size or 0))
end

-- The saved position is where the first button is: from the player
-- frame's top left while the bar is attached to it (so it moves along when
-- the player frame is moved in Edit Mode, or EllesmereUI's unlock mode),
-- otherwise from the screen's bottom left. Without one, or when it was saved
-- against the other UI's player frame, the bar is at its default spot.
local function ApplyPosition()
    local saved = ns.db.position
    local frame, ui = PlayerFrameToUse()
    if saved and saved.frame == "player" and frame and (saved.ui or "blizzard") == ui then
        PlaceFirstButton(frame, "TOPLEFT", saved.x, saved.y)
    elseif saved and saved.frame == "screen" then
        PlaceFirstButton(UIParent, "BOTTOMLEFT", saved.x, saved.y)
    elseif frame then
        PlaceFirstButton(frame, "TOPLEFT", DefaultOffset())
    else
        PlaceFirstButton(UIParent, "CENTER", 0, -200)
    end
end

-- Saves where the first button is now, against the player frame or the
-- screen depending on the Attach setting.
local function SavePosition()
    local size = ns.db.buttonSize
    local x, y = bar:GetLeft(), bar:GetTop()
    if not (x and y) then return end
    local _, vertical, side = Shape()
    if side == "RIGHT" then x = bar:GetRight() - size end
    if vertical == "BOTTOM" then y = bar:GetBottom() + size end

    -- If the player frame's place is secret just now, the bar is saved
    -- against the screen; the next drag attaches it again.
    local frame, ui = PlayerFrameToUse()
    local frameLeft, frameTop = ScreenEdge(frame, "Left"), ScreenEdge(frame, "Top")
    if ns.db.attached and frameLeft and frameTop then
        local barScale = bar:GetEffectiveScale()
        ns.db.position = { frame = "player", ui = ui, x = x - frameLeft / barScale, y = y - frameTop / barScale }
    else
        ns.db.position = { frame = "screen", x = x, y = y }
    end
end

-- The exact position, for the options: where the first button's outer
-- corner is, from the player frame's top left while attached, otherwise
-- from the middle of the screen (x to the right, y up), rounded. Returns
-- x, y and "player" or "screen", or nil before the bar exists.
function ns.GetPosition()
    if not bar then return nil end
    local saved = ns.db.position
    local frame, ui = PlayerFrameToUse()
    if ns.db.attached and frame then
        local x, y
        if saved and saved.frame == "player" and (saved.ui or "blizzard") == ui then
            x, y = saved.x, saved.y
        else
            x, y = DefaultOffset()
        end
        return math.floor(x + 0.5), math.floor(y + 0.5), "player"
    end
    local x, y
    if saved and saved.frame == "screen" then
        x, y = saved.x, saved.y
    else
        local size = ns.db.buttonSize
        local _, vertical, side = Shape()
        x = side == "RIGHT" and (bar:GetRight() or 0) - size or (bar:GetLeft() or 0)
        y = vertical == "BOTTOM" and (bar:GetBottom() or 0) + size or (bar:GetTop() or 0)
    end
    return math.floor(x - UIParent:GetWidth() / 2 + 0.5), math.floor(y - UIParent:GetHeight() / 2 + 0.5), "screen"
end

-- Moves the bar to an exact position, as ns.GetPosition gives it. Not in
-- combat. Returns true if it moved.
function ns.SetPosition(x, y)
    if InCombatLockdown() then
        ns.Refuse(L["You can't move the bar in combat."])
        return false
    end
    if not bar then return false end
    local frame, ui = PlayerFrameToUse()
    if ns.db.attached and frame then
        ns.db.position = { frame = "player", ui = ui, x = x, y = y }
    else
        ns.db.position = { frame = "screen", x = x + UIParent:GetWidth() / 2, y = y + UIParent:GetHeight() / 2 }
    end
    ApplyPosition()
    return true
end

function ns.ResetPosition()
    if InCombatLockdown() then
        ns.Refuse(L["You can't move the bar in combat."])
        return false
    end
    ns.db.position = nil
    if bar then
        ApplyPosition()
        if not ns.db.attached then SavePosition() end -- the default spot, pinned to the screen
    end
    if ns.RefreshWindow then ns.RefreshWindow() end
    return true
end

-- Attaches the bar to the player frame or pins it to the screen. The bar
-- stays where it is; only what it's attached to changes.
function ns.SetAttached(attached)
    if InCombatLockdown() then
        ns.Refuse(L["You can't move the bar in combat."])
        return false
    end
    ns.db.attached = attached and true or false
    if bar and (ns.db.position or not ns.db.attached) then
        SavePosition()
        ApplyPosition()
    end
    if ns.RefreshWindow then ns.RefreshWindow() end
    return true
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------

-- Forever's client keeps your auras secret in combat, and asking for them
-- then is an error ("Auras cannot be accessed when secret"). Every aura
-- lookup goes through this: the answer, or ok = false if it was refused.
local function AskAura(lookup, ...)
    local ok, aura = pcall(lookup, ...)
    if not ok then return false end
    return true, aura
end

-- Whether a value from an aura can be used (not a secret one).
local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end

-- The Recently Bandaged debuff on you: its duration and when it ends (nil
-- if you don't have it, or the game won't say).
local function RecentlyBandaged()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = AskAura(C_UnitAuras.GetPlayerAuraBySpellID, RECENTLY_BANDAGED)
        if ok and aura and Readable(aura.duration) and Readable(aura.expirationTime) then
            return aura.duration, aura.expirationTime
        end
        return nil
    end
    if AuraUtil and AuraUtil.FindAuraByName then
        local name = ns.SpellName(RECENTLY_BANDAGED) or "Recently Bandaged"
        local _, _, _, _, auraDuration, expiration = AuraUtil.FindAuraByName(name, "player", "HARMFUL")
        return auraDuration, expiration
    end
end

local function UpdateCooldown(button)
    local start, duration = 0, 0
    if button.itemID then
        local itemStart, itemDuration, enable = GetItemCooldown(button.itemID)
        if enable ~= 0 and enable ~= false and itemDuration and itemDuration > 0 then
            start, duration = itemStart, itemDuration
        end
    end

    -- Recently Bandaged lasts longer than the bandage's own cooldown.
    if button.kind.key == "bandage" then
        local auraDuration, expiration = RecentlyBandaged()
        if auraDuration and auraDuration > 0 and expiration and expiration > start + duration then
            start, duration = expiration - auraDuration, auraDuration
        end
    end

    -- Short ones (a global cooldown) only get the sweep, not the cooldown look.
    button.coolingDown = duration > 1.5 and start + duration > GetTime()
    if duration > 0 then
        button.cooldown:SetCooldown(start, duration)
    elseif button.cooldown.Clear then
        button.cooldown:Clear()
    else
        button.cooldown:SetCooldown(0, 0)
    end
end

-- Seconds left on a buff you have (math.huge if it doesn't run out, or if
-- the game won't say), or nil if you don't have it.
-- Your buff called name, looking through all your buffs: for when the
-- lookup by name finds nothing. true and the aura, or false if the game
-- won't say.
local function FindBuffByName(name)
    local wanted = ns.Lower(name)
    for i = 1, 40 do
        local ok, aura = AskAura(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then return false end
        if not aura then return true, nil end
        if Readable(aura.name) and ns.Lower(aura.name) == wanted then return true, aura end
    end
    return true, nil
end

local function AuraTimeLeft(name)
    local expiration
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = AskAura(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if ok and not aura and C_UnitAuras.GetAuraDataByIndex then
            ok, aura = FindBuffByName(name)
        end
        if not ok then return math.huge end -- secret: no reminder rather than a wrong one
        if not aura then return nil end
        expiration = aura.expirationTime
        if not Readable(expiration) then return math.huge end
    elseif AuraUtil and AuraUtil.FindAuraByName then
        local found, _, _, _, _, auraExpiration = AuraUtil.FindAuraByName(name, "player", "HELPFUL")
        if not found then return nil end
        expiration = auraExpiration
    else
        return nil
    end
    if not expiration or expiration == 0 then return math.huge end
    return expiration - GetTime()
end

local function BuffTimeLeft(spellID, englishName)
    return AuraTimeLeft(ns.SpellName(spellID) or englishName)
end

-- For the debug report: your buffs as the game gives them to addons, and
-- what the buff reminders make of them. out(line) adds a line.
function ns.AuraDebug(out)
    out("Buffs on you (name, spell ID, minutes left):")
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        out("  no C_UnitAuras.GetAuraDataByIndex")
    end
    for i = 1, 40 do
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then break end
        local ok, aura = AskAura(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then
            out("  (the game keeps your buffs secret right now)")
            break
        end
        if not aura then break end
        local left = "?"
        if Readable(aura.expirationTime) and aura.expirationTime then
            left = aura.expirationTime == 0 and "-" or ("%.1f"):format((aura.expirationTime - GetTime()) / 60)
        end
        out(("  %s (%s): %s"):format(Readable(aura.name) and tostring(aura.name) or "secret",
            Readable(aura.spellId) and tostring(aura.spellId) or "secret", left))
    end
    local function Check(label, name)
        local byName = "no lookup by name"
        if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
            local ok, aura = AskAura(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
            byName = not ok and "refused" or (aura and "found" or "not found")
        end
        local left = AuraTimeLeft(name)
        out(("  %s looks for \"%s\": by name %s; time left %s"):format(label, name, byName,
            left == nil and "none (glows gold)" or left == math.huge and "unknown" or ("%.1f min"):format(left / 60)))
    end
    out(("Glow: %s, %s%%, pulse %s; sparkle from %s"):format(ns.db.glowStyle, tostring(ns.db.glowStrength),
        tostring(ns.db.glowPulse), ns.ProcKind and ns.ProcKind() or "?"))
    out("What the reminders see:")
    Check("Buff food", ns.SpellName(WELL_FED) or "Well Fed")
    for _, key in ipairs({ "elixir", "scroll", "otherBuff" }) do
        local button = buttons[key]
        local spell = button and button.itemID and GetItemSpell(button.itemID)
        if spell then Check(button.kind.name, spell) end
    end
end

-- Bleeds have no debuff type in Classic's data, so they're also known by
-- name: the players' and the commonest monsters' bleeds, and any debuff
-- with "bleed" in its name. Built when first needed, in the client's language.
local BLEED_SPELLS = {
    772, -- Rend
    12162, -- Deep Wound
    703, -- Garrote
    1943, -- Rupture
    1822, -- Rake
    1079, -- Rip
    9005, -- Pounce (its bleed is "Pounce Bleed", caught by the word)
}
local bleedNames

local function IsBleed(name, dispel)
    if dispel == "Bleed" then return true end
    if not name then return false end
    if not bleedNames then
        bleedNames = {}
        for _, spellID in ipairs(BLEED_SPELLS) do
            local spellName = ns.SpellName(spellID)
            if spellName then bleedNames[spellName] = true end
        end
    end
    return bleedNames[name] or ns.Lower(name):find(L["bleed"], 1, true) ~= nil
end

-- Whether you have a debuff of this kind (Poison, Disease or Bleed): true
-- or false, or nil when the game won't say (your auras are secret in
-- combat). Single debuffs it keeps secret are skipped.
local function HasDebuff(cure)
    if inCombat or InCombatLockdown() then return nil end
    for i = 1, 40 do
        local name, dispel
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, aura = AskAura(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
            if not ok then return nil end
            if not aura then return false end
            name, dispel = aura.name, aura.dispelName
        elseif UnitDebuff then
            local debuffName, _, _, debuffType = UnitDebuff("player", i)
            if not debuffName then return false end
            name, dispel = debuffName, debuffType
        else
            return false
        end
        if Readable(name) and Readable(dispel) then
            if cure == "Bleed" then
                if IsBleed(name, dispel) then return true end
            elseif dispel == cure then
                return true
            end
        end
    end
    return false
end

-- The glow switch and "running out" setting of each buff button.
local GLOW_SETTING = { elixir = "elixirGlow", elixir2 = "elixirGlow", scroll = "scrollGlow", otherBuff = "otherBuffGlow" }
local MINUTES_SETTING = { scroll = "scrollMinutes", otherBuff = "otherBuffMinutes" } -- others: elixirMinutes

-- Gold while a buff is missing, silver in its last few minutes, as set on
-- the Reminders page for that kind of buff (see ns.RUNNING_OUT).
local function GlowFor(timeLeft, minutes)
    if not timeLeft then return GLOW_MISSING end
    return timeLeft <= minutes * 60 and GLOW_EXPIRING or nil
end

local WEAPON = Enum.ItemClass and Enum.ItemClass.Weapon or 2

local function HoldsWeapon(slot)
    local itemID = GetInventoryItemID("player", slot)
    return itemID ~= nil and select(6, C_Item.GetItemInfoInstant(itemID)) == WEAPON
end

-- The glow for the weapon in the slot (16 main hand, 17 off-hand): gold
-- while it has no stone, oil, poison or other temporary enchant on it,
-- silver when that enchant is running out. A shield or held-in-off-hand
-- item isn't a weapon, so it gets none.
local function WeaponGlow(slot)
    if not HoldsWeapon(slot) then return nil end
    local hasMainHand, mainHandLeft, _, _, hasOffHand, offHandLeft = GetWeaponEnchantInfo()
    if slot == 16 then
        return GlowFor(hasMainHand and (mainHandLeft or 0) / 1000 or nil, ns.db.weaponMinutes)
    end
    return GlowFor(hasOffHand and (offHandLeft or 0) / 1000 or nil, ns.db.weaponMinutes)
end

-- Reminders: a soft, slowly pulsing glow, gold while something is missing
-- and silver when it's running out: Well Fed on buff food (not while
-- you're eating), the item's buff on elixirs and scrolls, and stones, oils
-- and poisons on weapons. Only out of combat, and only when you carry some.
-- Cures glow gold while you have something they cure, out of combat only:
-- the game keeps your debuffs secret in a fight (see HasDebuff).
-- Returns the glow's colour, or nil.
local function WantsGlow(button, empty)
    if empty then return nil end
    if inCombat or InCombatLockdown() then return nil end
    local cure = button.kind.cure
    if cure then
        return ns.db.cureGlow and HasDebuff(cure) and GLOW_MISSING or nil
    end
    local key = button.kind.key
    if key == "buffFood" then
        if not ns.db.buffFoodGlow or BuffTimeLeft(EATING, "Food") then return nil end
        return GlowFor(BuffTimeLeft(WELL_FED, "Well Fed"), ns.db.wellFedMinutes)
    elseif key == "weapon" then
        -- Both hands: the more urgent of the two.
        if not ns.db.weaponGlow then return nil end
        local main, off = WeaponGlow(16), WeaponGlow(17)
        if main == GLOW_MISSING or off == GLOW_MISSING then return GLOW_MISSING end
        return main or off
    elseif button.kind.slot then -- poisons: their own hand
        return ns.db.weaponGlow and WeaponGlow(button.kind.slot) or nil
    elseif button.kind.buff then
        -- The buff is named like the item's use effect, e.g. "Elixir of the
        -- Mongoose" or "Stamina" for a Scroll of Stamina. A custom button
        -- with its glow on (Custom.lua) goes by the Other buffs timing.
        local custom = button.kind.custom
        if not button.itemID or (not custom and not ns.db[GLOW_SETTING[key]]) then return nil end
        local spell = GetItemSpell(button.itemID)
        local minutes = ns.db[MINUTES_SETTING[key] or (custom and "otherBuffMinutes") or "elixirMinutes"]
        return spell and GlowFor(AuraTimeLeft(spell), minutes) or nil
    end
    return nil
end

-- "Hide while on": which reminder each button belongs to.
local REMINDER_OF = {
    buffFood = "wellFed", elixir = "elixir", elixir2 = "elixir", scroll = "scroll", otherBuff = "otherBuff",
    weapon = "weapon", poison = "weapon", poison2 = "weapon",
    antiVenom = "cure", poultice = "cure", tourniquet = "cure",
}

-- True while the buff a button is for is on you and not running out yet,
-- the same moments its reminder glow is off. Weapons: every weapon you hold
-- has a stone, oil or poison on it (or for a poison button, its own hand).
-- Cures: you have nothing for them to cure.
local function BuffIsOn(key, itemID)
    local cure = ns.KIND_BY_KEY[key].cure
    if cure then
        return HasDebuff(cure) == false -- unknown: keep the button on the bar
    elseif key == "buffFood" then
        return GlowFor(BuffTimeLeft(WELL_FED, "Well Fed"), ns.db.wellFedMinutes) == nil
    elseif key == "weapon" then
        return (HoldsWeapon(16) or HoldsWeapon(17)) and WeaponGlow(16) == nil and WeaponGlow(17) == nil
    end
    local slot = ns.KIND_BY_KEY[key].slot
    if slot then
        return HoldsWeapon(slot) and WeaponGlow(slot) == nil
    end
    local spell = itemID and GetItemSpell(itemID)
    if not spell then return false end
    local minutes = ns.db[MINUTES_SETTING[key] or "elixirMinutes"]
    return GlowFor(AuraTimeLeft(spell), minutes) == nil
end

ns.BuffIsOn = BuffIsOn -- also used to pick an elixir or scroll that isn't on you yet

-- Whether "Hide while on" keeps a button off the bar right now.
local function HiddenWhileOn(key, itemID)
    local reminder = REMINDER_OF[key]
    if not reminder or not ns.db.hideWhileOn[reminder] then return false end
    return BuffIsOn(key, itemID) and true or false
end

-- All glows pulse together, from one clock: a slow, eased fade between
-- PULSE_LOW and PULSE_HIGH. Runs only while some button glows.
local PULSE_PERIOD = 3.2 -- seconds for a fade in and out
local PULSE_LOW, PULSE_HIGH = 0.3, 0.85

-- Every frame that can glow: the bar's buttons and the options' preview.
local glowFrames = {}

-- The look of the glow, from the Reminders page: style soft (the halo),
-- border (a frame tight around the button), both, or proc (the action
-- bars' sparkling proc glow); strength in percent; pulse on or off.
local function GlowLook()
    local db = ns.db
    return db.glowStyle or "soft", (db.glowStrength or 100) / 100, db.glowPulse ~= false
end

local pulse = CreateFrame("Frame")
pulse:Hide()
pulse:SetScript("OnUpdate", function(self)
    local _, strength, pulsing = GlowLook()
    local alpha = PULSE_HIGH
    if pulsing then
        local phase = (GetTime() % PULSE_PERIOD) / PULSE_PERIOD
        alpha = PULSE_LOW + (PULSE_HIGH - PULSE_LOW) * (0.5 - 0.5 * math.cos(phase * 2 * math.pi))
    end
    local glowing = false
    for frame in pairs(glowFrames) do
        if frame.glowColor and frame:IsVisible() then
            local value = math.min(1, alpha * frame.glowColor.strength * strength)
            frame.glow:SetAlpha(value)
            frame.ring:SetAlpha(value)
            glowing = true
        end
    end
    if not glowing then self:Hide() end
end)

-- The proc glow. This client may have the game's own: the newer action
-- bars' (ActionButtonSpellAlertTemplate) or the older ones'
-- (ActionBarButtonSpellActivationAlert). Without either, Fanny Pack draws
-- the older one's marching ants itself; without those, a border instead.
local procKind -- "new", "old", "ants" or "none", once known

local function HasTemplate(name)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        return C_XMLUtil.GetTemplateInfo(name) ~= nil
    end
    return nil -- can't tell
end

local function ProcKind()
    if procKind then return procKind end
    local new, old = HasTemplate("ActionButtonSpellAlertTemplate"), HasTemplate("ActionBarButtonSpellActivationAlert")
    if new == nil then -- no way to look templates up: go by what else the game has
        new = ActionButtonSpellAlertManager ~= nil
        old = not new and ActionButton_ShowOverlayGlow ~= nil
    end
    procKind = new and "new" or old and "old" or "ants"
    return procKind
end
ns.ProcKind = ProcKind -- for the debug report

-- Colours every texture in a proc glow: as it comes for gold, or greyed and
-- tinted for silver ("running out").
local function TintProc(frame, color)
    local silver = color[1] < 0.9
    local function tint(region)
        if region.SetVertexColor and region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetDesaturated(silver)
            if silver then region:SetVertexColor(color[1], color[2], color[3]) else region:SetVertexColor(1, 1, 1) end
        end
    end
    for _, region in ipairs({ frame:GetRegions() }) do tint(region) end
    for _, child in ipairs({ frame:GetChildren() }) do
        for _, region in ipairs({ child:GetRegions() }) do tint(region) end
    end
end

-- The proc glow frame of a button, made the first time it's needed. nil if
-- this client has none.
local function GetProc(button)
    if button.proc ~= nil then return button.proc or nil end
    local kind = ProcKind()
    local ok, frame
    if kind == "new" then
        ok, frame = pcall(CreateFrame, "Frame", nil, button, "ActionButtonSpellAlertTemplate")
        if ok and frame and frame.ProcLoop then
            if frame.ProcStartFlipbook then frame.ProcStartFlipbook:SetAlpha(0) end -- no opening burst
            if frame.ProcLoopFlipbook then frame.ProcLoopFlipbook:SetAlpha(1) end
        else
            frame = nil
        end
    elseif kind == "old" then
        ok, frame = pcall(CreateFrame, "Frame", nil, button, "ActionBarButtonSpellActivationAlert")
        if not (ok and frame and frame.ants) then frame = nil end
    end
    if not frame then
        -- Our own marching ants, from the older proc glow's texture.
        frame = CreateFrame("Frame", nil, button)
        frame.ants = frame:CreateTexture(nil, "OVERLAY")
        frame.ants:SetAllPoints()
        local loaded = frame.ants:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
        if loaded == false or not AnimateTexCoords then
            frame:Hide()
            button.proc = false
            return nil
        end
        frame:SetScript("OnUpdate", function(self, elapsed)
            AnimateTexCoords(self.ants, 256, 256, 48, 48, 22, elapsed, 0.01)
        end)
        frame.own = true
    end
    -- The game stops an animation when its button is hidden (food in
    -- combat, a button whose item ran out) and doesn't start it again when
    -- the button comes back: start it again on every show.
    frame:HookScript("OnShow", function(self)
        if self.ProcLoop and not self.ProcLoop:IsPlaying() then self.ProcLoop:Play() end
    end)
    frame:Hide()
    button.proc = frame
    return frame
end

local function StopProc(button)
    local frame = button.proc
    if not frame then return end
    if frame.ProcLoop then frame.ProcLoop:Stop() end
    if frame.animIn then frame.animIn:Stop() end
    frame:Hide()
end

local function StartProc(button, color)
    local frame = GetProc(button)
    if not frame then return false end
    local width, height = button:GetSize()
    frame:ClearAllPoints()
    frame:SetSize(width * 1.4, height * 1.4) -- as the action bars size it
    frame:SetPoint("CENTER", button, "CENTER")
    frame:SetFrameLevel(button:GetFrameLevel() + 5)
    TintProc(frame, color)
    local _, strength = GlowLook()
    frame:SetAlpha(math.min(1, color.strength * strength * (color.strength < 1 and 2 or 1)))
    if not frame:IsShown() then
        frame:Show()
        if frame.animIn then frame.animIn:Play() end
    end
    -- Also if it stopped for any other reason: every look update restarts it.
    if frame.ProcLoop and not frame.ProcLoop:IsPlaying() then frame.ProcLoop:Play() end
    return true
end

-- Shows a frame's glow in color (GLOW_MISSING or GLOW_EXPIRING) in the
-- chosen look, or hides it (color nil).
local function ShowGlow(frame, color)
    local style = GlowLook()
    local proc = color and style == "proc" and StartProc(frame, color)
    if not proc then StopProc(frame) end
    -- Without a proc glow on this client, the proc style shows a border.
    local soft = color and (style == "soft" or style == "both")
    local ring = color and (style == "border" or style == "both" or (style == "proc" and not proc))
    frame.glow:SetShown(soft and true or false)
    frame.ring:SetShown(ring and true or false)
    if soft then frame.glow:SetVertexColor(color[1], color[2], color[3]) end
    if ring then frame.ring:SetVertexColor(color[1], color[2], color[3]) end
    frame.glowColor = (soft or ring) and color or nil
    frame.glowing = color ~= nil
    if frame.glowColor then pulse:Show() end
end

local function UpdateGlow(button, empty)
    ShowGlow(button, WantsGlow(button, empty))
end

-- The size of one screen pixel in a frame's units, so borders stay crisp
-- and equally thin at any UI scale.
local function PixelSize(frame)
    local _, height = GetPhysicalScreenSize()
    if not height or height == 0 then return 1 end
    return 768 / height / frame:GetEffectiveScale()
end

-- Shape and border, or with a Masque skin on (Skin.lua) neither: the skin
-- draws the frame and places the icon, highlight, pressed look, cooldown,
-- count and key. Safe in combat.
local function ApplyStyle(button)
    local db = ns.db
    local skinned = ns.Skinned and ns.Skinned(button)
    local maskFile = not skinned and SHAPE_MASKS[db.shape] or nil
    local border = BORDERS[db.border]
    local shaped = { button.icon, button:GetHighlightTexture(), button:GetPushedTexture() }

    if skinned then
        button.border:Hide()
    else
        if ns.HideSkin then ns.HideSkin(button) end -- the skin's frame, while Masque's group is off
        -- The border is the button's shape in the border colour, behind the icon.
        button.border:Show()
        if maskFile then
            button.border:SetTexture(MEDIA .. maskFile)
        else
            button.border:SetColorTexture(1, 1, 1, 1)
        end
        button.border:SetVertexColor(unpack(border and border.color or { 0, 0, 0, 0 }))
        local inset = border and border.pixels * PixelSize(button) or 0
        button.icon:ClearAllPoints()
        button.icon:SetPoint("TOPLEFT", inset, -inset)
        button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        -- Back over the icon, in case a skin placed them elsewhere.
        for i = 2, 3 do
            shaped[i]:ClearAllPoints()
            shaped[i]:SetAllPoints(button.icon)
        end
        button.cooldown:ClearAllPoints()
        button.cooldown:SetAllPoints(button.icon)
    end

    -- The mask cuts the icon, highlight and pressed look to shape.
    if maskFile then
        button.mask:SetTexture(MEDIA .. maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if not button.masked then
            for _, texture in ipairs(shaped) do texture:AddMaskTexture(button.mask) end
            button.masked = true
        end
    elseif button.masked then
        for _, texture in ipairs(shaped) do texture:RemoveMaskTexture(button.mask) end
        button.masked = false
    end
    if not skinned then
        button.cooldown:SetSwipeTexture(maskFile and MEDIA .. maskFile or "Interface\\Buttons\\WHITE8x8")
        button.cooldown:SetSwipeColor(0, 0, 0, 0.75)
        if button.cooldown.SetUseCircularEdge then button.cooldown:SetUseCircularEdge(db.shape == "round") end
    end

    -- Text sized to the button, outlined to read on any background.
    local size = db.buttonSize
    button.count:SetFont(NUMBER_FONT, math.max(9, math.floor(size * 0.42 + 0.5)), "OUTLINE")
    button.hotkey:SetFont(NUMBER_FONT, math.max(9, math.floor(size * 0.42 + 0.5)), "OUTLINE")
    button.hotkey:SetTextColor(1, 1, 1)
    countdownFont:SetFont(NUMBER_FONT, math.max(10, math.floor(size * 0.5 + 0.5)), "OUTLINE")
    if button.cooldown.SetCountdownFont then button.cooldown:SetCountdownFont("FannyPackCountdownFont") end

    -- A skin's frame is near enough square for the glows.
    button.glow:SetTexture(MEDIA .. "glow-" .. (skinned and "square" or db.shape))
    button.glow:SetSize(db.buttonSize * 2, db.buttonSize * 2) -- the button covers its middle half
    -- The border glow: the button's shape, a few pixels bigger, behind it.
    if maskFile then
        button.ring:SetTexture(MEDIA .. maskFile)
    else
        button.ring:SetColorTexture(1, 1, 1, 1)
    end
    local thickness = math.max(2, math.floor(db.buttonSize * 0.1 + 0.5))
    button.ring:SetSize(db.buttonSize + thickness * 2, db.buttonSize + thickness * 2)
end

-- Short key names, like the action bars: SHIFT-1 becomes S1.
local KEY_ABBREVIATIONS = {
    { "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" }, { "META%-", "M" },
    { "MOUSEWHEELUP", "MwU" }, { "MOUSEWHEELDOWN", "MwD" }, { "BUTTON(%d+)", "M%1" },
    { "NUMPAD", "N" }, { "SPACE", "Sp" },
}

-- The key bound to a button (Bindings.xml), shown in its top right corner.
-- A key as the action bars show it: SHIFT-1 becomes S1.
function ns.ShortKey(key)
    for _, abbreviation in ipairs(KEY_ABBREVIATIONS) do
        key = key:gsub(abbreviation[1], abbreviation[2])
    end
    return key
end

local function UpdateHotkey(button)
    local key = GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton")
    button.hotkey:SetText(key and ns.ShortKey(key) or "")
end

-- Fade out of combat: how visible the bar is now, from 0 to 1. The fader
-- moves it towards 1 in combat or under the mouse, and towards 0 otherwise.
local visibility = 1

-- Empty buttons are dimmed; out of combat the whole bar fades, except a
-- glowing buff food button, so its reminder still shows.
local function ApplyAlpha(button)
    local alpha = button.empty and 0.4 or 1
    if not button.glowing then alpha = alpha * visibility end
    button:SetAlpha(alpha)
end

-- Icon, count, fading, cooldown and glow. Safe in combat.
local function UpdateLook(button)
    local itemID = button.itemID
    local count = itemID and GetItemCount(itemID) or 0
    local subIconID
    if button.partIDs then
        -- Eat & drink: the count of whichever runs out first, and the second
        -- item's icon in the corner.
        count = nil
        for i, partID in ipairs(button.partIDs) do
            local partCount = GetItemCount(partID)
            if partCount > 0 then count = count and math.min(count, partCount) or partCount end
            if i == 2 then subIconID = partID end
        end
        count = count or 0
    end
    local flyout = button.kind.flyout
    if flyout then count = #ns.ListFor(button.kind.key) end -- kinds of camp gear, not shown
    local empty = count == 0
    button.subIcon:SetShown(subIconID ~= nil and not empty)
    if subIconID then
        button.subIcon:SetTexture(select(5, C_Item.GetItemInfoInstant(subIconID)))
        button.subIcon:SetSize(ns.db.buttonSize * 0.45, ns.db.buttonSize * 0.45)
    end

    UpdateCooldown(button)
    local coolingDown = button.coolingDown

    -- Grey while empty or cooling down; red when you can't use it, like
    -- the action bars.
    button.icon:SetTexture(itemID and select(5, C_Item.GetItemInfoInstant(itemID)) or KindIcon(button.kind))
    button.icon:SetDesaturated(empty or coolingDown)
    if not empty and not button.usable then
        button.icon:SetVertexColor(1, 0.35, 0.35)
    else
        button.icon:SetVertexColor(1, 1, 1)
    end
    button.empty = empty

    -- During a cooldown its countdown is the only text, so it stays readable.
    button.count:SetText((empty or flyout) and "" or (count > 999 and "*" or count))
    local lowStock = ns.LowStock(button.kind.key)
    if ns.db.lowStockWarning and not empty and count <= lowStock then
        button.count:SetTextColor(unpack(LOW_STOCK_COLOR)) -- down to your last few
    else
        button.count:SetTextColor(1, 1, 1)
    end
    button.count:SetShown(not coolingDown)
    button.hotkey:SetShown(not coolingDown)
    UpdateGlow(button, empty)
    ApplyAlpha(button)
end

local function ShowButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.kind.flyout then
        GameTooltip:SetText(self.kind.name, 1, 1, 1)
        local list = ns.ListFor(self.kind.key)
        for _, entry in ipairs(list) do
            GameTooltip:AddDoubleLine(entry.name, entry.count, 1, 0.82, 0, 1, 1, 1)
        end
        if #list == 0 then
            GameTooltip:AddLine(L["None in your bags."], C.muted[1], C.muted[2], C.muted[3])
        end
        GameTooltip:AddLine(L["Click to show all of it in a row, then click one to use it. Right-click to hide some of it."],
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
        return
    elseif self.kind.combo then
        GameTooltip:SetText(self.kind.name, 1, 1, 1)
        for _, partID in ipairs(self.partIDs or {}) do
            local name = C_Item.GetItemInfo(partID)
            if name then GameTooltip:AddDoubleLine(name, GetItemCount(partID), 1, 0.82, 0, 1, 1, 1) end
        end
        if not (self.partIDs and #self.partIDs > 0) then
            GameTooltip:AddLine(L["None in your bags."], C.muted[1], C.muted[2], C.muted[3])
        end
        GameTooltip:AddLine(L["Eats and drinks in one click, with the items of your Food and Drink buttons."],
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
        return
    elseif self.itemID and GetItemCount(self.itemID) > 0 then
        GameTooltip:SetItemByID(self.itemID)
    else
        GameTooltip:SetText(self.kind.name, 1, 1, 1)
        GameTooltip:AddLine(L["None in your bags."], C.muted[1], C.muted[2], C.muted[3])
    end
    if self.kind.cure then
        local what = { Poison = L["a poison"], Disease = L["a disease"], Bleed = L["a bleed"] }
        GameTooltip:AddLine(L["Out of combat, only used while you have %s on you. Shift-click to use it anyway."]
            :format(what[self.kind.cure]), 0.6, 0.6, 0.6, true)
    end
    if self.kind.self then
        GameTooltip:AddLine(ns.db.useOnTarget and L["Goes on your friendly target, or on you."]
            or L["Always goes on you."], 0.6, 0.6, 0.6, true)
    elseif self.kind.shiftSlot then
        GameTooltip:AddLine(L["Click to put it on your main hand weapon, Shift-click for your off-hand."],
            0.6, 0.6, 0.6, true)
    elseif self.kind.slot == 16 then
        GameTooltip:AddLine(L["Click to put it on your main hand weapon."], 0.6, 0.6, 0.6, true)
    elseif self.kind.slot == 17 then
        GameTooltip:AddLine(L["Click to put it on your off-hand weapon."], 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(L["Right-click to choose another item, or hide one."], 0.6, 0.6, 0.6, true)
    if self.kind.custom then
        GameTooltip:AddLine(L["Your own button: drop an item from your bags on it to add it."], 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

-- The looks every button has, on the bar and in the camp gear row: border,
-- icon, glow, highlight, cooldown, count and hotkey.
local function AddButtonParts(button)
    -- Shape and border are set by ApplyStyle.
    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetAllPoints()

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.mask = button:CreateMaskTexture()
    button.mask:SetAllPoints(button.icon)

    -- Soft glow around the button, for the buff food reminder. It sits
    -- behind the border, so only the part outside the button shows.
    button.glow = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    button.glow:SetPoint("CENTER")
    button.glow:SetBlendMode("BLEND")
    button.glow:Hide()
    button.ring = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    button.ring:SetPoint("CENTER")
    button.ring:Hide()
    glowFrames[button] = true

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:GetHighlightTexture():SetAllPoints(button.icon)
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    button:GetPushedTexture():SetAllPoints(button.icon)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetDrawBling(false) -- its flash is square, also on round buttons
    if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(false) end

    -- The count goes on its own layer so the cooldown swipe doesn't cover it.
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    -- Eat & drink: the drink's icon small in the food's corner.
    button.subIcon = overlay:CreateTexture(nil, "ARTWORK")
    button.subIcon:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMLEFT", 1, 1)
    button.subIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.subIcon:Hide()

    button.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    button.hotkey = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    button.hotkey:SetPoint("TOPRIGHT", -1, -1)
end

-- Two sample buttons for the options' Glow look card: one glowing gold
-- (missing), one silver (running out), in the chosen look.
function ns.CreateGlowPreview(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder.samples = {}
    for i, color in ipairs({ GLOW_MISSING, GLOW_EXPIRING }) do
        local sample = CreateFrame("Button", nil, holder)
        sample.kind = ns.KIND_BY_KEY.buffFood
        AddButtonParts(sample)
        sample:SetSize(ns.db.buttonSize, ns.db.buttonSize)
        if ns.SkinButton then ns.SkinButton(sample) end -- shows the glow on the Masque skin too
        sample.icon:SetTexture(ns.KindIcon(ns.KIND_BY_KEY[i == 1 and "buffFood" or "elixir"]))
        sample:EnableMouse(false)
        sample.color = color
        holder.samples[i] = sample
    end
    function holder:Refresh()
        local size = ns.db.buttonSize
        self:SetSize(size * 2 + 24, size + 16)
        for i, sample in ipairs(self.samples) do
            sample:SetSize(size, size)
            ApplyStyle(sample)
            if ns.FitSkin then ns.FitSkin(sample) end
            sample:ClearAllPoints()
            sample:SetPoint("LEFT", (i - 1) * (size + 24) + 8, 0)
            ShowGlow(sample, sample.color)
        end
    end
    holder:SetScript("OnShow", holder.Refresh)
    return holder
end

local function CreateItemButton(kind)
    local button = CreateFrame("Button", ns.ButtonName(kind.key), bar, "SecureActionButtonTemplate")
    button.kind = kind
    button.usable = true

    -- Left-click uses the item. Right-click has no secure action, only
    -- the item list (PostClick). What a click does, and which half of it
    -- counts, is set in SecureUpdate.
    AddButtonParts(button)
    button.cooldown:SetScript("OnCooldownDone", function() UpdateLook(button) end)
    button:SetSize(ns.db.buttonSize, ns.db.buttonSize)
    if ns.SkinButton then ns.SkinButton(button) end
    ApplyStyle(button)

    -- Camp gear: a click opens its row, a right-click its list.
    button:SetScript("PostClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ns.TogglePicker(self)
        elseif self.kind.flyout then
            ns.ToggleFlyout(self)
        elseif self.locked and not IsShiftKeyDown() and UIErrorsFrame then
            UIErrorsFrame:AddMessage(L["Nothing to cure. Shift-click to use it anyway."], 1, 0.1, 0.1)
        end
    end)
    button:SetAttribute("fp-incombat", false)
    button:SetAttribute("fp-outofcombat", false)
    button:SetAttribute("fp-enabled", false)
    button:SetScript("OnEnter", ShowButtonTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    -- Custom buttons: drop an item from your bags on one to add it.
    if kind.custom then
        button:SetScript("OnReceiveDrag", function(self)
            local what, itemID = GetCursorInfo()
            if what ~= "item" or not itemID then return end
            ClearCursor()
            local ok, why = ns.AddCustomItem(self.kind.key, itemID)
            if not ok and why then ns.Refuse(why) end
        end)
    end
    return button
end

-- A custom button made while you play (Custom.lua). Not in combat.
function ns.AddBarButton(kind)
    if not bar or buttons[kind.key] or InCombatLockdown() then return end
    buttons[kind.key] = CreateItemButton(kind)
end

-- A custom button deleted: off the bar for good. Its frame stays, hidden
-- (the game can't delete frames); its key is never used again.
function ns.RemoveBarButton(key)
    local button = buttons[key]
    if not button or InCombatLockdown() then return end
    if picker and picker.owner == button then picker:Hide() end
    if ns.UnskinButton then ns.UnskinButton(button) end
    button:SetAttribute("fp-enabled", false)
    button:Hide()
    glowFrames[button] = nil
    buttons[key] = nil
end

-- Like the action bars, the buttons act on the half of a click the game's
-- "Cast action keybinds on key down" option picks: the press when it's on
-- (the default), the release when it's off. Secure buttons ignore the
-- other half, so registering for the wrong one makes clicks do nothing.
local function ClickHalf()
    return GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp"
end

-- Which item each button uses, which buttons show, their size, order and
-- places. Not allowed in combat, so then it waits.
local function SecureUpdate()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false

    local db = ns.db
    local size, spacing = db.buttonSize, db.spacing
    local clickHalf = ClickHalf()
    local shownOut, shownIn = 0, 0 -- buttons shown out of and in combat
    for i, key in ipairs(ns.Order()) do
        local button = buttons[key]
        local entry = ns.ItemFor(key)
        button.itemID = entry and entry.itemID
        button.usable = not entry or entry.usable
        local kind = button.kind
        if kind.flyout then
            -- No item of its own: a click opens the row (PostClick).
            button.itemID = nil
            button:SetAttribute("type1", nil)
        elseif kind.slot then
            -- Stones, oils and poisons need a weapon to go on: use the
            -- item, then pick the weapon's slot.
            local use = entry and "/use item:" .. entry.itemID .. "\n/use "
            button:SetAttribute("type1", "macro")
            button:SetAttribute("macrotext1", use and use .. kind.slot or nil)
            if kind.shiftSlot then
                button:SetAttribute("shift-macrotext1", use and use .. kind.shiftSlot or nil)
            end
        elseif kind.combo then
            -- Eat & drink: the Food and Drink buttons' items in one press.
            button.partIDs = {}
            local lines = {}
            for _, part in ipairs(kind.combo) do
                local partEntry = ns.ItemFor(part)
                if partEntry then
                    button.partIDs[#button.partIDs + 1] = partEntry.itemID
                    lines[#lines + 1] = "/use item:" .. partEntry.itemID
                end
            end
            button:SetAttribute("type1", "macro")
            button:SetAttribute("macrotext1", #lines > 0 and table.concat(lines, "\n") or nil)
        elseif kind.self and db.useOnTarget then
            -- Bandages and scrolls on a friendly, living target, otherwise
            -- on you. The game decides at the click, so it works in combat.
            button:SetAttribute("type1", "macro")
            button:SetAttribute("macrotext1",
                entry and ("/use [@target,help,nodead][@player] item:" .. entry.itemID) or nil)
        else
            button:SetAttribute("type1", "item")
            button:SetAttribute("unit1", kind.self and "player" or nil) -- on you, even with a friend targeted
            button:SetAttribute("item1", entry and ("item:" .. entry.itemID) or nil)
        end
        if kind.cure then
            -- Out of combat a cure is only used while you have something
            -- for it to cure, so it isn't wasted; Shift-click uses it
            -- anyway. In a fight the button can't change, so it stays armed.
            for _, attribute in ipairs({ "type1", "item1", "unit1", "macrotext1" }) do
                button:SetAttribute("shift-" .. attribute, button:GetAttribute(attribute))
            end
            button.locked = entry ~= nil and not inCombat and HasDebuff(kind.cure) == false
            if button.locked then button:SetAttribute("type1", nil) end
        end
        button:RegisterForClicks(clickHalf)
        button:SetSize(size, size)

        -- Out of combat, in combat, or both (see LAYOUT).
        local outOfCombat, inCombatToo = db.buttons[key], ns.ShowsInCombat(key)
        local hidden = entry ~= nil and HiddenWhileOn(key, entry.itemID)
        button.hiddenWhileOn = hidden
        -- Camp gear: not where you can't camp. Dungeons and raids, and
        -- cities and inns, which the game only tells apart as "resting".
        if kind.outdoors and db.campOutdoorsOnly and (IsInInstance() or IsResting()) then hidden = true end
        local show = ns.IsAvailable(key) and (outOfCombat or inCombatToo) and (entry ~= nil or not db.hideEmpty)
            and not hidden or false
        button:SetAttribute("fp-enabled", show)
        button:SetAttribute("fp-outofcombat", outOfCombat and true or false)
        button:SetAttribute("fp-incombat", inCombatToo and true or false)
        bar:SetFrameRef("button" .. i, button)
        if show and outOfCombat then shownOut = shownOut + 1 end
        if show and inCombatToo then shownIn = shownIn + 1 end
    end

    -- Rows of perRow buttons; the last one may be shorter. Sized for
    -- whichever is more, in or out of combat, so dragging and the fade's
    -- hover cover every button.
    local shown = math.max(shownOut, shownIn)
    local perRow = math.max(1, db.perRow)
    local columns = math.max(1, math.min(shown, perRow))
    local rows = math.max(1, math.ceil(shown / perRow))
    local along = columns * (size + spacing) - spacing
    local across = rows * (size + spacing) - spacing
    local horizontal, vertical, side = Shape()
    if horizontal then
        bar:SetSize(along, across)
    else
        bar:SetSize(across, along)
    end
    bar:SetAttribute("fp-size", size)
    bar:SetAttribute("fp-spacing", spacing)
    bar:SetAttribute("fp-perrow", perRow)
    bar:SetAttribute("fp-horizontal", horizontal)
    bar:SetAttribute("fp-corner", vertical .. side)
    bar:SetAttribute("fp-xsign", side == "LEFT" and 1 or -1)
    bar:SetAttribute("fp-ysign", vertical == "TOP" and -1 or 1)
    bar:SetAttribute("fp-count", #ns.Order())
    bar:Execute(LAYOUT)
    if not moving then ApplyPosition() end -- after sizing: it depends on the size

    if not stateDriver then
        -- From now on the game runs LAYOUT whenever combat starts or ends.
        bar:SetAttribute("_onstate-combat", LAYOUT)
        RegisterStateDriver(bar, "combat", "[combat] combat; normal")
        stateDriver = true
    end
end

-- Runs while "Fade out of combat" is on.
local fader = CreateFrame("Frame")
fader:Hide()

local function FadeTarget()
    if InCombatLockdown() or not ns.account.locked then return 1 end
    if bar:IsMouseOver(8, -8, -8, 8) then return 1 end
    if (picker and picker:IsShown()) or (flyout and flyout:IsShown()) or (ns.TourShowing and ns.TourShowing())
        or (ns.KeyBindingShowing and ns.KeyBindingShowing())
        or (FannyPackFrame and FannyPackFrame:IsShown()) then
        return 1
    end
    return 0
end

local function SetVisibility(value)
    if value == visibility then return end
    visibility = value
    for _, button in pairs(buttons) do ApplyAlpha(button) end
end

fader:SetScript("OnUpdate", function(_, elapsed)
    local target = FadeTarget()
    if target > visibility then
        SetVisibility(math.min(target, visibility + elapsed * 6)) -- in quickly
    elseif target < visibility then
        SetVisibility(math.max(target, visibility - elapsed * 2)) -- out gently
    end
end)

-- Starts or stops fading as the setting says. instant: jump to fully shown.
function ns.UpdateFade(instant)
    if not bar then return end
    fader:SetShown(ns.db.fadeOutOfCombat)
    if instant or not ns.db.fadeOutOfCombat then SetVisibility(1) end
end

------------------------------------------------------------------------
-- The camp gear row
------------------------------------------------------------------------

-- A click on the Camp gear button opens a row beside it with a button for
-- each camp item in your bags. Its buttons are secure like the bar's, so
-- the row only opens out of combat, and closes when a fight starts (you
-- can't camp in one anyway).
local FLYOUT_PADDING = 4

-- Icon, count and cooldown of a button in the row. Safe in combat.
local function UpdateSlot(slot)
    local count = GetItemCount(slot.itemID)
    slot.icon:SetTexture(select(5, C_Item.GetItemInfoInstant(slot.itemID)))
    UpdateCooldown(slot)
    slot.icon:SetDesaturated(count == 0 or slot.coolingDown)
    slot.count:SetText(count > 1 and count or "")
    slot.count:SetShown(not slot.coolingDown)
end

local function UpdateFlyout()
    if not (flyout and flyout:IsShown()) then return end
    for _, slot in ipairs(flyout.slots) do
        if slot:IsShown() then UpdateSlot(slot) end
    end
end

local function CreateFlyout()
    flyout = CreateFrame("Frame", "FannyPackFlyout", UIParent)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetClampedToScreen(true)
    flyout:EnableMouse(true)
    ns.Rounded(flyout, "BACKGROUND", C.bg)
    ns.Rounded(flyout, "BORDER", C.windowBorder, "rounded-border")
    flyout.slots = {}
    flyout:Hide()

    tinsert(UISpecialFrames, "FannyPackFlyout") -- Escape closes it
    -- A click anywhere else closes it too.
    flyout:SetScript("OnShow", function(self)
        pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    flyout:SetScript("OnHide", function(self)
        pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    flyout:SetScript("OnEvent", function(self)
        if InCombatLockdown() then return end
        if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
            self:Hide()
        end
    end)
end

local function GetSlot(i)
    local slot = flyout.slots[i]
    if slot then return slot end
    slot = CreateFrame("Button", nil, flyout, "SecureActionButtonTemplate")
    slot.kind = flyout.owner.kind
    AddButtonParts(slot)
    slot:SetSize(ns.db.buttonSize, ns.db.buttonSize)
    if ns.SkinButton then ns.SkinButton(slot) end
    slot.cooldown:SetScript("OnCooldownDone", function() UpdateSlot(slot) end)
    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    flyout.slots[i] = slot
    return slot
end

-- Fills the row with the owner's items and places it: above the button on
-- a bar that runs sideways, to its right on one that runs up or down.
-- False if there's nothing to show. Not in combat.
local function RefreshFlyout()
    if InCombatLockdown() then return false end
    local owner = flyout.owner
    local list = ns.ListFor(owner.kind.key)
    if #list == 0 then
        flyout:Hide()
        return false
    end
    local size, spacing = ns.db.buttonSize, ns.db.spacing
    local clickHalf = ClickHalf()
    for i, entry in ipairs(list) do
        local slot = GetSlot(i)
        slot.itemID = entry.itemID
        slot:SetAttribute("type1", "item")
        slot:SetAttribute("item1", "item:" .. entry.itemID)
        slot:RegisterForClicks(clickHalf)
        slot:SetSize(size, size)
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", FLYOUT_PADDING + (i - 1) * (size + spacing), -FLYOUT_PADDING)
        ApplyStyle(slot)
        if ns.FitSkin then ns.FitSkin(slot) end
        slot.hotkey:SetText("")
        UpdateSlot(slot)
        slot:Show()
    end
    for i = #list + 1, #flyout.slots do flyout.slots[i]:Hide() end
    flyout:SetSize(FLYOUT_PADDING * 2 + #list * (size + spacing) - spacing, FLYOUT_PADDING * 2 + size)
    flyout:ClearAllPoints()
    if ns.db.direction == "UP" or ns.db.direction == "DOWN" then
        flyout:SetPoint("LEFT", owner, "RIGHT", 6, 0)
    else
        flyout:SetPoint("BOTTOM", owner, "TOP", 0, 6)
    end
    return true
end

function ns.ToggleFlyout(button)
    if InCombatLockdown() then return end
    if not flyout then CreateFlyout() end
    if flyout:IsShown() and flyout.owner == button then
        flyout:Hide()
        return
    end
    if picker then picker:Hide() end
    GameTooltip:Hide()
    flyout.owner = button
    if RefreshFlyout() then flyout:Show() end
end

-- For the tour: the bar, its first button on show, and a glowing button.
function ns.BarFrame()
    return bar
end

-- The buttons on the bar now, in bar order (for hover key binding).
function ns.ShownButtons()
    local list = {}
    for _, key in ipairs(ns.Order()) do
        local button = buttons[key]
        if button and button:IsShown() then list[#list + 1] = button end
    end
    return list
end

function ns.FirstShownButton()
    for _, key in ipairs(ns.Order()) do
        local button = buttons[key]
        if button and button:IsShown() then return button end
    end
end

function ns.GlowingButton()
    for _, key in ipairs(ns.Order()) do
        local button = buttons[key]
        if button and button:IsShown() and button.glowing then return button end
    end
end

function ns.UpdateBar()
    if not bar then return end
    SecureUpdate()
    ns.UpdateFade()
    for _, button in pairs(buttons) do
        ApplyStyle(button)
        if ns.FitSkin then ns.FitSkin(button) end -- after a change of Button size
        UpdateLook(button)
        UpdateHotkey(button)
    end
    if picker and picker:IsShown() then ns.RefreshPicker() end
    if not InCombatLockdown() then
        if ns.UpdateMacros then ns.UpdateMacros() end
        -- Binding keys: the overlays follow the buttons.
        if ns.KeyBindingShowing and ns.KeyBindingShowing() then ns.StartKeyBinding() end
    end
    if flyout and flyout:IsShown() then
        -- Its button may have just gone, say on walking into an inn.
        if flyout.owner:IsShown() then RefreshFlyout() elseif not InCombatLockdown() then flyout:Hide() end
    end
end

------------------------------------------------------------------------
-- Moving the bar
------------------------------------------------------------------------

local function CreateMover()
    mover = CreateFrame("Frame", nil, bar)
    mover:SetPoint("TOPLEFT", -4, 4)
    mover:SetPoint("BOTTOMRIGHT", 4, -4)
    -- Above the buttons, so it gets the clicks, and above other frames (the
    -- player frame just below the bar), so all its arrows can be clicked.
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(bar:GetFrameLevel() + 20)
    ns.Rounded(mover, "BACKGROUND", { C.accent[1], C.accent[2], C.accent[3], 0.3 })
    ns.Rounded(mover, "BORDER", C.accent, "rounded-border")

    local label = ns.Text(mover, 12, C.text)
    label:SetPoint("BOTTOM", mover, "TOP", 0, 4)
    label:SetText("|cff5fb48eFanny|r Pack")

    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            ns.Refuse(L["You can't move the bar in combat."])
            return
        end
        GameTooltip:Hide()
        bar:StartMoving()
        moving = true
    end)
    mover:SetScript("OnDragStop", ns.StopMoving)
    mover:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" then ns.SetLocked(true) end
    end)
    -- Nudging: small arrows around the bar, and the arrow keys while the
    -- mouse is over it (only then, so they still walk otherwise). One
    -- pixel a step, ten with Shift.
    local function Nudge(dx, dy)
        local step = IsShiftKeyDown() and 10 or 1
        ns.NudgeBar(dx * step, dy * step)
    end
    local KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
    mover:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local direction = KEYS[key]
        self:SetPropagateKeyboardInput(direction == nil)
        if direction then
            Nudge(direction[1], direction[2])
            -- Let every other key through again (it can't change in combat).
            C_Timer.After(0, function()
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end)
        end
    end)
    local arrows = {}
    local function Hovered()
        if mover:IsMouseOver() then return true end
        for _, arrow in ipairs(arrows) do
            if arrow:IsMouseOver() then return true end
        end
        return false
    end
    local function KeysOn(on)
        if InCombatLockdown() then return end
        mover:EnableKeyboard(on)
        if on then mover:SetPropagateKeyboardInput(true) end
    end

    -- The arrows: the chevron points down, so it's turned for the others.
    local ARROWS = {
        { 0, 1, "BOTTOM", label, "TOP", 0, 1, nil, true },
        { 0, -1, "TOP", mover, "BOTTOM", 0, -2 },
        { -1, 0, "RIGHT", mover, "LEFT", -2, 0, -math.pi / 2 },
        { 1, 0, "LEFT", mover, "RIGHT", 2, 0, math.pi / 2 },
    }
    for _, info in ipairs(ARROWS) do
        local dx, dy, point, relativeTo, relativePoint, x, y, rotation, flip = unpack(info)
        local arrow = CreateFrame("Button", nil, mover)
        arrow:SetSize(18, 18)
        arrow:SetPoint(point, relativeTo, relativePoint, x, y)
        local bg = ns.Rounded(arrow, "BACKGROUND", C.bg)
        bg:SetAlpha(0.9)
        local icon = arrow:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(MEDIA .. "icon-chevron")
        icon:SetSize(12, 12)
        icon:SetPoint("CENTER")
        if flip then icon:SetTexCoord(0, 1, 1, 0) end
        if rotation then icon:SetRotation(rotation) end
        ns.SetColor(icon, C.accent)
        -- Held down, it keeps going after a moment.
        local held, wait = false, 0
        arrow:SetScript("OnMouseDown", function()
            Nudge(dx, dy)
            held, wait = true, 0.4
        end)
        arrow:SetScript("OnMouseUp", function() held = false end)
        arrow:SetScript("OnUpdate", function(_, elapsed)
            if not held then return end
            wait = wait - elapsed
            if wait <= 0 then
                Nudge(dx, dy)
                wait = 0.05
            end
        end)
        arrow:SetScript("OnEnter", function(self)
            ns.SetColor(icon, C.text)
            KeysOn(true)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Move one pixel"], 1, 1, 1)
            GameTooltip:AddLine(L["Hold to keep moving, Shift for 10 pixels. The arrow keys work too while the mouse is over the bar."],
                0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        arrow:SetScript("OnLeave", function()
            ns.SetColor(icon, C.accent)
            held = false
            GameTooltip:Hide()
            if not Hovered() then KeysOn(false) end
        end)
        arrows[#arrows + 1] = arrow
    end

    mover:SetScript("OnEnter", function(self)
        KeysOn(true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Fanny Pack", 1, 1, 1)
        GameTooltip:AddLine(L["Drag to move the bar, or use the arrows or your arrow keys for one pixel at a time (Shift: 10). Right-click to lock it."],
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if not Hovered() then KeysOn(false) end
    end)
    mover:Hide()
end

-- Moves the bar a few pixels (x right, y up), from the unlocked bar's
-- arrows and arrow keys. Not in combat.
function ns.NudgeBar(dx, dy)
    local x, y = ns.GetPosition()
    if not x then return end
    if ns.SetPosition(x + dx, y + dy) and ns.RefreshWindow then ns.RefreshWindow() end
end

function ns.StopMoving()
    if not moving then return end
    moving = false
    bar:StopMovingOrSizing()
    SavePosition()
    ApplyPosition()
    if ns.RefreshWindow then ns.RefreshWindow() end -- the X and Y in the options
end

-- Returns true if the change was made.
function ns.SetLocked(locked)
    ns.account.locked = locked and true or false
    if mover then
        if ns.account.locked then ns.StopMoving() end
        mover:SetShown(not ns.account.locked)
    end
    if ns.RefreshWindow then ns.RefreshWindow() end
    return true
end

------------------------------------------------------------------------
-- Item list (right-click a button)
------------------------------------------------------------------------

local function GetRow(i)
    local row = picker.rows[i]
    if row then return row end

    row = CreateFrame("Button", nil, picker)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 4, -30 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -4, -30 - (i - 1) * ROW_HEIGHT)

    row.highlight = ns.Rounded(row, "BACKGROUND", C.controlHover)
    row.highlight:Hide()

    row.mark = row:CreateTexture(nil, "ARTWORK") -- the item the button uses now
    row.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    row.mark:SetSize(3, 14)
    row.mark:SetPoint("LEFT", 3, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 12, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = ns.Text(row, 13, C.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetWordWrap(false)

    row.count = ns.Text(row, 12, C.muted)
    row.count:SetJustifyH("RIGHT")

    -- A small x on each item: hides it from every button (see ns.SetHidden).
    row.hide = CreateFrame("Button", nil, row)
    row.hide:SetSize(20, 20)
    row.hide:SetPoint("RIGHT", -6, 0)
    row.hide.icon = row.hide:CreateTexture(nil, "ARTWORK")
    row.hide.icon:SetTexture(MEDIA .. "icon-close")
    row.hide.icon:SetSize(10, 10)
    row.hide.icon:SetPoint("CENTER")
    ns.SetColor(row.hide.icon, C.muted)
    row.hide:SetScript("OnEnter", function(self)
        ns.SetColor(self.icon, C.text)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Hide"], 1, 1, 1)
        GameTooltip:AddLine(L["No button uses it until you show it again, under Hidden at the bottom of this list."],
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    row.hide:SetScript("OnLeave", function(self)
        ns.SetColor(self.icon, C.muted)
        GameTooltip:Hide()
    end)
    row.hide:SetScript("OnClick", function() ns.SetHidden(row.itemID, true) end)

    -- An item: use it on this button. A hidden one: show it again. Camp
    -- gear only lists its items (they're used from the row). A custom
    -- button's last row opens its card in the options.
    row:SetScript("OnClick", function(self)
        if self.edit then
            picker:Hide()
            ns.ShowCustomButton(picker.owner.kind.key)
        elseif self.unhide then
            ns.SetHidden(self.itemID, false)
        elseif not picker.owner.kind.flyout then
            ns.SetChoice(picker.owner.kind.key, self.itemID)
            picker:Hide()
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self.highlight:Show() end
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            if self.unhide then
                GameTooltip:AddLine(L["Hidden: click to show it again."], C.accent[1], C.accent[2], C.accent[3], true)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)
    row:SetMotionScriptsWhileDisabled(true)

    picker.rows[i] = row
    return row
end

local FOOTER_HEIGHT = 32
local PREFER_HEIGHT = 32

-- A small - or + button for the low-stock limit.
local function StepButton(parent, label, delta)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(20, 20)
    local bg = ns.Rounded(button, "BACKGROUND", C.control)
    local text = ns.Text(button, 14, C.text)
    text:SetPoint("CENTER", 0, 1)
    text:SetText(label)
    button:SetScript("OnEnter", function() ns.SetColor(bg, C.controlHover) end)
    button:SetScript("OnLeave", function() ns.SetColor(bg, C.control) end)
    button:SetScript("OnClick", function()
        local key = picker.owner.kind.key
        ns.SetLowStock(key, ns.LowStock(key) + delta)
    end)
    return button
end

local function CreatePicker()
    picker = CreateFrame("Frame", "FannyPackPicker", UIParent)
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    ns.Rounded(picker, "BACKGROUND", C.bg)
    ns.Rounded(picker, "BORDER", C.windowBorder, "rounded-border")

    picker.title = ns.Text(picker, 12, C.muted)
    picker.title:SetPoint("TOPLEFT", 14, -10)
    picker.rows = {}
    picker:Hide()

    -- Under the list: when the button's count turns red.
    local footer = CreateFrame("Frame", nil, picker)
    footer:SetHeight(FOOTER_HEIGHT)
    footer:SetPoint("BOTTOMLEFT", 4, 4)
    footer:SetPoint("BOTTOMRIGHT", -4, 4)
    local line = footer:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.06)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, 0)
    line:SetPoint("TOPRIGHT", -8, 0)
    footer.label = ns.Text(footer, 12, C.muted)
    footer.label:SetPoint("LEFT", 10, -1)
    footer.label:SetText(L["Warn when down to"])
    footer.plus = StepButton(footer, "+", 1)
    footer.plus:SetPoint("RIGHT", -6, -1)
    footer.value = ns.Text(footer, 13, C.text)
    footer.value:SetWidth(30)
    footer.value:SetJustifyH("CENTER")
    footer.value:SetPoint("RIGHT", footer.plus, "LEFT", -2, 0)
    footer.minus = StepButton(footer, "-", -1)
    footer.minus:SetPoint("RIGHT", footer.value, "LEFT", -2, 0)
    picker.footer = footer

    -- Above that: which item the automatic pick prefers.
    local prefer = CreateFrame("Frame", nil, picker)
    prefer:SetHeight(PREFER_HEIGHT)
    prefer:SetPoint("BOTTOMLEFT", footer, "TOPLEFT")
    prefer:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT")
    local preferLine = prefer:CreateTexture(nil, "ARTWORK")
    preferLine:SetColorTexture(1, 1, 1, 0.06)
    preferLine:SetHeight(1)
    preferLine:SetPoint("TOPLEFT", 8, 0)
    preferLine:SetPoint("TOPRIGHT", -8, 0)
    local preferLabel = ns.Text(prefer, 12, C.muted)
    preferLabel:SetPoint("LEFT", 10, -1)
    preferLabel:SetText(L["Use up low-level ones first"])
    prefer.toggle = ns.CreateToggle(prefer, function()
        return picker.owner and ns.db.preferLow[picker.owner.kind.key] or false
    end, function(value)
        ns.SetPreferLow(picker.owner.kind.key, value)
    end)
    prefer.toggle:SetPoint("RIGHT", -6, -1)
    picker.prefer = prefer

    tinsert(UISpecialFrames, "FannyPackPicker") -- Escape closes it

    -- A click anywhere else closes it too.
    picker:SetScript("OnShow", function(self)
        pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    picker:SetScript("OnHide", function(self)
        pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    picker:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
            self:Hide()
        end
    end)
end

function ns.RefreshPicker()
    local kind = picker.owner.kind
    local list = ns.ListFor(kind.key)
    local chosen = ns.charDB.chosen[kind.key]
    local inUse = ns.ItemFor(kind.key)
    local usingChoice = chosen and inUse and inUse.itemID == chosen
    picker.title:SetText(kind.name:upper())

    local count, width = 0, picker.title:GetStringWidth() + 28
    -- mode: "item" (has the hide x), "hidden" (click to show it again) or
    -- "edit" (a custom button's items in the options).
    local function Add(itemID, icon, name, countText, enabled, selected, mode)
        count = count + 1
        local row = GetRow(count)
        row.itemID = itemID
        row.unhide = mode == "hidden"
        row.edit = mode == "edit"
        row.hide:SetShown(mode == "item")
        row.count:ClearAllPoints()
        if mode == "item" then
            row.count:SetPoint("RIGHT", row.hide, "LEFT", -2, 0)
        else
            row.count:SetPoint("RIGHT", -10, 0)
        end
        row.icon:SetTexture(icon)
        row.icon:SetDesaturated(mode == "hidden")
        row.icon:SetShown(icon ~= nil)
        row.name:ClearAllPoints()
        if icon then
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        else
            row.name:SetPoint("LEFT", 12, 0)
        end
        row.name:SetText(name)
        row.count:SetText(countText)
        row.mark:SetShown(selected)
        row:SetEnabled(enabled)
        row:Show()
        local rowWidth = (icon and 40 or 12) + row.name:GetStringWidth() + 24 + row.count:GetStringWidth() + 10
            + (mode == "item" and 22 or 0)
        width = math.max(width, rowWidth + 8)
    end

    -- Camp gear only lists its items, to hide some: they're used from its row.
    local listOnly = kind.flyout
    local hidden = ns.HiddenFor(kind.key)
    if kind.combo then
        Add(nil, nil, "|cff8a8b93" .. L["Uses your Food and Drink buttons' items."] .. "|r", "", false, false)
    elseif #list == 0 then
        Add(nil, nil, "|cff8a8b93" .. L["None in your bags."] .. "|r", "", false, false)
    else
        if not listOnly then
            Add(nil, list[1].icon, kind.custom and L["First in your list"] or L["Best available"], "", true,
                not usingChoice)
        end
        for _, entry in ipairs(list) do
            local name = entry.name
            local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality]
            if not entry.usable then
                name = "|cff808080" .. name .. "|r"
            elseif color and color.hex then
                name = color.hex .. name .. "|r"
            end
            Add(entry.itemID, entry.icon, name, entry.usable and entry.count or L["can't use"],
                entry.usable and not listOnly, usingChoice and entry.itemID == chosen, "item")
        end
    end
    if #hidden > 0 then
        Add(nil, nil, "|cff8a8b93" .. L["Hidden"]:upper() .. "|r", "", false, false)
        for _, entry in ipairs(hidden) do
            Add(entry.itemID, entry.icon, "|cff808080" .. entry.name .. "|r", L["show"], true, false, "hidden")
        end
    end
    if kind.custom then
        local green = ("|cff%02x%02x%02x"):format(C.accent[1] * 255, C.accent[2] * 255, C.accent[3] * 255)
        Add(nil, nil, green .. L["Change its items..."] .. "|r", "", true, false, "edit")
    end
    for i = count + 1, #picker.rows do picker.rows[i]:Hide() end

    local lowStock = ns.LowStock(kind.key)
    picker.footer.value:SetText(lowStock > 0 and lowStock or L["off"])
    picker.footer.minus:SetEnabled(lowStock > 0)
    picker.footer.minus:SetAlpha(lowStock > 0 and 1 or 0.4)

    -- Eat & drink picks nothing itself: its items come from Food and Drink.
    -- Camp gear has neither a pick nor a count. Custom buttons go by your
    -- list, not by level.
    local noPrefer = kind.combo or listOnly or kind.custom
    picker.footer:SetShown(not listOnly)
    picker.prefer:SetShown(not noPrefer)
    picker.prefer.toggle:Update(true)
    local preferHeight = noPrefer and 0 or PREFER_HEIGHT
    local footerHeight = listOnly and 0 or FOOTER_HEIGHT

    picker:SetSize(math.max(260, width), 30 + count * ROW_HEIGHT + 6 + preferHeight + footerHeight)
    picker:ClearAllPoints()
    if ns.db.direction == "UP" or ns.db.direction == "DOWN" then
        picker:SetPoint("TOPLEFT", picker.owner, "TOPRIGHT", 8, 4) -- beside a vertical bar
    else
        picker:SetPoint("BOTTOMLEFT", picker.owner, "TOPLEFT", -4, 8)
    end
end

function ns.TogglePicker(button)
    if not picker then CreatePicker() end
    if flyout and flyout:IsShown() and not InCombatLockdown() then flyout:Hide() end
    if picker:IsShown() and picker.owner == button then
        picker:Hide()
        return
    end
    GameTooltip:Hide()
    picker.owner = button
    ns.RefreshPicker()
    picker:Show()
end

------------------------------------------------------------------------
-- Creating the bar, and events
------------------------------------------------------------------------

function ns.CreateBar()
    if bar then return end
    if InCombatLockdown() then
        createAfterCombat = true -- logged in or reloaded mid-fight
        return
    end
    bar = CreateFrame("Frame", "FannyPackBar", UIParent, "SecureHandlerStateTemplate")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    if bar.SetDontSavePosition then bar:SetDontSavePosition(true) end -- saved by us instead
    for _, kind in ipairs(ns.KINDS) do
        buttons[kind.key] = CreateItemButton(kind)
    end
    CreateMover()
    mover:SetShown(not ns.account.locked)

    -- After Edit Mode the player frame may be somewhere else, with more or
    -- less room above it.
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnHide", function() ns.UpdateBar() end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("CVAR_UPDATE") -- "Cast action keybinds on key down" changed
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_UPDATE_RESTING") -- into or out of a city or inn, for the Camp gear button
events:RegisterUnitEvent("UNIT_PET", "player")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player") -- weapons swapped, stones and oils on or off
pcall(events.RegisterEvent, events, "WEAPON_ENCHANT_CHANGED")
-- A stone or oil wearing off doesn't always send an event, and Well Fed
-- running low sends none, so look now and then.
-- Buffs come, go and start running out without the bags changing, so check
-- whether a "Hide while on" button should appear or go, and rearrange the
-- bar if so. Not in combat, when the buttons can't change.
local function CheckHideWhileOn()
    if not bar or InCombatLockdown() or not next(ns.db.hideWhileOn) then return end
    for key, button in pairs(buttons) do
        local entry = ns.ItemFor(key)
        local hidden = entry ~= nil and HiddenWhileOn(key, entry.itemID)
        -- An elixir or scroll button may also switch to one that isn't on you.
        local switched = REMINDER_OF[key] and entry and entry.itemID ~= button.itemID
        if hidden ~= (button.hiddenWhileOn or false) or switched then
            ns.UpdateBar()
            return
        end
    end
end

-- Cures are only armed while you have something to cure (see
-- SecureUpdate): look again when your debuffs change. Not in combat.
local function CheckCureLocks()
    if not bar or InCombatLockdown() then return end
    for _, button in pairs(buttons) do
        local cure = button.kind.cure
        local has = cure and button.itemID and HasDebuff(cure)
        if has ~= nil and (button.locked or false) == has then
            ns.UpdateBar()
            return
        end
    end
end

C_Timer.NewTicker(10, function()
    if not bar then return end
    for _, button in pairs(buttons) do UpdateLook(button) end
    CheckHideWhileOn()
end)

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if picker and picker:IsShown() and not ns.db.buttons[picker.owner.kind.key] then
            picker:Hide() -- its button only shows in combat
        end
        if createAfterCombat then
            createAfterCombat = false
            ns.CreateBar()
            ns.Scan()
            ns.UpdateBar()
        else
            -- Usability and counts may have changed mid-fight.
            ns.QueueScan()
        end
    elseif event == "CVAR_UPDATE" or event == "UPDATE_BINDINGS" then
        ns.UpdateBar()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The player frame has its final place now, and EllesmereUI's exists
        -- if it replaces the game's: line up with it again. Into or out of
        -- a dungeon, for the Camp gear button, too.
        if bar then ns.UpdateBar() end
    elseif event == "PLAYER_UPDATE_RESTING" then
        if bar then ns.UpdateBar() end
    elseif event == "UNIT_PET" then
        -- The pet frame is placed now, so its exact spot is known.
        if bar and not ns.db.position then ns.UpdateBar() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        ns.UpdateFade(true) -- show the bar at once when a fight starts
        if bar then
            for _, button in pairs(buttons) do UpdateLook(button) end -- no reminders in a fight
        end
        if bar then ns.StopMoving() end -- in case combat starts mid-drag
        -- No arrow-key nudging in a fight: every key goes to the game.
        if mover and not InCombatLockdown() then
            mover:SetPropagateKeyboardInput(true)
            mover:EnableKeyboard(false)
        end
        if flyout then flyout:Hide() end -- its buttons can't change in a fight
        -- Arm the cures for the fight while the buttons can still change
        -- (combat lockdown starts just after this event).
        local locked = false
        for _, button in pairs(buttons) do locked = locked or button.locked end
        if locked and not InCombatLockdown() then SecureUpdate() end
        if picker and picker:IsShown() and not ns.ShowsInCombat(picker.owner.kind.key) then
            picker:Hide() -- its button is about to disappear
        end
    elseif bar then
        -- Cooldowns, Recently Bandaged, and Well Fed and weapon stones for the reminders.
        for _, button in pairs(buttons) do UpdateLook(button) end
        UpdateFlyout()
        CheckCureLocks()
        CheckHideWhileOn()
    end
end)
