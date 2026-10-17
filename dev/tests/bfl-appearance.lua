-- ╔══════════════════════════════════════════════════════════════╗
-- ║  bfl-appearance.lua                                          ║
-- ║  Purpose: Gate for the BetterFriendlist write: what an       ║
-- ║           install sets, what it records for /kitn reset, and ║
-- ║           the next-login repair. Loads the SHIPPED code.     ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/bfl-appearance.lua

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

local loaded = { BetterFriendlist = true }
_G.C_AddOns = { IsAddOnLoaded = function(name) return loaded[name] == true end }
_G.print = function() end

local ns = { data = {}, title = "KitnUI", profileName = "KitnUI" }
ns.Color = function(text) return text end
local chunk, err = loadfile("Installer/Setup.lua")
if not chunk then
    io.write("FAIL  could not load Installer/Setup.lua: " .. tostring(err) .. "\n")
    os.exit(1)
end
chunk("KitnUI", ns)

local ABSENT = "__kitnui_absent"

local function player()
    return {
        friendsFrameStyle = "legacy",
        theme = "blizzard",
        simpleMode = false,
        primarySort = "name",
        modernFriendTabVisibility = { raid = false },
    }
end

---------------------------------------------------------------------------------
-- Install: the write and the record
---------------------------------------------------------------------------------

ns.db = {}
_G.BetterFriendlistDB = player()
local bfl = _G.BetterFriendlistDB
ns.ApplyBetterFriendlistAppearance()
local prev = ns.db.bflSnap.prev

eq(bfl.friendsFrameStyle, "modern", "install: the Modern style")
eq(bfl.theme, "dark", "install: the dark theme")
eq(bfl.primarySort, "status", "install: sorted by status")
eq(bfl.secondarySort, "name", "install: then by name")
eq(bfl.simpleMode, true, "install: simple mode")
eq(bfl.compactMode, false, "install: normal rows")
eq(bfl.friendListClickWhisperEnabled, true, "install: whisper from the list")
eq(bfl.friendListClickWhisperMode, "double", "install: on a double click")
eq(#bfl.modernFriendTabOrder, 8, "install: every side tab in the order")
eq(bfl.modernFriendTabOrder[1], "friends", "install: Friends first")
eq(next(bfl.modernFriendTabVisibility), nil, "install: every tab shown")
eq(bfl.modernFriendTabPopulatedOnly.quick_join, false, "install: Quick Join shown when empty")
eq(bfl.appearanceOnboardingVersion, 3, "install: the picker is marked done")

eq(prev.friendsFrameStyle, "legacy", "record: the player's style")
eq(prev.simpleMode, false, "record: a false is kept as false")
eq(prev.compactMode, ABSENT, "record: an absent key is marked absent")
eq(prev.primarySort, "name", "record: the player's sort")
eq(prev.modernFriendTabVisibility and prev.modernFriendTabVisibility.raid, false, "record: the player's hidden tab")
eq(prev.modernFriendTabOrder, ABSENT, "record: an absent table is marked absent")

ns.RecheckBetterFriendlistAppearance()
eq(ns.db.bflSnap.pending, nil, "repair: a write that held settles")

---------------------------------------------------------------------------------
-- Reset hands every recorded value back
---------------------------------------------------------------------------------

eq(ns.RestoreBetterFriendlistAppearance(), true, "reset: restores")
eq(bfl.friendsFrameStyle, "legacy", "reset: the style")
eq(bfl.simpleMode, false, "reset: simple mode")
eq(bfl.compactMode, nil, "reset: an absent key is absent again")
eq(bfl.primarySort, "name", "reset: the sort")
eq(bfl.modernFriendTabVisibility.raid, false, "reset: the hidden tab")
eq(bfl.modernFriendTabOrder, nil, "reset: the tab order is absent again")

---------------------------------------------------------------------------------
-- A record from an install before these keys were managed
---------------------------------------------------------------------------------

ns.db = { bflSnap = { taken = true, prev = { friendsFrameStyle = "legacy", theme = "blizzard" } } }
_G.BetterFriendlistDB = { friendsFrameStyle = "legacy", theme = "dark", simpleMode = false, primarySort = "zone" }
bfl = _G.BetterFriendlistDB
ns.ApplyBetterFriendlistAppearance()
prev = ns.db.bflSnap.prev
eq(prev.theme, "blizzard", "backfill: an existing record is kept")
eq(prev.primarySort, "zone", "backfill: a newly managed key records the player's value")
eq(prev.simpleMode, false, "backfill: including a false")
eq(bfl.primarySort, "status", "backfill: and is then written")

---------------------------------------------------------------------------------
-- The picker's rollback undoes the write before the next login
---------------------------------------------------------------------------------

ns.db = {}
_G.BetterFriendlistDB = player()
bfl = _G.BetterFriendlistDB
ns.ApplyBetterFriendlistAppearance()
bfl.friendsFrameStyle, bfl.simpleMode, bfl.compactMode = "legacy", false, true
ns.RecheckBetterFriendlistAppearance()
prev = ns.db.bflSnap.prev
eq(bfl.simpleMode, true, "repair: simple mode is written again")
eq(bfl.compactMode, false, "repair: compact mode too")
eq(prev.simpleMode, false, "repair: the rolled-back false is recorded, not marked absent")
eq(prev.compactMode, true, "repair: the rolled-back true is recorded")
eq(ns.db.bflSnap.pending, 2, "repair: one attempt spent")

bfl.modernFriendTabVisibility = { raid = false }
ns.RecheckBetterFriendlistAppearance()
eq(next(bfl.modernFriendTabVisibility), nil, "repair: a hidden tab fails the check and is shown again")
eq(prev.modernFriendTabVisibility.raid, false, "repair: a key the picker cannot reach is not re-recorded")

io.write(string.format("%d checks, %d failures\n", checks, failures))
os.exit(failures == 0 and 0 or 1)
