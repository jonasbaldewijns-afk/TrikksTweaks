-- Module: Chat
-- Fade, history between logins, tidier chat frames (no side buttons, edit box
-- on top, arrow keys, unclamped), class-coloured names, a copy window and a
-- few spam filters.
local _, TT = ...
local M = TT:RegisterModule("Chat", {
    title = "Chat",
    category = "Quality of Life",
    desc = "Fade, history between logins, hidden buttons, edit box on top, copy window, class colours and spam filters.",
    defaults = {
        fade = true, fadeTime = 30, history = true, lines = 50, saved = {},
        hideButtons = true, editTop = true, arrowKeys = true, unclamp = true, classColors = true,
        copyChat = true, filterDrunk = true, filterDuel = true, filterSpellLinks = false,
    },
})
local IsSecret = TT.IsSecret

local function Frames()
    local list = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then list[i] = cf end
    end
    return list
end

local hidden = CreateFrame("Frame")
hidden:Hide()
local function Stash(f, hide)
    if not f then return end
    f.ttParent = f.ttParent or f:GetParent()
    f:SetParent(hide and hidden or f.ttParent)
end

---------------------------------------------------------------------------
-- Fade (Blizzard's chat frames can fade by themselves; we just switch it on)
---------------------------------------------------------------------------
local function ApplyFade()
    local on = M.enabled and M.db.fade
    for _, cf in pairs(Frames()) do
        cf:SetFading(on)
        if on then cf:SetTimeVisible(M.db.fadeTime) end
    end
end

---------------------------------------------------------------------------
-- Frame tweaks
---------------------------------------------------------------------------
local CLASS_COLOR_TYPES = { "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "WHISPER", "WHISPER_INFORM",
    "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }
for i = 1, 20 do CLASS_COLOR_TYPES[#CLASS_COLOR_TYPES + 1] = "CHANNEL" .. i end

local function ApplyTweaks()
    local db, on = M.db, M.enabled
    -- side buttons (menu, channels, social/quick join, voice)
    for _, b in ipairs({ ChatFrameMenuButton, ChatFrameChannelButton, QuickJoinToastButton,
                         ChatFrameToggleVoiceDeafenButton, ChatFrameToggleVoiceMuteButton, TextToSpeechButton }) do
        Stash(b, on and db.hideButtons)
    end
    for i, cf in pairs(Frames()) do
        Stash(cf.buttonFrame or _G["ChatFrame" .. i .. "ButtonFrame"], on and db.hideButtons)
        local eb = cf.editBox or _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            if on and db.editTop then
                eb:ClearAllPoints()
                eb:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -5, 4)
                eb:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 5, 4)
            end
            -- arrow keys move the cursor without holding Alt
            eb:SetAltArrowKeyMode(not (on and db.arrowKeys))
        end
        if on and db.unclamp then
            cf:SetClampRectInsets(0, 0, 0, 0)
            cf:SetClampedToScreen(false)
        end
    end
    -- class colours: Blizzard's own per-chat-type setting (saved by the game itself)
    if on and db.classColors and SetChatColorNameByClass then
        for _, t in ipairs(CLASS_COLOR_TYPES) do pcall(SetChatColorNameByClass, t, true) end
    end
end

---------------------------------------------------------------------------
-- History between logins
---------------------------------------------------------------------------
local charKey = UnitName("player") .. "-" .. (GetRealmName() or "")
local live, restoring = {}, false

local function Remember(index, text, r, g, b)
    if restoring or not (M.enabled and M.db.history) then return end
    if type(text) ~= "string" or IsSecret(text) or text == "" then return end
    local list = live[index]
    if not list then list = {}; live[index] = list end
    list[#list + 1] = { text, r or 1, g or 1, b or 1 }
    if #list > M.db.lines then table.remove(list, 1) end
end

local function HookFrames()
    for i, cf in pairs(Frames()) do
        if not cf.ttHistoryHooked then
            cf.ttHistoryHooked = true
            hooksecurefunc(cf, "AddMessage", function(_, text, r, g, b) Remember(i, text, r, g, b) end)
        end
    end
end

local function RestoreHistory()
    local saved = M.db.saved[charKey]
    if not saved then return end
    restoring = true
    for i, cf in pairs(Frames()) do
        local lines = saved[i]
        if lines and #lines > 0 then
            for _, line in ipairs(lines) do
                cf:AddMessage(line[1], line[2] * 0.6, line[3] * 0.6, line[4] * 0.6)
                live[i] = live[i] or {}
                live[i][#live[i] + 1] = line
            end
            cf:AddMessage("|cff555555--- previous session ---|r")
        end
    end
    restoring = false
end

---------------------------------------------------------------------------
-- Copy window: the selected chat tab as plain, selectable text
---------------------------------------------------------------------------
local copyWin = TT.Window("TrikksTweaksCopyChat", 620, 420, "Copy chat")
copyWin:SetFrameStrata("DIALOG")
local copyScroll = TT.Scroll(copyWin)
copyScroll:SetPoint("TOPLEFT", 12, -36); copyScroll:SetPoint("BOTTOMRIGHT", -18, 12)
local copyEdit = CreateFrame("EditBox", nil, copyScroll)
copyEdit:SetMultiLine(true)
copyEdit:SetAutoFocus(false)
copyEdit:SetFontObject("ChatFontNormal")
copyEdit:SetWidth(580)
copyEdit:SetScript("OnEscapePressed", function() copyWin:Hide() end)
copyScroll:SetScrollChild(copyEdit)

-- strip colour codes, icons and link markup so the copied text is clean
local function Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return text
end

local function OpenCopy()
    local cf = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    local out = {}
    if cf.GetNumMessages and cf.GetMessageInfo then
        for i = 1, cf:GetNumMessages() do
            local text = cf:GetMessageInfo(i)
            if type(text) == "string" and not IsSecret(text) then out[#out + 1] = Plain(text) end
        end
    end
    copyEdit:SetText(table.concat(out, "\n"))
    copyWin:Show()
    copyEdit:SetFocus()
    copyEdit:HighlightText()
    C_Timer.After(0, function() copyScroll:SetVerticalScroll(copyScroll:GetVerticalScrollRange()) end)
end

local copyBtn = TT.Button(UIParent, "C", 18, OpenCopy)
copyBtn:SetSize(18, 18)
copyBtn:SetAlpha(0.35)
copyBtn:HookScript("OnEnter", function(self)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Copy chat"); GameTooltip:Show()
end)
copyBtn:HookScript("OnLeave", function(self) self:SetAlpha(0.35); GameTooltip:Hide() end)
copyBtn:Hide()

local function ApplyCopy()
    local on = M.enabled and M.db.copyChat
    copyBtn:SetShown(on)
    if on and ChatFrame1 then
        copyBtn:ClearAllPoints()
        copyBtn:SetPoint("TOPRIGHT", ChatFrame1, "TOPRIGHT", 2, 2)
        copyBtn:SetFrameStrata("MEDIUM")
    end
end

SLASH_TTCOPYCHAT1 = "/copychat"
SlashCmdList.TTCOPYCHAT = function() if M.enabled then OpenCopy() end end

---------------------------------------------------------------------------
-- Spam filters
---------------------------------------------------------------------------
-- Blizzard's own message formats ("%s looks tipsy.") turned into search patterns
local function ToPattern(fmt)
    fmt = fmt:gsub("%%%d%$s", "%%s")                            -- "%1$s" -> "%s"
    fmt = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")          -- escape special characters
    fmt = fmt:gsub("%%s", ".+")                                 -- "%s" -> "anything"
    return "^" .. fmt .. "$"
end
local function Patterns(names)
    local out = {}
    for _, n in ipairs(names) do if type(_G[n]) == "string" then out[#out + 1] = ToPattern(_G[n]) end end
    return out
end
local DRUNK = Patterns({ "DRUNK_MESSAGE_OTHER1", "DRUNK_MESSAGE_OTHER2", "DRUNK_MESSAGE_OTHER3", "DRUNK_MESSAGE_OTHER4",
    "DRUNK_MESSAGE_ITEM_OTHER1", "DRUNK_MESSAGE_ITEM_OTHER2", "DRUNK_MESSAGE_ITEM_OTHER3", "DRUNK_MESSAGE_ITEM_OTHER4" })
local DUEL = Patterns({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" })

local function Matches(msg, list)
    for _, pat in ipairs(list) do if msg:find(pat) then return true end end
end

-- A filter returns true to hide the message. Secret messages are never touched.
local function SystemFilter(_, _, msg)
    if not M.enabled or type(msg) ~= "string" or IsSecret(msg) then return false end
    if M.db.filterDrunk and Matches(msg, DRUNK) then return true end
    if M.db.filterDuel and Matches(msg, DUEL) then return true end
    return false
end
local function SpellLinkFilter(_, _, msg, sender)
    if not (M.enabled and M.db.filterSpellLinks) or type(msg) ~= "string" or IsSecret(msg) then return false end
    if sender and not IsSecret(sender) and Ambiguate(sender, "none") == UnitName("player") then return false end
    return msg:find("|Hspell:") ~= nil
end

local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if AddFilter then
    AddFilter("CHAT_MSG_SYSTEM", SystemFilter)
    for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE" }) do AddFilter(e, SpellLinkFilter) end
end

---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not M.enabled then return end
        ApplyFade(); ApplyTweaks(); ApplyCopy()
        if M.db.history then RestoreHistory() end
        HookFrames()
    elseif event == "PLAYER_LOGOUT" and M.enabled and M.db.history then
        local out = {}
        for i, list in pairs(live) do
            local from = math.max(1, #list - M.db.lines + 1)
            out[i] = {}
            for n = from, #list do out[i][#out[i] + 1] = list[n] end
        end
        M.db.saved[charKey] = out
    end
end)

StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] = StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] or {
    text = "%s\n\nReload your UI now?",
    button1 = RELOADUI or "Reload", button2 = LATER or "Later",
    OnAccept = function() C_UI.Reload() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function M:OnEnable() if IsLoggedIn() then ApplyFade(); ApplyTweaks(); ApplyCopy(); HookFrames() end end
function M:OnDisable()
    ApplyFade(); ApplyTweaks(); ApplyCopy()
    StaticPopup_Show("TRIKKSTWEAKS_RELOAD", "Chat module turned off. A reload puts the edit box and clamping back.")
end

function M:BuildSettings(body, page)
    local db, checks, steppers, y = M.db, {}, {}, 0
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(TT.C.dim)); h:SetPoint("TOPLEFT", 0, -y); y = y + 20
    end
    local function Check(key, text, indent, after)
        local cb = TT.Check(body, text, function(v) db[key] = v; if after then after() end end)
        cb:SetPoint("TOPLEFT", 2 + (indent and 20 or 0), -y)
        checks[key] = cb
        y = y + 24
    end
    local function Step(text, key, min, max, step, after)
        local s = TT.Stepper(body, text, function() return db[key] end,
            function(v) db[key] = v; if after then after() end end, min, max, step)
        s:SetPoint("TOPLEFT", 20, -y)
        steppers[#steppers + 1] = s
        y = y + 26
    end
    local function Reload() TT.Print("this change fully applies after a /reload.") end

    Head("Fade & history")
    Check("fade", "Fade chat text", nil, ApplyFade)
    Step("Fade after (seconds)", "fadeTime", 5, 300, 5, ApplyFade)
    Check("history", "Keep chat history between logins")
    Step("Lines per tab", "lines", 10, 200, 10)
    local clear = TT.Button(body, "Clear saved history", 140, function()
        wipe(db.saved); wipe(live); TT.Print("chat history cleared.")
    end)
    clear:SetPoint("TOPLEFT", 20, -y); y = y + 32

    Head("Chat frames")
    Check("hideButtons", "Hide the chat side buttons", nil, function() ApplyTweaks(); if not db.hideButtons then Reload() end end)
    Check("editTop", "Edit box above the chat", nil, function() ApplyTweaks(); if not db.editTop then Reload() end end)
    Check("arrowKeys", "Arrow keys move the cursor without Alt", nil, ApplyTweaks)
    Check("unclamp", "Let the chat frame go right up to the screen edge", nil, function() ApplyTweaks(); Reload() end)
    Check("classColors", "Class-coloured names in chat", nil, ApplyTweaks)
    Check("copyChat", "'C' button to copy chat (also /copychat)", nil, ApplyCopy)
    y = y + 6

    Head("Spam filters")
    Check("filterDrunk", "Hide other people's drunk messages")
    Check("filterDuel", "Hide duel results")
    Check("filterSpellLinks", "Hide say / yell / emote lines with spell links (from others)")

    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        for _, s in ipairs(steppers) do s.Refresh() end
    end
end
