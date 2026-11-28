-- What's new: after an update with new features, one line in chat at the
-- first login, a card at the top of the options until "Got it", and a dot
-- on the sidebar pages that changed until you visit them. A first install
-- gets none of it: everything is new then. Bug-fix releases without an
-- entry below stay quiet.

local ADDON_NAME, ns = ...
local L = ns.L

-- Newest first. version: the release; chat: what the chat line says is
-- new; points: the card's lines, each with the options page it's on and,
-- optionally, the setting (a key UI.lua's NewsDot or NewsCardDot gives its
-- row or card) that gets a dot, and the one class it's for (see ForYourClass).
ns.WHATS_NEW = {
    {
        version = "1.10.0",
        chat = L["mage imbue scrolls on the weapon button, and a Familiar button"],
        points = {
            { text = L["Imbue scrolls: the weapon button uses your imbue scrolls, each only on the weapon it's for. Choose Imbues to use them before oils."],
                page = "items", setting = "weaponPreference", class = "MAGE" },
            { text = L["Familiar: a new button summons your best familiar and glows while none is out."],
                page = "buttons", class = "MAGE" },
        },
    },
    {
        version = "1.9.0",
        chat = L["scrolls in your class's order, and weapon stones that fit your weapon"],
        points = {
            { text = L["Scroll order: the scroll button uses your class's scrolls first. Drag the stats to change the order."],
                page = "reminders", setting = "scrollOrder" },
            { text = L["Weapon stones: only stones that fit your weapon, and oils first for casters. Choose stones or oils first."],
                page = "items", setting = "weaponPreference" },
        },
    },
    {
        version = "1.8.1",
        chat = L["make your own buttons for any items you like, and Masque skins"],
        points = {
            { text = L["Custom buttons: make your own button for any items, like raid potions, Holy Water or a trinket, used in the order you set."],
                page = "custom" },
            { text = L["Masque: with Masque installed, skin the buttons to match your action bars (/msq)."],
                page = "look" },
        },
    },
    {
        version = "1.7.0",
        chat = L["macros for your own action bars, and binding keys by hovering the buttons"],
        points = {
            { text = L["Macros: put a Fanny Pack button on any action bar as a macro that always uses the best item."],
                page = "items", setting = "macros" },
            { text = L["Bind keys: hover a button on the bar and press a key. Find it on the Buttons page, or type /fannypack bind."],
                page = "buttons" },
        },
    },
    {
        version = "1.6.0",
        chat = L["new glow looks, drag and drop to sort your buttons, and an Items page"],
        points = {
            { text = L["Glow look: make the reminder glow easier to see, as a border or the action bars' sparkle, stronger or steady."],
                page = "reminders", setting = "glowLook" },
            { text = L["Drag the rows on the Buttons page to sort your buttons."], page = "buttons" },
            { text = L["The new Items page holds your hidden items and how items are used."], page = "items" },
            { text = L["A short tour of the bar for new players: replay it from the Bar page."], page = "bar",
                setting = "tour" },
        },
    },
}

-- Version numbers as { major, minor, patch }; "1.6.0" > "1.5.2".
local function Parse(version)
    local a, b, c = tostring(version):match("^(%d+)%.(%d+)%.?(%d*)")
    return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

local function Newer(a, b)
    local x, y = Parse(a), Parse(b)
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
end

-- The running version. From source ("dev") it's the newest entry, so the
-- news can be tried out before a release.
local function Current()
    if ns.VERSION and ns.VERSION:match("^%d") then return ns.VERSION end
    return ns.WHATS_NEW[1] and ns.WHATS_NEW[1].version or "0"
end

-- Entries newer than seen (and than the version Fanny Pack was installed
-- with), up to the running one, newest first.
local function EntriesAfter(seen)
    local account = ns.account
    local current = Current()
    local list = {}
    for _, entry in ipairs(ns.WHATS_NEW) do
        if Newer(entry.version, seen or "0") and Newer(entry.version, account.newsBaseline or "0")
            and not Newer(entry.version, current) then
            list[#list + 1] = entry
        end
    end
    return list
end

-- Points for one class only are left out on the others, and so is an
-- entry with no points left: a warrior hears nothing of mage scrolls.
local function ForYourClass()
    local class = select(2, UnitClass("player"))
    local kept = {}
    for _, entry in ipairs(ns.WHATS_NEW) do
        local points = {}
        for _, point in ipairs(entry.points) do
            if not point.class or point.class == class then points[#points + 1] = point end
        end
        if #points > 0 then
            entry.points = points
            kept[#kept + 1] = entry
        end
    end
    ns.WHATS_NEW = kept
end

-- At login: remember the version, and on the first login after an update
-- with news, say so in chat (a moment later, after the login messages).
function ns.InitNews()
    ForYourClass()
    local account = ns.account
    local current = Current()
    account.newsPages = account.newsPages or {}
    if ns.freshInstall then
        account.newsBaseline = current
        account.newsLastRun = current
        return
    end
    local news = EntriesAfter(account.newsLastRun)
    account.newsLastRun = current
    if #news > 0 and account.newsChat ~= false then
        C_Timer.After(8, function()
            ns.Print(L["new in %s: %s. Type /fannypack to see."], news[1].version, news[1].chat)
        end)
    end
end

-- The entries the options' "What's new" card shows, newest first.
function ns.UnseenNews()
    if not ns.account then return {} end
    return EntriesAfter(ns.account.newsSeen)
end

-- "Got it": the card stays away until the next release with news.
function ns.DismissNews()
    ns.account.newsSeen = Current()
end

-- Whether an options page has news you haven't looked at yet.
function ns.PageIsNew(key)
    if not ns.account then return false end
    for _, entry in ipairs(EntriesAfter((ns.account.newsPages or {})[key])) do
        for _, point in ipairs(entry.points) do
            if point.page == key then return true end
        end
    end
    return false
end

function ns.MarkPageSeen(key)
    ns.account.newsPages = ns.account.newsPages or {}
    ns.account.newsPages[key] = Current()
end

-- The chat line after an update (true by default).
function ns.SetNewsChat(value)
    ns.account.newsChat = value and true or false
end
