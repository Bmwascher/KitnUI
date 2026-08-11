-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cdm-fingerprint.lua                                         ║
-- ║  Purpose: Gate for the Blizzard CDM fingerprint scheme.       ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe dev/tests/cdm-fingerprint.lua
-- Exits non-zero on the first failure and prints what broke.
--
-- IT LOADS Installer/Core.lua AND Data/Classes/BlizzardCDM.lua AS CHUNKS. A
-- pasted copy of a function under test could pass every assertion here while
-- the shipped one drifted, which is the one thing a gate must not permit. Both
-- files take their namespace from chunk varargs, so a stub `ns` is all it takes.
--
-- KitnUI has no busted suite. This is a plain script, tracked in git and
-- stripped from the package by .pkgmeta's `dev` ignore.

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

local stubClassId = 1
local stubNumSpecs = 3

_G.format = string.format
_G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.CopyTable = function(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and _G.CopyTable(v) or v end
    return c
end
_G.C_AddOns = { GetAddOnMetadata = function() return "2026.08.11" end }
_G.C_Timer = { After = function() end }
_G.CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
end
_G.SlashCmdList = {}
_G.UnitClass = function() return "Warrior", "WARRIOR", stubClassId end
_G.C_SpecializationInfo = {
    GetNumSpecializationsForClassID = function() return stubNumSpecs end,
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
-- Load the shipped chunks
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

check(type(ns.GetCDMKey) == "function", "ns.GetCDMKey is defined")
check(type(ns.GetCDMShippedFingerprint) == "function", "ns.GetCDMShippedFingerprint is defined")
check(type(ns.GetCDMSpecState) == "function", "ns.GetCDMSpecState is defined")
check(type(ns.GetCDMSpecRows) == "function", "ns.GetCDMSpecRows is defined")
check(type(ns.SummarizeCDMRows) == "function", "ns.SummarizeCDMRows is defined")
check(type(ns.CDMNeedsOverwriteConfirm) == "function", "ns.CDMNeedsOverwriteConfirm is defined")
if failures > 0 then
    print(failures .. " of " .. checks .. " checks failed")
    os.exit(1)
end

---------------------------------------------------------------------------------
-- ns.GetCDMKey: both halves validated, output canonical
---------------------------------------------------------------------------------

eq(ns.GetCDMKey(1, 1), "1:1", "GetCDMKey canonical form")
eq(ns.GetCDMKey(13, 4), "13:4", "GetCDMKey two-digit class")
eq(ns.GetCDMKey(nil, 1), nil, "GetCDMKey rejects nil class")
eq(ns.GetCDMKey(1, nil), nil, "GetCDMKey rejects nil spec")
eq(ns.GetCDMKey("1", 1), nil, "GetCDMKey rejects string class")
eq(ns.GetCDMKey(1, "1"), nil, "GetCDMKey rejects string spec")
eq(ns.GetCDMKey(0, 1), nil, "GetCDMKey rejects zero class")
eq(ns.GetCDMKey(1, -1), nil, "GetCDMKey rejects negative spec")
eq(ns.GetCDMKey(1.5, 1), nil, "GetCDMKey rejects fractional class")
eq(ns.GetCDMKey(1, 1.5), nil, "GetCDMKey rejects fractional spec")

---------------------------------------------------------------------------------
-- The fingerprint, reached through the shipped accessor
---------------------------------------------------------------------------------

-- Golden vectors. Fixed by hand from the shipped algorithm; if the algorithm
-- changes these must be recomputed DELIBERATELY, which is the point of a golden
-- vector. Reached by planting a payload rather than calling a local directly.
-- The accessor memoizes per key, so every probe takes a fresh spec index.
local probeCounter = 0
local probeSlots = {}
local function fingerprintOf(str)
    probeCounter = probeCounter + 1
    probeSlots[probeCounter] = str
    ns.data.BlizzardCDM[99] = probeSlots
    return ns.GetCDMShippedFingerprint(99, probeCounter)
end

local fpA = fingerprintOf("a")
local fpB = fingerprintOf("b")
local fpAA = fingerprintOf("aa")

-- The vectors themselves. Hand-computed from the seed 5381, the multiplier 33
-- and the split emission; change any of the three and these fail, which is the
-- whole point. The long one is 24 bytes, so its running hash wraps the 2^32
-- modulus many times over, and its expected value was computed by an
-- INDEPENDENT implementation (.NET System.Numerics.BigInteger), never by the
-- code under test -- a value read off the implementation proves nothing.
eq(fpA, "2-46598-1", "golden vector: a")
eq(fpB, "2-46599-1", "golden vector: b")
eq(fpAA, "89-30503-2", "golden vector: aa")
eq(fingerprintOf("KitnUI CDM golden vector"), "16461-8921-24",
    "golden vector: a 24-byte string, which wraps the modulus")

check(fpA ~= nil, "fingerprint of a single byte is not nil")
check(fpA ~= fpB, "different one-byte strings differ", fpA .. " vs " .. fpB)
check(fpA ~= fpAA, "different lengths differ", fpA .. " vs " .. fpAA)
eq(fpA, fingerprintOf("a"), "the same string fingerprints the same twice")
eq(select(2, string.gsub(fpA, "%-", "")), 2, "fingerprint has exactly three fields")
check(fpA:match("^%d+%-%d+%-%d+$") ~= nil, "fingerprint is three decimal fields", fpA)

eq(ns.GetCDMShippedFingerprint(99, 900), nil, "no payload gives no fingerprint")
ns.data.BlizzardCDM[98] = { [1] = "" }
eq(ns.GetCDMShippedFingerprint(98, 1), nil, "an empty payload gives no fingerprint")
ns.data.BlizzardCDM[97] = { [1] = 12345 }
eq(ns.GetCDMShippedFingerprint(97, 1), nil, "a non-string payload gives no fingerprint")
eq(ns.GetCDMShippedFingerprint(nil, 1), nil, "a nil class gives no fingerprint")

-- Every payload the addon actually ships must fingerprint, and no two may
-- collide. This is the gate that matters when the data file is refreshed.
local seen, payloads = {}, 0
for classId, specs in pairs(ns.data.BlizzardCDM) do
    if classId < 90 then -- skip the probe classes planted above
        for specIndex, str in pairs(specs) do
            if type(str) == "string" and _G.strtrim(str) ~= "" then
                payloads = payloads + 1
                local fp = ns.GetCDMShippedFingerprint(classId, specIndex)
                check(fp ~= nil, "shipped payload fingerprints", classId .. ":" .. specIndex)
                if fp then
                    check(seen[fp] == nil, "no shipped payload collides",
                        classId .. ":" .. specIndex .. " collides with " .. tostring(seen[fp]))
                    seen[fp] = classId .. ":" .. specIndex
                end
            end
        end
    end
end
check(payloads > 0, "the data file actually holds payloads")

---------------------------------------------------------------------------------
-- ns.GetCDMSpecState: five states from the five database shapes
---------------------------------------------------------------------------------

ns.data.BlizzardCDM[stubClassId] = ns.data.BlizzardCDM[stubClassId] or {}
local shipped1 = ns.GetCDMShippedFingerprint(stubClassId, 1)
check(shipped1 ~= nil, "the stub class ships spec 1")

local function withStore(store)
    ns.db = { profiles = { BlizzardCDM = store } }
end

withStore({})
eq(ns.GetCDMSpecState(stubClassId, 1), "missing", "empty store gives missing")

withStore({ [1] = true })
eq(ns.GetCDMSpecState(stubClassId, 1), "untracked", "a legacy integer key gives untracked")

withStore({ ["1:1"] = shipped1 })
eq(ns.GetCDMSpecState(stubClassId, 1), "current", "a matching fingerprint gives current")

withStore({ ["1:1"] = "0-0-1" })
eq(ns.GetCDMSpecState(stubClassId, 1), "stale", "a differing fingerprint gives stale")

withStore({ ["1:1"] = shipped1, [1] = true })
eq(ns.GetCDMSpecState(stubClassId, 1), "current",
    "a tracked entry wins over a surviving legacy key")

withStore({})
eq(ns.GetCDMSpecState(stubClassId, 900), "nodata", "an unshipped spec gives nodata")

---------------------------------------------------------------------------------
-- ns.GetCDMSpecRows: guarded degradation, never a raise
---------------------------------------------------------------------------------

withStore({})
local rowsClassId, rows = ns.GetCDMSpecRows()
eq(rowsClassId, stubClassId, "rows carry the class id")
eq(#rows, stubNumSpecs, "one row per spec")
eq(rows[1].specName, "Spec1", "rows carry the spec name")

local savedUnitClass = _G.UnitClass
_G.UnitClass = function() return "Warrior", "WARRIOR", nil end
local nilClassId, nilRows = ns.GetCDMSpecRows()
eq(nilClassId, nil, "a nil class id gives a nil class id")
eq(#nilRows, 0, "a nil class id gives no rows")
_G.UnitClass = savedUnitClass

local savedSpecInfo = _G.C_SpecializationInfo
_G.C_SpecializationInfo = nil
local _, noApiRows = ns.GetCDMSpecRows()
eq(#noApiRows, 0, "a missing C_SpecializationInfo gives no rows")
_G.C_SpecializationInfo = savedSpecInfo

local savedCount = _G.C_SpecializationInfo.GetNumSpecializationsForClassID
_G.C_SpecializationInfo.GetNumSpecializationsForClassID = function() return nil end
local _, noCountRows = ns.GetCDMSpecRows()
eq(#noCountRows, 0, "a non-numeric spec count gives no rows")
_G.C_SpecializationInfo.GetNumSpecializationsForClassID = savedCount

local savedSpecName = _G.GetSpecializationInfoForClassID
_G.GetSpecializationInfoForClassID = function() return nil, nil end
local _, fallbackRows = ns.GetCDMSpecRows()
eq(fallbackRows[2] and fallbackRows[2].specName, "Spec 2",
    "an unresolvable spec name falls back rather than dropping the row")
_G.GetSpecializationInfoForClassID = savedSpecName

---------------------------------------------------------------------------------
-- ns.SummarizeCDMRows: missing is never called an update
---------------------------------------------------------------------------------

eq(ns.SummarizeCDMRows({}), "no layouts available for this class", "empty rows say so")
eq(ns.SummarizeCDMRows({ { state = "missing" }, { state = "missing" } }),
    "2 not imported", "missing specs are not called updates")
eq(ns.SummarizeCDMRows({ { state = "current" }, { state = "stale" } }),
    "1 up to date, 1 update available", "stale alone is an update")
eq(ns.SummarizeCDMRows({ { state = "untracked" } }), "1 untracked", "untracked is named")
eq(ns.SummarizeCDMRows({ { state = "nodata" } }),
    "no layouts available for this class", "nodata specs are not counted")

---------------------------------------------------------------------------------
-- ns.CDMNeedsOverwriteConfirm: the frozen-snapshot policy
---------------------------------------------------------------------------------

eq(ns.CDMNeedsOverwriteConfirm(nil, 1, 1), false, "no snapshot means no warning")
eq(ns.CDMNeedsOverwriteConfirm({}, 1, 1), false, "a clean database means no warning")
eq(ns.CDMNeedsOverwriteConfirm({ ["1:1"] = "x" }, 1, 1), true, "a pre-session spec warns")
eq(ns.CDMNeedsOverwriteConfirm({ ["1:2"] = "x" }, 1, 1), false,
    "another spec of the same class does not warn")
eq(ns.CDMNeedsOverwriteConfirm({ ["2:1"] = "x" }, 1, 1), false,
    "the same spec index of another class does not warn")
eq(ns.CDMNeedsOverwriteConfirm({ [1] = true }, 1, 1), true, "legacy evidence warns")
eq(ns.CDMNeedsOverwriteConfirm({ [1] = true }, 7, 3), true,
    "legacy evidence over-warns across classes, deliberately")
eq(ns.CDMNeedsOverwriteConfirm({ ["1:2"] = "x" }, 1, nil), true,
    "Import All warns when any spec of the class was there")
eq(ns.CDMNeedsOverwriteConfirm({ ["2:1"] = "x" }, 1, nil), false,
    "Import All does not warn for another class")
eq(ns.CDMNeedsOverwriteConfirm({ ["1:1"] = "x" }, nil, nil), false,
    "Import All with no class id does not warn")

-- The case the by-value snapshot exists for: a spec imported DURING the session
-- is absent from the frozen copy, so revisiting the page must not re-prompt.
local liveStore = {}
local frozen = {}
for k, v in pairs(liveStore) do frozen[k] = v end   -- what SnapshotProfiles does
liveStore["1:1"] = "written-this-session"           -- what the import does
eq(next(frozen), nil, "the frozen copy did not follow the live table")
eq(ns.CDMNeedsOverwriteConfirm(frozen, 1, 1), false,
    "a spec imported this session does not re-prompt")

---------------------------------------------------------------------------------

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed (" .. payloads .. " shipped payloads fingerprinted)")
