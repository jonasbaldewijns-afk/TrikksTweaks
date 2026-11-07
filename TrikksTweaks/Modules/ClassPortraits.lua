-- Module: Class Portraits
-- Replaces the portrait of player units with a class icon. NPCs keep theirs.
local _, TT = ...
local M = TT:RegisterModule("ClassPortraits", {
    title = "Class Portraits",
    category = "Interface",
    desc = "Shows class icons instead of faces on player portraits (you, target, focus, party).",
    defaults = { style = 1 },
})

-- Each style returns: texture + texcoords (l, r, t, b) of the icon in that file.
-- inset crops edges so baked-in borders hide behind the portrait ring.
local STYLES = {
    { name = "Trikks icons", inset = 0.06, get = function(class)
        return TT.MEDIA .. "icons\\" .. class, 0, 1, 0, 1 end },
    { name = "Round (classic)", inset = 0.04, get = function(class)
        local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if c then return "Interface\\TargetingFrame\\UI-Classes-Circles", c[1], c[2], c[3], c[4] end end },
    { name = "Flat (classicon)", inset = 0.08, atlas = "classicon-%s" },
    { name = "Group finder", inset = 0.18, atlas = "groupfinder-icon-class-%s" },
}

local function FromAtlas(pattern, class)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return end
    local info = C_Texture.GetAtlasInfo(pattern:format(class:lower()))
    if info and info.file then
        return info.file, info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    end
end

-- texture + cropped texcoords for a class in a style
local function Resolve(style, class)
    local file, l, r, t, b
    if style.atlas then file, l, r, t, b = FromAtlas(style.atlas, class)
    else file, l, r, t, b = style.get(class) end
    if not file then return end
    local dx, dy = (r - l) * style.inset, (b - t) * style.inset
    return file, l + dx, r - dx, t + dy, b - dy
end

local function UpdatePortrait(frame)
    local portrait, unit = frame.portrait, frame.unit
    if not portrait or not unit then return end

    if M.enabled then
        local isPlayer = UnitIsPlayer(unit)
        if not TT.IsSecret(isPlayer) and isPlayer then
            local _, class = UnitClass(unit)
            if class and not TT.IsSecret(class) then
                local file, l, r, t, b = Resolve(STYLES[M.db.style] or STYLES[1], class)
                if file then
                    portrait:SetTexture(file)
                    portrait:SetTexCoord(l, r, t, b)
                    portrait.ttCropped = true
                    return
                end
            end
        end
    end
    -- NPC, or module off: Blizzard drew the normal portrait; undo our crop.
    if portrait.ttCropped then portrait:SetTexCoord(0, 1, 0, 1); portrait.ttCropped = nil end
end
-- hooksecurefunc can't be undone, so the hook stays and checks M.enabled.
hooksecurefunc("UnitFramePortrait_Update", UpdatePortrait)

local function RefreshAll()
    for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame",
                            "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }) do
        local f = _G[name]
        if f and f.portrait and f.unit then UnitFramePortrait_Update(f) end
    end
    if PartyFrame and PartyFrame.PartyMemberFramePool then
        for f in PartyFrame.PartyMemberFramePool:EnumerateActive() do
            if f.portrait and f.unit then UnitFramePortrait_Update(f) end
        end
    end
end

function M:OnEnable() RefreshAll() end
function M:OnDisable() RefreshAll() end

function M:BuildSettings(body, page)
    local l = TT.Label(body, "Icon style:")
    l:SetPoint("TOPLEFT")
    local _, myClass = UnitClass("player")
    local radios = {}
    local function Refresh() for i, r in ipairs(radios) do r:SetChecked(M.db.style == i) end end
    for i, style in ipairs(STYLES) do
        local cb = TT.Check(body, style.name, function() M.db.style = i; Refresh(); RefreshAll() end)
        cb:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -8 - (i - 1) * 40)
        -- preview of your own class in this style
        local prev = body:CreateTexture(nil, "ARTWORK")
        prev:SetSize(34, 34)
        prev:SetPoint("LEFT", cb, "LEFT", 220, 0)
        local file, a, b, c, d = Resolve(style, myClass)
        if file then prev:SetTexture(file); prev:SetTexCoord(a, b, c, d)
        else prev:SetColorTexture(0.2, 0.2, 0.2, 1) end
        local m = body:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(prev)
        prev:AddMaskTexture(m)
        radios[i] = cb
    end
    local note = TT.Label(body, "A grey preview means your client doesn't have that icon set.", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -8 - #STYLES * 40 - 6)
    page.OnPageShow = Refresh
    Refresh()
end
