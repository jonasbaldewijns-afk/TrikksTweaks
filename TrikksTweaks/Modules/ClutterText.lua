-- Module: Clutter Text
-- Hide on-screen text you don't need: red error messages ("Not enough
-- energy"), the big zone name when you enter a zone, combat numbers on
-- portraits and the "Group 1..8" labels on raid frames.
local _, TT = ...
local M = TT:RegisterModule("ClutterText", {
    title = "Clutter Text",
    category = "Interface",
    desc = "Hide red error messages, the big zone name, combat numbers on portraits and raid group labels.",
    defaults = { errors = true, errorsInCombatOnly = false, zoneText = true, portraitNumbers = true, raidLabels = true },
})

local hidden = CreateFrame("Frame")
hidden:Hide()
local function Stash(f, hide)
    if not f then return end
    f.ttParent = f.ttParent or f:GetParent()
    f:SetParent(hide and hidden or f.ttParent)
end

-- Error messages: UIErrorsFrame shows red errors from the UI_ERROR_MESSAGE event.
-- Quest progress uses UI_INFO_MESSAGE and is left alone.
local function ApplyErrors()
    if not UIErrorsFrame then return end
    local hide = M.enabled and M.db.errors
    if hide and M.db.errorsInCombatOnly then hide = InCombatLockdown() end
    if hide then UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
    else UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE") end
end

local function ApplyZone()
    local hide = M.enabled and M.db.zoneText
    Stash(ZoneTextFrame, hide)
    Stash(SubZoneTextFrame, hide)
end

-- Damage / heal numbers drawn over the player and pet portraits
local function ApplyPortraits()
    local hide = M.enabled and M.db.portraitNumbers
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    Stash(main and main.HitIndicator, hide)
    Stash(PlayerHitIndicator, hide)
    Stash(PetHitIndicator, hide)
    Stash(PetFrame and PetFrame.feedbackFrame, hide)
end

-- "Group 1" ... titles above raid frame groups (and the party title)
local function ApplyRaidLabels()
    local a = (M.enabled and M.db.raidLabels) and 0 or 1
    for i = 1, 8 do
        local t = _G["CompactRaidGroup" .. i .. "Title"]
        if t then t:SetAlpha(a) end
    end
    if CompactPartyFrame and CompactPartyFrame.title then CompactPartyFrame.title:SetAlpha(a) end
end

local function ApplyAll() ApplyErrors(); ApplyZone(); ApplyPortraits(); ApplyRaidLabels() end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" then C_Timer.After(0, ApplyRaidLabels)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- combat state changes the "only in combat" error option (fired before/after the flag flips)
        C_Timer.After(0, ApplyErrors)
    else ApplyAll() end
end)

function M:OnEnable() ApplyAll() end
function M:OnDisable() ApplyAll() end

function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Check(key, text, indent)
        local cb = TT.Check(body, text, function(v) db[key] = v; ApplyAll() end)
        cb:SetPoint("TOPLEFT", 2 + (indent and 20 or 0), -y)
        checks[key] = cb
        y = y + 24
    end
    Check("errors", "Hide red error messages (\"Not enough energy\", \"Out of range\", ...)")
    Check("errorsInCombatOnly", "Only hide them during combat", true)
    Check("zoneText", "Hide the big zone name when entering a zone")
    Check("portraitNumbers", "Hide combat numbers on the player and pet portraits")
    Check("raidLabels", "Hide \"Group 1..8\" labels on raid frames")
    local help = TT.Label(body, "Quest progress messages (\"Boar killed: 3/8\") are never hidden.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 8)
    page.OnPageShow = function() for key, cb in pairs(checks) do cb:SetChecked(db[key]) end end
end
