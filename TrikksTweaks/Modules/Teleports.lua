-- Module: Teleports
-- A strip of buttons next to the Esc menu with every teleport you own: class
-- spells (mage teleports, Astral Recall, dungeon "Path of ..." spells, ...),
-- your hearthstone and hearthstone toys, engineering teleporters and your own
-- extra items. Click to use.
-- Casting / using needs Blizzard's secure buttons, and an addon may not show,
-- hide or change those in combat. So the buttons are children of the Esc menu
-- itself: the game shows and hides them along with the menu, and we only
-- rebuild the list out of combat.
local _, TT = ...
local M = TT:RegisterModule("Teleports", {
    title = "Teleports",
    category = "Quality of Life",
    desc = "Your teleports (spells, hearthstones, toys, engineering) next to the Esc menu, click to use. /tp",
    defaults = { side = "RIGHT", size = 36, perColumn = 10, spells = true, hearth = true, toys = true,
                 engineering = true, extra = {} },
})

-- spell names that are teleports (matched at the start of the name)
local SPELL_PREFIXES = { "Teleport", "Portal: ", "Ancient Teleport", "Ancient Portal", "Astral Recall",
                         "Death Gate", "Zen Pilgrimage", "Dreamwalk", "Path of " }
local HEARTHS = { 6948, 110560, 140192 }             -- Hearthstone, Garrison, Dalaran
local TOYS = { 64488, 54452, 93672, 142542, 162973, 163045, 165669, 165670, 165802, 166746, 166747, 168907,
               172179, 180290, 182773, 183716, 184353, 188952, 190196, 190237, 193588, 200630, 206195,
               208704, 209035, 210455, 212337 }      -- hearthstone toys (unknown IDs are simply never owned)
local ENGINEERING = { 18984, 18986, 30542, 30544, 48933, 87215, 112059, 151652, 168807, 168808, 172924,
                      198156, 221966 }               -- Everlook, Gadgetzan, Area 52, Northrend, Pandaria, ...

local function IsTeleportName(name)
    if not name or TT.IsSecret(name) then return false end
    for _, p in ipairs(SPELL_PREFIXES) do
        if name:sub(1, #p) == p then return true end
    end
    return false
end

-- every known teleport spell in your spellbook (inside flyouts too)
local function TeleportSpells()
    local list, seen = {}, {}
    local function Add(id, name)
        if id and not seen[id] and IsTeleportName(name) then seen[id] = true; list[#list + 1] = id end
    end
    local function Flyout(fid)
        if not GetFlyoutInfo then return end
        local _, _, numSlots, known = GetFlyoutInfo(fid)
        if not known then return end
        for s = 1, numSlots or 0 do
            local spellID, _, isKnown, name = GetFlyoutSlotInfo(fid, s)
            if isKnown then Add(spellID, name) end
        end
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if li and not li.offSpecID then
                for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if info then
                        if Enum.SpellBookItemType and info.itemType == Enum.SpellBookItemType.Flyout then
                            Flyout(info.actionID)
                        elseif not info.isPassive then
                            Add(info.spellID or info.actionID, info.name)
                        end
                    end
                end
            end
        end
    elseif GetNumSpellTabs then                       -- older clients
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = offset + 1, offset + num do
                local kind, id = GetSpellBookItemInfo(i, "spell")
                if kind == "FLYOUT" then Flyout(id)
                elseif kind == "SPELL" then Add(id, GetSpellBookItemName(i, "spell")) end
            end
        end
    end
    return list
end

local function HasItem(id) return (C_Item.GetItemCount(id) or 0) > 0 end
local function HasToy(id) return PlayerHasToy and PlayerHasToy(id) or false end

-- what to show: { kind = "spell" / "item" / "toy", id = ... }
local function Collect()
    local db, list = M.db, {}
    if db.spells then for _, id in ipairs(TeleportSpells()) do list[#list + 1] = { kind = "spell", id = id } end end
    if db.hearth then for _, id in ipairs(HEARTHS) do if HasItem(id) then list[#list + 1] = { kind = "item", id = id } end end end
    if db.toys then for _, id in ipairs(TOYS) do if HasToy(id) then list[#list + 1] = { kind = "toy", id = id } end end end
    if db.engineering then
        for _, id in ipairs(ENGINEERING) do
            if HasToy(id) then list[#list + 1] = { kind = "toy", id = id }
            elseif HasItem(id) then list[#list + 1] = { kind = "item", id = id } end
        end
    end
    for _, id in ipairs(db.extra) do
        if HasToy(id) then list[#list + 1] = { kind = "toy", id = id }
        elseif HasItem(id) then list[#list + 1] = { kind = "item", id = id } end
    end
    return list
end

---------------------------------------------------------------------------
-- The strip next to the Esc menu
---------------------------------------------------------------------------
local strip, buttons = nil, {}
local function Icon(d)
    if d.kind == "spell" then return C_Spell.GetSpellTexture(d.id) end
    return C_Item.GetItemIconByID(d.id)
end
local function OnEnter(self)
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, M.db.side == "LEFT" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
    if d.kind == "spell" then GameTooltip:SetSpellByID(d.id)
    elseif d.kind == "toy" and GameTooltip.SetToyByItemID then GameTooltip:SetToyByItemID(d.id)
    else GameTooltip:SetItemByID(d.id) end
    GameTooltip:Show()
end
local function UpdateCooldowns()
    for _, b in ipairs(buttons) do
        local d = b.data
        if b:IsShown() and d then
            local ok, start, dur
            if d.kind == "spell" then
                local ok2, cd = pcall(C_Spell.GetSpellCooldown, d.id)
                ok = ok2 and cd; start, dur = cd and cd.startTime, cd and cd.duration
            else
                ok, start, dur = pcall(C_Container.GetItemCooldown, d.id)
            end
            if ok and start and dur and not TT.IsSecret(start) and not TT.IsSecret(dur) and dur > 1.5 then
                b.cd:SetCooldown(start, dur)
            else
                b.cd:Clear()
            end
        end
    end
end

local function GetButton(i)
    if buttons[i] then return buttons[i] end
    local b = CreateFrame("Button", "TrikksTeleport" .. i, strip, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    TT.Flat(b, { 0, 0, 0, 1 }, { 0, 0, 0, 1 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon); hl:SetColorTexture(1, 1, 1, 0.15)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    buttons[i] = b
    return b
end

local pending = false
local function Rebuild()
    if not strip then return end
    if InCombatLockdown() then pending = true; return end     -- secure buttons: out of combat only
    pending = false
    local db = M.db
    local list = M.enabled and Collect() or {}
    local size, per = db.size, math.max(1, db.perColumn)
    for i, d in ipairs(list) do
        local b = GetButton(i)
        b.data = d
        b:SetSize(size, size)
        local col, row = math.floor((i - 1) / per), (i - 1) % per
        b:ClearAllPoints()
        if db.side == "LEFT" then b:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -6 - col * (size + 4), -6 - row * (size + 4))
        else b:SetPoint("TOPLEFT", strip, "TOPLEFT", 6 + col * (size + 4), -6 - row * (size + 4)) end
        b.icon:SetTexture(Icon(d) or 134400)
        b:SetAttribute("type", d.kind)
        b:SetAttribute("spell", d.kind == "spell" and d.id or nil)
        b:SetAttribute("item", d.kind == "item" and ("item:" .. d.id) or nil)
        b:SetAttribute("toy", d.kind == "toy" and d.id or nil)
        b:Show()
    end
    for i = #list + 1, #buttons do buttons[i]:Hide(); buttons[i].data = nil end
    local n = #list
    local cols, rows = math.ceil(n / per), math.min(n, per)
    strip:SetSize(math.max(1, cols * (size + 4) + 8), math.max(1, rows * (size + 4) + 8))
    strip:ClearAllPoints()
    if db.side == "LEFT" then strip:SetPoint("TOPRIGHT", GameMenuFrame, "TOPLEFT", -6, 0)
    else strip:SetPoint("TOPLEFT", GameMenuFrame, "TOPRIGHT", 6, 0) end
    strip:SetShown(n > 0)
    UpdateCooldowns()
end

local function CreateStrip()
    if strip or not GameMenuFrame or InCombatLockdown() then return end
    strip = CreateFrame("Frame", "TrikksTeleportStrip", GameMenuFrame, "BackdropTemplate")
    TT.Flat(strip, TT.C.bg, TT.C.border)
    strip:Hide()
    GameMenuFrame:HookScript("OnShow", function() if not InCombatLockdown() then Rebuild() else UpdateCooldowns() end end)
end

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.5, function() queued = false; Rebuild() end)
end
function M:Setup()
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED",
                         "TOYS_UPDATED", "NEW_TOY_ADDED", "SPELL_UPDATE_COOLDOWN" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function(_, event)
        if event == "SPELL_UPDATE_COOLDOWN" then
            if strip and strip:IsVisible() then UpdateCooldowns() end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" and not pending then return end
        Queue()
    end)
end

function M:OnEnable() CreateStrip(); Queue() end
function M:OnDisable() Queue() end

-- /tp opens the Esc menu with the strip (not in combat: Blizzard doesn't allow it)
SLASH_TTTELEPORTS1 = "/tp"
SLASH_TTTELEPORTS2 = "/teleports"
SlashCmdList.TTTELEPORTS = function()
    if not M.enabled then TT.Print("turn on Teleports in /trikks first."); return end
    if InCombatLockdown() then TT.Print("not during combat (press Esc instead)."); return end
    if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) else ShowUIPanel(GameMenuFrame) end
end

---------------------------------------------------------------------------
function M:BuildSettings(body, page)
    local db, refreshers, y = M.db, {}, 0
    local function Check(key, text)
        local cb = TT.Check(body, text, function(v) db[key] = v; Queue() end)
        cb:SetPoint("TOPLEFT", 2, -y)
        refreshers[#refreshers + 1] = function() cb:SetChecked(db[key]) end
        y = y + 24
    end
    Check("spells", "Class teleport spells (mage teleports, Astral Recall, dungeon teleports, ...)")
    Check("hearth", "Hearthstones (normal, garrison, Dalaran)")
    Check("toys", "Hearthstone toys you own")
    Check("engineering", "Engineering teleporters (Everlook, Gadgetzan, wormholes, ...)")
    y = y + 6
    local sl = TT.Label(body, "Side of the Esc menu:")
    sl:SetPoint("TOPLEFT", 4, -y - 4)
    local side = TT.Cycle(body, 100, { { "RIGHT", "Right" }, { "LEFT", "Left" } },
        function() return db.side end, function(v) db.side = v; Queue() end)
    side:SetPoint("TOPLEFT", 180, -y)
    refreshers[#refreshers + 1] = side.Refresh
    y = y + 32
    local size = TT.Stepper(body, "Button size", function() return db.size end,
        function(v) db.size = v; Queue() end, 20, 64, 2)
    size:SetPoint("TOPLEFT", 0, -y)
    refreshers[#refreshers + 1] = size.Refresh
    local per = TT.Stepper(body, "Buttons per column", function() return db.perColumn end,
        function(v) db.perColumn = v; Queue() end, 1, 30, 1)
    per:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -2)
    refreshers[#refreshers + 1] = per.Refresh
    y = y + 60
    local el = TT.Label(body, "Extra items or toys (item ID):")
    el:SetPoint("TOPLEFT", 4, -y)
    y = y + 20
    local list = TT.IDList(body, 360, 140, db.extra, function(id)
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
        return (name or "Item") .. "  |cff888888" .. id .. "|r"
    end, Queue)
    list:SetPoint("TOPLEFT", 4, -y)
    refreshers[#refreshers + 1] = list.Refresh
    y = y + 148
    local help = TT.Label(body,
        "Shows next to the Esc menu (or type /tp). Only teleports you own appear. The list\n" ..
        "updates out of combat; in combat the buttons still work, they just don't change.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -y)
    page.OnPageShow = function() for _, f in ipairs(refreshers) do f() end end
end
