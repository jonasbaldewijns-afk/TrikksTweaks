-- Module: Bulk Buy
-- Shift-click an item at a vendor to buy any amount, not just one stack.
--
-- How: Blizzard's own Shift-click pop-up stops at one stack (often 20) and
-- buys once. The game itself has no such limit: buying is just
-- BuyMerchantItem(slot, amount) with at most one stack per call. So this
-- pop-up buys in steps of one stack, a moment apart, until the amount is done.
-- Items that cost tokens / currency, or that Blizzard asks to confirm
-- (non-refundable, very expensive), keep Blizzard's own pop-up and warnings.
local _, TT = ...
local C = TT.C
local M = TT:RegisterModule("BulkBuy", {
    title = "Bulk Buy",
    category = "Quality of Life",
    desc = "Shift-click a vendor item to buy any amount (Blizzard's pop-up stops at one stack).",
})

local STEP_DELAY = 0.25
local win, amountBox, costText, infoText, buyBtn, icon, nameText
local cur                      -- { index, itemID, price (per item), bundle, maxStack, stock }
local buying                   -- { index, left, done, total } while buying

local function Money(copper)
    if GetCoinTextureString then return GetCoinTextureString(math.floor(copper + 0.5)) end
    return math.floor(copper / 10000) .. "g"
end

-- how many of this item still fit in the bags (free slots + room in stacks you have)
local function Fits(itemID)
    local stack = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID) or 1
    if not stack or stack < 1 then stack = 1 end
    local room = 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if free and (family == 0 or family == nil) then room = room + free * stack end
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and info.stackCount then room = room + math.max(0, stack - info.stackCount) end
        end
    end
    return room
end

local function Limits()
    local afford = cur.price > 0 and math.floor(GetMoney() / cur.price) or math.huge
    local fits = Fits(cur.itemID)
    local most = math.min(afford, fits)
    if cur.stock and cur.stock >= 0 then most = math.min(most, cur.stock * cur.bundle) end
    -- whole bundles only (arrows by 200, ...)
    most = math.floor(most / cur.bundle) * cur.bundle
    return most, afford, fits
end

local function Amount()
    local n = tonumber(amountBox:GetText()) or 0
    return math.floor(n / cur.bundle) * cur.bundle
end

local function Refresh()
    if not cur then return end
    local n = Amount()
    local most, afford, fits = Limits()
    costText:SetText(n > 0 and ("Total: " .. Money(n * cur.price)) or "Total: -")
    local parts = { "fits in bags: " .. fits }
    if afford ~= math.huge then parts[#parts + 1] = "you can afford: " .. afford end
    if cur.stock and cur.stock >= 0 then parts[#parts + 1] = "in stock: " .. (cur.stock * cur.bundle) end
    if cur.bundle > 1 then parts[#parts + 1] = "sold per " .. cur.bundle end
    infoText:SetText(table.concat(parts, "   "))
    if buying then
        buyBtn:SetText(string.format("Buying %d/%d...", buying.done, buying.total)); buyBtn:Disable()
    else
        buyBtn:SetText("Buy " .. n); buyBtn:SetEnabled(n > 0 and n <= most)
        if n > most then costText:SetText("|cffff5555Too many: max " .. most .. "|r") end
    end
end

-- one stack per step, then the next a moment later
local function Step()
    if not buying then return end
    if not (MerchantFrame and MerchantFrame:IsShown()) then buying = nil; if win then win:Hide() end; return end
    local n = math.min(buying.left, buying.chunk)
    if n <= 0 then
        buying = nil
        win:Hide()
        return
    end
    BuyMerchantItem(buying.index, n)
    buying.left = buying.left - n
    buying.done = buying.done + 1
    Refresh()
    C_Timer.After(STEP_DELAY, Step)
end

local function Buy()
    if buying or not cur then return end
    local n = Amount()
    if n <= 0 or n > Limits() then return end
    local chunk = math.max(cur.bundle, math.floor(cur.maxStack / cur.bundle) * cur.bundle)
    buying = { index = cur.index, left = n, done = 0, total = math.ceil(n / chunk), chunk = chunk }
    amountBox:ClearFocus()
    Step()
end

local function MakeWindow()
    win = TT.Window("TrikksTweaksBulkBuy", 330, 150, "Buy")
    win:SetFrameStrata("DIALOG")
    win:SetScript("OnHide", function() cur = nil; buying = nil end)
    icon = win:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32); icon:SetPoint("TOPLEFT", 14, -36)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    nameText = TT.Label(win, "", "GameFontNormal")
    nameText:SetPoint("LEFT", icon, "RIGHT", 10, 0); nameText:SetPoint("RIGHT", -14, 0)
    nameText:SetWordWrap(false)
    amountBox = TT.EditBox(win, 70, 22)
    amountBox:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
    amountBox:SetNumeric(true)
    amountBox:SetScript("OnTextChanged", Refresh)
    amountBox:SetScript("OnEnterPressed", Buy)
    amountBox:SetScript("OnEscapePressed", function() win:Hide() end)
    local plus = TT.Button(win, "+1 stack", 70, function()
        local n = Amount() + math.max(cur.bundle, cur.maxStack)
        amountBox:SetText(math.min(n, Limits()))
    end)
    plus:SetPoint("LEFT", amountBox, "RIGHT", 6, 0)
    local max = TT.Button(win, "Max", 50, function() amountBox:SetText(Limits()) end)
    max:SetPoint("LEFT", plus, "RIGHT", 6, 0)
    buyBtn = TT.Button(win, "Buy", 100, Buy)
    buyBtn:SetPoint("LEFT", max, "RIGHT", 6, 0)
    costText = TT.Label(win, "", "GameFontHighlight")
    costText:SetPoint("TOPLEFT", amountBox, "BOTTOMLEFT", 0, -10)
    infoText = TT.Label(win, "", "GameFontDisableSmall")
    infoText:SetPoint("TOPLEFT", costText, "BOTTOMLEFT", 0, -6)
end

-- Shift-click on a vendor item: ours instead of Blizzard's (gold-priced items only)
local lastButton, lastTime
local function OnModifiedClick(button)
    if not M.enabled or buying then return end
    -- reached through two routes (see Setup): handle each click once
    if lastButton == button and lastTime == GetTime() then return end
    lastButton, lastTime = button, GetTime()
    if not (MerchantFrame and MerchantFrame.selectedTab == 1) or not IsModifiedClick("SPLITSTACK") then return "not on the vendor's buy tab" end
    local index = button:GetID()
    local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(index)
    if not info and GetMerchantItemInfo then             -- older API: plain return values
        local name, texture, price, stackCount, numAvailable, _, _, extendedCost = GetMerchantItemInfo(index)
        info = name and { name = name, texture = texture, price = price, stackCount = stackCount,
                          numAvailable = numAvailable, hasExtendedCost = extendedCost } or nil
    end
    if not info then return "no item info for slot " .. tostring(index) end
    if info.hasExtendedCost then return "it costs tokens or currency" end
    if button.showNonrefundablePrompt then return "it isn't refundable" end
    if not info.price or info.price <= 0 then return "it has no gold price" end
    if MERCHANT_HIGH_PRICE_COST and info.price >= MERCHANT_HIGH_PRICE_COST then return "it's very expensive (Blizzard confirms those)" end
    local itemID = GetMerchantItemID and GetMerchantItemID(index)
    if not itemID then
        local link = GetMerchantItemLink and GetMerchantItemLink(index)
        itemID = link and C_Item.GetItemInfoInstant(link)
    end
    if not itemID then return "no item ID for slot " .. tostring(index) end
    if StackSplitFrame and StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
    if not win then MakeWindow() end
    local bundle = math.max(1, info.stackCount or 1)
    cur = { index = index, itemID = itemID, price = info.price / bundle, bundle = bundle,
            maxStack = math.max(1, GetMerchantItemMaxStack(index) or 1), stock = info.numAvailable }
    icon:SetTexture(info.texture or C_Item.GetItemIconByID(itemID))
    nameText:SetText(info.name or "?")
    local q = info.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality]
    if q then nameText:SetTextColor(q.r, q.g, q.b) else nameText:SetTextColor(unpack(C.text)) end
    win:ClearAllPoints()
    win:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 6)
    amountBox:SetText(math.min(math.max(bundle, cur.maxStack), Limits()))
    win:Show()
    amountBox:SetFocus()
    amountBox:HighlightText()
    Refresh()
end

function M:Setup()
    -- Two routes to the Shift-click, because clients wire it differently:
    -- the global function (retail calls it by name on every click) and the
    -- item buttons' own click scripts (where the function was bound at load).
    if type(MerchantItemButton_OnModifiedClick) == "function" then
        hooksecurefunc("MerchantItemButton_OnModifiedClick", OnModifiedClick)
    end
    for i = 1, 12 do
        local b = _G["MerchantItem" .. i .. "ItemButton"]
        if b then
            local function Check(btn) if IsModifiedClick("SPLITSTACK") then OnModifiedClick(btn) end end
            b:HookScript("OnClick", Check)
            if b:HasScript("OnModifiedClick") then b:HookScript("OnModifiedClick", Check) end
        end
    end
    -- third route, independent of how the vendor buttons are named or wired:
    -- Blizzard's split pop-up itself, opened for a button inside the vendor window
    if StackSplitFrame and type(StackSplitFrame.OpenStackSplitFrame) == "function" then
        hooksecurefunc(StackSplitFrame, "OpenStackSplitFrame", function(_, _, owner)
            if not (owner and owner.GetID and MerchantFrame and MerchantFrame:IsShown()) then return end
            local f = owner
            while f and f ~= MerchantFrame do f = f:GetParent() end
            if f == MerchantFrame then
                local why = OnModifiedClick(owner)
                if why and M.enabled then TT.Print("Bulk Buy: Blizzard's pop-up for this one: " .. why .. ".") end
            end
        end)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("MERCHANT_CLOSED")
    ev:RegisterEvent("PLAYER_MONEY")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:SetScript("OnEvent", function(_, event)
        if not (win and win:IsShown()) then return end
        if event == "MERCHANT_CLOSED" then win:Hide() else Refresh() end
    end)
end

function M:OnDisable() if win then win:Hide() end end

function M:BuildSettings(body)
    local help = TT.Label(body,
        "Shift-click an item at a vendor: type any amount (or +1 stack / Max) and press Enter.\n" ..
        "It buys one stack at a time, a quarter second apart, and stops if you close the vendor.\n" ..
        "Max = what you can afford, what fits in your bags and what the vendor has.\n\n" ..
        "Items that cost tokens or currency, and ones Blizzard asks you to confirm (non-\n" ..
        "refundable, very expensive), keep Blizzard's own pop-up.", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 2, 0)
end
