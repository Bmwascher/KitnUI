-- ╔══════════════════════════════════════════════════════════════╗
-- ║  step-skip.lua                                               ║
-- ║  Purpose: Gate for the per-step skip's version token.        ║
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
-- Stubs: the WoW surface Core.lua touches at load, and nothing more
---------------------------------------------------------------------------------

-- The versions KitnUI currently ships, keyed by TOC header. Mutable, because
-- moving one of these is exactly what a shipped update looks like.
local shipped = {
    ["X-BigWigs-Version"]     = "2026.08.22.1",
    ["X-EllesmereUI-Version"] = "2026.08.22",
}

_G.format = string.format
_G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.CopyTable = function(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and _G.CopyTable(v) or v end
    return c
end
_G.C_AddOns = { GetAddOnMetadata = function(_, header) return shipped[header] end }
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

local ns = { data = {} }

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

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
