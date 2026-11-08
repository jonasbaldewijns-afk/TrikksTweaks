-- Module: Social
-- Block unwanted requests (duels, invites from strangers,
-- Battle.net friend requests, quests shared by strangers) and automatically
-- accept invites from friends, or invite people who whisper a keyword.
local _, TT = ...
local M = TT:RegisterModule("Social", {
    title = "Social",
    category = "Quality of Life",
    desc = "Block duels, strangers' invites, friend requests and shared quests; auto-accept friends; whisper-to-invite.",
    defaults = {
        blockDuels = true, blockInvites = false, blockFriendRequests = false,
        blockSharedQuests = false, acceptInvites = true, guildFriends = true,
        keywordInvite = false, keyword = "inv",
    },
})
local IsSecret = TT.IsSecret

-- Is this person a friend? (WoW friends, Battle.net friends online in WoW, and
-- optionally guild members)
local function Short(name) return name and Ambiguate(name, "none"):lower() end
local function IsFriend(name)
    if not name or IsSecret(name) then return false end
    local want = Short(name)
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name and Short(info.name) == want then return true end
    end
    if C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
        for i = 1, BNGetNumFriends() do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            local game = acc and acc.gameAccountInfo
            if game and game.characterName and Short(game.characterName) == want then return true end
        end
    end
    if M.db.guildFriends and IsInGuild() then
        for i = 1, GetNumGuildMembers() do
            local gname = GetGuildRosterInfo(i)
            if gname and Short(gname) == want then return true end
        end
    end
    return false
end

local function CanInvite()
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function M:Setup()
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "DUEL_REQUESTED", "PARTY_INVITE_REQUEST",
                         "BN_FRIEND_INVITE_ADDED", "QUEST_DETAIL", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" }) do
        pcall(ev.RegisterEvent, ev, e)          -- some events may not exist on every client
    end

    ev:SetScript("OnEvent", function(_, event, a1, a2, ...)
        if not M.enabled then return end
        local db = M.db

        if event == "DUEL_REQUESTED" and db.blockDuels then
            if not IsFriend(a1) then CancelDuel(); StaticPopup_Hide("DUEL_REQUESTED") end


        elseif event == "PARTY_INVITE_REQUEST" then
            local friend = IsFriend(a1)
            if friend and db.acceptInvites then
                AcceptGroup(); StaticPopup_Hide("PARTY_INVITE")
            elseif not friend and db.blockInvites then
                DeclineGroup(); StaticPopup_Hide("PARTY_INVITE")
            end

        elseif event == "BN_FRIEND_INVITE_ADDED" and db.blockFriendRequests then
            if BNGetNumFriendInvites and BNGetFriendInviteInfo and BNDeclineFriendInvite then
                for i = BNGetNumFriendInvites(), 1, -1 do
                    local id = BNGetFriendInviteInfo(i)
                    if id then BNDeclineFriendInvite(id) end
                end
            end

        elseif event == "QUEST_DETAIL" and db.blockSharedQuests then
            -- a quest shared by a player opens with that player as the "npc"
            if UnitExists("npc") and UnitIsPlayer("npc") and not IsFriend(UnitName("npc")) then
                DeclineQuest()
            end

        elseif (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER") and db.keywordInvite then
            local text, sender = a1, a2
            if type(text) ~= "string" or IsSecret(text) or IsSecret(sender) then return end
            if strtrim(text):lower() ~= db.keyword:lower() or not CanInvite() then return end
            if event == "CHAT_MSG_BN_WHISPER" then
                -- Battle.net whispers: invite the character they're playing
                local bnetID = select(13, a1, a2, ...)          -- 13th argument = sender account ID
                local acc = bnetID and C_BattleNet.GetAccountInfoByID(bnetID)
                local game = acc and acc.gameAccountInfo
                if game and game.characterName then
                    local name = game.realmName and (game.characterName .. "-" .. game.realmName) or game.characterName
                    C_PartyInfo.InviteUnit(name)
                end
            else
                C_PartyInfo.InviteUnit(sender)
            end
        end
    end)
end

function M:BuildSettings(body, page)
    local db, checks, y = M.db, {}, 0
    local function Head(text)
        local h = TT.Label(body, text:upper(), "GameFontNormalSmall")
        h:SetTextColor(unpack(TT.C.dim)); h:SetPoint("TOPLEFT", 0, -y); y = y + 20
    end
    local function Check(key, text, indent)
        local cb = TT.Check(body, text, function(v) db[key] = v end)
        cb:SetPoint("TOPLEFT", 2 + (indent and 20 or 0), -y)
        checks[key] = cb
        y = y + 24
    end
    Head("Block")
    Check("blockDuels", "Duel requests (except from friends)")
    Check("blockInvites", "Group invites from people who aren't friends")
    Check("blockFriendRequests", "Battle.net friend requests")
    Check("blockSharedQuests", "Quests shared by people who aren't friends")
    y = y + 6
    Head("Friends")
    Check("acceptInvites", "Accept group invites from friends automatically")
    Check("guildFriends", "Treat guild members as friends")
    y = y + 6
    Head("Whisper to invite")
    Check("keywordInvite", "Invite people who whisper this word:")
    local box = TT.EditBox(body, 120, 22)
    box:SetPoint("TOPLEFT", 22, -y)
    box:SetScript("OnTextChanged", function(self, user)
        if user then local t = strtrim(self:GetText()); if t ~= "" then db.keyword = t end end
    end)
    y = y + 30
    local help = TT.Label(body, "Only invites when you're not in a group, or you're the leader / assistant.",
        "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y)

    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        box:SetText(db.keyword)
    end
end
