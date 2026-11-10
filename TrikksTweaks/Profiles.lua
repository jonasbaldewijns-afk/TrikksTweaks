-- Trikks Tweaks: export / import of all your Trikks settings as one text string
-- (to share it, or move your setup to another account / PC).
-- The string = your settings turned into data (CBOR), compressed and written as
-- text (Base64), with Blizzard's own C_EncodingUtil. Importing only DECODES
-- that data: a pasted string is never run as code, so it can't do anything
-- but change Trikks settings.
local _, TT = ...
local PREFIX = "TRIKKS1:"

local E = C_EncodingUtil
local function Supported()
    return E and E.SerializeCBOR and E.DeserializeCBOR and E.CompressString and E.DecompressString
        and E.EncodeBase64 and E.DecodeBase64 and true or false
end

-- plain copy of a settings table (only data: no functions, no frames)
local function Copy(t, depth)
    depth = depth or 0
    if type(t) ~= "table" or depth > 20 then return t end
    local out = {}
    for k, v in pairs(t) do
        local tk, tv = type(k), type(v)
        if (tk == "string" or tk == "number") and (tv == "string" or tv == "number" or tv == "boolean" or tv == "table") then
            out[k] = tv == "table" and Copy(v, depth + 1) or v
        end
    end
    return out
end

-- Things in a module's settings that are yours alone and never go into a
-- string: your chat history, and the notes modules keep of what a game setting
-- was before they changed it (to put it back when switched off). Someone who
-- imported those would get YOUR old values "restored" on their account.
local PRIVATE = {
    Chat = { "saved" }, XPBar = { "prevCVar" }, InteractGlow = { "saved" }, CameraVisuals = { "orig" },
    SoundMute = { "origEmotes" }, VendorBags = { "prevFree" },
}
local function StripPrivate(modules)
    for key, fields in pairs(PRIVATE) do
        local m = modules[key]
        if type(m) == "table" then for _, f in ipairs(fields) do m[f] = nil end end
    end
    return modules
end

-- Importing replaces only the modules that are in the string; anything else
-- you have (like saved Setups, when they weren't exported) stays as it is.
-- Your own private parts (see above) of a replaced module are kept.
local function Merge(into, from)
    StripPrivate(from)                       -- strings made by older versions still carry them
    for k, v in pairs(from) do
        local fields, old = PRIVATE[k], into[k]
        if fields and type(old) == "table" and type(v) == "table" then
            for _, f in ipairs(fields) do v[f] = old[f] end
        end
        into[k] = v
    end
    return into
end
-- the parts that can go into a string
local PARTS = {
    { key = "tweaks",  label = "Trikks Tweaks modules", get = function() return TrikksTweaksDB and TrikksTweaksDB.modules end,
      set = function(v)
          TrikksTweaksDB = TrikksTweaksDB or {}
          TrikksTweaksDB.modules = Merge(TrikksTweaksDB.modules or {}, v)
      end },
    { key = "reskins", label = "Trikks Reskins",        get = function() return TrikksReskinDB and TrikksReskinDB.modules end,
      set = function(v)
          TrikksReskinDB = TrikksReskinDB or {}
          TrikksReskinDB.modules = Merge(TrikksReskinDB.modules or {}, v)
      end },
}

local function Export(choice)
    local data = { v = 1 }
    for _, p in ipairs(PARTS) do
        local src = choice[p.key] and p.get()
        if src then
            local c = Copy(src)
            if p.key == "tweaks" then
                -- leave out what is personal or bulky: saved character setups unless asked, dev dumps
                if c.Setups and not choice.setups then c.Setups = nil end
            end
            StripPrivate(c)
            data[p.key] = c
        end
    end
    local raw = E.SerializeCBOR(data)
    return PREFIX .. E.EncodeBase64(E.CompressString(raw))
end

-- returns the decoded table, or nil + why not
local function Decode(text)
    text = (text or ""):gsub("%s+", "")
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, "this isn't a Trikks settings string." end
    local ok, data = pcall(function()
        return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(text:sub(#PREFIX + 1))))
    end)
    if not ok or type(data) ~= "table" or data.v ~= 1 then return nil, "the string is damaged or from a newer version." end
    return data
end

StaticPopupDialogs["TRIKKS_PROFILE_IMPORT"] = {
    text = "Replace your settings for:\n%s\n\nwith the imported ones? Your UI reloads afterwards.",
    button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    OnAccept = function(_, data)
        for _, p in ipairs(PARTS) do
            if data.parts[p.key] and data.profile[p.key] ~= nil then p.set(data.profile[p.key]) end
        end
        C_UI.Reload()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win
local function Build()
    win = TT.Window("TrikksTweaksProfiles", 560, 420, "Export / import", TT.hub)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    local choice = { tweaks = true, reskins = true, setups = false }
    local y = -36
    local checks = {}
    for _, p in ipairs(PARTS) do
        local cb = TT.Check(win, p.label, function(v) choice[p.key] = v end)
        cb:SetPoint("TOPLEFT", 16, y)
        checks[p.key] = cb
        y = y - 22
    end
    local sc = TT.Check(win, "Include your saved Setups (characters' addons, keybinds, ...)", function(v) choice.setups = v end)
    sc:SetPoint("TOPLEFT", 16, y)
    y = y - 30

    -- big text box for the string
    local scroll = TT.Scroll(win)
    scroll:SetPoint("TOPLEFT", 16, y); scroll:SetPoint("BOTTOMRIGHT", -24, 52)
    local bg = CreateFrame("Frame", nil, win, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", scroll, -4, 4); bg:SetPoint("BOTTOMRIGHT", scroll, 12, -4)
    TT.Flat(bg, { 0.03, 0.03, 0.04, 1 })
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(500)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    scroll:SetScrollChild(box)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)

    local status = TT.Label(win, "", "GameFontDisableSmall")
    status:SetPoint("BOTTOMLEFT", 16, 18)

    local exp = TT.Button(win, "Export", 100, function()
        local ok, s = pcall(Export, choice)
        if not ok then status:SetText("|cffff6666Export failed: " .. tostring(s) .. "|r"); return end
        box:SetText(s); box:SetFocus(); box:HighlightText()
        status:SetText("Ctrl+C to copy (" .. #s .. " characters).")
    end)
    exp:SetPoint("BOTTOMRIGHT", -126, 14)
    local imp = TT.Button(win, "Import", 100, function()
        local data, why = Decode(box:GetText())
        if not data then status:SetText("|cffff6666" .. why .. "|r"); return end
        local names, parts = {}, {}
        for _, p in ipairs(PARTS) do
            if choice[p.key] and data[p.key] ~= nil then parts[p.key] = true; names[#names + 1] = p.label end
        end
        if #names == 0 then status:SetText("|cffff6666Nothing to import for the ticked parts.|r"); return end
        StaticPopup_Show("TRIKKS_PROFILE_IMPORT", table.concat(names, ", "), nil, { parts = parts, profile = data })
    end)
    imp:SetPoint("BOTTOMRIGHT", -16, 14)

    win:SetScript("OnShow", function()
        for k, cb in pairs(checks) do cb:SetChecked(choice[k]) end
        sc:SetChecked(choice.setups)
        if Supported() then
            status:SetText("Export: tick what to include. Import: paste a string, tick what to take over.")
        else
            status:SetText("|cffff6666This client can't encode settings (C_EncodingUtil missing).|r")
        end
    end)
end

function TT.OpenProfiles()
    if not win then Build() end
    win:Show()
end
