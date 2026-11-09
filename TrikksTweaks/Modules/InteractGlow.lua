-- Module: Interact Glow
-- Ore, herbs, quest objects, chests and anything else you can interact with
-- sparkle when you come near: little sparks light up around the object and
-- fade, over a soft glow, in a colour per type.
--
-- How: near something interactable the game picks it as your "soft interact"
-- target and, with a few settings on (SoftTargetInteract & co, put back when
-- the module is off), gives it a nameplate. The sparkle is anchored to that
-- nameplate. The type comes from the cursor the game would show over it
-- (Mine, GatherHerbs, Quest, LootAll, PickLock, Fishing, ...): the game sets
-- that cursor on a hidden texture (SetUnitCursorTexture) and we read it back.
-- "Unable..." cursors (skill too low) get a dim grey sparkle.
-- The game highlights one object at a time: the nearest one in front of you.
local _, TT = ...
local IsSecret = TT.IsSecret

local M = TT:RegisterModule("InteractGlow", {
    title = "Interact Glow",
    category = "Interface",
    desc = "Ore, herbs, quest objects, chests and other interactables sparkle when you come near (colour per type).",
    defaults = {
        types = { ore = true, herb = true, quest = true, chest = true, fishing = true, other = true },
        size = 40, offsetY = -45, sparks = 6, brightness = 100, range = 20,
    },
})

local TYPES = {
    { "ore",     "Ore",                    { 1.00, 0.60, 0.25 } },
    { "herb",    "Herbs",                  { 0.40, 1.00, 0.45 } },
    { "quest",   "Quest objects",          { 1.00, 0.84, 0.15 } },
    { "chest",   "Chests and loot",        { 0.45, 0.78, 1.00 } },
    { "fishing", "Fishing",                { 0.30, 0.95, 0.95 } },
    { "other",   "Everything else",        { 0.90, 0.90, 1.00 } },
}
local COLOR = {}
for _, t in ipairs(TYPES) do COLOR[t[1]] = t[3] end
local BLOCKED = { 0.55, 0.55, 0.58 }          -- your skill is too low

-- the game's cursor names -> type (first match wins; "Unable..." = blocked)
local CURSOR_WORDS = {
    { "mine", "ore" }, { "herb", "herb" }, { "quest", "quest" },
    { "lootall", "chest" }, { "loot", "chest" }, { "pickup", "chest" }, { "picklock", "chest" },
    { "fish", "fishing" }, { "skin", "ore" },
}
local CURSOR_FILES = { "Mine", "GatherHerbs", "Quest", "LootAll", "Pickup", "PickLock", "Fishing", "Interact",
                       "Skin", "Gossip", "Mail", "Speak", "Taxi", "Repair", "Buy", "Innkeeper" }

---------------------------------------------------------------------------
-- What kind of object is it
---------------------------------------------------------------------------
local probe, byFile = nil, nil
local function BuildLookup()
    byFile = {}
    local t = UIParent:CreateTexture()
    for _, name in ipairs(CURSOR_FILES) do
        for _, prefix in ipairs({ "", "Unable" }) do
            t:SetTexture("Interface\\Cursor\\" .. prefix .. name)
            local id = t:GetTexture()
            if id then byFile[id] = { name:lower(), prefix ~= "" } end
        end
    end
    t:SetTexture(nil)
end

local function FromWords(s)
    if type(s) ~= "string" or IsSecret(s) then return nil end
    s = s:lower()
    local blocked = s:find("unable") ~= nil
    for _, w in ipairs(CURSOR_WORDS) do
        if s:find(w[1], 1, true) then return w[2], blocked end
    end
    return "other", blocked
end

-- type ("ore", "herb", ...) and blocked (skill too low) for the soft interact target
local function Classify(unit)
    if not probe then probe = UIParent:CreateTexture(); probe:Hide() end
    if not byFile then BuildLookup() end
    if not (SetUnitCursorTexture and pcall(SetUnitCursorTexture, probe, unit, nil, true)) then return "other", false end
    local tex = probe:GetTexture()
    if tex and not IsSecret(tex) then
        local known = byFile[tex]
        if known then return (FromWords(known[1])), known[2] end
        local kind, blocked = FromWords(tostring(tex))
        if kind ~= "other" then return kind, blocked end
    end
    local atlas = probe.GetAtlas and probe:GetAtlas()
    if atlas and atlas ~= "" then return FromWords(atlas) end
    return "other", false
end

---------------------------------------------------------------------------
-- The sparkle: a soft glow and a few sparks that light up, fade, and come
-- back somewhere else around the object (flattened, as if on the ground)
---------------------------------------------------------------------------
local GLOW = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR = "Interface\\Cooldown\\star4"
local glow                               -- the one sparkle frame (one target at a time)

local function Respawn(spark)
    local r = glow.radius * math.sqrt(math.random())
    local a = math.random() * 2 * math.pi
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", glow, "CENTER", r * math.cos(a), r * math.sin(a) * 0.45)
    local s = glow.sparkSize * (0.6 + math.random() * 0.6)
    spark:SetSize(s, s)
    spark.anim.fade:SetStartDelay(math.random() * 0.8)
    spark.anim:Play()
end

local function NewSpark()
    local s = glow:CreateTexture(nil, "OVERLAY")
    s:SetTexture(STAR)
    s:SetBlendMode("ADD")
    s:SetAlpha(0)
    local g = s:CreateAnimationGroup()
    local up = g:CreateAnimation("Alpha")
    up:SetFromAlpha(0); up:SetToAlpha(1); up:SetDuration(0.35); up:SetOrder(1); up:SetSmoothing("OUT")
    local down = g:CreateAnimation("Alpha")
    down:SetFromAlpha(1); down:SetToAlpha(0); down:SetDuration(0.55); down:SetOrder(2); down:SetSmoothing("IN")
    local spin = g:CreateAnimation("Rotation")
    spin:SetDegrees(90); spin:SetDuration(0.9); spin:SetOrder(1)
    g.fade = up
    g:SetScript("OnFinished", function() if glow:IsShown() then Respawn(s) end end)
    s.anim = g
    return s
end

local function Style()
    if not glow then return end
    local db = M.db
    local size = db.size
    glow:SetSize(size, size)
    glow.radius = size * 0.5
    glow.sparkSize = math.max(6, size * 0.28)
    glow.halo:SetSize(size * 1.4, size * 0.7)
    glow:SetAlpha(db.brightness / 100)
    for i = #glow.sparks + 1, db.sparks do glow.sparks[i] = NewSpark() end
    for i, s in ipairs(glow.sparks) do s.enabled = i <= db.sparks; if not s.enabled then s.anim:Stop(); s:SetAlpha(0) end end
end

local function MakeGlow()
    glow = CreateFrame("Frame", nil, UIParent)
    glow:SetFrameStrata("BACKGROUND")
    glow:Hide()
    glow.halo = glow:CreateTexture(nil, "ARTWORK")
    glow.halo:SetPoint("CENTER")
    glow.halo:SetTexture(GLOW)
    if not glow.halo:GetTexture() then glow.halo:SetTexture(STAR) end     -- in case this client lacks it
    glow.halo:SetBlendMode("ADD")
    local pulse = glow.halo:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0.35); a:SetToAlpha(0.7); a:SetDuration(1.1); a:SetSmoothing("IN_OUT")
    glow.pulse = pulse
    glow.sparks = {}
    Style()
end

local function Paint(color)
    glow.halo:SetVertexColor(color[1], color[2], color[3])
    for _, s in ipairs(glow.sparks) do s:SetVertexColor(color[1], color[2], color[3]) end
end

local function ShowOn(plate, kind, blocked)
    if not glow then MakeGlow() end
    glow:ClearAllPoints()
    if not pcall(glow.SetPoint, glow, "CENTER", plate, "CENTER", 0, M.db.offsetY) then glow:Hide(); return end
    Paint(blocked and BLOCKED or COLOR[kind] or COLOR.other)
    if not glow:IsShown() then
        glow:Show()
        glow.pulse:Play()
        for _, s in ipairs(glow.sparks) do if s.enabled then Respawn(s) end end
    end
end

local function HideGlow()
    if not glow then return end
    glow:Hide()
    glow.pulse:Stop()
    for _, s in ipairs(glow.sparks) do s.anim:Stop(); s:SetAlpha(0) end
end

---------------------------------------------------------------------------
-- Following the soft interact target
---------------------------------------------------------------------------
local function TargetPlate()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("softinteract")
    if plate then return plate end
    -- some clients only hand it out through the visible plates
    for _, p in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
        local token = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
        if token then
            local ok, same = pcall(UnitIsUnit, token, "softinteract")
            if ok and same == true then return p end
        end
    end
end

local previewing = false
local function Refresh()
    if previewing then return end                -- the settings page is showing a sample
    if not M.enabled or not UnitExists("softinteract") then return HideGlow() end
    local plate = TargetPlate()
    if not plate then return HideGlow() end
    local kind, blocked = Classify("softinteract")
    if not M.db.types[kind] then return HideGlow() end
    ShowOn(plate, kind, blocked)
end

---------------------------------------------------------------------------
-- The game settings it needs (saved, and put back when switched off)
---------------------------------------------------------------------------
local CVARS = { "SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetIconGameObject",
                "SoftTargetIconInteract", "SoftTargetInteractRange", "SoftTargetInteractArc" }
local function Wanted(name)
    if name == "SoftTargetInteract" then return "3" end            -- always look for interactables
    if name == "SoftTargetInteractRange" then return tostring(M.db.range) end
    if name == "SoftTargetInteractArc" then return "2" end         -- all around you
    return "1"
end
local pendingCVars = false
local function SetCVars(on)
    if InCombatLockdown() then pendingCVars = true; return end
    pendingCVars = false
    local db = M.db
    for _, name in ipairs(CVARS) do
        local ok, cur = pcall(GetCVar, name)
        if ok and cur ~= nil then
            if on then
                db.saved = db.saved or {}
                if db.saved[name] == nil then db.saved[name] = cur end
                pcall(SetCVar, name, Wanted(name))
            elseif db.saved and db.saved[name] ~= nil then
                pcall(SetCVar, name, db.saved[name])
            end
        end
    end
    if not on then db.saved = nil end
end

local ev, ticker
function M:Setup()
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingCVars then SetCVars(M.enabled) end
            return
        end
        Refresh()
    end)
end

local EVENTS = { "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
                 "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "SKILL_LINES_CHANGED" }
function M:OnEnable()
    for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    SetCVars(true)
    -- the plate can be recycled while you walk: check twice a second while something is targeted
    if not ticker then ticker = C_Timer.NewTicker(0.5, Refresh) end
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Lueur") then
        TT.Print("Interact Glow: Lueur is loaded too. Both change the same game settings: turn one of them off.")
    end
    Refresh()
end
function M:OnDisable()
    for _, e in ipairs(EVENTS) do pcall(ev.UnregisterEvent, ev, e) end
    if ticker then ticker:Cancel(); ticker = nil end
    SetCVars(false)
    HideGlow()
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function Preview(kind)
    if not glow then MakeGlow() end
    previewing = true
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
    Paint(COLOR[kind])
    glow:Show(); glow.pulse:Play()
    for _, s in ipairs(glow.sparks) do if s.enabled then Respawn(s) end end
    C_Timer.After(4, function() previewing = false; Refresh() end)
end

function M:BuildSettings(body, page)
    local db, refreshers, y = M.db, {}, 0
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(TT.C.dim)); h:SetPoint("TOPLEFT", 0, -y); y = y + 20
    end
    Head("What sparkles (click a name to preview its colour)")
    for i, t in ipairs(TYPES) do
        local col = (i - 1) % 2
        local hex = string.format("|cff%02x%02x%02x", t[3][1] * 255, t[3][2] * 255, t[3][3] * 255)
        local cb = TT.Check(body, hex .. t[2] .. "|r", function(v) db.types[t[1]] = v; Refresh() end)
        cb:SetPoint("TOPLEFT", 2 + col * 260, -y)
        cb:HookScript("OnClick", function() Preview(t[1]) end)
        refreshers[#refreshers + 1] = function() cb:SetChecked(db.types[t[1]]) end
        if col == 1 then y = y + 24 end
    end
    y = y + 8
    Head("Look")
    local function Step(text, key, min, max, step, after)
        local s = TT.Stepper(body, text, function() return db[key] end,
            function(v) db[key] = v; Style(); if after then after() end; Preview("ore") end, min, max, step)
        s:SetPoint("TOPLEFT", 0, -y); y = y + 26
        refreshers[#refreshers + 1] = s.Refresh
    end
    Step("Size", "size", 16, 120, 2)
    Step("Height (below the name)", "offsetY", -120, 40, 5)
    Step("Sparks", "sparks", 2, 12, 1)
    Step("Brightness %", "brightness", 20, 100, 5)
    Step("Range (yards)", "range", 5, 40, 1, function() if M.enabled then SetCVars(true) end end)
    local help = TT.Label(body,
        "The game highlights one object at a time: the nearest one in front of you. A grey sparkle\n" ..
        "means your skill is too low for it. This module turns on the game's soft-target settings\n" ..
        "for interactables and puts your own values back when you switch it off. Don't run it\n" ..
        "together with Lueur's glow (both change the same settings).", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 6)
    page.OnPageShow = function() for _, f in ipairs(refreshers) do f() end end
end
