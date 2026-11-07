-- Trikks Tweaks: minimap button (left-click opens the settings, drag to move)
-- and an entry in Blizzard's addon menu on the minimap.
local _, TT = ...
local ICON = TT.MEDIA .. "minimap"

local function DB()
    TrikksTweaksDB.minimapButton = TrikksTweaksDB.minimapButton or { hide = false, angle = 225 }
    return TrikksTweaksDB.minimapButton
end

-- The name ends in "MinimapButton" so button-bin addons (and our Minimap module) pick it up.
local btn = CreateFrame("Button", "TrikksTweaksMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:Hide()

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetTexture(ICON)
icon:SetAllPoints()
local hl = btn:CreateTexture(nil, "HIGHLIGHT")
hl:SetTexture(ICON)
hl:SetAllPoints()
hl:SetBlendMode("ADD")
hl:SetAlpha(0.35)

-- Place the button on the edge of the map at an angle (degrees).
-- Round map: on a circle. Square map: pushed out to the square's edge.
local function Place(angle)
    local rad = math.rad(angle)
    local x, y = math.cos(rad), math.sin(rad)
    local half = Minimap:GetWidth() / 2 + 6
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        -- scale the direction so its larger part touches the square edge
        local m = math.max(math.abs(x), math.abs(y))
        x, y = x / m, y / m
    end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x * half, y * half)
end

-- Dragging: follow the cursor's direction from the map's centre.
local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    DB().angle = angle
    Place(angle)
end
btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

local function Toggle() TT.hub:SetShown(not TT.hub:IsShown()) end
btn:SetScript("OnClick", Toggle)

btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Trikks Tweaks")
    GameTooltip:AddLine("Click: open settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the map", 1, 1, 1)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", GameTooltip_Hide)

-- show / hide (saved), used by the checkbox on the Modules page
function TT.SetMinimapButtonShown(show)
    DB().hide = not show
    btn:SetShown(show)
end
function TT.MinimapButtonShown() return not DB().hide end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    Place(DB().angle)
    btn:SetShown(not DB().hide)
    -- the Minimap module may make the map square a moment later: re-place then
    C_Timer.After(1, function() if btn:GetParent() == Minimap then Place(DB().angle) end end)
end)

-- Blizzard's addon menu (the number on the minimap) calls these by name (see the .toc)
function TrikksTweaks_OnAddonCompartmentClick() Toggle() end
function TrikksTweaks_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Trikks Tweaks")
    GameTooltip:AddLine("Click: open settings", 1, 1, 1)
    GameTooltip:Show()
end
function TrikksTweaks_OnAddonCompartmentLeave() GameTooltip:Hide() end
