-- Module: Sound Muting
-- Mute emote sounds while you're resting (cities / inns), and any sound
-- files you add to your own mute list.
local _, TT = ...
local M = TT:RegisterModule("SoundMute", {
    title = "Sound Muting",
    category = "System",
    desc = "Mute emote sounds while resting, plus your own list of muted sound files.",
    defaults = { emotesResting = true, muted = {}, origEmotes = nil },
})

-- Emote sounds (cheers, laughs, ...) are one game setting; switch it by rest state.
local EMOTE_CVAR = "Sound_EnableEmoteSounds"
local function ApplyEmotes()
    local ok, cur = pcall(C_CVar.GetCVar, EMOTE_CVAR)
    if not ok or cur == nil then return end
    if M.enabled and M.db.emotesResting then
        if M.db.origEmotes == nil then M.db.origEmotes = cur end
        C_CVar.SetCVar(EMOTE_CVAR, IsResting() and "0" or M.db.origEmotes)
    elseif M.db.origEmotes ~= nil then
        C_CVar.SetCVar(EMOTE_CVAR, M.db.origEmotes)
        M.db.origEmotes = nil
    end
end

-- MuteSoundFile only lasts for this session, so the list is applied at every login.
local applied = {}
local function ApplyMutes()
    local want = {}
    if M.enabled then for _, id in ipairs(M.db.muted) do want[id] = true end end
    for id in pairs(applied) do
        if not want[id] then UnmuteSoundFile(id); applied[id] = nil end
    end
    for id in pairs(want) do
        if not applied[id] then MuteSoundFile(id); applied[id] = true end
    end
end

function M:Setup()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_UPDATE_RESTING")
    ev:SetScript("OnEvent", function(_, event)
        if not M.enabled then return end
        ApplyEmotes()
        if event == "PLAYER_ENTERING_WORLD" then ApplyMutes() end
    end)
end

function M:OnEnable() ApplyEmotes(); ApplyMutes() end
function M:OnDisable() ApplyEmotes(); ApplyMutes() end

function M:BuildSettings(body, page)
    local db = M.db
    local emotes = TT.Check(body, "Mute emote sounds while resting (cities, inns)", function(v) db.emotesResting = v; ApplyEmotes() end)
    emotes:SetPoint("TOPLEFT", 2, -4)
    local l = TT.Label(body, "MUTED SOUND FILES", "GameFontNormalSmall")
    l:SetTextColor(unpack(TT.C.dim))
    l:SetPoint("TOPLEFT", 0, -40)
    local list = TT.IDList(body, 360, 220, db.muted, function(id) return "Sound file " .. id end, ApplyMutes)
    list:SetPoint("TOPLEFT", 0, -60)
    local help = TT.Label(body,
        "Add a sound's file ID to mute it. Find IDs at wago.tools/files\n" ..
        "(search for the sound's name, e.g. a mount).", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -290)
    page.OnPageShow = function() emotes:SetChecked(db.emotesResting); list.Refresh() end
end
