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
local GLOW_COLOR = { 0.94, 0.69, 0.24 } -- the gold of the logo's ring

local NUMBER_FONT = NumberFontNormal and NumberFontNormal:GetFont() or STANDARD_TEXT_FONT
local countdownFont = CreateFont("FannyPackCountdownFont") -- cooldown numbers, sized in ApplyStyle

local ROW_HEIGHT = 26 -- rows in the item list

local bar, mover, picker
local buttons = {} -- [kind key] = button
local pending = false -- a change to the buttons is waiting for combat to end
local createAfterCombat = false
local moving = false
local inCombat = false -- from the combat events, which come just before the lockdown starts
local stateDriver = false -- the combat snippet is hooked up

-- Places the shown buttons one after another from the bar's first-button
-- corner, in order, wrapping to a new row after fp-perrow buttons and
-- skipping food and drink in combat. Runs in the game's secure environment,
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
        if button:GetAttribute("fp-enabled") and not (inCombat and button:GetAttribute("fp-eating")) then
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

local function KindIcon(kind)
    return select(5, C_Item.GetItemInfoInstant(kind.icon))
end

------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------

-- Classes with a pet frame under the player frame.
local PET_CLASSES = { HUNTER = true, WARLOCK = true }
local GAP = 6 -- between the player frame (or what hangs under it) and the bar

-- How far the pet frame's bottom is below the player frame's top, in
-- screen pixels, once known.
local petFrameDepth

local function ScreenTop(region)
    local top = region and region.GetTop and region:GetTop()
    return top and top * region:GetEffectiveScale()
end

local function ScreenBottom(region)
    local bottom = region and region.GetBottom and region:GetBottom()
    return bottom and bottom * region:GetEffectiveScale()
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
    local bottom = ScreenBottom(PetFrame)
    if bottom then
        petFrameDepth = frameTop - bottom
    elseif not petFrameDepth and PetFrame then
        local point, relativeTo, relativePoint, _, y = PetFrame:GetPoint(1)
        local frameBottom = PlayerFrame:GetBottom()
        if point and relativeTo == PlayerFrame and frameBottom then
            local anchor = (frameBottom + PlayerFrame:GetHeight() * PointHeight(relativePoint))
                * PlayerFrame:GetEffectiveScale()
            local petBottom = anchor + (y - PetFrame:GetHeight() * PointHeight(point)) * PetFrame:GetEffectiveScale()
            petFrameDepth = frameTop - petBottom
        end
    end
    return petFrameDepth and frameTop - petFrameDepth
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
    local db = ns.db
    local size = db.buttonSize
    local scale = PlayerFrame:GetEffectiveScale()
    local frameLeft, frameTop = PlayerFrame:GetLeft(), PlayerFrame:GetTop()
    if not (frameLeft and frameTop) then return 40, GAP + size end
    frameLeft, frameTop = frameLeft * scale, frameTop * scale
    local barScale = bar:GetEffectiveScale()

    -- Forever's player frame is the newer, retail-style one: its portrait
    -- and bars have no global names, but the frame keeps them as fields.
    local portrait = PlayerFrame.portrait
    local healthBar = PlayerFrame.healthbar
    local manaBar = PlayerFrame.manabar
    local name = PlayerName

    local x
    if db.direction == "LEFT" then
        local bars = manaBar or healthBar
        local right = bars and bars:GetRight()
        right = right and right * bars:GetEffectiveScale() or PlayerFrame:GetRight() * scale
        x = (right - frameLeft) / barScale - size
    else
        local left = portrait and portrait:GetLeft()
        left = left and left * portrait:GetEffectiveScale() or frameLeft
        x = (left - frameLeft) / barScale
    end

    -- Above: just over the highest part of the frame you can see.
    local highest
    local parts = { name, healthBar, manaBar } -- any may be missing
    for i = 1, 3 do
        local top = ScreenTop(parts[i])
        if top and (not highest or top > highest) then highest = top end
    end
    local portraitTop = ScreenTop(portrait) -- includes its round border
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
    Consider(ScreenBottom(manaBar))
    Consider(ScreenBottom(portrait))
    if PlayerLevelText and PlayerLevelText:GetTop() then
        -- The level sits in a round badge that reaches below the text.
        local middle = (PlayerLevelText:GetTop() + PlayerLevelText:GetBottom()) / 2
        Consider((middle - 15) * PlayerLevelText:GetEffectiveScale())
    end
    if PET_CLASSES[select(2, UnitClass("player"))] then Consider(PetFrameBottom(frameTop)) end
    lowest = lowest or frameTop - 100 * scale
    local castBar = AttachedCastBar()
    if castBar then
        -- It hangs under all of that, with its spell name below it.
        lowest = lowest - (castBar:GetHeight() + 14) * castBar:GetEffectiveScale()
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
-- the player frame is moved in Edit Mode), otherwise from the screen's
-- bottom left. Without one, the bar is at its default spot.
local function ApplyPosition()
    local saved = ns.db.position
    if saved and saved.frame == "player" and PlayerFrame then
        PlaceFirstButton(PlayerFrame, "TOPLEFT", saved.x, saved.y)
    elseif saved and saved.frame == "screen" then
        PlaceFirstButton(UIParent, "BOTTOMLEFT", saved.x, saved.y)
    elseif PlayerFrame then
        PlaceFirstButton(PlayerFrame, "TOPLEFT", DefaultOffset())
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

    local frameLeft = ns.db.attached and PlayerFrame and PlayerFrame:GetLeft()
    if frameLeft then
        local ratio = PlayerFrame:GetEffectiveScale() / bar:GetEffectiveScale()
        ns.db.position = { frame = "player", x = x - frameLeft * ratio, y = y - PlayerFrame:GetTop() * ratio }
    else
        ns.db.position = { frame = "screen", x = x, y = y }
    end
end

function ns.ResetPosition()
    if InCombatLockdown() then
        ns.Print(L["You can't move the bar in combat."])
        return false
    end
    ns.db.position = nil
    if bar then
        ApplyPosition()
        if not ns.db.attached then SavePosition() end -- the default spot, pinned to the screen
    end
    return true
end

-- Attaches the bar to the player frame or pins it to the screen. The bar
-- stays where it is; only what it's attached to changes.
function ns.SetAttached(attached)
    if InCombatLockdown() then
        ns.Print(L["You can't move the bar in combat."])
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

-- The Recently Bandaged debuff on you: its duration and when it ends.
local function RecentlyBandaged()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(RECENTLY_BANDAGED)
        if aura then return aura.duration, aura.expirationTime end
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

local function HasBuff(spellID, englishName)
    local name = ns.SpellName(spellID) or englishName
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        return C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL") ~= nil
    end
    return AuraUtil and AuraUtil.FindAuraByName and AuraUtil.FindAuraByName(name, "player", "HELPFUL") ~= nil
end

local WEAPON = Enum.ItemClass and Enum.ItemClass.Weapon or 2

local function HoldsWeapon(slot)
    local itemID = GetInventoryItemID("player", slot)
    return itemID ~= nil and select(6, C_Item.GetItemInfoInstant(itemID)) == WEAPON
end

-- True while the weapon in the slot (16 main hand, 17 off-hand) has no
-- stone, oil, poison or other temporary enchant on it. A shield or
-- held-in-off-hand item isn't a weapon.
local function WeaponNeedsSomething(slot)
    if not HoldsWeapon(slot) then return false end
    local hasMainHand, _, _, _, hasOffHand = GetWeaponEnchantInfo()
    if slot == 16 then return not hasMainHand end
    return not hasOffHand
end

-- Reminders: a soft, slowly pulsing glow on buff food while you aren't Well
-- Fed (or eating already), and on weapon stones and oils while a weapon has
-- none on it. Only out of combat, and only when you carry some.
local function WantsGlow(button, empty)
    if empty or inCombat or InCombatLockdown() then return false end
    local key = button.kind.key
    if key == "buffFood" then
        return ns.db.buffFoodGlow and not HasBuff(WELL_FED, "Well Fed") and not HasBuff(EATING, "Food")
    elseif key == "weapon" then
        return ns.db.weaponGlow and (WeaponNeedsSomething(16) or WeaponNeedsSomething(17))
    elseif button.kind.slot then -- poisons: their own hand
        return ns.db.weaponGlow and WeaponNeedsSomething(button.kind.slot)
    end
    return false
end

local function UpdateGlow(button, empty)
    local show = WantsGlow(button, empty)
    if show and not button.glow:IsShown() then
        button.glow:Show()
        button.pulse:Play()
    elseif not show and button.glow:IsShown() then
        button.pulse:Stop()
        button.glow:Hide()
    end
end

-- The size of one screen pixel in a frame's units, so borders stay crisp
-- and equally thin at any UI scale.
local function PixelSize(frame)
    local _, height = GetPhysicalScreenSize()
    if not height or height == 0 then return 1 end
    return 768 / height / frame:GetEffectiveScale()
end

-- Shape and border. Safe in combat.
local function ApplyStyle(button)
    local db = ns.db
    local maskFile = SHAPE_MASKS[db.shape]
    local border = BORDERS[db.border]

    -- The border is the button's shape in the border colour, behind the icon.
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

    -- The mask cuts the icon, highlight and pressed look to shape.
    local shaped = { button.icon, button:GetHighlightTexture(), button:GetPushedTexture() }
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
    button.cooldown:SetSwipeTexture(maskFile and MEDIA .. maskFile or "Interface\\Buttons\\WHITE8x8")
    button.cooldown:SetSwipeColor(0, 0, 0, 0.75)
    if button.cooldown.SetUseCircularEdge then button.cooldown:SetUseCircularEdge(db.shape == "round") end

    -- Text sized to the button, outlined to read on any background.
    local size = db.buttonSize
    button.count:SetFont(NUMBER_FONT, math.max(9, math.floor(size * 0.42 + 0.5)), "OUTLINE")
    button.hotkey:SetFont(NUMBER_FONT, math.max(9, math.floor(size * 0.42 + 0.5)), "OUTLINE")
    button.hotkey:SetTextColor(1, 1, 1)
    countdownFont:SetFont(NUMBER_FONT, math.max(10, math.floor(size * 0.5 + 0.5)), "OUTLINE")
    if button.cooldown.SetCountdownFont then button.cooldown:SetCountdownFont("FannyPackCountdownFont") end

    button.glow:SetTexture(MEDIA .. "glow-" .. db.shape)
    button.glow:SetSize(db.buttonSize * 2, db.buttonSize * 2) -- the button covers its middle half
end

-- Short key names, like the action bars: SHIFT-1 becomes S1.
local KEY_ABBREVIATIONS = {
    { "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" }, { "META%-", "M" },
    { "MOUSEWHEELUP", "MwU" }, { "MOUSEWHEELDOWN", "MwD" }, { "BUTTON(%d+)", "M%1" },
    { "NUMPAD", "N" }, { "SPACE", "Sp" },
}

-- The key bound to a button (Bindings.xml), shown in its top right corner.
local function UpdateHotkey(button)
    local key = GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton")
    if key then
        for _, abbreviation in ipairs(KEY_ABBREVIATIONS) do
            key = key:gsub(abbreviation[1], abbreviation[2])
        end
    end
    button.hotkey:SetText(key or "")
end

-- Fade out of combat: how visible the bar is now, from 0 to 1. The fader
-- moves it towards 1 in combat or under the mouse, and towards 0 otherwise.
local visibility = 1

-- Empty buttons are dimmed; out of combat the whole bar fades, except a
-- glowing buff food button, so its reminder still shows.
local function ApplyAlpha(button)
    local alpha = button.empty and 0.4 or 1
    if not button.glow:IsShown() then alpha = alpha * visibility end
    button:SetAlpha(alpha)
end

-- Icon, count, fading, cooldown and glow. Safe in combat.
local function UpdateLook(button)
    local itemID = button.itemID
    local count = itemID and GetItemCount(itemID) or 0
    local empty = count == 0

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
    button.count:SetText(empty and "" or (count > 999 and "*" or count))
    button.count:SetShown(not coolingDown)
    button.hotkey:SetShown(not coolingDown)
    UpdateGlow(button, empty)
    ApplyAlpha(button)
end

local function ShowButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.itemID and GetItemCount(self.itemID) > 0 then
        GameTooltip:SetItemByID(self.itemID)
    else
        GameTooltip:SetText(self.kind.name, 1, 1, 1)
        GameTooltip:AddLine(L["None in your bags."], C.muted[1], C.muted[2], C.muted[3])
    end
    if self.kind.shiftSlot then
        GameTooltip:AddLine(L["Click to put it on your main hand weapon, Shift-click for your off-hand."],
            0.6, 0.6, 0.6, true)
    elseif self.kind.slot == 16 then
        GameTooltip:AddLine(L["Click to put it on your main hand weapon."], 0.6, 0.6, 0.6, true)
    elseif self.kind.slot == 17 then
        GameTooltip:AddLine(L["Click to put it on your off-hand weapon."], 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(L["Right-click to choose another item."], 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function CreateItemButton(kind)
    local button = CreateFrame("Button", ns.ButtonName(kind.key), bar, "SecureActionButtonTemplate")
    button.kind = kind
    button.usable = true

    -- Left-click uses the item. Right-click has no secure action, only
    -- the item list (PostClick). Which half of a click counts is set in
    -- SecureUpdate.
    if kind.slot then
        -- Stones, oils and poisons need a weapon to go on: use the item,
        -- then pick the weapon's slot (see SecureUpdate).
        button:SetAttribute("type1", "macro")
    else
        button:SetAttribute("type1", "item")
    end
    if kind.key == "bandage" then
        button:SetAttribute("unit1", "player") -- bandage yourself, even with a friend targeted
    end

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
    button.glow:SetBlendMode("ADD")
    button.glow:SetVertexColor(unpack(GLOW_COLOR))
    button.glow:Hide()
    button.pulse = button.glow:CreateAnimationGroup()
    button.pulse:SetLooping("BOUNCE")
    local fade = button.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.3)
    fade:SetToAlpha(0.85)
    fade:SetDuration(1.6)
    fade:SetSmoothing("IN_OUT")

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:GetHighlightTexture():SetAllPoints(button.icon)
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    button:GetPushedTexture():SetAllPoints(button.icon)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetDrawBling(false) -- its flash is square, also on round buttons
    if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(false) end
    button.cooldown:SetScript("OnCooldownDone", function() UpdateLook(button) end)

    -- The count goes on its own layer so the cooldown swipe doesn't cover it.
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    button.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    button.hotkey = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    button.hotkey:SetPoint("TOPRIGHT", -1, -1)

    ApplyStyle(button)

    button:SetScript("PostClick", function(self, mouseButton)
        if mouseButton == "RightButton" then ns.TogglePicker(self) end
    end)
    button:SetAttribute("fp-eating", false)
    button:SetAttribute("fp-enabled", false)
    button:SetScript("OnEnter", ShowButtonTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
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
    local shown = 0
    for i, key in ipairs(ns.Order()) do
        local button = buttons[key]
        local entry = ns.ItemFor(key)
        button.itemID = entry and entry.itemID
        button.usable = not entry or entry.usable
        local kind = button.kind
        if kind.slot then
            local use = entry and "/use item:" .. entry.itemID .. "\n/use "
            button:SetAttribute("macrotext1", use and use .. kind.slot or nil)
            if kind.shiftSlot then
                button:SetAttribute("shift-macrotext1", use and use .. kind.shiftSlot or nil)
            end
        else
            button:SetAttribute("item1", entry and ("item:" .. entry.itemID) or nil)
        end
        button:RegisterForClicks(clickHalf)
        button:SetSize(size, size)

        local show = ns.IsAvailable(key) and ns.charDB.buttons[key] and (entry ~= nil or not db.hideEmpty) or false
        button:SetAttribute("fp-enabled", show)
        button:SetAttribute("fp-eating", button.kind.eating and db.hideEatingInCombat or false)
        bar:SetFrameRef("button" .. i, button)
        if show then shown = shown + 1 end
    end

    -- Rows of perRow buttons; the last one may be shorter.
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
    if InCombatLockdown() or not ns.db.locked then return 1 end
    if bar:IsMouseOver(8, -8, -8, 8) then return 1 end
    if (picker and picker:IsShown()) or (FannyPackFrame and FannyPackFrame:IsShown()) then return 1 end
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

function ns.UpdateBar()
    if not bar then return end
    SecureUpdate()
    ns.UpdateFade()
    for _, button in pairs(buttons) do
        ApplyStyle(button)
        UpdateLook(button)
        UpdateHotkey(button)
    end
    if picker and picker:IsShown() then ns.RefreshPicker() end
end

------------------------------------------------------------------------
-- Moving the bar
------------------------------------------------------------------------

local function CreateMover()
    mover = CreateFrame("Frame", nil, bar)
    mover:SetPoint("TOPLEFT", -4, 4)
    mover:SetPoint("BOTTOMRIGHT", 4, -4)
    mover:SetFrameLevel(bar:GetFrameLevel() + 20) -- above the buttons, so it gets the clicks
    ns.Rounded(mover, "BACKGROUND", { C.accent[1], C.accent[2], C.accent[3], 0.3 })
    ns.Rounded(mover, "BORDER", C.accent, "rounded-border")

    local label = ns.Text(mover, 12, C.text)
    label:SetPoint("BOTTOM", mover, "TOP", 0, 4)
    label:SetText("|cff5fb48eFanny|r Pack")

    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            ns.Print(L["You can't move the bar in combat."])
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
    mover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Fanny Pack", 1, 1, 1)
        GameTooltip:AddLine(L["Drag to move the bar. Right-click to lock it."], 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", GameTooltip_Hide)
    mover:Hide()
end

function ns.StopMoving()
    if not moving then return end
    moving = false
    bar:StopMovingOrSizing()
    SavePosition()
    ApplyPosition()
end

-- Returns true if the change was made.
function ns.SetLocked(locked)
    ns.db.locked = locked and true or false
    if mover then
        if ns.db.locked then ns.StopMoving() end
        mover:SetShown(not ns.db.locked)
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
    row.count:SetPoint("RIGHT", -10, 0)
    row.count:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function(self)
        ns.SetChoice(picker.owner.kind.key, self.itemID)
        picker:Hide()
    end)
    row:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self.highlight:Show() end
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
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
    local function Add(itemID, icon, name, countText, enabled, selected)
        count = count + 1
        local row = GetRow(count)
        row.itemID = itemID
        row.icon:SetTexture(icon)
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
        width = math.max(width, rowWidth + 8)
    end

    if #list == 0 then
        Add(nil, nil, "|cff8a8b93" .. L["None in your bags."] .. "|r", "", false, false)
    else
        Add(nil, list[1].icon, L["Best available"], "", true, not usingChoice)
        for _, entry in ipairs(list) do
            local name = entry.name
            local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality]
            if not entry.usable then
                name = "|cff808080" .. name .. "|r"
            elseif color and color.hex then
                name = color.hex .. name .. "|r"
            end
            Add(entry.itemID, entry.icon, name, entry.usable and entry.count or L["can't use"],
                entry.usable, usingChoice and entry.itemID == chosen)
        end
    end
    for i = count + 1, #picker.rows do picker.rows[i]:Hide() end

    picker:SetSize(math.max(200, width), 30 + count * ROW_HEIGHT + 6)
    picker:ClearAllPoints()
    if ns.db.direction == "UP" or ns.db.direction == "DOWN" then
        picker:SetPoint("TOPLEFT", picker.owner, "TOPRIGHT", 8, 4) -- beside a vertical bar
    else
        picker:SetPoint("BOTTOMLEFT", picker.owner, "TOPLEFT", -4, 8)
    end
end

function ns.TogglePicker(button)
    if not picker then CreatePicker() end
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
    mover:SetShown(not ns.db.locked)

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
events:RegisterUnitEvent("UNIT_PET", "player")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player") -- weapons swapped, stones and oils on or off
pcall(events.RegisterEvent, events, "WEAPON_ENCHANT_CHANGED")
-- A stone or oil wearing off doesn't always send an event, so look now and then.
C_Timer.NewTicker(10, function()
    if bar and buttons.weapon then UpdateLook(buttons.weapon) end
end)

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
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
        -- The player frame has its final place now; line up with it again.
        if bar and not ns.db.position then ns.UpdateBar() end
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
        if picker and picker:IsShown() and picker.owner.kind.eating and ns.db.hideEatingInCombat then
            picker:Hide() -- its button is about to disappear
        end
    elseif bar then
        -- Cooldowns, Recently Bandaged, and Well Fed and weapon stones for the reminders.
        for _, button in pairs(buttons) do UpdateLook(button) end
    end
end)
