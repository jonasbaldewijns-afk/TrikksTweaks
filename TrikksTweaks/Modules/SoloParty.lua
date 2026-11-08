-- Module: Solo Party Frame
-- Keeps the raid-style party frame on screen while you're solo (it already
-- has a slot for you), so your health is always read from the same place,
-- and optionally hides the regular player frame.
--
-- How (and why this way): Blizzard hides the party frame with
--   ShouldShowPartyFrames() = in a group and not in a raid
-- The frame itself works fine solo: slot 1 is always "player" outside raids.
-- So right after Blizzard hides it, we show it again. We only call Show() on
-- the frame (a plain C function) and never Blizzard's own party code: running
-- that from an addon taints it, and tainted code can't read the "secret"
-- health values on Midnight-era clients (see Party Position for the same rule).
-- Party frames are protected in combat, so anything there waits until it ends.
--
-- The player frame is faded out (alpha 0) and stops taking clicks instead of
-- being hidden: hiding a protected frame from an addon is what causes taint.
-- Your class resource (combo points, ...) sits inside the player frame, so it
-- fades with it.
local _, TT = ...
local M = TT:RegisterModule("SoloParty", {
    title = "Solo Party Frame",
    category = "Interface",
    desc = "Show the raid-style party frame (with you in it) while solo, and optionally hide the player frame.",
    defaults = { soloParty = true, hidePlayer = true },
})

local pending = false          -- something to do once combat ends

local function RaidStyle()
    return EditModeManagerFrame and EditModeManagerFrame.UseRaidStylePartyFrames
        and EditModeManagerFrame:UseRaidStylePartyFrames()
end

---------------------------------------------------------------------------
-- Party frame
---------------------------------------------------------------------------
local function KeepPartyShown()
    local f = CompactPartyFrame
    if not (f and M.enabled and M.db.soloParty) then return end
    if IsInGroup() or not RaidStyle() then return end   -- grouped: Blizzard shows it itself
    if f:IsShown() then return end
    if InCombatLockdown() then pending = true; return end
    f:Show()
end

-- solo again after turning it off: put Blizzard's "hidden while solo" back
local function ReleaseParty()
    local f = CompactPartyFrame
    if f and f:IsShown() and not IsInGroup() and not InCombatLockdown() then f:Hide() end
end

local hooked = false
local function HookParty()
    if hooked or not CompactPartyFrame then return end
    hooked = true
    -- runs right after Blizzard decided shown / hidden
    hooksecurefunc(CompactPartyFrame, "UpdateVisibility", KeepPartyShown)
    CompactPartyFrame:HookScript("OnHide", function() C_Timer.After(0, KeepPartyShown) end)
end

---------------------------------------------------------------------------
-- Player frame
---------------------------------------------------------------------------
local playerHidden = false
local function ApplyPlayer()
    if not PlayerFrame then return end
    local hide = M.enabled and M.db.hidePlayer
    if InCombatLockdown() then
        if hide ~= playerHidden then pending = true end
        if hide then PlayerFrame:SetAlpha(0) end           -- alpha is allowed in combat; clicks wait
        return
    end
    playerHidden = hide and true or false
    TT.playerFrameHidden = playerHidden                     -- Mouseover Bars leaves it alone then
    PlayerFrame:SetAlpha(hide and 0 or 1)
    PlayerFrame:EnableMouse(not hide)
end

---------------------------------------------------------------------------
local function Apply()
    if M.enabled and RaidStyle() == false and M.db.soloParty and not M.warned then
        M.warned = true
        TT.Print("Solo Party Frame needs |cffffffffUse Raid-Style Party Frames|r on (Edit Mode > Party Frames).")
    end
    HookParty()
    if M.enabled and M.db.soloParty then KeepPartyShown() else ReleaseParty() end
    ApplyPlayer()
end

function M:Setup()
    -- the party frame is only made once raid-style party frames are switched on
    if CompactPartyFrame_Generate then
        hooksecurefunc("CompactPartyFrame_Generate", function() HookParty(); KeepPartyShown() end)
    end
    if PlayerFrame then
        -- vehicles and loading screens can bring it back
        PlayerFrame:HookScript("OnShow", function() if playerHidden then PlayerFrame:SetAlpha(0) end end)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("UNIT_EXITED_VEHICLE")
    ev:SetScript("OnEvent", function(_, event, unit)
        if not M.enabled then return end
        if event == "UNIT_EXITED_VEHICLE" and unit ~= "player" then return end
        if event == "PLAYER_REGEN_ENABLED" and not pending then return end
        pending = false
        C_Timer.After(0, Apply)             -- after Blizzard's own handlers for the same event
    end)
end

function M:OnEnable() Apply() end
function M:OnDisable() Apply() end

function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Check(key, text)
        local cb = TT.Check(body, text, function(v) db[key] = v; if M.enabled then Apply() end end)
        cb:SetPoint("TOPLEFT", 2, -y)
        checks[key] = cb
        y = y + 24
    end
    Check("soloParty", "Show the party frame while solo (you're in it)")
    Check("hidePlayer", "Hide the player frame (also hides combo points / class resource)")
    local help = TT.Label(body,
        "Needs \"Use Raid-Style Party Frames\" on: Edit Mode > Party Frames.\n" ..
        "Changes made in combat apply as soon as combat ends.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 8)
    page.OnPageShow = function() for key, cb in pairs(checks) do cb:SetChecked(db[key]) end end
end
