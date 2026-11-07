-- Module: Spell ID
-- Hold a modifier while hovering a spell/aura to see its spell ID, and press
-- modifier + copy key to open a box where Ctrl+C copies it.
local _, TT = ...
local M = TT:RegisterModule("SpellID", {
    title = "IDs & Links",
    category = "Quality of Life",
    desc = "Spell IDs on tooltips (hold a key) and copyable Wowhead links for quests.",
    defaults = { modifier = "CTRL", copyEnabled = true, copyKey = "C", questLinks = true },
})

local currentID
local MOD_KEYS = {
    CTRL = { LCTRL = true, RCTRL = true }, ALT = { LALT = true, RALT = true },
    SHIFT = { LSHIFT = true, RSHIFT = true },
}

local function HoverModDown()
    local m = M.db.modifier
    if m == "CTRL" then return IsControlKeyDown() end
    if m == "ALT" then return IsAltKeyDown() end
    if m == "SHIFT" then return IsShiftKeyDown() end
    return true                                       -- "NONE" = always
end
local function CopyModDown()
    if M.db.modifier == "NONE" then return IsControlKeyDown() end
    return HoverModDown()
end

-- Tooltip line (TooltipDataProcessor runs this after a tooltip is built)
local function AddSpellID(tooltip, data)
    if not M.enabled then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if not data or not data.id or TT.IsSecret(data.id) then return end
    if tooltip == GameTooltip then currentID = data.id end
    if not HoverModDown() then return end
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("Spell ID", tostring(data.id), 0.5, 0.8, 1, 1, 1, 1)
    if M.db.copyEnabled then
        local mod = M.db.modifier == "NONE" and "CTRL" or M.db.modifier
        tooltip:AddLine(mod:sub(1, 1) .. mod:sub(2):lower() .. "+" .. M.db.copyKey .. " to copy", 0.6, 0.6, 0.6)
    end
    tooltip:Show()
end
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AddSpellID)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, AddSpellID)
GameTooltip:HookScript("OnHide", function() currentID = nil end)

-- Copy box: addons can't reach the clipboard, so we pre-select the text
-- and the player's own Ctrl+C copies it.
local copyBox = CreateFrame("Frame", "TrikksTweaksCopyFrame", UIParent, "BackdropTemplate")
copyBox:SetSize(360, 70)
copyBox:SetPoint("CENTER", 0, 150)
copyBox:SetFrameStrata("DIALOG")
TT.Flat(copyBox, TT.C.bg, TT.C.accent)
copyBox:Hide()
tinsert(UISpecialFrames, "TrikksTweaksCopyFrame")
local cl = TT.Label(copyBox, "Ctrl+C to copy, Esc to close", "GameFontNormal")
cl:SetPoint("TOP", 0, -10)

local edit = TT.EditBox(copyBox, 330, 22)
edit:SetPoint("BOTTOM", 0, 12)
edit:SetJustifyH("CENTER")
edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
edit:SetScript("OnEnterPressed", function() copyBox:Hide() end)
edit:SetScript("OnTextChanged", function(self, user)          -- read-only
    if user then self:SetText(copyBox.value or ""); self:HighlightText() end
end)
edit:SetScript("OnKeyDown", function(_, key)
    if key == "C" and IsControlKeyDown() then C_Timer.After(0.1, function() copyBox:Hide() end) end
end)

local function ShowCopy(id)
    copyBox.value = tostring(id)
    copyBox:Show()
    edit:SetText(copyBox.value); edit:SetFocus(); edit:HighlightText()
end

-- Watches keys, passes them all through except our copy combo on a spell tooltip.
local keyWatcher = CreateFrame("Frame", nil, UIParent)
keyWatcher:EnableKeyboard(true)
keyWatcher:SetPropagateKeyboardInput(true)
keyWatcher:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end              -- propagation is locked in combat
    if M.enabled and M.db.copyEnabled and key == M.db.copyKey and currentID
       and GameTooltip:IsShown() and CopyModDown() and not copyBox:IsShown() then
        self:SetPropagateKeyboardInput(false)
        ShowCopy(currentID)
    else
        self:SetPropagateKeyboardInput(true)
    end
end)

-- Rebuild the tooltip when the modifier is pressed/released
local ev = CreateFrame("Frame")
ev:RegisterEvent("MODIFIER_STATE_CHANGED")
ev:SetScript("OnEvent", function(_, _, key)
    if not M.enabled then return end
    local keys = MOD_KEYS[M.db.modifier]
    if keys and keys[key] and GameTooltip:IsShown() and GameTooltip.RefreshData then GameTooltip:RefreshData() end
end)

---------------------------------------------------------------------------
-- Wowhead quest links
---------------------------------------------------------------------------
local WOWHEAD = "https://www.wowhead.com/forever/quest=%d"

local function QuestIDFrom(owner, ctx)
    if ctx and (ctx.questID or ctx.questId) then return ctx.questID or ctx.questId end
    if not owner then return end
    if owner.questID then return owner.questID end
    if owner.GetQuestID then
        local ok, id = pcall(owner.GetQuestID, owner)
        if ok and id then return id end
    end
    if owner.questLogIndex and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(owner.questLogIndex)
        if info then return info.questID end
    end
end

local function CopyQuestLink(id)
    if id and id > 0 then ShowCopy(WOWHEAD:format(id)) end
end

-- Right-click menus of the quest log and the objective tracker get an extra entry.
-- (Blizzard's menu system lets addons add entries by menu "tag".)
if Menu and Menu.ModifyMenu then
    local function AddEntry(owner, root, ctx)
        if not (M.enabled and M.db.questLinks) then return end
        local id = QuestIDFrom(owner, ctx)
        if not id and owner and owner.GetName and owner:GetName() == "ObjectiveTrackerFrame" then
            local focus = GetMouseFoci and GetMouseFoci()[1]
            local parent = focus and focus.GetParent and focus:GetParent()
            id = parent and parent.poiQuestID
        end
        if not id then return end
        root:CreateDivider()
        root:CreateButton("Copy Wowhead link", function() CopyQuestLink(id) end)
    end
    Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", AddEntry)
    Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", AddEntry)
end

-- A small "Wowhead" button on the quest window an NPC shows you.
if QuestFrame then
    local wh = TT.Button(QuestFrame, "Wowhead", 70, function() CopyQuestLink(GetQuestID and GetQuestID()) end)
    wh:SetPoint("TOPRIGHT", QuestFrame, "TOPRIGHT", -30, -30)
    wh:SetFrameLevel(QuestFrame:GetFrameLevel() + 10)
    QuestFrame:HookScript("OnShow", function()
        local id = GetQuestID and GetQuestID()
        wh:SetShown(M.enabled and M.db.questLinks and id and id > 0)
    end)
    wh:Hide()
end

-- /wh <quest name or id> : link for a quest in your log
SLASH_TTWOWHEAD1 = "/wh"
SlashCmdList.TTWOWHEAD = function(msg)
    msg = strtrim(msg or "")
    local id = tonumber(msg)
    if not id and msg ~= "" then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.title and info.title:lower():find(msg:lower(), 1, true) then
                id = info.questID; break
            end
        end
    end
    if id then CopyQuestLink(id) else TT.Print("usage: /wh <quest ID or part of a quest name from your log>") end
end

function M:OnDisable() copyBox:Hide() end

function M:BuildSettings(body, page)
    local l = TT.Label(body, "Show spell ID while holding:")
    l:SetPoint("TOPLEFT")
    local radios = {}
    local choices = { { "CTRL", "Ctrl" }, { "ALT", "Alt" }, { "SHIFT", "Shift" }, { "NONE", "Always (no key)" } }
    local function Refresh()
        for _, r in ipairs(radios) do r:SetChecked(M.db.modifier == r.value) end
    end
    for i, c in ipairs(choices) do
        local cb = TT.Check(body, c[2], function() M.db.modifier = c[1]; Refresh() end)
        cb:SetPoint("TOPLEFT", l, "BOTTOMLEFT", -2, -4 - (i - 1) * 26)
        cb.value = c[1]
        radios[i] = cb
    end

    local copyCB = TT.Check(body, "Enable copy (modifier + key opens a copy box, out of combat)",
        function(v) M.db.copyEnabled = v end)
    copyCB:SetPoint("TOPLEFT", radios[#radios], "BOTTOMLEFT", 0, -16)

    local kl = TT.Label(body, "Copy key:")
    kl:SetPoint("TOPLEFT", copyCB, "BOTTOMLEFT", 4, -12)
    local keyBtn = TT.Button(body, "", 120, nil)
    keyBtn:SetPoint("LEFT", kl, "RIGHT", 10, 0)
    local function RefreshKey() keyBtn:SetText(M.db.copyKey) end
    keyBtn:SetScript("OnClick", function(self)
        self:SetText("Press a key...")
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false)
    end)
    keyBtn:SetScript("OnKeyDown", function(self, key)
        if key:find("SHIFT") or key:find("CTRL") or key:find("ALT") then return end
        if key ~= "ESCAPE" then M.db.copyKey = key end
        self:EnableKeyboard(false)
        RefreshKey()
    end)

    local ql = TT.Check(body, "Wowhead links for quests (right-click a quest, the Wowhead button\n on quest windows, or /wh <quest name>)", function(v) M.db.questLinks = v end)
    ql:SetPoint("TOPLEFT", kl, "BOTTOMLEFT", -4, -24)

    page.OnPageShow = function()
        Refresh(); copyCB:SetChecked(M.db.copyEnabled); RefreshKey(); ql:SetChecked(M.db.questLinks)
    end
end
