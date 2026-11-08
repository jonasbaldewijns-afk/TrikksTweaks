-- Module: Mouseover Bars
-- Fades bars out and fades them back in while your mouse is over them: the
-- micro menu, the bag bar, the XP / reputation bars, any of the action bars,
-- and the player / target frames. Action bars are protected frames, but changing how see-through a
-- frame is (SetAlpha) is allowed even in combat, so this works everywhere.
local _, TT = ...
local M = TT:RegisterModule("BarFade", {
    title = "Mouseover Bars",
    category = "Interface",
    desc = "Hides the micro menu, bag bar, action bars or player / target frames until you move your mouse over them.",
    defaults = {
        micro = true, bags = true, xp = false, link = true, alpha = 0, speed = 8,
        -- 1.4: action bars and unit frames (all off until you tick them)
        main = false, bar2 = false, bar3 = false, bar4 = false, bar5 = false, bar6 = false, bar7 = false, bar8 = false,
        stance = false, pet = false, player = false, target = false,
        linkBars = false, combatShow = true,
    },
})

-- key -> label, the frames, and the group it belongs to ("menu" bars link
-- with each other, "action" bars link when linkBars is on). An optional 5th
-- entry = the frames to fade, when that isn't the hovered frame itself.
local BARS = {
    { "micro",  "Micro menu (character, spellbook, ... buttons)", function() return { MicroMenuContainer or MicroMenu } end, "menu" },
    { "bags",   "Bag bar",            function() return { BagsBar, BagSlotCluster } end, "menu" },
    -- XP / reputation: Blizzard animates the containers' own opacity (when the
    -- tracked bar changes), so the fade goes on their parent instead
    { "xp",     "XP / reputation bars",
      function() return { MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer } end, "menu",
      function() return { StatusTrackingBarManager } end },
    { "main",   "Action bar 1",       function() return { MainActionBar or MainMenuBar } end, "action" },
    { "bar2",   "Action bar 2",       function() return { MultiBarBottomLeft } end, "action" },
    { "bar3",   "Action bar 3",       function() return { MultiBarBottomRight } end, "action" },
    { "bar4",   "Action bar 4",       function() return { MultiBarRight } end, "action" },
    { "bar5",   "Action bar 5",       function() return { MultiBarLeft } end, "action" },
    { "bar6",   "Action bar 6",       function() return { MultiBar5 } end, "action" },
    { "bar7",   "Action bar 7",       function() return { MultiBar6 } end, "action" },
    { "bar8",   "Action bar 8",       function() return { MultiBar7 } end, "action" },
    { "stance", "Stance bar",         function() return { StanceBar } end, "action" },
    { "pet",    "Pet bar",            function() return { PetActionBar } end, "action" },
    { "player", "Player frame",       function() return { PlayerFrame } end, "unit" },
    { "target", "Target frame",       function() return { TargetFrame } end, "unit" },
}
local current = {}
for _, b in ipairs(BARS) do current[b[1]] = 1 end

-- Each bar's frames, looked up once and kept (looking them up every tick made
-- new tables 30x a second, which the garbage collector then had to clean up).
local frames, fadeFrames = {}, {}
local function Lookup(cache, key, fn)
    local list = cache[key]
    if not list or #list == 0 then
        list = {}
        for _, f in pairs(fn()) do if f then list[#list + 1] = f end end
        cache[key] = list
    end
    return list
end
local function Frames(bar) return Lookup(frames, bar[1], bar[3]) end
local function FadeFrames(bar) return bar[5] and Lookup(fadeFrames, bar[1], bar[5]) or Frames(bar) end

-- Mouse anywhere inside the bar's rectangle (+6px so gaps don't flicker)?
-- One check on the whole bar instead of OnEnter on every button, because a
-- parent frame doesn't get OnEnter when the mouse is on one of its buttons.
local function Hovered(bar)
    local list = Frames(bar)
    for i = 1, #list do
        local f = list[i]
        if f:IsVisible() and f:IsMouseOver(6, -6, -6, 6) then return true end
    end
    return false
end

local function SetBarAlpha(bar, a)
    current[bar[1]] = a
    if bar[1] == "player" and TT.playerFrameHidden then return end   -- Solo Party Frame hides it
    local list = FadeFrames(bar)
    for i = 1, #list do list[i]:SetAlpha(a) end
end

-- The driver polls the mouse (there's no "mouse entered this rectangle"
-- event), but it skips all work while nothing can have changed: same cursor
-- position, same combat / Edit Mode state and no fade still running.
local driver                     -- made in Setup (the first time the module is switched on)
local hover, groupHover = {}, {}          -- reused every tick
local acc, lastX, lastY, lastState, settled = 0, nil, nil, nil, false
local GetCursorPosition, InCombatLockdown, UnitAffectingCombat = GetCursorPosition, InCombatLockdown, UnitAffectingCombat
local abs, min = math.abs, math.min

local function Wake() settled = false end

function M:Setup()
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.03 then return end
        local dt = acc
        acc = 0
        local db = M.db
        local editing = EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive
            and EditModeManagerFrame:IsEditModeActive() or false
        local fighting = db.combatShow and (InCombatLockdown() or UnitAffectingCombat("player")) or false
        local x, y = GetCursorPosition()
        local state = (editing and 1 or 0) + (fighting and 2 or 0)
        if settled and x == lastX and y == lastY and state == lastState then return end
        lastX, lastY, lastState = x, y, state

        -- which bars are hovered, and is any bar of each group hovered?
        wipe(hover); wipe(groupHover)
        for _, bar in ipairs(BARS) do
            if db[bar[1]] and Hovered(bar) then
                hover[bar[1]] = true
                groupHover[bar[4]] = true
            end
        end
        local moving = false
        for _, bar in ipairs(BARS) do
            local key, group = bar[1], bar[4]
            local target = 1
            if db[key] and not editing then
                local linked = (group == "menu" and db.link) or (group == "action" and db.linkBars)
                local show = hover[key] or (linked and groupHover[group])
                    or (fighting and group ~= "menu")                 -- action bars / unit frames: full in combat
                target = show and 1 or db.alpha / 100
            end
            local cur = current[key]
            if abs(cur - target) > 0.01 then
                SetBarAlpha(bar, cur + (target - cur) * min(1, dt * db.speed))   -- ease towards target
                moving = true
            elseif cur ~= target then
                SetBarAlpha(bar, target)
            end
        end
        settled = not moving
    end)
    driver:Hide()

    -- frames can be (re)created on loading screens: look them up again then
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:SetScript("OnEvent", function() wipe(frames); wipe(fadeFrames); Wake() end)
end

function M:OnEnable() Wake(); driver:Show() end
function M:OnDisable() if driver then driver:Hide() end; for _, bar in ipairs(BARS) do SetBarAlpha(bar, 1) end end

function M:BuildSettings(body, page)
    local db, checks = M.db, {}
    local function Check(text, key, x, y)
        local cb = TT.Check(body, text, function(v)
            db[key] = v; Wake()
            if not v and M.enabled then for _, bar in ipairs(BARS) do if bar[1] == key then SetBarAlpha(bar, 1) end end end
        end)
        cb:SetPoint("TOPLEFT", x, y)
        checks[key] = cb
    end
    local function Head(text, y)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(TT.C.dim)); h:SetPoint("TOPLEFT", 0, y)
    end
    Head("Menus", -2)
    Check("Fade the micro menu (character, spellbook, ... buttons)", "micro", 2, -20)
    Check("Fade the bag bar", "bags", 2, -44)
    Check("Fade the XP / reputation bars", "xp", 2, -68)
    Check("Hovering one of these shows all of them", "link", 2, -92)
    Head("Action bars and unit frames", -124)
    local y = -142
    local i = 0
    for _, bar in ipairs(BARS) do
        if bar[4] ~= "menu" then
            local col = i % 2
            Check(bar[2], bar[1], 2 + col * 280, y)
            if col == 1 then y = y - 24 end
            i = i + 1
        end
    end
    if i % 2 == 1 then y = y - 24 end
    Check("Hovering one action bar shows all of them", "linkBars", 2, y - 6)
    Check("Show action bars and unit frames fully in combat", "combatShow", 2, y - 30)
    local alpha = TT.Stepper(body, "Faded opacity %", function() return db.alpha end, function(v) db.alpha = v; Wake() end, 0, 100, 5)
    alpha:SetPoint("TOPLEFT", 0, y - 62)
    local speed = TT.Stepper(body, "Fade speed", function() return db.speed end, function(v) db.speed = v end, 2, 20, 1)
    speed:SetPoint("TOPLEFT", alpha, "BOTTOMLEFT", 0, -2)
    local help = TT.Label(body, "0% = invisible until you hover (the buttons still work: keybinds always do).\n" ..
        "Everything shows fully while Edit Mode is open. Turn EnhanceQoL's mouseover\n" ..
        "options for the same bars off if you still use it.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", speed, "BOTTOMLEFT", 0, -14)
    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        alpha.Refresh(); speed.Refresh()
    end
end
