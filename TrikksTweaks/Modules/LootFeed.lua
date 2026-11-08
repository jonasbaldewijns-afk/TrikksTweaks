-- Module: Loot Feed
-- A list of what you (and your group) loot: icon, item name in its quality
-- colour, count, who got it (class colour), item level and sockets for gear.
-- Identical drops merge into one line, entries fade out after a while (not
-- while your mouse is on the feed), and the feed is placed with Edit Mode.
--
-- Where the data comes from: the loot lines in chat ("You receive loot: ...",
-- "Name receives loot: ..."). Personal drops, group loot and roll wins all end
-- in one of those lines, so one source covers everything. The patterns are
-- built from Blizzard's own text (LOOT_ITEM_SELF and friends), so they match
-- the client's wording. On this engine a chat line can be "secret" during
-- encounters; those are skipped (they can't be read, only shown by Blizzard).
local _, TT = ...
local C = TT.C
local IsSecret = TT.IsSecret

local M = TT:RegisterModule("LootFeed", {
    title = "Loot Feed",
    category = "Interface",
    desc = "Your loot (and your group's) in a feed: quality colours, item level, sockets, merged drops, filters, Edit Mode position.",
    defaults = {
        mine = true, group = true, pushed = true, merge = true, onlyGear = false,
        quality = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true },   -- 4 = epic and better
        duration = 15, limit = 6, width = 300, height = 36, fontSize = 13, opacity = 60,
        grow = "DOWN", blacklist = {}, layouts = {},
    },
})

local DEFAULT_POS = { point = "CENTER", x = 300, y = 0 }
local container, ticker
local active, pool = {}, {}         -- entries on screen (newest first), spare entry frames
local inEditMode, currentLayout, testing = false, nil, false
local blocked = {}                  -- blacklist as a set

---------------------------------------------------------------------------
-- Reading the loot lines
---------------------------------------------------------------------------
-- "You receive loot: %sx%d." -> "^You receive loot: (.+)x(%d+)%.$"
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end
-- who: "self" or "other" (first capture is the name); multi: last capture is the count;
-- push: an item given to you (quest reward, created, ...), not looted
local RULES = {}
local function Rule(fmt, who, multi, push)
    local p = Pattern(fmt)
    if p then RULES[#RULES + 1] = { p = p, who = who, multi = multi, push = push } end
end
-- the "x%d" versions first: the plain ones would also match "[Item]x3"
Rule(LOOT_ITEM_SELF_MULTIPLE, "self", true)
Rule(LOOT_ITEM_SELF, "self")
Rule(LOOT_ITEM_PUSHED_SELF_MULTIPLE, "self", true, true)
Rule(LOOT_ITEM_PUSHED_SELF, "self", false, true)
Rule(LOOT_ITEM_MULTIPLE, "other", true)
Rule(LOOT_ITEM, "other")
Rule(LOOT_ITEM_PUSHED_MULTIPLE, "other", true, true)
Rule(LOOT_ITEM_PUSHED, "other", false, true)

local function Parse(msg)
    for _, r in ipairs(RULES) do
        local a, b, c = msg:match(r.p)
        if a then
            local name, link, count
            if r.who == "self" then link, count = a, b
            else name, link, count = a, b, c end
            if link and link:find("|Hitem:") then
                return r.who, name, link, (r.multi and tonumber(count)) or 1, r.push
            end
        end
    end
end

---------------------------------------------------------------------------
-- Names in class colour
---------------------------------------------------------------------------
local function ClassColored(name, unit)
    local class = unit and select(2, UnitClass(unit))
    local col = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
    if col and col.WrapTextInColorCode then return col:WrapTextInColorCode(name) end
    return name
end
local function PlayerLabel(who, name)
    if who == "self" then return ClassColored(UnitName("player"), "player") end
    local short = name and Ambiguate and Ambiguate(name, "short") or name
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        local u = prefix .. i
        local n = GetUnitName(u, true)
        if n and not IsSecret(n) and (n == name or Ambiguate(n, "short") == short) then return ClassColored(short, u) end
    end
    return short or "?"
end

---------------------------------------------------------------------------
-- The feed
---------------------------------------------------------------------------
local function Font(fs, size)
    local file, _, flags = fs:GetFont()
    fs:SetFont(file or STANDARD_TEXT_FONT, size, flags or "")
end

local function ShowTooltip(e)
    local d = e.data
    if not d then return end
    GameTooltip:SetOwner(e, "ANCHOR_LEFT")
    if d.link then GameTooltip:SetHyperlink(d.link) else GameTooltip:SetText(d.name or "?") end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift-click: link in chat   Ctrl-click: try on", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Alt-right-click: never show this item again", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local Layout, Remove
local function NewEntry()
    local e = table.remove(pool)
    if e then return e end
    e = CreateFrame("Button", nil, container, "BackdropTemplate")
    e:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    e.edge = e:CreateTexture(nil, "ARTWORK")
    e.edge:SetColorTexture(0, 0, 0, 1)
    e.icon = e:CreateTexture(nil, "ARTWORK", nil, 1)
    e.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    e.icon:SetPoint("TOPLEFT", e.edge, 1, -1); e.icon:SetPoint("BOTTOMRIGHT", e.edge, -1, 1)
    e.count = e:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    e.count:SetPoint("BOTTOMRIGHT", e.edge, -1, 2)
    e.name = e:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    e.name:SetJustifyH("LEFT"); e.name:SetWordWrap(false)
    e.sub = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    e.sub:SetJustifyH("LEFT"); e.sub:SetWordWrap(false)
    e:SetScript("OnEnter", ShowTooltip)
    e:SetScript("OnLeave", GameTooltip_Hide)
    e:SetScript("OnClick", function(self, button)
        local d = self.data
        if not (d and d.link) then return end
        if button == "RightButton" and IsAltKeyDown() and d.itemID then
            local list = M.db.blacklist
            list[#list + 1] = d.itemID
            blocked[d.itemID] = true
            TT.Print("Loot Feed: " .. (d.name or d.itemID) .. " won't show any more (undo in /trikks).")
            Remove(self)
        elseif IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(d.link)
        elseif IsModifiedClick("DRESSUP") and DressUpItemLink then
            DressUpItemLink(d.link)
        end
    end)
    return e
end

-- size, fonts and colours from the settings (also when they change)
local function Style(e)
    local db, h = M.db, M.db.height
    e:SetSize(db.width, h)
    TT.Flat(e, { C.bg[1], C.bg[2], C.bg[3], db.opacity / 100 }, C.border)
    e.edge:ClearAllPoints()
    e.edge:SetPoint("LEFT", 4, 0)
    e.edge:SetSize(h - 8, h - 8)
    Font(e.name, db.fontSize); Font(e.sub, math.max(8, db.fontSize - 2))
    e.name:ClearAllPoints()
    e.name:SetPoint("TOPLEFT", e.edge, "TOPRIGHT", 7, -1); e.name:SetPoint("RIGHT", -6, 0)
    e.sub:ClearAllPoints()
    e.sub:SetPoint("BOTTOMLEFT", e.edge, "BOTTOMRIGHT", 7, 1); e.sub:SetPoint("RIGHT", -6, 0)
end

local function Fill(e)
    local d = e.data
    e.icon:SetTexture(d.icon or 134400)
    local col = d.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[d.quality]
    e.name:SetText(d.name or "...")
    if col then
        e.name:SetTextColor(col.r, col.g, col.b)
        e:SetBackdropBorderColor(col.r * 0.6, col.g * 0.6, col.b * 0.6, 1)
    else
        e.name:SetTextColor(1, 1, 1)
        e:SetBackdropBorderColor(unpack(C.border))
    end
    e.count:SetText(d.count > 1 and d.count or "")
    local parts = { d.player }
    if d.ilvl then parts[#parts + 1] = "|cffbbbbbbilvl " .. d.ilvl .. "|r" end
    if d.sockets and d.sockets > 0 then
        parts[#parts + 1] = "|cffbbbbbb" .. d.sockets .. (d.sockets == 1 and " socket" or " sockets") .. "|r"
    end
    e.sub:SetText(table.concat(parts, "  ·  "))
end

Layout = function()
    local db = M.db
    local gap = 3
    container:SetSize(db.width, db.height)
    for i, e in ipairs(active) do
        local off = (i - 1) * (db.height + gap)
        e:ClearAllPoints()
        if db.grow == "UP" then e:SetPoint("BOTTOM", container, "BOTTOM", 0, off)
        else e:SetPoint("TOP", container, "TOP", 0, -off) end
    end
end

Remove = function(e)
    for i, x in ipairs(active) do
        if x == e then table.remove(active, i); break end
    end
    e:Hide(); e.data = nil
    pool[#pool + 1] = e
    Layout()
end

local function Clear()
    for i = #active, 1, -1 do Remove(active[i]) end
end

-- One timer for the whole feed, only while something is on screen.
-- While the mouse is on the feed nothing ages (so you can read / click it).
local FADE = 0.6
local function Tick()
    if #active == 0 then
        if ticker then ticker:Cancel(); ticker = nil end
        return
    end
    local now = GetTime()
    local hovered = false
    for _, e in ipairs(active) do if e:IsMouseOver() then hovered = true; break end end
    for i = #active, 1, -1 do
        local e = active[i]
        local d = e.data
        if hovered then
            d.born = d.born + 0.1                          -- pause: push the clock along
            e:SetAlpha(1)
        elseif not d.sticky then
            local age = now - d.born - M.db.duration
            if age >= FADE then Remove(e)
            elseif age > 0 then e:SetAlpha(1 - age / FADE)
            else e:SetAlpha(1) end
        end
    end
end
local function StartTicker()
    if not ticker then ticker = C_Timer.NewTicker(0.1, Tick) end
end

local function Push(d)
    -- same item for the same person still on screen: add up
    if M.db.merge then
        for _, e in ipairs(active) do
            local o = e.data
            if o and not o.sticky and o.itemID == d.itemID and o.player == d.player then
                o.count = o.count + d.count
                o.born = GetTime()
                e:SetAlpha(1)
                Fill(e)
                return
            end
        end
    end
    local e = NewEntry()
    e.data = d
    Style(e)
    Fill(e)
    e:SetAlpha(1)
    e:Show()
    table.insert(active, 1, e)
    while #active > M.db.limit do Remove(active[#active]) end
    Layout()
    StartTicker()
end

-- item details (may need the item to load from the server first)
local function Sockets(link)
    local stats = C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link)
    if not stats then return 0 end
    local n = 0
    for k, v in pairs(stats) do
        if type(k) == "string" and k:find("^EMPTY_SOCKET_") and type(v) == "number" then n = n + v end
    end
    return n
end
local function Build(who, name, link, count)
    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID or blocked[itemID] then return end
    local iname, _, quality, _, _, _, _, _, equipLoc, icon = C_Item.GetItemInfo(link)
    if not iname then return false end                             -- not loaded yet
    local q = math.min(quality or 1, 4)
    if not M.db.quality[q] then return end
    local gear = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
    if M.db.onlyGear and not gear then return end
    local d = { itemID = itemID, link = link, name = iname, quality = quality, icon = icon,
                count = count, player = PlayerLabel(who, name), born = GetTime() }
    if gear then
        local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
        if ilvl and not IsSecret(ilvl) and ilvl > 1 then d.ilvl = ilvl end
        d.sockets = Sockets(link)
    end
    Push(d)
end

local function OnLoot(msg)
    if not msg or IsSecret(msg) then return end
    local who, name, link, count, push = Parse(msg)
    if not who then return end
    if who == "self" and not M.db.mine then return end
    if who == "other" and not M.db.group then return end
    if push and not M.db.pushed then return end
    if Build(who, name, link, count) == false then
        -- wait for the item to load, then try once more
        local item = Item and Item.CreateFromItemLink and Item:CreateFromItemLink(link)
        if item and not item:IsItemEmpty() then
            item:ContinueOnItemLoad(function() Build(who, name, link, count) end)
        end
    end
end

---------------------------------------------------------------------------
-- Test entries (also shown in Edit Mode, so there is something to move)
---------------------------------------------------------------------------
local SAMPLES = {
    { id = 2589, name = "Linen Cloth", quality = 1, count = 4 },
    { id = 2318, name = "Light Leather", quality = 1, count = 3 },
    { id = 2770, name = "Copper Ore", quality = 1, count = 2 },
    { id = 9395, name = "Gloves of Old", quality = 2, count = 1, ilvl = 24 },
    { id = 2059, name = "Sentry Cloak", quality = 3, count = 1, ilvl = 28, sockets = 1 },
    { id = 1728, name = "Teebu's Blazing Longsword", quality = 4, count = 1, ilvl = 63 },
}
local function ShowSamples(on)
    testing = on
    for i = #active, 1, -1 do
        if active[i].data.sticky then Remove(active[i]) end
    end
    if not on then return end
    for i = math.min(#SAMPLES, M.db.limit), 1, -1 do
        local s = SAMPLES[i]
        local icon = select(5, C_Item.GetItemInfoInstant(s.id))
        Push({ itemID = -i, name = s.name, quality = s.quality, icon = icon, count = s.count, ilvl = s.ilvl,
               sockets = s.sockets, player = ClassColored(UnitName("player"), "player"), born = GetTime(), sticky = true })
    end
end

-- re-apply size / fonts / opacity to what is on screen
local function Restyle()
    if not container then return end
    for _, e in ipairs(active) do Style(e); Fill(e) end
    for _, e in ipairs(pool) do Style(e) end
    Layout()
end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
local function Position()
    local p = currentLayout and M.db.layouts[currentLayout] or DEFAULT_POS
    container:ClearAllPoints()
    container:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end
local function RegisterEditMode()
    local LEM = LibStub and LibStub("LibEditMode", true)
    if not LEM then return end
    LEM:AddFrame(container, function(frame, layoutName)
        local cx, cy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local es, ues = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local x, y = (cx * es - ux * ues) / es, (cy * es - uy * ues) / es
        M.db.layouts[layoutName] = { point = "CENTER", x = x, y = y }
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end, DEFAULT_POS, "Loot Feed")
    LEM:RegisterCallback("layout", function(layoutName) currentLayout = layoutName; Position() end)
    LEM:RegisterCallback("enter", function() inEditMode = true; if M.enabled then ShowSamples(true) end end)
    LEM:RegisterCallback("exit", function() inEditMode = false; ShowSamples(false) end)
    LEM:RegisterCallback("rename", function(old, new)
        M.db.layouts[new], M.db.layouts[old] = M.db.layouts[old], nil
        if currentLayout == old then currentLayout = new end
    end)
    LEM:RegisterCallback("delete", function(name) M.db.layouts[name] = nil end)
    local ok, name = pcall(LEM.GetActiveLayoutName, LEM)
    if ok and name then currentLayout = name end
end

---------------------------------------------------------------------------
local ev
local function RebuildBlocked()
    wipe(blocked)
    for _, id in ipairs(M.db.blacklist) do blocked[id] = true end
end

function M:Setup()
    container = CreateFrame("Frame", "TrikksTweaksLootFeed", UIParent)
    container:SetSize(M.db.width, M.db.height)
    container:SetClampedToScreen(true)
    RegisterEditMode()
    Position()
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, _, msg) OnLoot(msg) end)
end

function M:OnEnable()
    RebuildBlocked()
    container:Show()
    ev:RegisterEvent("CHAT_MSG_LOOT")
    if inEditMode then ShowSamples(true) end
end

function M:OnDisable()
    ev:UnregisterEvent("CHAT_MSG_LOOT")
    Clear()
    container:Hide()
end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------
function M:BuildSettings(body, page)
    local db, refreshers, y = M.db, {}, 0
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(C.dim)); h:SetPoint("TOPLEFT", 0, -y); y = y + 20
    end
    local function Check(tbl, key, text, x)
        local cb = TT.Check(body, text, function(v) tbl[key] = v; Restyle() end)
        cb:SetPoint("TOPLEFT", (x or 0) + 2, -y)
        refreshers[#refreshers + 1] = function() cb:SetChecked(tbl[key]) end
    end
    local function Stepper(text, key, min, max, step, x)
        local s = TT.Stepper(body, text, function() return db[key] end,
            function(v) db[key] = v; Restyle() end, min, max, step)
        s:SetPoint("TOPLEFT", (x or 0), -y)
        refreshers[#refreshers + 1] = s.Refresh
    end

    Head("What to show")
    Check(db, "mine", "Your own loot"); Check(db, "group", "Your group's loot", 280); y = y + 24
    Check(db, "pushed", "Items given to you (quest rewards, created)"); Check(db, "merge", "Merge identical drops", 280); y = y + 24
    Check(db, "onlyGear", "Only equippable items"); y = y + 28

    Head("Qualities")
    local Q = { { 0, "Poor" }, { 1, "Common" }, { 2, "Uncommon" }, { 3, "Rare" }, { 4, "Epic and better" } }
    for i, q in ipairs(Q) do
        local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q[1]]
        local text = col and col.hex and (col.hex .. q[2] .. "|r") or q[2]
        Check(db.quality, q[1], text, ((i - 1) % 3) * 190)
        if i % 3 == 0 or i == #Q then y = y + 24 end
    end
    y = y + 4

    Head("Look")
    Stepper("Seconds on screen", "duration", 3, 60, 1); Stepper("Max entries", "limit", 1, 15, 1, 280); y = y + 26
    Stepper("Width", "width", 200, 500, 10); Stepper("Entry height", "height", 24, 60, 2, 280); y = y + 26
    Stepper("Font size", "fontSize", 9, 20, 1); Stepper("Background %", "opacity", 0, 100, 5, 280); y = y + 30
    local gl = TT.Label(body, "New entries:")
    gl:SetPoint("TOPLEFT", 2, -y - 4)
    local grow = TT.Cycle(body, 130, { { "DOWN", "Grow down" }, { "UP", "Grow up" } },
        function() return db.grow end, function(v) db.grow = v; Restyle() end)
    grow:SetPoint("LEFT", gl, "RIGHT", 10, 0)
    refreshers[#refreshers + 1] = grow.Refresh
    local test = TT.Button(body, "Show test entries", 140, function()
        if not M.enabled then TT.Print("turn the Loot Feed on first (Enabled, top right)."); return end
        ShowSamples(not testing)
    end)
    test:SetPoint("TOPLEFT", 282, -y)
    y = y + 34

    Head("Never show (item IDs)")
    local list = TT.IDList(body, 360, 140, db.blacklist, function(id)
        local n = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
        return id .. (n and ("  " .. n) or "")
    end, RebuildBlocked)
    list:SetPoint("TOPLEFT", 0, -y)
    refreshers[#refreshers + 1] = list.Refresh
    y = y + 148
    local help = TT.Label(body,
        "Alt-right-click an entry to add it here. Move the feed in Edit Mode (\"Loot Feed\").\n" ..
        "Your mouse on the feed stops entries fading. During some boss fights the game hides\n" ..
        "loot lines from addons: those drops can't show here.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y)

    page.OnPageShow = function() for _, f in ipairs(refreshers) do f() end end
    -- test entries go away when you leave the page
    body:HookScript("OnHide", function() if testing and not inEditMode then ShowSamples(false) end end)
end
