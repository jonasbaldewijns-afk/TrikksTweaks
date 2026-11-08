-- Module: Mail to Alts
-- Two saved characters ("Main" and "Bank alt"), each with its own rules:
-- items to always send (whitelist), whole item types (cloth, herbs, ore, ...)
-- and all gold above an amount you keep. At a mailbox there is a button per
-- character: a click sends everything set in /trikks (quick send), "..." opens
-- a panel to pick item types and type an amount of gold for this one send.
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
             hideOn = {}, boeQuality = 2 }    -- BoE gear: this quality and better (2 = uncommon)           -- characters ("Name-Realm") that don't show this button
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

-- BoE gear: a weapon or armour piece that isn't bound yet (bound items never
-- get this far), of at least the chosen quality
local WEAPON = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
local ARMOR = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
local function IsBoE(classID, equipLoc, quality, minQ)
    return (classID == WEAPON or classID == ARMOR) and equipLoc and equipLoc ~= ""
        and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and quality and not IsSecret(quality) and quality >= minQ
end
local function InList(r, itemID)
    for _, id in ipairs(r.items) do if id == itemID then return true end end
    return false
end
-- which ticked type an item is (key from TYPES), plus what IsBoE needs
local function TypeOf(itemID)
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return nil end
    for _, t in ipairs(TYPES) do
        if classID == t[3] and (t[4] == nil or subclassID == t[4]) then return t[1], equipLoc, classID end
    end
    return nil, equipLoc, classID
end

-- every bag slot that can be mailed at all: not bound, not locked, no quest item
local function Mailable()
    local list = {}
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not IsSecret(info.itemID) and not info.isBound and not info.isLocked then
                local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
                if not (q and (q.isQuestItem or q.questID)) then
                    list[#list + 1] = { bag, slot, itemID = info.itemID, quality = info.quality }
                end
            end
        end
    end
    return list
end

-- Rules for one send: from a profile, or the send panel's ticks for this time.
-- { items (the always-send list), useList, types (set), boeQuality, gold, keepGold }
local function RulesFrom(p)
    local types = {}
    for k, v in pairs(p.types) do types[k] = v end
    return { items = p.items, useList = true, types = types, boeQuality = p.boeQuality or 2,
             gold = p.gold, keepGold = p.keepGold or 0 }
end
local function Wanted(r, s)
    if r.useList and InList(r, s.itemID) then return true end
    local tkey, equipLoc, classID = TypeOf(s.itemID)
    if tkey and r.types[tkey] then return true end
    return r.types.boe and IsBoE(classID, equipLoc, s.quality, r.boeQuality) or false
end
local function Collect(r)
    local list = {}
    for _, s in ipairs(Mailable()) do if Wanted(r, s) then list[#list + 1] = s end end
    return list
end
-- gold for this send: a typed amount (send panel), or all above "keep" (settings)
local function SpareGold(r, margin)
    local free = math.max(0, GetMoney() - (margin or 0))
    if r.goldAmount then return math.min(r.goldAmount * 10000, free) end
    if not r.gold then return 0 end
    return math.max(0, free - (r.keepGold or 0) * 10000)
end

local function Money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return math.floor(copper / 10000) .. "g"
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local buttons, choosers, ev = {}, {}, nil
local job                        -- { key, rules, manual, more } while a run is going
local sending, timer = false, nil
local UpdateButtons, RefreshPanel

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
    local p, r, to = P(job.key), job.rules, NameOf(job.key)
    if not to or IsMe(to) then return Stop("set a different character's name in /trikks first.") end
    if not (MailFrame and MailFrame:IsShown()) then return Stop() end
    ShowSendTab()
    if ClearSendMail then ClearSendMail() end
    -- bags may have moved since the last mail: look again every time
    local queue = Collect(r)
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
    if #queue == 0 then                                -- last mail: the gold goes along
        local postage = GetSendMailPrice and GetSendMailPrice() or n * POSTAGE_GUESS
        money = math.max(0, SpareGold(r) - postage)
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

local function Start(key, rules)
    if sending then return end
    if not (job and job.key == key and job.manual) then job = { key = key, rules = rules } end
    SendOne()
end

---------------------------------------------------------------------------
-- The send panel: every option with a live count from your bags, ticked
-- from the profile; changes only count for this send unless saved
---------------------------------------------------------------------------
local panel, sel, selKey
local rows = {}                  -- category key -> { cb, label, text }

local function Counts()
    local c = { list = 0, boe = 0 }
    for _, s in ipairs(Mailable()) do
        if InList(sel, s.itemID) then c.list = c.list + 1 end
        local tkey, equipLoc, classID = TypeOf(s.itemID)
        if tkey then c[tkey] = (c[tkey] or 0) + 1 end
        if IsBoE(classID, equipLoc, s.quality, sel.boeQuality) then c.boe = c.boe + 1 end
    end
    return c
end

RefreshPanel = function()
    if not (panel and panel:IsShown() and sel) then return end
    local c = Counts()
    for key, row in pairs(rows) do
        local n = c[key] or 0
        row.cb.Text:SetText(row.text .. "  |cff888888(" .. n .. ")|r")
        row.cb:SetChecked(key == "list" and sel.useList or (key ~= "list" and sel.types[key]) and true or false)
    end
    if not panel.goldBox:HasFocus() then panel.goldBox:SetText(sel.goldAmount > 0 and sel.goldAmount or "") end
    panel.have:SetText("(you have " .. Money(GetMoney()) .. ")")
    panel.boeQ.Refresh()
    local items = #Collect(sel)
    local mails = math.ceil(items / MAX)
    local gold = SpareGold(sel, (items + 1) * POSTAGE_GUESS)
    if gold > 0 and mails == 0 then mails = 1 end
    local parts = {}
    if items > 0 then parts[#parts + 1] = items .. (items == 1 and " stack" or " stacks") end
    if gold > 0 then parts[#parts + 1] = Money(gold) end
    panel.summary:SetText(#parts > 0 and (table.concat(parts, " + ") .. string.format("  in %d %s", mails, mails == 1 and "mail" or "mails"))
        or "|cff888888Nothing ticked to send.|r")
    panel.send:SetEnabled(mails > 0 and not sending)
end

local function OpenPanel(key)
    if panel:IsShown() and selKey == key then panel:Hide(); return end
    -- nothing ticked yet: you pick for this one send (the always-send list is the profile's)
    selKey = key
    sel = { items = P(key).items, useList = false, types = {}, boeQuality = P(key).boeQuality or 2, goldAmount = 0 }
    panel.TitleText:SetText(("Send to " .. (NameOf(key) or "?") .. "  (" .. P(key).label .. ")"):upper())
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
    panel:Show()
    RefreshPanel()
end

local function BuildPanel()
    panel = TT.Window("TrikksTweaksMailPanel", 380, 330, "Send")
    panel:SetScript("OnShow", function() C_Timer.After(0, RefreshPanel) end)
    local function Row(key, text, x, y)
        local cb = TT.Check(panel, text, function(v)
            if key == "list" then sel.useList = v else sel.types[key] = v or nil end
            RefreshPanel()
        end)
        cb:SetPoint("TOPLEFT", x, y)
        rows[key] = { cb = cb, text = text }
    end
    -- two columns: the always-send list, every item type, BoE gear
    local cats = { { "list", "Always-send list" } }
    for _, t in ipairs(TYPES) do cats[#cats + 1] = { t[1], t[2] } end
    cats[#cats + 1] = { "boe", "BoE gear" }
    local perCol = math.ceil(#cats / 2)
    for i, c in ipairs(cats) do
        local col, row = math.floor((i - 1) / perCol), (i - 1) % perCol
        Row(c[1], c[2], 16 + col * 180, -40 - row * 22)
    end
    local y = -40 - perCol * 22 - 6
    local ql = TT.Label(panel, "BoE quality:", "GameFontHighlightSmall")
    ql:SetPoint("TOPLEFT", 16, y - 4)
    local function Q(q, text)
        local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        return { q, (col and col.hex or "") .. text .. "|r" }
    end
    panel.boeQ = TT.Cycle(panel, 150, { Q(2, "Uncommon and up"), Q(3, "Rare and up"), Q(4, "Epic and up") },
        function() return sel and sel.boeQuality or 2 end, function(v) sel.boeQuality = v; RefreshPanel() end)
    panel.boeQ:SetPoint("TOPLEFT", 100, y)
    y = y - 32
    local gt = TT.Label(panel, "Gold to send:", "GameFontHighlight")
    gt:SetPoint("TOPLEFT", 16, y - 4)
    panel.goldBox = TT.EditBox(panel, 80, 22)
    panel.goldBox:SetPoint("TOPLEFT", 110, y)
    panel.goldBox:SetNumeric(true)
    panel.goldBox:SetMaxLetters(7)
    panel.goldBox:SetScript("OnTextChanged", function(box, user)
        if user then sel.goldAmount = tonumber(box:GetText()) or 0; RefreshPanel() end
    end)
    panel.goldBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    local gl = TT.Label(panel, "gold", "GameFontHighlight")
    gl:SetPoint("LEFT", panel.goldBox, "RIGHT", 6, 0)
    panel.have = TT.Label(panel, "", "GameFontDisableSmall")
    panel.have:SetPoint("LEFT", gl, "RIGHT", 10, 0)
    y = y - 34
    panel.summary = TT.Label(panel, "", "GameFontHighlight")
    panel.summary:SetPoint("TOPLEFT", 16, y)
    panel.send = TT.Button(panel, "Send", 120, function() local r = sel; panel:Hide(); Start(selKey, r) end)
    panel.send:SetPoint("BOTTOMLEFT", 16, 14)
    local set = TT.Button(panel, "Settings...", 100, function() TT:ShowPage("BankAlt") end)
    set:SetPoint("LEFT", panel.send, "RIGHT", 6, 0)
end

UpdateButtons = function()
    local open = M.enabled and MailFrame and MailFrame:IsShown()
    local x = 0
    for _, key in ipairs(KEYS) do
        local b = buttons[key]
        local to = NameOf(key)
        local show = open and to and not IsMe(to) and not HiddenHere(key) and true or false
        b:SetShown(show)
        choosers[key]:SetShown(show)
        if show then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", x, -4)
            choosers[key]:ClearAllPoints()
            choosers[key]:SetPoint("LEFT", b, "RIGHT", 2, 0)
            x = x + b:GetWidth() + choosers[key]:GetWidth() + 10
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
    if not open and panel then panel:Hide() end
    RefreshPanel()
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
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
        RefreshPanel()
    end
end

function M:Setup()
    for _, key in ipairs(KEYS) do
        local b = TT.Button(UIParent, "", 170, nil)
        b:SetHeight(24)
        -- left-click: quick send (everything as set in /trikks); right-click: choose
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, mouse)
            if mouse == "RightButton" then OpenPanel(key); return end
            if job and job.key == key and job.manual and not sending then Start(key)
            else Start(key, RulesFrom(P(key))) end
        end)
        b:HookScript("OnEnter", function(btn)
            local r = RulesFrom(P(key))
            local items = #Collect(r)
            local gold = SpareGold(r, (items + 1) * POSTAGE_GUESS)
            GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Quick send to " .. (NameOf(key) or "?"), 1, 1, 1)
            GameTooltip:AddLine(items .. (items == 1 and " stack" or " stacks") .. (gold > 0 and (" + " .. Money(gold)) or ""), 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Everything set in /trikks > Mail to Alts.", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("Right-click or ...: choose what to send.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", GameTooltip_Hide)
        b:Hide()
        buttons[key] = b
        local c = TT.Button(UIParent, "...", 26, function() OpenPanel(key) end)
        c:SetHeight(24)
        c:Hide()
        choosers[key] = c
    end
    BuildPanel()
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", OnEvent)
end

local EVENTS = { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED",
                 "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }
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
        for _, list in ipairs({ buttons, choosers }) do
            for _, b in pairs(list) do b:SetParent(MailFrame); b:SetFrameStrata(MailFrame:GetFrameStrata()) end
        end
    end
    UpdateButtons()
end
function M:OnDisable()
    for _, e in ipairs(EVENTS) do pcall(ev.UnregisterEvent, ev, e) end
    if sending then Stop() end
    for _, b in pairs(buttons) do b:Hide() end
    for _, b in pairs(choosers) do b:Hide() end
    if panel then panel:Hide() end
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
    -- BoE gear, with its minimum quality
    local boe = TT.Check(body, "BoE gear (not bound yet)", function(v) P(shown).types.boe = v or nil end)
    boe:SetPoint("TOPLEFT", 2, -y)
    refreshers[#refreshers + 1] = function() boe:SetChecked(P(shown).types.boe and true or false) end
    local function Q(q, text)
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        return { q, (c and c.hex or "") .. text .. "|r" }
    end
    local boeQ = TT.Cycle(body, 150, { Q(2, "Uncommon and up"), Q(3, "Rare and up"), Q(4, "Epic and up") },
        function() return P(shown).boeQuality or 2 end, function(v) P(shown).boeQuality = v end)
    boeQ:SetPoint("TOPLEFT", 230, -y + 2)
    refreshers[#refreshers + 1] = boeQ.Refresh
    y = y + 30

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
        "At a mailbox: a button per character under the mail window. Click = quick send of\n" ..
        "everything set here. \"...\" (or right-click) = pick item types and type an amount of gold\n" ..
        "for this one send. 12 items per mail, one mail after another, gold in the last one.\n" ..
        "Soulbound, locked and quest items are never sent. If the game wants a click per\n" ..
        "mail, the button says \"next mail\".", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y)

    page.OnPageShow = Refresh
end
