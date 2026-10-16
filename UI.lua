-- Fanny Pack options window: a dark, card-based window in the style of
-- Pocket Goblin, with a sidebar of pages. The colours and drawing helpers
-- are shared with Bar.lua through ns.

local ADDON_NAME, ns = ...
local L = ns.L

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- A sidebar of pages, like Pocket Goblin's. Each page is a column of cards
-- that fits the window's width and scrolls when the window is shorter. The
-- window can be resized.
local SIDEBAR_WIDTH = 200
local CARD_WIDTH = 500 -- natural width, for the default size
local SCROLLBAR = 14 -- room on the right for the scroll bar
local WIDTH = SIDEBAR_WIDTH + 20 + CARD_WIDTH + 20 + SCROLLBAR
local MIN_WIDTH = SIDEBAR_WIDTH + 20 + 400 + 20 + SCROLLBAR
local MIN_HEIGHT = 360
local NAV_HEIGHT, NAV_SPACING = 44, 4
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
    danger = { 0.78, 0.29, 0.29, 1 },
    dangerHover = { 0.88, 0.38, 0.38, 1 },
    text = { 0.92, 0.92, 0.93, 1 },
    muted = { 0.53, 0.54, 0.58, 1 },
    off = { 0.2, 0.205, 0.225, 1 },
    knobOff = { 0.78, 0.78, 0.82, 1 },
    white = { 1, 1, 1, 1 },
    sidebar = { 0.035, 0.037, 0.043, 1 },
    accentDim = { 0.37, 0.71, 0.56, 0.14 },
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
ns.CreateToggle = CreateToggle -- also in the bar's right-click list

-- Scrolling a page with the mouse wheel shouldn't get caught by a slider
-- the pointer happens to pass over: wheel turns on a slider within this
-- long of scrolling the page keep scrolling the page. Stop for a moment,
-- and the wheel moves the slider.
local WHEEL_HANDOFF = 0.5 -- seconds
local lastPageScroll, scrolledPage = 0, nil

local function PageScrolled(page)
    lastPageScroll, scrolledPage = GetTime(), page
end

-- True (after passing the turn on) if the page was just being scrolled.
local function HandWheelToPage(delta)
    if scrolledPage and scrolledPage:IsVisible() and GetTime() - lastPageScroll < WHEEL_HANDOFF then
        scrolledPage:GetScript("OnMouseWheel")(scrolledPage, delta)
        return true
    end
    return false
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
        if HandWheelToPage(delta) then return end
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
    danger = { C.danger, C.dangerHover, C.white },
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
    button.label = text

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

-- Button showing a choice; a click opens the game's menu to pick another.
-- buildMenu(root) adds the menu's entries. Like Pocket Goblin's.
local function CreateDropdown(parent, width, getLabel, buildMenu)
    local dropdown = CreateFrame("Button", nil, parent)
    dropdown:SetSize(width, 28)
    local bg = Rounded(dropdown, "BACKGROUND", C.control)
    Rounded(dropdown, "BORDER", C.controlBorder, "rounded-border")
    local text = Text(dropdown, 13, C.text)
    text:SetPoint("LEFT", 10, 0)
    text:SetPoint("RIGHT", -26, 0)
    text:SetWordWrap(false)
    local chevron = Icon(dropdown, "icon-chevron", 14, C.muted)
    chevron:SetPoint("RIGHT", -8, 0)

    function dropdown:UpdateLabel()
        text:SetText(getLabel())
    end
    dropdown:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root) buildMenu(root) end)
        end
    end)
    dropdown:SetScript("OnEnter", function() SetColor(bg, C.controlHover) end)
    dropdown:SetScript("OnLeave", function() SetColor(bg, C.control) end)
    dropdown:UpdateLabel()
    updaters[#updaters + 1] = function() dropdown:UpdateLabel() end -- follows profile changes
    return dropdown
end

local function CreateTextInput(parent, width, placeholderText)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 28)
    box:SetAutoFocus(false)
    box:SetFont(FONT, 13, "")
    box:SetTextColor(C.text[1], C.text[2], C.text[3])
    box:SetTextInsets(10, 10, 0, 0)
    box:SetMaxLetters(32)
    Rounded(box, "BACKGROUND", C.control)
    local border = Rounded(box, "BORDER", C.controlBorder, "rounded-border")
    local placeholder = Text(box, 13, C.muted)
    placeholder:SetPoint("LEFT", 10, 0)
    placeholder:SetText(placeholderText)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEditFocusGained", function() SetColor(border, C.accent) end)
    box:SetScript("OnEditFocusLost", function() SetColor(border, C.controlBorder) end)
    box:SetScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "") end)
    return box
end

-- A button that asks "Confirm?" on the first click and acts on the second.
local function CreateConfirmButton(parent, label, width, style, onConfirm)
    local button = CreateButton(parent, label, width, style)
    local armed = false
    local function disarm()
        armed = false
        button.label:SetText(label)
    end
    button:SetScript("OnClick", function()
        if armed then
            disarm()
            onConfirm()
        else
            armed = true
            button.label:SetText(L["Confirm?"])
            C_Timer.After(3, function() if armed then disarm() end end)
        end
    end)
    return button
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
    local card = CreateCard(parent, L["The bar"], CARD_WIDTH)
    AddRow(card, L["Lock the bar"],
        L["Unlock it to drag the bar anywhere. Right-click the bar to lock it again."],
        function(p)
            return CreateToggle(p, function() return ns.account.locked end, ns.SetLocked)
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
            return CreateToggle(p, function() return ns.account.minimapButton end, ns.SetMinimapButton)
        end)
    LayoutCard(card)
    return card
end

-- The buttons in bar order, each with its icon, name, arrows to move it
-- and an on/off switch.
local function CreateButtonsCard(parent)
    local card = CreateCard(parent, L["Buttons"], CARD_WIDTH)
    local rowWidth = CARD_WIDTH - 40

    local intro = Text(card, 12, C.muted)
    intro:SetPoint("TOPLEFT", 20, -52)
    intro:SetText(L["The top one is the bar's first button. Right-click a button on the bar to pick which item it uses and when its count turns red."])
    local top -- where the list starts, under the intro; set by Relayout

    -- Headings over the two columns of switches, far enough apart for
    -- "Out of combat" to fit over its switch.
    local COLUMN_GAP = 30
    local shownHeading = Text(card, 10, C.muted)
    shownHeading:SetJustifyH("CENTER")
    shownHeading:SetText(L["Out of combat"])
    local combatHeading = Text(card, 10, C.muted)
    combatHeading:SetJustifyH("CENTER")
    combatHeading:SetText(L["In combat"])

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

        local toggle = CreateToggle(row, function() return ns.db.buttons[kind.key] end, function(value)
            ns.SetButtonShown(kind.key, value)
        end)
        toggle:SetPoint("RIGHT", -8, 0)
        local combat = CreateToggle(row, function() return ns.ShowsInCombat(kind.key) end, function(value)
            ns.SetShowsInCombat(kind.key, value)
        end)
        combat:SetPoint("RIGHT", toggle, "LEFT", -COLUMN_GAP, 0)
        row.down = CreateArrow(row, false, function() Move(kind.key, 1) end)
        row.down:SetPoint("RIGHT", combat, "LEFT", -10, 0)
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
    AddRow(card, L["Use on your target"],
        L["Bandages and scrolls go on a friendly target. With no target, or an enemy targeted, they go on you."],
        function(p)
            return CreateToggle(p, function() return ns.db.useOnTarget end, ns.SetUseOnTarget)
        end)
    AddRow(card, L["Hide empty buttons"], L["Hide buttons for things you don't carry, instead of fading them."],
        function(p)
            return CreateToggle(p, function() return ns.db.hideEmpty end, ns.SetHideEmpty)
        end)

    -- Fits the card to a width; the intro's height decides where the list starts.
    function card:Relayout(width)
        self:SetWidth(width)
        intro:SetWidth(width - 40)
        local headings = -52 - intro:GetStringHeight() - 14
        -- Centred over the switches: the right one ends 8 inside the row, which ends 20 inside the card.
        shownHeading:ClearAllPoints()
        shownHeading:SetPoint("TOP", self, "TOPRIGHT", -20 - 8 - 24, headings)
        combatHeading:ClearAllPoints()
        combatHeading:SetPoint("TOP", self, "TOPRIGHT", -20 - 8 - 48 - COLUMN_GAP - 24, headings)
        top = headings - shownHeading:GetStringHeight() - 6
        for _, row in pairs(rows) do row:SetWidth(width - 40) end
        Layout()
        LayoutCard(self, top - #shown * 36 - 14)
    end
    card:Relayout(CARD_WIDTH)
    return card
end

-- How the buttons look.
local function CreateLookCard(parent)
    local card = CreateCard(parent, L["Look"], CARD_WIDTH)
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
    AddRow(card, L["Fade out of combat"],
        L["The bar fades away outside combat and comes back when you hover over it or a fight starts."],
        function(p)
            return CreateToggle(p, function() return ns.db.fadeOutOfCombat end, ns.SetFadeOutOfCombat)
        end)
    LayoutCard(card)
    return card
end

-- The reminder glows as a small table: one row per reminder with its
-- "running out" slider and its on/off switch, under column headings.
local REMINDERS = {
    { name = L["Buff food"], icon = 6888, minutes = "wellFed", setting = "buffFoodGlow", set = "SetBuffFoodGlow" },
    { name = L["Elixirs"], icon = 2454, minutes = "elixir", setting = "elixirGlow", set = "SetElixirGlow" },
    { name = L["Scrolls"], icon = 1181, minutes = "scroll", setting = "scrollGlow", set = "SetScrollGlow" },
    { name = L["Weapons"], icon = 2862, minutes = "weapon", setting = "weaponGlow", set = "SetWeaponGlow" },
}

local function CreateRemindersCard(parent)
    local card = CreateCard(parent, L["Reminders"], CARD_WIDTH)
    local intro = Text(card, 12, C.muted)
    intro:SetPoint("TOPLEFT", 20, -52)
    intro:SetText(L["Buttons glow gold when their buff, or what's on your weapon, is missing, and silver this many minutes before it runs out (0: no silver)."])

    local SLIDER_WIDTH = 120
    local sliderHeading = Text(card, 10, C.muted)
    sliderHeading:SetText(L["Running out"])
    local onHeading = Text(card, 10, C.muted)
    onHeading:SetText(L["On"])

    local rows = {}
    for _, info in ipairs(REMINDERS) do
        local row = CreateFrame("Frame", nil, card)
        row:SetHeight(32)
        Rounded(row, "BACKGROUND", C.control)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", 8, 0)
        icon:SetTexture(select(5, C_Item.GetItemInfoInstant(info.icon)))
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local toggle = CreateToggle(row, function() return ns.db[info.setting] end, function(value)
            ns[info.set](value)
            if ns.RefreshWindow then ns.RefreshWindow() end -- dims the slider
        end)
        toggle:SetPoint("RIGHT", -8, 0)
        local slider = CreateSlider(row, 0, ns.RUNNING_OUT[info.minutes],
            function() return ns.db[info.minutes .. "Minutes"] end,
            function(value) ns.SetRunningOut(info.minutes, value) end, SLIDER_WIDTH)
        slider:SetPoint("RIGHT", toggle, "LEFT", -16, 0)
        updaters[#updaters + 1] = function() slider:SetAlpha(ns.db[info.setting] and 1 or 0.4) end

        local name = Text(row, 14, C.text)
        name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        name:SetPoint("RIGHT", slider, "LEFT", -8, 0)
        name:SetWordWrap(false)
        name:SetText(info.name)
        rows[#rows + 1] = row
    end

    function card:Relayout(width)
        self:SetWidth(width)
        intro:SetWidth(width - 40)
        local headings = -52 - intro:GetStringHeight() - 12
        -- Over the switch (8 inside the row, which is 20 inside the card) and
        -- the slider's track, which ends 40 before its value.
        onHeading:ClearAllPoints()
        onHeading:SetPoint("TOP", self, "TOPRIGHT", -20 - 8 - 24, headings)
        sliderHeading:ClearAllPoints()
        sliderHeading:SetPoint("TOP", self, "TOPRIGHT", -20 - 8 - 48 - 16 - 40 - SLIDER_WIDTH / 2, headings)
        local top = headings - onHeading:GetStringHeight() - 6
        for i, row in ipairs(rows) do
            row:SetWidth(width - 40)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 20, top - (i - 1) * 36)
        end
        self:SetHeight(-top + #rows * 36 - 4 + 20)
    end
    card:Relayout(CARD_WIDTH)
    return card
end

-- A small "- 5 +" control for a number from 0 (shown as "off") up.
local function CreateStepper(parent, get, set)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(96, 24)

    local function Step(label, delta)
        local button = CreateFrame("Button", nil, holder)
        button:SetSize(24, 24)
        local bg = Rounded(button, "BACKGROUND", C.control)
        Rounded(button, "BORDER", C.controlBorder, "rounded-border")
        local text = Text(button, 14, C.text)
        text:SetPoint("CENTER", 0, 1)
        text:SetJustifyH("CENTER")
        text:SetText(label)
        button:SetScript("OnEnter", function() SetColor(bg, C.controlHover) end)
        button:SetScript("OnLeave", function() SetColor(bg, C.control) end)
        button:SetScript("OnClick", function()
            set(get() + delta)
            holder:Update()
        end)
        return button
    end
    local minus = Step("-", -1)
    minus:SetPoint("LEFT")
    local plus = Step("+", 1)
    plus:SetPoint("RIGHT")
    local value = Text(holder, 13, C.text)
    value:SetPoint("CENTER")
    value:SetJustifyH("CENTER")

    function holder:Update()
        local number = get()
        value:SetText(number > 0 and number or L["off"])
        minus:SetEnabled(number > 0)
        minus:SetAlpha(number > 0 and 1 or 0.4)
    end
    holder:Update()
    updaters[#updaters + 1] = function() holder:Update() end
    return holder
end

-- Every button's low-stock limit in one place, in bar order. The same
-- limits are at the bottom of each button's right-click list.
local function CreateLowStockCard(parent)
    local card = CreateCard(parent, L["Low stock"], CARD_WIDTH)
    AddRow(card, L["Low-stock warning"],
        L["A button's count turns red when you're down to its limit or fewer. You can also set a limit at the bottom of the button's right-click list."],
        function(p)
            return CreateToggle(p, function() return ns.db.lowStockWarning end, ns.SetLowStockWarning)
        end)

    local rows, top = {}, nil
    local function Layout()
        local i = 0
        for _, key in ipairs(ns.Order()) do
            local row = rows[key]
            if row then
                i = i + 1
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 20, top - (i - 1) * 36)
            end
        end
    end

    -- With the warning off, the limits are kept but dimmed.
    local function Dim()
        for _, row in pairs(rows) do row:SetAlpha(ns.db.lowStockWarning and 1 or 0.4) end
    end

    for _, kind in ipairs(ns.KINDS) do
        if ns.IsAvailable(kind.key) then
            local row = CreateFrame("Frame", nil, card)
            row:SetHeight(32)
            Rounded(row, "BACKGROUND", C.control)
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(22, 22)
            icon:SetPoint("LEFT", 8, 0)
            icon:SetTexture(select(5, C_Item.GetItemInfoInstant(kind.icon)))
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local stepper = CreateStepper(row, function() return ns.LowStock(kind.key) end, function(value)
                ns.SetLowStock(kind.key, value)
            end)
            stepper:SetPoint("RIGHT", -8, 0)
            local name = Text(row, 14, C.text)
            name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
            name:SetPoint("RIGHT", stepper, "LEFT", -8, 0)
            name:SetWordWrap(false)
            name:SetText(kind.name)
            rows[kind.key] = row
        end
    end
    updaters[#updaters + 1] = Layout -- follows changes to the order
    updaters[#updaters + 1] = Dim

    -- The switch's row on top, then the list.
    function card:Relayout(width)
        self:SetWidth(width)
        LayoutCard(self)
        top = -self:GetHeight() + 4
        local count = 0
        for _, row in pairs(rows) do
            row:SetWidth(width - 40)
            count = count + 1
        end
        Layout()
        Dim()
        self:SetHeight(-top + count * 36 - 4 + 20)
    end
    card:Relayout(CARD_WIDTH)
    return card
end

local function ProfileExists(name)
    return name and tContains(ns.GetProfileNames(), name)
end

-- A dropdown with a button on its right, for a stacked row.
local function DropdownWithButton(parent, dropdown, button)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(256, 32)
    dropdown:SetParent(holder)
    dropdown:SetPoint("LEFT")
    button:SetParent(holder)
    button:SetPoint("RIGHT")
    return holder
end

-- Profiles: a whole bar setup each (for a tank, a healer...), like Pocket
-- Goblin's. Each character uses one.
local function CreateProfilesCard(parent)
    local card = CreateCard(parent, L["Profiles"], CARD_WIDTH)
    local copySource, deleteTarget

    AddRow(card, L["Active profile"], L["The bar setup this character uses: buttons, order, layout and look."],
        function(p)
            return CreateDropdown(p, 256,
                function() return ns.GetProfileName() end,
                function(root)
                    for _, name in ipairs(ns.GetProfileNames()) do
                        local others = #ns.GetProfileUsers(name)
                        local label = others > 0
                            and ("%s  |cff8a8b93(+%d %s)|r"):format(name, others,
                                others == 1 and L["character"] or L["characters"])
                            or name
                        root:CreateRadio(label, function() return ns.GetProfileName() == name end,
                            function() ns.SetProfile(name) end)
                    end
                end)
        end, true)
    AddRow(card, L["New profile"], L["Starts as a copy of the active profile, and this character switches to it."],
        function(p)
            local holder = CreateFrame("Frame", nil, p)
            holder:SetSize(256, 32)
            local box = CreateTextInput(holder, 170, L["Profile name"])
            box:SetPoint("LEFT")
            local create = CreateButton(holder, L["Create"], 78, "primary")
            create:SetPoint("RIGHT")
            local function submit()
                if ns.CreateProfile(box:GetText()) then
                    box:SetText("")
                    box:ClearFocus()
                else
                    ns.Print(L["Enter a name that isn't already used by a profile."])
                end
            end
            create:SetScript("OnClick", submit)
            box:SetScript("OnEnterPressed", submit)
            return holder
        end, true)
    AddRow(card, L["Copy from"], L["Replace the active profile's settings with a copy of another profile."],
        function(p)
            local dropdown
            dropdown = CreateDropdown(p, 170,
                function() return ProfileExists(copySource) and copySource or L["Choose profile"] end,
                function(root)
                    for _, name in ipairs(ns.GetProfileNames()) do
                        if name ~= ns.GetProfileName() then
                            root:CreateRadio(name, function() return copySource == name end, function()
                                copySource = name
                                dropdown:UpdateLabel()
                            end)
                        end
                    end
                end)
            local copy = CreateConfirmButton(p, L["Copy"], 78, nil, function()
                if ProfileExists(copySource) then ns.CopyProfile(copySource) end
            end)
            return DropdownWithButton(p, dropdown, copy)
        end, true)
    AddRow(card, L["Delete profile"],
        L["Characters using it switch to Default. Default and the active profile can't be deleted."],
        function(p)
            local dropdown
            dropdown = CreateDropdown(p, 170,
                function() return ProfileExists(deleteTarget) and deleteTarget or L["Choose profile"] end,
                function(root)
                    for _, name in ipairs(ns.GetProfileNames()) do
                        if name ~= ns.GetProfileName() and name ~= ns.DEFAULT_PROFILE then
                            root:CreateRadio(name, function() return deleteTarget == name end, function()
                                deleteTarget = name
                                dropdown:UpdateLabel()
                            end)
                        end
                    end
                end)
            local delete = CreateConfirmButton(p, L["Delete"], 78, "danger", function()
                if ProfileExists(deleteTarget) then ns.DeleteProfile(deleteTarget) end
                deleteTarget = nil
                dropdown:UpdateLabel()
            end)
            return DropdownWithButton(p, dropdown, delete)
        end, true)
    AddRow(card, L["Reset profile"], L["Back to the default settings."],
        function(p)
            return CreateConfirmButton(p, L["Reset"], 100, "danger", ns.ResetProfile)
        end)
    LayoutCard(card)
    return card
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------


local function SaveGeometry()
    local point, _, relativePoint, x, y = window:GetPoint(1)
    ns.account.window = {
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
        PageScrolled(self)
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

-- The sidebar's pages and the cards on each.
local PAGES = {
    { key = "buttons", title = L["Buttons"], subtitle = L["Order, hotkeys & hiding"], icon = "icon-list",
        cards = { CreateButtonsCard } },
    { key = "bar", title = L["Bar"], subtitle = L["Position & layout"], icon = "icon-sort",
        cards = { CreateBarCard } },
    { key = "look", title = L["Look"], subtitle = L["Shape, size & fading"], icon = "icon-look",
        cards = { CreateLookCard } },
    { key = "reminders", title = L["Reminders"], subtitle = L["Glows & low stock"], icon = "icon-clock",
        cards = { CreateRemindersCard, CreateLowStockCard } },
    { key = "profiles", title = L["Profiles"], subtitle = L["Setups for roles & characters"], icon = "icon-profile",
        cards = { CreateProfilesCard } },
}

local pages = {} -- [key] = { frame, scroll, content, cards, nav }
local currentPage = "buttons"

-- Fits a page's cards to the window's width and stacks them. Returns the
-- height of all the cards.
local function LayoutPage(key)
    local page = pages[key]
    local width = window:GetWidth() - SIDEBAR_WIDTH - 1 - SCROLLBAR - 40
    local y = -20
    for _, card in ipairs(page.cards) do
        if card.Relayout then
            card:Relayout(width)
        else
            card:SetWidth(width)
            LayoutCard(card)
        end
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", page.content, "TOPLEFT", 20, y)
        y = y - card:GetHeight() - 16
    end
    page.content:SetHeight(-y + 4)
    page.scroll.UpdateScrollBar()
    return -y + 4
end

local function SelectPage(key)
    currentPage = key
    for pageKey, page in pairs(pages) do
        local selected = pageKey == key
        page.frame:SetShown(selected)
        page.nav.selected:SetShown(selected)
        page.nav.accent:SetShown(selected)
        SetColor(page.nav.icon, selected and C.accent or C.muted)
        local color = selected and C.accent or C.text
        page.nav.title:SetTextColor(color[1], color[2], color[3])
    end
    LayoutPage(key)
end

-- A sidebar entry: icon, title and a short subtitle. A long subtitle wraps
-- onto more lines and the entry grows to fit, like Pocket Goblin's.
local function CreateNavButton(parent, page, y)
    local nav = CreateFrame("Button", nil, parent)
    nav:SetPoint("TOPLEFT", 10, y)

    nav.selected = Rounded(nav, "BACKGROUND", C.accentDim)
    local hover = Rounded(nav, "BACKGROUND", { 1, 1, 1, 0.035 })
    hover:Hide()

    nav.accent = nav:CreateTexture(nil, "ARTWORK")
    nav.accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    nav.accent:SetSize(3, 30)
    nav.accent:SetPoint("LEFT")

    nav.icon = Icon(nav, page.icon, 20, C.muted)
    nav.icon:SetPoint("LEFT", 16, 0)

    nav.title = Text(nav, 15, C.text)
    nav.title:SetText(page.title)
    local subtitle = Text(nav, 11, C.muted)
    subtitle:SetPoint("TOPLEFT", nav.title, "BOTTOMLEFT", 0, -4)
    subtitle:SetWidth(SIDEBAR_WIDTH - 20 - 56)
    subtitle:SetText(page.subtitle)

    -- Title and subtitle centred together, at least NAV_HEIGHT high.
    local textHeight = nav.title:GetStringHeight() + 4 + subtitle:GetStringHeight()
    local height = math.max(NAV_HEIGHT, math.ceil(textHeight) + 12)
    nav:SetSize(SIDEBAR_WIDTH - 20, height)
    nav.title:SetPoint("TOPLEFT", 48, -(height - textHeight) / 2)

    nav:SetScript("OnEnter", function() if currentPage ~= page.key then hover:Show() end end)
    nav:SetScript("OnLeave", function() hover:Hide() end)
    nav:SetScript("OnClick", function()
        hover:Hide()
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        SelectPage(page.key)
    end)
    return nav
end

local function CreateWindow()
    window = CreateFrame("Frame", "FannyPackFrame", UIParent, "BackdropTemplate")
    local saved = ns.account.window
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
    window:SetSize(saved and saved.width or WIDTH, saved and saved.height or MIN_HEIGHT)

    local sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT - 1)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(unpack(C.sidebar))
    local sidebarLine = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarLine:SetColorTexture(1, 1, 1, 0.06)
    sidebarLine:SetWidth(1)
    sidebarLine:SetPoint("TOPRIGHT")
    sidebarLine:SetPoint("BOTTOMRIGHT")

    -- Each page: its own scrolling column of cards, right of the sidebar.
    local tallest, navY = 0, -8
    for _, info in ipairs(PAGES) do
        local frame = CreateFrame("Frame", nil, window)
        frame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", -1, 1)
        frame:Hide()
        local scroll, content = CreateScrollArea(frame)
        scroll:SetPoint("TOPLEFT")
        scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 0)
        local cards = {}
        for _, create in ipairs(info.cards) do cards[#cards + 1] = create(content) end
        local nav = CreateNavButton(sidebar, info, navY)
        navY = navY - nav:GetHeight() - NAV_SPACING
        pages[info.key] = { frame = frame, scroll = scroll, content = content, cards = cards, nav = nav }
        tallest = math.max(tallest, LayoutPage(info.key))
    end
    CreateResizeGrip()

    -- The saved size, or tall enough for the longest page, as far as the
    -- screen allows.
    local maxHeight = FitToScreen()
    if not (saved and saved.height) then
        window:SetHeight(math.min(HEADER_HEIGHT + 1 + tallest, maxHeight))
    end
    SelectPage(currentPage)

    window:SetScript("OnSizeChanged", function() LayoutPage(currentPage) end)
    window:SetScript("OnShow", function(self)
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        FitToScreen() -- the screen or UI scale may have changed
        ns.RefreshWindow()
        LayoutPage(currentPage)
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
