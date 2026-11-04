-- ╔══════════════════════════════════════════════════════════════╗
-- ║  xpbar-session.lua                                           ║
-- ║  Purpose: Gate for the XP session: where it starts, what     ║
-- ║           a /reload keeps, and when /played is asked.        ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/xpbar-session.lua

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

local DEFAULTS = { xpResetOnReload = false, xpShowLevelTime = true, xpMutePlayed = false }
local clock, wall, played = 0, 0, 0
_G.GetTime = function() return clock end
_G.time = function() return wall end
_G.RequestTimePlayed = function() played = played + 1 end

-- Next-frame work waits in later until flush() runs it.
local later = {}
_G.C_Timer = {
    After = function(_, fn) later[#later + 1] = fn end,
    NewTimer = function() return { Cancel = function() end } end,
}
local function flush()
    local run = later
    later = {}
    for i = 1, #run do run[i]() end
end

local chat = { on = true }
function chat:IsEventRegistered() return self.on end
function chat:UnregisterEvent() self.on = false end
function chat:RegisterEvent() self.on = true end
_G.ChatFrame1 = chat
_G.Constants = { ChatFrameConstants = { MaxChatWindows = 1 } }

local function XP(cur, max, level, atMax)
    return { cur = cur, max = max, level = level, atMax = atMax or false, xpOff = false }
end

-- A fresh load of the shipped files. Returns the module and a setter for
-- what ReadXP reports next. opts.barOff reads as the XP bar being off.
local function load(opts)
    later, chat.on = {}, true
    local ns = { db = { perChar = {} }, EUILoadStart = opts.start }
    ns.GetCharKey = function() return not opts.noKey and "Tester-Realm" or nil end
    if opts.rec then ns.db.perChar["Tester-Realm"] = { xp = opts.rec } end
    for _, file in ipairs({ "KitnUI_EUI/XPBar/Math.lua", "KitnUI_EUI/XPBar/Session.lua" }) do
        local chunk, err = loadfile(file)
        if not chunk then
            print("FAIL  could not load " .. file .. ": " .. tostring(err))
            os.exit(1)
        end
        if file:find("Session") then
            local current = opts.xp
            ns.XPBar.ReadXP = function() return current end
            ns.XPBar.Get = function(key)
                local v = opts.settings and opts.settings[key]
                if v == nil then v = DEFAULTS[key] end
                return v
            end
            ns.setXP = function(t) current = t end
        end
        chunk("KitnUI_EUI", ns)
    end
    ns.XPBar.SessionListen(not opts.barOff)
    return ns.XPBar, ns.setXP
end

-- Turned on an hour after login
clock, wall, played = 4600, 90000, 0
local X, setXP = load({ start = { time = 1000, xp = 100, max = 1000, level = 10 }, xp = XP(600, 1000, 10) })
X.SessionStart("login")
eq(X.SessionElapsed(), 3600, "turned on later: the session counts from the login")
eq(X.SessionGained(), 500, "turned on later: its XP is the XP since the login")
setXP(XP(900, 1000, 10))
X.OnXP()
eq(X.SessionGained(), 800, "turned on later: XP from then on adds to it")

X = load({ start = { time = 1000, xp = 900, max = 1000, level = 10 }, xp = XP(200, 1200, 11) })
X.SessionStart("login")
eq(X.SessionGained(), 300, "a level passed before the bar ran: the rest of it counts")

X = load({ xp = XP(600, 1000, 10) })
X.SessionStart("login")
eq(X.SessionElapsed(), 0, "no captured start: the session counts from now")
eq(X.SessionGained(), 0, "no captured start: with nothing gained")

-- A level-up reported level first, through the session's own handlers
X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("login")
setXP(XP(900, 1200, 11))
X.OnLevelUp(11)
setXP(XP(100, 1200, 11))
X.OnXP()
X.OnXP()
eq(X.SessionGained(), 200, "level first: the level counts once")

-- A save takes a reading first
local saved = {}
X, setXP = load({ rec = saved, xp = XP(600, 1000, 10) })
X.SessionStart("login")
setXP(XP(700, 1000, 10))
X.SessionSave()
eq(saved.gained, 100, "save: XP since the last event is in it")
eq(saved.lastXP, 700, "save: with the reading it was taken at")

-- A save between a level's rise and its new total
local mid = {}
X, setXP = load({ rec = mid, xp = XP(900, 1000, 10) })
X.SessionStart("login")
setXP(XP(100, 1000, 11))
X.SessionSave()
X = load({ rec = mid, start = { time = 4595, xp = 100, max = 1000, level = 11 }, xp = XP(100, 1200, 11) })
X.SessionStart("reload")
eq(X.SessionGained(), 200, "reload: a save between the level and its total counts the level once")
X = load({ rec = mid, settings = { xpResetOnReload = true }, start = { time = 4595, xp = 100, max = 1000, level = 11 },
    xp = XP(100, 1200, 11) })
X.SessionStart("reload")
eq(X.SessionGained(), 0, "reset on reload: a level half reported before the save counts no level again")

-- Reset XP Session Now between a level's rise and its new total
X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("login")
setXP(XP(100, 1000, 11))
X.OnXP()
X.ResetSession()
setXP(XP(100, 1200, 11))
X.OnXP()
eq(X.SessionGained(), 0, "reset now: a level half reported before the reset counts no level again")
setXP(XP(150, 1200, 11))
X.OnXP()
eq(X.SessionGained(), 50, "reset now: XP after the reset counts")

X = load({ start = { time = 1000, xp = 100, max = 1000, level = 10 }, xp = XP(600, 1000, 10) })
X.ResetSession()
eq(X.SessionStarted(), false, "reset now before the session starts: nothing starts")
X.SessionStart("login")
eq(X.SessionGained(), 500, "reset now before the session starts: the session still counts from the login")

-- Both asks due: the ask again wins, muted, and is re-armed when its reply
-- cannot be heard
played = 0
X = load({ start = { time = 1000, xp = 900, max = 1000, level = 10 }, xp = XP(200, 1200, 11) })
X.SessionStart("login")
X.RequestPlayed()
eq(played, 1, "both due, ask again first: one request")
eq(chat.on, false, "both due, ask again first: muted with Mute /played in Chat off")
X.SessionListen(false)
X.SessionListen(true)
X.RequestPlayed()
eq(played, 2, "both due, ask again first: a lost reply re-arms it")

played = 0
X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.RequestPlayed()
eq(chat.on, true, "login ask first: unmuted with Mute /played in Chat off")
X.SessionListen(false)
setXP(XP(50, 1200, 11))
X.SessionSave()
X.SessionListen(true)
X.OnXP()
X.RequestPlayed()
eq(played, 2, "login ask first, then an unseen level-up: the ask again runs")
eq(chat.on, false, "login ask first, then an unseen level-up: muted")

-- A request that raises spends nothing
played = 0
local realRequest = _G.RequestTimePlayed
_G.RequestTimePlayed = function() error("refused") end
X = load({ settings = { xpMutePlayed = true }, xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.RequestPlayed()
eq(chat.on, true, "request error: chat is given back")
_G.RequestTimePlayed = realRequest
X.RequestPlayed()
eq(played, 1, "request error: the login ask is still due")

-- A /reload
local rec = { savedAt = 90000 - 10, gained = 5000, elapsed = 120, levelTime = 300, levelOf = 10, kills = { 400 },
    lastXP = 600, lastMax = 1000, lastLevel = 10 }
X = load({ rec = rec, start = { time = 4595, xp = 600, max = 1000, level = 10 }, xp = XP(650, 1000, 10) })
X.SessionStart("reload")
eq(X.SessionGained(), 5050, "reload: the saved session continues, with the XP since its save")
eq(X.SessionElapsed(), 130, "reload: its time advanced by the gap")
eq(X.LevelTime(), 310, "reload: and the time this level")
eq(#X.Kills(), 1, "reload: with its kill samples")

-- A timely /reload with the bars turned on ten minutes later
local late = { savedAt = 90000 - 610, gained = 5000, elapsed = 120, lastXP = 600, lastMax = 1000, lastLevel = 10 }
X = load({ rec = late, start = { time = 4600 - 600, xp = 600, max = 1000, level = 10 }, xp = XP(650, 1000, 10) })
X.SessionStart("reload")
eq(X.SessionGained(), 5050, "late first apply: a /reload 10 s after its save continues the session")
eq(X.SessionElapsed(), 730, "late first apply: its time advanced through to the first apply")
local slow = { savedAt = 90000 - 960, gained = 5000, elapsed = 120, lastXP = 600, lastMax = 1000, lastLevel = 10 }
X = load({ rec = slow, start = { time = 4600 - 600, xp = 600, max = 1000, level = 10 }, xp = XP(650, 1000, 10) })
X.SessionStart("reload")
eq(X.SessionGained(), 50, "late first apply: a /reload 6 minutes after its save starts at the reload")

X = load({ rec = rec, settings = { xpResetOnReload = true }, start = { time = 4595, xp = 600, max = 1000, level = 10 },
    xp = XP(650, 1000, 10) })
X.SessionStart("reload")
eq(X.SessionGained(), 50, "reset on reload: the session starts at the reload")
eq(X.SessionElapsed(), 5, "reset on reload: its time too")
eq(X.LevelTime(), 310, "reset on reload: the time this level is kept")

local old = { savedAt = 90000 - 1000, gained = 5000, elapsed = 120, levelTime = 300 }
X = load({ rec = old, start = { time = 4595, xp = 600, max = 1000, level = 10 }, xp = XP(650, 1000, 10) })
X.SessionStart("reload")
eq(X.SessionGained(), 50, "an old save: the session starts at the reload")
eq(X.LevelTime(), nil, "an old save: the time this level is unknown")

-- The time this level belongs to one level: every way a level-up can go by
-- unseen makes it unknown, and no stale reading does.
X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(nil, 300)
eq(X.LevelTime(), 300, "level clock: /played seeds it")
setXP(XP(50, 1200, 11))
X.OnXP()
eq(X.LevelTime(), nil, "level clock: a level gained unseen makes it unknown")

X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(nil, 300)
setXP(XP(50, 1200, 11))
X.SessionSave()
eq(X.LevelTime(), nil, "level clock: a save after an unseen level-up drops it")

local unseen = {}
X = load({ rec = unseen, xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(nil, 300)
X.SessionSave()
eq(unseen.levelOf, 10, "level clock: a save records the level it belongs to")

X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(nil, 300)
X.OnLevelUp(11)
eq(X.LevelTime(), 0, "level clock: a level-up restarts it")
X.OnXP()
eq(X.LevelTime(), 0, "level clock: a stale reading of the old level keeps it")
setXP(XP(100, 1200, 11))
X.OnXP()
eq(X.LevelTime(), 0, "level clock: the new level's reading keeps it")

played = 0
X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(nil, 300)
setXP(XP(900, 1200, 10))
X.OnXP()
eq(X.LevelTime(), nil, "level clock: a new total read before the event clears it")
X.OnLevelUp(11)
eq(X.LevelTime(), 0, "level clock: and the event starts it again")
flush()
eq(played, 0, "level clock: a level-up whose event follows its reading asks nothing")

local leveled = { savedAt = 90000 - 10, gained = 0, elapsed = 120, levelTime = 300, levelOf = 10,
    lastXP = 600, lastMax = 1000, lastLevel = 10 }
played = 0
X = load({ rec = leveled, xp = XP(50, 1200, 11) })
X.SessionStart("reload")
eq(X.LevelTime(), nil, "level clock: a reload save from an earlier level is not restored")
X.RequestPlayed()
eq(played, 1, "ask again: a /reload after an unseen level-up asks once more")
eq(chat.on, false, "ask again: muted, with Mute /played in Chat off")

local noLevel = { savedAt = 90000 - 10, gained = 0, elapsed = 120, levelTime = 300 }
X = load({ rec = noLevel, xp = XP(650, 1000, 10) })
X.SessionStart("reload")
eq(X.LevelTime(), nil, "level clock: a save that does not name its level is not restored")

-- Asked again when an unseen level-up makes the time this level unknown. The
-- loads are /reloads, where the login ask never runs.
played = 0
X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("reload")
X.OnPlayed(nil, 300)
setXP(XP(50, 1200, 11))
X.OnXP()
eq(played, 0, "ask again: on the next frame")
flush()
eq(played, 1, "ask again: an unseen level-up asks once more")
eq(chat.on, false, "ask again: muted, whatever Mute /played in Chat says")
X.OnPlayed(nil, 20)
flush()
eq(X.LevelTime(), 20, "ask again: the reply sets the time this level")
eq(chat.on, true, "ask again: chat comes back")

played = 0
X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("reload")
X.OnPlayed(nil, 300)
setXP(XP(50, 1200, 11))
X.OnXP()
flush()
setXP(XP(50, 1500, 12))
X.OnLevelUp(12)
setXP(XP(50, 1800, 13))
X.OnXP()
flush()
eq(played, 1, "ask again: never while a request waits for its reply")

played = 0
X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("reload")
X.OnPlayed(nil, 300)
X.SessionListen(false)
setXP(XP(50, 1200, 11))
X.SessionSave()
eq(#later, 0, "ask again: the save that turns the XP bar off queues nothing")
eq(played, 0, "ask again: not while the XP bar is off")
X.SessionListen(true)
X.OnXP()
X.RequestPlayed()
eq(played, 1, "ask again: asked once the XP bar is back")

-- An unseen level-up asks whether or not the clock was known
played = 0
X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("reload")
eq(X.LevelTime(), nil, "unknown clock: a /reload with no save leaves it unknown")
X.SessionListen(false)
setXP(XP(50, 1200, 11))
X.SessionSave()
X.SessionListen(true)
X.OnXP()
X.RequestPlayed()
eq(played, 1, "unknown clock: an unseen level-up still asks again")

-- A request whose reply can no longer be heard
played = 0
X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("reload")
X.OnPlayed(nil, 300)
setXP(XP(50, 1200, 11))
X.OnXP()
flush()
X.SessionListen(false)
X.SessionListen(true)
X.RequestPlayed()
eq(played, 2, "reply lost: the XP bar going off before the reply lets the ask again run once more")

played = 0
X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.RequestPlayed()
X.SessionListen(false)
X.SessionListen(true)
X.RequestPlayed()
eq(played, 1, "reply lost: a spent login ask stays spent")
X.SessionListen(false)
setXP(XP(50, 1200, 11))
X.SessionSave()
X.SessionListen(true)
X.OnXP()
X.RequestPlayed()
eq(played, 2, "reply lost: a later unseen level-up still asks again")

played = 0
X, setXP = load({ xp = XP(600, 1000, 10) })
X.SessionStart("reload")
X.OnPlayed(nil, 300)
setXP(XP(0, 0, 90, true))
X.OnXP()
flush()
eq(played, 0, "ask again: not at max level")

-- /played
played = 0
X = load({ xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.RequestPlayed()
X.RequestPlayed()
eq(played, 1, "played: asked once after a login")
played = 0
X = load({ xp = XP(600, 1000, 10) })
X.SessionStart("reload")
X.RequestPlayed()
eq(played, 0, "played: the login ask never runs after a /reload")
X = load({ xp = XP(0, 0, 90, true) })
X.SessionStart("login")
X.RequestPlayed()
eq(played, 0, "played: not asked at max level, where the line is not drawn")
X = load({ xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.OnLevelUp()
X.RequestPlayed()
eq(played, 0, "played: not asked while the time this level is known")

-- Pause
clock, wall, played = 1000, 50000, 0
X, setXP = load({ xp = XP(100, 1000, 10) })
X.SessionPause(true)
eq(X.SessionPaused(), false, "pause: nothing before the session starts")
X.SessionStart("login")
setXP(XP(200, 1000, 10))
clock = 1100
X.SessionPause(true)
eq(X.SessionPaused(), true, "pause: on")
eq(X.SessionGained(), 100, "pause: XP up to the click counts")
eq(X.SessionElapsed(), 100, "pause: time up to the click counts")
setXP(XP(500, 1000, 10))
clock = 1300
X.OnXP()
eq(X.SessionGained(), 100, "pause: XP during it is dropped")
eq(X.SessionElapsed(), 100, "pause: the elapsed time is frozen")
X.SessionPause(false)
eq(X.SessionPaused(), false, "start: off")
eq(X.SessionGained(), 100, "start: XP during the pause stays out")
eq(X.SessionElapsed(), 100, "start: resumes from the frozen time")
setXP(XP(600, 1000, 10))
clock = 1350
X.OnXP()
eq(X.SessionGained(), 200, "start: later XP counts")
eq(X.SessionElapsed(), 150, "start: and later time")

-- The time this level runs through a pause, and a level-up during one
clock, wall = 1000, 50000
X, setXP = load({ xp = XP(100, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(5000, 300)
X.SessionPause(true)
clock = 1060
eq(X.LevelTime(), 360, "pause: the level clock keeps running")
setXP(XP(50, 1200, 11))
X.OnLevelUp(11)
eq(X.SessionGained(), 0, "pause: a level-up during it counts no XP")
eq(X.History().splits[10], 360, "pause: and is still recorded")
eq(X.LevelTime(), 0, "pause: and the clock restarts")
eq(X.SessionPaused(), true, "pause: and it holds")

-- Reset while paused
clock = 1000
X, setXP = load({ xp = XP(100, 1000, 10) })
X.SessionStart("login")
setXP(XP(200, 1000, 10))
clock = 1100
X.SessionPause(true)
clock = 1200
X.ResetSession()
eq(X.SessionGained(), 0, "reset while paused: zero XP")
eq(X.SessionElapsed(), 0, "reset while paused: zero time")
eq(X.SessionPaused(), true, "reset while paused: stays paused")
clock = 1300
eq(X.SessionElapsed(), 0, "reset while paused: and frozen")
X.SessionPause(false)
clock = 1350
eq(X.SessionElapsed(), 50, "reset while paused: Start counts from there")

-- A save, and a /reload, while paused
do
    local record = {}
    clock, wall = 1000, 50000
    X, setXP = load({ rec = record, xp = XP(100, 1000, 10) })
    X.SessionStart("login")
    X.OnPlayed(5000, 300)
    setXP(XP(300, 1000, 10))
    clock, wall = 1100, 50100
    X.SessionPause(true)
    clock, wall = 1200, 50200
    X.SessionSave()
    eq(record.paused, true, "save: records the pause")
    eq(record.elapsed, 100, "save: and the frozen time")
    eq(record.played, 5200, "save: and the total")

    clock, wall = 2000, 50230
    local start = { time = 1995, xp = 700, max = 1000, level = 10 }
    X = load({ rec = record, start = start, xp = XP(700, 1000, 10) })
    X.SessionStart("reload")
    eq(X.SessionPaused(), true, "reload while paused: stays paused")
    eq(X.SessionGained(), 200, "reload while paused: the same XP, without what came since")
    eq(X.SessionElapsed(), 100, "reload while paused: the same time, without the gap")
    eq(X.PlayedTotal(), 5230, "reload while paused: the total advances by the gap")
    eq(X.LevelTime(), 530, "reload while paused: the level clock advances by the gap")

    X = load({ rec = record, start = start, settings = { xpResetOnReload = true }, xp = XP(700, 1000, 10) })
    X.SessionStart("reload")
    eq(X.SessionPaused(), true, "reset on reload while paused: stays paused")
    eq(X.SessionGained(), 0, "reset on reload while paused: at zero XP")
    eq(X.SessionElapsed(), 0, "reset on reload while paused: at zero time")

    X = load({ rec = record, xp = XP(700, 1000, 10) })
    X.SessionStart("login")
    eq(X.SessionPaused(), false, "login after a paused save: running")
    eq(X.PlayedTotal(), nil, "login: the saved total is not restored")

    wall = 60000
    X = load({ rec = record, xp = XP(700, 1000, 10) })
    X.SessionStart("reload")
    eq(X.SessionPaused(), false, "an old save: running")
end

-- The XP bar going off and on while paused
clock, wall = 1000, 50000
X, setXP = load({ rec = {}, xp = XP(100, 1000, 10) })
X.SessionStart("login")
X.SessionPause(true)
X.SessionListen(false)
setXP(XP(400, 1000, 10))
X.SessionSave()
X.SessionListen(true)
X.OnXP()
eq(X.SessionPaused(), true, "bar off and on while paused: stays paused")
eq(X.SessionGained(), 0, "bar off and on while paused: adds nothing")

-- Reaching max level ends a pause, whichever order the level-up and its reading
-- come in, and a /reload there comes back running.
do
    local function reading(cur, level)
        return XP(cur, 1000, level, level >= 90)
    end

    clock, wall = 1000, 50000
    X, setXP = load({ xp = reading(100, 89) })
    X.SessionStart("login")
    setXP(reading(200, 89))
    clock = 1100
    X.SessionPause(true)
    clock = 1200
    setXP(reading(0, 90))
    X.OnXP()
    eq(X.SessionPaused(), false, "max level: a reading of it ends a pause")
    eq(X.SessionGained(), 100, "max level: XP during the pause stays out")
    eq(X.SessionElapsed(), 100, "max level: the session resumes from the frozen time")
    X.OnLevelUp(90)
    eq(X.SessionPaused(), false, "max level: and its level-up after the reading changes nothing")
    clock = 1250
    eq(X.SessionElapsed(), 150, "max level: the session runs again")

    clock = 1000
    X, setXP = load({ xp = reading(100, 89) })
    X.SessionStart("login")
    X.SessionPause(true)
    clock = 1100
    X.OnLevelUp(90)
    eq(X.SessionPaused(), true, "max level: a level-up with the level still reading old waits for its reading")
    clock = 1200
    setXP(reading(0, 90))
    X.OnXP()
    eq(X.SessionPaused(), false, "max level: and the reading ends the pause")
    eq(X.SessionGained(), 0, "max level: with no XP from the pause when the level-up comes first")
    eq(X.SessionElapsed(), 0, "max level: and the time from before the pause when the level-up comes first")

    clock = 1000
    X, setXP = load({ xp = reading(900, 89) })
    X.SessionStart("login")
    X.SessionPause(true)
    setXP(reading(900, 90))
    X.OnXP()
    eq(X.SessionPaused(), false, "max level: a reading with the new level and the old XP ends the pause")
    setXP(reading(0, 90))
    X.OnXP()
    eq(X.SessionGained(), 0, "max level: and the correction after it stays out")

    clock = 1000
    X, setXP = load({ xp = reading(900, 89) })
    X.SessionStart("login")
    X.SessionPause(true)
    setXP(XP(900, 1200, 89))
    X.OnXP()
    eq(X.SessionPaused(), true, "max level: a new total with the old level keeps the pause")
    setXP(XP(0, 1200, 90, true))
    X.OnXP()
    eq(X.SessionPaused(), false, "max level: until the level reads new")
    eq(X.SessionGained(), 0, "max level: with no XP from the pause when the total comes first")

    clock = 1000
    X, setXP = load({ xp = reading(900, 89) })
    X.SessionStart("login")
    setXP(reading(0, 90))
    X.OnXP()
    eq(X.SessionGained(), 100, "max level: a session not paused still counts the rest of the level")

    clock = 1000
    X, setXP = load({ xp = reading(100, 89) })
    X.SessionStart("login")
    X.SessionPause(true)
    clock = 1100
    setXP(reading(0, 90))
    X.SessionPause(false)
    eq(X.SessionPaused(), false, "max level: Start whose own reading ended the pause ends it once")
    eq(X.SessionElapsed(), 0, "max level: with the frozen time")

    clock = 1000
    X, setXP = load({ xp = reading(100, 89) })
    X.SessionStart("login")
    X.SessionPause(true)
    clock = 1100
    setXP(reading(0, 90))
    X.ResetSession()
    eq(X.SessionPaused(), false, "max level: a reset there leaves it running")
    eq(X.SessionElapsed(), 0, "max level: at zero time")

    X = load({ xp = reading(0, 90) })
    X.SessionStart("login")
    X.SessionPause(true)
    eq(X.SessionPaused(), false, "max level: Pause does nothing there")

    local record = {}
    clock, wall = 1000, 50000
    X, setXP = load({ rec = record, xp = reading(100, 89) })
    X.SessionStart("login")
    setXP(reading(300, 89))
    clock, wall = 1100, 50100
    X.SessionPause(true)
    X.SessionSave()
    eq(record.paused, true, "max level: a pause below it is saved")

    clock, wall = 2000, 50130
    X = load({ rec = record, xp = reading(0, 90) })
    X.SessionStart("reload")
    eq(X.SessionPaused(), false, "max level: a /reload there comes back running")
    eq(X.SessionGained(), 200, "max level: with the frozen XP")
    eq(X.SessionElapsed(), 100, "max level: and the frozen time")
    clock = 2050
    eq(X.SessionElapsed(), 150, "max level: and it runs from there")

    clock, wall = 2000, 50130
    X, setXP = load({ rec = record, xp = reading(300, 90) })
    X.SessionStart("reload")
    setXP(reading(0, 90))
    X.OnXP()
    eq(X.SessionGained(), 200, "max level: a /reload there drops the correction too")

    clock = 2000
    X = load({ rec = record, settings = { xpResetOnReload = true }, xp = reading(0, 90) })
    X.SessionStart("reload")
    eq(X.SessionPaused(), false, "max level: with Reset Session on Reload on too")
    eq(X.SessionGained(), 0, "max level: at zero XP")

    local maxSave = {}
    clock, wall = 1000, 50000
    X, setXP = load({ rec = maxSave, xp = reading(100, 89) })
    X.SessionStart("login")
    X.SessionPause(true)
    setXP(reading(0, 90))
    X.SessionSave()
    eq(maxSave.paused, nil, "max level: a save there records no pause")
end

-- The level history
_G.UnitClass = function() return "Hunter", "HUNTER" end
clock = 1000
X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(nil, 100)
clock = 1200
local genBefore = X.HistoryGen()
setXP(XP(900, 1200, 11))
X.OnLevelUp(11)
setXP(XP(50, 1200, 11))
X.OnXP()
eq(X.History().splits[10], 300, "history, event first: the split")
eq(X.History().class, "HUNTER", "history: the class is stored")
check(X.HistoryGen() > genBefore, "history: the counter moves")

clock = 1000
X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(nil, 100)
clock = 1200
setXP(XP(50, 1200, 11))
X.OnXP()
eq(X.LevelTime(), nil, "history, reading first: the clock drops")
X.OnLevelUp(11)
eq(X.History().splits[10], 300, "history, reading first: the same split")
flush()

X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("reload")
setXP(XP(50, 1200, 11))
X.OnLevelUp(11)
eq(X.History(), nil, "history: a clock unknown at the level-up writes nothing")

clock = 1000
X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(nil, 100)
X.SessionListen(false)
setXP(XP(50, 1200, 11))
X.OnXP()
X.SessionListen(true)
X.OnPlayed(nil, 20)
clock = 1100
setXP(XP(10, 1400, 12))
X.OnLevelUp(12)
eq(X.History().splits[10], nil, "history: a level passed while the bar was off writes nothing")
eq(X.History().splits[11], 120, "history: the next seen level-up with a clock writes its own")

clock = 1000
X, setXP = load({ noKey = true, xp = XP(900, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(5000, 100)
setXP(XP(50, 1200, 11))
X.OnLevelUp(11)
eq(X.History(true), nil, "history: a nil character key writes nothing")

X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(nil, 100)
setXP(XP(50, 1200, 11))
X.OnLevelUp(11)
_G.UnitClass = function() return "Mage", "MAGE" end
X.OnPlayed(nil, 100)
setXP(XP(50, 1400, 12))
X.OnLevelUp(12)
eq(X.History().class, "HUNTER", "history: the class is stored once")
_G.UnitClass = nil

-- The total
clock = 1000
X, setXP = load({ xp = XP(900, 1000, 10) })
X.SessionStart("login")
X.OnPlayed(5000, 300)
eq(X.PlayedTotal(), 5000, "total: a reply keeps it")
eq(X.History().reached[10], 4700, "total: and writes the counted level's start")
clock = 1100
eq(X.PlayedTotal(), 5100, "total: it advances")
setXP(XP(50, 1200, 11))
X.OnLevelUp(11)
eq(X.History().reached[11], 5100, "total: a level-up writes the new level's start")

do
    local SECRET_TOTAL = 123456
    _G.issecretvalue = function(v) return v == SECRET_TOTAL end
    X = load({ xp = XP(900, 1000, 10) })
    X.SessionStart("login")
    X.OnPlayed(SECRET_TOTAL, 300)
    eq(X.PlayedTotal(), nil, "total: a secret one is not kept")
    eq(X.LevelTime(), 300, "total: and the time this level still seeds")
    _G.issecretvalue = nil
end

-- The asks with the card on
clock, wall, played = 1000, 50000, 0
X = load({ settings = { xpShowLevelTime = false, xpTickerEnabled = true, xpTickerShowPlayed = true },
    xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.RequestPlayed()
X.RequestPlayed()
eq(played, 1, "card ask: the Played row alone asks once after a login")
eq(chat.on, true, "card ask: a login ask follows the mute switch, off")

played = 0
X = load({ settings = { xpShowLevelTime = false, xpTickerEnabled = true, xpTickerShowPlayed = true, xpMutePlayed = true },
    xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.RequestPlayed()
eq(played, 1, "card ask: and asks with the mute switch on")
eq(chat.on, false, "card ask: a login ask follows the mute switch, on")

played = 0
X = load({ settings = { xpTickerEnabled = true, xpTickerShowPace = true }, xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.OnLevelUp(10)
X.RequestPlayed()
eq(played, 1, "card ask: a known clock with an unknown total asks")

played = 0
X = load({ settings = { xpTickerEnabled = true, xpTickerShowCurrent = true, xpMutePlayed = false }, xp = XP(600, 1000, 10) })
X.SessionStart("reload")
X.RequestPlayed()
X.RequestPlayed()
eq(played, 1, "card ask: a /reload load with a card row wanting a missing value asks once")
eq(chat.on, false, "card ask: muted, whatever the switch says")

played = 0
X = load({ xp = XP(600, 1000, 10) })
X.SessionStart("reload")
X.RequestPlayed()
eq(played, 0, "card ask: the same load with the card off does not ask")

played = 0
X = load({ rec = { savedAt = wall - 5, levelTime = 100, levelOf = 10, played = 5000, lastXP = 600, lastMax = 1000,
        lastLevel = 10, gained = 0, elapsed = 10 },
    settings = { xpTickerEnabled = true, xpTickerShowCurrent = true, xpTickerShowPlayed = true }, xp = XP(600, 1000, 10) })
X.SessionStart("reload")
X.RequestPlayed()
eq(played, 0, "card ask: a recent save holding both does not ask")

played = 0
X = load({ settings = { xpShowLevelTime = false, xpTickerEnabled = false, xpTickerShowPlayed = true }, xp = XP(600, 1000, 10) })
X.SessionStart("login")
X.RequestPlayed()
eq(played, 0, "card ask: with the card off and the level-time line off, nothing asks")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
