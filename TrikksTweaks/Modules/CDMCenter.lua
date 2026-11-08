-- Module: Centre Tracked Buffs
-- Blizzard's Cooldown Manager ("Tracked Buffs") is the one thing allowed to see
-- buffs that are secret in combat. But with "Hide when inactive" each of its
-- icons keeps a fixed slot, so gaps appear where inactive buffs would be. This
-- re-places the visible icons as one row growing from the centre every time
-- one appears or disappears. It only moves Blizzard's icons; it never reads
-- the buffs themselves.
-- Safety: the hooks only schedule the re-centring for the next frame, so none
-- of our code runs in the middle of Blizzard's own (secret-handling) code.
-- Hooks can't be removed again, so turning it off makes them do nothing, and
-- a /reload puts Blizzard's own layout back.
local _, TT = ...
local IsSecret = TT.IsSecret

local M = TT:RegisterModule("CDMCenter", {
    title = "Centre Tracked Buffs",
    category = "Interface",
    desc = "Keep Blizzard's Cooldown Manager buff row (Tracked Buffs) centred, without gaps for inactive buffs.",
})

local viewer, container
local hooked = setmetatable({}, { __mode = "k" })
local pending = false
local lastSize, lastScale              -- icon size / scale from the last time they were readable

-- Blizzard's icons in their own order
local function Items()
    local list = {}
    if not (viewer and viewer.itemFramePool) then return list end
    for f in viewer.itemFramePool:EnumerateActive() do list[#list + 1] = f end
    table.sort(list, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)
    return list
end

local function Recenter()
    pending = false
    if not (M.enabled and viewer and container) then return end
    local shown = {}
    for _, f in ipairs(Items()) do
        local s = f:IsShown()
        if IsSecret(s) then return end      -- can't tell what's shown: leave Blizzard's layout alone
        if s then shown[#shown + 1] = f end
    end
    local n = #shown
    if n == 0 then return end
    local horizontal = container.isHorizontal ~= false
    -- icons are scaled (Edit Mode "icon size"); their offsets are in their own
    -- scaled units, the padding is in the row's units
    -- In combat the icons' size and scale are secret (can't be used in maths),
    -- so use the last values we could read; with none yet, leave Blizzard's layout.
    local first = shown[1]
    local scale = first:GetScale()
    local size = horizontal and first:GetWidth() or first:GetHeight()
    if IsSecret(scale) or IsSecret(size) or not scale or not size then
        if not lastSize then return end
        scale, size = lastScale, lastSize
    else
        if scale <= 0 then scale = 1 end
        lastScale, lastSize = scale, size
    end
    local gap = (container.childXPadding or 0) / scale
    local total = n * size + (n - 1) * gap
    for i, f in ipairs(shown) do
        local offset = -total / 2 + size / 2 + (i - 1) * (size + gap)
        f:ClearAllPoints()
        if horizontal then f:SetPoint("CENTER", container, "CENTER", offset, 0)
        else f:SetPoint("CENTER", container, "CENTER", 0, -offset) end
    end
end

local function Queue()
    if pending or not M.enabled then return end
    pending = true
    C_Timer.After(0, Recenter)
end

-- every icon (they come from a pool, new ones can appear): re-centre when it shows / hides
local function HookItems()
    for _, f in ipairs(Items()) do
        if not hooked[f] then
            hooked[f] = true
            for _, fn in ipairs({ "UpdateShownState", "SetShown", "Show", "Hide" }) do
                if type(f[fn]) == "function" then hooksecurefunc(f, fn, Queue) end
            end
        end
    end
end

local function Attach()
    if viewer or not BuffIconCooldownViewer then return end
    viewer = BuffIconCooldownViewer
    container = viewer.GetItemContainerFrame and viewer:GetItemContainerFrame() or viewer
    -- Blizzard rebuilds the row (new buffs tracked, Edit Mode changes): hook the new icons, re-centre
    if type(viewer.RefreshLayout) == "function" then
        hooksecurefunc(viewer, "RefreshLayout", function() HookItems(); Queue() end)
    end
    if type(container.Layout) == "function" then hooksecurefunc(container, "Layout", Queue) end
    HookItems()
    Queue()
end

local function Availability()
    if not BuffIconCooldownViewer then
        return "|cffff6666Blizzard's Cooldown Manager isn't loaded on this client.|r"
    end
    if C_CooldownViewer and C_CooldownViewer.IsCooldownViewerAvailable then
        local ok, available, reason = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
        if ok and available == false then
            return "|cffff6666Cooldown Manager not available: " .. tostring(reason or "?") .. "|r"
        end
    end
    return "|cff33ff99Cooldown Manager found.|r"
end

function M:Setup()
    -- Blizzard_CooldownViewer may load after us
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function()
        if M.enabled then Attach(); HookItems(); Queue() end
    end)
end

function M:OnEnable() Attach(); HookItems(); Queue() end
function M:OnDisable()
    if viewer then TT.Print("type /reload to put Blizzard's own Tracked Buffs layout back.") end
end

function M:BuildSettings(body, page)
    local status = TT.Label(body, "", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 2, 0)

    local info = TT.Label(body,
        "Why: in combat Blizzard hides most buffs from addons, so no addon can show a\n" ..
        "buff you gain during a fight. Blizzard's own Cooldown Manager can. This keeps\n" ..
        "its Tracked Buffs row centred: it grows from the middle, without gaps.\n\n" ..
        "How to set it up:\n" ..
        "1. Open the Cooldown Manager (button below) and put the buffs you want\n" ..
        "    under Tracked Buffs.\n" ..
        "2. Esc > Edit Mode > click Tracked Buffs: turn on \"Hide when inactive\"\n" ..
        "    (otherwise every icon always shows and there is nothing to centre).\n" ..
        "3. Still in Edit Mode, put the Tracked Buffs row where you want its centre.\n\n" ..
        "Only Blizzard's icons are moved; their look, size and timers stay Blizzard's\n" ..
        "(set in Edit Mode). Turning this off needs a /reload.", "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -12)

    local open = TT.Button(body, "Open Cooldown Manager", 180, function()
        if InCombatLockdown() then TT.Print("not during combat."); return end
        if CooldownViewerSettings and CooldownViewerSettings.TogglePanel then
            CooldownViewerSettings:TogglePanel()
        else
            TT.Print("couldn't find Blizzard's Cooldown Manager settings.")
        end
    end)
    open:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -14)

    page.OnPageShow = function() status:SetText(Availability()) end
end
