-- Module: Dialog Keys
-- Use the keyboard in NPC windows and pop-ups:
--   Space (or a key you choose) = the main button: accept / continue /
--     complete / take reward / the first option / "Okay" on pop-ups
--   1-9 = pick that option (gossip, quests in a greeting, reward choices)
-- Keys are only taken while one of those windows is open; otherwise they
-- work as normal (jump, action bars, ...). WoW doesn't allow addons to take
-- over keys during combat, so it rests while you're fighting.
local _, TT = ...
local M = TT:RegisterModule("DialogKeys", {
    title = "Dialog Keys",
    category = "Quality of Life",
    desc = "Space for the main button and 1-9 for options in NPC dialogs, quests and pop-ups.",
    defaults = { key = "SPACE", numbers = true, showNumbers = true, popups = false, skipRisky = true },
})

-- Pop-ups that do something you can't undo: never confirm these by key.
local RISKY = { "DELETE", "ABANDON", "UNLEARN", "DESTROY", "DISENCHANT", "RESET", "SELL", "REPLACE", "BIND" }
local function Risky(which)
    if not which then return true end
    for _, word in ipairs(RISKY) do if which:find(word) then return true end end
    return false
end

---------------------------------------------------------------------------
-- Finding the options in the open window, top to bottom
---------------------------------------------------------------------------
local function ByPosition(list)
    table.sort(list, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
    return list
end

local function GossipButtons()
    local list = {}
    local box = GossipFrame and GossipFrame:IsShown() and GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox
    if box and box.ForEachFrame then
        box:ForEachFrame(function(f)
            -- options and quests are clickable buttons with text; titles / dividers aren't
            if f:IsShown() and f:IsObjectType("Button") and f.GetText and f:GetText() and f:IsEnabled() then
                list[#list + 1] = f
            end
        end)
    end
    return ByPosition(list)
end

local function GreetingButtons()
    local list = {}
    local panel = QuestFrameGreetingPanel
    if not (panel and panel:IsVisible()) then return list end
    local pool = panel.titleButtonPool
    if pool and pool.EnumerateActive then
        for b in pool:EnumerateActive() do if b:IsShown() then list[#list + 1] = b end end
    else
        for i = 1, 32 do
            local b = _G["QuestTitleButton" .. i]
            if b and b:IsShown() then list[#list + 1] = b end
        end
    end
    return ByPosition(list)
end

local function RewardButtons()
    local list = {}
    if not (QuestFrameRewardPanel and QuestFrameRewardPanel:IsVisible()) then return list end
    for i = 1, GetNumQuestChoices() do
        local b = _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
            or (QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons and QuestInfoRewardsFrame.RewardButtons[i])
        if b and b:IsShown() then list[#list + 1] = b end
    end
    return list
end

local function Options()
    local r = RewardButtons()
    if #r > 0 then return r end
    local g = GreetingButtons()
    if #g > 0 then return g end
    return GossipButtons()
end

---------------------------------------------------------------------------
-- Numbers in front of the options
---------------------------------------------------------------------------
local function NumberOptions()
    if not (M.enabled and M.db.showNumbers and M.db.numbers) then return end
    for i, b in ipairs(Options()) do
        if i > 9 then break end
        local text = b.GetText and b:GetText()
        if text and not TT.IsSecret(text) and not text:find("^|cff33ff99%d%.|r ") then
            b:SetText("|cff33ff99" .. i .. ".|r " .. text)
        end
    end
end
local function HookDialogs()
    if GossipFrame then
        GossipFrame:HookScript("OnShow", function() C_Timer.After(0, NumberOptions) end)
        if GossipFrame.Update then hooksecurefunc(GossipFrame, "Update", function() C_Timer.After(0, NumberOptions) end) end
    end
    if QuestFrameGreetingPanel then
        QuestFrameGreetingPanel:HookScript("OnShow", function() C_Timer.After(0, NumberOptions) end)
    end
end

---------------------------------------------------------------------------
-- The main key (Space): one action, the most obvious one for what's open
---------------------------------------------------------------------------
local function Visible(b) return b and b:IsVisible() and b:IsEnabled() end

local function MainAction()
    -- 1) a pop-up asking something (not the risky ones)
    if M.db.popups and StaticPopup_ForEachShownDialog then
        local done = false
        StaticPopup_ForEachShownDialog(function(dialog)
            if done then return end
            local b1 = dialog.button1 or (dialog.GetButton1 and dialog:GetButton1())
            if Visible(b1) and not (M.db.skipRisky and Risky(dialog.which)) then
                b1:Click(); done = true
            end
        end)
        if done then return true end
    end
    -- 2) quest window: accept / continue / take reward
    if QuestFrame and QuestFrame:IsVisible() then
        if Visible(QuestFrameAcceptButton) then AcceptQuest(); return true end
        if Visible(QuestFrameCompleteButton) then CompleteQuest(); return true end
        if Visible(QuestFrameCompleteQuestButton) then
            local choices = GetNumQuestChoices()
            local picked = QuestInfoFrame and QuestInfoFrame.itemChoice or 0
            if choices <= 1 then GetQuestReward(choices); return true end
            if picked > 0 then GetQuestReward(picked); return true end
            TT.Print("pick a reward first (number keys).")
            return true
        end
        local g = GreetingButtons()
        if g[1] then g[1]:Click(); return true end
    end
    -- 3) NPC chat: the first option
    local opts = GossipButtons()
    if opts[1] then opts[1]:Click(); return true end
    return false
end

local function NumberAction(n)
    local b = Options()[n]
    if not b then return false end
    b:Click()
    return true
end

---------------------------------------------------------------------------
-- Key catcher: sees every key, lets it through unless we used it
---------------------------------------------------------------------------
local DIGIT = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
                NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4, NUMPAD5 = 5, NUMPAD6 = 6, NUMPAD7 = 7, NUMPAD8 = 8, NUMPAD9 = 9 }

local function AnythingOpen()
    return (GossipFrame and GossipFrame:IsVisible()) or (QuestFrame and QuestFrame:IsVisible())
        or (M.db.popups and StaticPopup1 and StaticPopup1:IsVisible())
end

local catcher                    -- made in Setup; hidden (gets no keys) while the module is off
local function MakeCatcher()
    catcher = CreateFrame("Frame", nil, UIParent)
    catcher:EnableKeyboard(true)
    catcher:SetPropagateKeyboardInput(true)
    catcher:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end                   -- can't change key handling in combat
        local used = false
        if M.enabled and AnythingOpen() and not GetCurrentKeyBoardFocus()       -- not while typing
           and not IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown() then
            if key == M.db.key then
                used = MainAction()
            elseif M.db.numbers and DIGIT[key] then
                used = NumberAction(DIGIT[key])
            end
        end
        self:SetPropagateKeyboardInput(not used)                -- false = the game doesn't also get this key
    end)
end

function M:Setup() HookDialogs(); MakeCatcher() end
function M:OnEnable() catcher:Show() end
function M:OnDisable() catcher:Hide() end

---------------------------------------------------------------------------
function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Check(key, text, indent)
        local cb = TT.Check(body, text, function(v) db[key] = v end)
        cb:SetPoint("TOPLEFT", 2 + (indent and 20 or 0), -y); checks[key] = cb; y = y + 24
    end
    local kl = TT.Label(body, "Main key:")
    kl:SetPoint("TOPLEFT", 4, -y - 4)
    local keyBtn = TT.Button(body, "", 120, nil)
    keyBtn:SetPoint("TOPLEFT", 120, -y)
    keyBtn:SetScript("OnClick", function(self)
        self:SetText("Press a key...")
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false)
    end)
    keyBtn:SetScript("OnKeyDown", function(self, key)
        if key:find("SHIFT") or key:find("CTRL") or key:find("ALT") then return end
        if key ~= "ESCAPE" then db.key = key end
        self:EnableKeyboard(false)
        self:SetText(db.key)
    end)
    y = y + 32
    Check("numbers", "Number keys 1-9 pick options and rewards")
    Check("showNumbers", "Show the numbers in front of the options", true)
    Check("popups", "Main key also confirms pop-ups")
    Check("skipRisky", "Never for pop-ups that delete, abandon, sell, bind, ...", true)
    local help = TT.Label(body,
        "Keys only do this while an NPC window or pop-up is open, and not while you're\n" ..
        "typing or holding Shift / Ctrl / Alt. Not available during combat.\n" ..
        "If you also use the DialogKey addon, turn one of them off.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 8)
    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        keyBtn:SetText(db.key)
    end
end
