-- Trikks Tweaks: core
-- Every file in a WoW addon receives two values via "...": the addon's folder
-- name and a private table shared by all files of this addon. We use that
-- table (TT) as our namespace so modules can talk to the core without globals.
local ADDON, TT = ...

-- Public handle so companion addons (TrikksReskin) can add their own modules
-- to the same hub and use the same UI kit.
_G.TrikksTweaks = TT

TT.modules, TT.order = {}, {}
TT.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"

function TT.IsSecret(v) return issecretvalue and issecretvalue(v) end
function TT.Print(msg) print("|cff33ff99Trikks Tweaks:|r " .. msg) end

-- name, icon, spellID from a spell ID or known spell name
function TT.SpellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spell)
        if info then return info.name, info.iconID, info.spellID end
    elseif GetSpellInfo then
        local name, _, icon, _, _, _, id = GetSpellInfo(spell)
        return name, icon, id
    end
end

---------------------------------------------------------------------------
-- Module registry
---------------------------------------------------------------------------
-- m = { title, desc, defaults = {...}, OnLoad, OnEnable, OnDisable, BuildSettings }
-- m.addon / m.svName: which addon the module belongs to and which saved
-- variable holds its settings (defaults: this addon / TrikksTweaksDB).
function TT:RegisterModule(key, m)
    m.key, m.enabled = key, false
    m.addon = m.addon or ADDON
    m.svName = m.svName or "TrikksTweaksDB"
    self.modules[key] = m
    self.order[#self.order + 1] = key
    return m
end

-- Run a module function without letting an error in one module stop the rest.
-- The error is still shown (via WoW's error handler) so it can be fixed.
function TT.SafeCall(m, fname, ...)
    local fn = m[fname]
    if not fn then return true end
    local ok = xpcall(fn, function(err)
        geterrorhandler()("Trikks Tweaks [" .. m.key .. "." .. fname .. "]: " .. tostring(err))
    end, m, ...)
    return ok
end

function TT:SetEnabled(key, on)
    local m = self.modules[key]
    if not m or not m.db or m.enabled == on then return end
    m.enabled, m.db.enabled = on, on
    TT.SafeCall(m, on and "OnEnable" or "OnDisable")
    if self.RefreshHub then self:RefreshHub() end
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = type(dst[k]) == "table" and dst[k] or {}
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- UI kit: flat, dark, minimalist. Every module builds its UI with these, so
-- changing the look here restyles the whole addon.
---------------------------------------------------------------------------
local C = {
    bg     = { 0.06, 0.06, 0.07, 0.96 },   -- window background
    panel  = { 0.10, 0.10, 0.11, 1 },      -- buttons, boxes, title bar
    hover  = { 0.16, 0.16, 0.18, 1 },
    border = { 0.20, 0.20, 0.22, 1 },
    accent = { 0.20, 1.00, 0.60, 1 },      -- Trikks green (same as chat prefix)
    text   = { 0.92, 0.92, 0.92, 1 },
    dim    = { 0.50, 0.50, 0.53, 1 },
}
TT.C = C
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Flat background + 1px border using a plain white texture tinted by colour.
function TT.Flat(f, bg, border)
    if not f.SetBackdrop then
        Mixin(f, BackdropTemplateMixin)
        f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged)
    end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(bg or C.panel))
    f:SetBackdropBorderColor(unpack(border or C.border))
end

function TT.Label(parent, text, font)
    local l = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    l:SetText(text or "")
    l:SetJustifyH("LEFT")
    return l
end

function TT.Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    TT.Flat(b)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetText(text or "")
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self:SetBackdropColor(unpack(C.hover)); self:SetBackdropBorderColor(unpack(C.accent)) end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(C.panel)); self:SetBackdropBorderColor(unpack(C.border))
    end)
    b:SetScript("OnDisable", function(self) self:SetBackdropColor(0.07, 0.07, 0.08, 1) end)
    b:SetScript("OnEnable", function(self) self:SetBackdropColor(unpack(C.panel)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Square checkbox: empty box, filled with the accent colour when ticked.
function TT.Check(parent, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(14, 14)
    TT.Flat(cb, { 0.04, 0.04, 0.05, 1 })
    local fill = cb:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3); fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(unpack(C.accent))
    cb:SetCheckedTexture(fill)
    cb.Text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.Text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.Text:SetText(text or "")
    -- make the label clickable too
    cb:SetHitRectInsets(0, -(cb.Text:GetStringWidth() + 12), -4, -4)
    cb:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    cb:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    -- old layouts assumed a 26px tall Blizzard checkbox; keep spacing similar
    return cb
end

function TT.EditBox(parent, w, h)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(w or 150, h or 22)
    TT.Flat(e, { 0.04, 0.04, 0.05, 1 })
    e:SetFontObject("GameFontHighlightSmall")
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

-- Scroll area: mouse wheel to scroll, thin accent bar shows the position.
function TT.Scroll(parent)
    local s = CreateFrame("ScrollFrame", nil, parent)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    thumb:SetWidth(2)
    local function UpdateThumb()
        local range, h = s:GetVerticalScrollRange(), s:GetHeight()
        if range <= 0 or h <= 0 then thumb:Hide(); return end
        local th = math.max(16, h * h / (h + range))
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", s, "TOPRIGHT", 6, -(h - th) * (s:GetVerticalScroll() / range))
        thumb:Show()
    end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local v = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 26))
        self:SetVerticalScroll(v)
    end)
    s:SetScript("OnVerticalScroll", UpdateThumb)
    s:SetScript("OnScrollRangeChanged", UpdateThumb)
    s:SetScript("OnSizeChanged", UpdateThumb)
    return s
end

-- "Label: value  [-] [+]"  (Shift-click = 5x step)
function TT.Stepper(parent, text, get, set, min, max, step)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(250, 24)
    local l = TT.Label(row, "")
    l:SetPoint("LEFT")
    function row.Refresh() l:SetText(text .. ":  |cffffffff" .. get() .. "|r") end
    local function Change(d)
        set(math.max(min, math.min(max, get() + d)))
        row.Refresh()
    end
    local plus = TT.Button(row, "+", 22, function() Change(IsShiftKeyDown() and step * 5 or step) end)
    plus:SetPoint("RIGHT", -10, 0)
    local minus = TT.Button(row, "-", 22, function() Change(IsShiftKeyDown() and -step * 5 or -step) end)
    minus:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    return row
end

-- Button that cycles through a list of choices: { {value, text}, ... }.
-- Left-click = next, right-click = previous.
function TT.Cycle(parent, width, choices, get, set)
    local b = TT.Button(parent, "", width, nil)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function Index()
        for i, c in ipairs(choices) do if c[1] == get() then return i end end
        return 1
    end
    function b.Refresh() b:SetText(choices[Index()][2]) end
    b:SetScript("OnClick", function(self, button)
        local step = button == "RightButton" and -1 or 1
        set(choices[(Index() - 1 + step) % #choices + 1][1])
        self.Refresh()
    end)
    return b
end

-- Editable list of numeric IDs (spells, sound files, ...): box + Add, rows with X.
-- list = the saved table; describe(id) returns a label for the row.
function TT.IDList(parent, width, height, list, describe, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    local box = TT.EditBox(f, 120, 22)
    box:SetPoint("TOPLEFT")
    box:SetNumeric(true)
    local add = TT.Button(f, "Add", 50, nil)
    add:SetPoint("LEFT", box, "RIGHT", 6, 0)
    local scroll = TT.Scroll(f)
    scroll:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
    scroll:SetSize(width - 12, height - 34)
    local bg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", scroll, -4, 4); bg:SetPoint("BOTTOMRIGHT", scroll, 10, -4)
    bg:SetFrameLevel(scroll:GetFrameLevel() - 1)
    TT.Flat(bg, { 0.03, 0.03, 0.04, 1 })
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width - 12, 1)
    scroll:SetScrollChild(content)
    local rows = {}
    function f.Refresh()
        for i, id in ipairs(list) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(width - 16, 20)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
                row.text = TT.Label(row, "", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 4, 0)
                row.del = TT.Button(row, "X", 20, nil)
                row.del:SetPoint("RIGHT")
                rows[i] = row
            end
            row.text:SetText(describe(id))
            row.del:SetScript("OnClick", function()
                table.remove(list, i); f.Refresh(); if onChange then onChange() end
            end)
            row:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, #list * 22))
    end
    local function DoAdd()
        local id = tonumber(box:GetText())
        box:SetText(""); box:ClearFocus()
        if not id then return end
        for _, v in ipairs(list) do if v == id then return end end
        list[#list + 1] = id
        f.Refresh()
        if onChange then onChange() end
    end
    add:SetScript("OnClick", DoAdd)
    box:SetScript("OnEnterPressed", DoAdd)
    return f
end

-- Window: flat panel, thin accent line on top, title on the left, "x" to close.
function TT.Window(name, w, h, title, parent)
    local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    TT.Flat(f, C.bg)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    if name then tinsert(UISpecialFrames, name) end          -- Esc closes it

    local line = f:CreateTexture(nil, "OVERLAY")
    line:SetPoint("TOPLEFT", 1, -1); line:SetPoint("TOPRIGHT", -1, -1)
    line:SetHeight(2)
    line:SetColorTexture(unpack(C.accent))

    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -9)
    t:SetTextColor(unpack(C.text))
    t:SetText(title and title:upper() or "")
    f.TitleText = t

    local sep = f:CreateTexture(nil, "OVERLAY")
    sep:SetPoint("TOPLEFT", 1, -26); sep:SetPoint("TOPRIGHT", -1, -26)
    sep:SetHeight(1)
    sep:SetColorTexture(unpack(C.border))

    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -2)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("x")
    x:SetTextColor(unpack(C.dim))
    close:SetScript("OnEnter", function() x:SetTextColor(1, 0.35, 0.35) end)
    close:SetScript("OnLeave", function() x:SetTextColor(unpack(C.dim)) end)
    close:SetScript("OnClick", function() f:Hide() end)
    return f
end

-- Sidebar entry: text with an accent bar when selected.
function TT.NavButton(parent, text, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 24)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0)
    local bar = b:CreateTexture(nil, "OVERLAY")
    bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT"); bar:SetWidth(2)
    bar:SetColorTexture(unpack(C.accent))
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 12, 0)
    fs:SetText(text)
    function b:SetSelected(on)
        self.selected = on
        bar:SetShown(on)
        bg:SetColorTexture(1, 1, 1, on and 0.06 or 0)
        fs:SetTextColor(unpack(on and C.text or C.dim))
    end
    b:SetScript("OnEnter", function(self) if not self.selected then fs:SetTextColor(unpack(C.text)) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then fs:SetTextColor(unpack(C.dim)) end end)
    b:SetSelected(false)
    return b
end

---------------------------------------------------------------------------
-- Hub window: sidebar grouped by category, one page per module
---------------------------------------------------------------------------
TT.CATEGORIES = { "Interface", "Reskin", "Quality of Life", "System", "Tools", "Fun", "Other" }

local hub = TT.Window("TrikksTweaksHub", 800, 560, "Trikks Tweaks")
hub:SetFrameStrata("DIALOG")
TT.hub = hub

local sidebar = CreateFrame("Frame", nil, hub)
sidebar:SetPoint("TOPLEFT", 1, -27); sidebar:SetPoint("BOTTOMLEFT", 1, 1); sidebar:SetWidth(170)
local sbg = sidebar:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints(); sbg:SetColorTexture(1, 1, 1, 0.02)
local sline = sidebar:CreateTexture(nil, "BORDER")
sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT"); sline:SetWidth(1)
sline:SetColorTexture(unpack(TT.C.border))

local content = CreateFrame("Frame", nil, hub)
content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 16, -14)
content:SetPoint("BOTTOMRIGHT", -12, 10)

local pages, navButtons, currentPage = {}, {}, nil

local function ShowPage(key)
    for k, p in pairs(pages) do p:SetShown(k == key) end
    for k, b in pairs(navButtons) do b:SetSelected(k == key) end
    currentPage = key
    if pages[key] and pages[key].OnPageShow then xpcall(pages[key].OnPageShow, geterrorhandler(), pages[key]) end
    if pages[key] and pages[key].FitBody then C_Timer.After(0, pages[key].FitBody) end
end
TT.ShowPage = function(_, key) hub:Show(); ShowPage(key) end

-- modules of one category, in the order their files load
local function ModulesIn(cat)
    local list = {}
    for _, key in ipairs(TT.order) do
        if (TT.modules[key].category or "Other") == cat then list[#list + 1] = key end
    end
    return list
end

-- small grey category title
local function Header(parent, text)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetText(text:upper())
    h:SetTextColor(unpack(TT.C.dim))
    return h
end

local homeRows = {}
local function BuildHome()
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()
    local t = TT.Label(p, "Modules", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT")
    local sub = TT.Label(p, "Tick a module to turn it on. Settings are saved per account.", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)

    -- the list can be longer than the window: scroll it
    local scroll = TT.Scroll(p)
    scroll:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
    scroll:SetPoint("BOTTOMRIGHT", -10, 34)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(580, 1)
    scroll:SetScrollChild(list)

    local y = 0
    for _, cat in ipairs(TT.CATEGORIES) do
        local keys = ModulesIn(cat)
        if #keys > 0 then
            local h = Header(list, cat)
            h:SetPoint("TOPLEFT", 2, -y)
            y = y + 18
            for _, key in ipairs(keys) do
                local m = TT.modules[key]
                local row = CreateFrame("Frame", nil, list)
                row:SetSize(570, 42)
                row:SetPoint("TOPLEFT", 0, -y)
                TT.Flat(row, { 1, 1, 1, 0.025 })
                row.cb = TT.Check(row, m.title, function(v) TT:SetEnabled(key, v) end)
                row.cb:SetPoint("TOPLEFT", 10, -8)
                local d = TT.Label(row, m.desc, "GameFontDisableSmall")
                d:SetPoint("TOPLEFT", 32, -25); d:SetWidth(440); d:SetWordWrap(false)
                if m.BuildSettings then
                    local sb = TT.Button(row, "Settings", 76, function() ShowPage(key) end)
                    sb:SetPoint("RIGHT", -8, 0)
                end
                homeRows[key] = row
                y = y + 46
            end
            y = y + 10
        end
    end
    list:SetHeight(y)

    local note = TT.Label(p, "Something stuck after turning a module off? Reload.", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 0, 6)
    local rl = TT.Button(p, "Reload UI", 100, function() C_UI.Reload() end)
    rl:SetPoint("BOTTOMRIGHT", 0, 0)
    -- the minimap button itself lives in MinimapButton.lua
    p.minimapCB = TT.Check(p, "Minimap button", function(v)
        if TT.SetMinimapButtonShown then TT.SetMinimapButtonShown(v) end
    end)
    p.minimapCB:SetPoint("RIGHT", rl, "LEFT", -110, 0)
    return p
end

function TT:RefreshHub()
    for key, row in pairs(homeRows) do row.cb:SetChecked(self.modules[key].enabled) end
    if pages.home and pages.home.minimapCB and TT.MinimapButtonShown then
        pages.home.minimapCB:SetChecked(TT.MinimapButtonShown())
    end
    for key, p in pairs(pages) do
        local m = self.modules[key]
        if m and p.disabledNote then p.disabledNote:SetShown(not m.enabled) end
        if m and p.enabledCB then p.enabledCB:SetChecked(m.enabled) end
    end
end

-- Module pages are built the first time the hub opens.
local function BuildModulePage(key)
    local m = TT.modules[key]
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()
    local t = TT.Label(p, m.title, "GameFontNormalLarge")
    t:SetPoint("TOPLEFT")
    -- on/off switch for this module, right on its own page (same as on the Modules page)
    p.enabledCB = TT.Check(p, "Enabled", function(v) TT:SetEnabled(key, v) end)
    p.enabledCB:SetPoint("TOPRIGHT", -60, -2)
    p.disabledNote = TT.Label(p, "(off)", "GameFontRedSmall")
    p.disabledNote:SetPoint("LEFT", t, "RIGHT", 10, 0)
    -- the page body scrolls, so a module can have as many settings as it needs
    local scroll = TT.Scroll(p)
    scroll:SetPoint("TOPLEFT", 0, -30); scroll:SetPoint("BOTTOMRIGHT", -10, 0)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(590, 400)
    scroll:SetScrollChild(body)
    -- after the page is drawn, measure how far down its content goes
    p.FitBody = function()
        local top, low = body:GetTop(), nil
        if not top then return end
        local function Check(obj)
            local b = obj:IsShown() and obj:GetBottom()
            if b and (not low or b < low) then low = b end
        end
        for _, c in ipairs({ body:GetChildren() }) do Check(c) end
        for _, r in ipairs({ body:GetRegions() }) do Check(r) end
        body:SetHeight(math.max(scroll:GetHeight(), low and (top - low + 12) or 400))
    end
    if not TT.SafeCall(m, "BuildSettings", body, p) then
        local err = TT.Label(body, "This page failed to load (see the error message).", "GameFontRedSmall")
        err:SetPoint("TOPLEFT")
    end
    return p
end

local function BuildSidebar()
    -- the list of pages can be taller than the window: make it scroll
    local scroll = TT.Scroll(sidebar)
    scroll:SetPoint("TOPLEFT"); scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(169, 1)
    scroll:SetScrollChild(list)
    local y = 8
    local function Nav(key, text)
        local b = TT.NavButton(list, text, 160)
        b:SetScript("OnClick", function() ShowPage(key) end)
        b:SetPoint("TOPLEFT", 0, -y)
        navButtons[key] = b
        y = y + 24
    end
    Nav("home", "Modules")
    y = y + 8
    for _, cat in ipairs(TT.CATEGORIES) do
        local keys = {}
        for _, key in ipairs(ModulesIn(cat)) do
            if TT.modules[key].BuildSettings then keys[#keys + 1] = key end
        end
        if #keys > 0 then
            local h = Header(list, cat)
            h:SetPoint("TOPLEFT", 12, -y - 4)
            y = y + 20
            for _, key in ipairs(keys) do
                pages[key] = BuildModulePage(key)
                Nav(key, TT.modules[key].title)
            end
            y = y + 8
        end
    end
    list:SetHeight(y)
end

hub:SetScript("OnShow", function()
    if not pages.home then
        pages.home = BuildHome()
        BuildSidebar()
    end
    TT:RefreshHub()
    ShowPage(currentPage or "home")
end)

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
-- Give a module its saved settings and start it. Runs when the addon that
-- owns the module has loaded (its saved variables are available from then on).
local function InitModule(m)
    local sv = _G[m.svName] or {}
    _G[m.svName] = sv
    sv.modules = sv.modules or {}
    local db = sv.modules[m.key]
    -- a module that moved to another addon brings its old settings along once
    if not db and m.svName ~= "TrikksTweaksDB" and TrikksTweaksDB and TrikksTweaksDB.modules
       and TrikksTweaksDB.modules[m.key] then
        db = TrikksTweaksDB.modules[m.key]
        TrikksTweaksDB.modules[m.key] = nil
    end
    db = db or {}
    sv.modules[m.key] = db
    -- opt-in: a module is off until you turn it on (a saved choice is kept)
    if db.enabled == nil then db.enabled = false end
    CopyDefaults(m.defaults or {}, db)
    m.db, m.enabled = db, db.enabled
    TT.SafeCall(m, "OnLoad")
    if m.enabled then TT.SafeCall(m, "OnEnable") end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    for _, key in ipairs(TT.order) do
        local m = TT.modules[key]
        if m.addon == name and not m.db then InitModule(m) end
    end
    if name ~= ADDON then return end

    -- Entry in Esc > Options > AddOns that opens the hub
    local panel = CreateFrame("Frame")
    panel.name = "Trikks Tweaks"
    local lt = TT.Label(panel, "Trikks Tweaks", "GameFontNormalLarge"); lt:SetPoint("TOPLEFT", 16, -16)
    local ob = TT.Button(panel, "Open Trikks Tweaks", 180, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        hub:Show()
    end)
    ob:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 0, -12)
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, panel.name))
end)

-- (not /tt: WoW already uses that for "tell target")
SLASH_TRIKKSTWEAKS1, SLASH_TRIKKSTWEAKS2 = "/trikks", "/tweaks"
SlashCmdList.TRIKKSTWEAKS = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
    if cmd and cmd:lower() == "dump" then TT.Dump(arg)       -- developer tool (Inspector.lua)
    elseif cmd and cmd:lower() == "minimap" then               -- /trikks minimap: show / hide the button
        TT.SetMinimapButtonShown(not TT.MinimapButtonShown())
    else hub:SetShown(not hub:IsShown()) end
end
