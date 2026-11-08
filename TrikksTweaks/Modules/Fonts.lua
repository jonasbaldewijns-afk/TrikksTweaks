-- Module: Font
-- One clean font for the whole interface: Liberation Sans Bold, a free font
-- made to look and measure like Arial Bold (it ships with Trikks Tweaks under
-- the SIL Open Font License, see media\fonts\OFL.txt).
--
-- How (and why this way): the game draws text through "font objects"
-- (GameFontNormal, ChatFontNormal, ... about a thousand of them). We give each
-- one our font file and keep its size and outline. Font objects belong to the
-- engine, so changing them doesn't taint any Blizzard code. Blizzard's own
-- text-size setting only changes heights, so it keeps working on top of this.
--
-- Combat text and names above heads aren't font objects: the game reads them
-- from two variables once, when you log in. That's a separate option, and it
-- needs a relog (not just a /reload) to show.
local _, TT = ...
local M = TT:RegisterModule("Fonts", {
    title = "Font",
    category = "Interface",
    desc = "Use one clean font everywhere: Liberation Sans Bold (looks like Arial Bold). Optional: combat text and names above heads.",
    defaults = { worldText = false },
})

local FONT = TT.MEDIA .. "fonts\\LiberationSans-Bold.ttf"

local function ApplyTo(obj)
    if type(obj) ~= "table" or not obj.GetFont or not obj.SetFont then return end
    local file, size, flags = obj:GetFont()
    if not file or not size or TT.IsSecret(file) or TT.IsSecret(size) or size <= 0 then return end
    if file == FONT then return end
    obj:SetFont(FONT, size, flags or "")
end

-- Every font object the game knows about. New ones appear when Blizzard
-- loads a window on demand (talents, auction house, ...), so this runs again
-- then; fonts already done are skipped by the file check above.
local function ApplyAll()
    if not M.enabled or not GetFonts then return end
    for _, f in ipairs(GetFonts()) do
        local obj = type(f) == "string" and _G[f] or f
        pcall(ApplyTo, obj)
    end
end

-- Read by the game once at login (Blizzard's Lua doesn't use them, so setting
-- them doesn't taint anything).
local function ApplyWorldText()
    if not (M.enabled and M.db.worldText) then return end
    DAMAGE_TEXT_FONT = FONT
    UNIT_NAME_FONT = FONT
end

function M:Setup()
    ApplyWorldText()                -- Setup runs while the addon loads: early enough for login
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("ADDON_LOADED")
    local queued = false
    ev:SetScript("OnEvent", function()
        if not M.enabled or queued then return end
        queued = true                -- several addons can load at once: one pass after them
        C_Timer.After(0, function() queued = false; ApplyAll() end)
    end)
end

function M:OnEnable() ApplyAll() end
function M:OnDisable()
    StaticPopup_Show("TRIKKSTWEAKS_RELOAD", "Font turned off. A reload puts Blizzard's fonts back.")
end

StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] = StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] or {
    text = "%s\n\nReload your UI now?",
    button1 = RELOADUI or "Reload", button2 = LATER or "Later",
    OnAccept = function() C_UI.Reload() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function M:BuildSettings(body, page)
    local db = M.db
    local sample = body:CreateFontString(nil, "OVERLAY")
    sample:SetFont(FONT, 18, "")
    sample:SetPoint("TOPLEFT", 4, -4)
    sample:SetText("Liberation Sans Bold  -  The quick brown fox 0123456789")
    local world = TT.Check(body, "Also combat text and names above heads (needs a relog)", function(v)
        db.worldText = v
        TT.Print("log out and back in for combat text and names to change.")
    end)
    world:SetPoint("TOPLEFT", 2, -40)
    local help = TT.Label(body,
        "Changes nearly all interface text and keeps every size and outline.\n" ..
        "If you replaced the files in your WoW \"Fonts\" folder yourself, that swap\n" ..
        "still wins for the login screen and anything addons can't reach.\n\n" ..
        "Font: Liberation Sans Bold 2.1.5, SIL Open Font License 1.1\n" ..
        "(media\\fonts\\OFL.txt in the addon folder).", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -76)
    page.OnPageShow = function() world:SetChecked(db.worldText) end
end
