-- Fanny Pack options window: a dark, card-based window in the style of
-- Pocket Goblin, with the bar's settings and which buttons to show. The
-- colours and drawing helpers are shared with Bar.lua through ns.

local ADDON_NAME, ns = ...
local L = ns.L

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- The window lays its cards out in two columns when it's wide enough (the
-- bar and its look on the left, the buttons on the right), otherwise in
-- one. It can be resized, and scrolls when it's shorter than its cards.
local BAR_CARD_WIDTH = 500 -- natural widths, for the default size
local BUTTONS_CARD_WIDTH = 340
local SCROLLBAR = 14 -- room on the right for the scroll bar
local WIDTH = 20 + BAR_CARD_WIDTH + 16 + BUTTONS_CARD_WIDTH + 20 + SCROLLBAR
local TWO_COLUMNS = 20 + 420 + 16 + 320 + 20 -- the narrowest content that fits two columns
local MIN_WIDTH = 20 + 420 + 20 + SCROLLBAR -- one column
local MIN_HEIGHT = 320
local SCREEN_MARGIN = 40
local HEADER_HEIGHT = 72

local C = {
    bg = { 0.047, 0.05, 0.058, 0.97 },
    windowBorder = { 0.17, 0.17, 0.19, 1 },
    card = { 0.078, 0.081, 0.092, 1 },
    cardBorder = { 0.16, 0.165, 0.18, 1 },
    control = { 0.11, 0.114, 0.126, 1 },
    controlHover = { 0.15, 0.154, 0.168, 1 },
    controlBorder = { 0.24, 0.245, 0.265, 1 },
    accent = { 0.37, 0.71, 0.56, 1 }, -- the pack's green in the logo
    accentHover = { 0.47, 0.8, 0.65, 1 },
    text = { 0.92, 0.92, 0.93, 1 },
    muted = { 0.53, 0.54, 0.58, 1 },
    off = { 0.2, 0.205, 0.225, 1 },
    knobOff = { 0.78, 0.78, 0.82, 1 },
    white = { 1, 1, 1, 1 },
}

local window
local updaters = {} -- controls and texts refreshed by RefreshWindow

------------------------------------------------------------------------
-- Drawing helpers
------------------------------------------------------------------------

local function SetColor(texture, color)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- A rounded rectangle that keeps its corners at any size (texture slicing).
-- file is "rounded" (filled) or "rounded-border" (1px outline).
local function Rounded(parent, layer, color, file)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    if texture.SetTextureSliceMargins then
        texture:SetTexture(MEDIA .. (file or "rounded"))
        texture:SetTextureSliceMargins(8, 8, 8, 8)
        texture:SetTextureSliceMode(Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
        SetColor(texture, color)
    elseif file == "rounded-border" then
        texture:Hide() -- no slicing support: skip outlines rather than draw a blob
    else
        texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
    return texture
end

local function Icon(parent, name, size, color, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetTexture(MEDIA .. name)
    texture:SetSize(size, size)
    SetColor(texture, color)
    return texture
end

local function Text(parent, size, color, layer)
    local text = parent:CreateFontString(nil, layer or "ARTWORK")
    text:SetFont(FONT, size, "")
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetShadowColor(0, 0, 0, 0.6)
    text:SetShadowOffset(1, -1)
    text:SetJustifyH("LEFT")
    return text
end

ns.C, ns.SetColor, ns.Rounded, ns.Text = C, SetColor, Rounded, Text

local function PlayToggleSound(on)
    if SOUNDKIT then
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

------------------------------------------------------------------------
-- Controls
------------------------------------------------------------------------

-- Pill-shaped on/off switch whose knob slides across.
local function CreateToggle(parent, get, set)
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(48, 24)

    local track = toggle:CreateTexture(nil, "ARTWORK")
    track:SetTexture(MEDIA .. "pill")
    track:SetAllPoints()

    local knob = toggle:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(MEDIA .. "circle")
    knob:SetSize(18, 18)

    local pos = get() and 1 or 0
    local hovered = false

    local function paint()
        knob:SetPoint("LEFT", 3 + pos * 24, 0)
        local on = hovered and C.accentHover or C.accent
        local off = hovered and C.controlBorder or C.off
        track:SetVertexColor(Lerp(off[1], on[1], pos), Lerp(off[2], on[2], pos), Lerp(off[3], on[3], pos))
        knob:SetVertexColor(Lerp(C.knobOff[1], 1, pos), Lerp(C.knobOff[2], 1, pos), Lerp(C.knobOff[3], 1, pos))
    end

    local function animate(self, elapsed)
        local target = get() and 1 or 0
        local step = elapsed * 7
        if math.abs(target - pos) <= step then
            pos = target
            self:SetScript("OnUpdate", nil)
        else
            pos = pos + (target > pos and step or -step)
        end
        paint()
    end

    -- Slides to the current value, or jumps there when not animating.
    function toggle:Update(instant)
        if instant then
            if not self:GetScript("OnUpdate") then
                pos = get() and 1 or 0
                paint()
            end
        else
            self:SetScript("OnUpdate", animate)
        end
    end

    toggle:SetScript("OnClick", function(self)
        local value = not get()
        set(value)
        PlayToggleSound(value)
        self:Update()
    end)
    toggle:SetScript("OnEnter", function() hovered = true; paint() end)
    toggle:SetScript("OnLeave", function() hovered = false; paint() end)

    paint()
    updaters[#updaters + 1] = function() toggle:Update(true) end
    return toggle
end

-- Thin track with a coloured fill, a round knob and the value on the right.
local function CreateSlider(parent, minValue, maxValue, get, onChange, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width + 40, 24)

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width, 24)
    slider:SetPoint("LEFT")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetHitRectInsets(0, 0, -4, -4)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(C.off[1], C.off[2], C.off[3], 1)
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    fill:SetHeight(4)
    fill:SetPoint("LEFT")

    slider:SetThumbTexture(MEDIA .. "circle")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(16, 16)
    SetColor(thumb, C.white)

    local label = Text(holder, 15, C.text)
    label:SetPoint("RIGHT")
    label:SetJustifyH("RIGHT")

    local initializing = true
    slider:SetScript("OnValueChanged", function(_, newValue)
        local fraction = (newValue - minValue) / (maxValue - minValue)
        fill:SetWidth(math.max(1, 8 + fraction * (slider:GetWidth() - 16)))
        label:SetText(math.floor(newValue + 0.5))
        if not initializing then onChange(newValue) end
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta)
    end)
    slider:SetValue(get())
    initializing = false

    updaters[#updaters + 1] = function()
        initializing = true
        slider:SetValue(get())
        initializing = false
    end
    return holder
end

-- Rounded button. style: nil (dark outline) or "primary" (filled).
local BUTTON_STYLES = {
    primary = { C.accent, C.accentHover, C.white },
}

local function CreateButton(parent, label, width, style)
    local filled = BUTTON_STYLES[style]
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 32)

    local bg = Rounded(button, "BACKGROUND", filled and filled[1] or C.control)
    local border = Rounded(button, "BORDER", filled and filled[1] or C.controlBorder, "rounded-border")
    local text = Text(button, 13, filled and filled[3] or C.text)
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    text:SetText(label)
    if filled then text:SetShadowOffset(0, 0) end

    local hovered = false
    local function paint()
        if not button:IsEnabled() then
            SetColor(bg, C.control)
            SetColor(border, C.cardBorder)
            text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        elseif filled then
            SetColor(bg, hovered and filled[2] or filled[1])
            SetColor(border, hovered and filled[2] or filled[1])
            text:SetTextColor(filled[3][1], filled[3][2], filled[3][3])
        else
            SetColor(bg, hovered and C.controlHover or C.control)
            SetColor(border, C.controlBorder)
            text:SetTextColor(C.text[1], C.text[2], C.text[3])
        end
    end
    button:SetScript("OnEnable", paint)
    button:SetScript("OnDisable", paint)
    button:HookScript("OnEnter", function() hovered = true; paint() end)
    button:HookScript("OnLeave", function() hovered = false; paint() end)
    button:SetMotionScriptsWhileDisabled(true)
    paint()
    return button
end

-- A row of buttons, one per choice; the chosen one is filled.
-- choices: { { value = ..., label = ... }, ... }
local function CreateSegmented(parent, choices, get, set, itemWidth)
    itemWidth = itemWidth or 54
    local holder = CreateFrame("Frame", nil, parent)
    local items, x = {}, 0

    function holder:Update()
        local current = get()
        for _, item in ipairs(items) do
            local chosen = item.value == current
            if chosen then
                SetColor(item.bg, item.hovered and C.accentHover or C.accent)
                SetColor(item.border, item.hovered and C.accentHover or C.accent)
                item.text:SetTextColor(C.white[1], C.white[2], C.white[3])
            else
                SetColor(item.bg, item.hovered and C.controlHover or C.control)
                SetColor(item.border, C.controlBorder)
                item.text:SetTextColor(C.text[1], C.text[2], C.text[3])
            end
        end
    end

    for i, choice in ipairs(choices) do
        local item = CreateFrame("Button", nil, holder)
        item:SetSize(itemWidth, 28)
        item:SetPoint("LEFT", x, 0)
        x = x + itemWidth + 4
        item.value = choice.value
        item.bg = Rounded(item, "BACKGROUND", C.control)
        item.border = Rounded(item, "BORDER", C.controlBorder, "rounded-border")
        item.text = Text(item, 12, C.text)
        item.text:SetPoint("CENTER")
        item.text:SetJustifyH("CENTER")
        item.text:SetShadowOffset(0, 0)
        item.text:SetText(choice.label)
        item:SetScript("OnClick", function()
            set(choice.value)
            PlayToggleSound(true)
            holder:Update()
        end)
        item:SetScript("OnEnter", function() item.hovered = true; holder:Update() end)
        item:SetScript("OnLeave", function() item.hovered = false; holder:Update() end)
        items[i] = item
    end
    holder:SetSize(x - 4, 28)
    holder:Update()
    updaters[#updaters + 1] = function() holder:Update() end
    return holder
end

-- Small chevron button for moving a row up (towards the start) or down.
local function CreateArrow(parent, up, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(24, 24)
    local icon = Icon(button, "icon-chevron", 14, C.muted)
    icon:SetPoint("CENTER")
    if up then icon:SetTexCoord(0, 1, 1, 0) end -- the chevron points down; flip it

    local hovered = false
    local function paint()
        if not button:IsEnabled() then
            SetColor(icon, C.off)
        else
            SetColor(icon, hovered and C.text or C.muted)
        end
    end
    button:SetScript("OnEnter", function() hovered = true; paint() end)
    button:SetScript("OnLeave", function() hovered = false; paint() end)
    button:SetScript("OnEnable", paint)
    button:SetScript("OnDisable", paint)
    button:SetScript("OnClick", onClick)
    button:SetMotionScriptsWhileDisabled(true)
    paint()
    return button
end

-- Small rounded label, e.g. the version number.
local function CreateBadge(parent, color, background)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetHeight(20)
    Rounded(badge, "BACKGROUND", background)
    badge.text = Text(badge, 11, color)
    badge.text:SetPoint("CENTER")
    badge.text:SetShadowOffset(0, 0)
    function badge:SetText(text)
        self.text:SetText(text)
        self:SetWidth(self.text:GetStringWidth() + 18)
    end
    return badge
end

------------------------------------------------------------------------
-- Cards
------------------------------------------------------------------------

-- A rounded card with an uppercase title and an accent bar. Rows are added
-- with AddRow; LayoutCard stacks them and sizes the card.
local function CreateCard(parent, title, width)
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(width)
    Rounded(card, "BACKGROUND", C.card)
    Rounded(card, "BORDER", C.cardBorder, "rounded-border")

    local bar = card:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    bar:SetSize(3, 14)
    bar:SetPoint("TOPLEFT", 20, -22)

    local label = Text(card, 13, C.text)
    label:SetPoint("LEFT", bar, "RIGHT", 10, 0)
    label:SetText(title:upper())

    card.rows = {}
    return card
end

-- A row with a title, a description and a control on the right, or under
-- the text when stacked. makeControl(card) creates the control. Returns the
-- description text, so callers can change it.
local function AddRow(card, title, description, makeControl, stacked)
    local control = makeControl and makeControl(card)
    local titleText = Text(card, 14, C.text)
    titleText:SetText(title)
    local descText = Text(card, 12, C.muted)
    descText:SetText(description)
    descText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    card.rows[#card.rows + 1] = { title = titleText, desc = descText, control = control, stacked = stacked }
    return descText
end

-- startY: where the first row goes, for cards with other content on top.
local function LayoutCard(card, startY)
    local y = startY or -56
    for _, row in ipairs(card.rows) do
        local control = row.control
        local beside = control and not row.stacked
        local textWidth = card:GetWidth() - 40 - (beside and control:GetWidth() + 24 or 0)
        row.title:SetWidth(textWidth)
        row.desc:SetWidth(textWidth)
        local textHeight = row.title:GetStringHeight() + 4 + row.desc:GetStringHeight()
        local rowHeight
        row.title:ClearAllPoints()
        if row.stacked then
            rowHeight = textHeight + 10 + control:GetHeight()
            row.title:SetPoint("TOPLEFT", 20, y)
            control:ClearAllPoints()
            control:SetPoint("TOPLEFT", 20, y - textHeight - 10)
        else
            rowHeight = math.max(textHeight, control and control:GetHeight() or 0)
            row.title:SetPoint("TOPLEFT", 20, y - (rowHeight - textHeight) / 2)
            if control then
                control:ClearAllPoints()
                control:SetPoint("RIGHT", card, "TOPRIGHT", -20, y - rowHeight / 2)
            end
        end
        y = y - rowHeight - 20
    end
    card:SetHeight(-y)
end

------------------------------------------------------------------------
-- Content
------------------------------------------------------------------------

local function CreateBarCard(parent)
    local card = CreateCard(parent, L["The bar"], BAR_CARD_WIDTH)
    AddRow(card, L["Lock the bar"],
        L["Unlock it to drag the bar anywhere. Right-click the bar to lock it again."],
        function(p)
            return CreateToggle(p, function() return ns.db.locked end, ns.SetLocked)
        end)
    AddRow(card, L["Grow toward"], L["The way the bar runs from its first button."],
        function(p)
            return CreateSegmented(p, {
                { value = "RIGHT", label = L["Right"] },
                { value = "LEFT", label = L["Left"] },
                { value = "DOWN", label = L["Down"] },
                { value = "UP", label = L["Up"] },
            }, function() return ns.db.direction end, ns.SetDirection)
        end)
    AddRow(card, L["Buttons per row"],
        L["The bar starts a new row after this many buttons. For a bar growing up or down, it's per column."],
        function(p)
            return CreateSlider(p, 1, 12, function() return ns.db.perRow end, ns.SetPerRow, 140)
        end)
    AddRow(card, L["New rows"], L["Where the bar's next rows go."],
        function(p)
            -- Above or below for a bar growing sideways, left or right otherwise.
            local holder = CreateFrame("Frame", nil, p)
            local get = ns.RowsToward
            local sideways = CreateSegmented(holder, {
                { value = "UP", label = L["Above"] },
                { value = "DOWN", label = L["Below"] },
            }, get, ns.SetRowsToward, 76)
            local upright = CreateSegmented(holder, {
                { value = "LEFT", label = L["Left"] },
                { value = "RIGHT", label = L["Right"] },
            }, get, ns.SetRowsToward, 76)
            sideways:SetPoint("RIGHT")
            upright:SetPoint("RIGHT")
            holder:SetSize(sideways:GetWidth(), sideways:GetHeight())
            local function update()
                local horizontal = ns.db.direction == "LEFT" or ns.db.direction == "RIGHT"
                sideways:SetShown(horizontal)
                upright:SetShown(not horizontal)
            end
            update()
            updaters[#updaters + 1] = update
            return holder
        end)
    AddRow(card, L["Attach to player frame"],
        L["The bar moves along when you move the player frame in Edit Mode. Turn this off to pin it to the screen."],
        function(p)
            return CreateToggle(p, function() return ns.db.attached end, ns.SetAttached)
        end)
    AddRow(card, L["Position"], L["Put the bar back above your player frame."],
        function(p)
            local button = CreateButton(p, L["Reset"], 110)
            button:SetScript("OnClick", ns.ResetPosition)
            return button
        end)
    AddRow(card, L["Minimap button"],
        L["Show a Fanny Pack button on the minimap. Click it to open this window, drag it to move it."],
        function(p)
            return CreateToggle(p, function() return ns.db.minimapButton end, ns.SetMinimapButton)
        end)
    LayoutCard(card)
    return card
end

-- The buttons in bar order, each with its icon, name, arrows to move it
-- and an on/off switch.
local function CreateButtonsCard(parent)
    local card = CreateCard(parent, L["Buttons"], BUTTONS_CARD_WIDTH)
    local rowWidth = BUTTONS_CARD_WIDTH - 40

    local intro = Text(card, 12, C.muted)
    intro:SetPoint("TOPLEFT", 20, -52)
    intro:SetText(L["The top one is the bar's first button. Right-click a button on the bar to pick which item it uses."])
    local top -- where the list starts, under the intro; set by Relayout

    -- Only the buttons this character gets (poisons are for rogues).
    local rows, shown = {}, {}
    for _, kind in ipairs(ns.KINDS) do
        if ns.IsAvailable(kind.key) then shown[#shown + 1] = kind end
    end

    local function Layout()
        local i = 0
        for _, key in ipairs(ns.Order()) do
            local row = rows[key]
            if row then
                i = i + 1
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 20, top - (i - 1) * 36)
                row.up:SetEnabled(i > 1)
                row.down:SetEnabled(i < #shown)
            end
        end
    end

    local function Move(key, delta)
        ns.MoveButton(key, delta)
        Layout()
    end

    for _, kind in ipairs(shown) do
        local row = CreateFrame("Frame", nil, card)
        row:SetSize(rowWidth, 32)
        Rounded(row, "BACKGROUND", C.control)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", 8, 0)
        icon:SetTexture(select(5, C_Item.GetItemInfoInstant(kind.icon)))
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local toggle = CreateToggle(row, function() return ns.charDB.buttons[kind.key] end, function(value)
            ns.SetButtonShown(kind.key, value)
        end)
        toggle:SetPoint("RIGHT", -8, 0)
        row.down = CreateArrow(row, false, function() Move(kind.key, 1) end)
        row.down:SetPoint("RIGHT", toggle, "LEFT", -10, 0)
        row.up = CreateArrow(row, true, function() Move(kind.key, -1) end)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)

        local name = Text(row, 14, C.text)
        name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        name:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
        name:SetWordWrap(false)
        name:SetText(kind.name)

        rows[kind.key] = row
    end
    updaters[#updaters + 1] = Layout

    -- Under the list: hotkeys, and when buttons hide.
    AddRow(card, L["Hotkeys"], L["Bind a key to any button, under Fanny Pack."],
        function(p)
            local button = CreateButton(p, L["Key Bindings"], 110)
            button:SetScript("OnClick", function()
                window:Hide() -- would cover the game's settings
                ns.OpenKeyBindings()
            end)
            return button
        end)
    AddRow(card, L["Hide empty buttons"], L["Hide buttons for things you don't carry, instead of fading them."],
        function(p)
            return CreateToggle(p, function() return ns.db.hideEmpty end, ns.SetHideEmpty)
        end)
    AddRow(card, L["Hide food and drink in combat"], L["You can't eat or drink in a fight, so those buttons step aside."],
        function(p)
            return CreateToggle(p, function() return ns.db.hideEatingInCombat end, ns.SetHideEatingInCombat)
        end)

    -- Fits the card to a width; the intro's height decides where the list starts.
    function card:Relayout(width)
        self:SetWidth(width)
        intro:SetWidth(width - 40)
        top = -52 - intro:GetStringHeight() - 16
        for _, row in pairs(rows) do row:SetWidth(width - 40) end
        Layout()
        LayoutCard(self, top - #shown * 36 - 14)
    end
    card:Relayout(BUTTONS_CARD_WIDTH)
    return card
end

-- How the buttons look.
local function CreateLookCard(parent)
    local card = CreateCard(parent, L["Look"], BAR_CARD_WIDTH)
    AddRow(card, L["Shape"], L["The shape of the buttons."],
        function(p)
            return CreateSegmented(p, {
                { value = "square", label = L["Square"] },
                { value = "rounded", label = L["Rounded"] },
                { value = "round", label = L["Round"] },
            }, function() return ns.db.shape end, ns.SetShape, 76)
        end)
    AddRow(card, L["Border"], L["A thin line around each button."],
        function(p)
            return CreateSegmented(p, {
                { value = "none", label = L["None"] },
                { value = "silver", label = L["Silver"] },
                { value = "gold", label = L["Gold"] },
            }, function() return ns.db.border end, ns.SetBorder, 76)
        end)
    AddRow(card, L["Button size"], L["How big the buttons are."],
        function(p)
            return CreateSlider(p, 24, 56, function() return ns.db.buttonSize end, ns.SetButtonSize, 140)
        end)
    AddRow(card, L["Spacing"], L["The gap between the buttons."],
        function(p)
            return CreateSlider(p, 0, 16, function() return ns.db.spacing end, ns.SetSpacing, 140)
        end)
    AddRow(card, L["Buff food reminder"], L["The buff food button glows softly while you're not Well Fed."],
        function(p)
            return CreateToggle(p, function() return ns.db.buffFoodGlow end, ns.SetBuffFoodGlow)
        end)
    AddRow(card, L["Weapon reminder"],
        L["The buttons for weapon stones, oils and poisons glow softly while a weapon has nothing on it."],
        function(p)
            return CreateToggle(p, function() return ns.db.weaponGlow end, ns.SetWeaponGlow)
        end)
    AddRow(card, L["Fade out of combat"],
        L["The bar fades away outside combat and comes back when you hover over it or a fight starts."],
        function(p)
            return CreateToggle(p, function() return ns.db.fadeOutOfCombat end, ns.SetFadeOutOfCombat)
        end)
    LayoutCard(card)
    return card
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local scroll, content, cards

local function SaveGeometry()
    local point, _, relativePoint, x, y = window:GetPoint(1)
    ns.db.window = {
        point = point, relativePoint = relativePoint, x = x, y = y,
        width = window:GetWidth(), height = window:GetHeight(),
    }
end

local function SetResizeBounds(frame, minWidth, minHeight, maxWidth, maxHeight)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    else -- older clients
        frame:SetMinResize(minWidth, minHeight)
        frame:SetMaxResize(maxWidth, maxHeight)
    end
end

-- Keeps the window on the screen: no bigger than the screen, and scaled
-- down when even its smallest size doesn't fit (small screens, large UI
-- scale). Returns the tallest it may be.
local function FitToScreen()
    local screenWidth, screenHeight = UIParent:GetWidth() - SCREEN_MARGIN, UIParent:GetHeight() - SCREEN_MARGIN
    local scale = math.min(1, screenWidth / MIN_WIDTH, screenHeight / MIN_HEIGHT)
    window:SetScale(scale)
    local maxWidth, maxHeight = math.max(MIN_WIDTH, screenWidth / scale), math.max(MIN_HEIGHT, screenHeight / scale)
    SetResizeBounds(window, MIN_WIDTH, MIN_HEIGHT, maxWidth, maxHeight)
    window:SetSize(math.max(MIN_WIDTH, math.min(window:GetWidth(), maxWidth)),
        math.max(MIN_HEIGHT, math.min(window:GetHeight(), maxHeight)))
    return maxHeight
end

-- Scroll frame with a slim scrollbar on its right, like Pocket Goblin's.
local function CreateScrollArea(parent)
    local area = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, area)
    child:SetSize(1, 1)
    area:SetScrollChild(child)
    area:SetScript("OnSizeChanged", function(_, width) child:SetWidth(width) end)

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(4)
    bar:SetPoint("TOPLEFT", area, "TOPRIGHT", 5, -20)
    bar:SetPoint("BOTTOMLEFT", area, "BOTTOMRIGHT", 5, 20)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.04)

    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetWidth(4)
    thumb:EnableMouse(true)
    local thumbTexture = thumb:CreateTexture(nil, "ARTWORK")
    thumbTexture:SetAllPoints()
    thumbTexture:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.75)

    local function update()
        local range = area:GetVerticalScrollRange()
        if range <= 0 then
            bar:Hide()
            area:SetVerticalScroll(0)
            return
        end
        bar:Show()
        local height = bar:GetHeight()
        local thumbHeight = math.max(24, height * height / (height + range))
        thumb:SetHeight(thumbHeight)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -(area:GetVerticalScroll() / range) * (height - thumbHeight))
    end

    local function scrollTo(value)
        local range = area:GetVerticalScrollRange()
        area:SetVerticalScroll(math.max(0, math.min(range, value)))
        update()
    end

    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(self, delta)
        scrollTo(self:GetVerticalScroll() - delta * 48)
    end)
    area:SetScript("OnScrollRangeChanged", function(self)
        scrollTo(self:GetVerticalScroll())
    end)

    -- Drag the thumb.
    thumb:SetScript("OnMouseDown", function(self)
        local _, startY = GetCursorPosition()
        local startScroll = area:GetVerticalScroll()
        self:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local range = area:GetVerticalScrollRange()
            local travel = bar:GetHeight() - thumb:GetHeight()
            if travel > 0 then
                scrollTo(startScroll + (startY - y) / bar:GetEffectiveScale() / travel * range)
            end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

    area.UpdateScrollBar = update
    return area, child
end

-- Drag handle in the bottom-right corner.
local function CreateResizeGrip()
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(window:GetFrameLevel() + 50)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then window:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        window:StopMovingOrSizing()
        SaveGeometry()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Drag to resize"], 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
end

local function CreateHeader()
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        SaveGeometry()
    end)

    local logo = Icon(header, "emblem", 48, C.white)
    logo:SetPoint("LEFT", 16, 0)

    local title = Text(header, 26, C.text)
    title:SetPoint("BOTTOMLEFT", logo, "RIGHT", 14, 0)
    title:SetText("|cff5fb48eFanny|r Pack")

    local version = CreateBadge(header, C.accent, { C.accent[1], C.accent[2], C.accent[3], 0.16 })
    version:SetPoint("LEFT", title, "RIGHT", 12, 0)
    version:SetText(ns.VERSION == "dev" and "dev" or ("v" .. (ns.VERSION or "?")))

    local subtitle = Text(header, 13, C.muted)
    subtitle:SetPoint("TOPLEFT", logo, "RIGHT", 14, -4)
    subtitle:SetText(L["Bandages, food and potions on your hip"])

    local close = CreateFrame("Button", nil, header)
    close:SetSize(32, 32)
    close:SetPoint("RIGHT", -18, 0)
    local closeIcon = Icon(close, "icon-close", 18, C.muted)
    closeIcon:SetPoint("CENTER")
    close:SetScript("OnEnter", function() SetColor(closeIcon, C.text) end)
    close:SetScript("OnLeave", function() SetColor(closeIcon, C.muted) end)
    close:SetScript("OnClick", function() window:Hide() end)

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.55)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 1, 0)
    line:SetPoint("BOTTOMRIGHT", -1, 0)
end

-- Fits the cards to the window's width: two columns when there's room,
-- otherwise one. Returns the height of all the cards.
local function LayoutWindow()
    local width = window:GetWidth() - SCROLLBAR
    local columns
    if width >= TWO_COLUMNS then
        local right = math.max(320, math.floor((width - 56) * 0.4))
        columns = {
            { width = width - 56 - right, cards.bar, cards.look },
            { width = right, cards.buttons },
        }
    else
        columns = { { width = width - 40, cards.bar, cards.buttons, cards.look } }
    end

    local x, height = 20, 0
    for _, column in ipairs(columns) do
        local y = -20
        for _, card in ipairs(column) do
            if card.Relayout then
                card:Relayout(column.width)
            else
                card:SetWidth(column.width)
                LayoutCard(card)
            end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
            y = y - card:GetHeight() - 16
        end
        x = x + column.width + 16
        height = math.max(height, -y + 4)
    end
    content:SetHeight(height)
    scroll.UpdateScrollBar()
    return height
end

local function CreateWindow()
    window = CreateFrame("Frame", "FannyPackFrame", UIParent, "BackdropTemplate")
    local saved = ns.db.window
    if saved and saved.point then
        window:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        window:SetPoint("CENTER")
    end
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetResizable(true)
    if window.SetDontSavePosition then window:SetDontSavePosition(true) end -- saved by us instead
    window:EnableMouse(true)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    window:SetBackdropColor(unpack(C.bg))
    window:SetBackdropBorderColor(unpack(C.windowBorder))
    window:Hide()

    -- Escape closes only this window, not the game options behind it.
    -- Keyboard propagation can't be changed in combat, so Escape is
    -- ignored then.
    window:EnableKeyboard(true)
    window:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
            C_Timer.After(0, function()
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    CreateHeader()
    scroll, content = CreateScrollArea(window)
    scroll:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT - 1)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 1)
    cards = {
        bar = CreateBarCard(content),
        look = CreateLookCard(content),
        buttons = CreateButtonsCard(content),
    }
    CreateResizeGrip()

    -- The saved size, or wide enough for two columns and tall enough for
    -- everything, as far as the screen allows.
    window:SetSize(saved and saved.width or WIDTH, saved and saved.height or MIN_HEIGHT)
    local maxHeight = FitToScreen()
    if not (saved and saved.height) then
        window:SetHeight(math.min(HEADER_HEIGHT + 1 + LayoutWindow(), maxHeight))
    end

    window:SetScript("OnSizeChanged", LayoutWindow)
    window:SetScript("OnShow", function(self)
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        FitToScreen() -- the screen or UI scale may have changed
        ns.RefreshWindow()
        LayoutWindow()
    end)
end

function ns.RefreshWindow()
    if not (window and window:IsShown()) then return end
    for _, update in ipairs(updaters) do update() end
end

-- show: true/false, or nil to toggle.
function ns.ToggleWindow(show)
    if not ns.db then return end
    if not window then CreateWindow() end
    if show == nil then show = not window:IsShown() end
    window:SetShown(show)
end

------------------------------------------------------------------------
-- Entry points: AddOns options panel and the minimap addon compartment
------------------------------------------------------------------------

if Settings and Settings.RegisterCanvasLayoutCategory then
    local panel = CreateFrame("Frame")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Fanny Pack")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText(L["Settings are in the Fanny Pack window (/fannypack)."])

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(180, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
    open:SetText(L["Open Fanny Pack"])
    open:SetScript("OnClick", function() ns.ToggleWindow(true) end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Fanny Pack")
    Settings.RegisterAddOnCategory(category)
end

function FannyPack_OnAddonCompartmentClick()
    ns.ToggleWindow()
end
