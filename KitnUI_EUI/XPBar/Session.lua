-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Session.lua                                ║
-- ║  Purpose: The per-character XP session, time this level,     ║
-- ║           kill samples and the /played requests.             ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
local M = X.Math

-- Seconds before a muted chat frame is given back when no reply comes.
local MUTE_FALLBACK = 5

local started = false
local loadKind
local sessionStart = 0
local gained = 0
-- Math.Track's state: the last XP reading and the level counted to.
local track = {}
-- The time this level: when it began, and the level it belongs to.
local levelStart, levelOf
local kills = {}
-- The login ask is spent; an unseen level-up wants one more.
local playedAsked, askAgain = false, false
-- nil, or the ask whose reply is awaited: "login" or "again".
local pending
-- The XP bar's events are registered, so a reply can be heard.
local listening = false
local muted = {}
local muteTimer

-- KitnUIDB.perChar[<character>].xp. Per character and outside the EUI
-- profile, so no export carries it.
local function Record(create)
    local key = ns.GetCharKey and ns.GetCharKey()
    local db = ns.db
    if not (key and db) then return nil end
    if type(db.perChar) ~= "table" then
        if not create then return nil end
        db.perChar = {}
    end
    local char = db.perChar[key]
    if type(char) ~= "table" then
        if not create then return nil end
        char = {}
        db.perChar[key] = char
    end
    if type(char.xp) ~= "table" then
        if not create then return nil end
        char.xp = {}
    end
    return char.xp
end

-- Starts the tracker from a stored reading, or empty, so that the next
-- reading seeds it.
local function Seed(x, m, level, wait)
    track.x, track.m, track.level, track.wait = nil, nil, nil, nil
    if type(x) == "number" and type(m) == "number" and type(level) == "number" then
        track.x, track.m, track.level = x, m, level
        track.wait = wait == "total" and "total" or nil
    end
end

local function AskAgain() X.RequestPlayed() end

-- upTo is the level the tracker just counted a level-up to. A seen
-- PLAYER_LEVEL_UP has already set the clock to that level. Anything else, a
-- clock of another level or no clock at all, means the level-up went by
-- unseen (the XP bar was off, or the save is from an earlier level): the
-- time this level is unknown and /played is wanted once more. Returns true
-- when the level-up was unseen.
local function Counted(upTo)
    if not upTo or (levelStart and upTo == levelOf) then return false end
    levelStart, levelOf, askAgain = nil, nil, true
    return true
end

-- Once per load, when the XP bar first runs. A fresh session counts from the
-- start of the load, which Core captured: the real login, even when the bar
-- is turned on an hour later. Its XP is then the XP since that start, so the
-- session's time and XP cover the same span. A /reload within the window of
-- its save continues the saved session instead, each time advanced by the gap, and
-- its XP adds everything since the save's own reading, so XP earned between
-- the save and the bar's first run is not lost. The time this level
-- continues from that save even with Reset Session on Reload on: that switch
-- resets the session, not the level. Anything else leaves the time this
-- level unknown. The tracker runs on from a recent save through the load's
-- start to now whichever session wins, so a level-up half reported before
-- the save counts once.
function X.SessionStart(kind)
    if started then return end
    started = true
    loadKind = kind
    local now, wall = GetTime(), time()
    local rec = Record(false)
    local reset = X.Get and X.Get("xpResetOnReload") == true
    local window = M.SESSION_RELOAD_WINDOW
    local t = X.ReadXP()
    gained, sessionStart, levelStart, levelOf = 0, now, nil, nil
    Seed()
    local load = ns.EUILoadStart
    local fromLoad = type(load) == "table" and type(load.time) == "number" and load.time <= now
    -- The window is measured to the /reload itself, the load's start, so a
    -- bar first turned on later still continues a timely save. The restored
    -- times then advance through to now.
    local reloadedAt = fromLoad and (wall - (now - load.time)) or wall
    -- time() is whole seconds; a load never starts before the save it follows.
    if rec and type(rec.savedAt) == "number" then reloadedAt = math.max(reloadedAt, rec.savedAt) end
    local recent = rec and M.ShouldContinue(kind, false, rec.savedAt, reloadedAt, window)
    local continuing = recent and M.ShouldContinue(kind, reset, rec.savedAt, reloadedAt, window)
    local gap = recent and (wall - rec.savedAt) or 0
    if recent then
        Seed(rec.lastXP, rec.lastMax, rec.lastLevel, rec.lastWait)
        if type(rec.levelTime) == "number" and type(rec.levelOf) == "number" then
            levelStart, levelOf = now - (rec.levelTime + gap), rec.levelOf
        end
    end
    local beforeLoad, upLoad = 0, nil
    if fromLoad then beforeLoad, upLoad = M.Track(track, load.xp, load.max, load.level) end
    local sinceLoad, upNow = M.Track(track, t.cur, t.max, t.level)
    Counted(upLoad)
    Counted(upNow)
    if continuing then
        gained = (type(rec.gained) == "number" and rec.gained or 0) + beforeLoad + sinceLoad
        sessionStart = now - ((type(rec.elapsed) == "number" and rec.elapsed or 0) + gap)
        if type(rec.kills) == "table" then
            for i = 1, #rec.kills do
                if type(rec.kills[i]) == "number" then M.PushKill(kills, rec.kills[i]) end
            end
        end
    elseif fromLoad then
        gained, sessionStart = sinceLoad, load.time
    end
end

-- Takes one reading first, so XP earned since the last event is in the save.
function X.SessionSave()
    if not started then return end
    local rec = Record(true)
    if not rec then return end
    X.OnXP()
    local now = GetTime()
    rec.gained = gained
    rec.lastXP, rec.lastMax, rec.lastLevel, rec.lastWait = track.x, track.m, track.level, track.wait
    rec.elapsed = now - sessionStart
    rec.savedAt = time()
    rec.levelTime = levelStart and (now - levelStart) or nil
    rec.levelOf = levelStart and levelOf or nil
    local list = {}
    for i = 1, #kills do list[i] = kills[i] end
    rec.kills = list
end

function X.SessionElapsed()
    return started and (GetTime() - sessionStart) or 0
end

function X.SessionGained() return gained end

function X.SessionStarted() return started end

function X.LevelTime()
    return levelStart and (GetTime() - levelStart) or nil
end

function X.Kills() return kills end

-- Runs on every XP, level and level-total event alike: Track counts a level
-- once whatever order the client reports it in. The ask waits a frame, so a
-- PLAYER_LEVEL_UP arriving just after its reading restarts the clock first.
-- Nothing is queued while the XP bar is off: the save that turns it off
-- leaves no work behind, and the apply that turns it back on asks.
function X.OnXP()
    if not started then return end
    local t = X.ReadXP()
    local gain, upTo = M.Track(track, t.cur, t.max, t.level)
    gained = gained + gain
    if Counted(upTo) and listening and C_Timer and C_Timer.After then C_Timer.After(0, AskAgain) end
end

-- newLevel is PLAYER_LEVEL_UP's own first argument: UnitLevel can still read
-- the old level inside the event.
function X.OnLevelUp(newLevel)
    if type(newLevel) ~= "number" or (issecretvalue and issecretvalue(newLevel)) then
        newLevel = X.ReadXP().level
    end
    levelStart, levelOf, askAgain = GetTime(), newLevel, false
    X.OnXP()
end

function X.OnKill(xpGain)
    M.PushKill(kills, xpGain)
end

-- Zeroes the session's XP and time now. The tracker takes this reading and
-- keeps its state, so the new session starts from its running state. The
-- time this level and the kill samples stay. Before the session has started
-- there is nothing to reset, and the session that starts later still counts
-- from the login.
function X.ResetSession()
    if not started then return end
    X.OnXP()
    gained, sessionStart = 0, GetTime()
end

-- Bar.lua calls this as the XP bar's events come and go. A request whose
-- reply can no longer be heard stops waiting: an ask again is wanted once
-- more, and a spent login ask stays spent (one per login).
function X.SessionListen(on)
    listening = on and true or false
    if listening or not pending then return end
    if pending == "again" then askAgain = true end
    pending = nil
end

local function Unmute()
    if muteTimer then
        muteTimer:Cancel()
        muteTimer = nil
    end
    for i = #muted, 1, -1 do
        local frame = muted[i]
        muted[i] = nil
        if frame.RegisterEvent then frame:RegisterEvent("TIME_PLAYED_MSG") end
    end
end

-- The chat frames print TIME_PLAYED_MSG in their own OnEvent before any
-- message filter runs, so the only quiet way is to take the event off them
-- for the one reply.
local function Mute()
    if muteTimer then
        muteTimer:Cancel()
        muteTimer = nil
    end
    for i = 1, tonumber(NUM_CHAT_WINDOWS) or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
            frame:UnregisterEvent("TIME_PLAYED_MSG")
            muted[#muted + 1] = frame
        end
    end
    if #muted > 0 and C_Timer and C_Timer.NewTimer then
        muteTimer = C_Timer.NewTimer(MUTE_FALLBACK, Unmute)
    end
end

-- Two asks. The login ask runs at most once, in a load that began with a
-- login, muted as Mute /played in Chat says. The ask again runs once each
-- time an unseen level-up made the time this level unknown, in any load,
-- and always muted: the player did not type it. When both are due, the ask
-- again wins and its one request spends the login ask too. Either runs only
-- while the time this level is unknown, no request waits for its reply, and
-- the line is drawn: the XP bar is on, its switch is on, and the player is
-- below max level with XP gain on. A request that raises never reached the
-- server, so nothing is spent. Otherwise a /reload's time this level comes
-- from the saved session, or reads "--" until a level-up or a typed /played.
function X.RequestPlayed()
    if not (started and listening) or levelStart or pending then return end
    local again = askAgain
    local login = loadKind == "login" and not playedAsked
    if not (again or login) then return end
    if X.Get("xpShowLevelTime") ~= true or type(RequestTimePlayed) ~= "function" then return end
    local t = X.ReadXP()
    if t.atMax or t.xpOff then return end
    local spent = playedAsked
    playedAsked, askAgain, pending = true, false, again and "again" or "login"
    if again or X.Get("xpMutePlayed") == true then Mute() end
    if not pcall(RequestTimePlayed) then
        playedAsked, askAgain, pending = spent, again, nil
        Unmute()
    end
end

-- Any reply while the bar is on ends the wait and seeds the time this level,
-- for the level the tracker has counted to once it has this reading too;
-- chat comes back on the next frame.
function X.OnPlayed(_, thisLevel)
    pending = nil
    if type(thisLevel) == "number" and not (issecretvalue and issecretvalue(thisLevel)) then
        X.OnXP()
        levelStart, levelOf, askAgain = GetTime() - thisLevel, track.level or X.ReadXP().level, false
    end
    if #muted > 0 and C_Timer and C_Timer.After then C_Timer.After(0, Unmute) end
end

function X.SessionStop()
    Unmute()
end
