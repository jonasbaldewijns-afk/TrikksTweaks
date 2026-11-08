-- Module: Vendor & Bags
-- Sell prices in item tooltips, a free-slots count on the backpack button,
-- "Nude" / "No weapons" buttons in the dressing room, and the item level on
-- gear in your bags.
local _, TT = ...
local M = TT:RegisterModule("VendorBags", {
    title = "Vendor & Bags",
    category = "Quality of Life",
    desc = "Sell prices in item tooltips, free bag slots on the backpack, nude / no-weapons buttons in the dressing room.",
    defaults = { sellPrice = true, freeSlots = true, dressingRoom = true, bagIlvl = true },
})

---------------------------------------------------------------------------
-- Sell price in tooltips
---------------------------------------------------------------------------
local function StackCount(tooltip)
    -- bag item buttons know their bag and slot
    local owner = tooltip:GetOwner()
    if owner and owner.GetBagID and owner.GetID then
        local ok, bag = pcall(owner.GetBagID, owner)
        if ok and bag then
            local info = C_Container.GetContainerItemInfo(bag, owner:GetID())
            if info then return info.stackCount or 1 end
        end
    end
    return 1
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not (M.enabled and M.db.sellPrice) or not data or not data.id then return end
    if TT.IsSecret(data.id) then return end
    -- the game already showed a price (e.g. at a vendor): don't add a second one
    if (tooltip.shownMoneyFrames or 0) > 0 then return end
    local price = select(11, C_Item.GetItemInfo(data.id))
    if not price or price <= 0 then return end
    local count = StackCount(tooltip)
    if SetTooltipMoney then
        SetTooltipMoney(tooltip, price * count, nil, (SELL_PRICE or "Sell Price") .. ":",
            count > 1 and (" (" .. GetCoinTextureString(price) .. " each)") or nil)
    else
        tooltip:AddLine((SELL_PRICE or "Sell Price") .. ": " .. GetCoinTextureString(price * count), 1, 1, 1)
    end
    tooltip:Show()
end)

---------------------------------------------------------------------------
-- Item level on gear in your bags
---------------------------------------------------------------------------
local function BagButtonIlvl(b)
    if not b.ttIlvl then
        b.ttIlvl = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.ttIlvl:SetPoint("TOPLEFT", 2, -2)
    end
    local text = ""
    if M.enabled and M.db.bagIlvl and b.GetBagID then
        local ok, bag = pcall(b.GetBagID, b)
        local info = ok and bag and C_Container.GetContainerItemInfo(bag, b:GetID())
        local link = info and info.hyperlink
        if link and not TT.IsSecret(link) then
            -- only weapons (class 2) and armour (class 4)
            local classID = select(6, C_Item.GetItemInfoInstant(link))
            if classID == 2 or classID == 4 then
                local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
                local lvl = f and f(link)
                if lvl and not TT.IsSecret(lvl) and lvl > 1 then
                    text = lvl
                    local c = info.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality]
                    if c then b.ttIlvl:SetTextColor(c.r, c.g, c.b) else b.ttIlvl:SetTextColor(1, 1, 1) end
                end
            end
        end
    end
    b.ttIlvl:SetText(text)
end
local function BagIlvl(frame)
    if type(frame.EnumerateValidItems) ~= "function" then return end
    for _, b in frame:EnumerateValidItems() do BagButtonIlvl(b) end
end
local bagFrames = { "ContainerFrameCombinedBags" }
for i = 1, 13 do bagFrames[#bagFrames + 1] = "ContainerFrame" .. i end
for _, n in ipairs(bagFrames) do
    local f = _G[n]
    if f and type(f.UpdateItems) == "function" then hooksecurefunc(f, "UpdateItems", BagIlvl) end
end
local function RefreshBags()
    for _, n in ipairs(bagFrames) do
        local f = _G[n]
        if f and f:IsShown() then BagIlvl(f) end
    end
end

---------------------------------------------------------------------------
-- Free bag slots on the backpack button
---------------------------------------------------------------------------
local freeText
local function UpdateFree()
    local btn = MainMenuBarBackpackButton
    if not btn then return end
    local on = M.enabled and M.db.freeSlots
    -- newer clients have this built in as a setting
    if C_CVar.GetCVar("displayFreeBagSlots") ~= nil then
        C_CVar.SetCVar("displayFreeBagSlots", on and "1" or "0")
        return
    end
    if not freeText then
        freeText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        freeText:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    freeText:SetShown(on)
    if not on then return end
    local free = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0) end
    freeText:SetText(free)
    if free == 0 then freeText:SetTextColor(1, 0.3, 0.3) else freeText:SetTextColor(1, 1, 1) end   -- red when full
end

---------------------------------------------------------------------------
-- Dressing room buttons
---------------------------------------------------------------------------
local dressButtons
local function Actor()
    local scene = DressUpFrame and DressUpFrame.ModelScene
    if scene and scene.GetPlayerActor then return scene:GetPlayerActor() end
    return DressUpModelFrame or DressUpModel                       -- older style dressing room
end

local function MakeDressButtons()
    if dressButtons or not DressUpFrame then return end
    dressButtons = CreateFrame("Frame", nil, DressUpFrame)
    dressButtons:SetSize(170, 22)
    local anchor = DressUpFrame.ResetButton or DressUpFrameResetButton
    if anchor then dressButtons:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    else dressButtons:SetPoint("BOTTOMLEFT", DressUpFrame, "BOTTOMLEFT", 10, 10) end
    local nude = TT.Button(dressButtons, "Nude", 70, function()
        local a = Actor(); if a and a.Undress then a:Undress() end
    end)
    nude:SetPoint("RIGHT")
    local weapons = TT.Button(dressButtons, "No weapons", 90, function()
        local a = Actor()
        if a and a.UndressSlot then
            for _, slot in ipairs({ INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17, INVSLOT_RANGED or 18 }) do
                pcall(a.UndressSlot, a, slot)
            end
        end
    end)
    weapons:SetPoint("RIGHT", nude, "LEFT", -4, 0)
end

local function ApplyDress()
    if M.enabled and M.db.dressingRoom then MakeDressButtons() end
    if dressButtons then dressButtons:SetShown(M.enabled and M.db.dressingRoom) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function(_, event)
    UpdateFree()
    if event == "PLAYER_ENTERING_WORLD" then ApplyDress() end
end)
if DressUpFrame then DressUpFrame:HookScript("OnShow", ApplyDress) end

function M:OnEnable() UpdateFree(); ApplyDress() end
function M:OnDisable() UpdateFree(); ApplyDress() end

function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Check(key, text, after)
        local cb = TT.Check(body, text, function(v) db[key] = v; if after then after() end end)
        cb:SetPoint("TOPLEFT", 2, -y)
        checks[key] = cb
        y = y + 24
    end
    Check("sellPrice", "Sell price in item tooltips (whole stack for bag items)")
    Check("freeSlots", "Free bag slots on the backpack button", UpdateFree)
    Check("dressingRoom", "\"Nude\" and \"No weapons\" buttons in the dressing room", ApplyDress)
    Check("bagIlvl", "Item level on weapons and armour in your bags", RefreshBags)
    page.OnPageShow = function() for key, cb in pairs(checks) do cb:SetChecked(db[key]) end end
end
