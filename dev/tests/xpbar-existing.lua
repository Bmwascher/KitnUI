-- ╔══════════════════════════════════════════════════════════════╗
-- ║  xpbar-existing.lua                                          ║
-- ║  Purpose: Gate for Hide Existing: the claim, the note, the   ║
-- ║           Never write, the restore, what blocks a write and  ║
-- ║           Blizzard's tracking bar.                           ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/xpbar-existing.lua

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

local DEFAULTS = { xpEnabled = false, fbEnabled = false, xpHideExisting = true, fbHideExisting = true }
local settings, snaps, writes, storedModes = {}, {}, {}, {}
local profile, eab, stored
local editing, captured, inCombat = false, false, false
local rebuilds = 0
local describer
-- snaps is the active profile's notes, as Core keys them.
local activeProfile, snapsAll = "Kitn", { Kitn = snaps }
local generation = 0

local ns = { XPBar = {} }
ns.EUIActiveProfileName = function() return activeProfile end
ns.EUIProfileGeneration = function() return generation end
ns.XPBar.Get = function(key)
    local v = settings[key]
    if v == nil then v = DEFAULTS[key] end
    return v
end
ns.XPBar.Set = function(key, v) settings[key] = v end
ns.EUISnap = function(section, key)
    if section ~= "xpbar" then return nil end
    snaps[key] = snaps[key] or {}
    return snaps[key]
end
ns.EUIPeekSnap = function(section, key)
    if section ~= "xpbar" then return nil end
    return snaps[key]
end
ns.EUIRegisterHeld = function(section, fn) if section == "xpbar" then describer = fn end end
ns.EUIEditSessionActive = function() return editing end
ns.EUIRebuildForOwnership = function() rebuilds = rebuilds + 1 end
ns.EUIProfile = function() return profile end
ns.EUIAddon = function() return eab end
ns.EUIStoredProfile = function() return stored end
ns.EUIApplyVisModeStored = function(s, mode)
    storedModes[#storedModes + 1] = mode
    s.barVisibility = mode
    s.alwaysHidden = mode == "never"
end

_G.EllesmereUI = {
    GetVisibilitySelection = function(store)
        local sel = {}
        if type(store.visibilityModes) == "table" then
            for k in pairs(store.visibilityModes) do sel[k] = true end
        else
            sel[store.barVisibility or "always"] = true
        end
        return sel, false
    end,
    SetVisibilitySelection = function(store, _, sel, apply)
        local keys = {}
        for k in pairs(sel) do keys[#keys + 1] = k end
        table.sort(keys)
        local scalar = sel.never and "never" or (#keys == 1 and keys[1]) or "in_combat"
        writes[#writes + 1] = { sel = sel, apply = apply }
        apply(store, scalar)
        if #keys > 1 and not sel.never then
            store.visibilityModes = {}
            for _, k in ipairs(keys) do store.visibilityModes[k] = true end
        else
            store.visibilityModes = nil
        end
    end,
    VisOverrideValue = function(store) return store.visibilityOverride end,
    SpecOverrides_IsCaptured = function() return captured end,
}
_G.InCombatLockdown = function() return inCombat end
local frames = {}
_G.CreateFrame = function()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(_, fn) self.handler = fn end
    function f:Hide() self.hidden = true end
    frames[#frames + 1] = f
    return f
end
_G.UIParent = { name = "UIParent" }
local manager = { parent = _G.UIParent }
function manager:GetParent() return self.parent end
function manager:SetParent(p) self.parent = p end
_G.StatusTrackingBarManager = manager

local chunk, err = loadfile("KitnUI_EUI/XPBar/Existing.lua")
if not chunk then
    print("FAIL  could not load KitnUI_EUI/XPBar/Existing.lua: " .. tostring(err))
    os.exit(1)
end
chunk("KitnUI_EUI", ns)
local X = ns.XPBar
if type(X.SyncExisting) ~= "function" then
    print("FAIL  Existing.lua did not publish ns.XPBar.SyncExisting")
    os.exit(1)
end

local function euiBars(xp, rep)
    eab = { refreshed = {} }
    eab.VisibilityCompat = {
        ApplyMode = function(store, mode)
            store.barVisibility = mode
            store.alwaysHidden = mode == "never"
        end,
    }
    function eab:RefreshRuntimeVisibility() self.refreshed[#self.refreshed + 1] = "runtime" end
    function eab:RefreshMouseover() self.refreshed[#self.refreshed + 1] = "mouseover" end
    function eab:ApplyCombatVisibility() self.refreshed[#self.refreshed + 1] = "combat" end
    profile = { useBlizzardDataBars = false, bars = {
        XPBar = xp or { barVisibility = "always" },
        RepBar = rep or { barVisibility = "always" },
    } }
end

local function reset()
    settings, snaps, writes, storedModes = {}, {}, {}, {}
    activeProfile, snapsAll = "Kitn", { Kitn = snaps }
    editing, captured, inCombat, stored = false, false, false, nil
end

local function switchProfile(name)
    activeProfile = name
    snapsAll[name] = snapsAll[name] or {}
    snaps = snapsAll[name]
end

local function regen()
    for _, f in ipairs(frames) do
        if f.events.PLAYER_REGEN_ENABLED and f.handler then f.handler(f, "PLAYER_REGEN_ENABLED") end
    end
end

local function waitingForCombat()
    for _, f in ipairs(frames) do
        if f.events.PLAYER_REGEN_ENABLED then return true end
    end
    return false
end

local function xpBar() return profile.bars.XPBar end

---------------------------------------------------------------------------------
-- A click on a bar that is off
---------------------------------------------------------------------------------

reset(); euiBars(); inCombat = true
X.SyncExisting("xp")
eq(#frames, 0, "off-state click in combat: no frame is made")
check(not waitingForCombat(), "off-state click in combat: nothing waits for combat to end")
inCombat = false
settings.xpEnabled = true
X.SyncExisting()
eq(#writes, 0, "off-state click: it is no claim once the bar is turned on later")

---------------------------------------------------------------------------------
-- EllesmereUI's bars
---------------------------------------------------------------------------------

reset(); euiBars({ barVisibility = "mouseover" })
settings.xpEnabled = true
X.SyncExisting()
eq(#writes, 0, "unclaimed: nothing is written")
eq(snaps.xp, nil, "unclaimed: nothing is recorded")
eq(xpBar().barVisibility, "mouseover", "unclaimed: EllesmereUI's bar keeps its choice")

X.SyncExisting("xp")
check(snaps.xp and snaps.xp.prev and snaps.xp.prev.mouseover == true, "claim: the previous choice is recorded")
eq(#writes, 1, "claim: one write")
check(writes[1] and writes[1].sel.never == true, "claim: the write is Never")
eq(writes[1] and writes[1].apply, eab.VisibilityCompat.ApplyMode, "claim: through the module's ApplyMode")
eq(table.concat(eab.refreshed, ","), "runtime,mouseover,combat", "claim: then the three refreshes")
eq(xpBar().barVisibility, "never", "claim: EllesmereUI's bar reads Never")
eq(snaps.rep, nil, "claim: the reputation bar is not touched")
check(rebuilds > 0, "claim: the page is rebuilt for its ownership sentence")
eq(X.HoldsExisting("xp"), true, "claim: the XP switch's tooltip reads its own note as held")
eq(X.HoldsExisting("rep"), false, "claim: the reputation switch's does not")

writes = {}
X.SyncExisting("xp")
eq(#writes, 0, "held: a second claim writes nothing")

settings.xpEnabled = false
X.SyncExisting("xp")
eq(#writes, 1, "release: one write")
check(writes[1] and writes[1].sel.mouseover == true, "release: the previous choice goes back")
eq(xpBar().barVisibility, "mouseover", "release: EllesmereUI's bar reads it")
eq(snaps.xp.prev, nil, "release: the note is cleared")

reset(); euiBars({ barVisibility = "in_combat", visibilityModes = { in_combat = true, in_raid = true } })
settings.xpEnabled = true
X.SyncExisting("xp")
check(snaps.xp and snaps.xp.prev and snaps.xp.prev.in_combat and snaps.xp.prev.in_raid, "multi: the set is recorded")
eq(xpBar().visibilityModes, nil, "multi: Never clears the set")
settings.xpEnabled = false
X.SyncExisting("xp")
check(xpBar().visibilityModes and xpBar().visibilityModes.in_combat and xpBar().visibilityModes.in_raid,
    "multi: the set comes back")

reset(); euiBars({ barVisibility = "never", alwaysHidden = true })
settings.xpEnabled = true
X.SyncExisting("xp")
eq(#writes, 0, "already never: nothing is written")
eq(snaps.xp, nil, "already never: nothing is recorded")

reset(); euiBars({ barVisibility = "always", visibilityOverride = "always" })
settings.xpEnabled = true
X.SyncExisting("xp")
eq(#writes, 0, "override value: nothing is written")
eq(snaps.xp, nil, "override value: nothing is recorded")

reset(); euiBars(); captured = true
settings.xpEnabled = true
X.SyncExisting("xp")
eq(#writes, 0, "captured: nothing is written")
eq(snaps.xp, nil, "captured: nothing is recorded")

reset(); euiBars(); editing = true
settings.xpEnabled = true
X.SyncExisting("xp")
eq(#writes, 0, "editing session: nothing is written")
editing = false
X.SyncExisting()
eq(#writes, 1, "editing session: the claim lands once the session ends")

reset(); euiBars(); editing = true
settings.xpEnabled = true
X.SyncExisting("xp")
switchProfile("Other"); euiBars()
editing = false
X.SyncExisting()
eq(#writes, 0, "profile switch: a waiting claim does not land in another profile")
eq(snaps.xp, nil, "profile switch: and records nothing there")
eq(xpBar().barVisibility, "always", "profile switch: that profile's bar keeps its choice")
switchProfile("Kitn")
X.SyncExisting()
eq(#writes, 0, "profile switch: the dropped claim does not come back with its profile")

reset(); euiBars(); inCombat = true
settings.xpEnabled = true
X.SyncExisting("xp")
switchProfile("Other"); euiBars()
inCombat = false
regen()
eq(#writes, 0, "profile switch in combat: the claim does not land after combat either")

-- Every way the active profile's contents can be replaced while a claim
-- waits: the name changes (switch, rename, delete; above), an import refills
-- it under its own name (the generation moves), or a path no hook sees
-- changes the bar (the Visibility differs from the click's).
reset(); euiBars(); editing = true
settings.xpEnabled = true
X.SyncExisting("xp")
generation = generation + 1
euiBars({ barVisibility = "mouseover" })
editing = false
X.SyncExisting()
eq(#writes, 0, "import under the same name: a waiting claim does not land")
eq(snaps.xp, nil, "import under the same name: and records nothing")

reset(); euiBars(); editing = true
settings.xpEnabled = true
X.SyncExisting("xp")
generation = generation + 1
euiBars()
editing = false
X.SyncExisting()
eq(#writes, 0, "import of the same Visibility: the claim still does not land")

reset(); euiBars(); editing = true
settings.xpEnabled = true
X.SyncExisting("xp")
xpBar().barVisibility = "in_combat"
editing = false
X.SyncExisting()
eq(#writes, 0, "contents changed unseen: a waiting claim does not land")
eq(xpBar().barVisibility, "in_combat", "contents changed unseen: the bar keeps the new choice")

reset(); euiBars(); inCombat = true
settings.xpEnabled = true
X.SyncExisting("xp")
generation = generation + 1
X.SyncExisting()
check(not waitingForCombat(), "import in combat: the dropped claim leaves nothing waiting")
inCombat = false
regen()
eq(#writes, 0, "import in combat: and nothing lands after combat")

-- Every way a claim made in combat can be canceled before combat ends:
-- nothing may still wait for combat to end afterwards.
local function canceled(label, undo)
    reset(); euiBars(); inCombat = true
    settings.xpEnabled = true
    X.SyncExisting("xp")
    check(waitingForCombat(), label .. ": the claim waits for combat to end")
    undo()
    check(not waitingForCombat(), label .. ": nothing waits once it is canceled")
    inCombat = false
    regen()
    eq(#writes, 0, label .. ": nothing is written after combat")
end
canceled("bar turned off in combat", function()
    settings.xpEnabled = false
    X.SyncExisting()
end)
canceled("Hide Existing turned off in combat", function()
    settings.xpHideExisting = false
    X.SyncExisting("xp")
end)
canceled("profile switched in combat", function()
    switchProfile("Other"); euiBars()
    X.SyncExisting()
end)
canceled("profile refilled in combat", function()
    generation = generation + 1
    X.SyncExisting()
end)
canceled("reset in combat", function()
    X.SyncExisting(nil, true)
end)

reset(); profile, eab = { useBlizzardDataBars = true }, nil; inCombat = true
settings.xpEnabled = true
X.SyncExisting()
check(waitingForCombat(), "blizzard in combat: the move waits for combat to end")
settings.xpEnabled = false
X.SyncExisting()
check(not waitingForCombat(), "blizzard in combat: turned back off, nothing waits")
inCombat = false
regen()
eq(manager.parent, _G.UIParent, "blizzard in combat: the bar never moved")

reset(); euiBars(); inCombat = true
settings.xpEnabled = true
X.SyncExisting("xp")
eq(#writes, 0, "combat: nothing is written")
inCombat = false
regen()
eq(#writes, 1, "combat: the claim lands when combat ends")
check(snaps.xp and snaps.xp.prev and snaps.xp.prev.always, "combat: with its note")

reset(); euiBars()
settings.xpEnabled = true
X.SyncExisting("xp")
xpBar().barVisibility, xpBar().alwaysHidden = "always", false
writes = {}
X.SyncExisting()
eq(#writes, 0, "changed while held: Never is not forced back")
eq(snaps.xp.prev, nil, "changed while held: the note is dropped")
eq(xpBar().barVisibility, "always", "changed while held: the player's choice stays")

reset(); euiBars()
settings.xpEnabled = true
X.SyncExisting("xp")
xpBar().barVisibility = "mouseover"
settings.xpEnabled = false
writes = {}
X.SyncExisting("xp")
eq(#writes, 0, "changed then released: nothing is written")
eq(snaps.xp.prev, nil, "changed then released: the note is cleared")
eq(xpBar().barVisibility, "mouseover", "changed then released: the player's choice stays")

reset(); euiBars()
settings.xpEnabled = true
X.SyncExisting("xp")
captured = true
settings.xpEnabled = false
writes = {}
X.SyncExisting("xp")
eq(#writes, 0, "override while held: nothing is written")
eq(snaps.xp.prev, nil, "override while held: the note is released")

reset(); euiBars()
settings.xpEnabled = true
X.SyncExisting("xp")
profile, eab = nil, nil
stored = { bars = { XPBar = { barVisibility = "never", alwaysHidden = true } } }
settings.xpEnabled = false
X.SyncExisting("xp")
eq(storedModes[1], "always", "unloaded: the stored profile gets the previous choice")
eq(stored.bars.XPBar.barVisibility, "always", "unloaded: and reads it")
eq(snaps.xp.prev, nil, "unloaded: the note is cleared")

reset(); euiBars()
settings.xpEnabled = true
X.SyncExisting("xp")
profile, eab = nil, nil
stored = { bars = { XPBar = { barVisibility = "never", alwaysHidden = true } } }
captured = true
settings.xpEnabled = false
X.SyncExisting("xp")
eq(#storedModes, 0, "unloaded and captured: the stored profile is not written")
eq(stored.bars.XPBar.barVisibility, "never", "unloaded and captured: the override's value stays")
eq(snaps.xp.prev, nil, "unloaded and captured: the note is released")

reset(); euiBars()
settings.xpEnabled = true
X.SyncExisting("xp")
profile, eab = nil, nil
stored = { bars = { XPBar = { barVisibility = "never", alwaysHidden = true, visibilityOverride = "never" } } }
settings.xpEnabled = false
X.SyncExisting("xp")
eq(#storedModes, 0, "unloaded with a visibility override: the stored profile is not written")
eq(snaps.xp.prev, nil, "unloaded with a visibility override: the note is released")

reset(); euiBars()
settings.xpEnabled = true
X.SyncExisting("xp")
profile, eab = nil, nil
stored = { bars = { XPBar = { barVisibility = "never", alwaysHidden = true } } }
editing = true
settings.xpEnabled = false
X.SyncExisting("xp")
eq(#storedModes, 0, "unloaded in an editing session: the stored profile is not written")
check(snaps.xp.prev ~= nil, "unloaded in an editing session: the note is kept for later")
editing = false
X.SyncExisting()
eq(storedModes[1], "always", "unloaded in an editing session: the restore lands once it ends")

reset(); euiBars()
settings.xpEnabled = true
X.SyncExisting("xp")
X.SyncExisting(nil, true)
eq(xpBar().barVisibility, "always", "release all: EllesmereUI's bar gets its choice back")
eq(snaps.xp.prev, nil, "release all: the note is cleared")

local paths = {}
if describer then describer("xp", { prev = {} }, function(p) paths[p] = true end) end
check(paths["addons.EllesmereUIActionBars.bars.XPBar.barVisibility"], "held: the XP bar's Visibility is a held path")
check(paths["addons.EllesmereUIActionBars.bars.XPBar.visibilityModes"], "held: with its condition set")
paths = {}
if describer then describer("rep", { prev = {} }, function(p) paths[p] = true end) end
check(paths["addons.EllesmereUIActionBars.bars.RepBar.alwaysHidden"], "held: the reputation bar's fields are held paths")

---------------------------------------------------------------------------------
-- Blizzard's tracking bar
---------------------------------------------------------------------------------

reset(); profile, eab = { useBlizzardDataBars = true }, nil
settings.xpEnabled = true
X.SyncExisting()
check(manager.parent ~= _G.UIParent, "blizzard: the tracking bar moves under a hidden frame")
eq(#writes, 0, "blizzard: no EllesmereUI setting is written")
settings.xpEnabled = false
X.SyncExisting()
eq(manager.parent, _G.UIParent, "blizzard: it comes back to its parent")
inCombat = true
settings.fbEnabled = true
X.SyncExisting()
eq(manager.parent, _G.UIParent, "blizzard: nothing moves in combat")
inCombat = false
regen()
check(manager.parent ~= _G.UIParent, "blizzard: the move lands when combat ends")

---------------------------------------------------------------------------------
-- First position
---------------------------------------------------------------------------------

_G.UIParent.GetEffectiveScale = function() return 1 end
reset(); euiBars()
settings.xpEnabled = true
_G.EllesmereEAB_XPBar = nil
eq(X.SeedPosition(), false, "seed: EllesmereUI's XP bar not built yet asks for a retry")
eq(settings.xpPos, nil, "seed: nothing is stored before that bar exists")
_G.EllesmereEAB_XPBar = {
    GetCenter = function() return 400.4, 60.6 end,
    GetEffectiveScale = function() return 1 end,
}
eq(X.SeedPosition(), true, "seed: EllesmereUI's XP bar built settles the seed")
eq(settings.xpPos and settings.xpPos.x, 400, "seed: its center is stored")
eq(settings.xpPos and settings.xpPos.y, 61, "seed: in UIParent's units, rounded")
_G.EllesmereEAB_XPBar = nil
eq(X.SeedPosition(), true, "seed: a stored spot is never read again")
reset(); profile, eab = { useBlizzardDataBars = true }, nil
settings.xpEnabled = true
eq(X.SeedPosition(), true, "seed: the Blizzard path never asks for a retry")
eq(settings.xpPos, nil, "seed: and stores nothing without a spot")
settings.xpHideExisting = false
eq(X.SeedPosition(), true, "seed: Hide Existing off needs no seed")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
