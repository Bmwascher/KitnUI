-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/Theme.lua                                        ║
-- ║  Purpose: Register and render the KitnUI options theme.      ║
-- ╚══════════════════════════════════════════════════════════════╝

local addonName, ns = ... ---@type string, KitnUINS
if ns.EUI_INERT then return end

local THEME_NAME = "KitnUI"
local THEME_TEXTURE = "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\KitnUI-EUI-Options.png"

local overlay

local function RegisterTheme()
    local EUI = _G.EllesmereUI
    if not (EUI and type(EUI.THEME_PRESETS) == "table"
        and type(EUI.THEME_ORDER) == "table") then
        return false
    end

    EUI.THEME_PRESETS[THEME_NAME] = { r = 1, g = 0, b = 0.549 }

    local defaultIndex
    for i, name in ipairs(EUI.THEME_ORDER) do
        if name == THEME_NAME then return true end
        if name == "EllesmereUI" then defaultIndex = i end
    end

    table.insert(EUI.THEME_ORDER, defaultIndex and (defaultIndex + 1) or (#EUI.THEME_ORDER + 1), THEME_NAME)
    return true
end

local function SyncOverlay()
    local EUI = _G.EllesmereUI
    if not EUI then return end

    local mainFrame = EUI._mainFrame
    if mainFrame and not overlay then
        if not (mainFrame.GetFrameLevel and CreateFrame) then return end
        overlay = CreateFrame("Frame", nil, mainFrame)
        overlay:SetAllPoints(mainFrame)
        overlay:SetFrameLevel(mainFrame:GetFrameLevel() + 1)
        overlay:EnableMouse(false)

        local texture = overlay:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        texture:SetTexture(THEME_TEXTURE)
    end

    if not overlay then return end

    local theme
    if EUI.GetActiveTheme then
        local ok, active = pcall(EUI.GetActiveTheme)
        if ok then theme = active end
    end
    if theme == nil and _G.EllesmereUIDB then
        theme = EllesmereUIDB.activeTheme
    end

    if theme == THEME_NAME then overlay:Show() else overlay:Hide() end
end

function ns.ApplyEUIOptionsTheme()
    local EUI = _G.EllesmereUI
    if not (RegisterTheme() and EUI and EUI.SetActiveTheme) then return false end

    local ok = pcall(EUI.SetActiveTheme, THEME_NAME)
    if not ok then return false end
    if EUI.RefreshAccent then pcall(EUI.RefreshAccent) end
    SyncOverlay()
    return true
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" then
        if loadedAddon ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        RegisterTheme()
        return
    end

    self:UnregisterEvent("PLAYER_LOGIN")
    if not RegisterTheme() then return end

    local EUI = _G.EllesmereUI
    if EUI.RegisterOnShow then
        pcall(EUI.RegisterOnShow, EUI, SyncOverlay)
    end
    if EUI.SetActiveTheme and type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, EUI, "SetActiveTheme", SyncOverlay)
    end
    SyncOverlay()
end)
