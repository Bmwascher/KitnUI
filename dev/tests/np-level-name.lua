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

local ns = {}
for _, file in ipairs({ "KitnUI_EUI/Core.lua", "KitnUI_EUI/Nameplates.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        realPrint("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI_EUI", ns)
end

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

realPrint(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
