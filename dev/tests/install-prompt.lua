-- ╔══════════════════════════════════════════════════════════════╗
-- ║  install-prompt.lua                                          ║
-- ║  Purpose: Gate for the /kitn install overwrite prompt: an    ║
-- ║           install record or the account's profiles raise     ║
-- ║           it, a character's other stored settings do not.    ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/install-prompt.lua

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

local playerName = "Tester"
local popups = {}

_G.C_AddOns = {
    GetAddOnMetadata = function() return "1.0.0" end,
    IsAddOnLoaded = function() return true end,
}
_G.CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
end
_G.SlashCmdList = {}
_G.UnitName = function() return playerName end
_G.GetRealmName = function() return "Realm" end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(name) popups[#popups + 1] = name return true end

local ns = { data = {}, Wizard = {} }
for _, path in ipairs({ "Installer/Core.lua", "Installer/Setup.lua" }) do
    local chunk, err = loadfile(path)
    if not chunk then
        print("FAIL  could not load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", ns)
end

local KEY = "Tester-Realm"
local opened = 0
ns.OpenInstaller = function() opened = opened + 1 end
ns.ApplyEUIModuleSet = function() end
ns.CleanMinimapIcons = function() end

-- A fresh account holding one character record, or none.
local function account(rec)
    ns.db = { profiles = {}, addonVersions = {}, perChar = { [KEY] = rec } }
    ns.characterWorkApplied = nil
end

-- Runs /kitn install. Returns whether the prompt showed and whether the wizard
-- opened straight away.
local function install()
    for i = #popups, 1, -1 do popups[i] = nil end
    opened = 0
    _G.KitnCommands.install()
    return popups[1] == "KITNUI_OVERWRITE_CONFIRM", opened == 1
end

local function expectFresh(label)
    local prompted, wizard = install()
    eq(prompted, false, label .. ": no prompt")
    eq(wizard, true, label .. ": the wizard opens")
end

local function expectPrompt(label)
    local prompted, wizard = install()
    eq(prompted, true, label .. ": the prompt shows")
    eq(wizard, false, label .. ": the wizard waits for the answer")
end

---------------------------------------------------------------------------------
-- A record without the install field is not an install
---------------------------------------------------------------------------------

account(nil)
expectFresh("no record")

-- The shape the XP session save leaves at the first logout.
account({ xp = { gained = 0, lastXP = 0, lastMax = 250, lastLevel = 1, elapsed = 5 } })
expectFresh("XP session only")

account(nil)
eq(ns.SetInstallerTheme("alt"), true, "the theme choice stored")
expectFresh("installer theme only")

account(nil)
eq(ns:MarkEditModeApplied(), true, "the Edit Mode mark stored")
expectFresh("Edit Mode mark only")

account({ layoutWatchOff = { [1] = true } })
expectFresh("layout watch opt-out only")

account({ loaded = false })
expectFresh("loaded false")

---------------------------------------------------------------------------------
-- The install record raises it, through the writers that run headless
---------------------------------------------------------------------------------

account({ loaded = true })
expectPrompt("loaded true")

account(nil)
ns:SetCharLoaded()
expectPrompt("SetCharLoaded")

account(nil)
ns.CompleteSetup("BigWigs")
eq(ns.db.perChar[KEY].loaded, true, "an imported profile writes the install record")
expectPrompt("an imported profile")

account(nil)
ns.ApplyCharacterWork()
expectPrompt("the wizard's character work")

-- The order a real character meets them in: the XP row first, the install after.
account({ xp = { gained = 0 } })
expectFresh("before the install")
ns.CompleteSetup("BigWigs")
expectPrompt("an install over an XP record")
check(type(ns.db.perChar[KEY].xp) == "table", "the install keeps the XP record")

---------------------------------------------------------------------------------
-- An alt on an installed account overwrites the same shared profiles
---------------------------------------------------------------------------------

account(nil)
ns.db.profiles.BigWigs = true
expectPrompt("an alt with no record")

account({ xp = { gained = 0 } })
ns.db.profiles.BigWigs = true
expectPrompt("an alt with only an XP record")

-- The Cooldown Manager's entry is a table rather than a flag.
account(nil)
ns.db.profiles.BlizzardCDM = { WARRIOR_1 = "fingerprint" }
expectPrompt("an alt on an account with only Cooldown Manager layouts")

account(nil)
ns.db.profiles = nil
expectFresh("no profile list")

---------------------------------------------------------------------------------
-- The prompt's own contract
---------------------------------------------------------------------------------

account({ loaded = true })
install()
opened = 0
StaticPopupDialogs.KITNUI_OVERWRITE_CONFIRM.OnAccept()
eq(opened, 1, "Yes opens the wizard")

-- No identifiable character: refused, whatever the account holds.
account({ loaded = true })
playerName = nil
local realPrint = _G.print
_G.print = function() end
local prompted, wizard = install()
_G.print = realPrint
playerName = "Tester"
eq(prompted, false, "no character key: no prompt")
eq(wizard, false, "no character key: the wizard stays closed")

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
