-- ╔══════════════════════════════════════════════════════════════╗
-- ║  xpbar-ticker.lua                                            ║
-- ║  Purpose: Gate for the XP ticker card: its texts, history    ║
-- ║           and peers, its timer, what shows it, and its cost  ║
-- ║           per tick. Loads the SHIPPED code, never a copy.    ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/xpbar-ticker.lua

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
-- Recording stubs
---------------------------------------------------------------------------------

local NOOP = function() end
local methods = {}
local framesMade, setTexts = 0, 0
local tickers = {}
local tipLines = 0

-- A capitalized method is a no-op unless listed below; a data field reads nil.
local function Obj(kind)
    return setmetatable({ kind = kind, shown = true, scripts = {} }, {
        __index = function(_, key)
            if methods[key] then return methods[key] end
            if type(key) == "string" and key:match("^%u") then return NOOP end
            return nil
        end,
    })
end

methods.SetScript = function(self, name, fn) self.scripts[name] = fn end
-- As the client does, a change of shown state runs the script.
methods.Show = function(self)
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
methods.Hide = function(self)
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
methods.SetShown = function(self, v)
    if v then self:Show() else self:Hide() end
end
methods.IsShown = function(self) return self.shown end
methods.IsMouseOver = function(self) return self.over end
methods.CreateTexture = function() return Obj("Texture") end
methods.CreateFontString = function() return Obj("FontString") end
-- As the client does, a FontString with no font refuses text.
methods.SetFont = function(self)
    self.fontSet = true
    return true
end
methods.SetText = function(self, v)
    if not self.fontSet then error("Font not set") end
    self.text = v
    setTexts = setTexts + 1
end
methods.SetMouseClickEnabled = function(self, on) self.click = on end
methods.SetMouseMotionEnabled = function(self, on) self.motion = on end
methods.SetTextColor = function(self, r, g, b) self.colorR, self.colorG, self.colorB = r, g, b end

_G.CreateFrame = function(kind)
    framesMade = framesMade + 1
    return Obj(kind)
end
_G.UIParent = Obj("Frame")
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.hooksecurefunc = NOOP
_G.GameTooltip = Obj("GameTooltip")
local tipLeft, tipRight = {}, {}
_G.GameTooltip.AddDoubleLine = function(_, left, right)
    tipLines = tipLines + 1
    tipLeft[tipLines], tipRight[tipLines] = left, right
end
_G.GameTooltip.IsOwned = function() return true end
_G.UnitClass = function() return "Hunter", "HUNTER" end

local clock, wall = 1000, 50000
_G.GetTime = function() return clock end
_G.time = function() return wall end
_G.C_Timer = {
    After = NOOP,
    NewTimer = function() return { Cancel = NOOP } end,
    NewTicker = function(_, fn)
        local t = { fn = fn, canceled = false }
        function t.Cancel(self) self.canceled = true end
        tickers[#tickers + 1] = t
        return t
    end,
}

local mouseover = 0
local EUI = {
    MakeUnlockElement = function(opts) return opts end,
    RegisterMouseoverTarget = function() mouseover = mouseover + 1 end,
    UnregisterMouseoverTarget = function() mouseover = mouseover - 1 end,
}
_G.EllesmereUI = EUI

local DEFAULTS = {
    xpTickerEnabled = true, xpTickerVisibility = "always", xpTickerHideResting = true, xpTickerShowCurrent = true,
    xpTickerHistoryRows = 5, xpTickerShowPlayed = true, xpTickerShowPace = false, xpTickerFontSize = 12,
    xpTickerBackground = "card",
}
local reading

local function view(key) return DEFAULTS[key] end

local function fresh(opts)
    opts = opts or {}
    local settings = opts.settings or {}
    framesMade = 0
    reading = { level = 59, cur = 94410, max = 209800, atMax = false, xpOff = false, resting = false }
    local ns = { db = opts.db or { perChar = {} } }
    ns.GetCharKey = function() return not opts.noKey and "Me-Realm" or nil end
    function ns.EUIPlain(v)
        if v ~= nil and _G.issecretvalue and _G.issecretvalue(v) then return nil end
        return v
    end
    local function run(file)
        local chunk, err = loadfile(file)
        if not chunk then
            print("FAIL  could not load " .. file .. ": " .. tostring(err))
            os.exit(1)
        end
        chunk("KitnUI_EUI", ns)
    end
    run("KitnUI_EUI/XPBar/Math.lua")
    local X = ns.XPBar
    X.Get = function(key)
        local v = settings[key]
        if v == nil then v = DEFAULTS[key] end
        return v
    end
    X.Set = function(key, v) settings[key] = v end
    X.ReadXP = function() return reading end
    X.XPEnabled = function() return settings.xpEnabled ~= false end
    X.EvalVisibility = function(mode)
        if mode == "never" then return false end
        if mode == "mouseover" then return "mouseover" end
        return true
    end
    X.PlaceFrame = function() X.placed = (X.placed or 0) + 1 end
    X.FontPath = function() return "font" end
    X.OutlineFlag = function() return "" end
    X.SetFont = function(fs, font, size, flags) fs:SetFont(font, size, flags) end
    X.AccentColor = function() return 1, 0, 0 end
    X.Apply = function() X.applied = (X.applied or 0) + 1 end
    run("KitnUI_EUI/XPBar/Session.lua")
    run("KitnUI_EUI/XPBar/Ticker.lua")
    X.SessionListen(true)
    return X, settings
end

local function rawRecord()
    return { level = 59, cur = 94410, max = 209800, levelTime = 1200, elapsed = 3600, gained = 90000 }
end

-- Brings the live card up from a raw record, as Bar.lua's funnel does.
local function showCard(X, raw)
    X.TickerRefresh(raw)
    X.TickerVisibility()
    return X.TickerElement(EUI).getFrame()
end

---------------------------------------------------------------------------------
-- The texts
---------------------------------------------------------------------------------

do
    local X = fresh()
    local out = {}
    X.TickerView(rawRecord(), view, out)
    eq(out.rate, "90.0K xp/hr", "view: XP per hour")
    eq(out.ding, "Ding 1h 16m", "view: time to level")
    eq(out.urgent, false, "view: over 10 minutes is not urgent")
    eq(out.dingTone, nil, "view: and Ding is plain")
    eq(out.n, 2, "view: the current level and Played, with nothing else known")
    eq(out.left[1], "Level 59", "view: the current level")
    eq(out.right[1], "20:00  45%", "view: with its clock and percent")
    eq(out.right[2], "--", "view: an unknown total reads --")

    local r = rawRecord()
    r.trend = "up"
    X.TickerView(r, view, out)
    eq(out.arrow, "up", "view: the arrow")

    r.cur = 209000
    X.TickerView(r, view, out)
    eq(out.urgent, true, "view: under 10 minutes is urgent")
    eq(out.dingTone, "urgent", "view: and Ding takes the tint")

    r = rawRecord()
    r.trend, r.paused = "up", true
    X.TickerView(r, view, out)
    eq(out.rate, "90.0K xp/hr", "view, paused: the rate holds")
    eq(out.ding, "Paused", "view, paused: the right slot says so")
    eq(out.dingTone, "dim", "view, paused: dimmed")
    eq(out.arrow, nil, "view, paused: no arrow")
    eq(out.pauseText, "Start", "view, paused: the button reads Start")

    r = rawRecord()
    r.gained, r.trend = 0, "up"
    X.TickerView(r, view, out)
    eq(out.rate, "no XP yet", "view, no XP: the left says so")
    eq(out.ding, "Ding --", "view, no XP: no time to level")
    eq(out.dingTone, "dim", "view, no XP: dimmed")
    eq(out.rateDim, true, "view, no XP: and the rate too")
    eq(out.arrow, nil, "view, no XP: no arrow")
    eq(out.pauseText, "Pause", "view: the button reads Pause")

    r = rawRecord()
    r.levelTime = nil
    X.TickerView(r, view, out)
    eq(out.right[1], "--  45%", "view: an unknown clock reads --")

    local X2, set = fresh()
    set.xpTickerShowCurrent, set.xpTickerShowPlayed = false, false
    X2.TickerView(rawRecord(), X2.Get, out)
    eq(out.n, 0, "view: every row switched off")
    set.xpTickerShowPace = true
    r = rawRecord()
    r.pace = 3600
    X2.TickerView(r, X2.Get, out)
    eq(out.right[1], "1h 0m ahead", "view: the Pace row")
    eq(out.keys[1], "tkPace", "view: names its setting")
end

---------------------------------------------------------------------------------
-- History rows
---------------------------------------------------------------------------------

do
    local db = { perChar = { ["Me-Realm"] = { xpHistory = { splits = { [58] = 100, [56] = 200, [55] = 300 }, reached = {} } } } }
    local X = fresh({ db = db, settings = { xpTickerHistoryRows = 2 } })
    X.SessionStart("login")
    local raw = rawRecord()
    local card = showCard(X, raw)
    eq(card.left[1].text, "Level 59", "history: the current level first")
    eq(card.left[2].text, "Level 58", "history: the newest completed level next")
    eq(card.right[2].text, "1:40", "history: with its time")
    eq(card.left[3].text, "Level 56", "history: a missing level is skipped")
    eq(card.left[4].text, "Played", "history: capped by the slider")
    eq(raw.hist.n, 2, "history: two rows kept")
    eq(card.left[5].shown, false, "history: rows past the last hide")
end

---------------------------------------------------------------------------------
-- Peers
---------------------------------------------------------------------------------

do
    local perChar = {
        ["Me-Realm"] = { xpHistory = { reached = { [59] = 1, [60] = 2 } } },
        ["Near-Realm"] = { xpHistory = { class = "MAGE", reached = { [59] = 1000, [60] = 2000 } } },
        ["Far-Realm"] = { xpHistory = { class = "ROGUE", reached = { [59] = 1000, [60] = 1300 } } },
        ["OneEnd-Realm"] = { xpHistory = { reached = { [59] = 1000 } } },
        ["Odd-Realm"] = 5,
        ["Odder-Realm"] = { xpHistory = 7 },
        ["Oddest-Realm"] = { xpHistory = { reached = { [59] = "x", [60] = 2 } } },
    }
    local walks = 0
    local realPairs = pairs
    _G.pairs = function(t)
        if t == perChar then walks = walks + 1 end
        return realPairs(t)
    end
    local X = fresh({ db = { perChar = perChar }, settings = { xpTickerShowPace = true } })
    X.SessionStart("login")
    X.OnPlayed(1400)
    local raw = rawRecord()
    raw.cur = 104900
    local card = showCard(X, raw)
    eq(card.left[3].text, "Pace", "peers: the Pace row is last")
    eq(card.right[3].text, "1m ahead", "peers: it shows the closest gap")
    eq(walks, 1, "peers: one walk when the row first shows")
    local tick = tickers[#tickers].fn
    tick()
    tick()
    eq(walks, 1, "peers: no walk on a tick")
    raw.level = 60
    X.TickerRefresh(raw)
    eq(walks, 2, "peers: one walk when the level changes")
    eq(card.right[3].shown, false, "peers: with no character at both ends of that level, Pace hides")
    raw.level = 59
    X.TickerRefresh(raw)
    eq(walks, 3, "peers: and one coming back")

    tipLines = 0
    check(card.paceHover.shown, "peers: the Pace row has its hover")
    card.paceHover.scripts.OnEnter(card.paceHover)
    eq(tipLines, 3, "peers: the tooltip lists the two that count, and the player")
    card.paceHover.scripts.OnLeave(card.paceHover)

    for i = 1, 12 do
        perChar["More" .. i .. "-Realm"] = { xpHistory = { reached = { [59] = 1000 + i, [60] = 2000 } } }
    end
    raw.level = 60
    X.TickerRefresh(raw)
    raw.level = 59
    X.TickerRefresh(raw)
    tipLines = 0
    card.paceHover.scripts.OnEnter(card.paceHover)
    eq(tipLines, 8, "peers: the tooltip lists up to 8")
    _G.pairs = realPairs
end

---------------------------------------------------------------------------------
-- The timer and a tick's cost
---------------------------------------------------------------------------------

do
    local X = fresh()
    X.SessionStart("login")
    X.OnPlayed(5000, 300)
    local raw = rawRecord()
    local count = #tickers
    local card = showCard(X, raw)
    eq(#tickers, count + 1, "timer: one while on screen")
    local timer = tickers[#tickers]
    local tick = timer.fn
    tick()
    tick()
    local texts = setTexts
    for _ = 1, 5 do tick() end
    eq(setTexts, texts, "tick: no SetText for an unchanged text")

    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 200 do tick() end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    check(grown < 1, "tick: makes no table", grown)

    clock = clock + 1
    tick()
    clock = clock - 1
    check(setTexts > texts, "tick: a text that changed is set")

    card:Hide()
    eq(timer.canceled, true, "timer: a Hide cancels it, as the mouseover service's does")
    card:Show()
    eq(#tickers, count + 2, "timer: a Show starts it again")
    X.TickerStop()
    eq(tickers[#tickers].canceled, true, "stop: cancels it")
    eq(card.shown, false, "stop: and hides")
end

---------------------------------------------------------------------------------
-- What shows the card
---------------------------------------------------------------------------------

do
    local X, set = fresh({ settings = { xpTickerEnabled = false } })
    X.TickerVisibility()
    eq(framesMade, 0, "off: no frame")
    eq(X.TickerElement(EUI).getFrame(), nil, "off: its Unlock element creates none")
    eq(X.TickerElement(EUI).isHidden(), true, "off: and is hidden")
    set.xpTickerEnabled = true
    local card = showCard(X, rawRecord())
    check(card ~= nil, "on: the card exists")
    eq(card.shown, true, "on: and shows")
    eq(card.click, false, "mouse: clicks pass through")
    eq(card.motion, true, "mouse: hovering reaches it")
    eq(X.TickerElement(EUI).isHidden(), false, "on: its Unlock element is not hidden")

    local function shownWhen(key, value, field)
        local t = field and reading or set
        local old = t[key]
        t[key] = value
        X.TickerVisibility()
        local shown = card.shown
        t[key] = old
        X.TickerVisibility()
        return shown
    end
    eq(shownWhen("atMax", true, true), false, "shows: not at max level")
    eq(shownWhen("xpOff", true, true), false, "shows: not with XP gain off")
    eq(shownWhen("resting", true, true), false, "shows: not while resting, with the switch")
    eq(shownWhen("xpTickerVisibility", "never"), false, "shows: not under Never")
    eq(shownWhen("xpEnabled", false), false, "shows: not with the XP bar off")
    set.xpTickerHideResting = false
    eq(shownWhen("resting", true, true), true, "shows: while resting, with the switch off")
    eq(card.shown, true, "shows: back on")

    local before = mouseover
    set.xpTickerVisibility = "mouseover"
    X.TickerVisibility()
    eq(mouseover, before + 1, "mouseover: joins the service")
    X.TickerVisibility()
    eq(mouseover, before + 1, "mouseover: once")
    set.xpTickerVisibility = "always"
    X.TickerVisibility()
    eq(mouseover, before, "mouseover: and leaves it")

    local element = X.TickerElement(EUI)
    eq(element.key, "KitnUI_XPTicker", "unlock: its key")
    eq(element.label, "KitnUI XP Ticker", "unlock: its label")
    eq(element.noResize, true, "unlock: no resize controls")
    eq(element.order, 5, "unlock: after the bars")
    local w, h = element.getSize()
    eq(w, card.kuiW, "unlock: its width")
    eq(h, card.kuiH, "unlock: its height")
    local placed = X.placed
    element.savePos(nil, "LEFT", "LEFT", 7, 8)
    eq(set.xpTickerPos and set.xpTickerPos.x, 7, "unlock: a move is saved")
    check(X.placed > placed, "unlock: and placed")
    eq(element.loadPos().y, 8, "unlock: and read back")
    element.clearPos()
    eq(set.xpTickerPos, nil, "unlock: and cleared")

    -- A spec layout banks "never moved" and gets it back.
    local spotNever = element.loadRawPos()
    eq(spotNever.neverMoved, true, "layout: it hears the ticker never moved")
    element.savePos(nil, "LEFT", "LEFT", 7, 8)
    local spotMoved = element.loadRawPos()
    eq(spotMoved.x, 7, "layout: it hears its spot")
    placed = X.placed
    element.saveRawPos(nil, spotNever)
    eq(set.xpTickerPos, nil, "layout: never moved clears the spot")
    check(X.placed > placed, "layout: and places it")
    element.saveRawPos(nil, spotMoved)
    eq(set.xpTickerPos and set.xpTickerPos.x, 7, "layout: and its spot comes back")
    element.clearPos()

    -- A drag lives only on the frame until the save, so a session's visibility run
    -- leaves a placed card alone and places one that never was.
    X.UnlockActive = true
    placed = X.placed
    X.TickerVisibility()
    eq(X.placed, placed, "unlock: a session's visibility run leaves it where it is")
    element.applyPos()
    eq(X.placed, placed, "unlock: an apply leaves it where it is")
    card.kuiPlaced = nil
    element.applyPos()
    check(X.placed > placed, "unlock: an apply places a card never placed")
    placed = X.placed
    card.kuiPlaced = nil
    X.TickerVisibility()
    check(X.placed > placed, "unlock: a card never placed is placed")
    X.UnlockActive = nil
    placed = X.placed
    X.TickerVisibility()
    check(X.placed > placed, "unlock: and after the session every run places again")
    X.TickerStop()
end

---------------------------------------------------------------------------------
-- Pause with its Start gone, and the card's buttons
---------------------------------------------------------------------------------

do
    local X, set = fresh()
    X.SessionStart("login")
    X.SessionPause(true)
    X.TickerApply()
    eq(X.SessionPaused(), true, "no-Start rule: the card on keeps the pause")
    set.xpEnabled = false
    X.TickerApply()
    eq(X.SessionPaused(), true, "no-Start rule: the XP bar off keeps it")
    set.xpEnabled = nil
    set.xpTickerEnabled = false
    X.TickerApply()
    eq(X.SessionPaused(), false, "no-Start rule: the switch off ends it")
    set.xpTickerEnabled = nil
    X.SessionPause(true)
    set.xpTickerVisibility = "never"
    X.TickerApply()
    eq(X.SessionPaused(), false, "no-Start rule: Never ends it")
    set.xpTickerVisibility = nil

    local card = showCard(X, rawRecord())
    eq(card.pauseBtn.shown, false, "hover: the buttons wait")
    card.scripts.OnEnter(card)
    eq(card.pauseBtn.shown, true, "hover: Pause shows")
    eq(card.resetBtn.shown, true, "hover: and Reset")
    card.over = true
    card.scripts.OnLeave(card)
    eq(card.pauseBtn.shown, true, "hover: moving onto a button keeps them")
    card.over = false
    card.pauseBtn.scripts.OnLeave(card.pauseBtn)
    eq(card.pauseBtn.shown, false, "hover: leaving the card hides them")
    card.scripts.OnEnter(card)
    local SECRET = {}
    _G.issecretvalue = function(v) return v == SECRET end
    card.over = SECRET
    card.scripts.OnLeave(card)
    eq(card.pauseBtn.shown, false, "hover: a secret answer counts as not hovered")
    _G.issecretvalue = nil

    local applied = X.applied or 0
    card.pauseBtn.scripts.OnClick(card.pauseBtn)
    eq(X.SessionPaused(), true, "buttons: Pause pauses")
    eq(X.applied, applied + 1, "buttons: and applies")
    card.pauseBtn.scripts.OnClick(card.pauseBtn)
    eq(X.SessionPaused(), false, "buttons: Start resumes")
    card.resetBtn.scripts.OnClick(card.resetBtn)
    eq(X.SessionGained(), 0, "buttons: Reset zeroes the session")
    eq(X.applied, applied + 3, "buttons: and applies")

    card.scripts.OnEnter(card)
    card:Hide()
    eq(card.pauseBtn.shown, false, "hover: the buttons stop with the card")
    X.TickerStop()
end

---------------------------------------------------------------------------------
-- The trend across a hide and a reset
---------------------------------------------------------------------------------

do
    local X = fresh()
    X.SessionStart("login")
    local raw = rawRecord()
    local card = showCard(X, raw)
    -- Time and XP pass on the session, which is what the trend reads.
    local function pass(seconds, xp)
        clock = clock + seconds
        reading.cur = reading.cur + xp
        X.OnXP()
        X.TickerRefresh(raw)
    end
    local function twoWindows()
        X.ResetSession()
        pass(0, 0)
        pass(180, 1000)
        pass(180, 2000)
    end

    twoWindows()
    eq(raw.trend, "up", "trend: a faster second window points up")

    card:Hide()
    pass(10, 100)
    card:Show()
    eq(raw.trend, nil, "trend: a hide starts it over, however short")
    pass(180, 1000)
    eq(raw.trend, nil, "trend: and the first window after it sets none")
    pass(180, 2000)
    eq(raw.trend, "up", "trend: the next compares two windows the card saw")

    twoWindows()
    pass(20, 100)
    card:Hide()
    pass(120, 100)
    card:Show()
    pass(40, 2000)
    eq(raw.trend, nil, "trend: a window with a hide in it, at the time it would have closed, is not compared")

    twoWindows()
    card:Hide()
    X.ResetSession()
    pass(500, 9000)
    card:Show()
    eq(raw.trend, nil, "trend: a reset while hidden starts it over, though both numbers passed the kept ones")

    twoWindows()
    X.ResetSession()
    pass(1, 10)
    eq(raw.trend, nil, "trend: a reset on screen starts it over too")

    twoWindows()
    pass(600, 3000)
    eq(raw.trend, nil, "trend: a window closing too late, with the card on screen, is dropped")
    pass(180, 1000)
    eq(raw.trend, nil, "trend: and the first window after it sets none")
    pass(180, 2000)
    eq(raw.trend, "up", "trend: the next compares the two after it")
    X.TickerStop()
end

---------------------------------------------------------------------------------
-- A card drawn from a view
---------------------------------------------------------------------------------

do
    local X = fresh()
    local count = #tickers
    local card = X.NewCard(_G.UIParent)
    local out = {}
    local r = rawRecord()
    r.trend = "up"
    X.TickerView(r, view, out)
    X.DrawCard(card, view, out)
    eq(card.top.text, "90.0K xp/hr", "draw: the top line's left")
    eq(card.topR.text, "Ding 1h 16m", "draw: and right")
    eq(card.arrow.shown, true, "draw: the arrow")
    check(card.kuiW == X.Math.TickerWidth(12), "draw: the width follows the font size")
    local h = card.kuiH
    r.trend = nil
    r.played = 100
    r.pace = 100
    X.TickerView(r, function(key) if key == "xpTickerShowPace" then return true end return view(key) end, out)
    X.DrawCard(card, view, out)
    eq(card.arrow.shown, false, "draw: the arrow goes with the trend")
    check(card.kuiH > h, "draw: a row more makes the card taller")
    eq(card.paceHover.shown, false, "draw: only the live card has a Pace hover")
    eq(#tickers, count, "draw: starts no timer")
end

---------------------------------------------------------------------------------
-- A card that is on but not showing
---------------------------------------------------------------------------------

do
    local X = fresh({ settings = { xpTickerVisibility = "mouseover" } })
    X.SessionStart("login")
    local before = mouseover
    local raw = rawRecord()
    local card = showCard(X, raw)
    eq(card.shown, false, "not showing: a card on Mouseover waits for the cursor")
    eq(mouseover, before + 1, "not showing: having joined the service")
    check(card.kuiW ~= nil, "not showing: it has a width for the service to read")
    check(card.kuiH ~= nil, "not showing: and a height")

    clock = clock + 180
    reading.cur = reading.cur + 1000
    X.OnXP()
    X.TickerRefresh(raw)
    X.TickerApply()
    X.TickerVisibility()
    eq(raw.trend, nil, "not showing: a draw sets no arrow")
    card:Show()
    clock = clock + 180
    reading.cur = reading.cur + 5000
    X.OnXP()
    X.TickerRefresh(raw)
    eq(raw.trend, nil, "not showing: a draw starts no window, so the first after the show sets none")
    X.TickerStop()
end

do
    local X, set = fresh()
    X.SessionStart("login")
    reading.resting = true
    local card = showCard(X, rawRecord())
    check(card ~= nil, "not showing: a card held back by resting has a frame, for Unlock Mode")
    eq(X.TickerElement(EUI).isHidden(), false, "not showing: and its element is not hidden")
    eq(card and card.shown, false, "not showing: it stays hidden")
    check(card and card.kuiW ~= nil and card.kuiH ~= nil, "not showing: with its size")
    reading.resting = false
    X.TickerVisibility()
    eq(card and card.shown, true, "not showing: it shows when resting ends")

    set.xpEnabled = false
    X.TickerApply()
    X.TickerVisibility()
    eq(card and card.dirty, true, "not showing: the XP bar off draws nothing on a frame that exists")
    X.TickerStop()
end

do
    local X = fresh({ settings = { xpEnabled = false } })
    X.TickerVisibility()
    eq(framesMade, 0, "not showing: the XP bar off makes no frame")
    eq(X.TickerElement(EUI).getFrame(), nil, "not showing: and its element creates none")
end

---------------------------------------------------------------------------------
-- A show reads the session
---------------------------------------------------------------------------------

do
    local X = fresh()
    X.SessionStart("login")
    local raw = rawRecord()
    local card = showCard(X, raw)
    card:Hide()
    raw.elapsed, raw.gained = 1, 1
    X.SessionPause(true)
    card:Show()
    eq(raw.elapsed, X.SessionElapsed(), "a show: the session's time is current")
    eq(raw.gained, X.SessionGained(), "a show: and its XP")
    eq(raw.paused, true, "a show: and its pause")
    X.TickerStop()
end

---------------------------------------------------------------------------------
-- A new accent
---------------------------------------------------------------------------------

do
    local X = fresh()
    X.SessionStart("login")
    local raw = rawRecord()
    local card = showCard(X, raw)
    raw.gained, raw.elapsed, raw.cur = 90000, 3600, 209000
    X.TickerRefresh(raw)
    eq(card.topR.colorG, select(2, X.Math.AccentText(1, 0, 0, 0.05 * 0.85 + (1 - 0.85))), "accent: an urgent Ding takes the accent's text tint")
    X.AccentColor = function() return 0, 1, 0 end
    X.TickerAccent()
    eq(card.topR.colorG, 1, "accent: and follows a new one")
    card:Hide()
    X.TickerAccent()
    eq(card.dirty, true, "accent: a hidden card reads it at its next show")
    X.TickerStop()
end

---------------------------------------------------------------------------------
-- No character key
---------------------------------------------------------------------------------

do
    local perChar = { ["Near-Realm"] = { xpHistory = { reached = { [59] = 1000, [60] = 2000 } } } }
    local X = fresh({ noKey = true, db = { perChar = perChar }, settings = { xpTickerShowPace = true } })
    X.SessionStart("login")
    X.OnPlayed(1400)
    local card = showCard(X, rawRecord())
    tipLines = 0
    card.paceHover.scripts.OnEnter(card.paceHover)
    eq(tipLines, 1, "no key: the tooltip has no line without a name")
    X.TickerStop()
end

---------------------------------------------------------------------------------
-- The Pace tooltip's order and wording
---------------------------------------------------------------------------------

do
    local perChar = {
        ["Near-Realm"] = { xpHistory = { reached = { [59] = 1000, [60] = 2000 } } },
        ["Far-Realm"] = { xpHistory = { reached = { [59] = 1000, [60] = 1300 } } },
        ["Tied-Realm"] = { xpHistory = { reached = { [59] = 1400, [60] = 1400 } } },
    }
    local X = fresh({ db = { perChar = perChar }, settings = { xpTickerShowPace = true } })
    X.SessionStart("login")
    X.OnPlayed(1400)
    local raw = rawRecord()
    raw.cur = 104900
    local card = showCard(X, raw)
    tipLines = 0
    card.paceHover.scripts.OnEnter(card.paceHover)
    eq(table.concat(tipLeft, ",", 1, tipLines), "Far,Tied,Me,Near", "pace tooltip: fastest on top, a tie above you")
    eq(table.concat(tipRight, "|", 1, tipLines), "4m ahead|< 1m ahead|you|1m behind",
        "pace tooltip: each line from that character's view")
    X.TickerStop()
end

---------------------------------------------------------------------------------
-- Negative session XP
---------------------------------------------------------------------------------

do
    local X = fresh()
    local M = X.Math
    local out = {}
    local r = rawRecord()
    r.gained = -900
    X.TickerView(r, view, out)
    eq(out.rate, "no XP yet", "negative session XP: the card's rate reads no XP yet")
    eq(out.ding, "Ding --", "negative session XP: and its time to level --")
    eq(M.Rate(-900, 60, 100), nil, "negative session XP: no rate")
    eq(M.Number(-1900, "short"), "-1900", "negative session XP: the short number")
    eq(M.Number(-1900, "plain"), "-1900", "negative session XP: the plain number")
    eq(M.Number(-1900, "full"), "-1,900", "negative session XP: the full number")
    local state = {}
    eq(M.Trend(state, -900, 0, 180), nil, "negative session XP: the trend seeds")
    eq(M.Trend(state, -800, 180, 180), nil, "negative session XP: and sets no arrow from one window")
    eq(M.Trend(state, -700, 360, 180), nil, "negative session XP: nor from a steady rate")
end

---------------------------------------------------------------------------------
-- Gap bars, the line, the footer and Pace
---------------------------------------------------------------------------------

local GRID = { xpTickerGapBars = true, xpTickerShowLine = true, xpTickerShowPace = true }

local function viewWith(over)
    return function(key)
        local v = over[key]
        if v == nil then v = DEFAULTS[key] end
        return v
    end
end

local function sampleHist(X, acct, curAcct, current)
    local h = { n = 3, levels = { 58, 57, 56 }, texts = { "1:12:05", "58:40", "49:12" }, secs = { 4325, 3520, 2952 },
        acct = acct, curAcct = curAcct, ref = {}, src = {}, share = {}, gap = {}, star = {}, gapText = {} }
    X.SummarizeHistory(h, current ~= false)
    return h
end

do
    local X = fresh()
    local out = {}
    local r = rawRecord()
    r.hist = sampleHist(X, { 3900, 3900 }, 4800)
    r.pace = -120
    X.TickerView(r, viewWith(GRID), out)
    eq(out.kind[1], "current", "grid: the current level first")
    eq(out.right[1], "20:00", "grid: its clock")
    eq(out.extra[1], "45%", "grid: and its percent apart")
    check(type(out.share[1]) == "number" and out.share[1] > 0, "grid: its projected finish runs slower than the other characters'", out.share[1])
    eq(out.extra[2], "+7:05", "grid: a slower level")
    eq(out.cls[2], "slow", "grid: in amber")
    eq(out.extra[3], "-6:20", "grid: a faster level")
    eq(out.cls[3], "fast", "grid: in teal")
    eq(out.extra[4], "-9:28|cffa8a8a8*|r", "grid: a level on the recent median carries the star")
    eq(out.extraKey[2], "tkGapBars", "grid: a gap leads to Gap Bars")
    eq(out.kind[5], "footer", "grid: the footer after the levels")
    eq(out.left[5], "Played", "grid: with Played")
    eq(out.extra[5], "vs account", "grid: and the main source")
    eq(out.kind[6], "legend", "grid: the legend on its own row")
    eq(out.extra[6], "* recent median 58:40", "grid: naming the other source")
    eq(out.kind[7], "pace", "grid: Pace last")
    eq(out.cls[7], "slow", "grid: behind reads amber")
    eq(out.levelRows, 4, "grid: four level rows")
    eq(out.n, 7, "grid: seven rows in all")

    r.paused = true
    X.TickerView(r, viewWith(GRID), out)
    eq(out.share[1], nil, "grid, paused: no projected finish")
    r.paused = nil

    r.hist = sampleHist(X, {}, nil)
    X.TickerView(r, viewWith(GRID), out)
    eq(out.extra[2], "+13:25", "grid: a gap to the recent median")
    eq(out.extra[3], "even", "grid: within 5% reads even")
    eq(out.cls[3], "even", "grid: in dim gray")
    eq(out.extra[5], "median 58:40", "grid: every level on the recent median names it in the footer")
    eq(out.kind[6], "pace", "grid: with no legend")

    r.pace = nil
    X.TickerView(r, viewWith(GRID), out)
    eq(out.n, 5, "grid: Pace with no value is left out")

    X.TickerView(r, viewWith({ xpTickerGapBars = true, xpTickerShowPlayed = false }), out)
    eq(out.left[5], "", "grid, Played off: the footer keeps only its source")
    eq(out.extra[5], "median 58:40", "grid, Played off: which it still names")

    r.hist = sampleHist(X, { 3900, 3900 }, 4800)
    X.TickerView(r, viewWith({ xpTickerShowPace = true }), out)
    eq(out.extra[2], nil, "bars off: no gap")
    eq(out.share[2], nil, "bars off: no bar")
    eq(out.right[1], "20:00  45%", "bars off: the current level as before")
    eq(out.kind[5], "footer", "bars off: the footer")
    eq(out.extra[5], nil, "bars off: names no source")
    eq(out.n, 5, "bars off: and no legend")

    r.hist = sampleHist(X, {}, 4800)
    X.TickerView(r, viewWith(GRID), out)
    eq(out.extra[1], "45%|cffa8a8a8*|r", "grid: a current level on the other source carries the star")
    eq(out.extra[6], "* account", "grid: and the legend names that source")
    r.hist = sampleHist(X, {}, 4800, false)
    X.TickerView(r, viewWith({ xpTickerGapBars = true, xpTickerShowCurrent = false }), out)
    eq(out.kind[4], "footer", "current off: the footer follows the levels")
    eq(out.extra[4], "median 58:40", "current off: naming the shown rows' source")
    eq(out.n, 4, "current off: with no legend for a row not shown")
    r.hist.n = 0
    X.SummarizeHistory(r.hist, false)
    X.TickerView(r, viewWith({ xpTickerGapBars = true, xpTickerShowCurrent = false, xpTickerShowPlayed = false }), out)
    eq(out.n, 0, "every row off: no footer from a current level not shown")

    r.hist = sampleHist(X, { 3900, 3900 }, 4800)
    local card = X.NewCard(_G.UIParent)
    X.TickerView(r, viewWith(GRID), out)
    X.DrawCard(card, viewWith(GRID), out)
    eq(card.bar[2].shown, true, "draw: a slower level has its bar")
    eq(card.tick[2].shown, true, "draw: and its tick")
    eq(card.bar[1].shown, true, "draw: the current level its projected finish")
    eq(card.extra[2].colorR, 1, "draw: the gap in amber")
    eq(card.extra[2].colorG, 0.71, "draw: amber")
    eq(card.left[2].colorR, 0.66, "draw: under a dim label")
    eq(card.left[1].colorG, select(2, X.Math.AccentText(1, 0, 0, 0.05 * 0.85 + (1 - 0.85))), "draw: the current level in the accent tint")
    eq(card.divider.shown, true, "draw: a divider over the footer")

    r.hist = sampleHist(X, {}, nil)
    X.TickerView(r, viewWith(GRID), out)
    X.DrawCard(card, viewWith(GRID), out)
    eq(card.extra[3].text, "even", "draw: an even level")
    eq(card.tick[3].shown, true, "draw: keeps its tick")
    eq(card.bar[3].shown, false, "draw: with no bar")
    local tall = card.kuiH
    local noLine = { xpTickerGapBars = true, xpTickerShowPace = true }
    X.TickerView(r, viewWith(noLine), out)
    X.DrawCard(card, viewWith(noLine), out)
    eq(tall - card.kuiH, 8, "line off: the card loses the line and its margin")
    eq(card.lineTrack.shown, false, "line off: the line hides")
end

---------------------------------------------------------------------------------
-- Account medians on the live card, and their cost
---------------------------------------------------------------------------------

do
    local perChar = {
        ["Me-Realm"] = { xpHistory = { splits = { [58] = 4325, [57] = 3520, [56] = 2952 }, reached = {} } },
        ["Alt-Realm"] = { xpHistory = { splits = { [59] = 4800, [58] = 3900, [57] = 3800 }, reached = { [59] = 1000, [60] = 2000 } } },
        ["Alt2-Realm"] = { xpHistory = { splits = { [58] = 3900, [57] = 4000 } } },
        ["Odd-Realm"] = { xpHistory = { splits = { [58] = "x" } } },
    }
    local walks = 0
    local realPairs = pairs
    _G.pairs = function(t)
        if t == perChar then walks = walks + 1 end
        return realPairs(t)
    end
    local X, set = fresh({ db = { perChar = perChar },
        settings = { xpTickerGapBars = true, xpTickerShowLine = true, xpTickerHistoryRows = 3, xpTickerShowPace = true } })
    X.SessionStart("login")
    X.OnPlayed(1400)
    local raw = rawRecord()
    local card = showCard(X, raw)
    eq(walks, 2, "account: one walk for the medians and one for Pace when the card first shows")
    eq(raw.hist.acct[1], 3900, "account: the other characters' median for a level")
    eq(raw.hist.acct[2], 3900, "account: for each level")
    eq(raw.hist.acct[3], nil, "account: none for a level no other character has")
    eq(raw.hist.curAcct, 4800, "account: and the current level's")
    eq(card.extra[2].text, "+7:05", "account: the card shows the gap")
    eq(card.extra[4].text, "-9:28|cffa8a8a8*|r", "account: and stars the level on the recent median")
    eq(card.extra[5].text, "vs account", "account: the footer names the main source")
    eq(card.extra[6].text, "* recent median 58:40", "account: and the legend the other")
    eq(card.left[7].text, "Pace", "account: Pace last, with a value")
    eq(card.right[7].colorG, 0.85, "account: ahead in teal")

    local tick = tickers[#tickers].fn
    tick()
    tick()
    eq(walks, 2, "account: no walk on a tick")
    local texts = setTexts
    for _ = 1, 5 do tick() end
    eq(setTexts, texts, "account: no SetText for an unchanged text")
    local height = card.kuiH
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 200 do tick() end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    check(grown < 1, "account: a tick makes no table", grown)
    eq(card.kuiH, height, "account: the height holds across ticks")

    X.OnPlayed(5000, 1200)
    tick()
    eq(walks, 3, "account: a history write walks once more")
    raw.level = 60
    X.TickerRefresh(raw)
    eq(walks, 5, "account: a level change walks for the medians and for Pace")
    set.xpTickerShowCurrent = false
    X.TickerApply()
    tick()
    eq(walks, 5, "account: hiding Current Level re-summarizes with no walk")
    eq(card.extra[1].text, "+7:05", "account: and the newest level leads")
    set.xpTickerShowCurrent = nil
    set.xpTickerGapBars = false
    X.TickerApply()
    tick()
    eq(walks, 5, "account: with Gap Bars off, no walk")
    eq(card.extra[2].text, "", "account: and no gap")
    _G.pairs = realPairs
    X.TickerStop()
end

do
    local perChar = { ["Alt-Realm"] = { xpHistory = { splits = { [58] = 3900 }, reached = { [59] = 1000, [60] = 2000 } } } }
    local walks = 0
    local realPairs = pairs
    _G.pairs = function(t)
        if t == perChar then walks = walks + 1 end
        return realPairs(t)
    end
    local X = fresh({ db = { perChar = perChar } })
    X.SessionStart("login")
    showCard(X, rawRecord())
    tickers[#tickers].fn()
    eq(walks, 0, "both off: with Gap Bars and Pace off, no save is walked")
    _G.pairs = realPairs
    X.TickerStop()
end

do
    local perChar = { ["Alt-Realm"] = { xpHistory = { splits = { [59] = 4800, [58] = 3900 } } } }
    local X = fresh({ noKey = true, db = { perChar = perChar }, settings = { xpTickerGapBars = true } })
    X.SessionStart("login")
    local raw = rawRecord()
    local card = showCard(X, raw)
    eq(raw.hist.curAcct, nil, "no key: no account median, since the player's own entry cannot be told apart")
    eq(card.left[2].text, "Played", "no key: the footer follows the current level")
    eq(card.extra[2].text, "", "no key: and names no source, with nothing to compare")
    X.TickerStop()
end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
