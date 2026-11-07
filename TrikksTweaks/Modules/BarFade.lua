-- Module: Mouseover Bars
-- Fades the micro menu (character/spellbook/... buttons) and the bag bar out,
-- and fades them back in while your mouse is over them.
local _, TT = ...
local M = TT:RegisterModule("BarFade", {
    title = "Mouseover Bars",
    category = "Interface",
    desc = "Hides the micro menu and bag bar until you move your mouse over them.",
    defaults = { micro = true, bags = true, link = true, alpha = 0, speed = 8 },
})

-- the frames that make up each bar (bag slots can live in their own cluster)
local BARS = {
    micro = function() return { MicroMenuContainer or MicroMenu } end,
    bags  = function() return { BagsBar, BagSlotCluster } end,
}
local current = { micro = 1, bags = 1 }

local function Frames(key)
    local list = {}
    for _, f in ipairs(BARS[key]()) do if f then list[#list + 1] = f end end
    return list
end

-- Mouse anywhere inside the bar's rectangle (+6px so gaps don't flicker)?
-- One check on the whole bar instead of OnEnter on every button, because a
-- parent frame doesn't get OnEnter when the mouse is on one of its buttons.
local function Hovered(key)
    for _, f in ipairs(Frames(key)) do
        if f:IsVisible() and f:IsMouseOver(6, -6, -6, 6) then return true end
    end
    return false
end

local function SetBarAlpha(key, a)
    current[key] = a
    for _, f in ipairs(Frames(key)) do f:SetAlpha(a) end
end

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.03 then return end
    local dt = acc
    acc = 0
    local db = M.db
    local editing = EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive
        and EditModeManagerFrame:IsEditModeActive()
    local hover = { micro = db.micro and Hovered("micro"), bags = db.bags and Hovered("bags") }
    local either = hover.micro or hover.bags
    for key in pairs(BARS) do
        local target = 1
        if db[key] and not editing then
            target = (hover[key] or (db.link and either)) and 1 or db.alpha / 100
        end
        local cur = current[key]
        if math.abs(cur - target) > 0.01 then
            SetBarAlpha(key, cur + (target - cur) * math.min(1, dt * db.speed))   -- ease towards target
        elseif cur ~= target then
            SetBarAlpha(key, target)
        end
    end
end)
driver:Hide()

function M:OnEnable() driver:Show() end
function M:OnDisable() driver:Hide(); for key in pairs(BARS) do SetBarAlpha(key, 1) end end

function M:BuildSettings(body, page)
    local db, checks = M.db, {}
    local function Check(text, key, y)
        local cb = TT.Check(body, text, function(v) db[key] = v; if not v and BARS[key] then SetBarAlpha(key, 1) end end)
        cb:SetPoint("TOPLEFT", 2, y)
        checks[key] = cb
    end
    Check("Fade the micro menu (character, spellbook, ... buttons)", "micro", -4)
    Check("Fade the bag bar", "bags", -28)
    Check("Hovering one bar shows both", "link", -52)
    local alpha = TT.Stepper(body, "Faded opacity %", function() return db.alpha end, function(v) db.alpha = v end, 0, 100, 5)
    alpha:SetPoint("TOPLEFT", 0, -84)
    local speed = TT.Stepper(body, "Fade speed", function() return db.speed end, function(v) db.speed = v end, 2, 20, 1)
    speed:SetPoint("TOPLEFT", alpha, "BOTTOMLEFT", 0, -2)
    local help = TT.Label(body, "0% = invisible until you hover. Bars show fully while Edit Mode is open.\n" ..
        "Turn EnhanceQoL's mouseover option for these bars off if you still use it.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", speed, "BOTTOMLEFT", 0, -14)
    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        alpha.Refresh(); speed.Refresh()
    end
end
