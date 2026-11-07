-- Module: Hide Blizzard Frames
-- Switch off pop-ups and decorations: achievement/loot alerts, the talking
-- head, event toasts (level up etc.), the boss banner, the action bar
-- gryphons, the rested "zzz" animation and the stance bar.
local _, TT = ...
local M = TT:RegisterModule("HideFrames", {
    title = "Hide Blizzard Frames",
    category = "Interface",
    desc = "Hide alerts, talking head, event toasts, boss banner, gryphons, rested animation and the stance bar.",
    defaults = { alerts = false, talkingHead = true, toasts = false, bossBanner = true,
                 gryphons = true, rested = true, stanceBar = false },
})

local hidden = CreateFrame("Frame")
hidden:Hide()
local function Stash(f, hide)
    if not f then return end
    f.ttParent = f.ttParent or f:GetParent()
    f:SetParent(hide and hidden or f.ttParent)
end
local function On(key) return M.enabled and M.db[key] end

-- the talking head pops up whenever an NPC "speaks": close it right away
local talkingHooked = false
local function HookTalkingHead()
    if talkingHooked or not TalkingHeadFrame or not TalkingHeadFrame.PlayCurrent then return end
    talkingHooked = true
    hooksecurefunc(TalkingHeadFrame, "PlayCurrent", function(self)
        if On("talkingHead") then
            if self.CloseImmediately then self:CloseImmediately() else self:Hide() end
        end
    end)
end

local function Apply()
    Stash(AlertFrame, On("alerts"))
    Stash(EventToastManagerFrame, On("toasts"))
    -- boss banner: stop it listening for kills (a reload restores it)
    if BossBanner and On("bossBanner") then BossBanner:UnregisterAllEvents() end
    HookTalkingHead()
    -- gryphons / end caps of the main action bar
    local bar = MainActionBar or MainMenuBar
    if bar and bar.EndCaps then bar.EndCaps:SetAlpha(On("gryphons") and 0 or 1) end
    for _, cap in ipairs({ MainMenuBarLeftEndCap, MainMenuBarRightEndCap }) do
        if cap then cap:SetAlpha(On("gryphons") and 0 or 1) end
    end
    -- rested "zzz" loop on the player portrait
    local ctx = PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual
    for _, f in ipairs({ ctx and ctx.PlayerRestLoop, PlayerRestGlow, PlayerRestIcon }) do
        if f then f:SetAlpha(On("rested") and 0 or 1) end
    end
    -- stance bar: it's protected, so it's hidden with a "state driver" (the
    -- secure way to show/hide protected frames) and only outside combat
    local stance = StanceBar or StanceBarFrame
    if stance and not InCombatLockdown() then
        if On("stanceBar") then
            RegisterStateDriver(stance, "visibility", "hide")
            stance.ttDriven = true
        elseif stance.ttDriven then
            UnregisterStateDriver(stance, "visibility")
            stance.ttDriven = nil
            stance:Show()
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ADDON_LOADED")               -- the talking head loads on demand
ev:SetScript("OnEvent", function() if M.enabled then Apply() end end)

StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] = StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] or {
    text = "%s\n\nReload your UI now?",
    button1 = RELOADUI or "Reload", button2 = LATER or "Later",
    OnAccept = function() C_UI.Reload() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function M:OnEnable() Apply() end
function M:OnDisable()
    Apply()
    StaticPopup_Show("TRIKKSTWEAKS_RELOAD", "Hide Blizzard Frames turned off. A reload brings the boss banner back.")
end

function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Check(key, text)
        local cb = TT.Check(body, text, function(v)
            db[key] = v; Apply()
            if key == "bossBanner" and not v then TT.Print("the boss banner comes back after a /reload.") end
        end)
        cb:SetPoint("TOPLEFT", 2, -y)
        checks[key] = cb
        y = y + 24
    end
    Check("alerts", "Alerts (achievements, loot, ... pop-ups)")
    Check("talkingHead", "Talking head (NPC speech box)")
    Check("toasts", "Event toasts (level up, zone, ...)")
    Check("bossBanner", "Boss kill / loot banner")
    Check("gryphons", "Action bar gryphons")
    Check("rested", "Rested \"zzz\" animation on your portrait")
    Check("stanceBar", "Stance bar (changes outside combat)")
    local help = TT.Label(body, "Tip: Edit Mode can also hide the stance bar per layout.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 8)
    page.OnPageShow = function() for key, cb in pairs(checks) do cb:SetChecked(db[key]) end end
end
