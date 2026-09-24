-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-reset.lua                                               ║
-- ║  Purpose: Gate for what the full EllesmereUI install records ║
-- ║           for the update: the base string, the cleared       ║
-- ║           report, the scale flag on a kept backup, and the   ║
-- ║           line /kitn reset leaves about the backup profile.  ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe dev/tests/eui-reset.lua

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

---------------------------------------------------------------------------------
-- Stubs
---------------------------------------------------------------------------------

_G.C_AddOns = { IsAddOnLoaded = function() return false end }
_G.strtrim = function(value) return value:match("^%s*(.-)%s*$") end
_G.UnitName = function() return "Tester" end
_G.GetRealmName = function() return "Realm" end
_G.InCombatLockdown = function() return false end
_G.SlashCmdList = {}
_G.hooksecurefunc = function() end
_G.CreateFrame = function()
    local f = {}
    function f.RegisterEvent() end
    function f.SetScript() end
    function f.Hide() end
    function f.Show() end
    return f
end
_G.C_Timer = { After = function() end }
_G.EllesmereUIDB = { profiles = { KitnUI = {} } }

local imports = 0
_G.EllesmereUI = {
    ImportProfileSilent = function() imports = imports + 1 return true end,
    SetProfile = function() end,
    RefreshAllAddons = function() end,
}

local ns = {
    title = "KitnUI",
    profileName = "KitnUI",
    version = "test",
    data = { EllesmereUI = "shipped-string" },
    EUIReady = function() return true end,
    GetEUIModuleSet = function() return {} end,
    GetAddonDataVersion = function(key) return key == "EllesmereUI" and "2026.09.19" or nil end,
    ApplyEUIModuleSet = function() end,
    DecideAccountTheme = function() end,
    ApplyLook = function() end,
    TopBar = { SetEnabled = function() end },
}

local chunk, err = loadfile("Installer/Setup.lua")
if not chunk then
    print("FAIL  could not load Installer/Setup.lua: " .. tostring(err))
    os.exit(1)
end
chunk("KitnUI", ns)

check(type(ns.CompleteSetup) == "function", "ns.CompleteSetup is exported")

---------------------------------------------------------------------------------
-- The full install
---------------------------------------------------------------------------------

ns.db = { profiles = {}, addonVersions = {}, perChar = {}, euiUpdateReport = { conflicts = {} } }
eq(ns.SetupAddon("EllesmereUI", true), true, "the full install succeeds")
eq(imports, 1, "one silent import")
eq(ns.db.euiBase, "shipped-string", "the install records the shipped string as the base")
eq(ns.db.addonVersions.EllesmereUI, "2026.09.19", "the install stamps the version")
eq(ns.db.euiUpdateReport, nil, "the install clears the last update's report")
eq(ns.db.euiBackup, nil, "no backup record is invented")

ns.db = { profiles = {}, addonVersions = {}, perChar = {}, euiBackup = { scaleTaken = false, ppUIScale = 0.9 } }
eq(ns.SetupAddon("EllesmereUI", true), true, "a reset over a kept backup succeeds")
eq(ns.db.euiBackup.scaleTaken, true, "the reset marks the scale as taken")
eq(ns.db.euiBackup.ppUIScale, 0.9, "the recorded scale snapshot is left alone")

-- CompleteSetup from another caller records the base the same way.
ns.db = { profiles = {}, addonVersions = {}, perChar = {} }
ns.CompleteSetup("EllesmereUI")
eq(ns.db.euiBase, "shipped-string", "CompleteSetup alone records the base")
ns.CompleteSetup("BigWigs")
eq(ns.db.euiBase, "shipped-string", "another addon's completion leaves the base alone")

-- A load never records anything.
ns.db = { profiles = { EllesmereUI = true }, addonVersions = {}, perChar = {} }
eq(ns.SetupAddon("EllesmereUI", false), true, "the load succeeds")
eq(ns.db.euiBase, nil, "the load records no base")

---------------------------------------------------------------------------------
-- /kitn reset names the backup profile it cannot take with it
---------------------------------------------------------------------------------

_G.format = string.format
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.C_AddOns.GetAddOnMetadata = function() return "test" end
_G.ReloadUI = function() end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function() end

local core = { data = {} }
local coreChunk, coreErr = loadfile("Installer/Core.lua")
if not coreChunk then
    print("FAIL  could not load Installer/Core.lua: " .. tostring(coreErr))
    os.exit(1)
end
coreChunk("KitnUI", core)
core.EUIBackupName = "KitnUI (before update)"
core.EUIResetAll = function() return true end

local function resetLines(profiles)
    _G.EllesmereUIDB = { profiles = profiles }
    core.db = {}
    _G.KitnUIDB = core.db
    _G.KitnCommands.reset()
    local found = 0
    for _, line in ipairs(_G.KitnUIDB and _G.KitnUIDB.pendingMessages or {}) do
        if line:find("KitnUI (before update)", 1, true) then found = found + 1 end
    end
    return found
end

check(type(_G.KitnCommands) == "table" and type(_G.KitnCommands.reset) == "function", "the reset command is defined")
eq(resetLines({ KitnUI = {}, ["KitnUI (before update)"] = {} }), 1, "a reset with the backup profile present queues one line naming it")
eq(resetLines({ KitnUI = {} }), 0, "a reset with no backup profile queues nothing about it")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
