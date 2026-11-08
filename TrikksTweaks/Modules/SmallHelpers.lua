-- Module: Small Helpers
-- Skip cutscenes without the "are you sure?" box, type DELETE for you when
-- destroying an item, warn when your bags are full while looting, and remove
-- transform buffs you don't want (outside combat).
local _, TT = ...
local M = TT:RegisterModule("SmallHelpers", {
    title = "Small Helpers",
    category = "Quality of Life",
    desc = "Faster cutscene skip, easy item destroy, full-bags loot warning, remove unwanted transforms.",
    defaults = { skipMovies = false, easyDestroy = false, bagsFull = true, removeTransforms = false, transforms = {} },
})
local function On(key) return M.enabled and M.db[key] end

---------------------------------------------------------------------------
-- Cutscenes: when Blizzard asks "skip this?", answer yes for you
---------------------------------------------------------------------------
local function HookHelpers()
    if CinematicFrame and CinematicFrame.closeDialog then
        CinematicFrame.closeDialog:HookScript("OnShow", function(self)
            if not On("skipMovies") then return end
            self:Hide()
            if CinematicFrame_CancelCinematic then CinematicFrame_CancelCinematic() else StopCinematic() end
        end)
    end
    if MovieFrame and MovieFrame.CloseDialog then
        MovieFrame.CloseDialog:HookScript("OnShow", function(self)
            if not On("skipMovies") then return end
            self:Hide()
            MovieFrame:StopMovie()
        end)
    end

    ---------------------------------------------------------------------------
    -- Destroying a good item asks you to type DELETE: fill it in
    ---------------------------------------------------------------------------
    hooksecurefunc("StaticPopup_Show", function(which)
        if not On("easyDestroy") then return end
        if which ~= "DELETE_GOOD_ITEM" and which ~= "DELETE_GOOD_QUEST_ITEM" then return end
        local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
        local eb = dialog and (dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox()))
        if eb then eb:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE") end
    end)
end

---------------------------------------------------------------------------
-- Bags full while looting: big warning in the middle of the screen
---------------------------------------------------------------------------
local warn                      -- made the first time it's needed
local function MakeWarn()
    warn = CreateFrame("Frame", nil, UIParent)
    warn:SetSize(400, 40)
    warn:SetPoint("TOP", 0, -180)
    warn:Hide()
    local warnText = warn:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    warnText:SetPoint("CENTER")
    warnText:SetText("|cffff5555Your bags are full!|r")
end
local lastWarn = 0
local function BagsFull()
    if GetTime() - lastWarn < 5 then return end
    local free = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0) end
    if free > 0 then return end
    lastWarn = GetTime()
    if not warn then MakeWarn() end
    warn:Show(); warn:SetAlpha(1)
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    C_Timer.After(3, function() warn:Hide() end)
end

---------------------------------------------------------------------------
-- Remove transforms (only possible outside combat)
---------------------------------------------------------------------------
local function RemoveTransforms()
    if not On("removeTransforms") or InCombatLockdown() or #M.db.transforms == 0 then return end
    local want = {}
    for _, id in ipairs(M.db.transforms) do want[id] = true end
    for i = 1, 40 do
        local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then break end
        if not TT.IsSecret(a) and a.spellId and not TT.IsSecret(a.spellId) and want[a.spellId] then
            pcall(CancelUnitBuff, "player", i, "HELPFUL")
            break                                  -- indexes shift after cancelling; next UNIT_AURA continues
        end
    end
end

function M:Setup()
    HookHelpers()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("LOOT_READY")
    ev:RegisterUnitEvent("UNIT_AURA", "player")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if not M.enabled then return end
        if event == "LOOT_READY" then if M.db.bagsFull then BagsFull() end
        else RemoveTransforms() end
    end)
end

function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Check(key, text)
        local cb = TT.Check(body, text, function(v) db[key] = v end)
        cb:SetPoint("TOPLEFT", 2, -y); checks[key] = cb; y = y + 24
    end
    Check("skipMovies", "Skip cutscenes without the \"are you sure?\" box (press Esc)")
    Check("easyDestroy", "Type DELETE for you when destroying an item")
    Check("bagsFull", "Warn when your bags are full while looting")
    Check("removeTransforms", "Remove these transform buffs automatically (outside combat):")
    local list = TT.IDList(body, 360, 180, db.transforms, function(id)
        local name = TT.SpellInfo(id)
        return (name or "Unknown") .. "  |cff888888" .. id .. "|r"
    end, RemoveTransforms)
    list:SetPoint("TOPLEFT", 22, -y - 4)
    local help = TT.Label(body, "Add the buff's spell ID (hold Ctrl over the buff to see it).", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 22, -y - 192)
    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        list.Refresh()
    end
end
