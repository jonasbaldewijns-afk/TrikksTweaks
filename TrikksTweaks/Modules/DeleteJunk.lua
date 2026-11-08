-- Module: Delete Junk
-- Press a key (Backspace by default) to destroy the cheapest grey item in your
-- bags, to make room fast. With a vendor open it sells the item instead.
-- Deleting an item is only allowed right after a real key press (a "hardware
-- event"), so this listens to the keyboard, like Dialog Keys does.
local _, TT = ...
local M = TT:RegisterModule("DeleteJunk", {
    title = "Delete Junk",
    category = "Quality of Life",
    desc = "Press Backspace to destroy the cheapest grey item in your bags (sells it instead at a vendor).",
    defaults = { key = "BACKSPACE", byStack = true, onlyFull = false, announce = true, sellAtVendor = true,
                 maxValue = 0, keep = {} },
})

local merchantOpen = false

local function Price(id)
    local p = id and select(11, C_Item.GetItemInfo(id))
    if not p or TT.IsSecret(p) then return 0 end
    return p
end
local function Money(c)
    if GetMoneyString then return GetMoneyString(c, true) end
    return c .. "c"
end
local function Kept(id)
    for _, v in ipairs(M.db.keep) do if v == id then return true end end
    return false
end
local function FreeSlots()
    local free = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0) end
    return free
end

-- the grey item to get rid of: lowest value (whole stack, or per item), never
-- one on the keep list, never one worth more than the set limit
local function FindCheapest()
    local db, best = M.db, nil
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and not TT.IsSecret(info) and info.quality == 0 and not info.isLocked
               and info.itemID and not Kept(info.itemID) then
                local each, count = Price(info.itemID), info.stackCount or 1
                local total = each * count
                local value = db.byStack and total or each
                if (db.maxValue == 0 or total <= db.maxValue * 100)
                   and (not best or value < best.value) then
                    best = { bag = bag, slot = slot, id = info.itemID, link = info.hyperlink,
                             count = count, total = total, value = value }
                end
            end
        end
    end
    return best
end

-- returns true when the key was used (then the game doesn't also get it)
local function DeleteCheapest()
    if CursorHasItem() then return false end
    if M.db.onlyFull and FreeSlots() > 0 then return false end   -- bags not full: Backspace does its normal thing
    local item = FindCheapest()
    if not item then
        if M.db.announce then TT.Print("no grey items to delete.") end
        return true
    end
    local name = (item.link or ("item " .. item.id)) .. (item.count > 1 and (" x" .. item.count) or "")
    if merchantOpen and M.db.sellAtVendor then
        C_Container.UseContainerItem(item.bag, item.slot)            -- with a vendor open, "use" = sell
        if M.db.announce then TT.Print("sold " .. name .. " for " .. Money(item.total) .. ".") end
        return true
    end
    C_Container.PickupContainerItem(item.bag, item.slot)
    -- only delete if the cursor really holds that item (else put it back)
    local kind, id = GetCursorInfo()
    if kind ~= "item" or id ~= item.id then ClearCursor(); return true end
    DeleteCursorItem()
    if M.db.announce then TT.Print("deleted " .. name .. " (worth " .. Money(item.total) .. ").") end
    return true
end

-- the key with its modifiers, e.g. "SHIFT-BACKSPACE"
local function Combo(key)
    local p = ""
    if IsAltKeyDown() then p = p .. "ALT-" end
    if IsControlKeyDown() then p = p .. "CTRL-" end
    if IsShiftKeyDown() then p = p .. "SHIFT-" end
    return p .. key
end
local function IsModifier(key)
    return key:find("SHIFT") or key:find("CTRL") or key:find("ALT")
end

-- Key catcher: sees every key, lets it through unless we used it. Only exists
-- once the module was switched on, and is hidden (gets no keys) while it's off.
local catcher
function M:Setup()
    catcher = CreateFrame("Frame", nil, UIParent)
    catcher:EnableKeyboard(true)
    catcher:SetPropagateKeyboardInput(true)
    catcher:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end                   -- can't change key handling in combat
        local used = false
        if M.enabled and not GetCurrentKeyBoardFocus() and not IsModifier(key) and Combo(key) == M.db.key then
            used = DeleteCheapest()
        end
        self:SetPropagateKeyboardInput(not used)                -- false = the game doesn't also get this key
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("MERCHANT_SHOW")
    ev:RegisterEvent("MERCHANT_CLOSED")
    ev:SetScript("OnEvent", function(_, event) merchantOpen = (event == "MERCHANT_SHOW") end)
end
function M:OnEnable() catcher:Show() end
function M:OnDisable() catcher:Hide() end

---------------------------------------------------------------------------
function M:BuildSettings(body, page)
    local db, refreshers, y = M.db, {}, 0
    local function Check(key, text, indent)
        local cb = TT.Check(body, text, function(v) db[key] = v end)
        cb:SetPoint("TOPLEFT", 2 + (indent and 20 or 0), -y)
        refreshers[#refreshers + 1] = function() cb:SetChecked(db[key]) end
        y = y + 24
    end

    local kl = TT.Label(body, "Key:")
    kl:SetPoint("TOPLEFT", 4, -y - 4)
    local keyBtn = TT.Button(body, "", 160, nil)
    keyBtn:SetPoint("TOPLEFT", 120, -y)
    keyBtn:SetScript("OnClick", function(self)
        self:SetText("Press a key...")
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false)
    end)
    keyBtn:SetScript("OnKeyDown", function(self, key)
        if IsModifier(key) then return end                 -- wait for the real key
        if key ~= "ESCAPE" then db.key = Combo(key) end
        self:EnableKeyboard(false)
        self:SetText(db.key)
    end)
    refreshers[#refreshers + 1] = function() keyBtn:SetText(db.key) end
    y = y + 32

    local cl = TT.Label(body, "Cheapest by:")
    cl:SetPoint("TOPLEFT", 4, -y - 4)
    local cycle = TT.Cycle(body, 160, { { true, "Whole stack value" }, { false, "Price per item" } },
        function() return db.byStack end, function(v) db.byStack = v end)
    cycle:SetPoint("TOPLEFT", 120, -y)
    refreshers[#refreshers + 1] = cycle.Refresh
    y = y + 34

    Check("sellAtVendor", "With a vendor open, sell it instead of deleting")
    Check("onlyFull", "Only when my bags are full (else the key does its normal thing)")
    Check("announce", "Say in chat what was deleted / sold")
    local stepper = TT.Stepper(body, "Never delete greys worth more than (silver, 0 = no limit)",
        function() return db.maxValue end, function(v) db.maxValue = v end, 0, 10000, 10)
    stepper:SetSize(470, 24)
    stepper:SetPoint("TOPLEFT", 4, -y - 2)
    refreshers[#refreshers + 1] = stepper.Refresh
    y = y + 34

    local nl = TT.Label(body, "Never delete these items (item ID):")
    nl:SetPoint("TOPLEFT", 4, -y)
    y = y + 20
    local list = TT.IDList(body, 360, 160, db.keep, function(id)
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
        return (name or "Item") .. "  |cff888888" .. id .. "|r"
    end)
    list:SetPoint("TOPLEFT", 4, -y)
    refreshers[#refreshers + 1] = list.Refresh
    y = y + 168

    local help = TT.Label(body,
        "Only grey (poor quality) items, one per key press. Not during combat (WoW locks\n" ..
        "key handling then) and not while you're typing. Tip: hold Ctrl over an item with\n" ..
        "IDs & Links on to see its item ID.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 4)

    page.OnPageShow = function() for _, f in ipairs(refreshers) do f() end end
end
