-- Module: Four in a Row (Connect Four)
-- vs Computer, 2 players on one PC, or online vs players who have Trikks Tweaks.
local _, TT = ...
local M = TT:RegisterModule("FourInARow", {
    title = "Four in a Row",
    category = "Fun",
    desc = "Connect Four: vs the computer, 2 players on one PC, or online with friends who have Trikks Tweaks. /c4",
    defaults = { mode = "AI", difficulty = "Normal", wins = 0, losses = 0, allowInvites = true },
})

local COLS, ROWS, CELL = 7, 6, 44
local COLORS = { { 1, 0.82, 0.1 }, { 0.9, 0.15, 0.15 } }   -- 1 = yellow, 2 = red
local NAMES = { "Yellow", "Red" }
local DEPTHS = { Easy = 2, Normal = 4, Hard = 6 }
local DIFF_ORDER = { "Easy", "Normal", "Hard" }
local MODE_ORDER = { "AI", "LOCAL", "ONLINE" }
local MODE_TEXT = { AI = "vs Computer", LOCAL = "2 Players", ONLINE = "Online" }
local ORDER = { 4, 3, 5, 2, 6, 1, 7 }                       -- centre columns first
local PREFIX = "TrikksC4"                                   -- addon message channel

local db
local board, turn, gameOver, winCells, busy
local gameId, starter, moveCount = 0, 1, 0
local online = { opponent = nil, myColor = 1, active = false, pending = nil }

---------------------------------------------------------------------------
-- Board logic  board[col][row], row 1 = bottom
---------------------------------------------------------------------------
local function NewBoard() local b = {} for c = 1, COLS do b[c] = {} end return b end
local function DropRow(b, c) for r = 1, ROWS do if not b[c][r] then return r end end end
local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }

local function FourAt(b, c, r)
    local p = b[c][r]
    if not p then return end
    for _, d in ipairs(DIRS) do
        local cells = { { c, r } }
        for s = -1, 1, 2 do
            local x, y = c + d[1] * s, r + d[2] * s
            while x >= 1 and x <= COLS and y >= 1 and y <= ROWS and b[x][y] == p do
                cells[#cells + 1] = { x, y }
                x, y = x + d[1] * s, y + d[2] * s
            end
        end
        if #cells >= 4 then return cells end
    end
end

local function IsFull(b) for c = 1, COLS do if not b[c][ROWS] then return false end end return true end

---------------------------------------------------------------------------
-- AI: minimax + alpha-beta pruning
---------------------------------------------------------------------------
local function Evaluate(b, p)
    local o, score = 3 - p, 0
    for r = 1, ROWS do if b[4][r] == p then score = score + 3 end end
    for c = 1, COLS do
        for r = 1, ROWS do
            for _, d in ipairs(DIRS) do
                local ec, er = c + d[1] * 3, r + d[2] * 3
                if ec >= 1 and ec <= COLS and er >= 1 and er <= ROWS then
                    local mine, theirs, empty = 0, 0, 0
                    for i = 0, 3 do
                        local v = b[c + d[1] * i][r + d[2] * i]
                        if v == p then mine = mine + 1 elseif v == o then theirs = theirs + 1 else empty = empty + 1 end
                    end
                    if mine == 3 and empty == 1 then score = score + 5
                    elseif mine == 2 and empty == 2 then score = score + 2
                    elseif theirs == 3 and empty == 1 then score = score - 4 end
                end
            end
        end
    end
    return score
end

local function Minimax(b, depth, alpha, beta, maximizing, ai, lc, lr)
    if lc and FourAt(b, lc, lr) then return (b[lc][lr] == ai) and (100000 + depth) or -(100000 + depth) end
    if IsFull(b) then return 0 end
    if depth == 0 then return Evaluate(b, ai) end
    local p = maximizing and ai or (3 - ai)
    local best = maximizing and -math.huge or math.huge
    for _, c in ipairs(ORDER) do
        local r = DropRow(b, c)
        if r then
            b[c][r] = p
            local v = Minimax(b, depth - 1, alpha, beta, not maximizing, ai, c, r)
            b[c][r] = nil
            if maximizing then
                if v > best then best = v end
                if best > alpha then alpha = best end
            else
                if v < best then best = v end
                if best < beta then beta = best end
            end
            if alpha >= beta then break end
        end
    end
    return best
end

local function BestMove(ai)
    local depth = DEPTHS[db.difficulty] or 4
    local bestScore, best = -math.huge, {}
    for _, c in ipairs(ORDER) do
        local r = DropRow(board, c)
        if r then
            board[c][r] = ai
            local v = Minimax(board, depth - 1, -math.huge, math.huge, false, ai, c, r)
            board[c][r] = nil
            if v > bestScore then bestScore, best = v, { c } elseif v == bestScore then best[#best + 1] = c end
        end
    end
    return best[math.random(#best)]
end

---------------------------------------------------------------------------
-- Networking
---------------------------------------------------------------------------
local function Short(name) return name and Ambiguate(name, "none") or "?" end
local function SameName(a, b) return a and b and Short(a):lower() == Short(b):lower() end
local function Send(target, msg)
    local result = C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", target)
    if result == false or (type(result) == "number" and result ~= 0) then
        TT.Print("Four in a Row: could not send to " .. Short(target) .. " (combat/instance restriction or offline).")
    end
end

---------------------------------------------------------------------------
-- Game window
---------------------------------------------------------------------------
-- The game window, the board and the online play are only made once the
-- module is switched on (Setup). These are used outside of it:
local frame, ApplyModeUI, NewGame, LeaveOnline, UpdateScore, Invite

local function Build()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    frame = TT.Window("TrikksTweaksC4", COLS * CELL + 40, ROWS * CELL + CELL + 150, "Four in a Row")

    local boardFrame = CreateFrame("Frame", nil, frame)
    boardFrame:SetSize(COLS * CELL, ROWS * CELL)
    boardFrame:SetPoint("BOTTOM", 0, 70)
    local bg = boardFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -6, 6); bg:SetPoint("BOTTOMRIGHT", 6, -6)
    bg:SetColorTexture(0.11, 0.11, 0.13, 1)          -- flat dark board

    local function MakeDisc(parent, layer, size)        -- square texture + circle mask
        local t = parent:CreateTexture(nil, layer)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetSize(size, size)
        local m = parent:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
        return t
    end
    local function CellXY(c, r) return (c - 0.5) * CELL, (r - 0.5) * CELL end

    local holes = {}
    for c = 1, COLS do
        holes[c] = {}
        for r = 1, ROWS do
            local d = MakeDisc(boardFrame, "ARTWORK", CELL - 8)
            d:SetPoint("CENTER", boardFrame, "BOTTOMLEFT", CellXY(c, r))
            holes[c][r] = d
        end
    end
    local ghost = MakeDisc(boardFrame, "OVERLAY", CELL - 8)
    ghost:Hide()

    local status = TT.Label(frame, "", "GameFontNormalLarge")
    status:SetPoint("BOTTOM", 0, 42)
    local scoreText = TT.Label(frame, "", "GameFontHighlightSmall")

    local onlineRow = CreateFrame("Frame", nil, frame)
    onlineRow:SetSize(260, 24)
    onlineRow:SetPoint("TOP", 0, -34)
    local nameBox = TT.EditBox(onlineRow, 150, 22)
    nameBox:SetPoint("LEFT", 6, 0)
    local inviteBtn = TT.Button(onlineRow, "Invite", 90, nil)
    inviteBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

    ---------------------------------------------------------------------------
    -- Game flow
    ---------------------------------------------------------------------------
    local function Blocked()                 -- may the local player NOT click now?
        if db.mode == "AI" then return turn == 2 end
        if db.mode == "ONLINE" then return not online.active or turn ~= online.myColor end
        return false
    end

    local function Render()
        for c = 1, COLS do
            for r = 1, ROWS do
                local p, d = board[c][r], holes[c][r]
                if p then d:SetVertexColor(unpack(COLORS[p])) else d:SetVertexColor(0.035, 0.035, 0.04) end
                d:SetAlpha((winCells and p) and 0.3 or 1)
            end
        end
        if winCells then for _, cell in ipairs(winCells) do holes[cell[1]][cell[2]]:SetAlpha(1) end end
    end

    local function ColorText(p, s)
        local c = COLORS[p]
        return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, s)
    end

    function UpdateScore()
        if db.mode == "AI" then scoreText:SetText("You " .. db.wins .. " - " .. db.losses .. " AI  (" .. db.difficulty .. ")")
        elseif db.mode == "ONLINE" and online.active then scoreText:SetText("vs " .. Short(online.opponent))
        else scoreText:SetText("") end
    end

    local function UpdateStatus()
        if gameOver then return end
        if db.mode == "AI" then
            status:SetText(turn == 2 and ColorText(2, "Computer is thinking...") or ColorText(1, "Your turn"))
        elseif db.mode == "ONLINE" then
            if not online.active then status:SetText("Type a name (or target someone) and Invite")
            elseif turn == online.myColor then status:SetText(ColorText(turn, "Your turn"))
            else status:SetText(ColorText(turn, Short(online.opponent) .. "'s turn")) end
        else
            status:SetText(ColorText(turn, NAMES[turn] .. "'s turn"))
        end
    end

    local hoverCol
    local function UpdateGhost()
        if hoverCol and not busy and not gameOver and not Blocked() and DropRow(board, hoverCol) then
            ghost:ClearAllPoints()
            ghost:SetPoint("CENTER", boardFrame, "BOTTOMLEFT", (CellXY(hoverCol, 1)), (ROWS + 0.6) * CELL)
            ghost:SetVertexColor(unpack(COLORS[turn]))
            ghost:SetAlpha(0.5)
            ghost:Show()
        else
            ghost:Hide()
        end
    end

    local function Sound(kit) if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end end

    local animator = CreateFrame("Frame")
    local function AnimateDrop(c, r, p, done)
        local x, targetY = CellXY(c, r)
        local y, speed = (ROWS + 0.6) * CELL, 0
        ghost:SetVertexColor(unpack(COLORS[p])); ghost:SetAlpha(1); ghost:Show()
        animator:SetScript("OnUpdate", function(_, elapsed)
            speed = speed + 2500 * elapsed              -- gravity
            y = y - speed * elapsed
            if y <= targetY then
                animator:SetScript("OnUpdate", nil)
                ghost:Hide()
                done()
            else
                ghost:ClearAllPoints()
                ghost:SetPoint("CENTER", boardFrame, "BOTTOMLEFT", x, y)
            end
        end)
    end

    local PlayMove, ProcessPending

    local function QueueAI(delay)
        busy = true
        local id = gameId
        C_Timer.After(delay, function()
            if id ~= gameId then return end
            busy = false
            PlayMove(BestMove(2), true)
        end)
    end

    local function AfterMove(c, r)
        local cells = FourAt(board, c, r)
        if cells then
            gameOver, winCells = true, cells
            local p = board[c][r]
            if db.mode == "AI" then
                if p == 1 then db.wins = db.wins + 1; status:SetText(ColorText(1, "You win!"))
                else db.losses = db.losses + 1; status:SetText(ColorText(2, "Computer wins!")) end
            elseif db.mode == "ONLINE" then
                online.active = false
                status:SetText(p == online.myColor and ColorText(p, "You win!") or ColorText(p, Short(online.opponent) .. " wins!"))
            else
                status:SetText(ColorText(p, NAMES[p] .. " wins!"))
            end
        elseif IsFull(board) then
            gameOver, online.active = true, false
            status:SetText("Draw!")
        else
            turn = 3 - turn
            UpdateStatus()
        end
        Render(); UpdateScore()
        busy = false
        UpdateGhost()
        if not gameOver and db.mode == "AI" and turn == 2 then QueueAI(0.35) end
        ProcessPending()
    end

    PlayMove = function(c, remote)
        if busy or gameOver then return end
        if Blocked() and not remote then return end
        local r = DropRow(board, c)
        if not r then return end
        busy = true
        moveCount = moveCount + 1
        if db.mode == "ONLINE" and not remote then Send(online.opponent, "MOV:" .. c .. ":" .. moveCount) end
        ghost:Hide()
        local id, p = gameId, turn
        AnimateDrop(c, r, p, function()
            if id ~= gameId then return end
            board[c][r] = p
            Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
            AfterMove(c, r)
        end)
    end

    -- Opponent moves can arrive while our own disc is still falling: queue them,
    -- and only accept the exact next move, in a valid column, on their turn.
    ProcessPending = function()
        local m = online.pending
        if not m or busy then return end
        online.pending = nil
        if db.mode == "ONLINE" and online.active and turn ~= online.myColor
           and m.n == moveCount + 1 and m.c >= 1 and m.c <= COLS and DropRow(board, m.c) then
            PlayMove(m.c, true)
        end
    end

    local function ResetBoard(firstTurn)
        gameId = gameId + 1
        animator:SetScript("OnUpdate", nil)
        board, gameOver, winCells, busy, moveCount = NewBoard(), false, nil, false, 0
        online.pending = nil
        turn = firstTurn
        Render(); UpdateStatus(); UpdateScore(); UpdateGhost()
    end

    function NewGame()
        if db.mode == "ONLINE" then online.active = false; ResetBoard(1); return end
        if db.mode == "AI" then starter = 3 - starter else starter = 1 end    -- alternate vs AI
        ResetBoard(starter)
        if db.mode == "AI" and turn == 2 then QueueAI(0.5) end
    end

    local function StartOnline(opponent, myColor)
        online.opponent, online.myColor, online.active = opponent, myColor, true
        ResetBoard(1)                        -- yellow (the inviter) starts
        frame:Show()
        Sound("READY_CHECK")
    end

    function LeaveOnline()
        if online.active and online.opponent then Send(online.opponent, "RES") end
        online.active = false
    end

    function Invite(name)
        name = name and strtrim(name) or ""
        if name == "" then
            if UnitIsPlayer("target") then name = GetUnitName("target", true)
            else status:SetText("Type a name or target a player first"); return end
        end
        if SameName(name, UnitName("player")) then status:SetText("You can't invite yourself :)"); return end
        LeaveOnline()
        online.opponent = name
        nameBox:SetText(Short(name))
        Send(name, "INV")
        ResetBoard(1)
        status:SetText("Waiting for " .. Short(name) .. "...")
    end
    inviteBtn:SetScript("OnClick", function() Invite(nameBox:GetText()); nameBox:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed", function(self) Invite(self:GetText()); self:ClearFocus() end)

    for c = 1, COLS do
        local b = CreateFrame("Button", nil, boardFrame)
        b:SetSize(CELL, (ROWS + 1) * CELL)
        b:SetPoint("BOTTOMLEFT", (c - 1) * CELL, 0)
        b:SetScript("OnEnter", function() hoverCol = c; UpdateGhost() end)
        b:SetScript("OnLeave", function() if hoverCol == c then hoverCol = nil end; UpdateGhost() end)
        b:SetScript("OnClick", function() PlayMove(c) end)
    end

    local modeBtn, diffBtn
    function ApplyModeUI()
        modeBtn:SetText(MODE_TEXT[db.mode])
        diffBtn:SetText(db.difficulty)
        diffBtn:SetShown(db.mode == "AI")
        onlineRow:SetShown(db.mode == "ONLINE")
        scoreText:ClearAllPoints()
        scoreText:SetPoint("TOP", 0, db.mode == "ONLINE" and -62 or -38)
    end

    local newBtn = TT.Button(frame, "New Game", 100, function()
        if db.mode == "ONLINE" and online.opponent then Invite(online.opponent) else NewGame() end
    end)
    newBtn:SetPoint("BOTTOM", -110, 12)
    modeBtn = TT.Button(frame, "", 100, function()
        LeaveOnline()
        local i = 1
        for k, v in ipairs(MODE_ORDER) do if v == db.mode then i = k end end
        db.mode = MODE_ORDER[i % #MODE_ORDER + 1]
        ApplyModeUI(); NewGame()
    end)
    modeBtn:SetPoint("BOTTOM", 0, 12)
    diffBtn = TT.Button(frame, "", 100, function()
        local i = 1
        for k, v in ipairs(DIFF_ORDER) do if v == db.difficulty then i = k end end
        db.difficulty = DIFF_ORDER[i % #DIFF_ORDER + 1]
        ApplyModeUI(); NewGame()
    end)
    diffBtn:SetPoint("BOTTOM", 110, 12)

    ---------------------------------------------------------------------------
    -- Incoming invites + messages
    ---------------------------------------------------------------------------
    StaticPopupDialogs["TRIKKSTWEAKS_C4_INVITE"] = {
        text = "%s challenges you to Four in a Row!",
        button1 = ACCEPT or "Accept",
        button2 = DECLINE or "Decline",
        timeout = 30, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, sender)
            LeaveOnline()
            db.mode = "ONLINE"
            ApplyModeUI()
            nameBox:SetText(Short(sender))
            Send(sender, "ACC")
            StartOnline(sender, 2)           -- the invited player is red
        end,
        OnCancel = function(_, sender) Send(sender, "DEC") end,
    }

    local comms = CreateFrame("Frame")
    comms:RegisterEvent("CHAT_MSG_ADDON")
    comms:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
        if prefix ~= PREFIX or not db then return end
        if SameName(sender, UnitName("player")) then return end
        local cmd, a, b = strsplit(":", msg)
        if cmd == "INV" then
            if not M.enabled or not db.allowInvites then Send(sender, "DEC"); return end
            StaticPopup_Show("TRIKKSTWEAKS_C4_INVITE", Short(sender), nil, sender)   -- 4th arg = data
        elseif not SameName(sender, online.opponent) then
            return
        elseif cmd == "ACC" and not online.active then
            db.mode = "ONLINE"; ApplyModeUI()
            StartOnline(sender, 1)           -- we invited: yellow, we start
        elseif cmd == "DEC" then
            status:SetText(Short(sender) .. " declined.")
        elseif cmd == "RES" and online.active then
            online.active, gameOver = false, true
            status:SetText(Short(sender) .. " left the game.")
        elseif cmd == "MOV" and online.active then
            online.pending = { c = tonumber(a) or 0, n = tonumber(b) or 0 }
            ProcessPending()
        end
    end)
end

---------------------------------------------------------------------------
-- Module hooks, settings page, slash
---------------------------------------------------------------------------
function M:OnLoad()
    db = M.db
    if not MODE_TEXT[db.mode] then db.mode = "AI" end
    if not DEPTHS[db.difficulty] then db.difficulty = "Normal" end
end
function M:Setup()
    Build()
    ApplyModeUI()
    starter = 2                          -- first game vs AI: you start
    NewGame()
end
function M:OnDisable() LeaveOnline(); frame:Hide() end

function M:BuildSettings(body, page)
    local open = TT.Button(body, "Open game", 140, function()
        if M.enabled then frame:Show() else TT.Print("turn Four in a Row on first.") end
    end)
    open:SetPoint("TOPLEFT")
    local inv = TT.Check(body, "Accept invites from other players", function(v) db.allowInvites = v end)
    inv:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -4, -12)
    local stats = TT.Label(body, "")
    stats:SetPoint("TOPLEFT", inv, "BOTTOMLEFT", 4, -14)
    local reset = TT.Button(body, "Reset score", 110, function()
        db.wins, db.losses = 0, 0; if UpdateScore then UpdateScore() end; page.OnPageShow()
    end)
    reset:SetPoint("LEFT", stats, "RIGHT", 16, 0)
    local help = TT.Label(body,
        "/c4  open or close the game\n/c4 invite Name  challenge someone online\n\n" ..
        "Online play: both players need Trikks Tweaks, the same faction and\nthe same (or a connected) realm. Moves can't be sent in combat\nor inside some instances.",
        "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -20)
    page.OnPageShow = function()
        inv:SetChecked(db.allowInvites)
        stats:SetText("Score vs computer:  |cffffffff" .. db.wins .. " - " .. db.losses .. "|r")
    end
end

SLASH_TTFOURINAROW1, SLASH_TTFOURINAROW2 = "/c4", "/fourinarow"
SlashCmdList.TTFOURINAROW = function(msg)
    if not M.enabled then TT.Print("Four in a Row is turned off (/trikks to turn it on)."); return end
    local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
    if cmd and cmd:lower() == "invite" then
        db.mode = "ONLINE"; ApplyModeUI(); frame:Show(); Invite(arg)
    else
        frame:SetShown(not frame:IsShown())
    end
end
