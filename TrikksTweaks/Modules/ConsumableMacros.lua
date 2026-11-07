-- Module: Consumable Macros
-- Keeps a few character macros pointed at the best item in your bags:
--   TT Heal    - healthstone or best healing potion
--   TT Drink   - best drink (optionally conjured water first)
--   TT Food    - best food
--   TT Bandage - best bandage
-- Put the macros on your bars once; they update themselves when your bags change.
local _, TT = ...
local M = TT:RegisterModule("ConsumableMacros", {
    title = "Consumable Macros",
    category = "Quality of Life",
    desc = "Self-updating macros that always use your best potion / healthstone, drink, food and bandage.",
    defaults = { heal = true, drink = true, food = false, bandage = true,
                 preferStone = true, preferConjured = true },
})

-- Item classes (GetItemInfoInstant): consumables are class 0.
local CONSUMABLE, POTION, FOOD_DRINK, BANDAGE = 0, 1, 5, 7

local MACROS = {
    { key = "heal",    name = "TT Heal",    label = "healing potion or healthstone" },
    { key = "drink",   name = "TT Drink",   label = "drink" },
    { key = "food",    name = "TT Food",    label = "food" },
    { key = "bandage", name = "TT Bandage", label = "bandage" },
}

local function ItemSpellName(itemID)
    local name = C_Item.GetItemSpell and C_Item.GetItemSpell(itemID) or (GetItemSpell and GetItemSpell(itemID))
    return name or ""
end

-- What kind of consumable is this? Returns "heal", "drink", "food", "bandage" or nil.
local function Kind(itemID, itemName)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= CONSUMABLE then return end
    local spell = ItemSpellName(itemID):lower()
    if itemName and itemName:find("Healthstone") then return "heal", true end
    if subclassID == POTION and spell:find("heal") then return "heal" end
    if subclassID == BANDAGE then return "bandage" end
    if subclassID == FOOD_DRINK then
        if spell:find("drink") or spell:find("refreshment") then return "drink" end
        if spell:find("food") then return "food" end
    end
end

-- Score items so the best one wins: usable level first, then item level.
local function Score(itemID, isStone, name)
    local _, _, _, itemLevel, minLevel = C_Item.GetItemInfo(itemID)
    if (minLevel or 0) > UnitLevel("player") then return nil end
    local score = (minLevel or 0) * 1000 + (itemLevel or 0)
    if isStone and M.db.preferStone then score = score + 1e7 end
    if name and name:find("^Conjured") and M.db.preferConjured then score = score + 1e7 end
    return score
end

local function BestItems()
    local best = {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local name = C_Item.GetItemInfo(info.itemID)
                local kind, isStone = Kind(info.itemID, name)
                if kind then
                    local score = Score(info.itemID, isStone, name)
                    if score and (not best[kind] or score > best[kind].score) then
                        best[kind] = { id = info.itemID, score = score }
                    end
                end
            end
        end
    end
    return best
end

local lastBody = {}
local function SetMacro(name, body)
    if lastBody[name] == body then return end
    local index = GetMacroIndexByName(name)
    if index == 0 then
        local _, perChar = GetNumMacros()
        if perChar >= (MAX_CHARACTER_MACROS or 18) then
            TT.Print("no free character macro slot for " .. name .. ".")
            return
        end
        CreateMacro(name, "INV_MISC_QUESTIONMARK", body, true)   -- true = character macro
    else
        EditMacro(index, name, nil, body)
    end
    lastBody[name] = body
end

local pending
local function Update()
    if not M.enabled then return end
    -- Macros can't be created or changed during combat.
    if InCombatLockdown() then pending = true; return end
    pending = false
    local best = BestItems()
    for _, m in ipairs(MACROS) do
        if M.db[m.key] then
            local item = best[m.key]
            local body = item and ("#showtooltip\n/use item:" .. item.id)
                or ("#showtooltip\n/run print(\"|cff33ff99Trikks Tweaks:|r no " .. m.label .. " in your bags\")")
            SetMacro(m.name, body)
        end
    end
end

-- Bags change a lot (several events per loot): wait a moment, then update once.
local queued
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.5, function() queued = false; Update() end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP",
                     "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    Queue()
end)

function M:OnEnable() Queue() end

function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Check(key, text, indent)
        local cb = TT.Check(body, text, function(v) db[key] = v; lastBody = {}; Queue() end)
        cb:SetPoint("TOPLEFT", 2 + (indent and 20 or 0), -y)
        checks[key] = cb
        y = y + 24
    end
    Check("heal", "TT Heal  (healthstone / healing potion)")
    Check("preferStone", "Prefer healthstones over potions", true)
    Check("drink", "TT Drink")
    Check("preferConjured", "Prefer conjured (mage) food and water", true)
    Check("food", "TT Food")
    Check("bandage", "TT Bandage")

    local open = TT.Button(body, "Open macros", 110, function()
        if not MacroFrame then C_AddOns.LoadAddOn("Blizzard_MacroUI") end
        if MacroFrame then ShowUIPanel(MacroFrame) end
    end)
    open:SetPoint("TOPLEFT", 0, -y - 10)

    local help = TT.Label(body,
        "The macros are created in your Character macros (/macro). Drag them onto\n" ..
        "your bars once; they switch to your best item whenever your bags change.\n" ..
        "Macros can't be edited in combat, so changes wait until combat ends.\n" ..
        "Turning a macro off here leaves it as it is; delete it in /macro if you like.",
        "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -14)

    page.OnPageShow = function() for key, cb in pairs(checks) do cb:SetChecked(db[key]) end end
end
