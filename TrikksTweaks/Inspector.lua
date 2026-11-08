-- Trikks Tweaks: frame inspector (developer tool, not a module)
-- /trikks dump            -> dumps the window under your mouse
-- /trikks dump FrameName  -> dumps a frame by its global name
-- The result is stored in TrikksTweaksDB.dumps and written to disk on /reload
-- or logout (WTF\Account\<account>\SavedVariables\TrikksTweaks.lua).
local _, TT = ...
local MAX_NODES, MAX_DEPTH, MAX_KIDS = 4000, 12, 40

local function S(v)                            -- safe tostring (secret values)
    if v == nil then return "" end
    if TT.IsSecret(v) then return "<secret>" end
    return tostring(v)
end

-- Which key does the parent use for this child? (e.g. frame.NineSlice -> "NineSlice")
local function ParentKey(parent, child)
    if not parent then return nil end
    for k, v in pairs(parent) do
        if v == child and type(k) == "string" then return k end
    end
end

local function Describe(obj, parent, idx)
    local name = obj.GetName and obj:GetName()
    local key = ParentKey(parent, obj)
    return name or (key and ("." .. key)) or ("[" .. idx .. "]")
end

function TT.Dump(target)
    local frame
    if target and target ~= "" then
        -- a global name, or a path like WorldMapFrame.BorderFrame
        for part in target:gmatch("[^%.]+") do
            frame = (frame == nil) and _G[part] or (type(frame) == "table" and frame[part] or nil)
            if frame == nil then break end
        end
        if type(frame) ~= "table" or not frame.GetObjectType then TT.Print("no frame called " .. target); return end
    else
        local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
        frame = foci and foci[1]
        if not frame or frame == WorldFrame then TT.Print("hover over a window first"); return end
        -- climb up to the top-level window
        while frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
    end

    local lines, count = {}, 0
    local function Add(depth, text) lines[#lines + 1] = string.rep("  ", depth) .. text end

    local function Walk(f, parent, depth, idx)
        count = count + 1
        if count > MAX_NODES or depth > MAX_DEPTH then return end
        local w, h = f:GetSize()
        Add(depth, string.format("%s <%s> %dx%d%s", Describe(f, parent, idx), f:GetObjectType(),
            w or 0, h or 0, f:IsShown() and "" or " (hidden)"))
        for i, r in ipairs({ f:GetRegions() }) do
            count = count + 1
            local t = r:GetObjectType()
            local info = ""
            if t == "Texture" or t == "MaskTexture" then
                local layer, sub = r:GetDrawLayer()
                info = string.format(" %s:%s tex=%s atlas=%s", S(layer), S(sub), S(r:GetTexture()),
                    S(r.GetAtlas and r:GetAtlas()))
            elseif t == "FontString" then
                info = " text=\"" .. S(r:GetText()):sub(1, 40) .. "\""
            end
            Add(depth + 1, "- " .. Describe(r, f, i) .. " <" .. t .. ">" .. info .. (r:IsShown() and "" or " (hidden)"))
        end
        -- huge child lists (map pins, list rows) would eat the whole budget:
        -- summarise them in one line instead
        local kids = { f:GetChildren() }
        if #kids > MAX_KIDS then
            Add(depth + 1, string.format("(%d children, not listed)", #kids))
        else
            for i, c in ipairs(kids) do Walk(c, f, depth + 1, i) end
        end
    end
    Walk(frame, nil, 0, 1)

    local name = frame:GetName() or (target ~= "" and target) or "unnamed"
    TrikksTweaksDB.dumps = TrikksTweaksDB.dumps or {}
    TrikksTweaksDB.dumps[name] = lines
    TT.Print(string.format("dumped %s (%d lines). /reload to save it to disk.", name, #lines))
end
