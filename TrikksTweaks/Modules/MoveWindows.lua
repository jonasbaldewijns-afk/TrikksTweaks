-- Module: Movable Windows
-- Drag Blizzard's windows (character, mail, merchant, quests, ...) wherever
-- you like; their position is remembered.
local _, TT = ...
local M = TT:RegisterModule("MoveWindows", {
    title = "Movable Windows",
    category = "Quality of Life",
    desc = "Drag Blizzard windows (character, merchant, mail, quests, ...) anywhere; positions are remembered.",
    defaults = { modifier = "NONE", positions = {}, imported = false },
})

-- Windows that can be moved. Load-on-demand ones are picked up when they load.
local FRAMES = {
    "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "TalentFrame", "QuestFrame", "QuestLogFrame",
    "GossipFrame", "MerchantFrame", "MailFrame", "OpenMailFrame", "BankFrame", "GuildBankFrame",
    "FriendsFrame", "AddFriendFrame", "FriendsFriendsFrame", "RaidInfoFrame", "ChannelFrame",
    "CommunitiesFrame", "CommunitiesGuildLogFrame", "CommunitiesGuildTextEditFrame",
    "CommunitiesGuildNewsFiltersFrame", "CommunitiesNotificationSettingsDialog", "CommunitiesRecruitmentDialog",
    "ClubFinderGuildFinderFrame", "ClubFinderCommunityAndGuildFinderFrame",
    "PVEFrame", "PVPMatchResults", "EncounterJournal", "AchievementFrame", "CollectionsJournal",
    "DressUpFrame", "TransmogFrame", "InspectFrame", "TradeFrame", "TaxiFrame", "FlightMapFrame",
    "ClassTrainerFrame", "ProfessionsFrame", "ProfessionsBookFrame", "ProfessionsCustomerOrdersFrame",
    "TradeSkillFrame", "AuctionHouseFrame", "MacroFrame", "AddonList", "GameMenuFrame", "SettingsPanel",
    "ChatConfigFrame", "HelpFrame", "TimeManagerFrame", "CalendarFrame", "CalendarCreateEventFrame",
    "CalendarViewHolidayFrame", "BattlefieldMapFrame", "ReadyCheckFrame", "PlayerChoiceFrame",
    "CurrencyTransferMenu", "CooldownViewerSettings", "ItemTextFrame", "PetStableFrame",
    "TabardFrame", "GuildRegistrarFrame", "ContainerFrameCombinedBags", "SplashFrame",
    "RecruitAFriendRewardsFrame", "RecruitAFriendRecruitmentFrame", "CatalogShopFrame", "LootFrame",
}

-- The four windows you had moved with EnhanceQoL, copied from its settings.
local FROM_EQOL = {
    CharacterFrame   = { "LEFT", "LEFT", 51, 5 },
    QuestFrame       = { "TOPLEFT", "TOPLEFT", 18, -119 },
    ProfessionsFrame = { "TOP", "TOP", -197.5, -104 },
    MerchantFrame    = { "TOPLEFT", "TOPLEFT", 16, -116 },
}

local function ModDown()
    local m = M.db.modifier
    if m == "SHIFT" then return IsShiftKeyDown() end
    if m == "ALT" then return IsAltKeyDown() end
    if m == "CTRL" then return IsControlKeyDown() end
    return true
end

-- Protected windows can't be moved during combat.
local function CanTouch(f) return not (InCombatLockdown() and f:IsProtected()) end

local function Restore(f)
    if not M.enabled or not f:IsShown() or not CanTouch(f) then return end
    local p = M.db.positions[f:GetName()]
    if not p then return end
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local hooked = {}
-- windows being dragged by us right now (our own table: no field on Blizzard's frame)
local moving = {}
local function Hook(name)
    local f = _G[name]
    if not f or hooked[f] or (f.IsForbidden and f:IsForbidden()) or not f.SetMovable then return end
    if not CanTouch(f) then return end
    hooked[f] = true
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    if not f:IsMouseEnabled() then f:EnableMouse(true) end
    f:RegisterForDrag("LeftButton")
    f:HookScript("OnDragStart", function(self)
        if M.enabled and ModDown() and CanTouch(self) then self:StartMoving(); moving[self] = true end
    end)
    f:HookScript("OnDragStop", function(self)
        if not moving[self] then return end
        moving[self] = nil
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)               -- we remember it, not WoW's layout cache
        local point, _, relPoint, x, y = self:GetPoint(1)
        M.db.positions[self:GetName()] = { point, relPoint, x, y }
    end)
    -- Blizzard positions windows when they open: put ours back right after.
    f:HookScript("OnShow", function(self) C_Timer.After(0, function() Restore(self) end) end)
end

local function HookAll()
    for _, name in ipairs(FRAMES) do Hook(name) end
end

function M:Setup()
    -- The panel manager re-arranges open windows (e.g. when a second one opens).
    if type(UpdateUIPanelPositions) == "function" then
        hooksecurefunc("UpdateUIPanelPositions", function()
            if not M.enabled then return end
            for f in pairs(hooked) do if f:IsShown() then Restore(f) end end
        end)
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")          -- load-on-demand windows (auction house, talents, ...)
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function()
        if M.enabled then HookAll() end
    end)
end

function M:OnLoad()
    if not M.db.imported then
        for name, pos in pairs(FROM_EQOL) do
            if not M.db.positions[name] then M.db.positions[name] = pos end
        end
        M.db.imported = true
    end
end
function M:OnEnable() HookAll() end

function M:BuildSettings(body, page)
    local db = M.db
    local l = TT.Label(body, "Drag windows with:")
    l:SetPoint("TOPLEFT")
    local radios = {}
    local choices = { { "NONE", "Just the left mouse button" }, { "SHIFT", "Shift + drag" },
                      { "ALT", "Alt + drag" }, { "CTRL", "Ctrl + drag" } }
    local function Refresh() for _, r in ipairs(radios) do r:SetChecked(db.modifier == r.value) end end
    for i, c in ipairs(choices) do
        local cb = TT.Check(body, c[2], function() db.modifier = c[1]; Refresh() end)
        cb:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -8 - (i - 1) * 24)
        cb.value = c[1]
        radios[i] = cb
    end
    local count = TT.Label(body, "", "GameFontHighlightSmall")
    count:SetPoint("TOPLEFT", radios[#radios], "BOTTOMLEFT", -2, -18)
    local reset = TT.Button(body, "Reset all positions", 140, function()
        wipe(db.positions)
        TT.Print("window positions reset (reopen the windows or /reload).")
        page.OnPageShow()
    end)
    reset:SetPoint("TOPLEFT", count, "BOTTOMLEFT", 0, -10)
    local help = TT.Label(body,
        "Drag a window by an empty spot (its title or background).\n" ..
        "Your EnhanceQoL positions for the character, quest, professions and\n" ..
        "merchant windows were copied over.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -14)
    page.OnPageShow = function()
        Refresh()
        local n = 0
        for _ in pairs(db.positions) do n = n + 1 end
        count:SetText(n .. " window" .. (n == 1 and "" or "s") .. " with a saved position")
    end
end
