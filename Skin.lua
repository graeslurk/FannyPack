-- Masque support: with the Masque addon installed, Fanny Pack's buttons
-- (the bar, the camp gear row and the glow preview in the options) are a
-- Masque group called "Fanny Pack", and take the skin you pick for it in
-- Masque's options, like your action bars. While a skin is on, Fanny Pack
-- leaves the shape, border and cooldown shape to it (see ApplyStyle in
-- Bar.lua); turn the group off in Masque and Fanny Pack's own look is back.
--
-- The buttons are added as action buttons, with their parts named, so
-- Masque puts the count and the key where the action bars have them. Masque
-- makes the skin's frame (its "Normal" layer) itself.

local ADDON_NAME, ns = ...

local Masque = LibStub and LibStub("Masque", true)
local group
local skinned = {} -- [button] = true: in the group

-- The skin's frame on a button, if Masque made one (older Masque versions
-- may not offer the lookup).
local function SkinFrame(button)
    return group.GetLayer and group:GetLayer(button, "Normal") or nil
end

-- The Fanny Pack group, made the first time it's needed. nil without Masque.
local function Group()
    if group or not Masque then return group end
    group = Masque:Group("Fanny Pack")
    -- Turned off or on in Masque's options, or reset: Fanny Pack's own look
    -- comes back, or steps aside. After Masque has made its change.
    group:RegisterCallback(function(_, option, value)
        if option ~= "Disabled" and option ~= "Reset" then return end
        C_Timer.After(0, function()
            if option == "Disabled" and not value then
                -- Back on: the skin's frame, hidden while it was off (see
                -- ns.HideSkin), shows again before Masque paints it.
                for button in pairs(skinned) do
                    local normal = SkinFrame(button)
                    if normal then normal:Show() end
                    button.skinWidth = nil
                end
                group:ReSkin()
            end
            ns.UpdateBar()
            if ns.RefreshWindow then ns.RefreshWindow() end
        end)
    end)
    return group
end

-- Whether Masque skins Fanny Pack's buttons now: it's installed and the
-- group isn't turned off.
function ns.MasqueActive()
    local g = Group()
    return g ~= nil and not (g.db and g.db.Disabled)
end

-- Adds a button to the group (once). Its parts are the ones AddButtonParts
-- makes in Bar.lua.
function ns.SkinButton(button)
    if skinned[button] or not Group() then return end
    skinned[button] = true
    group:AddButton(button, {
        Icon = button.icon,
        Cooldown = button.cooldown,
        Count = button.count,
        HotKey = button.hotkey,
        Highlight = button:GetHighlightTexture(),
        Pushed = button:GetPushedTexture(),
    }, "Action", true)
end

-- A deleted custom button leaves the group.
function ns.UnskinButton(button)
    if not skinned[button] then return end
    skinned[button] = nil
    group:RemoveButton(button)
end

-- Whether this button wears the Masque skin right now.
function ns.Skinned(button)
    return skinned[button] ~= nil and ns.MasqueActive()
end

-- Masque sizes a skin to the button when it paints it, so a button that
-- changed size (the Button size setting) is painted again.
function ns.FitSkin(button)
    if not ns.Skinned(button) then return end
    local width = button:GetWidth()
    if width > 0 and button.skinWidth ~= width then
        button.skinWidth = width
        group:ReSkin(button)
    end
end

-- While the group is off, the skin's frame Masque made would sit over
-- Fanny Pack's own look: hidden until it's back on.
function ns.HideSkin(button)
    if not skinned[button] then return end
    local normal = SkinFrame(button)
    if normal then normal:Hide() end
end
