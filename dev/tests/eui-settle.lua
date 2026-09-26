-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-settle.lua                                              ║
-- ║  Purpose: Gate for the settled snapshot's arming and         ║
-- ║           capture: nothing created with nothing pending,     ║
-- ║           one timer after the loading screen, the wait each  ║
-- ║           refusal takes, and what the capture records.       ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/eui-settle.lua

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

local game = { combat = false }
_G.InCombatLockdown = function() return game.combat end
_G.debugprofilestop = function() return 0 end

-- Frames keep the events they are registered for, and `fire` delivers one
-- only while it is registered, as the client does.
local frames = {}
_G.CreateFrame = function()
    local f = { events = {}, scripts = {} }
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterEvent(event) self.events[event] = nil end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = f
    return f
end
local function fire(f, event)
    if f and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event) end
end
local function listening(f)
    local out = {}
    for event in pairs(f and f.events or {}) do out[#out + 1] = event end
    table.sort(out)
    return table.concat(out, ",")
end

local timers = {}
_G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
-- Runs the timers started so far; returns how many ran.
local function runTimers()
    local started = timers
    timers = {}
    for _, t in ipairs(started) do t.fn() end
    return #started
end

local exports = 0
local E = { _ADDON_DB_MAP = {}, establishPending = false }
for _, fn in ipairs({ "DecodeImportStringAsync", "DecodeImportString", "RenameProfile", "DeleteProfile",
    "ImportProfile", "BuildImportKeyToFolder", "FilterLayoutToFolders", "SetProfile" }) do
    E[fn] = function() end
end
E.ExportProfile = function()
    exports = exports + 1
    return "export-" .. exports
end
E.Conditions_EstablishPending = function() return E.establishPending end
_G.EllesmereUI = E
local profile = {}
_G.EllesmereUIDB = { activeProfile = "KitnUI", profiles = { KitnUI = profile } }

local ns = { profileName = "KitnUI", data = {}, title = "KitnUI" }
for _, file in ipairs({ "Installer/Merge.lua", "Installer/MergeInputs.lua", "Installer/ModuleRows.lua", "Installer/Update.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", ns)
end
ns.EUIHeldPaths = function() return { ["fonts.global"] = true } end
-- The list's hook; it counts the captures that reached it.
local landed = 0
ns.EUISettleLanded = function() landed = landed + 1 end

-- The boot's call at a login with this record, with fresh frames and timers.
-- Returns the frame it created, if any.
local function login(record)
    ns.db = record
    frames, timers = {}, {}
    exports, landed = 0, 0
    game.combat = false
    E.establishPending = false
    _G.EllesmereUIDB.activeProfile = "KitnUI"
    profile._importEstablishPending = nil
    ns.EUIArmSettle()
    return frames[1]
end

---------------------------------------------------------------------------------
-- Nothing pending
---------------------------------------------------------------------------------

eq(login({}), nil, "idle: nothing pending creates no frame")
eq(#timers, 0, "idle: and starts no timer")
eq(ns.EUIPartSettle("general"), nil, "idle: a profile from before snapshots has no state")
eq(login({ euiSettlePending = { ["*"] = "yes" } }), nil, "idle: a pending mark of the wrong type is nothing pending")

---------------------------------------------------------------------------------
-- Pending: one frame, one timer, one capture
---------------------------------------------------------------------------------

eq(ns.EUI_SETTLE_DELAY, 10, "the settle delay is ten seconds")
local frame = login({ euiSettlePending = { ["*"] = true } })
check(frame ~= nil, "armed: a pending change creates a frame")
eq(#frames, 1, "armed: one frame")
eq(listening(frame), "PLAYER_ENTERING_WORLD", "armed: waiting for the loading screen")
eq(ns.EUIPartSettle("general"), "due", "armed: a part changed before this session is due")
eq(ns.euiSettleOpen, false, "armed: the settle moment has not passed")
fire(frame, "PLAYER_ENTERING_WORLD")
eq(listening(frame), "PLAYER_ENTERING_WORLD", "armed: the frame still listens for loading screens")
eq(#timers, 1, "armed: the loading screen starts one timer")
eq(timers[1] and timers[1].delay, ns.EUI_SETTLE_DELAY, "armed: of the settle delay")
fire(frame, "PLAYER_ENTERING_WORLD")
eq(#timers, 2, "armed: a second loading screen starts the delay again")
local first = table.remove(timers, 1)
if first then first.fn() end
eq(exports, 0, "armed: the first loading screen's timer captures nothing")
eq(ns.euiSettleOpen, false, "armed: and the settle moment has not come")
runTimers()
eq(ns.euiSettleOpen, true, "captured: the settle moment has passed")
eq(landed, 1, "captured: the list is told once")
local snap = ns.db.euiSettled and ns.db.euiSettled[1]
eq(snap and snap.s, "export-1", "captured: the export is the snapshot")
eq(snap and snap.held and snap.held["fonts.global"], true, "captured: with what the switches held")
eq(ns.db.euiSettledAt and ns.db.euiSettledAt["*"], 1, "captured: for every part")
eq(ns.db.euiSettlePending, nil, "captured: nothing is left pending")
eq(ns.EUIPartSettle("general"), "settled", "captured: a part reads settled")
eq(listening(frame), "", "captured: the frame listens for nothing")
eq(exports, 1, "captured: one export")

---------------------------------------------------------------------------------
-- Refusals
---------------------------------------------------------------------------------

frame = login({ euiSettlePending = { ["*"] = true } })
fire(frame, "PLAYER_ENTERING_WORLD")
game.combat = true
runTimers()
eq(ns.db.euiSettled, nil, "combat: nothing is recorded in combat")
eq(listening(frame), "PLAYER_ENTERING_WORLD,PLAYER_REGEN_ENABLED", "combat: the capture waits for combat to end")
eq(ns.EUIPartSettle("general"), "due", "combat: the parts stay due")
eq(landed, 0, "combat: a refusal tells the list nothing")
game.combat = false
fire(frame, "PLAYER_REGEN_ENABLED")
eq(ns.db.euiSettled, nil, "combat: its end records nothing at once")
eq(#timers, 1, "combat: it starts the settle delay again")
eq(timers[1] and timers[1].delay, ns.EUI_SETTLE_DELAY, "combat: the whole delay")
eq(listening(frame), "PLAYER_ENTERING_WORLD", "combat: and no longer waits for combat")
runTimers()
eq(ns.db.euiSettled and ns.db.euiSettled[1] and ns.db.euiSettled[1].s, "export-1", "combat: recorded when the delay ends")
eq(listening(frame), "", "combat: and the frame listens for nothing")

-- Refused in combat, then a loading screen before combat ends: the new delay
-- runs whole, and combat ending inside it captures nothing.
frame = login({ euiSettlePending = { ["*"] = true } })
fire(frame, "PLAYER_ENTERING_WORLD")
game.combat = true
runTimers()
fire(frame, "PLAYER_ENTERING_WORLD")
eq(listening(frame), "PLAYER_ENTERING_WORLD", "combat then loading: the new delay drops the wait for combat")
game.combat = false
fire(frame, "PLAYER_REGEN_ENABLED")
eq(ns.db.euiSettled, nil, "combat then loading: combat ending inside the new delay records nothing")
eq(runTimers(), 1, "combat then loading: the new delay runs")
eq(ns.db.euiSettled and ns.db.euiSettled[1] and ns.db.euiSettled[1].s, "export-1",
    "combat then loading: and records when it ends")

local refusals = {
    { "establishing", function(on) E.establishPending = on end },
    { "import establishing", function(on) profile._importEstablishPending = on or nil end },
    { "another profile", function(on) _G.EllesmereUIDB.activeProfile = on and "Other" or "KitnUI" end },
    { "options panel open", function(on)
        E._mainFrame = on and { IsShown = function() return true end } or nil
    end },
    { "override edit", function(on)
        E.SpecOverrides_EditSessionActive = on and function() return true end or nil
    end },
}
for _, case in ipairs(refusals) do
    local name, set = case[1], case[2]
    frame = login({ euiSettlePending = { ["*"] = true } })
    fire(frame, "PLAYER_ENTERING_WORLD")
    set(true)
    runTimers()
    eq(ns.db.euiSettled, nil, name .. ": nothing is recorded")
    eq(exports, 0, name .. ": and nothing exported")
    eq(landed, 0, name .. ": and the list is told nothing")
    eq(listening(frame), "PLAYER_ENTERING_WORLD", name .. ": the capture waits for the next loading screen")
    set(false)
    fire(frame, "PLAYER_ENTERING_WORLD")
    eq(runTimers(), 1, name .. ": which starts the timer again")
    eq(ns.db.euiSettled and ns.db.euiSettled[1] and ns.db.euiSettled[1].s, "export-1", name .. ": and records")
end

-- Nothing is left due when the timer fires: a Restore emptied the due set.
frame = login({ euiSettlePending = { ["*"] = true } })
fire(frame, "PLAYER_ENTERING_WORLD")
ns.euiSettleDue = {}
runTimers()
eq(exports, 0, "nothing due: the timer exports nothing")
eq(listening(frame), "", "nothing due: and the frame listens for nothing")

---------------------------------------------------------------------------------
-- A part installed after login waits for the next one
---------------------------------------------------------------------------------

local RB = "EllesmereUIResourceBars"
frame = login({ euiSettlePending = { ["*"] = true } })
local before = { settled = ns.db.euiSettled, at = ns.db.euiSettledAt, pending = ns.db.euiSettlePending, due = ns.euiSettleDue }
ns.db.euiSettled, ns.db.euiSettledAt, ns.db.euiSettlePending, ns.euiSettleDue =
    ns.EUISettleRecord("reset", before, { parts = { [RB] = true } })
eq(ns.EUIPartSettle(RB), "pending", "later: a part reset after login is pending, not due")
fire(frame, "PLAYER_ENTERING_WORLD")
runTimers()
eq(ns.db.euiSettledAt and ns.db.euiSettledAt["*"], 1, "later: the capture records the parts that were due")
eq(ns.db.euiSettledAt and ns.db.euiSettledAt[RB], false, "later: but not the part reset this session")
eq(ns.db.euiSettlePending and ns.db.euiSettlePending[RB], true, "later: which waits for the next login")
eq(ns.EUIPartSettle(RB), "pending", "later: and still reads pending")

frame = login(ns.db)
check(frame ~= nil, "next login: the waiting part arms the capture")
fire(frame, "PLAYER_ENTERING_WORLD")
runTimers()
eq(ns.db.euiSettledAt and ns.db.euiSettledAt[RB], 2, "next login: the part gets the new snapshot")
eq(ns.db.euiSettledAt and ns.db.euiSettledAt["*"], 1, "next login: the others keep theirs")
eq(ns.db.euiSettled and ns.db.euiSettled[2] and ns.db.euiSettled[2].s, "export-1", "next login: from that session's export")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
