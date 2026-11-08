-- Module: Camera & Visuals
-- Game settings (CVars) for a further camera, no screen glow, no full-screen
-- effects and lighter weather. Your original values are remembered and put
-- back when you turn an option (or the module) off.
local _, TT = ...
local M = TT:RegisterModule("CameraVisuals", {
    title = "Camera & Visuals",
    category = "System",
    desc = "Further camera zoom, no screen glow, no full-screen effects, adjustable weather density.",
    defaults = { zoom = true, zoom10 = 26, noGlow = false, noEffects = false, weather = false, weatherLevel = 1, orig = {} },
})

local function Get(name) local ok, v = pcall(C_CVar.GetCVar, name); return ok and v or nil end
local function Set(name, value)
    if Get(name) == nil then return end                       -- this client doesn't have it
    if M.db.orig[name] == nil then M.db.orig[name] = Get(name) end   -- remember your own value once
    pcall(C_CVar.SetCVar, name, tostring(value))
end
local function Restore(name)
    if M.db.orig[name] ~= nil then pcall(C_CVar.SetCVar, name, M.db.orig[name]); M.db.orig[name] = nil end
end

local GROUPS = {
    zoom = { "cameraDistanceMaxZoomFactor" },
    noGlow = { "ffxGlow" },
    noEffects = { "ffxDeath", "ffxNether", "ffxVenari", "ffxLingeringVenari" },
    weather = { "weatherDensity" },
}

local function Apply()
    if InCombatLockdown() then return end
    local db = M.db
    for key, cvars in pairs(GROUPS) do
        for _, cvar in ipairs(cvars) do
            if M.enabled and db[key] then
                if key == "zoom" then Set(cvar, db.zoom10 / 10)
                elseif key == "weather" then Set(cvar, db.weatherLevel)
                else Set(cvar, 0) end
            else
                Restore(cvar)
            end
        end
    end
end

function M:Setup()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() if M.enabled then Apply() end end)
end

function M:OnEnable() Apply() end
function M:OnDisable() Apply() end

function M:BuildSettings(body, page)
    local db, checks, steps, y = M.db, {}, {}, 0
    local function Check(key, text)
        local cb = TT.Check(body, text, function(v) db[key] = v; if M.enabled then Apply() end end)
        cb:SetPoint("TOPLEFT", 2, -y); checks[key] = cb; y = y + 24
    end
    local function Step(text, key, min, max, step)
        local s = TT.Stepper(body, text, function() return db[key] end, function(v) db[key] = v; if M.enabled then Apply() end end, min, max, step)
        s:SetPoint("TOPLEFT", 20, -y); steps[#steps + 1] = s; y = y + 26
    end
    Check("zoom", "Further camera zoom")
    Step("Max zoom factor (x10)", "zoom10", 10, 40, 1)
    Check("noGlow", "No screen glow (cleaner, sharper image)")
    Check("noEffects", "No full-screen effects (death, nether, ...)")
    Check("weather", "Change weather density")
    Step("Weather (0 = none, 3 = full)", "weatherLevel", 0, 3, 1)
    local help = TT.Label(body,
        "Zoom factor 26 = 2.6, the usual maximum; the game ignores higher values\n" ..
        "if it doesn't allow them. Turning an option off restores your old value.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y - 8)
    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        for _, s in ipairs(steps) do s.Refresh() end
    end
end
