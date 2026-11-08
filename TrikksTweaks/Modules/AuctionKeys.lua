-- Module: Auction House Keys
-- Keys for the auction house sell page: one for "Create Auction" (Space by
-- default) and one for the "Max" quantity button (Shift-Space).
--
-- How (and why this way): posting an auction is one of the actions the game
-- only allows from a real key press or click. So the key doesn't call the
-- posting function itself: it "clicks" Blizzard's own Create Auction / Max
-- button, and the key press stays attached to that click.
-- The keys are only bound while a sell page is open (override bindings, gone
-- again when it closes), so Space jumps as usual everywhere else. While you
-- type in a price box, the box gets the keys first.
local _, TT = ...
local M = TT:RegisterModule("AuctionKeys", {
    title = "Auction House Keys",
    category = "Quality of Life",
    desc = "Keys on the auction house sell page: Create Auction (Space) and Max quantity (Shift-Space).",
    defaults = { postKey = "SPACE", maxKey = "SHIFT-SPACE" },
})

local owner, postBtn, maxBtn       -- made in Setup
local pending = false              -- binding change waiting for combat to end

-- the sell page that is open right now (commodities or single items)
local function SellFrame()
    local ah = AuctionHouseFrame
    if not (ah and ah:IsShown()) then return nil end
    for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
        local f = ah[k]
        if f and f:IsShown() then return f end
    end
end

local function ClickIfEnabled(b)
    if b and b:IsShown() and b:IsEnabled() then b:Click() end
end

local function Bind()
    if not owner then return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    ClearOverrideBindings(owner)
    if not (M.enabled and SellFrame()) then return end
    if M.db.postKey and M.db.postKey ~= "" then SetOverrideBindingClick(owner, true, M.db.postKey, postBtn:GetName()) end
    if M.db.maxKey and M.db.maxKey ~= "" then SetOverrideBindingClick(owner, true, M.db.maxKey, maxBtn:GetName()) end
end

local hooked = false
local function HookSellFrames()
    local ah = AuctionHouseFrame
    if hooked or not ah then return end
    hooked = true
    for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
        local f = ah[k]
        if f then
            f:HookScript("OnShow", Bind)
            f:HookScript("OnHide", function() C_Timer.After(0, Bind) end)
        end
    end
end

function M:Setup()
    owner = CreateFrame("Frame")
    -- hidden buttons the keys "click"; they pass the click on to Blizzard's buttons
    postBtn = CreateFrame("Button", "TrikksTweaksAHPost", UIParent)
    postBtn:SetScript("OnClick", function()
        local f = SellFrame()
        ClickIfEnabled(f and f.PostButton)
    end)
    maxBtn = CreateFrame("Button", "TrikksTweaksAHMax", UIParent)
    maxBtn:SetScript("OnClick", function()
        local f = SellFrame()
        ClickIfEnabled(f and f.QuantityInput and f.QuantityInput.MaxButton)
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("AUCTION_HOUSE_SHOW")
    ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pending then Bind() end
            return
        end
        if event == "AUCTION_HOUSE_SHOW" then HookSellFrames() end
        C_Timer.After(0, Bind)                 -- after Blizzard has set up its pages
    end)
end

function M:OnEnable() HookSellFrames(); Bind() end
function M:OnDisable() Bind() end              -- not enabled: clears the keys

---------------------------------------------------------------------------
-- Settings: click a key button, then press the key (with Shift / Ctrl / Alt)
---------------------------------------------------------------------------
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }
local function KeyButton(parent, get, set)
    local b = TT.Button(parent, "", 150, nil)
    local listening = false
    local function Show()
        if listening then b:SetText("|cff33ff99press a key...|r")
        else b:SetText(get() ~= "" and GetBindingText(get()) or "(none)") end
    end
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then set(""); listening = false; self:EnableKeyboard(false); Show(); return end
        listening = not listening
        self:EnableKeyboard(listening)
        Show()
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnKeyDown", function(self, key)
        if not listening or MODIFIERS[key] then return end
        listening = false
        self:EnableKeyboard(false)
        if key ~= "ESCAPE" then
            local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
                .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
            set(combo)
        end
        Show()
    end)
    b.Refresh = Show
    return b
end

function M:BuildSettings(body, page)
    local db = M.db
    local rows = {}
    local function Row(y, text, key)
        local l = TT.Label(body, text)
        l:SetPoint("TOPLEFT", 2, -y - 4)
        local b = KeyButton(body, function() return db[key] or "" end, function(v) db[key] = v; Bind() end)
        b:SetPoint("TOPLEFT", 200, -y)
        rows[#rows + 1] = b
    end
    Row(0, "Create Auction", "postKey")
    Row(30, "Max quantity", "maxKey")
    local help = TT.Label(body,
        "Click a key button, then press the key (Shift / Ctrl / Alt combinations work).\n" ..
        "Esc cancels, right-click clears. The keys only work while the auction house sell\n" ..
        "page is open; everywhere else they do what they normally do. While you type in\n" ..
        "a price box, the box gets the keys.", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 0, -72)
    page.OnPageShow = function() for _, b in ipairs(rows) do b.Refresh() end end
end
