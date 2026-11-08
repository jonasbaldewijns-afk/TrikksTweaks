-- Module: XP Bar
-- The XP bar, easier to read:
--   * text always visible, shorter: 45%  ·  2,750 to go  ·  +20% rested  ·  +12% from quests
--   * always blue (Blizzard turns it purple while you have rested XP)
--   * a band showing how far your rested XP reaches
--   * a gold band for the XP waiting in quests that are complete (ready to hand in)
--
-- How: "always show" is Blizzard's own setting (the xpBarText CVar, the same
-- one the bars read). The text, the colour and the bands are post-hooks on the
-- XP bar (UpdateCurrentText, UpdateStatusBarTextures, Update): Blizzard does
-- its part, then we adjust. The bands are our own textures on the bar, sized
-- from UnitXP / UnitXPMax, GetXPExhaustion and the quest log.
local _, TT = ...
local M = TT:RegisterModule("XPBar", {
    title = "XP Bar",
    category = "Interface",
    desc = "XP bar: text always shown and shorter, always blue, bands for rested XP and for completed quests.",
    defaults = { always = true, short = true, rested = true, blue = true, restedBand = true, questBand = true, questText = true },
})

local IsSecret = TT.IsSecret
local BLUE_FILL = "UI-HUD-ExperienceBar-Fill-Experience"
local BLUE_FLARE = "UI-HUD-ExperienceBar-Flare-XP-2x-Flipbook"
local BLUE_LEVELUP = "UI-HUD-ExperienceBar-Fill-Experience-2x-Flipbook"
local REST_COLOR = { 0.35, 0.55, 1, 0.35 }
local QUEST_COLOR = { 1, 0.78, 0.1, 0.55 }

local function Num(v) if v == nil or IsSecret(v) then return nil end return tonumber(v) end

---------------------------------------------------------------------------
-- "Always show the text": Blizzard's own setting
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- XP waiting in completed quests (ready to hand in)
---------------------------------------------------------------------------
local questXP, questDirty = 0, true
local function QuestXP()
    if not questDirty then return questXP end
    questDirty = false
    local total = 0
    local QL = C_QuestLog
    if QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.IsComplete and GetQuestLogRewardXP then
        for i = 1, (QL.GetNumQuestLogEntries() or 0) do
            local info = QL.GetInfo(i)
            local id = info and not info.isHeader and info.questID
            if id and not IsSecret(id) and QL.IsComplete(id) then
                local ok, xp = pcall(GetQuestLogRewardXP, id)
                xp = ok and Num(xp) or nil
                if xp and xp > 0 then total = total + xp end
            end
        end
    end
    questXP = total
    return total
end

---------------------------------------------------------------------------
-- The XP bar(s): in one of the two bar containers (main / secondary)
---------------------------------------------------------------------------
local function ExpBars()
    local list = {}
    local mgr = StatusTrackingBarManager
    local idx = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum and StatusTrackingBarInfo.BarsEnum.Experience
    if not (mgr and idx) then return list end
    for _, c in ipairs(mgr.barContainers or {}) do
        local bar = c.bars and c.bars[idx]
        if bar and bar.OverlayFrame and bar.OverlayFrame.Text and bar.StatusBar then list[#list + 1] = bar end
    end
    return list
end

local function ShortText(bar)
    if not (M.enabled and M.db.short) then return end
    local cur, max = Num(UnitXP("player")), Num(UnitXPMax("player"))
    if not cur or not max or max <= 0 then return end
    local text = string.format("%d%%  ·  %s to go", math.floor(cur / max * 100), BreakUpLargeNumbers(max - cur))
    local rested = Num(GetXPExhaustion and GetXPExhaustion())
    if M.db.rested and rested and rested > 0 then
        text = text .. string.format("  ·  +%d%% rested", math.floor(rested / max * 100))
    end
    local q = M.db.questText and QuestXP() or 0
    if q > 0 then text = text .. string.format("  ·  |cffffd040+%d%% from quests|r", math.floor(q / max * 100)) end
    bar.OverlayFrame.Text:SetText(text)
end

-- always blue: right after Blizzard picked purple (rested) or blue
local function Blue(bar, isRested)
    if not (M.enabled and M.db.blue and isRested) then return end
    local sb = bar.StatusBar
    if sb.SetBarTexture then pcall(sb.SetBarTexture, sb, BLUE_FILL) end
    if sb.SetAnimationTextures then pcall(sb.SetAnimationTextures, sb, BLUE_FLARE, BLUE_LEVELUP) end
end

-- the two bands, drawn from where your XP is now
local bands = setmetatable({}, { __mode = "k" })   -- bar -> { rest = tex, quest = tex }
local function Band(sb, sub, color)
    local t = sb:CreateTexture(nil, "ARTWORK", nil, sub)
    t:SetColorTexture(color[1], color[2], color[3], color[4])
    t:Hide()
    return t
end
local function PlaceBand(tex, sb, from, amount, max)
    local w = sb:GetWidth()
    if not (amount and amount > 0 and w and w > 0) or from >= max then tex:Hide(); return end
    local x1 = from / max * w
    local x2 = math.min(from + amount, max) / max * w
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", sb, "TOPLEFT", x1, 0)
    tex:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", x1, 0)
    tex:SetWidth(math.max(1, x2 - x1))
    tex:Show()
end
local function Bands(bar)
    local sb = bar.StatusBar
    local b = bands[bar]
    if not b then
        b = { rest = Band(sb, 1, REST_COLOR), quest = Band(sb, 2, QUEST_COLOR) }
        bands[bar] = b
        sb:HookScript("OnSizeChanged", function() Bands(bar) end)
    end
    local on = M.enabled
    -- Blizzard's own (faint) rested marker: hidden while our band shows
    local blizz = bar.ExhaustionLevelFillBar
    if blizz then blizz:SetAlpha(on and M.db.restedBand and 0 or 1) end
    local cur, max = Num(UnitXP("player")), Num(UnitXPMax("player"))
    if not (on and cur and max and max > 0) then b.rest:Hide(); b.quest:Hide(); return end
    if M.db.restedBand then PlaceBand(b.rest, sb, cur, Num(GetXPExhaustion and GetXPExhaustion()), max) else b.rest:Hide() end
    if M.db.questBand then PlaceBand(b.quest, sb, cur, QuestXP(), max) else b.quest:Hide() end
end

-- everything again, right away (also puts Blizzard's look back when switched off)
local function Refresh()
    for _, bar in ipairs(ExpBars()) do
        if bar.Update then bar:Update() end           -- Blizzard's own textures and text first
        -- the colour: Blizzard only picks it when the rested state changes, so pick it now
        local rested = Num(GetXPExhaustion and GetXPExhaustion())
        if rested and rested > 0 and bar.UpdateStatusBarTextures then bar:UpdateStatusBarTextures(true) end
        if bar.UpdateCurrentText then bar:UpdateCurrentText() end
        Bands(bar)
    end
end

function M:Setup()
    for _, bar in ipairs(ExpBars()) do
        if type(bar.UpdateCurrentText) == "function" then hooksecurefunc(bar, "UpdateCurrentText", ShortText) end
        if type(bar.UpdateStatusBarTextures) == "function" then hooksecurefunc(bar, "UpdateStatusBarTextures", Blue) end
        if type(bar.Update) == "function" then hooksecurefunc(bar, "Update", Bands) end
    end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
        ev:RegisterEvent(e)
    end
    local pending = false
    ev:SetScript("OnEvent", function(_, event)
        if not M.enabled then return end
        if event == "QUEST_LOG_UPDATE" or event == "PLAYER_LEVEL_UP" then questDirty = true end
        if pending then return end
        pending = true
        C_Timer.After(0.2, function() pending = false; Refresh() end)
    end)
end

function M:OnEnable() questDirty = true; SetAlways(); Refresh() end
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
    Check("rested", "...with rested XP:  ·  +20% rested", Refresh)
    Check("questText", "...with completed quests:  ·  +12% from quests", Refresh)
    y = y + 6
    Check("blue", "Always blue (Blizzard makes it purple while you have rested XP)", Refresh)
    Check("restedBand", "Band showing how far your rested XP reaches", Refresh)
    Check("questBand", "Gold band for XP from quests that are complete (ready to hand in)", Refresh)
    local help = TT.Label(body,
        "\"Always show\" is Blizzard's own setting; turning this module off puts back what it\n" ..
        "was before. Reputation and honor keep Blizzard's text.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 8)
    page.OnPageShow = function() for key, cb in pairs(checks) do cb:SetChecked(db[key]) end end
end
