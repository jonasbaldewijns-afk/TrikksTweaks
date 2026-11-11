-- Module: Dark Mode
-- Darkens Blizzard's frame art (unit frame borders, castbar borders, minimap
-- border, tooltips, bar art) by desaturating it and tinting it grey.
-- Written for Trikks Tweaks; works whether or not BBF's own dark mode is on.
local _, TT = ...
local M = TT:RegisterModule("DarkMode", {
    title = "Dark Mode",
    category = "Interface",
    desc = "Darkens unit frame borders, castbars, minimap border, tooltips and bar art.",
    defaults = { brightness = 30, unitframes = true, castbars = true, minimap = true,
                 tooltips = true, bars = true },
})

-- Parts to darken, per category. Paths are walked from _G: "A.B.C" = _G.A.B.C.
-- Missing paths are skipped, so one list works with and without BBF's
-- classic / no-portrait frame styles.
local TARGETS = {
    unitframes = {
        "PlayerFrame.PlayerFrameContainer.FrameTexture",
        "PlayerFrame.PlayerFrameContainer.FrameTextureBBF",
        "PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture",
        "PlayerFrame.PlayerFrameContainer.VehicleFrameTexture",
        "PlayerFrame.ClassicFrame.Texture",
        "PlayerFrameCompactRing",
        "TargetFrame.TargetFrameContainer.FrameTexture",
        "TargetFrame.ClassicFrame.Texture",
        "TargetFrameCompactRing",
        "FocusFrame.TargetFrameContainer.FrameTexture",
        "FocusFrame.ClassicFrame.Texture",
        "FocusFrameCompactRing",
        "TargetFrameToT.FrameTexture", "FocusFrameToT.FrameTexture",
        "PetFrameTexture", "PetFrame.FrameTexture",
        "PartyFrame.MemberFrame1.Texture", "PartyFrame.MemberFrame2.Texture",
        "PartyFrame.MemberFrame3.Texture", "PartyFrame.MemberFrame4.Texture",
        "PartyFrame.MemberFrame1.PetFrame.Texture", "PartyFrame.MemberFrame2.PetFrame.Texture",
        "PartyFrame.MemberFrame3.PetFrame.Texture", "PartyFrame.MemberFrame4.PetFrame.Texture",
        "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.LevelBackgroundCircle",
        "TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelBackgroundCircle",
        "FocusFrame.TargetFrameContent.TargetFrameContentMain.LevelBackgroundCircle",
    },
    castbars = {
        "PlayerCastingBarFrame.Border", "PlayerCastingBarFrame.TextBorder", "PlayerCastingBarFrame.Background",
        "TargetFrameSpellBar.Border", "TargetFrameSpellBar.TextBorder", "TargetFrameSpellBar.Background",
        "FocusFrameSpellBar.Border", "FocusFrameSpellBar.TextBorder", "FocusFrameSpellBar.Background",
    },
    minimap = {
        "MinimapCompassTexture", "MinimapBorder", "MinimapBorderTop",
        "MinimapCluster.BorderTop", "MinimapCluster.Tracking.Background",
        "MiniMapTrackingButtonBorder", "MiniMapMailBorder",
    },
    bars = {
        "MainActionBar.EndCaps.LeftEndCap", "MainActionBar.EndCaps.RightEndCap",
        "MainActionBar.BorderArt", "MainActionBar.Background",
        "MainMenuBar.EndCaps.LeftEndCap", "MainMenuBar.EndCaps.RightEndCap",
        "MainMenuBar.BorderArt", "MainMenuBar.Background",
        "StatusTrackingBarManager.MainStatusTrackingBarContainer.BarFrameTexture",
        "StatusTrackingBarManager.SecondaryStatusTrackingBarContainer.BarFrameTexture",
    },
}

-- "A.B.C" is cut into its parts once and kept: the paths are walked on every
-- target change, and cutting the text up each time made a lot of throwaway
-- strings. The walk itself is redone every time (frames can appear later).
local PARTS = {}
local function Resolve(path)
    local parts = PARTS[path]
    if not parts then
        parts = {}
        for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
        PARTS[path] = parts
    end
    local obj = _G
    for i = 1, #parts do
        if type(obj) ~= "table" then return nil end
        obj = obj[parts[i]]
    end
    return type(obj) == "table" and obj or nil
end

local function Color() return M.db.brightness / 100 end

-- Darken a texture (or every texture region of a frame).
-- kept here, not as fields on Blizzard's textures (taint)
local busy, locked = nil, {}

local Darken
-- every texture of a frame, without putting them in a new table first
local function DarkenRegions(on, ...)
    for i = 1, select("#", ...) do
        local r = select(i, ...)
        if r:GetObjectType() == "Texture" then Darken(r, on) end
    end
end
Darken = function(obj, on)
    if obj.IsForbidden and obj:IsForbidden() then return end
    if obj.GetObjectType and obj:GetObjectType() ~= "Texture" then
        if obj.GetRegions then DarkenRegions(on, obj:GetRegions()) end
        return
    end
    local c = on and Color() or 1
    busy = obj                             -- our own calls must not trigger our hooks
    obj:SetDesaturated(on)
    obj:SetVertexColor(c, c, c)
    busy = nil
end

-- Blizzard recolours / re-textures some of these on updates (e.g. elite target
-- borders). Hook those calls and put our colour back right after them.
local function Lock(tex, category)
    if locked[tex] or tex:GetObjectType() ~= "Texture" then return end
    locked[tex] = true
    local function reapply(self)
        if busy == self then return end
        if M.enabled and M.db[category] then Darken(self, true) end
    end
    hooksecurefunc(tex, "SetVertexColor", reapply)
    hooksecurefunc(tex, "SetAtlas", reapply)
    hooksecurefunc(tex, "SetTexture", reapply)
end

local function ApplyCategory(category)
    local on = M.enabled and M.db[category]
    for _, path in ipairs(TARGETS[category]) do
        local obj = Resolve(path)
        if obj then
            Darken(obj, on)
            if on then Lock(obj, category) end
        end
    end
end

-- Tooltips use a NineSlice frame with its own colour functions; Blizzard resets
-- the style each time a tooltip is shown, so re-tint after that.
local function DarkenTooltip(tt)
    if not (M.enabled and M.db.tooltips) or not tt or not tt.NineSlice then return end
    local ns = tt.NineSlice
    if ns.SetCenterColor then ns:SetCenterColor(0.04, 0.04, 0.05, 0.92) end
    if ns.SetBorderColor then
        local c = Color()
        ns:SetBorderColor(c, c, c, 1)
    end
end
local function HookTooltips()
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if tt then tt:HookScript("OnShow", DarkenTooltip) end
    end
    if type(SharedTooltip_SetBackdropStyle) == "function" then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt) DarkenTooltip(tt) end)
    end
end

local function ApplyAll()
    if not M.db then return end
    for category in pairs(TARGETS) do ApplyCategory(category) end
end

function M:Setup()
    HookTooltips()
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
                         "GROUP_ROSTER_UPDATE", "UNIT_PET", "UNIT_CLASSIFICATION_CHANGED" }) do
        ev:RegisterEvent(e)
    end
    -- One frame later (after Blizzard / BBF have updated), once per frame.
    -- A loading screen redoes everything; target, focus, group and pet changes
    -- only touch the unit frames, so only those are redone.
    local pendingAll, pendingUnits = false, false
    local function Run()
        local all = pendingAll
        pendingAll, pendingUnits = false, false
        if not M.enabled then return end
        if all then ApplyAll() else ApplyCategory("unitframes") end
    end
    ev:SetScript("OnEvent", function(_, event)
        if not M.enabled then return end
        local waiting = pendingAll or pendingUnits
        if event == "PLAYER_ENTERING_WORLD" then pendingAll = true else pendingUnits = true end
        if not waiting then C_Timer.After(0, Run) end
    end)
end

function M:OnEnable() ApplyAll() end
function M:OnDisable()
    ApplyAll()   -- puts colours back to normal
    TT.AskReload("Dark Mode turned off. A reload restores everything exactly.")
end

function M:BuildSettings(body, page)
    local db = M.db
    local checks = {}
    local list = {
        { "unitframes", "Unit frames (player, target, focus, party, pet)" },
        { "castbars", "Castbars" },
        { "minimap", "Minimap border" },
        { "tooltips", "Tooltips" },
        { "bars", "Action bar art and XP / reputation bar" },
    }
    for i, item in ipairs(list) do
        local key = item[1]
        local cb = TT.Check(body, item[2], function(v)
            db[key] = v
            if not M.enabled then return end
            if key == "tooltips" then
                if not v then TT.Print("tooltips go back to normal after a reload.") end
            else
                ApplyCategory(key)
            end
        end)
        cb:SetPoint("TOPLEFT", 2, -4 - (i - 1) * 26)
        checks[key] = cb
    end

    local bright = TT.Stepper(body, "Brightness %", function() return db.brightness end,
        function(v) db.brightness = v; if M.enabled then ApplyAll() end end, 0, 100, 5)
    bright:SetPoint("TOPLEFT", 0, -4 - #list * 26 - 10)

    local help = TT.Label(body,
        "Lower brightness = darker. 0% is black, 100% is just grey (no tint).\n\n" ..
        "You can turn BBF's own Dark Mode off. If both are on they do the same\n" ..
        "thing, so nothing breaks, but there's no need for both.",
        "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", bright, "BOTTOMLEFT", 0, -14)

    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        bright.Refresh()
    end
end
