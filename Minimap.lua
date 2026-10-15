-- Minimap button: the Fanny Pack logo on the edge of the minimap. Click
-- it to open the window, drag it to move it around the minimap. The
-- tooltip shows how much of each kind you carry.

local ADDON_NAME, ns = ...
local L = ns.L

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local SIZE = 31 -- same as other minimap buttons
local ICON_SIZE = 20 -- fills the hole in the gold ring
local EDGE_OFFSET = 10 -- how far outside the minimap's edge the button sits

-- Which quarters of the minimap are round, for minimap addons that change
-- its shape (GetMinimapShape). Order: bottom-right, bottom-left, top-right,
-- top-left. In a square quarter the button follows the corner instead.
local SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local button

local function SetAngle(angle)
    local rad = math.rad(angle)
    local x, y = math.cos(rad), math.sin(rad)
    local quarter = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0)
    local shape = SHAPES[GetMinimapShape and GetMinimapShape() or "ROUND"] or SHAPES.ROUND
    local w = Minimap:GetWidth() / 2 + EDGE_OFFSET
    local h = Minimap:GetHeight() / 2 + EDGE_OFFSET
    if shape[quarter] then
        x, y = x * w, y * h
    else
        -- Push out along the diagonal, then flatten onto the square's edge.
        local diagonalW, diagonalH = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * diagonalW, w))
        y = math.max(-h, math.min(y * diagonalH, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging: follow the cursor around the minimap.
local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    SetAngle(ns.db.minimapAngle)
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Fanny Pack", 1, 1, 1)
    for _, kind in ipairs(ns.KINDS) do
        -- Shared lists (second elixir, off-hand poison) would repeat the first.
        if ns.IsAvailable(kind.key) and ns.charDB.buttons[kind.key] and not kind.list then
            local count = ns.CountKind(kind.key)
            if count > 0 then
                GameTooltip:AddDoubleLine(kind.name, count, 1, 0.82, 0, 1, 1, 1)
            else
                GameTooltip:AddDoubleLine(kind.name, L["none"], 1, 0.82, 0, 0.53, 0.54, 0.58)
            end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click to open the options. Drag to move this button."], 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function CreateButton()
    button = CreateFrame("Button", "FannyPackMinimapButton", Minimap)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    -- The game's own minimap button look: dark background, the icon, and
    -- the gold ring on top.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")

    -- The logo cropped to its teal disc, so only the disc shows inside the
    -- gold ring.
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "icon")
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function() ns.ToggleWindow() end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", FollowCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)

    SetAngle(ns.db.minimapAngle)
end

-- Updates the tooltip if it's showing.
function ns.RefreshMinimapButton()
    if button and button:IsShown() and GameTooltip:IsOwned(button) then ShowTooltip(button) end
end

function ns.SetMinimapButton(show)
    ns.db.minimapButton = show and true or false
    if show and not button then CreateButton() end
    if button then button:SetShown(show) end
    ns.RefreshMinimapButton()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    if ns.db.minimapButton then CreateButton() end
end)
