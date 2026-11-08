-- Module: Mail to Alts
-- Two saved characters ("Main" and "Bank alt"), each with its own rules:
-- items to always send (whitelist), whole item types (cloth, herbs, ore, ...)
-- and all gold above an amount you keep. At a mailbox there is a button per
-- character; it opens a small menu: send all, only items, only gold, settings.
-- The button for the character you're playing is hidden (no mailing yourself).
--
-- How sending works: one mail holds up to 12 items. A mail is filled and sent,
-- and when the server says it arrived (MAIL_SEND_SUCCESS) the next one follows.
-- Gold goes in the last mail. If the game refuses to send without a click (it
-- reports ADDON_ACTION_BLOCKED) or doesn't answer, the chain stops and the
-- button says "next mail": each click then sends one.
-- Soulbound, locked and quest items are never sent (they can't be mailed).
local _, TT = ...
local C = TT.C
local IsSecret = TT.IsSecret

local function Profile(label)
    return { name = "", label = label, subject = "", items = {}, types = {}, gold = false, keepGold = 50,
             hideOn = {} }           -- characters ("Name-Realm") that don't show this button
end
local M = TT:RegisterModule("BankAlt", {
    title = "Mail to Alts",
    category = "Quality of Life",
    desc = "Mailbox buttons for your main and your bank alt: send whitelisted items, item types and spare gold in one click.",
    defaults = { profiles = { main = Profile("Main"), bank = Profile("Bank alt") } },
})
local KEYS = { "main", "bank" }

local MAX = ATTACHMENTS_MAX_SEND or 12
local POSTAGE_GUESS = 30                 -- copper per item, only to keep a margin

-- item types you can tick: { key, label, classID, subclassID (nil = whole class) }
local TG = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local GEM = Enum and Enum.ItemClass and Enum.ItemClass.Gem or 3
local TYPES = {
    { "cloth",     "Cloth",             TG, 5 },
    { "leather",   "Leather",           TG, 6 },
    { "metal",     "Ore, bars & stone", TG, 7 },
    { "herb",      "Herbs",             TG, 9 },
    { "cooking",   "Meat & cooking",    TG, 8 },
    { "elemental", "Elemental",         TG, 10 },
    { "enchant",   "Enchanting",        TG, 12 },
    { "parts",     "Parts",             TG, 1 },
    { "jewel",     "Jewelcrafting",     TG, 4 },
    { "gems",      "Gems",              GEM, nil },
}

---------------------------------------------------------------------------
-- Who and what
---------------------------------------------------------------------------
local function P(key) return M.db.profiles[key] end
local function NameOf(key)
    local n = strtrim(P(key).name or "")
    return n ~= "" and n or nil
end
-- this character, as the key in hideOn
local function CharKey() return UnitName("player") .. "-" .. (GetRealmName() or "") end
local function HiddenHere(key) return P(key).hideOn[CharKey()] and true or false end

local function IsMe(name)
    if not name then return false end
    local me = UnitName("player"):lower()
    name = name:lower()
    return name == me or name:match("^(.-)%-") == me
end

local function Wanted(p, itemID)
    for _, id in ipairs(p.items) do if id == itemID then return true end end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return false end
    for _, t in ipairs(TYPES) do
        if p.types[t[1]] and classID == t[3] and (t[4] == nil or subclassID == t[4]) then return true end
    end
    return false
end

-- every bag slot with something for this profile: { bag, slot }
local function Collect(p)
    local list = {}
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not IsSecret(info.itemID) and not info.isBound and not info.isLocked
               and Wanted(p, info.itemID) then
                local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
                if not (q and (q.isQuestItem or q.questID)) then list[#list + 1] = { bag, slot } end
            end
        end
    end
    return list
end

local function SpareGold(p, margin)
    if not p.gold then return 0 end
    return math.max(0, GetMoney() - (p.keepGold or 0) * 10000 - (margin or 0))
end

-- what a mode would send right now: items, mails, gold (copper)
local function Plan(key, mode)
    local p = P(key)
    local items = (mode ~= "gold") and #Collect(p) or 0
    local mails = math.ceil(items / MAX)
    local gold = (mode ~= "items") and SpareGold(p, (items + 1) * POSTAGE_GUESS) or 0
    if gold > 0 and mails == 0 then mails = 1 end
    return items, mails, gold
end

local function Money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return math.floor(copper / 10000) .. "g"
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local buttons, menu, ev = {}, nil, nil
local job                        -- { key, mode, manual, more } while a run is going
local sending, timer = false, nil
local UpdateButtons

local function Stop(why, keepJob)
    sending = false
    if timer then timer:Cancel(); timer = nil end
    if not keepJob then job = nil end
    if why then TT.Print("Mail to Alts: " .. why) end
    UpdateButtons()
end

local function ShowSendTab()
    if SendMailFrame and not SendMailFrame:IsShown() and MailFrameTab2 and MailFrameTab_OnClick then
        MailFrameTab_OnClick(MailFrameTab2, 2)
    end
end

local function SendOne()
    if not job then return end
    local p, to = P(job.key), NameOf(job.key)
    if not to or IsMe(to) then return Stop("set a different character's name in /trikks first.") end
    if not (MailFrame and MailFrame:IsShown()) then return Stop() end
    ShowSendTab()
    if ClearSendMail then ClearSendMail() end
    -- bags may have moved since the last mail: look again every time
    local queue = job.mode ~= "gold" and Collect(p) or {}
    local n = 0
    while n < MAX and #queue > 0 do
        local spot = table.remove(queue, 1)
        ClearCursor()
        C_Container.PickupContainerItem(spot[1], spot[2])
        n = n + 1
        ClickSendMailItemButton(n)
    end
    ClearCursor()
    local money = 0
    if #queue == 0 and job.mode ~= "items" then       -- last mail: the gold goes along
        local postage = GetSendMailPrice and GetSendMailPrice() or n * POSTAGE_GUESS
        money = math.max(0, SpareGold(p) - postage)
        if money > 0 then SetSendMailMoney(money) end
    end
    if n == 0 and money == 0 then return Stop("nothing to send.") end
    job.more = #queue > 0
    sending = true
    SendMail(to, (p.subject ~= "" and p.subject or p.label), "")
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(6, function()
        if job then job.manual = true end
        Stop("no answer from the mailbox: click the button again for the next mail.", true)
    end)
    UpdateButtons()
end

local function Start(key, mode)
    if sending then return end
    if job and job.key == key and job.manual then job.mode = mode or job.mode
    else job = { key = key, mode = mode or "all" } end
    SendOne()
end

---------------------------------------------------------------------------
-- Mailbox buttons and their menu
---------------------------------------------------------------------------
local function HideMenu() if menu then menu:Hide() end end

local function MenuItem(i, text, enabled, fn)
    local b = menu.items[i]
    if not b then
        b = TT.Button(menu, "", 200, nil)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 25)
        menu.items[i] = b
    end
    b:SetText(text)
    b:SetEnabled(enabled)
    b:SetScript("OnClick", function() HideMenu(); fn() end)
    b:Show()
end

local function OpenMenu(key, anchor)
    if menu:IsShown() and menu.key == key then HideMenu(); return end
    menu.key = key
    local _, mails = Plan(key, "all")
    local iItems, iMails = Plan(key, "items")
    local _, _, gGold = Plan(key, "gold")
    MenuItem(1, string.format("Send all  (%d %s)", mails, mails == 1 and "mail" or "mails"), mails > 0,
        function() Start(key, "all") end)
    MenuItem(2, string.format("Only items  (%d in %d %s)", iItems, iMails, iMails == 1 and "mail" or "mails"), iItems > 0,
        function() Start(key, "items") end)
    MenuItem(3, gGold > 0 and ("Only gold  (" .. Money(gGold) .. ")") or "Only gold  (none spare)", gGold > 0,
        function() Start(key, "gold") end)
    MenuItem(4, "Settings...", true, function() TT:ShowPage("BankAlt") end)
    menu.title:SetText(P(key).label .. ": " .. (NameOf(key) or "?"))
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

UpdateButtons = function()
    local open = M.enabled and MailFrame and MailFrame:IsShown()
    local x = 0
    for _, key in ipairs(KEYS) do
        local b = buttons[key]
        local to = NameOf(key)
        local show = open and to and not IsMe(to) and not HiddenHere(key) and true or false
        b:SetShown(show)
        if show then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", x, -4)
            x = x + b:GetWidth() + 6
            local label = P(key).label .. ": " .. to
            if sending and job and job.key == key then
                b:SetText("Sending..."); b:Disable()
            elseif job and job.key == key and job.manual then
                b:SetText(label .. "  (next mail)"); b:Enable()
            else
                b:SetText(label); b:Enable()
            end
        end
    end
    if not open then HideMenu() end
end

local function OnEvent(_, event, _, a2)
    if event == "MAIL_SHOW" then
        job = nil
        C_Timer.After(0, UpdateButtons)
    elseif event == "MAIL_CLOSED" then
        if sending then Stop() end
        job = nil
        UpdateButtons()
    elseif event == "MAIL_SEND_SUCCESS" then
        if not sending then return end
        if timer then timer:Cancel(); timer = nil end
        sending = false
        if not job then return UpdateButtons() end
        if not job.more then
            TT.Print("Mail to Alts: all sent to " .. (NameOf(job.key) or "?") .. ".")
            job = nil
            return UpdateButtons()
        end
        if job.manual then return UpdateButtons() end
        C_Timer.After(0.6, SendOne)                  -- next mail once the bags have updated
    elseif event == "MAIL_FAILED" then
        if sending then Stop("a mail failed (is the name right?), nothing more was sent.") end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- the game wants a real click per mail: one mail per click from now on
        if sending and a2 and tostring(a2):find("SendMail") and job then
            job.manual = true
            if ClearSendMail then ClearSendMail() end
            Stop("the game wants a click for each mail: click the button again for the next one.", true)
        end
    elseif event == "GLOBAL_MOUSE_DOWN" then
        if menu and menu:IsShown() and not menu:IsMouseOver() then
            local overButton = false
            for _, b in pairs(buttons) do if b:IsMouseOver() then overButton = true end end
            if not overButton then HideMenu() end
        end
    end
end

function M:Setup()
    for _, key in ipairs(KEYS) do
        local b = TT.Button(UIParent, "", 170, nil)
        b:SetHeight(24)
        b:SetScript("OnClick", function(btn)
            if job and job.key == key and job.manual and not sending then Start(key) else OpenMenu(key, btn) end
        end)
        b:Hide()
        buttons[key] = b
    end
    menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetSize(212, 6 + 4 * 25 + 20)
    menu:SetFrameStrata("DIALOG")
    TT.Flat(menu, C.bg, C.border)
    menu.items = {}
    menu.title = TT.Label(menu, "", "GameFontNormalSmall")
    menu.title:SetPoint("BOTTOMLEFT", 8, 6)
    menu.title:SetTextColor(unpack(C.dim))
    menu:Hide()
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", OnEvent)
end

local EVENTS = { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED",
                 "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "GLOBAL_MOUSE_DOWN" }
function M:OnLoad()
    -- the first version had one recipient: move it into the "Bank alt" profile
    local db = M.db
    if db.recipient and db.recipient ~= "" and db.profiles.bank.name == "" then
        local b = db.profiles.bank
        b.name, b.subject, b.items, b.types = db.recipient, db.subject or "", db.items or {}, db.types or {}
        b.gold, b.keepGold = db.gold or false, db.keepGold or 50
    end
    db.recipient, db.subject, db.items, db.types, db.gold, db.keepGold = nil, nil, nil, nil, nil, nil
end
function M:OnEnable()
    for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    if MailFrame then
        for _, b in pairs(buttons) do b:SetParent(MailFrame); b:SetFrameStrata(MailFrame:GetFrameStrata()) end
    end
    UpdateButtons()
end
function M:OnDisable()
    for _, e in ipairs(EVENTS) do pcall(ev.UnregisterEvent, ev, e) end
    if sending then Stop() end
    for _, b in pairs(buttons) do b:Hide() end
    HideMenu()
end

---------------------------------------------------------------------------
-- Settings: one tab per character
---------------------------------------------------------------------------
function M:BuildSettings(body, page)
    local shown = "main"
    local refreshers = {}
    local tabs = {}
    local function Refresh() for _, f in ipairs(refreshers) do f() end end
    for i, key in ipairs(KEYS) do
        local t = TT.Button(body, "", 140, function() shown = key; Refresh() end)
        t:SetPoint("TOPLEFT", (i - 1) * 146, 0)
        tabs[key] = t
    end
    refreshers[#refreshers + 1] = function()
        for _, key in ipairs(KEYS) do
            local n = NameOf(key)
            tabs[key]:SetText(P(key).label .. (n and (": " .. n) or ""))
            tabs[key]:SetBackdropBorderColor(unpack(key == shown and C.accent or C.border))
        end
    end
    local y = 36
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(C.dim)); h:SetPoint("TOPLEFT", 0, -y); y = y + 20
    end
    local function Box(label, field, w)
        local l = TT.Label(body, label)
        l:SetPoint("TOPLEFT", 2, -y - 4)
        local b = TT.EditBox(body, w, 22)
        b:SetPoint("TOPLEFT", 140, -y)
        b:SetScript("OnTextChanged", function(box, user)
            if user then P(shown)[field] = strtrim(box:GetText() or ""); UpdateButtons() end
        end)
        b:SetScript("OnEnterPressed", function(box) box:ClearFocus(); Refresh() end)
        b:SetScript("OnEditFocusLost", function() Refresh() end)
        refreshers[#refreshers + 1] = function() b:SetText(P(shown)[field] or "") end
        y = y + 28
    end

    Head("Character")
    Box("Character name", "name", 180)
    Box("Button label", "label", 180)
    Box("Mail subject", "subject", 180)
    -- per character: show this profile's button at the mailbox here or not
    local here = TT.Check(body, "", function(v) P(shown).hideOn[CharKey()] = (not v) or nil; UpdateButtons() end)
    here:SetPoint("TOPLEFT", 2, -y)
    refreshers[#refreshers + 1] = function()
        here.Text:SetText("Show this button on " .. UnitName("player") .. " (the character you're on)")
        here:SetHitRectInsets(0, -(here.Text:GetStringWidth() + 12), -4, -4)
        here:SetChecked(not HiddenHere(shown))
    end
    y = y + 28

    Head("Item types to send")
    for i, t in ipairs(TYPES) do
        local col = (i - 1) % 3
        local cb = TT.Check(body, t[2], function(v) P(shown).types[t[1]] = v or nil end)
        cb:SetPoint("TOPLEFT", 2 + col * 190, -y)
        refreshers[#refreshers + 1] = function() cb:SetChecked(P(shown).types[t[1]] and true or false) end
        if col == 2 or i == #TYPES then y = y + 24 end
    end
    y = y + 6

    Head("Gold")
    local gcb = TT.Check(body, "Send gold, keep this much on the character:", function(v) P(shown).gold = v end)
    gcb:SetPoint("TOPLEFT", 2, -y)
    refreshers[#refreshers + 1] = function() gcb:SetChecked(P(shown).gold) end
    -- type any amount (whole gold); empty counts as 0
    local keep = TT.EditBox(body, 80, 22)
    keep:SetPoint("TOPLEFT", 330, -y + 2)
    keep:SetNumeric(true)
    keep:SetMaxLetters(7)
    keep:SetScript("OnTextChanged", function(box, user)
        if user then P(shown).keepGold = tonumber(box:GetText()) or 0 end
    end)
    keep:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    keep:SetScript("OnEditFocusLost", function(box) box:SetText(P(shown).keepGold or 0) end)
    local unit = TT.Label(body, "gold", "GameFontHighlight")
    unit:SetPoint("LEFT", keep, "RIGHT", 6, 0)
    refreshers[#refreshers + 1] = function() keep:SetText(P(shown).keepGold or 0) end
    y = y + 34

    Head("Always send these items")
    -- one ID list per character, only the shown one is visible
    local holder = CreateFrame("Frame", nil, body)
    holder:SetPoint("TOPLEFT", 0, -y); holder:SetSize(360, 160)
    local lists = {}
    for _, key in ipairs(KEYS) do
        local l = TT.IDList(holder, 360, 160, P(key).items, function(id)
            local n = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
            return id .. (n and ("  " .. n) or "")
        end)
        l:SetPoint("TOPLEFT")
        lists[key] = l
    end
    refreshers[#refreshers + 1] = function()
        for key, l in pairs(lists) do l:SetShown(key == shown); if key == shown then l.Refresh() end end
    end
    local drop = TT.Button(body, "Drop an item here", 170, nil)
    drop:SetPoint("TOPLEFT", 380, -y)
    local function AddFromCursor()
        local kind, id = GetCursorInfo()
        if kind == "item" and id then
            ClearCursor()
            local items = P(shown).items
            for _, v in ipairs(items) do if v == id then return end end
            items[#items + 1] = id
            Refresh()
        end
    end
    drop:SetScript("OnReceiveDrag", AddFromCursor)
    drop:SetScript("OnClick", AddFromCursor)
    y = y + 168
    local help = TT.Label(body,
        "At a mailbox there is a button per character under the mail window (not for the one\n" ..
        "you're playing). It opens a menu: send all, only items, only gold. 12 items per mail,\n" ..
        "one mail after another, gold in the last one. Soulbound, locked and quest items are\n" ..
        "never sent. If the game wants a click per mail, the button says \"next mail\".", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y)

    page.OnPageShow = Refresh
end
