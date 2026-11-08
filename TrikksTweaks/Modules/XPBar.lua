-- Module: XP Bar Text
-- Shows the text on the XP / reputation bars all the time, and can replace
-- Blizzard's "XP 2300/5000" with something easier to read at a glance:
--   45%  ·  2,750 to go  ·  +20% rested
--
-- How: "always show" is Blizzard's own setting (the xpBarText CVar, the same
-- one the bars read), so nothing is hooked for that. The short text is a
-- post-hook on the XP bar's UpdateCurrentText: Blizzard writes its text, then
-- we overwrite it. XP numbers are never secret, but they're checked anyway.
local _, TT = ...
local M = TT:RegisterModule("XPBar", {
    title = "XP Bar Text",
    category = "Interface",
    desc = "Always show the text on the XP / reputation bars, and a shorter XP text (percent, XP to go, rested).",
    defaults = { always = true, short = true, rested = true },
})

local IsSecret = TT.IsSecret

local function SetAlways()
    if not (SetCVar and GetCVar) then return end
    if M.enabled and M.db.always then
        -- remember what it was, so switching off puts it back
        if M.db.prevCVar == nil then M.db.prevCVar = GetCVar("xpBarText") or "0" end
        SetCVar("xpBarText", "1")
    elseif M.db.prevCVar ~= nil then
        SetCVar("xpBarText", M.db.prevCVar)
        M.db.prevCVar = nil
    end
    if StatusTrackingBarManager and StatusTrackingBarManager.UpdateBarTextVisibility then
        StatusTrackingBarManager:UpdateBarTextVisibility()
    end
end

local function ShortText(bar)
    if not (M.enabled and M.db.short) then return end
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if IsSecret(cur) or IsSecret(max) or not max or max <= 0 then return end
    local text = string.format("%d%%  ·  %s to go", math.floor(cur / max * 100), BreakUpLargeNumbers(max - cur))
    local rested = GetXPExhaustion and GetXPExhaustion()
    if M.db.rested and rested and not IsSecret(rested) and rested > 0 then
        text = text .. string.format("  ·  +%d%% rested", math.floor(rested / max * 100))
    end
    bar.OverlayFrame.Text:SetText(text)
end

-- the XP bar lives in one of the two bar containers (main / secondary)
local function ExpBars()
    local list = {}
    local mgr = StatusTrackingBarManager
    local idx = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum and StatusTrackingBarInfo.BarsEnum.Experience
    if not (mgr and idx) then return list end
    for _, c in ipairs(mgr.barContainers or {}) do
        local bar = c.bars and c.bars[idx]
        if bar and bar.OverlayFrame and bar.OverlayFrame.Text then list[#list + 1] = bar end
    end
    return list
end

-- Blizzard's own text back (or ours), right away
local function Refresh()
    for _, bar in ipairs(ExpBars()) do
        if bar.UpdateCurrentText then bar:UpdateCurrentText() end
    end
end

function M:Setup()
    for _, bar in ipairs(ExpBars()) do
        if type(bar.UpdateCurrentText) == "function" then hooksecurefunc(bar, "UpdateCurrentText", ShortText) end
    end
end

function M:OnEnable() SetAlways(); Refresh() end
function M:OnDisable() SetAlways(); Refresh() end

function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Check(key, text, fn)
        local cb = TT.Check(body, text, function(v) db[key] = v; if M.enabled then fn() end end)
        cb:SetPoint("TOPLEFT", 2, -y)
        checks[key] = cb
        y = y + 24
    end
    Check("always", "Always show the text (XP, reputation, honor)", SetAlways)
    Check("short", "Short XP text: 45%  ·  2,750 to go", Refresh)
    Check("rested", "Add rested XP:  ·  +20% rested", Refresh)
    local help = TT.Label(body,
        "\"Always show\" is Blizzard's own setting; turning this module off puts back\n" ..
        "what it was before. Reputation and honor keep Blizzard's text.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 8)
    page.OnPageShow = function() for key, cb in pairs(checks) do cb:SetChecked(db[key]) end end
end
