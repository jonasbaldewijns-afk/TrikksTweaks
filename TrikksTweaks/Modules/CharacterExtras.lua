-- Module: Character Extras
-- Durability % and a master volume slider on the character window, flight
-- times on the flight map (learned the first time you fly a route), and
-- class-coloured health bars on the player / target / focus frames.
local _, TT = ...
local M = TT:RegisterModule("CharacterExtras", {
    title = "Character Extras",
    category = "Interface",
    desc = "Durability and volume on the character window, flight times, class-coloured health bars.",
    defaults = {
        durability = true, durPos = "TOPLEFT", volume = true, volPos = "BOTTOMLEFT",
        flightTimes = true, flights = {}, classBars = false,
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

if CharacterFrame then
    CharacterFrame:HookScript("OnShow", function() UpdateDurability(); UpdateVolume() end)
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

hooksecurefunc("TakeTaxiNode", function(index)
    local src, dest = CurrentNode(), TaxiNodeName(index)
    if src and dest then flight = { key = src .. " > " .. dest, start = GetTime() } end
end)

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

-- classic-style flight map
if type(TaxiNodeOnButtonEnter) == "function" then
    hooksecurefunc("TaxiNodeOnButtonEnter", function(button) AddFlightLine(button:GetID()) end)
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
if type(UnitFrameHealthBar_Update) == "function" then
    hooksecurefunc("UnitFrameHealthBar_Update", function(bar, unit) ColorBar(bar, unit) end)
end
local function ColorAll()
    for unit, frame in pairs({ player = PlayerFrame, target = TargetFrame, focus = FocusFrame }) do
        local bar = frame and (frame.healthbar or (frame.GetHealthBar and frame:GetHealthBar()))
        if bar then ColorBar(bar, unit) end
    end
end

---------------------------------------------------------------------------
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

function M:OnEnable() UpdateDurability(); UpdateVolume(); ColorAll() end
function M:OnDisable() UpdateDurability(); UpdateVolume() end

function M:BuildSettings(body, page)
    local db, checks, cycles, y = M.db, {}, {}, 0
    local function Check(key, text, after)
        local cb = TT.Check(body, text, function(v) db[key] = v; if after then after() end end)
        cb:SetPoint("TOPLEFT", 2, -y)
        checks[key] = cb
        y = y + 24
    end
    local function Corner(key, after)
        local c = TT.Cycle(body, 110, CORNERS, function() return db[key] end, function(v) db[key] = v; after() end)
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
    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        for _, c in ipairs(cycles) do c.Refresh() end
        local n = 0
        for _ in pairs(db.flights) do n = n + 1 end
        count:SetText(n .. " flight route" .. (n == 1 and "" or "s") .. " learned")
    end
end
