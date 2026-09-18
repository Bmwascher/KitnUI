-- ╔══════════════════════════════════════════════════════════════╗
-- ║  step-skip.lua                                               ║
-- ║  Purpose: Gate for the per-step skip: its version token and  ║
-- ║           the paths that honour or retire it.                ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe dev/tests/step-skip.lua
--
-- The one property worth a gate: a skip stores the SHIPPED VERSION, not a
-- boolean, so it retires itself when a newer profile ships. A boolean would
-- pass every other assertion here and hold the step down forever.

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
-- Stubs: the WoW surface the three loaded chunks touch, and nothing more
---------------------------------------------------------------------------------

-- The versions KitnUI currently ships, keyed by TOC header. Mutable, because
-- moving one of these is exactly what a shipped update looks like.
local shipped = {
    ["X-BigWigs-Version"]        = "2026.08.22.1",
    ["X-EllesmereUI-Version"]    = "2026.08.22",
    ["X-KitnEssentials-Version"] = "2026.08.30",
}

_G.format = string.format
_G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.CopyTable = function(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and _G.CopyTable(v) or v end
    return c
end
-- IsAddOnLoaded before any chunk loads: Setup.lua and Installer.lua capture it
-- into a local at file scope, so a stub added later would never be seen.
_G.C_AddOns = {
    GetAddOnMetadata = function(_, header) return shipped[header] end,
    IsAddOnLoaded = function() return true end,
}
_G.tinsert = table.insert
_G.InCombatLockdown = function() return false end
_G.C_Timer = { After = function() end }
_G.CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
end
_G.SlashCmdList = {}
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
_G.C_SpecializationInfo = {
    GetNumSpecializationsForClassID = function() return 3 end,
    GetSpecialization = function() return 1 end,
}
_G.GetSpecializationInfoForClassID = function(_, i) return 70 + i, "Spec" .. i, "", 12345 end
_G.UnitName = function() return "Tester" end
_G.GetRealmName = function() return "Realm" end
_G.ReloadUI = function() end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function() end
_G.print = print

---------------------------------------------------------------------------------
-- Load the shipped chunk
---------------------------------------------------------------------------------

-- Installer.lua assigns into ns.Wizard at file scope; the shell that normally
-- creates it (Wizard.lua) needs a live frame API and is not loaded here.
local ns = { data = {}, Wizard = {} }

local function loadChunk(path)
    local chunk, err = loadfile(path)
    if not chunk then
        print("FAIL  could not load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", ns)
end

loadChunk("Data/Classes/BlizzardCDM.lua")
loadChunk("Installer/Core.lua")
loadChunk("Installer/Setup.lua")
loadChunk("Installer/Installer.lua")

check(type(ns.CanSkipStep) == "function", "ns.CanSkipStep is defined")
check(type(ns.IsStepSkipped) == "function", "ns.IsStepSkipped is defined")
check(type(ns.SetStepSkipped) == "function", "ns.SetStepSkipped is defined")
check(type(ns.ClearStepSkip) == "function", "ns.ClearStepSkip is defined")

-- The event handler that normally builds this never runs headlessly.
ns.db = {}

---------------------------------------------------------------------------------
-- Which steps can be skipped at all
---------------------------------------------------------------------------------

eq(ns.CanSkipStep("BigWigs"), true, "an addon with a shipped version can be skipped")
-- The exception that carries a reason: CDM has no version header on purpose,
-- because one string cannot say which spec changed.
eq(ns.CanSkipStep("BlizzardCDM"), false, "Blizzard CDM cannot be skipped")
eq(ns.CanSkipStep("NotAnAddon"), false, "an unknown key cannot be skipped")

---------------------------------------------------------------------------------
-- The version token
---------------------------------------------------------------------------------

eq(ns.IsStepSkipped("BigWigs"), false, "a step nobody skipped is offered")

eq(ns.SetStepSkipped("BigWigs"), true, "skipping a versioned step succeeds")
eq(ns.IsStepSkipped("BigWigs"), true, "a skipped step is withheld")
eq(ns.db.skipped.BigWigs, "2026.08.22.1", "the skip records the shipped version, not a boolean")

-- Unrelated steps are untouched.
eq(ns.IsStepSkipped("EllesmereUI"), false, "skipping one step does not withhold another")

-- THE POINT OF THE WHOLE DESIGN. Ship a newer BigWigs profile and the step
-- comes back with no reset pass anywhere.
shipped["X-BigWigs-Version"] = "2026.09.01"
eq(ns.IsStepSkipped("BigWigs"), false, "a newer shipped version retires the skip")

-- Going back to the skipped version withholds it again: the test is equality,
-- not recency, so nothing has to reason about version ordering.
shipped["X-BigWigs-Version"] = "2026.08.22.1"
eq(ns.IsStepSkipped("BigWigs"), true, "the stored version still matches after a revert")

---------------------------------------------------------------------------------
-- An explicit action outranks an earlier skip
---------------------------------------------------------------------------------

ns.ClearStepSkip("BigWigs")
eq(ns.IsStepSkipped("BigWigs"), false, "clearing the skip offers the step again")
eq(ns.db.skipped.BigWigs, nil, "clearing removes the record rather than blanking it")

-- A step with no version has nothing to record against, so the call refuses
-- rather than writing a key that could never be compared.
eq(ns.SetStepSkipped("BlizzardCDM"), false, "skipping Blizzard CDM refuses")
eq(ns.db.skipped.BlizzardCDM, nil, "a refused skip records nothing")

---------------------------------------------------------------------------------
-- The update prompt honours the skip
---------------------------------------------------------------------------------

-- The login line, the update popup and /kitn update all read this one list, so
-- a skip that is missing here reaches the player through all three at once.
local function outdatedNames(key)
    for _, entry in ipairs(ns.GetOutdatedAddons()) do
        if entry.key == key then return true end
    end
    return false
end

ns.db = { profiles = { BigWigs = true }, addonVersions = { BigWigs = "2026.08.22.1" } }
ns.data.BigWigs = "payload"
shipped["X-BigWigs-Version"] = "2026.09.01"

-- Without this the next check could pass on a list that never named BigWigs.
eq(outdatedNames("BigWigs"), true, "an older import is reported outdated")

ns.SetStepSkipped("BigWigs")
eq(outdatedNames("BigWigs"), false, "a skipped update is not reported outdated")

shipped["X-BigWigs-Version"] = "2026.09.15"
eq(outdatedNames("BigWigs"), true, "a newer shipped version is reported again")

---------------------------------------------------------------------------------
-- Which modes list a skipped step
---------------------------------------------------------------------------------

local function listsStep(key, profileLoadMode, updateKeys)
    local data = ns:GetInstallerData(profileLoadMode, updateKeys)
    for _, k in ipairs(data.StepKeys) do
        if k == key then return true end
    end
    return false
end

-- A stale import, because that is what an update skip declines; a step already
-- at the shipped version has nothing to skip.
ns.db = { profiles = { BigWigs = true }, addonVersions = { BigWigs = "2026.08.22.1" } }
-- Asserted, because a refused skip would make every mode check below meaningless.
eq(ns.SetStepSkipped("BigWigs"), true, "a stale import can be skipped")

eq(listsStep("BigWigs", false, { BigWigs = true }), false, "update mode withholds a skipped step")
-- The escape hatch: only an import retires a skip, so hiding the step here too
-- would leave nothing that could.
eq(listsStep("BigWigs", false, nil), true, "a plain install still lists a skipped step")
-- Loading activates a profile the account already owns and never touches the
-- shipped version the skip is keyed to.
eq(listsStep("BigWigs", true, nil), true, "load mode lists a skipped step")

---------------------------------------------------------------------------------
-- Only an import retires a skip
---------------------------------------------------------------------------------

ns.data.KitnEssentials = "payload"
_G.KitnEssentialsAPI = {
    DecodeProfileString = function() return { setting = 1 } end,
    SetProfile = function() end,
}
_G.KitnEssentialsDB = { profiles = { [ns.profileName] = { setting = 1 } } }

ns.db = { profiles = { KitnEssentials = true }, addonVersions = {}, perChar = {} }
ns.SetStepSkipped("KitnEssentials")

-- Asserted first: a load that failed would leave the skip in place too, and the
-- check after it would then pass without proving anything.
check(ns.SetupAddon("KitnEssentials", false) ~= false, "the load itself succeeds")
eq(ns.IsStepSkipped("KitnEssentials"), true, "a successful load leaves the skip in place")

check(ns.SetupAddon("KitnEssentials", true) ~= false, "the import itself succeeds")
eq(ns.IsStepSkipped("KitnEssentials"), false, "a successful import retires the skip")

-- The import above stamped the shipped version, so there is now nothing to
-- decline. A skip recorded here would withhold nothing and still mark an
-- imported step as skipped.
eq(ns.CanSkipStep("KitnEssentials"), false, "a step imported at the shipped version cannot be skipped")
eq(ns.SetStepSkipped("KitnEssentials"), false, "skipping a current step refuses")
eq(ns.db.skipped.KitnEssentials, nil, "a refused skip of a current step records nothing")

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
