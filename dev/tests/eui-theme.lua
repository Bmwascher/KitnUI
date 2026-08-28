-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-theme.lua                                               ║
-- ║  Purpose: Gate for the KitnUI EllesmereUI options theme.     ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe dev/tests/eui-theme.lua

local failures = 0
local checks = 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
    end
end

local function eq(actual, expected, label)
    check(actual == expected, label, "got " .. tostring(actual) .. ", wanted " .. tostring(expected))
end

local frames = {}
local overlay
local activeTheme = "EllesmereUI"
local appliedAccentTheme = "EllesmereUI"
local onShow

local function NewFrame(parent)
    local frame = {
        parent = parent,
        events = {},
        scripts = {},
        shown = true,
    }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(script, handler) self.scripts[script] = handler end
    function frame:SetAllPoints(target) self.allPoints = target or true end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:EnableMouse(enabled) self.mouseEnabled = enabled end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:CreateTexture()
        local texture = {}
        function texture:SetAllPoints() self.allPoints = true end
        function texture:SetTexture(path) self.path = path end
        self.texture = texture
        return texture
    end
    frames[#frames + 1] = frame
    if parent then overlay = frame end
    return frame
end

_G.CreateFrame = function(_, _, parent) return NewFrame(parent) end
_G.hooksecurefunc = function(tbl, key, hook)
    local original = tbl[key]
    tbl[key] = function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end
end

local mainFrame = {
    GetFrameLevel = function() return 20 end,
}

local EUI = {
    THEME_PRESETS = {
        EllesmereUI = { r = 0, g = 0.8, b = 0.7 },
    },
    THEME_ORDER = { "EllesmereUI", "Dark" },
    _mainFrame = mainFrame,
    GetActiveTheme = function() return activeTheme end,
    SetActiveTheme = function(theme) activeTheme = theme end,
    RefreshAccent = function() appliedAccentTheme = activeTheme end,
    RegisterOnShow = function(_, fn) onShow = fn end,
}
_G.EllesmereUI = EUI

local ns = { EUI_INERT = false }
local themeChunk, themeError = loadfile("KitnUI_EUI/Theme.lua")
check(themeChunk ~= nil, "Theme.lua exists", themeError)
if themeChunk then
    themeChunk("KitnUI_EUI", ns)

    local boot = frames[1]
    check(boot and boot.events.ADDON_LOADED, "theme registration is scheduled before PLAYER_LOGIN")
    if boot and boot.events.ADDON_LOADED then
        boot.scripts.OnEvent(boot, "ADDON_LOADED", "KitnUI_EUI")
    end

    local preset = EUI.THEME_PRESETS.KitnUI
    check(type(preset) == "table", "KitnUI theme preset is registered before PLAYER_LOGIN")
    if preset then
        eq(preset.r, 1, "theme preset uses the KitnUI red channel")
        eq(preset.g, 0, "theme preset uses the KitnUI green channel")
        eq(preset.b, 0.549, "theme preset uses the KitnUI blue channel")
    end
    eq(EUI.THEME_ORDER[2], "KitnUI", "KitnUI follows the default EUI theme")

    check(boot and boot.events.PLAYER_LOGIN, "theme UI wiring waits for PLAYER_LOGIN")
    if boot then boot.scripts.OnEvent(boot, "PLAYER_LOGIN") end
    check(type(onShow) == "function", "panel show synchronization is registered")

    if onShow then onShow() end
    check(overlay ~= nil, "opening the panel creates the background overlay")
    if overlay then
        eq(overlay.parent, mainFrame, "overlay belongs to the EUI panel")
        eq(overlay.frameLevel, 21, "overlay sits above the native background")
        eq(overlay.mouseEnabled, false, "overlay cannot intercept input")
        eq(overlay.shown, false, "overlay stays hidden for another theme")
        eq(overlay.texture and overlay.texture.path,
            "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\KitnUI-EUI-Options.png",
            "overlay uses the shipped KitnUI artwork")
    end

    check(type(ns.ApplyEUIOptionsTheme) == "function", "installer theme API is published locally")
    if ns.ApplyEUIOptionsTheme then
        eq(ns.ApplyEUIOptionsTheme(), true, "installer theme API succeeds")
        eq(activeTheme, "KitnUI", "installer theme API selects KitnUI")
        eq(appliedAccentTheme, "KitnUI", "installer theme API refreshes the KitnUI accent")
        if overlay then eq(overlay.shown, true, "KitnUI selection shows the overlay") end

        EUI.SetActiveTheme("Dark")
        if overlay then eq(overlay.shown, false, "another theme hides the overlay") end
        EUI.SetActiveTheme("KitnUI")
        if overlay then eq(overlay.shown, true, "dropdown selection restores the overlay") end

        ns.ApplyEUIOptionsTheme()
        local count = 0
        for _, name in ipairs(EUI.THEME_ORDER) do
            if name == "KitnUI" then count = count + 1 end
        end
        eq(count, 1, "theme registration is idempotent")
    end
end

local coreFile = assert(io.open("KitnUI_EUI/Core.lua", "rb"))
local coreSource = coreFile:read("*a")
coreFile:close()
check(coreSource:find('"ApplyEUIOptionsTheme"', 1, true) ~= nil,
    "the reverse bridge exports ApplyEUIOptionsTheme")

local manifestFile = assert(io.open("KitnUI_EUI/EUITab.xml", "rb"))
local manifest = manifestFile:read("*a")
manifestFile:close()
local corePos = manifest:find('file="Core.lua"', 1, true)
local themePos = manifest:find('file="Theme.lua"', 1, true)
local firstPagePos = manifest:find('file="Lulu.lua"', 1, true)
check(corePos and themePos and firstPagePos and corePos < themePos and themePos < firstPagePos,
    "Theme.lua loads after Core and before the option pages")

local assetFile = io.open("KitnUI_EUI/Media/Backgrounds/KitnUI-EUI-Options.png", "rb")
check(assetFile ~= nil, "the theme artwork ships with KitnUI_EUI")
if assetFile then
    local header = assetFile:read(24)
    assetFile:close()
    local function U32(offset)
        local a, b, c, d = header:byte(offset, offset + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    eq(U32(17), 1500, "theme artwork width matches EUI")
    eq(U32(21), 1154, "theme artwork height matches EUI")
end

if themeChunk then
    local themeCalls = 0
    local realApply = ns.ApplyEUIOptionsTheme
    ns.ApplyEUIOptionsTheme = function()
        themeCalls = themeCalls + 1
        return realApply()
    end

    _G.C_AddOns = { IsAddOnLoaded = function() return true end }
    _G.strtrim = function(value) return value:match("^%s*(.-)%s*$") end
    _G.UnitName = function() return "Tester" end
    _G.GetRealmName = function() return "Realm" end
    _G.InCombatLockdown = function() return false end
    _G.EllesmereUIDB = { profiles = { KitnUI = {} } }

    EUI.ImportProfileSilent = function() return true end
    EUI.SetProfile = function() end
    EUI.RefreshAllAddons = function() end

    ns.title = "KitnUI"
    ns.profileName = "KitnUI"
    ns.data = { EllesmereUI = "profile-data" }
    ns.db = { profiles = {}, addonVersions = {}, perChar = {} }
    ns.version = "test"
    ns.EUIReady = function() return true end
    ns.GetEUIModuleSet = function() return {} end
    ns.GetAddonDataVersion = function() return "test-data" end
    ns.ApplyEUIModuleSet = function() end
    ns.ApplyLook = function() end
    ns.TopBar = { SetEnabled = function() end }

    local setupChunk = assert(loadfile("Installer/Setup.lua"))
    setupChunk("KitnUI", ns)

    eq(ns.SetupAddon("EllesmereUI", true), true, "EUI profile import succeeds")
    eq(themeCalls, 1, "EUI profile import selects the KitnUI theme")
    eq(ns.SetupAddon("EllesmereUI", false), true, "EUI profile load succeeds")
    eq(themeCalls, 1, "EUI profile load preserves the selected theme")
end

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
