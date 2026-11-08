-- Module: Bank Alt
-- A button at the mailbox that sends items (and gold) to your bank alt:
-- whitelisted items, whole item types (cloth, herbs, ore, ...) and, if you
-- want, all gold above an amount you keep.
--
-- How: one mail holds up to 12 items. The button fills a mail, sends it, and
-- when the server says it arrived (MAIL_SEND_SUCCESS) it does the next one.
-- Gold goes in the last mail. If the game refuses to send without a click (it
-- reports ADDON_ACTION_BLOCKED) or doesn't answer, the chain stops and the
-- button says "Send next mail": each click then sends one.
-- Soulbound, locked and quest items are never sent (they can't be mailed).
local _, TT = ...
local IsSecret = TT.IsSecret
local M = TT:RegisterModule("BankAlt", {
    title = "Bank Alt",
    category = "Quality of Life",
    desc = "A mailbox button that sends whitelisted items, chosen item types and spare gold to your bank alt.",
    defaults = {
        recipient = "", subject = "Bank", items = {},
        types = {}, gold = false, keepGold = 50,
    },
})

local MAX = ATTACHMENTS_MAX_SEND or 12
local POSTAGE_GUESS = 30                 -- copper per item, only used to keep a margin

-- item types you can tick: { key, label, classID, subclassID (nil = whole class) }
local TG = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local GEM = Enum and Enum.ItemClass and Enum.ItemClass.Gem or 3
local TYPES = {
    { "cloth",     "Cloth",            TG, 5 },
    { "leather",   "Leather",          TG, 6 },
    { "metal",     "Ore, bars & stone", TG, 7 },
    { "herb",      "Herbs",            TG, 9 },
    { "cooking",   "Meat & cooking",   TG, 8 },
    { "elemental", "Elemental",        TG, 10 },
    { "enchant",   "Enchanting",       TG, 12 },
    { "parts",     "Parts",            TG, 1 },
    { "jewel",     "Jewelcrafting",    TG, 4 },
    { "gems",      "Gems",             GEM, nil },
}

---------------------------------------------------------------------------
-- What to send
---------------------------------------------------------------------------
local function Me() return UnitName("player") end
local function TargetName()
    local r = strtrim(M.db.recipient or "")
    return r ~= "" and r or nil
end
local function IsMe(name)
    if not name then return false end
    return name:lower() == Me():lower() or name:lower():match("^(.-)%-") == Me():lower()
end

local whitelist = {}
local function RebuildWhitelist()
    wipe(whitelist)
    for _, id in ipairs(M.db.items) do whitelist[id] = true end
end

local function Wanted(itemID)
    if whitelist[itemID] then return true end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return false end
    for _, t in ipairs(TYPES) do
        if M.db.types[t[1]] and classID == t[3] and (t[4] == nil or subclassID == t[4]) then return true end
    end
    return false
end

local function LastBag()
    return (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
end

-- every bag slot holding something to send: { bag, slot }
local function Collect()
    local list = {}
    for bag = 0, LastBag() do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not IsSecret(info.itemID) and not info.isBound and not info.isLocked
               and Wanted(info.itemID) then
                local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
                if not (q and (q.isQuestItem or q.questID)) then list[#list + 1] = { bag, slot } end
            end
        end
    end
    return list
end

local function SpareGold(mailsLeft, itemsLeft)
    if not M.db.gold then return 0 end
    local keep = (M.db.keepGold or 0) * 10000
    local margin = (itemsLeft + mailsLeft) * POSTAGE_GUESS
    return math.max(0, GetMoney() - keep - margin)
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local button, ev
local queue, sending, manual, timer = {}, false, false, nil
local UpdateButton

local function Stop(why)
    sending = false
    if timer then timer:Cancel(); timer = nil end
    if why then TT.Print("Bank Alt: " .. why) end
    UpdateButton()
end

local function ShowSendTab()
    if SendMailFrame and not SendMailFrame:IsShown() and MailFrameTab2 and MailFrameTab_OnClick then
        MailFrameTab_OnClick(MailFrameTab2, 2)
    end
end

-- fill one mail with up to 12 items (and the gold, if this is the last one) and send it
local function SendOne()
    local to = TargetName()
    if not to or IsMe(to) then return Stop("set your bank alt's name in /trikks first (not this character).") end
    if not (MailFrame and MailFrame:IsShown()) then return Stop() end
    ShowSendTab()
    if ClearSendMail then ClearSendMail() end
    -- the bag contents may have moved since the last mail: look again
    queue = Collect()
    local n = 0
    while n < MAX and #queue > 0 do
        local spot = table.remove(queue, 1)
        ClearCursor()
        C_Container.PickupContainerItem(spot[1], spot[2])
        n = n + 1
        ClickSendMailItemButton(n)
    end
    ClearCursor()
    local last = #queue == 0
    local money = 0
    if last then
        local postage = GetSendMailPrice and GetSendMailPrice() or n * POSTAGE_GUESS
        money = math.max(0, SpareGold(0, 0) - postage)
        if money > 0 then SetSendMailMoney(money) end
    end
    if n == 0 and money == 0 then return Stop("nothing (left) to send.") end
    local subject = (M.db.subject ~= "" and M.db.subject or "Bank")
    sending = true
    SendMail(to, subject, "")
    -- no answer from the server in time: stop and leave it to the next click
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(6, function() manual = true; Stop("no answer from the mailbox, click to send the next mail.") end)
    UpdateButton()
end

local function Start()
    if sending then return end
    RebuildWhitelist()
    SendOne()
end

UpdateButton = function()
    if not button then return end
    local to = TargetName()
    local items = #Collect()
    local mails = math.ceil(items / MAX)
    local gold = SpareGold(mails, items)
    if gold > 0 and mails == 0 then mails = 1 end
    button:SetShown(M.enabled and MailFrame and MailFrame:IsShown() and true or false)
    if sending then
        button:SetText("Sending..."); button:Disable()
    elseif not to then
        button:SetText("Set a bank alt in /trikks"); button:Disable()
    elseif IsMe(to) then
        button:SetText("This is the bank alt"); button:Disable()
    elseif mails == 0 then
        button:SetText("Nothing to send to " .. to); button:Disable()
    else
        local label = manual and "Send next mail" or ("Send to " .. to)
        button:SetText(string.format("%s (%d %s)", label, mails, mails == 1 and "mail" or "mails"))
        button:Enable()
    end
end

local function OnEvent(_, event, a1, a2)
    if event == "MAIL_SHOW" then
        manual = false
        RebuildWhitelist()
        C_Timer.After(0, UpdateButton)
    elseif event == "MAIL_CLOSED" then
        if sending then Stop() end
        if button then button:Hide() end
    elseif event == "MAIL_SEND_SUCCESS" then
        if not sending then return end
        if timer then timer:Cancel(); timer = nil end
        sending = false
        if manual then UpdateButton(); return end
        -- next mail a moment later (the bags update first)
        C_Timer.After(0.6, function()
            -- gold always rides in the last mail, so only items can be left over here
            if #Collect() > 0 then SendOne() else TT.Print("Bank Alt: all sent."); UpdateButton() end
        end)
    elseif event == "MAIL_FAILED" then
        if sending then manual = true; Stop("a mail failed (is the name right?), nothing more was sent.") end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- the game wants a real click for each mail: switch to one mail per click
        if sending and a2 and tostring(a2):find("SendMail") then
            manual = true
            if ClearSendMail then ClearSendMail() end
            Stop("the game wants a click for each mail: click the button again for the next one.")
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if not sending and button and button:IsShown() then UpdateButton() end
    end
end

function M:Setup()
    button = TT.Button(UIParent, "", 230, function() Start() end)
    button:SetHeight(24)
    button:Hide()
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", OnEvent)
end

local EVENTS = { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "ADDON_ACTION_BLOCKED",
                 "ADDON_ACTION_FORBIDDEN", "BAG_UPDATE_DELAYED" }
function M:OnEnable()
    RebuildWhitelist()
    for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    if MailFrame then
        button:SetParent(MailFrame)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 0, -4)
        button:SetFrameStrata(MailFrame:GetFrameStrata())
    end
    UpdateButton()
end
function M:OnDisable()
    for _, e in ipairs(EVENTS) do pcall(ev.UnregisterEvent, ev, e) end
    if sending then Stop() end
    button:Hide()
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function M:BuildSettings(body, page)
    local db, refreshers, y = M.db, {}, 0
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(TT.C.dim)); h:SetPoint("TOPLEFT", 0, -y); y = y + 20
    end
    local function Box(label, key, w)
        local l = TT.Label(body, label)
        l:SetPoint("TOPLEFT", 2, -y - 4)
        local b = TT.EditBox(body, w, 22)
        b:SetPoint("TOPLEFT", 140, -y)
        b:SetScript("OnTextChanged", function(box) db[key] = strtrim(box:GetText() or ""); UpdateButton() end)
        b:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
        refreshers[#refreshers + 1] = function() b:SetText(db[key] or "") end
        y = y + 28
    end

    Head("Bank alt")
    Box("Character name", "recipient", 180)
    Box("Mail subject", "subject", 180)
    y = y + 4

    Head("Item types to send")
    for i, t in ipairs(TYPES) do
        local col = (i - 1) % 3
        local cb = TT.Check(body, t[2], function(v) db.types[t[1]] = v or nil; UpdateButton() end)
        cb:SetPoint("TOPLEFT", 2 + col * 190, -y)
        refreshers[#refreshers + 1] = function() cb:SetChecked(db.types[t[1]] and true or false) end
        if col == 2 or i == #TYPES then y = y + 24 end
    end
    y = y + 6

    Head("Gold")
    local gcb = TT.Check(body, "Send gold, keep this much on the character:", function(v) db.gold = v; UpdateButton() end)
    gcb:SetPoint("TOPLEFT", 2, -y)
    refreshers[#refreshers + 1] = function() gcb:SetChecked(db.gold) end
    local keep = TT.Stepper(body, "Keep (gold)", function() return db.keepGold end,
        function(v) db.keepGold = v; UpdateButton() end, 0, 100000, 10)
    keep:SetPoint("TOPLEFT", 330, -y + 4)
    refreshers[#refreshers + 1] = keep.Refresh
    y = y + 34

    Head("Always send these items")
    -- drop an item from your bags here, or type its ID in the box below
    local drop = TT.Button(body, "Drop an item here", 170, nil)
    drop:SetPoint("TOPLEFT", 380, -y)
    local list
    local function AddFromCursor()
        local kind, id = GetCursorInfo()
        if kind == "item" and id then
            ClearCursor()
            for _, v in ipairs(db.items) do if v == id then return end end
            db.items[#db.items + 1] = id
            RebuildWhitelist(); list.Refresh(); UpdateButton()
        end
    end
    drop:SetScript("OnReceiveDrag", AddFromCursor)
    drop:SetScript("OnClick", AddFromCursor)
    list = TT.IDList(body, 360, 160, db.items, function(id)
        local n = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
        return id .. (n and ("  " .. n) or "")
    end, function() RebuildWhitelist(); UpdateButton() end)
    list:SetPoint("TOPLEFT", 0, -y)
    refreshers[#refreshers + 1] = list.Refresh
    y = y + 168
    local help = TT.Label(body,
        "At a mailbox, the button under the mail window sends everything above, 12 items\n" ..
        "per mail, one mail after another (gold in the last one). Soulbound, locked and\n" ..
        "quest items are never sent. If the game wants a click for each mail, the button\n" ..
        "says \"Send next mail\" and each click sends one.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y)

    page.OnPageShow = function() for _, f in ipairs(refreshers) do f() end end
end
