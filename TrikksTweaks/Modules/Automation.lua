-- Module: Automation
-- Small time savers: auto repair, sell grey items, auto accept / turn in
-- quests, and instant looting. Each part has its own switch.
local _, TT = ...
local M = TT:RegisterModule("Automation", {
    title = "Automation",
    category = "Quality of Life",
    desc = "Auto repair, sell junk, quests, instant loot, summons, resurrections and more.",
    defaults = {
        repair = true, guildRepair = false, sellJunk = true, sell12 = true,
        quests = true, skipDaily = true, skipTrivial = true, skipGold = true,
        fastLoot = true,
        summons = true, resurrect = true, resNoCombat = true, pvpRelease = true, altGossip = true,
    },
})
local function On(key) return M.enabled and M.db[key] end
local function Money(c) return GetCoinTextureString and GetCoinTextureString(c) or (c .. "c") end

---------------------------------------------------------------------------
-- Vendor: repair + sell junk
---------------------------------------------------------------------------
local selling = false

local function Repair()
    if not On("repair") or not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost <= 0 then return end
    if M.db.guildRepair and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
        RepairAllItems(true)
        TT.Print("repaired for " .. Money(cost) .. " (guild bank)")
    elseif GetMoney() >= cost then
        RepairAllItems(false)
        TT.Print("repaired for " .. Money(cost))
    else
        TT.Print("not enough gold to repair (" .. Money(cost) .. ")")
    end
end

-- Find grey items worth money in your bags.
local function JunkList()
    local list = {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == 0 and not info.hasNoValue and not info.isLocked then
                local price = select(11, C_Item.GetItemInfo(info.itemID)) or 0
                list[#list + 1] = { bag = bag, slot = slot, value = price * (info.stackCount or 1) }
            end
        end
    end
    return list
end

-- Sell one item every 0.15s (selling everything in one frame can fail).
-- With "sell 12" on, stop after 12: the buyback tab only holds 12 items.
local function SellJunk()
    if not On("sellJunk") or selling then return end
    local list = JunkList()
    if #list == 0 then return end
    local limit = M.db.sell12 and math.min(12, #list) or #list
    selling = true
    local i, total = 0, 0
    local function Next()
        if not selling or not MerchantFrame:IsShown() then selling = false; return end
        i = i + 1
        if i > limit then
            selling = false
            TT.Print(string.format("sold %d junk item%s for %s%s", limit, limit == 1 and "" or "s",
                Money(total), (#list > limit) and " (more left: reopen the vendor)" or ""))
            return
        end
        local item = list[i]
        C_Container.UseContainerItem(item.bag, item.slot)    -- with a vendor open, "use" = sell
        total = total + item.value
        C_Timer.After(0.15, Next)
    end
    Next()
end

---------------------------------------------------------------------------
-- Quests: accept and turn in automatically. Hold Shift to pause.
---------------------------------------------------------------------------
local DAILY, WEEKLY = 1, 2         -- Enum.QuestFrequency values
local function Paused() return IsShiftKeyDown() end

local function SkipFrequency(freq) return M.db.skipDaily and (freq == DAILY or freq == WEEKLY) end

local function QuestDetail()
    if UnitExists("npc") and UnitIsPlayer("npc") then return end      -- shared by a player
    if QuestIsDaily and M.db.skipDaily and (QuestIsDaily() or (QuestIsWeekly and QuestIsWeekly())) then return end
    local id = GetQuestID and GetQuestID()
    if M.db.skipTrivial and id and C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(id) then return end
    AcceptQuest()
end

local function QuestProgress()
    if not IsQuestCompletable() then return end
    if M.db.skipGold and (GetQuestMoneyToGet() or 0) > 0 then return end
    CompleteQuest()
end

local function QuestComplete()
    local choices = GetNumQuestChoices()
    if choices <= 1 then GetQuestReward(choices) end   -- you pick if there's a real choice
end

-- NPCs with a gossip window (modern style)
local function Gossip()
    for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
        if q.isComplete then C_GossipInfo.SelectActiveQuest(q.questID); return end
    end
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if not (M.db.skipTrivial and q.isTrivial) and not SkipFrequency(q.frequency) then
            C_GossipInfo.SelectAvailableQuest(q.questID); return
        end
    end
end

-- NPCs with the old-style quest greeting window
local function Greeting()
    for i = 1, GetNumActiveQuests() do
        local _, isComplete = GetActiveTitle(i)
        if isComplete then SelectActiveQuest(i); return end
    end
    for i = 1, GetNumAvailableQuests() do
        local isTrivial, frequency = GetAvailableQuestInfo(i)
        if not (M.db.skipTrivial and isTrivial) and not SkipFrequency(frequency) then
            SelectAvailableQuest(i); return
        end
    end
end

---------------------------------------------------------------------------
-- Fast loot: take everything the moment the loot window is ready
---------------------------------------------------------------------------
local lastLoot = 0
local function FastLoot()
    if GetTime() - lastLoot < 0.3 then return end
    -- auto loot is on when the setting and the modifier key "disagree"
    if GetCVarBool("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then return end
    lastLoot = GetTime()
    for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
end

---------------------------------------------------------------------------
-- Summons, resurrections, battleground release, Alt = gossip
---------------------------------------------------------------------------
local function Summon()
    if not (C_SummonInfo and C_SummonInfo.GetSummonConfirmTimeLeft) then return end
    -- accepting while in combat isn't allowed; wait a moment for the popup to exist
    C_Timer.After(0.5, function()
        if UnitAffectingCombat("player") or C_SummonInfo.GetSummonConfirmTimeLeft() <= 0 then return end
        C_SummonInfo.ConfirmSummon()
        StaticPopup_Hide("CONFIRM_SUMMON")
    end)
end

local function Resurrect(name)
    if M.db.resNoCombat and name and not TT.IsSecret(name) and UnitAffectingCombat(name) then return end
    AcceptResurrect()
    for _, which in ipairs({ "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }) do
        StaticPopup_Hide(which)
    end
end

local function PvPRelease()
    local _, kind = IsInInstance()
    if kind ~= "pvp" then return end
    if HasSoulstone and HasSoulstone() then return end   -- you can res yourself: don't release
    C_Timer.After(0.5, function() if UnitIsDead("player") and not UnitIsGhost("player") then RepopMe() end end)
end

-- Hold Alt when talking to an NPC with a single gossip option and no quests: pick it.
local function AltGossip()
    if not IsAltKeyDown() then return end
    local options = C_GossipInfo.GetOptions() or {}
    local quests = #(C_GossipInfo.GetAvailableQuests() or {}) + #(C_GossipInfo.GetActiveQuests() or {})
    if #options == 1 and quests == 0 then C_GossipInfo.SelectOption(options[1].gossipOptionID) end
end

---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "QUEST_DETAIL", "QUEST_PROGRESS",
                     "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING", "LOOT_READY",
                     "CONFIRM_SUMMON", "RESURRECT_REQUEST", "PLAYER_DEAD" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if not M.enabled then return end
    if event == "CONFIRM_SUMMON" then if M.db.summons then Summon() end; return end
    if event == "RESURRECT_REQUEST" then if M.db.resurrect then Resurrect(arg1) end; return end
    if event == "PLAYER_DEAD" then if M.db.pvpRelease then PvPRelease() end; return end
    if event == "GOSSIP_SHOW" and M.db.altGossip then AltGossip() end
    if event == "MERCHANT_SHOW" then Repair(); SellJunk()
    elseif event == "MERCHANT_CLOSED" then selling = false
    elseif event == "LOOT_READY" then if M.db.fastLoot then FastLoot() end
    elseif M.db.quests and not Paused() then
        if event == "QUEST_DETAIL" then QuestDetail()
        elseif event == "QUEST_PROGRESS" then QuestProgress()
        elseif event == "QUEST_COMPLETE" then QuestComplete()
        elseif event == "GOSSIP_SHOW" then Gossip()
        elseif event == "QUEST_GREETING" then Greeting() end
    end
end)

---------------------------------------------------------------------------
function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(TT.C.dim))
        h:SetPoint("TOPLEFT", 0, -y)
        y = y + 20
    end
    local function Check(key, text, indent)
        local cb = TT.Check(body, text, function(v) db[key] = v end)
        cb:SetPoint("TOPLEFT", 2 + (indent and 20 or 0), -y)
        checks[key] = cb
        y = y + 24
    end
    Head("Vendor")
    Check("repair", "Auto repair")
    Check("guildRepair", "Use guild bank money when allowed", true)
    Check("sellJunk", "Sell grey items")
    Check("sell12", "Max 12 per visit (so you can still buy them back)", true)
    y = y + 8
    Head("Quests")
    Check("quests", "Auto accept and turn in quests (hold Shift to pause)")
    Check("skipDaily", "Skip daily / weekly quests", true)
    Check("skipTrivial", "Skip grey (trivial) quests", true)
    Check("skipGold", "Don't turn in quests that cost gold", true)
    y = y + 8
    Head("Loot")
    Check("fastLoot", "Instant loot (when auto loot is on)")
    y = y + 8
    Head("Other")
    Check("summons", "Accept summons (not in combat)")
    Check("resurrect", "Accept resurrections")
    Check("resNoCombat", "Not from players who are still in combat", true)
    Check("pvpRelease", "Release your spirit automatically in battlegrounds")
    Check("altGossip", "Hold Alt at an NPC to pick its only chat option")

    local help = TT.Label(body, "Quests with a choice of rewards are left for you to pick.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 10)

    page.OnPageShow = function() for key, cb in pairs(checks) do cb:SetChecked(db[key]) end end
end
