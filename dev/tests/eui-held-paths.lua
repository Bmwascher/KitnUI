-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-held-paths.lua                                          ║
-- ║  Purpose: Gate for the export paths KitnUI's EllesmereUI-tab ║
-- ║           switches hold, which the per-part count leaves     ║
-- ║           out. Loads the SHIPPED code, never a copy.         ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/eui-held-paths.lua

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
-- Stubs: KitnUI's namespace with the two files the describers read, and what
-- the tab's files touch at load
---------------------------------------------------------------------------------

local core = { title = "KitnUI", profileName = "KitnUI", data = {} }
for _, file in ipairs({ "Installer/Merge.lua", "Installer/ModuleRows.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", core)
end
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
local CDM = "EllesmereUICooldownManager"
_G.EllesmereUI = { Lite = { _dbRegistry = {
    { folder = CDM, profile = { cdmBars = { bars = { { key = "cooldowns" }, { key = "buffs" } } } } },
} } }

local PAGE_FILES = { "KitnUI_EUI/Lulu.lua", "KitnUI_EUI/Bite.lua", "KitnUI_EUI/General.lua",
    "KitnUI_EUI/Gameplay.lua", "KitnUI_EUI/Nameplates.lua" }
local ns = {}
for _, file in ipairs({ "KitnUI_EUI/Core.lua", unpack(PAGE_FILES) }) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI_EUI", ns)
end

check(type(ns.EUIHeldPaths) == "function", "ns.EUIHeldPaths is defined")
check(type(ns.EUIMoveProfileRecords) == "function", "ns.EUIMoveProfileRecords is defined")
if failures > 0 then
    print(string.format("%d checks, %d failures", checks, failures))
    os.exit(1)
end

---------------------------------------------------------------------------------
-- One note per row of the spec's table gives exactly its path
---------------------------------------------------------------------------------

local BACKUP = "KitnUI (before update)"
local RB = "EllesmereUIResourceBars"
local FK = core.EUI_HELD_FKEY

local function heldFor(section, profile, notes)
    core.db = { euiSnap = { [section] = { [profile] = notes } } }
    return ns.EUIHeldPaths({ "KitnUI", BACKUP })
end

local function sameSet(got, want, label)
    local wanted = {}
    for _, p in ipairs(want) do wanted[p] = true end
    for p in pairs(got) do check(wanted[p], label .. ": no path beyond the expected", p) end
    for p in pairs(wanted) do check(got[p], label .. ": holds " .. p) end
end

sameSet(heldFor("bite", "KitnUI", { showSpellText = { prev = true } }),
    { "addons." .. RB .. ".castBar.showSpellText" }, "bite spell text")
sameSet(heldFor("bite", "KitnUI", { ["spellText\31cond\31default"] = { prev = true } }),
    { FK .. RB .. "\31castBar\30showSpellText" }, "bite spell text in an override slot")
sameSet(heldFor("bite", "KitnUI", { ERB_CastBar = { prev = {} }, ERB_Power = { prev = {} } }),
    { "unlockLayout.anchors.ERB_CastBar", "unlockLayout.anchors.ERB_Power" }, "bite anchors")
sameSet(heldFor("bite", "KitnUI", { ["override:ERB_CastBar"] = { prev = "__kitnui_absent__" } }),
    { "unlockOverrideAnchors.ERB_CastBar" }, "bite override position")
sameSet(heldFor("bite", "KitnUI", { darkWasOn = { prev = true } }), {}, "bite's dark flag holds no path")
sameSet(heldFor("bite", "KitnUI", { ["buffOffset\031buffs\031262"] = { prev = 21 } }),
    { FK .. CDM .. "\031cdmBars\030bars\0302\030addOffsetY" }, "bite buff offset in an override slot")
sameSet(heldFor("bite", "KitnUI", { ["buffOffset\031gone\031262"] = { prev = 21 } }), {},
    "bite buff offset for a bar that is gone")
sameSet(heldFor("bite", "KitnUI", { ["buffOffset\031buffs"] = { prev = 21 } }), {},
    "bite buff offset without a slot names nothing")
sameSet(heldFor("bite", "KitnUI", { ["buffOffset\031buffs\031262"] = { prev = 21, shown = true } }), {},
    "bite buff offset put back for the open panel holds nothing")
sameSet(heldFor("darkcastbar", "KitnUI", { fillR = { prev = 1 }, ["bgA\03171"] = { prev = 0.5 } }),
    { "addons." .. RB .. ".castBar.fillR", FK .. RB .. "\31castBar\30bgA" }, "dark cast bar")
sameSet(heldFor("darkresourcegap", "KitnUI", { gapR = { prev = 1 }, ["gapColorEnabled\31default"] = { prev = false } }),
    { "addons." .. RB .. ".secondary.gapR", FK .. RB .. "\31secondary\30gapColorEnabled" }, "seam colour")
sameSet(heldFor("accent", "KitnUI", {
    color = { prev = "__kitnui_absent__" },
    scope = { keys = {
        ["EllesmereUIQuestTracker.headerUseAccent"] = { prev = false },
        ["EllesmereUIMythicTimer.titleUseAccent"] = { prev = true },
        ["EllesmereUIFriends.useAccentTab"] = {},
    } },
}), {
    "euiAccent",
    "addons.EllesmereUIQuestTracker.questTracker.headerUseAccent",
    "addons.EllesmereUIMythicTimer.titleUseAccent",
}, "accent colour and scope")
sameSet(heldFor("beginner", "KitnUI", {
    ["buffs\31showTooltip"] = { prev = false },
    ["#1\31showKeybind"] = { prev = false },
    ["MainBar\31hideKeybind"] = { prev = true },
    ["Bar2\31barVisibility"] = { prev = "mouseover" },
}), {
    "addons." .. CDM .. ".cdmBars.bars.[2].showTooltip",
    "addons." .. CDM .. ".cdmBars.bars.[1].showKeybind",
    "addons.EllesmereUIActionBars.bars.MainBar.hideKeybind",
    "addons.EllesmereUIActionBars.bars.Bar2.barVisibility",
    "addons.EllesmereUIActionBars.bars.Bar2.alwaysHidden",
    "addons.EllesmereUIActionBars.bars.Bar2.mouseoverEnabled",
    "addons.EllesmereUIActionBars.bars.Bar2.mouseoverAlpha",
    "addons.EllesmereUIActionBars.bars.Bar2._savedBarAlpha",
    "addons.EllesmereUIActionBars.bars.Bar2.combatHideEnabled",
    "addons.EllesmereUIActionBars.bars.Bar2.combatShowEnabled",
}, "beginner mode")
sameSet(heldFor("lulu", "KitnUI", { minimapShape = { prev = "square" }, clockOffsetY = { prev = 0 } }),
    { "addons.EllesmereUIMinimap.minimap.shape", "addons.EllesmereUIMinimap.minimap.clockOffsetY" }, "lulu minimap")
sameSet(heldFor("nameplates", "KitnUI", { euiArrows = { prev = true } }),
    { "addons.EllesmereUINameplates.showTargetArrows" }, "target arrows")

sameSet(heldFor("bite", "KitnUI", { showSpellText = {} }), {}, "a released note holds nothing")
sameSet(heldFor("nameplates", BACKUP, { euiArrows = { prev = true } }),
    { "addons.EllesmereUINameplates.showTargetArrows" }, "notes under the backup name are read")
sameSet(heldFor("nameplates", "Other", { euiArrows = { prev = true } }), {}, "another profile's notes are not")

---------------------------------------------------------------------------------
-- Every section the page files write has a describer
---------------------------------------------------------------------------------

local sections, found = {}, 0
for _, file in ipairs(PAGE_FILES) do
    local f = assert(io.open(file, "rb"))
    local src = f:read("*a")
    f:close()
    for name in src:gmatch('_SECTION%s*=%s*"([%w_]+)"') do sections[name] = true end
    for name in src:gmatch('EUISnap%(%s*"([%w_]+)"') do sections[name] = true end
    for name in src:gmatch('EUIPeekSnap%(%s*"([%w_]+)"') do sections[name] = true end
end
for name in pairs(sections) do
    found = found + 1
    check(ns.EUIHeldDescribers[name] ~= nil, "section " .. name .. " has a held-path describer")
end
check(found >= 7, "the source scan found the seven sections", found)

---------------------------------------------------------------------------------
-- The notes reader
---------------------------------------------------------------------------------

check(type(ns.EUIPeekNotes) == "function", "ns.EUIPeekNotes is defined")
if type(ns.EUIPeekNotes) == "function" then
    core.db = { euiSnap = { bite = { Default = { x = { prev = 1 } } } } }
    local notes = ns.EUIPeekNotes("bite")
    eq(notes and notes.x and notes.x.prev, 1, "peek notes: the active profile's notes")
    eq(ns.EUIPeekNotes("lulu"), nil, "peek notes: a section with no notes reads nil")
    eq(core.db.euiSnap.lulu, nil, "peek notes: nothing is seeded")
end

---------------------------------------------------------------------------------
-- The note move and the bridge
---------------------------------------------------------------------------------

core.db = { euiSnap = { bite = { ["KitnUI (updating)"] = { x = { prev = 1 } } } } }
ns.EUIMoveProfileRecords("KitnUI (updating)", "KitnUI")
eq(core.db.euiSnap.bite.KitnUI and core.db.euiSnap.bite.KitnUI.x.prev, 1, "move: the notes follow the name")
eq(core.db.euiSnap.bite["KitnUI (updating)"], nil, "move: the old name keeps nothing")

local coreFile = assert(io.open("KitnUI_EUI/Core.lua", "rb"))
local coreSource = coreFile:read("*a")
coreFile:close()
local exports = coreSource:match("local EXPORTS = (%b{})") or ""
check(exports:find('"EUIHeldPaths"', 1, true), "EXPORTS names EUIHeldPaths")
check(exports:find('"EUIMoveProfileRecords"', 1, true), "EXPORTS names EUIMoveProfileRecords")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
