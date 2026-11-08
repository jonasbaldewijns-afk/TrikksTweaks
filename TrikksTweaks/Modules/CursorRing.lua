-- Module: Cursor Ring
-- A ring around your mouse cursor so you never lose it in a busy fight.
-- The ring is a white picture tinted in the colour you pick.
local _, TT = ...
local M = TT:RegisterModule("CursorRing", {
    title = "Cursor Ring",
    category = "Interface",
    desc = "A ring around your mouse cursor (size, colour, thickness), optionally only in combat.",
    defaults = { size = 48, thick = false, colour = "class", alpha = 80, combatOnly = false, hideInMenus = true },
})

local COLOURS = { { "class", "Class colour" }, { "accent", "Trikks green" }, { "white", "White" },
                  { "red", "Red" }, { "yellow", "Yellow" }, { "blue", "Blue" } }
local RGB = { accent = { 0.2, 1, 0.6 }, white = { 1, 1, 1 }, red = { 1, 0.25, 0.25 },
              yellow = { 1, 0.85, 0.1 }, blue = { 0.3, 0.6, 1 } }

local ring = CreateFrame("Frame", nil, UIParent)
ring:SetFrameStrata("TOOLTIP")
ring:EnableMouse(false)
local tex = ring:CreateTexture(nil, "OVERLAY")
tex:SetAllPoints()
ring:Hide()

local function Apply()
    local db = M.db
    ring:SetSize(db.size, db.size)
    tex:SetTexture(TT.MEDIA .. (db.thick and "ring-thick" or "ring-thin"))
    local c = RGB[db.colour]
    if db.colour == "class" then
        local _, class = UnitClass("player")
        local cc = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
        c = cc and { cc.r, cc.g, cc.b } or RGB.white
    end
    tex:SetVertexColor(c[1], c[2], c[3], db.alpha / 100)
end

-- follow the cursor every frame (cursor position is in screen pixels: divide by the UI scale)
ring:SetScript("OnUpdate", function(self)
    local db = M.db
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    local menus = db.hideInMenus and ((GameMenuFrame and GameMenuFrame:IsShown()) or (TT.hub and TT.hub:IsShown()))
    if (db.combatOnly and not inCombat) or menus then tex:Hide(); return end
    tex:Show()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
end)

function M:OnEnable() Apply(); ring:Show() end
function M:OnDisable() ring:Hide() end

function M:BuildSettings(body, page)
    local db, refreshers, y = M.db, {}, 0
    local function Check(key, text)
        local cb = TT.Check(body, text, function(v) db[key] = v; Apply() end)
        cb:SetPoint("TOPLEFT", 2, -y)
        refreshers[#refreshers + 1] = function() cb:SetChecked(db[key]) end
        y = y + 24
    end
    local cl = TT.Label(body, "Colour:")
    cl:SetPoint("TOPLEFT", 4, -y - 4)
    local col = TT.Cycle(body, 130, COLOURS, function() return db.colour end, function(v) db.colour = v; Apply() end)
    col:SetPoint("TOPLEFT", 120, -y)
    refreshers[#refreshers + 1] = col.Refresh
    y = y + 32
    Check("thick", "Thick ring")
    Check("combatOnly", "Only in combat")
    Check("hideInMenus", "Hide while the Esc menu or this window is open")
    local size = TT.Stepper(body, "Size", function() return db.size end, function(v) db.size = v; Apply() end, 16, 160, 4)
    size:SetPoint("TOPLEFT", 0, -y - 4)
    refreshers[#refreshers + 1] = size.Refresh
    local alpha = TT.Stepper(body, "Opacity %", function() return db.alpha end, function(v) db.alpha = v; Apply() end, 10, 100, 5)
    alpha:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -2)
    refreshers[#refreshers + 1] = alpha.Refresh
    page.OnPageShow = function() for _, f in ipairs(refreshers) do f() end end
end
