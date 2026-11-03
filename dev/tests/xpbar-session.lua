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
_G.NUM_CHAT_WINDOWS = 1

local function XP(cur, max, level, atMax)
    return { cur = cur, max = max, level = level, atMax = atMax or false, xpOff = false }
end

-- A fresh load of the shipped files. Returns the module and a setter for
-- what ReadXP reports next. opts.barOff reads as the XP bar being off.
local function load(opts)
    later, chat.on = {}, true
    local ns = { db = { perChar = {} }, EUILoadStart = opts.start }
    ns.GetCharKey = function() return "Tester-Realm" end
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

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
