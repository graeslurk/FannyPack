-- Translations. All text the player sees goes through L["English text"];
-- anything without a translation for the client's language stays English.
--
-- To add a language: create Locales/<locale>.lua (for example deDE.lua)
-- that calls ns.AddTranslations("deDE", { ["English text"] = "..." }) and
-- list it in FannyPack.toc after this file.

local _, ns = ...

ns.L = setmetatable({}, {
    __index = function(_, english) return english end,
})

-- Called by a translation file: { ["English text"] = "translated text" }.
-- Only applies when the game runs in that language.
function ns.AddTranslations(locale, translations)
    if GetLocale() ~= locale then return end
    for english, translated in pairs(translations) do
        if translated ~= "" then rawset(ns.L, english, translated) end
    end
end
