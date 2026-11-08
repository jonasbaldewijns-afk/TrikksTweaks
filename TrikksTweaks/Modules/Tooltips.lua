-- Module: Tooltips
-- Class-coloured player names, guild rank, who the unit is targeting, where
-- the tooltip appears (Blizzard spot / at the mouse / a fixed spot), scale,
-- hide in combat and hide the health bar.
local _, TT = ...
local M = TT:RegisterModule("Tooltips", {
    title = "Tooltips",
    category = "Interface",
    desc = "Class colours, guild rank, unit's target, tooltip position and scale, hide in combat.",
    defaults = {
        classColor = true, guildRank = true, target = true, hideHealthBar = false,
        anchor = "BLIZZARD", mouseX = 20, mouseY = 0, point = "BOTTOMRIGHT", x = -60, y = 120,
        scale = 100, hideCombat = false, combatUnitsOnly = true,
    },
})
local IsSecret = TT.IsSecret

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    if not class or IsSecret(class) then return end
    return (C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
end

-- Runs after the game has filled in a unit tooltip.
local function OnUnit(tooltip)
    if not M.enabled or tooltip ~= GameTooltip then return end
    local db = M.db
    local _, unit = tooltip:GetUnit()
    if not unit or IsSecret(unit) then unit = "mouseover" end
    if not UnitExists(unit) then return end
    local isPlayer = UnitIsPlayer(unit)
    if IsSecret(isPlayer) then return end

    if isPlayer then
        local color = db.classColor and ClassColor(unit)
        if color and GameTooltipTextLeft1 then GameTooltipTextLeft1:SetTextColor(color.r, color.g, color.b) end
        if db.guildRank then
            local guild, rank = GetGuildInfo(unit)
            if guild and rank and not IsSecret(guild) and not IsSecret(rank) then
                for i = 2, math.min(4, tooltip:NumLines()) do
                    local fs = _G["GameTooltipTextLeft" .. i]
                    local text = fs and fs:GetText()
                    if text and not IsSecret(text) and text:find(guild, 1, true) then
                        fs:SetText(text .. " |cff888888- " .. rank .. "|r")
                        break
                    end
                end
            end
        end
    end

    if db.target then
        local tu = unit .. "target"
        if UnitExists(tu) then
            local name = UnitName(tu)
            if name and not IsSecret(name) then
                local text
                if UnitIsUnit(tu, "player") then
                    text = "|cffff5555>> You <<|r"
                else
                    local c = UnitIsPlayer(tu) and ClassColor(tu)
                    text = c and string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) or name
                end
                tooltip:AddLine("Target: " .. text)
            end
        end
    end

    if db.hideHealthBar and GameTooltipStatusBar then GameTooltipStatusBar:Hide() end
    tooltip:Show()
end

function M:Setup()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)

    -- Position: Blizzard calls GameTooltip_SetDefaultAnchor for most tooltips;
    -- we re-anchor right after it.
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not M.enabled then return end
        local db = M.db
        if db.anchor == "MOUSE" then
            tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", db.mouseX, db.mouseY)
        elseif db.anchor == "FIXED" then
            tooltip:ClearAllPoints()
            tooltip:SetPoint(db.point, UIParent, db.point, db.x, db.y)
        end
    end)

    -- Hide in combat (hold Shift to see it anyway)
    GameTooltip:HookScript("OnShow", function(self)
        local db = M.db
        if not (M.enabled and db and db.hideCombat) or not InCombatLockdown() or IsShiftKeyDown() then return end
        if db.combatUnitsOnly then
            local _, unit = self:GetUnit()
            if not unit then return end
        end
        self:Hide()
    end)
end

local function ApplyScale()
    local s = (M.enabled and M.db.scale or 100) / 100
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2, EmbeddedItemTooltip }) do
        if tt then tt:SetScale(s) end
    end
end

function M:OnEnable() ApplyScale() end
function M:OnDisable() ApplyScale() end

function M:BuildSettings(body, page)
    local db, checks, refresh, y = M.db, {}, {}, 0
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(TT.C.dim)); h:SetPoint("TOPLEFT", 0, -y); y = y + 20
    end
    local function Check(key, text, indent)
        local cb = TT.Check(body, text, function(v) db[key] = v end)
        cb:SetPoint("TOPLEFT", 2 + (indent and 20 or 0), -y)
        checks[key] = cb
        y = y + 24
    end
    local function Step(text, key, min, max, step, after)
        local s = TT.Stepper(body, text, function() return db[key] end,
            function(v) db[key] = v; if after and M.enabled then after() end end, min, max, step)
        s:SetPoint("TOPLEFT", 20, -y)
        refresh[#refresh + 1] = s.Refresh
        y = y + 26
    end
    local function Cycle(text, key, choices)
        local l = TT.Label(body, text)
        l:SetPoint("TOPLEFT", 4, -y - 4)
        local c = TT.Cycle(body, 140, choices, function() return db[key] end, function(v) db[key] = v end)
        c:SetPoint("TOPLEFT", 220, -y)
        refresh[#refresh + 1] = c.Refresh
        y = y + 28
    end

    Head("Players")
    Check("classColor", "Class-coloured names")
    Check("guildRank", "Show guild rank after the guild name")
    Check("target", "Show who they're targeting")
    Check("hideHealthBar", "Hide the health bar under unit tooltips")
    y = y + 6
    Head("Position & size")
    Cycle("Tooltip position", "anchor", { { "BLIZZARD", "Blizzard default" }, { "MOUSE", "At the mouse" }, { "FIXED", "Fixed spot" } })
    Step("Mouse offset X", "mouseX", -200, 200, 5)
    Step("Mouse offset Y", "mouseY", -200, 200, 5)
    Cycle("Fixed spot: screen corner", "point", { { "BOTTOMRIGHT", "Bottom right" }, { "BOTTOMLEFT", "Bottom left" },
        { "TOPRIGHT", "Top right" }, { "TOPLEFT", "Top left" }, { "BOTTOM", "Bottom" }, { "CENTER", "Centre" } })
    Step("Fixed spot X", "x", -2000, 2000, 10)
    Step("Fixed spot Y", "y", -2000, 2000, 10)
    Step("Scale %", "scale", 50, 200, 5, ApplyScale)
    y = y + 6
    Head("Combat")
    Check("hideCombat", "Hide tooltips in combat (hold Shift to show)")
    Check("combatUnitsOnly", "Only unit tooltips (keep spell / item tooltips)", true)

    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        for _, f in ipairs(refresh) do f() end
    end
end
