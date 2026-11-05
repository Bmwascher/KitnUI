-- ╔══════════════════════════════════════════════════════════════╗
-- ║  np-level-name.lua                                           ║
-- ║  Purpose: Gate for the Nameplates page's Show Level Before   ║
-- ║           Name switch: what it writes, what it gives back.   ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/np-level-name.lua

local realPrint = print
local failures = 0
local checks = 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        realPrint("FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
    end
end

local function eq(actual, expected, label)
    check(actual == expected, label, "got " .. tostring(actual) .. ", wanted " .. tostring(expected))
end

---------------------------------------------------------------------------------
-- Stubs
---------------------------------------------------------------------------------

local core = { title = "KitnUI", data = {} }
_G.KitnUI_Shared = core

_G.InCombatLockdown = function() return false end
_G.UnitGUID = function() return "Player-1-1" end
_G.hooksecurefunc = function() end
_G.CreateFrame = function()
    local f = {}
    function f.RegisterEvent() end
    function f.RegisterUnitEvent() end
    function f.UnregisterEvent() end
    function f.SetScript() end
    return f
end

local prof = {}
local refreshes = 0
local printed = {}
_G.print = function(msg) printed[#printed + 1] = msg end
_G._ENP_RefreshAllSettings = function() refreshes = refreshes + 1 end
_G.EllesmereUI = {
    GetActiveProfileName = function() return "KitnUI" end,
    Lite = { _dbRegistry = { { folder = "EllesmereUINameplates", profile = prof } } },
}
_G.C_Timer = { After = function(_, fn) fn() end }

local function load(isForever)
    core.IS_FOREVER = isForever
    local into = {}
    for _, file in ipairs({ "KitnUI_EUI/Core.lua", "KitnUI_EUI/Nameplates.lua" }) do
        local chunk, err = loadfile(file)
        if not chunk then
            realPrint("FAIL  could not load " .. file .. ": " .. tostring(err))
            os.exit(1)
        end
        chunk("KitnUI_EUI", into)
    end
    return into
end

eq(load(true).EUI_DEFAULTS.npLevelName, true, "Forever: the switch is on by default")
local ns = load(false)
eq(ns.EUI_DEFAULTS.npLevelName, false, "retail: the switch is off by default")

-- The page builder hands back the toggle's setter by its label.
local toggles = {}
local W = {}
function W:SectionHeader() return nil, 10 end
function W:DualRow() return nil, 10 end
function W:Toggle(_, label, _, _, set) toggles[label] = set; return nil, 10 end
_G.EllesmereUI.Widgets = W
ns.EUIPages["Nameplates"]({}, 0)

local set = toggles["Show Level Before Name"]
check(type(set) == "function", "the page builds the Show Level Before Name toggle")
if not set then
    realPrint(string.format("%d checks, %d failures", checks, failures))
    os.exit(1)
end

local function reset(slots)
    for k in pairs(prof) do prof[k] = nil end
    for k, v in pairs(slots) do prof[k] = v end
    core.db = {}
    printed = {}
    ns.EUISettings().npLevelName = false
    ns.EUISettings().npLevelNameSeeded = nil
end

---------------------------------------------------------------------------------
-- On writes the name slot, off gives every key back
---------------------------------------------------------------------------------

reset({ textSlotLeft = "enemyName", textSlotTop = "none", textSlotLeftLevelColorOn = true })
local before = refreshes
set(true)
eq(prof.textSlotLeft, "levelName", "on: the name slot shows Level | Name")
eq(prof.textSlotLeftLevelDiffOn, true, "on: the level takes the difficulty color")
eq(prof.textSlotLeftLevelColorOn, false, "on: a custom level color is switched off")
eq(prof.textSlotTop, "none", "on: other slots are left alone")
check(refreshes > before, "on: the plates are refreshed")
eq(ns.NameplateLevelNameEnabled(), true, "on: the switch reads on")

set(true)
set(false)
eq(prof.textSlotLeft, "enemyName", "off: the name slot is given back")
eq(prof.textSlotLeftLevelDiffOn, nil, "off: an unset difficulty key is unset again")
eq(prof.textSlotLeftLevelColorOn, true, "off: the custom level color is given back")
eq(ns.NameplateLevelNameEnabled(), false, "off: the switch reads off")

---------------------------------------------------------------------------------
-- The name may sit in any slot
---------------------------------------------------------------------------------

reset({ textSlotTop = "enemyName", textSlotLeft = "none" })
set(true)
eq(prof.textSlotTop, "levelName", "top slot: the slot holding the name is the one changed")
eq(prof.textSlotLeft, "none", "top slot: the empty left slot stays empty")
set(false)
eq(prof.textSlotTop, "enemyName", "top slot: given back")

---------------------------------------------------------------------------------
-- No slot shows the name: refused, nothing written, switch left off
---------------------------------------------------------------------------------

reset({ textSlotTop = "none", textSlotLeft = "level" })
set(true)
eq(ns.NameplateLevelNameEnabled(), false, "no name: the switch stays off")
eq(prof.textSlotLeft, "level", "no name: nothing is written")
check(#printed == 1, "no name: the refusal is printed once", #printed)

---------------------------------------------------------------------------------
-- On by default: the first re-apply claims once, a stamped profile never
---------------------------------------------------------------------------------

reset({ textSlotLeft = "enemyName" })
ns.EUISettings().npLevelName = true
ns.EUIQueueReapply()
eq(prof.textSlotLeft, "levelName", "default on: the first re-apply writes Level | Name")
eq(ns.EUISettings().npLevelNameSeeded, true, "default on: the profile is stamped")
set(false)
eq(prof.textSlotLeft, "enemyName", "default on: switching off gives the name slot back")

reset({ textSlotLeft = "enemyName" })
ns.EUISettings().npLevelName = false
before = refreshes
ns.EUIQueueReapply()
eq(prof.textSlotLeft, "enemyName", "default off: the first re-apply writes nothing")
eq(ns.EUISettings().npLevelNameSeeded, nil, "default off: the profile is not stamped")
eq(refreshes, before, "default off: the plates are not refreshed")

reset({ textSlotLeft = "levelName", textSlotLeftLevelDiffOn = true })
ns.EUISettings().npLevelName = true
ns.EUISettings().npLevelNameSeeded = true
ns.EUIQueueReapply()
eq(ns.EUIPeekSnap("nameplates", "levelName\31textSlotLeft"), nil,
    "copied profile: a stamped profile with no note records nothing")

reset({ textSlotLeft = "levelName", textSlotLeftLevelDiffOn = true })
ns.EUISettings().npLevelName = true
ns.EUIQueueReapply()
eq(ns.EUIPeekSnap("nameplates", "levelName\31textSlotLeft"), nil,
    "already Level | Name: the unclicked claim records nothing")

---------------------------------------------------------------------------------
-- The name moved in EllesmereUI: the notes are dropped, nothing is written
---------------------------------------------------------------------------------

reset({ textSlotLeft = "enemyName", textSlotTop = "none" })
set(true)
prof.textSlotLeft, prof.textSlotTop = "none", "enemyName"
ns.EUIQueueReapply()
eq(prof.textSlotLeft, "none", "moved name: the old slot is not written again")
eq(prof.textSlotTop, "enemyName", "moved name: the new name slot is left as the user set it")
local rec = ns.EUIPeekSnap("nameplates", "levelName\31textSlotLeft")
check(not (rec and rec.prev ~= nil), "moved name: the note is dropped")
set(false)
eq(prof.textSlotLeft, "none", "moved name: off writes nothing into the old slot")

---------------------------------------------------------------------------------
-- EllesmereUI's own lookup, which knows an unset slot's default
---------------------------------------------------------------------------------

reset({})
_G.EllesmereNameplates_NS = { FindNameSlot = function(db)
    if (db.textSlotTop or "enemyName") ~= "none" then return "textSlotTop" end
    return nil
end }
set(true)
eq(prof.textSlotTop, "levelName", "lookup: an unset Top slot, the name by default, is the one written")
set(false)
eq(prof.textSlotTop, nil, "lookup: off unsets it again")
_G.EllesmereNameplates_NS = nil

---------------------------------------------------------------------------------
-- The reset gives the keys back and stops its own re-apply from claiming
---------------------------------------------------------------------------------

reset({ textSlotLeft = "enemyName" })
set(true)
ns.NameplateLevelNameTeardown()
eq(prof.textSlotLeft, "enemyName", "reset: the name slot is given back")
ns.EUISettings().npLevelName = true
ns.EUISettings().npLevelNameSeeded = nil
ns.EUIQueueReapply()
eq(prof.textSlotLeft, "enemyName", "reset: the reset's re-apply writes nothing")
eq(ns.EUISettings().npLevelNameSeeded, nil, "reset: the reset's re-apply stamps nothing")

---------------------------------------------------------------------------------
-- The reset with the nameplate module switched off: both switches reach its
-- stored profile and give their keys back
---------------------------------------------------------------------------------

local stored = { textSlotLeft = "levelName", textSlotLeftLevelDiffOn = true,
    textSlotLeftLevelColorOn = false, showTargetArrows = false }
_G.EllesmereUI.Lite._dbRegistry = {}
_G.EllesmereUIDB = { profiles = { KitnUI = { addons = { EllesmereUINameplates = stored } } } }
local off = load(false)
core.db = { euiSnap = { nameplates = { KitnUI = {
    ["levelName\31textSlotLeft"] = { prev = "enemyName" },
    ["levelName\31textSlotLeftLevelDiffOn"] = { prev = "__kitnui_absent__" },
    ["levelName\31textSlotLeftLevelColorOn"] = { prev = "__kitnui_absent__" },
    euiArrows = { prev = true },
} } } }
off.EUIQueueReapply()
eq(stored.showTargetArrows, false, "module off: an ordinary re-apply keeps the arrows held")
eq(stored.textSlotLeft, "levelName", "module off: an ordinary re-apply keeps the name slot held")
off.NameplateLevelNameTeardown()
off.NameplateArrowsTeardown()
eq(stored.textSlotLeft, "enemyName", "module off: the reset gives the name slot back")
eq(stored.textSlotLeftLevelDiffOn, nil, "module off: the difficulty key is unset again")
eq(stored.showTargetArrows, true, "module off: the reset gives EllesmereUI's own arrows back")

realPrint(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
