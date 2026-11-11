-- Module: Setups
-- Save your setup under a name and apply it on another (e.g. brand new)
-- character: enabled addons, Edit Mode layout, keybindings, interface
-- settings (CVars) and, for the same class, action bars.
-- Setups are stored account-wide, so every character can see them.
local _, TT = ...
local M = TT:RegisterModule("Setups", {
    title = "Setups",
    category = "Tools",
    desc = "Save addons, Edit Mode layout, keybinds, interface settings and action bars, and apply them on a new character.",
    defaults = { setups = {}, parts = { addons = true, layout = true, bindings = true, cvars = true, actions = false } },
})

local AddOns = C_AddOns
local function Me() return UnitName("player") end
local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

---------------------------------------------------------------------------
-- Capture: one function per part, each returns plain data for SavedVariables
---------------------------------------------------------------------------
local Capture, Apply = {}, {}

-- Addons: enabled / disabled for this character
function Capture.addons()
    local out = {}
    for i = 1, AddOns.GetNumAddOns() do
        local name = AddOns.GetAddOnInfo(i)
        out[name] = AddOns.GetAddOnEnableState(name, Me()) > 0
    end
    return out
end
function Apply.addons(data)
    for name, on in pairs(data) do
        if name ~= "TrikksTweaks" and AddOns.GetAddOnInfo(name) then      -- skip addons you don't have
            if on then AddOns.EnableAddOn(name, Me()) else AddOns.DisableAddOn(name, Me()) end
        end
    end
    return true                                                        -- needs a reload
end

-- Edit Mode: remember the active layout by name (presets come first in the list)
local NUM_PRESETS = (Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues) or 2
function Capture.layout()
    local info = C_EditMode and C_EditMode.GetLayouts()
    if not info then return nil end
    local idx = info.activeLayout
    if idx <= NUM_PRESETS then return { preset = idx } end
    local l = info.layouts[idx - NUM_PRESETS]
    return l and { name = l.layoutName }
end
function Apply.layout(data)
    local info = C_EditMode.GetLayouts()
    if data.preset then C_EditMode.SetActiveLayout(data.preset); return end
    for i, l in ipairs(info.layouts) do
        if l.layoutName == data.name then C_EditMode.SetActiveLayout(NUM_PRESETS + i); return end
    end
    TT.Print("Edit Mode layout '" .. tostring(data.name) .. "' isn't available on this character " ..
        "(character layouts only exist on the character that made them; use an Account layout).")
end

-- Keybindings: every command that has a key
function Capture.bindings()
    local out = {}
    for i = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(i)
        if command and (key1 or key2) then out[#out + 1] = { command, key1, key2 } end
    end
    return out
end
function Apply.bindings(data)
    for _, b in ipairs(data) do
        if b[2] then SetBinding(b[2], b[1]) end
        if b[3] then SetBinding(b[3], b[1]) end
    end
    SaveBindings(GetCurrentBindingSet())
end

-- Interface settings: every console variable (CVar) you changed from its default.
-- A few are machine- or session-specific and are skipped.
local SKIP = { "^last", "^agentUID", "^portal", "^realm", "^account", "Cache", "^gxWindow", "^gxMonitor",
               "^Sound_OutputDriver", "^showTutorials", "^closedInfoFrames", "^seenAsiaCharacterUpgradePopup" }
local function Skip(name)
    for _, pat in ipairs(SKIP) do if name:find(pat) then return true end end
end
function Capture.cvars()
    local out = {}
    if not (C_Console and C_Console.GetAllCommands) then return out end
    local CVAR = Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar or 0
    for _, cmd in ipairs(C_Console.GetAllCommands()) do
        if cmd.commandType == CVAR and not Skip(cmd.command) then
            local ok, value = pcall(C_CVar.GetCVar, cmd.command)
            local okD, default = pcall(C_CVar.GetCVarDefault, cmd.command)
            if ok and okD and value ~= nil and value ~= default then out[cmd.command] = value end
        end
    end
    return out
end
function Apply.cvars(data)
    local failed = 0
    for name, value in pairs(data) do
        if C_CVar.GetCVar(name) ~= value then
            if not pcall(C_CVar.SetCVar, name, value) then failed = failed + 1 end
        end
    end
    if failed > 0 then TT.Print(failed .. " setting(s) couldn't be changed.") end
end

-- Action bars: what's in every slot (only applied to the same class)
local SLOTS = 180
function Capture.actions()
    local out = {}
    for slot = 1, SLOTS do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" or kind == "item" then
            out[slot] = { kind, id }
        elseif kind == "macro" then
            local name = GetActionText(slot) or (id and GetMacroInfo(id))
            if name then out[slot] = { "macro", name } end
        end
    end
    return out
end
function Apply.actions(data, setup)
    local _, class = UnitClass("player")
    if setup.class ~= class then
        TT.Print("action bars skipped: this setup was made on a " .. tostring(setup.class) .. ".")
        return
    end
    local placed = 0
    for slot = 1, SLOTS do
        local a = data[slot] or data[tostring(slot)]
        if a then
            ClearCursor()
            if a[1] == "spell" then
                if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(a[2]) else PickupSpell(a[2]) end
            elseif a[1] == "item" then
                if C_Item and C_Item.PickupItem then C_Item.PickupItem(a[2]) else PickupItem(a[2]) end
            elseif a[1] == "macro" then
                local idx = GetMacroIndexByName(a[2])
                if idx > 0 then PickupMacro(idx) end
            end
            -- Unknown spells / missing items leave the cursor empty: skip those.
            if GetCursorInfo() then PlaceAction(slot); placed = placed + 1 end
            ClearCursor()
        end
    end
    TT.Print(placed .. " action bar slot(s) filled (spells you don't know yet were skipped).")
end

---------------------------------------------------------------------------
local PARTS = {
    { key = "addons",   label = "Enabled addons" },
    { key = "layout",   label = "Edit Mode layout" },
    { key = "bindings", label = "Keybindings" },
    { key = "cvars",    label = "Interface settings (game options you changed)" },
    { key = "actions",  label = "Action bars (only applied to the same class)" },
}

local function SaveSetup(name)
    name = strtrim(name or "")
    if name == "" then TT.Print("give the setup a name first."); return end
    local _, class = UnitClass("player")
    local setup = { class = class, by = Me(), date = date("%Y-%m-%d"), parts = {} }
    for _, p in ipairs(PARTS) do
        if M.db.parts[p.key] then
            local ok, data = pcall(Capture[p.key])
            if ok and data then setup.parts[p.key] = data end
        end
    end
    M.db.setups[name] = setup
    TT.Print("saved setup '" .. name .. "'.")
end

local function ApplySetup(name)
    local setup = M.db.setups[name]
    if not setup then return end
    -- Keybinds, CVars and action bars are protected in combat.
    if InCombatLockdown() then TT.Print("leave combat first."); return end
    for _, p in ipairs(PARTS) do
        local data = setup.parts[p.key]
        if data and M.db.parts[p.key] then
            local ok, err = pcall(Apply[p.key], data, setup)
            if not ok then TT.Print(p.label .. " failed: " .. tostring(err)) end
        end
    end
    TT.AskReload("Setup '" .. name .. "' applied.\nA reload loads the right addons.")
end

StaticPopupDialogs["TRIKKSTWEAKS_DELETE_SETUP"] = {
    text = "Delete setup '%s'?",
    button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
    OnAccept = function(_, data) M.db.setups[data.name] = nil; data.refresh() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------
function M:BuildSettings(body, page)
    local db = M.db

    local nl = TT.Label(body, "Name:")
    nl:SetPoint("TOPLEFT", 0, -4)
    local nameBox = TT.EditBox(body, 200, 22)
    nameBox:SetPoint("LEFT", nl, "RIGHT", 10, 0)
    local saveBtn = TT.Button(body, "Save current setup", 140, nil)
    saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

    local il = TT.Label(body, "INCLUDE (when saving and applying)", "GameFontNormalSmall")
    il:SetTextColor(unpack(TT.C.dim))
    il:SetPoint("TOPLEFT", 0, -40)
    local checks = {}
    for i, p in ipairs(PARTS) do
        local cb = TT.Check(body, p.label, function(v) db.parts[p.key] = v end)
        cb:SetPoint("TOPLEFT", 2, -60 - (i - 1) * 24)
        checks[p.key] = cb
    end

    local sl = TT.Label(body, "SAVED SETUPS", "GameFontNormalSmall")
    sl:SetTextColor(unpack(TT.C.dim))
    sl:SetPoint("TOPLEFT", 0, -60 - #PARTS * 24 - 14)

    local scroll = TT.Scroll(body)
    scroll:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", 0, -8)
    scroll:SetSize(570, 230)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(560, 1)
    scroll:SetScrollChild(list)
    local empty = TT.Label(list, "No setups yet. Set up a character the way you like it, type a name\n" ..
        "and press Save. On a new character, open this page and press Apply.", "GameFontDisable")
    empty:SetPoint("TOPLEFT", 4, -6)

    local rows = {}
    local function Refresh()
        local names = {}
        for name in pairs(db.setups) do names[#names + 1] = name end
        table.sort(names)
        for i, name in ipairs(names) do
            local s = db.setups[name]
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, list, "BackdropTemplate")
                row:SetSize(556, 40)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * 44)
                TT.Flat(row, { 1, 1, 1, 0.025 })
                row.title = TT.Label(row, "")
                row.title:SetPoint("TOPLEFT", 10, -7)
                row.info = TT.Label(row, "", "GameFontDisableSmall")
                row.info:SetPoint("TOPLEFT", 10, -23)
                row.del = TT.Button(row, "Delete", 60, nil)
                row.del:SetPoint("RIGHT", -8, 0)
                row.apply = TT.Button(row, "Apply", 60, nil)
                row.apply:SetPoint("RIGHT", row.del, "LEFT", -6, 0)
                row.over = TT.Button(row, "Overwrite", 76, nil)
                row.over:SetPoint("RIGHT", row.apply, "LEFT", -6, 0)
                rows[i] = row
            end
            local p = s.parts
            local bits = {}
            if p.addons then bits[#bits + 1] = Count(p.addons) .. " addons" end
            if p.layout then bits[#bits + 1] = "layout" end
            if p.bindings then bits[#bits + 1] = #p.bindings .. " keybinds" end
            if p.cvars then bits[#bits + 1] = Count(p.cvars) .. " settings" end
            if p.actions then bits[#bits + 1] = Count(p.actions) .. " action slots" end
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[s.class or ""]
            row.title:SetText(name)
            row.info:SetText(((color and color:WrapTextInColorCode(s.by or "?")) or (s.by or "?")) ..
                "  " .. (s.date or "") .. "   " .. table.concat(bits, ", "))
            row.apply:SetScript("OnClick", function() ApplySetup(name) end)
            row.over:SetScript("OnClick", function() SaveSetup(name); Refresh() end)
            row.del:SetScript("OnClick", function()
                StaticPopup_Show("TRIKKSTWEAKS_DELETE_SETUP", name, nil, { name = name, refresh = Refresh })
            end)
            row:Show()
        end
        for i = #names + 1, #rows do rows[i]:Hide() end
        list:SetHeight(math.max(1, #names * 44))
        empty:SetShown(#names == 0)
    end

    local function DoSave() SaveSetup(nameBox:GetText()); nameBox:SetText(""); nameBox:ClearFocus(); Refresh() end
    saveBtn:SetScript("OnClick", DoSave)
    nameBox:SetScript("OnEnterPressed", DoSave)

    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db.parts[key]) end
        Refresh()
    end
end
