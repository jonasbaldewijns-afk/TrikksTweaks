-- Module: Party Position
-- Choose where YOUR frame sits in the raid-style party frames.
--
-- How (and why this way): on Midnight-era clients, health values are "secret"
-- and only Blizzard's own, untainted code may compare them. Asking Blizzard to
-- re-sort the party frames from addon code makes its refresh run "tainted",
-- which breaks it. So we never call Blizzard's party code. Instead:
--   1. right after Blizzard lays the frames out, we note where each slot is,
--   2. then we move the frames themselves so you land in the slot you chose.
-- Moving frames doesn't run any Blizzard Lua code, so nothing gets tainted.
-- Party frames are protected in combat, so moving waits until combat ends.
local _, TT = ...
local M = TT:RegisterModule("PartyPosition", {
    title = "Party Position",
    category = "Interface",
    desc = "Choose where your own frame sits in the raid-style party frames (top, bottom, or a slot in between).",
    defaults = { position = 1 },        -- 0 = Blizzard default, 1-4 = slot, -1 = bottom
})

local slots = {}        -- slot positions (relative to the party container) from Blizzard's last layout
local placedAt = {}     -- [frame] = position WE gave it, to tell our layout from Blizzard's
local pending = false

local function FrameSortLoaded()
    local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return f and f("FrameSort") or false
end

local function Active()
    return M.enabled and M.db.position ~= 0 and not FrameSortLoaded() and not IsInRaid()
end

-- Party member frames in Blizzard's order (only the ones in use).
local function Members()
    local list = {}
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if f and f:IsShown() and f.unit then list[#list + 1] = f end
    end
    return list
end

-- Read where Blizzard put each frame. Only valid right after Blizzard's own layout.
local function RememberSlots()
    if not CompactPartyFrame then return end
    local ok, cl, ct = pcall(function() return CompactPartyFrame:GetLeft(), CompactPartyFrame:GetTop() end)
    if not ok or not cl or not ct then return end
    local members, found, ours = Members(), {}, true
    for i, f in ipairs(members) do
        local okF, l, t = pcall(function() return f:GetLeft(), f:GetTop() end)
        if not (okF and l and t) then return end
        found[i] = { l - cl, t - ct }
        local mine = placedAt[f]
        if not (mine and math.abs(mine[1] - found[i][1]) < 0.5 and math.abs(mine[2] - found[i][2]) < 0.5) then
            ours = false
        end
    end
    -- Every frame is still exactly where WE put it: that's not Blizzard's layout, keep the old slots.
    if ours and #slots >= #members then return end
    wipe(slots); wipe(placedAt)
    for i, pos in ipairs(found) do slots[i] = pos end
end

local function Place(order)
    for i, f in ipairs(order) do
        local s = slots[i]
        if s then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", CompactPartyFrame, "TOPLEFT", s[1], s[2])
            placedAt[f] = { s[1], s[2] }
        end
    end
end

local function Apply()
    if not CompactPartyFrame or not CompactPartyFrame:IsShown() then return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    local members = Members()
    if #members < 2 or #slots < #members then return end

    local order = {}
    if Active() then
        local player
        for _, f in ipairs(members) do
            if f.unit == "player" then player = f else order[#order + 1] = f end
        end
        if not player then return end
        local pos = M.db.position
        if pos == -1 or pos > #order + 1 then pos = #order + 1 end
        table.insert(order, pos, player)
    else
        order = members                  -- put everyone back in Blizzard's order
    end
    Place(order)
end

-- Run right after Blizzard (re)builds the party frames. hooksecurefunc runs our
-- code AFTER Blizzard's has finished, so Blizzard's own run stays untainted.
local hooked = false
local function Hook()
    if hooked or not CompactPartyFrame then return end
    hooked = true
    local function After()
        RememberSlots()
        Apply()
    end
    for _, method in ipairs({ "RefreshMembers", "UpdateLayout" }) do
        if CompactPartyFrame[method] then hooksecurefunc(CompactPartyFrame, method, After) end
    end
end

function M:Setup()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        Hook()
        if event == "PLAYER_REGEN_ENABLED" and not pending then return end
        -- next frame: after Blizzard's own handler for the same event
        C_Timer.After(0, function() RememberSlots(); Apply() end)
    end)
end

function M:OnEnable() Hook(); RememberSlots(); Apply() end
function M:OnDisable() Apply() end

function M:BuildSettings(body, page)
    local l = TT.Label(body, "Where should your frame be?")
    l:SetPoint("TOPLEFT")
    local choices = {
        { 0, "Blizzard default (don't change anything)" },
        { 1, "Top (1st)" }, { 2, "2nd" }, { 3, "3rd" }, { 4, "4th" },
        { -1, "Bottom (last)" },
    }
    local radios = {}
    local function Refresh()
        for _, r in ipairs(radios) do r:SetChecked(M.db.position == r.value) end
    end
    for i, c in ipairs(choices) do
        local cb = TT.Check(body, c[2], function()
            M.db.position = c[1]; Refresh(); if M.enabled then Apply() end
            if InCombatLockdown() then TT.Print("party order will update after combat.") end
        end)
        cb:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -8 - (i - 1) * 24)
        cb.value = c[1]
        radios[i] = cb
    end

    local state = TT.Label(body, "", "GameFontNormalSmall")
    state:SetWidth(540)
    state:SetPoint("TOPLEFT", radios[#radios], "BOTTOMLEFT", 0, -16)

    local help = TT.Label(body,
        "Only works with raid-style party frames (Edit Mode > Party Frames >\n" ..
        "\"Use Raid-Style Party Frames\"). With fewer people in the group, a slot\n" ..
        "that doesn't exist yet puts you at the bottom.\n\n" ..
        "Party frames are protected during combat: if the group changes mid-fight,\n" ..
        "your position is fixed as soon as combat ends.",
        "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", state, "BOTTOMLEFT", 0, -10)

    page.OnPageShow = function()
        Refresh()
        local raidStyle = EditModeManagerFrame and EditModeManagerFrame.UseRaidStylePartyFrames
            and EditModeManagerFrame:UseRaidStylePartyFrames()
        if FrameSortLoaded() then
            state:SetText("|cffff6666FrameSort is loaded, so this module is paused. Use one or the other.|r")
        else
            state:SetText(raidStyle and "|cff33ff99Raid-style party frames are on.|r"
                or "|cffff6666Raid-style party frames are off - turn them on in Edit Mode.|r")
        end
    end
end
