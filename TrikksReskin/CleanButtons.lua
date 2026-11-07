-- Module: Clean Action Buttons
-- Square, cropped icons with a thin border instead of Blizzard's rounded,
-- bronze-framed buttons.
--
-- What makes the default buttons round:
--   * a circular MASK texture on the icon (cuts the square icon into a rounded shape)
--   * a rounded frame texture on top ("NormalTexture")
--   * rounded atlases for the pushed / highlight / checked states, plus slot art
-- We remove the masks, hide the frame and slot art, and swap the state
-- textures for flat squares.
-- Part of TrikksReskin: uses Trikks Tweaks' core (hub, UI kit, module system).
local TT = TrikksTweaks
local M = TT:RegisterModule("CleanButtons", {
    title = "Clean Action Buttons",
    category = "Reskin",
    addon = "TrikksReskin", svName = "TrikksReskinDB",
    desc = "Square, cropped action bar icons with a thin border instead of Blizzard's rounded bronze buttons.",
    defaults = { crop = true, border = 1, hideArt = true, hideMacroText = false, hideHotkeys = false },
})
local WHITE = "Interface\\Buttons\\WHITE8x8"

local BARS = {
    { "ActionButton", 12 }, { "MultiBarBottomLeftButton", 12 }, { "MultiBarBottomRightButton", 12 },
    { "MultiBarRightButton", 12 }, { "MultiBarLeftButton", 12 }, { "MultiBar5Button", 12 },
    { "MultiBar6Button", 12 }, { "MultiBar7Button", 12 }, { "PetActionButton", 10 },
    { "StanceButton", 10 }, { "PossessButton", 2 },
}

-- Turn one of the button's state textures into a flat square over the icon.
local function FlatState(tex, icon, r, g, b, a)
    if not tex then return end
    tex:SetTexture(WHITE)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(r, g, b, a)
    tex:ClearAllPoints()
    tex:SetAllPoints(icon)
end

local function StyleButton(btn, name)
    local db = M.db
    local icon = btn.icon or btn.Icon or _G[name .. "Icon"]
    if not icon then return end

    if not btn.ttClean then
        btn.ttClean = true
        -- 1) remove every mask on the icon -> square icon
        if icon.GetNumMaskTextures then
            for i = icon:GetNumMaskTextures(), 1, -1 do
                icon:RemoveMaskTexture(icon:GetMaskTexture(i))
            end
        end
        -- 2) hide the rounded frame and the slot art (alpha survives Blizzard's SetAtlas calls)
        local normal = btn.GetNormalTexture and btn:GetNormalTexture()
        if normal then normal:SetAlpha(0) end
        for _, key in ipairs({ "SlotArt", "SlotBackground", "FloatingBG" }) do
            if btn[key] then btn[key]:SetAlpha(0) end
        end
        if _G[name .. "FloatingBG"] then _G[name .. "FloatingBG"]:SetAlpha(0) end
        -- 3) flat state textures
        FlatState(btn.GetPushedTexture and btn:GetPushedTexture(), icon, 0, 0, 0, 0.4)
        FlatState(btn.GetHighlightTexture and btn:GetHighlightTexture(), icon, 1, 1, 1, 0.15)
        FlatState(btn.GetCheckedTexture and btn:GetCheckedTexture(), icon, TT.C.accent[1], TT.C.accent[2], TT.C.accent[3], 0.3)
        -- 4) dark square behind the icon (visible on empty slots) + border frame
        btn.ttBg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
        btn.ttBg:SetAllPoints(icon)
        btn.ttBg:SetColorTexture(0.05, 0.05, 0.06, 0.6)
        btn.ttBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        btn.ttBorder:SetAllPoints(icon)
        btn.ttBorder:SetFrameLevel(btn:GetFrameLevel() + 1)
    end

    -- settings that can change live
    if db.crop then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else icon:SetTexCoord(0, 1, 0, 1) end
    if db.border > 0 then
        btn.ttBorder:SetBackdrop({ edgeFile = WHITE, edgeSize = db.border })
        btn.ttBorder:SetBackdropBorderColor(0, 0, 0, 1)
        btn.ttBorder:Show()
    else
        btn.ttBorder:Hide()
    end
    local macro = btn.Name or _G[name .. "Name"]
    if macro then macro:SetAlpha(db.hideMacroText and 0 or 1) end
    local hotkey = btn.HotKey or _G[name .. "HotKey"]
    if hotkey then hotkey:SetAlpha(db.hideHotkeys and 0 or 1) end
end

-- Bronze bar art: end caps (gryphons), border art and background of the main bar.
local function StyleBarArt()
    local bar = MainActionBar or MainMenuBar
    if not bar then return end
    for _, key in ipairs({ "EndCaps", "BorderArt", "Background" }) do
        local part = bar[key]
        if part then part:SetAlpha(M.db.hideArt and 0 or 1) end
    end
end

local pending
local function Apply()
    if not M.enabled then return end
    -- Action buttons are secure: only restyle them out of combat.
    if InCombatLockdown() then pending = true; return end
    pending = false
    for _, bar in ipairs(BARS) do
        for i = 1, bar[2] do
            local name = bar[1] .. i
            local btn = _G[name]
            if btn then StyleButton(btn, name) end
        end
    end
    StyleBarArt()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")      -- stance buttons appear/change
ev:RegisterEvent("PET_BAR_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    Apply()
end)

StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] = StaticPopupDialogs["TRIKKSTWEAKS_RELOAD"] or {
    text = "%s\n\nReload your UI now?",
    button1 = RELOADUI or "Reload", button2 = LATER or "Later",
    OnAccept = function() C_UI.Reload() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local loggedIn = false
function M:OnEnable()
    if loggedIn then Apply() end
end
function M:OnDisable()
    -- Masks and textures we removed can't be put back reliably: reload.
    StaticPopup_Show("TRIKKSTWEAKS_RELOAD", "Clean Action Buttons turned off.")
end
ev:HookScript("OnEvent", function(_, event) if event == "PLAYER_ENTERING_WORLD" then loggedIn = true end end)

function M:BuildSettings(body, page)
    local db = M.db
    local checks = {}
    local function Check(text, key, y)
        local cb = TT.Check(body, text, function(v) db[key] = v; Apply() end)
        cb:SetPoint("TOPLEFT", 2, y)
        checks[key] = cb
    end
    Check("Crop icons (cut off Blizzard's built-in icon border)", "crop", -4)
    Check("Hide bar art (end caps / bronze border of the main bar)", "hideArt", -30)
    Check("Hide macro names", "hideMacroText", -56)
    Check("Hide keybind text", "hideHotkeys", -82)

    local border = TT.Stepper(body, "Border thickness (px)", function() return db.border end,
        function(v) db.border = v; Apply() end, 0, 3, 1)
    border:SetPoint("TOPLEFT", 0, -112)

    local help = TT.Label(body,
        "Changes apply right away (or right after combat, since action buttons\n" ..
        "are protected while you're fighting). Turning the module off needs a\n" ..
        "reload to bring Blizzard's rounded buttons back.",
        "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", border, "BOTTOMLEFT", 0, -14)

    page.OnPageShow = function()
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        border.Refresh()
    end
end
