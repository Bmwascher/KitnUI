-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-theme.lua                                               ║
-- ║  Purpose: Gate for the KitnUI EllesmereUI options themes.    ║
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

-- Dropdown order, artwork and shipped file for every KitnUI theme. Both carry the
-- brand accent: a theme chooses artwork and nothing else.
local MEDIA = "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\"
local BRAND_ACCENT = { r = 1, g = 0, b = 0.549 }
local THEMES = {
    { name = "KitnUI",       file = "KitnUI-EUI-Options.png" },
    { name = "KitnUI Rasta", file = "KitnUI-EUI-Options-Rasta.png" },
}
local DEFAULT_THEME = THEMES[1].name
local ALT_THEME = THEMES[2].name

local frames = {}
local overlay
local activeTheme = "EllesmereUI"
local appliedAccentTheme = "EllesmereUI"
local onShow

local charName, charRealm = "Tester", "Realm"
local function AsCharacter(name, realm)
    charName, charRealm = name, realm
end

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
        self.textureCount = (self.textureCount or 0) + 1
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

    for i, theme in ipairs(THEMES) do
        local preset = EUI.THEME_PRESETS[theme.name]
        check(type(preset) == "table", theme.name .. " preset is registered before PLAYER_LOGIN")
        if preset then
            eq(preset.r, BRAND_ACCENT.r, theme.name .. " preset uses the brand red channel")
            eq(preset.g, BRAND_ACCENT.g, theme.name .. " preset uses the brand green channel")
            eq(preset.b, BRAND_ACCENT.b, theme.name .. " preset uses the brand blue channel")
        end
        eq(EUI.THEME_ORDER[i + 1], theme.name, theme.name .. " follows the default EUI theme in order")
    end
    eq(#EUI.THEME_ORDER, 4, "exactly two KitnUI themes reach the dropdown")

    check(type(ns.EUIThemeNames) == "table", "the theme names are published for the installer")
    if type(ns.EUIThemeNames) == "table" then
        eq(ns.EUIThemeNames.default, DEFAULT_THEME, "the published default name is Theme A")
        eq(ns.EUIThemeNames.alt, ALT_THEME, "the published alternate name is Theme B")
    end

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
    end

    check(type(ns.ApplyEUIOptionsTheme) == "function", "installer theme API is published locally")
    if ns.ApplyEUIOptionsTheme and overlay then
        -- Both themes paint the one overlay with their own artwork.
        for _, theme in ipairs(THEMES) do
            EUI.SetActiveTheme(theme.name)
            eq(overlay.shown, true, theme.name .. " selection shows the overlay")
            eq(overlay.texture and overlay.texture.path, MEDIA .. theme.file,
                theme.name .. " selection paints its own artwork")
        end
        eq(overlay.textureCount, 1, "theme switching reuses one overlay texture")

        EUI.SetActiveTheme("Dark")
        eq(overlay.shown, false, "another theme hides the overlay")

        eq(ns.ApplyEUIOptionsTheme(), true, "installer theme API succeeds")
        eq(activeTheme, DEFAULT_THEME, "installer theme API defaults to Theme A")
        eq(appliedAccentTheme, DEFAULT_THEME, "installer theme API refreshes the KitnUI accent")
        eq(overlay.shown, true, "installer theme API shows the overlay")

        eq(ns.ApplyEUIOptionsTheme(ALT_THEME), true, "installer theme API accepts a named theme")
        eq(activeTheme, ALT_THEME, "installer theme API selects the named theme")
        eq(overlay.texture and overlay.texture.path, MEDIA .. THEMES[2].file,
            "installer theme API paints the named artwork")

        ns.ApplyEUIOptionsTheme("Not A KitnUI Theme")
        eq(activeTheme, DEFAULT_THEME, "an unregistered name falls back to Theme A")
        ns.ApplyEUIOptionsTheme(ALT_THEME)
        ns.ApplyEUIOptionsTheme(nil)
        eq(activeTheme, DEFAULT_THEME, "a nil name falls back to Theme A")

        for _, theme in ipairs(THEMES) do
            local count = 0
            for _, name in ipairs(EUI.THEME_ORDER) do
                if name == theme.name then count = count + 1 end
            end
            eq(count, 1, theme.name .. " registration is idempotent")
        end
    end
end

local coreFile = assert(io.open("KitnUI_EUI/Core.lua", "rb"))
local coreSource = coreFile:read("*a")
coreFile:close()
check(coreSource:find('"ApplyEUIOptionsTheme"', 1, true) ~= nil,
    "the reverse bridge exports ApplyEUIOptionsTheme")
check(coreSource:find('"EUIThemeNames"', 1, true) ~= nil,
    "the reverse bridge exports EUIThemeNames")

local manifestFile = assert(io.open("KitnUI_EUI/EUITab.xml", "rb"))
local manifest = manifestFile:read("*a")
manifestFile:close()
local corePos = manifest:find('file="Core.lua"', 1, true)
local themePos = manifest:find('file="Theme.lua"', 1, true)
local firstPagePos = manifest:find('file="Lulu.lua"', 1, true)
check(corePos and themePos and firstPagePos and corePos < themePos and themePos < firstPagePos,
    "Theme.lua loads after Core and before the option pages")

for _, theme in ipairs(THEMES) do
    local path = "KitnUI_EUI/Media/Backgrounds/" .. theme.file
    local assetFile = io.open(path, "rb")
    check(assetFile ~= nil, theme.name .. " artwork ships with KitnUI_EUI")
    if assetFile then
        local header = assetFile:read(24)
        assetFile:close()
        local function U32(offset)
            local a, b, c, d = header:byte(offset, offset + 3)
            return ((a * 256 + b) * 256 + c) * 256 + d
        end
        eq(U32(17), 1500, theme.name .. " artwork width matches EUI")
        eq(U32(21), 1154, theme.name .. " artwork height matches EUI")
    end
end

-- The only artwork left in the folder is the two shipped themes; a comparison
-- candidate left behind would ship to players as dead weight.
do
    local listed = io.popen('dir /b "KitnUI_EUI\\Media\\Backgrounds"')
    if listed then
        local shipped = {}
        for line in listed:lines() do
            line = line:gsub("%s+$", "")
            if line ~= "" then shipped[#shipped + 1] = line end
        end
        listed:close()
        eq(#shipped, #THEMES, "no leftover comparison artwork ships")
    end
end

_G.C_AddOns = {
    IsAddOnLoaded = function() return true end,
    GetAddOnMetadata = function() return "test" end,
}
_G.strtrim = function(value) return value:match("^%s*(.-)%s*$") end
_G.UnitName = function() return charName end
_G.GetRealmName = function() return charRealm end
_G.InCombatLockdown = function() return false end
_G.SlashCmdList = {}
_G.EllesmereUIDB = { profiles = { KitnUI = {} } }

local installerCore, installerCoreError = loadfile("Installer/Core.lua")
check(installerCore ~= nil, "Installer/Core.lua exists", installerCoreError)
if installerCore then
    local loaded, runError = pcall(installerCore, "KitnUI", ns)
    check(loaded, "Installer/Core.lua loads in the test harness", runError)
end

check(type(ns.EUIThemeForCharacter) == "function", "the installer publishes a per-character theme choice")
if type(ns.EUIThemeForCharacter) == "function" then
    -- Exact recognition, compared without spaces, apostrophes or case, because
    -- the live realm string is punctuated and a mismatch silently picks Theme A.
    local allowed = {
        { "Cznfik", "Area 52" },
        { "Rescuelol", "Mal'Ganis" },
        { "Zenfiki", "Area 52" },
        { "Cznp", "Area 52" },
        { "Bite", "Area 52" },
        { "Cheeklord", "Area 52" },
        { "Cheekgripper", "Area 52" },
        { "Glizzygordo", "Area 52" },
        { "Frankcole", "Area 52" },
    }
    local hasRoster = type(ns.OnAltThemeRoster) == "function"
    check(hasRoster, "the installer publishes the roster test")
    local function OnRoster()
        if not hasRoster then return "<missing>" end
        return ns.OnAltThemeRoster()
    end

    for _, who in ipairs(allowed) do
        AsCharacter(who[1], who[2])
        eq(ns.EUIThemeForCharacter(), ALT_THEME, who[1] .. "-" .. who[2] .. " gets Theme B")
        eq(OnRoster(), true, who[1] .. "-" .. who[2] .. " is on the roster")
    end

    AsCharacter("Cznfik", "Area52")
    eq(ns.EUIThemeForCharacter(), ALT_THEME, "an unspaced realm still matches")
    AsCharacter("cznfik", "area 52")
    eq(ns.EUIThemeForCharacter(), ALT_THEME, "letter case does not decide the theme")
    AsCharacter("Rescuelol", "MalGanis")
    eq(ns.EUIThemeForCharacter(), ALT_THEME, "a realm apostrophe does not decide the theme")

    AsCharacter("Stranger", "Area 52")
    eq(ns.EUIThemeForCharacter(), DEFAULT_THEME, "an unlisted name gets Theme A")
    eq(OnRoster(), false, "an unlisted name is off the roster")
    AsCharacter("Cznfik", "Another Realm")
    eq(ns.EUIThemeForCharacter(), DEFAULT_THEME, "a listed name on another realm gets Theme A")
    AsCharacter("Cznf", "Area 52")
    eq(ns.EUIThemeForCharacter(), DEFAULT_THEME, "a partial name match gets Theme A")
    AsCharacter(nil, "Area 52")
    eq(ns.EUIThemeForCharacter(), DEFAULT_THEME, "an unreadable character name gets Theme A")
    eq(OnRoster(), false, "an unreadable character name is off the roster")
    AsCharacter("Tester", "Realm")
end

-- The installer wizard art follows the same roster. Its texcoords crop a fixed
-- rectangle out of the file, so a background of another shape would crop wrong.
do
    local function TgaHeader(path)
        local file = io.open(path, "rb")
        if not file then return nil end
        local header = file:read(18)
        file:close()
        if not header or #header < 18 then return nil end
        local b = { header:byte(1, 18) }
        return {
            imageType  = b[3],
            width      = b[13] + b[14] * 256,
            height     = b[15] + b[16] * 256,
            depth      = b[17],
            descriptor = b[18],
        }
    end

    local shipped = TgaHeader("Media/Background/KitnUI-EUI-Background.tga")
    local alt = TgaHeader("Media/Background/KitnUI-EUI-Background-Rasta.tga")
    check(shipped ~= nil, "the default installer background is readable")
    check(alt ~= nil, "the alternate installer background ships")
    if shipped and alt then
        eq(alt.width, shipped.width, "alternate background width matches the default")
        eq(alt.height, shipped.height, "alternate background height matches the default")
        eq(alt.depth, shipped.depth, "alternate background bit depth matches the default")
        eq(alt.imageType, shipped.imageType, "alternate background is the same TGA type")
        eq(alt.descriptor, shipped.descriptor, "alternate background shares origin and alpha bits")
    end

    local wizardFile = assert(io.open("Installer/Wizard.lua", "rb"))
    local wizardSource = wizardFile:read("*a")
    wizardFile:close()
    check(wizardSource:find("KitnUI-EUI-Background-Rasta.tga", 1, true) ~= nil,
        "the wizard names the alternate background")
    check(wizardSource:find("ns.OnAltThemeRoster", 1, true) ~= nil,
        "the wizard picks its background from the roster")

    -- The wizard chrome follows the roster, but the exported brand colour must
    -- not: the Nameplates page defaults its target arrow to it.
    check(wizardSource:find("local KITN_PINK = { 1, 0, 0.549 }", 1, true) ~= nil,
        "the brand accent value is unchanged")
    check(wizardSource:find("ns.KITN_PINK = KITN_PINK", 1, true) ~= nil,
        "the brand accent is still exported unchanged")
    check(wizardSource:find("accent = ns.OnAltThemeRoster()", 1, true) ~= nil,
        "the wizard resolves its accent from the roster")
    check(wizardSource:find("KITN_PINK%[") == nil,
        "no wizard chrome paints from the brand constant directly")
    check(wizardSource:find("local P = KITN_PINK", 1, true) == nil,
        "the button variant helper paints from the resolved accent")
end

-- The installer chrome and the named accent choice must be the same amber. Two
-- copies of a colour drift, which is why the brand pink already carries a
-- keep-in-step warning in three files.
do
    local wizardFile = assert(io.open("Installer/Wizard.lua", "rb"))
    local wizardSource = wizardFile:read("*a")
    wizardFile:close()

    local generalFile = assert(io.open("KitnUI_EUI/General.lua", "rb"))
    local generalSource = generalFile:read("*a")
    generalFile:close()

    local wr, wg, wb = wizardSource:match("RASTA_AMBER = { ([%d%.]+), ([%d%.]+), ([%d%.]+) }")
    local gr, gg, gb = generalSource:match("RASTA_R, RASTA_G, RASTA_B = ([%d%.]+), ([%d%.]+), ([%d%.]+)")
    check(wr ~= nil, "the wizard declares the alternate accent")
    check(gr ~= nil, "the KitnUI page declares the alternate accent")
    if wr and gr then
        eq(gr, wr, "the named accent red channel matches the installer chrome")
        eq(gg, wg, "the named accent green channel matches the installer chrome")
        eq(gb, wb, "the named accent blue channel matches the installer chrome")
    end

    check(generalSource:find("Use Rasta Amber", 1, true) ~= nil,
        "the KitnUI page offers the alternate accent by name")
    check(generalSource:find("IsRastaAmber", 1, true) ~= nil,
        "the page can tell whether the stored accent is the alternate one")
end

-- The two named colour switches share one row. Built as full-width rows they
-- read as a list rather than a pair of alternatives, and pushed the swatch that
-- they both write down the page.
do
    local generalFile = assert(io.open("KitnUI_EUI/General.lua", "rb"))
    local generalSource = generalFile:read("*a")
    generalFile:close()

    local sectionStart = generalSource:find('SectionHeader(parent, "ACCENTS"', 1, true)
    local sectionEnd = generalSource:find('SectionHeader(parent, "TWEAKS"', 1, true)
    check(sectionStart ~= nil and sectionEnd ~= nil and sectionEnd > sectionStart,
        "the accent section can be isolated from the rest of the page")

    if sectionStart and sectionEnd and sectionEnd > sectionStart then
        local section = generalSource:sub(sectionStart, sectionEnd)

        local dualRows = 0
        for _ in section:gmatch("W:DualRow") do dualRows = dualRows + 1 end
        eq(dualRows, 1, "the accent section builds exactly one dual row")

        local dualAt = section:find("W:DualRow", 1, true)
        local pinkAt = section:find("Use KitnUI Pink", 1, true)
        local amberAt = section:find("Use Rasta Amber", 1, true)
        check(pinkAt ~= nil and amberAt ~= nil,
            "both named colour switches are still on the page")
        check(dualAt ~= nil and pinkAt ~= nil and amberAt ~= nil
            and pinkAt > dualAt and amberAt > pinkAt,
            "both named colour switches sit in the dual row, pink on the left")

        check(section:find('W:Toggle(parent, "Use ', 1, true) == nil,
            "neither named colour switch is built as a full-width row")

        local veils = 0
        for _ in section:gmatch("Veil%(") do veils = veils + 1 end
        eq(veils, 2, "one veil covers the shared row and one covers the swatch")
    end
end

if themeChunk then
    local themeCalls = 0
    local lastThemeArg
    local realApply = ns.ApplyEUIOptionsTheme
    ns.ApplyEUIOptionsTheme = function(name, ...)
        themeCalls = themeCalls + 1
        lastThemeArg = name
        return realApply(name, ...)
    end

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
    eq(themeCalls, 1, "EUI profile import selects a KitnUI theme")
    eq(lastThemeArg, DEFAULT_THEME, "an unlisted character imports with Theme A")
    eq(activeTheme, DEFAULT_THEME, "an unlisted character ends on Theme A")

    AsCharacter("Zenfiki", "Area 52")
    eq(ns.SetupAddon("EllesmereUI", true), true, "EUI profile import succeeds for a listed character")
    eq(lastThemeArg, ALT_THEME, "a listed character imports with Theme B")
    eq(activeTheme, ALT_THEME, "a listed character ends on Theme B")

    eq(ns.SetupAddon("EllesmereUI", false), true, "EUI profile load succeeds")
    eq(themeCalls, 2, "EUI profile load preserves the selected theme")
    eq(activeTheme, ALT_THEME, "EUI profile load leaves the active theme alone")
end

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
