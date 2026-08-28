-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/Theme.lua                                        ║
-- ║  Purpose: Register and render the KitnUI options themes.     ║
-- ╚══════════════════════════════════════════════════════════════╝

local addonName, ns = ... ---@type string, KitnUINS
if ns.EUI_INERT then return end

local ACCENT = { r = 1, g = 0, b = 0.549 }
local MEDIA = "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\"

-- Dropdown order. Both entries carry the same KitnUI accent; only the artwork
-- differs.
local THEMES = {
    { name = "KitnUI",       texture = MEDIA .. "KitnUI-EUI-Options.png" },
    { name = "KitnUI Rasta", texture = MEDIA .. "KitnUI-EUI-Options-Rasta.png" },
}
local DEFAULT_THEME = THEMES[1].name

local textureFor = {}
for _, theme in ipairs(THEMES) do textureFor[theme.name] = theme.texture end

-- The installer picks between these by character and hands one back to
-- ns.ApplyEUIOptionsTheme. Crossing the addon bridge, so the name is listed in
-- the EXPORTS table in Core.lua; a missing entry there fails silently.
ns.EUIThemeNames = { default = DEFAULT_THEME, alt = THEMES[2].name }

local overlay, overlayTexture

local function RegisterTheme()
    local EUI = _G.EllesmereUI
    if not (EUI and type(EUI.THEME_PRESETS) == "table"
        and type(EUI.THEME_ORDER) == "table") then
        return false
    end

    local at
    for i, name in ipairs(EUI.THEME_ORDER) do
        if name == "EllesmereUI" then at = i end
    end
    at = at or #EUI.THEME_ORDER

    -- Each name lands after the one before it, so a rerun that finds an entry
    -- already there still places the rest in dropdown order behind it.
    for _, theme in ipairs(THEMES) do
        EUI.THEME_PRESETS[theme.name] = { r = ACCENT.r, g = ACCENT.g, b = ACCENT.b }

        local found
        for i, name in ipairs(EUI.THEME_ORDER) do
            if name == theme.name then
                found = i
                break
            end
        end

        if found then
            at = found
        else
            at = at + 1
            table.insert(EUI.THEME_ORDER, at, theme.name)
        end
    end

    return true
end

local function ActiveTheme()
    local EUI = _G.EllesmereUI
    local theme
    if EUI and EUI.GetActiveTheme then
        local ok, active = pcall(EUI.GetActiveTheme)
        if ok then theme = active end
    end
    if theme == nil and _G.EllesmereUIDB then
        theme = EllesmereUIDB.activeTheme
    end
    return theme
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

        overlayTexture = overlay:CreateTexture(nil, "BACKGROUND")
        overlayTexture:SetAllPoints()
    end

    if not (overlay and overlayTexture) then return end

    local active = ActiveTheme()
    local texture = active and textureFor[active]
    if texture then
        overlayTexture:SetTexture(texture)
        overlay:Show()
    else
        overlay:Hide()
    end
end

-- An unregistered or missing name falls back to the default rather than handing
-- the panel a theme it cannot colour.
function ns.ApplyEUIOptionsTheme(themeName)
    local EUI = _G.EllesmereUI
    if not (RegisterTheme() and EUI and EUI.SetActiveTheme) then return false end

    local name = DEFAULT_THEME
    if type(themeName) == "string" and textureFor[themeName] then name = themeName end

    local ok = pcall(EUI.SetActiveTheme, name)
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
