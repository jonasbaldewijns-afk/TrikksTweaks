-- Module: Minimap
-- Square minimap with a thin border, mouse-wheel zoom, a small stats line
-- (location, FPS, latency, time, durability) and a "button bin" that collects
-- addon minimap buttons into one flyout.
local _, TT = ...
local M = TT:RegisterModule("Minimap", {
    title = "Minimap",
    category = "Interface",
    desc = "Square minimap, stats line (location, FPS, ping, time, durability) and an addon button bin.",
    defaults = {
        square = true, wheelZoom = true,
        stats = true, location = true, fps = false, latency = true, time = true, hour24 = true, durability = false,
        coords = true, clockInside = true,
        -- which side of the second row each stat sits on
        side = { fps = "LEFT", latency = "LEFT", coords = "RIGHT", durability = "RIGHT" },
        bin = true,
        -- where each minimap element goes: a corner of the map, "HIDDEN", or
        -- "BLIZZARD" (leave it where Blizzard puts it). Mouseover = only show
        -- while the mouse is over the map.
        hideZone = true,
        moveUp = true,
        corner = true,       -- square map: flush in the top-right corner of its Edit Mode box
        elements = {
            tracking   = { pos = "TOPLEFT",     mouseover = true },
            difficulty = { pos = "TOPLEFT",     mouseover = true },
            calendar   = { pos = "TOPRIGHT",    mouseover = true },
            addons     = { pos = "TOPRIGHT",    mouseover = true },
            clock      = { pos = "HIDDEN",      mouseover = true },
            mail       = { pos = "BOTTOMLEFT",  mouseover = true },
            diel       = { pos = "BOTTOMLEFT",  mouseover = true },
            bin        = { pos = "BOTTOMRIGHT", mouseover = true },
        },
    },
})
local WHITE = "Interface\\Buttons\\WHITE8x8"

StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] = StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] or {
    text = "%s\n\nReload your UI now?",
    button1 = RELOADUI or "Reload", button2 = LATER or "Later",
    OnAccept = function() C_UI.Reload() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Square shape
---------------------------------------------------------------------------
local function Hide(obj) if obj then obj:SetAlpha(0); if obj.EnableMouse and obj ~= Minimap then obj:EnableMouse(false) end end end

local border
local function MakeSquare()
    -- The minimap is drawn through a mask; a plain white square mask = square map.
    Minimap:SetMaskTexture(WHITE)
    -- Round border art (retail-style and classic-style names; missing ones are skipped)
    Hide(MinimapCompassTexture); Hide(MinimapBorder); Hide(MinimapBorderTop)
    -- The quest / archaeology "blob" rings are drawn as circles: switch them off.
    for _, fn in ipairs({ "SetArchBlobRingScalar", "SetArchBlobRingAlpha", "SetQuestBlobRingScalar",
                          "SetQuestBlobRingAlpha", "SetTaskBlobRingScalar", "SetTaskBlobRingAlpha" }) do
        if Minimap[fn] then Minimap[fn](Minimap, 0) end
    end
    -- Addons (LibDBIcon) ask this global where to place their buttons around the map.
    function GetMinimapShape() return "SQUARE" end

    border = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    border:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)
end

local function SetupZoom()
    for _, z in ipairs({ Minimap.ZoomIn, Minimap.ZoomOut, MinimapZoomIn, MinimapZoomOut }) do
        if z then z:Hide(); z:SetAlpha(0) end
    end
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(self, delta)
        local zoom = self:GetZoom() + (delta > 0 and 1 or -1)
        self:SetZoom(math.max(0, math.min(self:GetZoomLevels() - 1, zoom)))
    end)
end

---------------------------------------------------------------------------
-- Stats line
---------------------------------------------------------------------------
-- Two rows under the map:
--   row 1:            time (centred)
--   row 2:  [left group]          [right group]
-- each stat on row 2 can go in the left or the right group.
-- All frames of this module are made in Setup (BuildFrames, near the end),
-- the first time the module is switched on.
local stats, timeText, leftText, rightText
local locFrame, locText         -- the location text inside the map

-- Place the rows; when the clock is off, row 2 moves up.
local function LayoutStats()
    local inside = M.db.clockInside
    local row2 = (M.db.time and not inside) and -14 or 0
    timeText:ClearAllPoints()
    if inside then
        -- inside the map, bottom centre (drawn above the map, with a shadow to stay readable)
        timeText:SetParent(locFrame)
        timeText:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 5)
        timeText:SetShadowOffset(1, -1)
    else
        timeText:SetParent(stats)
        timeText:SetPoint("TOP", stats, "TOP", 0, 0)
    end
    leftText:ClearAllPoints(); leftText:SetPoint("TOPLEFT", stats, "TOPLEFT", 0, row2)
    rightText:ClearAllPoints(); rightText:SetPoint("TOPRIGHT", stats, "TOPRIGHT", 0, row2)
    stats:SetHeight(row2 == 0 and 14 or 28)
end

-- Your position on the zone map, 0-100 like most coordinate addons.
local function Coords()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos or TT.IsSecret(pos) then return end
    local x, y = pos:GetXY()
    if not x or TT.IsSecret(x) or (x == 0 and y == 0) then return end
    return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- The Forever client shows its own coordinates on the minimap; hide them while ours show.
local function BlizzardCoords()
    return MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.PlayerCoords
end


local PVP_COLORS = {
    sanctuary = "68ccef", friendly = "33ff33", hostile = "ff3333",
    contested = "ffb300", arena = "ff3333", combat = "ff3333",
}

local function Durability()
    local low
    for slot = 1, 19 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not low or pct < low then low = pct end
        end
    end
    return low
end

local function Color(value, good, bad)       -- green -> yellow -> red
    if value <= good then return "33ff99" elseif value <= bad then return "ffd100" else return "ff5555" end
end

-- Durability only changes on these events, so it's worked out then instead of
-- scanning 19 gear slots 4 times a second.
local durability, durabilityDirty = nil, true

local STAT_KEYS = { "fps", "latency", "coords", "durability" }
local values, left, right = {}, {}, {}        -- reused every update (no new tables 4x a second)

local function UpdateStats()
    local db = M.db
    wipe(values); wipe(left); wipe(right)
    if db.fps then
        local fps = math.floor(GetFramerate() + 0.5)
        values.fps = "|cff" .. (fps >= 50 and "33ff99" or fps >= 25 and "ffd100" or "ff5555") .. fps .. "|r fps"
    end
    if db.latency then
        local _, _, home, world = GetNetStats()
        local ms = math.max(home or 0, world or 0)
        values.latency = "|cff" .. Color(ms, 100, 250) .. ms .. "|r ms"
    end
    if db.coords then values.coords = Coords() end
    if db.durability then
        if durabilityDirty then durability, durabilityDirty = Durability(), false end
        local d = durability
        values.durability = d and ("|cff" .. (d >= 50 and "33ff99" or d >= 20 and "ffd100" or "ff5555") .. math.floor(d) .. "%|r") or nil
    end
    for _, key in ipairs(STAT_KEYS) do
        if values[key] then
            local group = (db.side[key] == "RIGHT") and right or left
            group[#group + 1] = values[key]
        end
    end
    leftText:SetText(table.concat(left, "  "))
    rightText:SetText(table.concat(right, "  "))
    timeText:SetText(db.time and date(db.hour24 and "%H:%M" or "%I:%M %p") or "")

    if db.location then
        local zone = GetMinimapZoneText() or ""
        local pvp = GetZonePVPInfo and GetZonePVPInfo()
        locText:SetText("|cff" .. (PVP_COLORS[pvp or ""] or "ffffff") .. zone .. "|r")
    else
        locText:SetText("")
    end
end

local ticker
local function ApplyStats()
    local on = M.enabled and M.db.stats
    stats:SetShown(on and (M.db.fps or M.db.latency or M.db.time or M.db.durability or M.db.coords))
    LayoutStats()
    local bc = BlizzardCoords()
    if bc then bc:SetAlpha((on and M.db.coords) and 0 or 1) end
    locFrame:SetShown(on and (M.db.location or (M.db.time and M.db.clockInside)))
    local needed = stats:IsShown() or locFrame:IsShown()  -- no ticker when nothing is shown
    if needed and not ticker then
        ticker = C_Timer.NewTicker(0.25, UpdateStats)     -- 4x a second so coordinates feel live
        UpdateStats()
    elseif not needed and ticker then
        ticker:Cancel(); ticker = nil
    end
end

---------------------------------------------------------------------------
-- Button bin: addon minimap buttons -> one flyout
---------------------------------------------------------------------------
local binBtn, bin

local binned, laying = {}, false
-- Blizzard's own minimap buttons are left alone.
local IGNORE = { MiniMapTracking = true, GameTimeFrame = true, MinimapZoomIn = true, MinimapZoomOut = true,
                 QueueStatusButton = true, MiniMapMailFrame = true, TimeManagerClockButton = true,
                 ExpansionLandingPageMinimapButton = true, AddonCompartmentFrame = true }

local binOrder = {}                  -- reused: the buttons to show, sorted by name
local function ByName(a, b) return (a:GetName() or "") < (b:GetName() or "") end
local function Layout()
    laying = true
    local size, gap, perRow = 30, 4, 5
    -- always the same order (a set has none: the buttons used to shuffle)
    wipe(binOrder)
    for btn in pairs(binned) do
        if btn:IsShown() or btn.ttWasShown then binOrder[#binOrder + 1] = btn end
    end
    table.sort(binOrder, ByName)
    local i = 0
    for _, btn in ipairs(binOrder) do
        local row, col = math.floor(i / perRow), i % perRow
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bin, "TOPLEFT", 6 + col * (size + gap), -6 - row * (size + gap))
        btn:SetAlpha(1)
        i = i + 1
    end
    local cols = math.max(1, math.min(i, perRow))
    local rows = math.max(1, math.ceil(i / perRow))
    bin:SetSize(12 + cols * size + (cols - 1) * gap, 12 + rows * size + (rows - 1) * gap)
    laying = false
end

local function Grab(btn)
    if binned[btn] or not btn or btn == binBtn then return end
    binned[btn] = true
    btn.ttWasShown = btn:IsShown()
    -- LibDBIcon pins its buttons to the MEDIUM strata (fixed strata / level), so
    -- they'd ignore the new parent and stay behind the bin's background (DIALOG).
    -- Unpin them and put them on the bin's own layer, above its background.
    if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
    if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
    btn:SetParent(bin)
    btn:SetFrameStrata(bin:GetFrameStrata())
    btn:SetFrameLevel(bin:GetFrameLevel() + 2)
    btn:SetScript("OnDragStart", nil)        -- no dragging them back around the map
    btn:SetScript("OnDragStop", nil)
    -- LibDBIcon re-positions its buttons now and then; put them back in the grid.
    hooksecurefunc(btn, "SetPoint", function()
        if not laying then C_Timer.After(0, Layout) end
    end)
end

local function Collect()
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if lib and lib.GetButtonList then
        for _, name in ipairs(lib:GetButtonList()) do Grab(lib:GetMinimapButton(name)) end
    end
    -- older addons that make their own button on the minimap
    for _, child in ipairs({ Minimap:GetChildren() }) do
        local name = child.GetName and child:GetName()
        if name and not IGNORE[name] and child:IsObjectType("Button")
           and (name:find("^LibDBIcon10_") or name:find("MinimapButton") or name:find("Minimap_Button")) then
            Grab(child)
        end
    end
    Layout()
end


---------------------------------------------------------------------------
-- Minimap elements: put them in a corner of the map, hide them, or leave them
---------------------------------------------------------------------------
local ELEMENTS = {   -- order = order within a corner (outside -> inside)
    { key = "tracking",   label = "Tracking (magnifier)",
      get = function() return MinimapCluster and MinimapCluster.Tracking or MiniMapTracking end },
    { key = "difficulty", label = "Instance difficulty",
      get = function() return MinimapCluster and MinimapCluster.InstanceDifficulty end },
    { key = "calendar",   label = "Calendar",       get = function() return GameTimeFrame end },
    { key = "addons",     label = "Addon menu (the number)", get = function() return AddonCompartmentFrame end },
    { key = "clock",      label = "Blizzard clock", get = function() return TimeManagerClockButton end },
    { key = "mail",       label = "Mail / crafting orders",
      get = function() return MinimapCluster and MinimapCluster.IndicatorFrame or MiniMapMailFrame end },
    { key = "diel",       label = "Day / night (moon)",
      get = function() return MinimapCluster and MinimapCluster.DielFrame end },
    { key = "bin",        label = "Addon button bin (...)", get = function() return binBtn end },
}
local POSITIONS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "HIDDEN", "BLIZZARD" }
local POS_TEXT = { TOPLEFT = "Top left", TOPRIGHT = "Top right", BOTTOMLEFT = "Bottom left",
                   BOTTOMRIGHT = "Bottom right", HIDDEN = "Hidden", BLIZZARD = "Blizzard default" }

-- Hidden things are parented to a frame that's never shown (more reliable than
-- Hide(): Blizzard re-shows some of these frames by itself).
local hiddenParent

local placing, fights, fightReset = false, 0, 0
local PlaceElements, PlaceZone

-- Blizzard (or another addon) re-anchors some of these now and then: put them back.
local guarded = {}          -- kept here, not as a field on Blizzard's frames (taint)
local function Guard(f)
    if guarded[f] then return end
    guarded[f] = true
    hooksecurefunc(f, "SetPoint", function()
        if placing or not M.enabled then return end
        -- if another addon keeps moving it back, stop fighting after a while
        if GetTime() > fightReset then fights, fightReset = 0, GetTime() + 2 end
        fights = fights + 1
        if fights > 20 then return end
        C_Timer.After(0, PlaceElements)
    end)
end

local function Remember(f)
    if not f.ttOrig then f.ttOrig = { parent = f:GetParent(), points = {} } end
end

-- The zone name bar at the top. On this client it is one button
-- (MinimapCluster.ZoneTextButton) whose own texture is the dark bar; other
-- clients also have a separate BorderTop. Our location text replaces it.
--
-- It is faded out (alpha 0, no mouse) instead of being moved to a hidden
-- parent: MinimapCluster is a restricted frame on this client, and moving its
-- children away failed, which stopped everything after it (the bar stayed and
-- the map didn't move up). Fading is always allowed. Each step runs on its
-- own so one failing step can't block the others, and a failure is printed
-- once in chat (WoW's own error pop-up may be switched off).
local zoneHooked, zoneWarned = {}, {}
local function Step(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not zoneWarned[name] then
        zoneWarned[name] = true
        TT.Print("minimap zone bar (" .. name .. "): " .. tostring(err))
    end
end

local function FadeZoneFrame(f, hide)
    f:SetAlpha(hide and 0 or 1)
    if f.EnableMouse then f:EnableMouse(not hide) end
    if not zoneHooked[f] then
        zoneHooked[f] = true
        -- keep it faded if Blizzard changes its alpha or shows it again
        hooksecurefunc(f, "SetAlpha", function(self, a)
            if a ~= 0 and M.enabled and M.db.hideZone then self:SetAlpha(0) end
        end)
        f:HookScript("OnShow", function(self)
            if M.enabled and M.db.hideZone then self:SetAlpha(0) end
        end)
    end
end

local origBoxPoint
local function MoveMapUp()
    -- move the map up into the gap the bar leaves. The container sits below
    -- the bar (or above it when Edit Mode puts the header underneath); we pin
    -- its top to the top of the cluster, keeping its sideways offset.
    local box = MinimapCluster.MinimapContainer
    if not box then return end
    Guard(box)
    if M.db.hideZone and M.db.moveUp then
        if origBoxPoint == nil then
            local p, rel, rp, x, y = box:GetPoint(1)
            origBoxPoint = p and { p, rel, rp, x, y } or false
        end
        box:ClearAllPoints()
        box:SetPoint("TOP", MinimapCluster, "TOP", origBoxPoint and origBoxPoint[4] or 10, -2)
    elseif origBoxPoint then
        box:ClearAllPoints()
        box:SetPoint(unpack(origBoxPoint))
        origBoxPoint = nil
    end
end

-- Square map: pin the map itself to the top-right corner of the cluster (the
-- box Edit Mode moves). Blizzard centres the 198px map in a ~253px container
-- to leave room for the round border art; with a square map that room is
-- just empty space around it. Offset 1 so the 1px border stays inside.
local mapPinned = false
local function PinMap()
    if M.db.square and M.db.corner then
        Guard(Minimap)
        Minimap:ClearAllPoints()
        Minimap:SetPoint("TOPRIGHT", MinimapCluster, "TOPRIGHT", -1, -1)
        mapPinned = true
    elseif mapPinned then
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", MinimapCluster.MinimapContainer or Minimap:GetParent())   -- Blizzard's default
        mapPinned = false
    end
end

PlaceZone = function()
    if not MinimapCluster then return end
    local hide = M.db.hideZone and true or false
    for _, key in ipairs({ "BorderTop", "ZoneTextButton" }) do
        local f = MinimapCluster[key]
        if f then Step(key, FadeZoneFrame, f, hide) end
    end
    Step("move map up", MoveMapUp)
    Step("pin map to corner", PinMap)
end

PlaceElements = function()
    if not M.enabled then return end
    placing = true
    local used = { TOPLEFT = 0, TOPRIGHT = 0, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }
    local function PlaceOne(e)
        local f = e.get()
        local cfg = M.db.elements[e.key]
        if f and cfg and not (f.IsForbidden and f:IsForbidden()) and not (InCombatLockdown() and f:IsProtected()) then
            local pos = cfg.pos
            if e.key == "bin" and not M.db.bin then pos = "HIDDEN" end
            if pos == "HIDDEN" then
                Remember(f)
                f:SetParent(hiddenParent)
            elseif used[pos] then
                Remember(f)
                Guard(f)
                if f:GetParent() ~= Minimap then f:SetParent(Minimap) end
                f:SetFrameLevel(Minimap:GetFrameLevel() + 5)
                local w = f:GetWidth()
                local right = pos:find("RIGHT")
                local x = (right and -1 or 1) * (3 + used[pos])
                local y = pos:find("TOP") and -3 or 3
                f:ClearAllPoints()
                f:SetPoint(pos, Minimap, pos, x, y)
                used[pos] = used[pos] + (w > 0 and w or 20) + 2
            elseif f.ttOrig and f:GetParent() == hiddenParent then
                f:SetParent(f.ttOrig.parent)      -- back from hidden; Blizzard re-anchors it on reload
            end
        end
    end
    -- one element failing (a frame this client doesn't have, ...) must not stop
    -- the others or the zone bar: each gets its own protected call
    for _, e in ipairs(ELEMENTS) do
        local ok, err = pcall(PlaceOne, e)
        if not ok then geterrorhandler()("Trikks Tweaks minimap (" .. e.key .. "): " .. tostring(err)) end
    end
    local ok, err = pcall(PlaceZone)
    if not ok then geterrorhandler()("Trikks Tweaks minimap (zone bar): " .. tostring(err)) end
    placing = false
end

-- Mouseover: fade in-map elements in while the mouse is over the map.
local fader
local fadeAlpha, acc, lastX, lastY, settled = 0, 0, nil, nil, false
local GetCursorPosition = GetCursorPosition
local function FaderUpdate(_, elapsed)
    acc = acc + elapsed
    if acc < 0.03 then return end
    local dt = acc
    acc = 0
    -- nothing to do while the cursor stands still and the fade has finished
    local x, y = GetCursorPosition()
    if settled and x == lastX and y == lastY then return end
    lastX, lastY = x, y
    local over = Minimap:IsMouseOver(4, -4, -4, 4) or (bin:IsShown() and bin:IsMouseOver())
    local target = over and 1 or 0
    fadeAlpha = fadeAlpha + (target - fadeAlpha) * math.min(1, dt * 10)
    if math.abs(fadeAlpha - target) < 0.01 then fadeAlpha = target end
    settled = fadeAlpha == target
    for _, e in ipairs(ELEMENTS) do
        local f = e.get()
        local cfg = M.db.elements[e.key]
        if f and cfg and cfg.pos ~= "HIDDEN" and cfg.pos ~= "BLIZZARD" then
            f:SetAlpha(cfg.mouseover and fadeAlpha or 1)
        end
    end
end

---------------------------------------------------------------------------
local applied = false
local function ApplyAll()
    if not M.enabled then return end
    if not applied then
        applied = true
        if M.db.square then MakeSquare() end
        if M.db.wheelZoom then SetupZoom() end
    end
    ApplyStats()
    binBtn:SetShown(M.db.bin)
    if M.db.bin then C_Timer.After(2, Collect) end      -- after other addons made their buttons
    PlaceElements()
    C_Timer.After(1, PlaceElements)                     -- again, after Blizzard's own minimap layout
    settled = false
    fader:Show()
end


function M:Setup()
    stats = CreateFrame("Frame", nil, Minimap)
    stats:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", 2, -3)
    stats:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", -2, -3)
    stats:SetHeight(28)
    stats:Hide()
    local function Text(justify)
        local t = stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetJustifyH(justify)
        return t
    end
    timeText, leftText, rightText = Text("CENTER"), Text("LEFT"), Text("RIGHT")

    locFrame = CreateFrame("Frame", nil, Minimap)
    locFrame:SetPoint("TOPLEFT", 2, -3); locFrame:SetPoint("TOPRIGHT", -2, -3)
    locFrame:SetHeight(14)
    locFrame:SetFrameLevel(Minimap:GetFrameLevel() + 3)
    locFrame:Hide()
    locText = locFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    locText:SetPoint("CENTER")
    locText:SetShadowOffset(1, -1)

    local durEv = CreateFrame("Frame")
    durEv:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    durEv:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    durEv:SetScript("OnEvent", function() durabilityDirty = true end)

    binBtn = CreateFrame("Button", nil, Minimap, "BackdropTemplate")
    binBtn:SetSize(16, 16)
    binBtn:SetPoint("BOTTOMRIGHT", -3, 3)
    binBtn:SetFrameLevel(Minimap:GetFrameLevel() + 4)
    TT.Flat(binBtn, { 0, 0, 0, 0.6 })
    local dots = binBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dots:SetPoint("CENTER", 0, 3)
    dots:SetText("...")
    binBtn:Hide()

    bin = CreateFrame("Frame", "TrikksTweaksButtonBin", UIParent, "BackdropTemplate")
    bin:SetFrameStrata("DIALOG")
    TT.Flat(bin, TT.C.bg, TT.C.border)
    bin:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", -6, 0)
    bin:Hide()
    tinsert(UISpecialFrames, "TrikksTweaksButtonBin")

    binBtn:SetScript("OnClick", function()
        if bin:IsShown() then bin:Hide() else Collect(); bin:Show() end
    end)
    binBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(TT.C.accent))
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Addon buttons")
        GameTooltip:Show()
    end)
    binBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(TT.C.border)); GameTooltip:Hide() end)

    hiddenParent = CreateFrame("Frame")
    hiddenParent:Hide()

    fader = CreateFrame("Frame")
    fader:SetScript("OnUpdate", FaderUpdate)
    fader:SetScript("OnShow", function() settled = false end)   -- re-apply after settings / loading screens
    fader:Hide()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", ApplyAll)
end

function M:OnEnable() if IsLoggedIn() then ApplyAll() end end
function M:OnDisable()
    ApplyStats(); binBtn:Hide(); bin:Hide(); fader:Hide()
    StaticPopup_Show("TRIKKSTWEAKS_RELOAD", "Minimap module turned off. A reload brings the round minimap back.")
end

function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(TT.C.dim)); h:SetPoint("TOPLEFT", 0, -y); y = y + 20
    end
    local function Check(key, text, indent, after)
        local cb = TT.Check(body, text, function(v) db[key] = v; if after and M.enabled then after(v) end end)
        cb:SetPoint("TOPLEFT", 2 + (indent and 20 or 0), -y)
        checks[key] = cb
        y = y + 24
    end
    local function NeedsReload() TT.Print("this change applies after a /reload.") end
    Head("Shape")
    Check("square", "Square minimap with a thin border", nil, NeedsReload)
    Check("wheelZoom", "Zoom with the mouse wheel (hides the + / - buttons)", nil, NeedsReload)
    y = y + 8
    Head("Stats")
    Check("stats", "Show stats", nil, ApplyStats)
    Check("location", "Location on the map (coloured by PvP status)", true, ApplyStats)
    Check("time", "Clock", true, ApplyStats)
    Check("clockInside", "Clock inside the map (bottom centre) instead of under it", true, ApplyStats)
    Check("hour24", "24-hour clock", true, ApplyStats)
    local SIDES = { { "LEFT", "Left" }, { "RIGHT", "Right" } }
    local sideButtons = {}
    local function Stat(key, text)
        Check(key, text, true, ApplyStats)
        local c = TT.Cycle(body, 60, SIDES, function() return db.side[key] end,
            function(v) db.side[key] = v end)
        c:SetPoint("TOPLEFT", 330, -(y - 24) + 3)
        sideButtons[#sideButtons + 1] = c
    end
    Stat("fps", "FPS")
    Stat("latency", "Latency")
    Stat("coords", "Coordinates (replaces Blizzard's)")
    Stat("durability", "Lowest durability")
    y = y + 8
    Head("Addon buttons")
    Check("bin", "Collect addon minimap buttons behind one '...' button", nil, function(v)
        binBtn:SetShown(v); if not v then bin:Hide(); NeedsReload() end
    end)
    y = y + 8
    Head("Minimap elements")
    Check("hideZone", "Hide the zone name bar above the map", nil, function() PlaceElements() end)
    Check("moveUp", "Move the map up into the gap", true, function() PlaceElements() end)
    Check("corner", "Square map: push it into the top-right corner of its Edit Mode box", nil, function() PlaceElements() end)
    local rows = {}
    for _, e in ipairs(ELEMENTS) do
        local cfg = db.elements[e.key]
        local label = TT.Label(body, e.label)
        label:SetPoint("TOPLEFT", 4, -y - 4)
        local posBtn = TT.Button(body, "", 110, nil)
        posBtn:SetPoint("TOPLEFT", 210, -y)
        local mo = TT.Check(body, "Mouseover", function(v) cfg.mouseover = v; settled = false end)
        mo:SetPoint("LEFT", posBtn, "RIGHT", 14, 0)
        posBtn:SetScript("OnClick", function(self)
            -- cycle through the positions (right-click goes backwards)
            local i = 1
            for k, v in ipairs(POSITIONS) do if v == cfg.pos then i = k end end
            local step = (GetMouseButtonClicked and GetMouseButtonClicked() == "RightButton") and -1 or 1
            cfg.pos = POSITIONS[(i - 1 + step) % #POSITIONS + 1]
            self:SetText(POS_TEXT[cfg.pos])
            if cfg.pos == "BLIZZARD" then TT.Print(e.label .. ": back to Blizzard's spot after a /reload.") end
            PlaceElements()
        end)
        posBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        rows[#rows + 1] = function() posBtn:SetText(POS_TEXT[cfg.pos] or cfg.pos); mo:SetChecked(cfg.mouseover) end
        y = y + 26
    end
    local tip = TT.Label(body, "Click a position to cycle through corners / hidden / Blizzard default\n(right-click to go back). Several elements in one corner line up next to each other.",
        "GameFontDisableSmall")
    tip:SetPoint("TOPLEFT", 0, -y - 8)

    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        for _, r in ipairs(rows) do r() end
        for _, c in ipairs(sideButtons) do c.Refresh() end
    end
end
