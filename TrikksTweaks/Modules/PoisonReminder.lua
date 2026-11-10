-- Module: Poison Reminder (rogues)
-- An icon per weapon (main hand, off hand) when its poison is missing or
-- about to run out, out of combat. Each icon holds up to four poisons:
-- click, Shift-click, Ctrl-click and Alt-click each put a poison of your choice
-- on that weapon.
--
-- How: Blizzard's secure buttons read their settings with modifier versions
-- ("shift-item1", "ctrl-target-slot1", ...), so one icon can do four things.
-- A poison is an item you use on a weapon: type "item" + "target-slot" 16 / 17.
-- The highest rank in your bags is used ("Deadly Poison" finds "Deadly Poison
-- III"). On clients where poisons are spells you know, the spell is cast.
-- Secure settings only change out of combat, the only time the icons show.
local _, TT = ...
local IsSecret = TT.IsSecret
local _, CLASS = UnitClass("player")

local POISONS = { "Instant Poison", "Deadly Poison", "Wound Poison", "Crippling Poison", "Mind-numbing Poison",
                  "Amplifying Poison", "Numbing Poison", "Atrophic Poison" }
local MODS = { { "", "Click" }, { "shift-", "Shift-click" }, { "ctrl-", "Ctrl-click" }, { "alt-", "Alt-click" } }
local SLOTS = { { key = "mh", slot = 16, label = "Main hand" }, { key = "oh", slot = 17, label = "Off hand" } }

local M = TT:RegisterModule("PoisonReminder", {
    title = "Poison Reminder",
    category = "Quality of Life",
    desc = "Rogues: an icon per weapon when its poison runs out; click, Shift-, Ctrl- or Alt-click to apply the poison you chose.",
    defaults = {
        minLeft = 5, size = 40, spacing = 6, always = false, hideResting = false, sound = false,
        layouts = {},
        -- per weapon, per click: a poison name ("" = nothing)
        mh = { [""] = "Instant Poison", ["shift-"] = "Deadly Poison", ["ctrl-"] = "", ["alt-"] = "" },
        oh = { [""] = "Deadly Poison", ["shift-"] = "Instant Poison", ["ctrl-"] = "", ["alt-"] = "" },
    },
})

local DEFAULT_POS = { point = "CENTER", x = 0, y = 170 }
local container, inEditMode, currentLayout = nil, false, nil
local icons = {}

---------------------------------------------------------------------------
-- Poisons you have
---------------------------------------------------------------------------
-- is this poison a spell you know? Asked once per name and kept (the icons
-- are re-checked every second); forgotten again when your spells change.
local knownCache = {}
local function Known(name)
    local v = knownCache[name]
    if v == nil then
        v = false
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
        local id = info and info.spellID
        if id and not IsSecret(id) then
            if (IsPlayerSpell and IsPlayerSpell(id))
               or (IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(id)) then v = id end
        end
        knownCache[name] = v
    end
    return v or nil
end

-- base name -> best item name in your bags (highest required level = highest rank)
local bagBest = {}
local function ScanBags()
    wipe(knownCache)                 -- runs on login, new spells and bag changes: a good moment to ask again
    wipe(bagBest)
    local bestLevel = {}
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local name = info and info.itemID and C_Item.GetItemNameByID(info.itemID)
            if name and not IsSecret(name) then
                for _, base in ipairs(POISONS) do
                    if name:sub(1, #base) == base then
                        local lvl = select(5, C_Item.GetItemInfo(info.itemID)) or 0
                        if not bagBest[base] or lvl > (bestLevel[base] or -1) then
                            bagBest[base], bestLevel[base] = name, lvl
                        end
                        break
                    end
                end
            end
        end
    end
end

-- what a click does for this poison: "spell", name / "item", name / nil
local function Action(base)
    if not base or base == "" then return nil end
    if Known(base) then return "spell", base end
    if bagBest[base] then return "item", bagBest[base] end
    return nil
end

local function OffhandWeapon()
    if C_PaperDollInfo and C_PaperDollInfo.OffhandHasWeapon then return C_PaperDollInfo.OffhandHasWeapon() end
    local id = GetInventoryItemID("player", 17)
    if not id then return false end
    return select(6, C_Item.GetItemInfoInstant(id)) == 2
end

-- seconds left on the poison of a weapon slot (nil = none, math.huge = no weapon)
local function TimeLeft(slot)
    if not GetInventoryItemID("player", slot) then return math.huge end
    local hasMain, mainMs, _, _, hasOff, offMs = GetWeaponEnchantInfo()
    if slot == 16 then return hasMain and (mainMs or 0) / 1000 or nil end
    return hasOff and (offMs or 0) / 1000 or nil
end

local function Icon(base)
    local kind, name = Action(base)
    if kind == "spell" then
        local info = C_Spell.GetSpellInfo(name)
        return info and info.iconID
    elseif kind == "item" then
        local id = C_Item.GetItemInfoInstant(name)
        return id and C_Item.GetItemIconByID(id)
    end
end

---------------------------------------------------------------------------
-- The icons
---------------------------------------------------------------------------
local function FormatTime(s)
    if s >= 60 then return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60)) end
    return string.format("%ds", math.floor(s))
end

local function OnEnter(self)
    local w = self.weapon
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(w.label .. " poison", 1, 1, 1)
    for _, m in ipairs(MODS) do
        local base = M.db[w.key][m[1]]
        if base and base ~= "" then
            local kind, name = Action(base)
            if kind then GameTooltip:AddDoubleLine(m[2], name, 0.7, 0.7, 0.7, 1, 1, 1)
            else GameTooltip:AddDoubleLine(m[2], base .. " (none in bags)", 0.7, 0.7, 0.7, 1, 0.35, 0.35) end
        end
    end
    GameTooltip:Show()
end

local function GetIcon(i)
    if icons[i] then return icons[i] end
    local b = CreateFrame("Button", "TrikksTweaksPoison" .. i, container, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon); hl:SetColorTexture(1, 1, 1, 0.15)
    b.tag = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.tag:SetPoint("TOPLEFT", 3, -2)
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.time:SetPoint("TOP", b, "BOTTOM", 0, -2)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    icons[i] = b
    return b
end

-- the four clicks of one icon (secure settings: out of combat only).
-- Only set again when one of them changed: this is called every second, and
-- each setting is a call into the game's secure code (20 per icon).
local function Bind(b, w)
    local sig = tostring(w.slot)
    for _, m in ipairs(MODS) do
        local kind, name = Action(M.db[w.key][m[1]])
        sig = sig .. "|" .. (kind or "-") .. ":" .. (name or "")
    end
    if b.sig == sig then return end
    b.sig = sig
    for _, m in ipairs(MODS) do
        local p = m[1]
        local kind, name = Action(M.db[w.key][p])
        b:SetAttribute(p .. "type1", kind)
        b:SetAttribute(p .. "spell1", kind == "spell" and name or nil)
        b:SetAttribute(p .. "item1", kind == "item" and name or nil)
        b:SetAttribute(p .. "target-slot1", kind == "item" and w.slot or nil)
        b:SetAttribute(p .. "unit1", kind == "spell" and "player" or nil)
    end
end

local shownBefore = 0
local function Update()
    if not container or InCombatLockdown() then return end
    local db = M.db
    local preview = inEditMode
    local show = {}
    local allowed = M.enabled and CLASS == "ROGUE" and not UnitIsDeadOrGhost("player") and not UnitOnTaxi("player")
        and not (UnitInVehicle and UnitInVehicle("player")) and not (db.hideResting and IsResting())
    if allowed or preview then
        for _, w in ipairs(SLOTS) do
            if w.slot == 16 or OffhandWeapon() or preview then
                local left = TimeLeft(w.slot)
                local low = not left or left < db.minLeft * 60
                if left ~= math.huge and (low or db.always or preview) then
                    show[#show + 1] = { w = w, left = left and left < math.huge and left or nil, low = low }
                end
            end
        end
    end
    local n, size, gap = #show, db.size, db.spacing
    local total = n * size + math.max(0, n - 1) * gap
    local layout = n .. ":" .. size .. ":" .. gap          -- sizes and places: only when they changed
    if container.layout ~= layout then
        container.layout = layout
        container:SetSize(math.max(size, total), size)
    end
    for i, d in ipairs(show) do
        local b = GetIcon(i)
        b.weapon = d.w
        if b.layout ~= layout then
            b.layout = layout
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("CENTER", container, "CENTER", -total / 2 + size / 2 + (i - 1) * (size + gap), 0)
        end
        b.icon:SetTexture(Icon(db[d.w.key][""]) or GetInventoryItemTexture("player", d.w.slot) or 134400)
        b.icon:SetDesaturated(not d.low)                        -- "always show": grey while it's fine
        b.tag:SetText(d.w.slot == 16 and "MH" or "OH")
        b.time:SetText(d.left and FormatTime(d.left) or (d.low and "|cffff5555none|r" or ""))
        Bind(b, d.w)
        if not b:IsShown() then b:Show() end
    end
    for i = n + 1, #icons do
        if icons[i]:IsShown() then icons[i]:Hide() end
    end
    local lowCount = 0
    for _, d in ipairs(show) do if d.low then lowCount = lowCount + 1 end end
    if db.sound and not preview and lowCount > shownBefore then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
    if not preview then shownBefore = lowCount end
end

---------------------------------------------------------------------------
-- Edit Mode, events
---------------------------------------------------------------------------
local function Position()
    if not container then return end
    local p = currentLayout and M.db.layouts[currentLayout] or DEFAULT_POS
    container:ClearAllPoints()
    container:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

local registered = false
local function RegisterEditMode()
    local LEM = LibStub and LibStub("LibEditMode", true)
    if registered or not LEM then return end
    registered = true
    LEM:AddFrame(container, function(frame, layoutName)
        local cx, cy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local es, ues = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local x, y = (cx * es - ux * ues) / es, (cy * es - uy * ues) / es
        M.db.layouts[layoutName] = { point = "CENTER", x = x, y = y }
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end, DEFAULT_POS, "Poison Reminder")
    LEM:RegisterCallback("layout", function(layoutName) currentLayout = layoutName; Position() end)
    LEM:RegisterCallback("enter", function() inEditMode = true; Update() end)
    LEM:RegisterCallback("exit", function() inEditMode = false; Update() end)
    LEM:RegisterCallback("rename", function(old, new)
        M.db.layouts[new], M.db.layouts[old] = M.db.layouts[old], nil
        if currentLayout == old then currentLayout = new end
    end)
    LEM:RegisterCallback("delete", function(name) M.db.layouts[name] = nil end)
    local ok, name = pcall(LEM.GetActiveLayoutName, LEM)
    if ok and name then currentLayout = name end
end

local ev, ticker, pendingApply = nil, nil, false
local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED",
                 "PLAYER_EQUIPMENT_CHANGED", "PLAYER_UPDATE_RESTING", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
                 "PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED" }

local function Apply()
    if not container then return end
    local on = M.enabled and CLASS == "ROGUE"
    for _, e in ipairs(EVENTS) do
        if on then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
    end
    if on and not ticker then ticker = C_Timer.NewTicker(1, Update)
    elseif not on and ticker then ticker:Cancel(); ticker = nil end
    if InCombatLockdown() then pendingApply = true; return end
    pendingApply = false
    if on then
        RegisterEditMode()
        RegisterStateDriver(container, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(container, "visibility")
        container:Hide()
    end
    ScanBags()
    Position()
    Update()
end

function M:Setup()
    container = CreateFrame("Frame", "TrikksTweaksPoisonReminder", UIParent)
    container:SetSize(40, 40)
    container:SetClampedToScreen(true)
    container:Hide()
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and pendingApply then Apply() end
        if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then ScanBags() end
        C_Timer.After(0.2, Update)
    end)
end

function M:OnEnable() Apply() end
function M:OnDisable() Apply() end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function M:BuildSettings(body, page)
    local db, refreshers, y = M.db, {}, 0
    if CLASS ~= "ROGUE" then
        local l = TT.Label(body, "This one is for rogues: it does nothing on this character.", "GameFontRedSmall")
        l:SetPoint("TOPLEFT", 0, -y); y = y + 24
    end
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(TT.C.dim)); h:SetPoint("TOPLEFT", 0, -y); y = y + 20
    end
    -- choices for a click: (nothing) + every poison; poisons you don't carry are grey.
    -- One list shared by all the buttons, updated in place when the page opens.
    local choices = { { "", "|cff888888(nothing)|r" } }
    for _, base in ipairs(POISONS) do choices[#choices + 1] = { base, base } end
    local function Shade()
        ScanBags()
        for i = 2, #choices do
            local base = choices[i][1]
            choices[i][2] = Action(base) and base or ("|cff777777" .. base .. "|r")
        end
    end

    Head("What each click puts on the weapon")
    for _, w in ipairs(SLOTS) do
        local l = TT.Label(body, w.label, "GameFontNormal")
        l:SetPoint("TOPLEFT", 2, -y); y = y + 22
        for i, m in ipairs(MODS) do
            local col = (i - 1) % 2
            local ml = TT.Label(body, m[2], "GameFontHighlightSmall")
            ml:SetPoint("TOPLEFT", 12 + col * 290, -y - 4)
            local c = TT.Cycle(body, 170, choices, function() return db[w.key][m[1]] or "" end,
                function(v) db[w.key][m[1]] = v; if M.enabled then Update() end end)
            c:SetPoint("TOPLEFT", 100 + col * 290, -y)
            refreshers[#refreshers + 1] = c.Refresh
            if col == 1 then y = y + 26 end
        end
        y = y + 6
    end
    local lgrey = TT.Label(body, "Grey = none in your bags right now. The highest rank you carry is used.", "GameFontDisableSmall")
    lgrey:SetPoint("TOPLEFT", 2, -y); y = y + 24

    Head("When it shows")
    local function DbCheck(key, text)
        local cb = TT.Check(body, text, function(v) db[key] = v; if M.enabled then Update() end end)
        cb:SetPoint("TOPLEFT", 2, -y); y = y + 24
        refreshers[#refreshers + 1] = function() cb:SetChecked(db[key]) end
    end
    DbCheck("always", "Always show the icons (grey while the poison is fine): a quick re-apply bar")
    DbCheck("hideResting", "Hide while resting (cities, inns)")
    DbCheck("sound", "Play a sound when a poison runs out")
    local function Step(text, key, min, max, step)
        local s = TT.Stepper(body, text, function() return db[key] end,
            function(v) db[key] = v; if M.enabled then Update() end end, min, max, step)
        s:SetPoint("TOPLEFT", 0, -y); y = y + 26
        refreshers[#refreshers + 1] = s.Refresh
    end
    Step("Remind at less than (min)", "minLeft", 0, 30, 1)
    Step("Icon size", "size", 24, 80, 2)
    Step("Spacing", "spacing", 0, 30, 1)
    local help = TT.Label(body,
        "Never shown in combat. Move the icons in Edit Mode (\"Poison Reminder\"). The off-hand\n" ..
        "icon only shows with a weapon in your off hand.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 6)

    page.OnPageShow = function()
        Shade()                    -- grey / white depends on what's in your bags now
        for _, f in ipairs(refreshers) do f() end
    end
end
