-- Module: Character Extras
-- Durability % and a master volume slider on the character window, flight
-- times on the flight map (learned the first time you fly a route), and
-- class-coloured health bars on the player / target / focus frames, and item
-- level + a missing enchant / empty socket mark on the gear slots.
local _, TT = ...
local M = TT:RegisterModule("CharacterExtras", {
    title = "Character Extras",
    category = "Interface",
    desc = "Durability and volume on the character window, flight times, class-coloured health bars.",
    defaults = {
        durability = true, durPos = "TOPLEFT", volume = true, volPos = "BOTTOMLEFT",
        flightTimes = true, flights = {}, classBars = false,
        itemLevel = true, enchantCheck = true, gemCheck = true, inspect = true,
        -- slots that should carry an enchant (which ones depends on the expansion: your choice)
        enchantSlots = { [15] = true, [5] = true, [9] = true, [7] = true, [8] = true, [16] = true },
    },
})
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CORNERS = { { "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" },
                  { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" } }
-- small inset from each corner of the character window, clear of the title bar
local INSET = { TOPLEFT = { 12, -32 }, TOPRIGHT = { -12, -32 }, BOTTOMLEFT = { 12, 12 }, BOTTOMRIGHT = { -12, 12 } }

---------------------------------------------------------------------------
-- Durability on the character window
---------------------------------------------------------------------------
local durText
local function UpdateDurability()
    if not CharacterFrame then return end
    if not durText then
        durText = CharacterFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end
    local on = M.enabled and M.db.durability
    durText:SetShown(on)
    if not on then return end
    local pos = M.db.durPos
    durText:ClearAllPoints()
    durText:SetPoint(pos, CharacterFrame, pos, INSET[pos][1], INSET[pos][2])
    local cur, max = 0, 0
    for slot = 1, 19 do
        local c, m = GetInventoryItemDurability(slot)
        if c and m then cur, max = cur + c, max + m end
    end
    if max == 0 then durText:SetText(""); return end
    local pct = math.floor(cur / max * 100)
    local color = pct >= 50 and "33ff99" or pct >= 20 and "ffd100" or "ff5555"
    durText:SetText("Durability |cff" .. color .. pct .. "%|r")
end

---------------------------------------------------------------------------
-- Volume slider on the character window
---------------------------------------------------------------------------
local vol
local function MakeVolume()
    if vol or not CharacterFrame then return end
    vol = CreateFrame("Slider", nil, CharacterFrame, "BackdropTemplate")
    vol:SetOrientation("HORIZONTAL")
    vol:SetSize(110, 8)
    -- a slider made in code ignores the mouse until told otherwise (Blizzard's
    -- XML templates switch this on for their sliders)
    vol:EnableMouse(true)
    vol:SetHitRectInsets(-4, -4, -6, -6)                 -- bigger grab area than the thin bar
    -- above the window's other parts (the 3D model area catches the mouse to rotate)
    vol:SetFrameLevel(CharacterFrame:GetFrameLevel() + 20)
    TT.Flat(vol, { 0.04, 0.04, 0.05, 1 })
    vol:SetThumbTexture(WHITE)
    local thumb = vol:GetThumbTexture()
    thumb:SetSize(6, 14)
    thumb:SetVertexColor(unpack(TT.C.accent))
    vol:SetMinMaxValues(0, 100)
    vol:SetValueStep(5)
    vol:SetObeyStepOnDrag(true)
    vol.label = vol:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    vol.label:SetPoint("BOTTOM", vol, "TOP", 0, 3)
    vol:SetScript("OnValueChanged", function(self, value, userInput)
        self.label:SetText("Volume " .. math.floor(value + 0.5) .. "%")
        if userInput then C_CVar.SetCVar("Sound_MasterVolume", value / 100) end
    end)
    vol:EnableMouseWheel(true)
    vol:SetScript("OnMouseWheel", function(self, delta)
        local v = math.max(0, math.min(100, self:GetValue() + delta * 5))
        self:SetValue(v)
        C_CVar.SetCVar("Sound_MasterVolume", v / 100)
    end)
end

local function UpdateVolume()
    local on = M.enabled and M.db.volume
    if on then MakeVolume() end
    if not vol then return end
    vol:SetShown(on)
    if not on then return end
    local pos = M.db.volPos
    vol:ClearAllPoints()
    vol:SetPoint(pos, CharacterFrame, pos, INSET[pos][1], INSET[pos][2] + (pos:find("TOP") and -14 or 0))
    vol:SetValue((tonumber(C_CVar.GetCVar("Sound_MasterVolume")) or 1) * 100)
end


---------------------------------------------------------------------------
-- Flight times: remember how long each route took, show it on the flight map
---------------------------------------------------------------------------
local flight
local function CurrentNode()
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
    end
end


local function AddFlightLine(index)
    if not (M.enabled and M.db.flightTimes) or not index then return end
    if TaxiNodeGetType(index) ~= "REACHABLE" then return end
    local src = CurrentNode()
    if not src then return end
    local t = M.db.flights[src .. " > " .. TaxiNodeName(index)]
    GameTooltip:AddLine(t and string.format("Flight time: %d:%02d", t / 60, t % 60)
        or "Flight time: unknown (fly it once to learn it)", 0.6, 0.9, 1)
    GameTooltip:Show()
end

-- modern flight map (loads on demand)
local flightMapHooked = false
local function HookFlightMap()
    if flightMapHooked or not FlightMap_FlightPointPinMixin then return end
    flightMapHooked = true
    hooksecurefunc(FlightMap_FlightPointPinMixin, "OnMouseEnter", function(pin)
        AddFlightLine(pin.taxiNodeData and pin.taxiNodeData.slotIndex)
    end)
end

---------------------------------------------------------------------------
-- Class-coloured health bars (player / target / focus)
---------------------------------------------------------------------------
local BAR_UNITS = { player = true, target = true, focus = true }
local function ColorBar(bar, unit)
    if not (M.enabled and M.db.classBars) or not bar or not unit or not BAR_UNITS[unit] then return end
    local isPlayer = UnitIsPlayer(unit)
    if TT.IsSecret(isPlayer) or not isPlayer then return end
    local _, class = UnitClass(unit)
    local c = class and not TT.IsSecret(class) and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or RAID_CLASS_COLORS[class])
    if not c then return end
    if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(true) end
    bar:SetStatusBarColor(c.r, c.g, c.b)
end
local function ColorAll()
    for unit, frame in pairs({ player = PlayerFrame, target = TargetFrame, focus = FocusFrame }) do
        local bar = frame and (frame.healthbar or (frame.GetHealthBar and frame:GetHealthBar()))
        if bar then ColorBar(bar, unit) end
    end
end

---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Item level and enchant / gem check on the gear slots (character + inspect)
---------------------------------------------------------------------------
-- slot ID -> name, for the settings (the IDs are the game's inventory slots)
local ENCHANT_SLOTS = { { 1, "Head" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
    { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Ring 1" }, { 12, "Ring 2" },
    { 16, "Main hand" }, { 17, "Off hand" } }

local function ItemLevel(link)
    local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    local lvl = f and f(link)
    if lvl and not TT.IsSecret(lvl) and lvl > 0 then return lvl end
end
-- "item:id:enchant:gem1:gem2:gem3:gem4:..." -> enchant ID, number of gems in it
local function LinkParts(link)
    local body = link:match("item:([%-%d:]*)")
    if not body then return 0, 0 end
    local parts, i = {}, 0
    for v in (body .. ":"):gmatch("([^:]*):") do i = i + 1; parts[i] = tonumber(v) or 0 end
    local gems = 0
    for k = 3, 6 do if (parts[k] or 0) > 0 then gems = gems + 1 end end
    return parts[2] or 0, gems
end
-- how many sockets the item has (any colour)
local function Sockets(link)
    local f = (C_Item and C_Item.GetItemStats) or GetItemStats
    local stats = f and f(link)
    local n = 0
    if type(stats) == "table" then
        for k, v in pairs(stats) do
            if type(k) == "string" and k:find("EMPTY_SOCKET") and type(v) == "number" then n = n + v end
        end
    end
    return n
end

local slotTexts = setmetatable({}, { __mode = "k" })   -- button -> { ilvl, mark } (not fields on Blizzard's buttons)
local function SlotTexts(button)
    local t = slotTexts[button]
    if not t then
        local ilvl = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        ilvl:SetPoint("BOTTOM", 0, 2)
        local mark = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        mark:SetPoint("TOPLEFT", 2, -2)
        mark:SetTextColor(1, 0.25, 0.25)
        t = { ilvl, mark }
        slotTexts[button] = t
    end
    return t[1], t[2]
end

local function UpdateSlot(button, unit)
    if not button or not button.GetID then return end
    if not M.enabled and not slotTexts[button] then return end   -- off and nothing shown: nothing to do
    local ilvlText, mark = SlotTexts(button)
    local db = M.db
    local link = unit and GetInventoryItemLink(unit, button:GetID())
    if not (M.enabled and link) or TT.IsSecret(link) then ilvlText:SetText(""); mark:SetText(""); return end
    local slot = button:GetID()
    -- item level, in the item's quality colour (not for shirt / tabard)
    local lvl = db.itemLevel and slot ~= 4 and slot ~= 19 and ItemLevel(link)
    if lvl then
        ilvlText:SetText(lvl)
        local q = select(3, C_Item.GetItemInfo(link))
        local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c then ilvlText:SetTextColor(c.r, c.g, c.b) else ilvlText:SetTextColor(1, 1, 1) end
    else
        ilvlText:SetText("")
    end
    -- red "E" = should be enchanted but isn't, red "G" = an empty socket
    local enchant, gems = LinkParts(link)
    local m = ""
    if db.enchantCheck and db.enchantSlots[slot] and enchant == 0 then m = "E" end
    if db.gemCheck and Sockets(link) > gems then m = m .. "G" end
    mark:SetText(m)
end

local GEAR_SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands",
    "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged" }
local function UpdateCharacterSlots()
    for _, n in ipairs(GEAR_SLOTS) do UpdateSlot(_G["Character" .. n .. "Slot"], "player") end
end
local function UpdateInspectSlots()
    local unit = InspectFrame and InspectFrame.unit
    for _, n in ipairs(GEAR_SLOTS) do
        local b = _G["Inspect" .. n .. "Slot"]
        if b then UpdateSlot(b, M.db.inspect and unit or nil) end
    end
end
local inspectHooked = false
local function HookInspect()
    if inspectHooked or type(InspectPaperDollItemSlotButton_Update) ~= "function" then return end
    inspectHooked = true
    hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(b)
        UpdateSlot(b, M.db.inspect and InspectFrame and InspectFrame.unit or nil)
    end)
end

-- Hooks and events only exist once the module has been switched on.
function M:Setup()
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", function() UpdateDurability(); UpdateVolume() end)
    end
    hooksecurefunc("TakeTaxiNode", function(index)
        local src, dest = CurrentNode(), TaxiNodeName(index)
        if src and dest then flight = { key = src .. " > " .. dest, start = GetTime() } end
    end)
    -- classic-style flight map
    if type(TaxiNodeOnButtonEnter) == "function" then
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button) AddFlightLine(button:GetID()) end)
    end
    if type(UnitFrameHealthBar_Update) == "function" then
        hooksecurefunc("UnitFrameHealthBar_Update", function(bar, unit) ColorBar(bar, unit) end)
    end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "PLAYER_CONTROL_GAINED",
                         "ADDON_LOADED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "CVAR_UPDATE" }) do
        ev:RegisterEvent(e)
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_CONTROL_GAINED" then
            -- landed: store how long the flight took
            if flight and not UnitOnTaxi("player") then
                local dur = GetTime() - flight.start
                if dur > 5 then M.db.flights[flight.key] = math.floor(dur + 0.5) end
                flight = nil
            end
        elseif event == "ADDON_LOADED" then
            HookFlightMap()
        elseif event == "UPDATE_INVENTORY_DURABILITY" then
            UpdateDurability()
        elseif event == "CVAR_UPDATE" then
            if vol and vol:IsVisible() then UpdateVolume() end
        else
            if event == "PLAYER_ENTERING_WORLD" then HookFlightMap(); UpdateDurability() end
            C_Timer.After(0, ColorAll)
        end
    end)
    if type(PaperDollItemSlotButton_Update) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_Update", function(b) UpdateSlot(b, "player") end)
    end
    local gearEv = CreateFrame("Frame")
    gearEv:RegisterEvent("ADDON_LOADED")
    gearEv:RegisterEvent("INSPECT_READY")
    gearEv:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    gearEv:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then HookInspect()
        elseif not M.enabled then return     -- off: no gear rescans
        elseif event == "INSPECT_READY" then C_Timer.After(0.1, UpdateInspectSlots)
        else C_Timer.After(0.1, UpdateCharacterSlots) end
    end)
    HookInspect()
end

function M:OnEnable() UpdateDurability(); UpdateVolume(); ColorAll(); UpdateCharacterSlots() end
function M:OnDisable() UpdateDurability(); UpdateVolume(); UpdateCharacterSlots() end

function M:BuildSettings(body, page)
    local db, checks, cycles, y = M.db, {}, {}, 0
    local function Check(key, text, after)
        local cb = TT.Check(body, text, function(v) db[key] = v; if after and M.enabled then after() end end)
        cb:SetPoint("TOPLEFT", 2, -y)
        checks[key] = cb
        y = y + 24
    end
    local function Corner(key, after)
        local c = TT.Cycle(body, 110, CORNERS, function() return db[key] end, function(v) db[key] = v; if M.enabled then after() end end)
        c:SetPoint("TOPLEFT", 380, -(y - 24) + 3)
        cycles[#cycles + 1] = c
    end
    Check("durability", "Durability % on the character window", UpdateDurability)
    Corner("durPos", UpdateDurability)
    Check("volume", "Master volume slider on the character window", UpdateVolume)
    Corner("volPos", UpdateVolume)
    Check("flightTimes", "Flight times on the flight map")
    Check("classBars", "Class-coloured health bars (player, target, focus)", function()
        ColorAll()
        if not db.classBars then TT.Print("health bars go back to green after a /reload.") end
    end)
    Check("itemLevel", "Item level on the gear slots", UpdateCharacterSlots)
    Check("gemCheck", "Red G on items with an empty gem socket", UpdateCharacterSlots)
    Check("enchantCheck", "Red E on items that should be enchanted but aren't:", UpdateCharacterSlots)
    -- which slots count as "should be enchanted": three columns of checkboxes
    for i, sd in ipairs(ENCHANT_SLOTS) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local cb = TT.Check(body, sd[2], function(v) db.enchantSlots[sd[1]] = v or nil; if M.enabled then UpdateCharacterSlots() end end)
        cb:SetPoint("TOPLEFT", 22 + col * 150, -(y + row * 22))
        checks["slot" .. sd[1]] = { SetChecked = function() cb:SetChecked(db.enchantSlots[sd[1]] and true or false) end }
    end
    y = y + math.ceil(#ENCHANT_SLOTS / 3) * 22 + 4
    Check("inspect", "Also on the inspect window", UpdateInspectSlots)
    local count = TT.Label(body, "", "GameFontHighlightSmall")
    count:SetPoint("TOPLEFT", 4, -y - 6)
    local clear = TT.Button(body, "Forget flight times", 140, function()
        wipe(db.flights); page.OnPageShow()
    end)
    clear:SetPoint("TOPLEFT", 0, -y - 26)
    local help = TT.Label(body,
        "The buttons on the right pick which corner of the character window the\n" ..
        "text / slider sits in. If BBF also colours health bars, use only one of them.",
        "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 60)
    local help2 = TT.Label(body,
        "Which slots can be enchanted depends on the expansion: tick the ones that apply.", "GameFontDisableSmall")
    help2:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -6)
    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        for _, c in ipairs(cycles) do c.Refresh() end
        UpdateCharacterSlots()
        local n = 0
        for _ in pairs(db.flights) do n = n + 1 end
        count:SetText(n .. " flight route" .. (n == 1 and "" or "s") .. " learned")
    end
end
