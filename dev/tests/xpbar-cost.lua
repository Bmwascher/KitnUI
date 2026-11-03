-- ╔══════════════════════════════════════════════════════════════╗
-- ║  xpbar-cost.lua                                              ║
-- ║  Purpose: Gate for the XP bars' cost: nothing exists until   ║
-- ║           a bar is on, the XP bar alone registers only its   ║
-- ║           events, and turning both off takes it all down.    ║
-- ║           Also the page and preview with both bars off, the  ║
-- ║           preview's sample level and atlas lookups per draw. ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/xpbar-cost.lua

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

local function finish()
    print(string.format("%d checks, %d failures", checks, failures))
    os.exit(failures == 0 and 0 or 1)
end

---------------------------------------------------------------------------------
-- Recording stubs
---------------------------------------------------------------------------------

local NOOP = function() end
local methods = {}
local frames, timers = {}, {}

-- A capitalized method is a no-op unless listed below; a data field reads nil.
local function Obj(kind)
    return setmetatable({ kind = kind, shown = true, events = {}, scripts = {} }, {
        __index = function(_, key)
            if methods[key] then return methods[key] end
            if type(key) == "string" and key:match("^%u") then return NOOP end
            return nil
        end,
    })
end

methods.RegisterEvent = function(self, e) self.events[e] = true end
methods.RegisterUnitEvent = function(self, e) self.events[e] = true end
methods.UnregisterEvent = function(self, e) self.events[e] = nil end
methods.IsEventRegistered = function(self, e) return self.events[e] == true end
methods.SetScript = function(self, name, fn) self.scripts[name] = fn end
methods.Show = function(self) self.shown = true end
methods.Hide = function(self) self.shown = false end
methods.SetShown = function(self, v) self.shown = v and true or false end
methods.IsShown = function(self) return self.shown end
methods.IsVisible = function(self) return self.shown end
methods.GetWidth = function() return 100 end
methods.GetHeight = function() return 20 end
methods.GetFrameLevel = function() return 1 end
methods.GetParent = function() return _G.UIParent end
methods.CreateTexture = function() return Obj("Texture") end
methods.CreateFontString = function() return Obj("FontString") end
methods.CreateMaskTexture = function() return Obj("MaskTexture") end
methods.CreateAnimationGroup = function() return Obj("AnimationGroup") end
methods.CreateAnimation = function() return Obj("Animation") end
methods.GetStatusBarTexture = function(self)
    self.barTex = self.barTex or Obj("Texture")
    return self.barTex
end
methods.SetFont = function() return true end
methods.IsPlaying = function() return false end
methods.EnableMouse = function(self, on) self.click, self.motion = on and true or false, on and true or false end
methods.SetMouseClickEnabled = function(self, on) self.click = on and true or false end
methods.SetMouseMotionEnabled = function(self, on) self.motion = on and true or false end

_G.CreateFrame = function(kind)
    local f = Obj(kind)
    frames[#frames + 1] = f
    return f
end
local afters = 0
_G.C_Timer = {
    After = function() afters = afters + 1 end,
    NewTimer = function(_, fn)
        local t = { fn = fn, canceled = false }
        function t.Cancel(self) self.canceled = true end
        timers[#timers + 1] = t
        return t
    end,
}
_G.UIParent = Obj("Frame")
_G.GameTooltip = Obj("GameTooltip")
_G.StatusTrackingBarManager = Obj("Frame")
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.CreateColor = function() return { SetRGBA = NOOP } end
_G.InCombatLockdown = function() return false end
-- Runs fn after the hooked function, as the client's does.
_G.hooksecurefunc = function(t, name, fn)
    local orig = t[name]
    t[name] = function(...)
        orig(...)
        fn(...)
    end
end
_G.GetTime = function() return 1000 end
_G.time = function() return 50000 end
_G.UnitLevel = function() return 10 end
_G.UnitXP = function() return 100 end
_G.UnitXPMax = function() return 1000 end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.GetXPExhaustion = function() return 0 end
_G.IsResting = function() return false end
_G.IsXPUserDisabled = function() return false end
_G.GetMaxLevelForPlayerExpansion = function() return 90 end
_G.GetMaxPlayerLevel = function() return 90 end

local updaters, unlocks, accents = {}, 0, 0
local EUI = {
    Lite = { NewDB = function() return { profile = {} } end, _dbRegistry = {} },
    RegisterVisibilityUpdater = function(fn) updaters[fn] = true end,
    UnregisterVisibilityUpdater = function(fn) updaters[fn] = nil end,
    RegisterMouseoverTarget = NOOP,
    UnregisterMouseoverTarget = NOOP,
    EvalVisibility = function() return true end,
    MakeUnlockElement = function(opts) return opts end,
    RegAccent = function() accents = accents + 1 end,
    GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end,
    GetFontOutlineFlag = function() return "" end,
}
local unlockList
function EUI.RegisterUnlockElements(_, list)
    unlocks = unlocks + 1
    unlockList = list
end
_G.EllesmereUI = EUI

local core = { title = "KitnUI", profileName = "KitnUI", data = {}, db = { perChar = {}, euiSnap = {} } }
core.GetCharKey = function() return "Tester-Realm" end
_G.KitnUI_Shared = core

---------------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------------

local ns = {}
local function load(file)
    local chunk, err = loadfile(file)
    if not chunk then
        print("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI_EUI", ns)
end

load("KitnUI_EUI/Core.lua")
local coreFrames = #frames

local fh = assert(io.open("KitnUI_EUI/XPBar/XPBar.xml", "rb"))
local manifest = fh:read("*a")
fh:close()
local files = {}
for file in manifest:gmatch('<Script file="([^"]+)"') do files[#files + 1] = file end
check(#files > 0, "the XP Bar manifest lists its files")
for _, file in ipairs(files) do load("KitnUI_EUI/XPBar/" .. file) end

local X = ns.XPBar
check(type(X) == "table" and type(X.Apply) == "function", "the XP Bar module loads with its Apply funnel")
check(type(ns.EUIPages) == "table" and type(ns.EUIPages["XP Bar"]) == "function", "the XP Bar page registers its builder")
check(type(X.BuildPreviewHeader) == "function" and type(X.PreviewRefresh) == "function"
    and type(X.PreviewRestore) == "function", "the XP Bar page has its preview header")
if not (type(X) == "table" and type(X.Apply) == "function") then finish() end

local XP_EVENTS = {
    "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
    "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "PLAYER_MAX_LEVEL_UPDATE", "MAX_EXPANSION_LEVEL_UPDATED",
    "PLAYER_LOGOUT", "TIME_PLAYED_MSG",
}
local FACTION_EVENTS = { "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "ZONE_CHANGED_NEW_AREA" }

local function eventNames()
    local seen, list = {}, {}
    for _, f in ipairs(frames) do
        for e in pairs(f.events) do seen[e] = true end
    end
    for e in pairs(seen) do list[#list + 1] = e end
    table.sort(list)
    return table.concat(list, ",")
end

local function quiet(label)
    eq(#frames, coreFrames, label .. ": no frame beyond Core's own")
    eq(#timers, 0, label .. ": no timer")
    eq(eventNames(), "PLAYER_ENTERING_WORLD,PLAYER_LOGIN", label .. ": only Core's boot events")
    check(next(updaters) == nil, label .. ": no visibility updater")
    eq(unlocks, 0, label .. ": no Unlock Mode element")
    eq(accents, 0, label .. ": no accent callback")
end

---------------------------------------------------------------------------------
-- Off costs nothing
---------------------------------------------------------------------------------

quiet("at load")
local ok, why = pcall(X.Apply)
check(ok, "an apply with both bars off runs", why)
quiet("a re-apply with both bars off")

local combat = false
_G.InCombatLockdown = function() return combat end
combat = true
ok, why = pcall(X.SetHideExisting, "xp", false)
check(ok, "a Hide Existing click with both bars off runs in combat", why)
ok, why = pcall(X.SetHideExisting, "xp", true)
check(ok, "and so does the click back", why)
combat = false
quiet("a Hide Existing click in combat with both bars off")

-- Opening the XP Bar page with both bars off: the preview draws its sample
-- bars, which are options-page frames, and starts nothing.
ok, why = pcall(X.BuildPreviewHeader, Obj("Frame"), 800)
check(ok, "the preview opens with both bars off", why)
eq(#timers, 0, "preview with both bars off: no timer")
eq(eventNames(), "PLAYER_ENTERING_WORLD,PLAYER_LOGIN", "preview with both bars off: only Core's boot events")
check(next(updaters) == nil, "preview with both bars off: no visibility updater")
eq(unlocks, 0, "preview with both bars off: no Unlock Mode element")
eq(accents, 0, "preview with both bars off: no accent callback")
local previewFrames = #frames
ok, why = pcall(X.PreviewRefresh)
check(ok, "preview with both bars off: a redraw runs without a Lua error", why)
eq(#frames, previewFrames, "preview with both bars off: a redraw creates no frame")

-- The page builder itself with both bars off. Its one script hook goes on its
-- own Pinned dropdown, a control of the options window.
local hooks, mounts = {}, 0
local touchErr
local function Control()
    local c = Obj("Control")
    c.HookScript = function(_, name, fn) hooks[#hooks + 1] = { name = name, fn = fn } end
    return c
end
local function Touch(cfg)
    if type(cfg) ~= "table" then return end
    for _, key in ipairs({ "getValue", "disabled" }) do
        if type(cfg[key]) == "function" then
            local done, err = pcall(cfg[key])
            if not done and not touchErr then touchErr = key .. ": " .. tostring(err) end
        end
    end
end
EUI.Widgets = {
    SectionHeader = function() return Obj("Frame"), 20 end,
    DualRow = function(_, _parent, _y, left, right)
        Touch(left)
        Touch(right)
        return { _rightRegion = { _control = Control() } }, 30
    end,
}
function EUI.SetContentHeader(_, builder)
    mounts = mounts + 1
    builder(Obj("Frame"), 800)
end
local aftersAtPage = afters
local height
ok, why = pcall(function() height = ns.EUIPages["XP Bar"](Obj("Frame"), -10) end)
check(ok, "the page builds with both bars off", why)
check(type(height) == "number" and height > 10, "page with both bars off: it returns its height", height)
eq(mounts, 1, "page with both bars off: it mounts the preview header once")
check(touchErr == nil, "page with both bars off: every control reads its value and state", touchErr)
eq(#hooks, 1, "page with both bars off: one script hook")
eq(hooks[1] and hooks[1].name, "OnMouseDown", "page with both bars off: on the Pinned dropdown's press")
if hooks[1] then
    ok, why = pcall(hooks[1].fn)
    check(ok, "page with both bars off: a press on the Pinned dropdown runs", why)
end
eq(#frames, previewFrames, "page with both bars off: no frame beyond the preview's own")
eq(#timers, 0, "page with both bars off: no timer")
eq(afters, aftersAtPage, "page with both bars off: no next-frame work")
eq(eventNames(), "PLAYER_ENTERING_WORLD,PLAYER_LOGIN", "page with both bars off: only Core's boot events")
check(next(updaters) == nil, "page with both bars off: no visibility updater")
eq(unlocks, 0, "page with both bars off: no Unlock Mode element")
eq(accents, 0, "page with both bars off: no accent callback")

-- The preview's sample level: 85, or five below a lower cap.
local realDraw = X.Draw
local drawnLevel
X.Draw = function(w, view, data)
    if data and data.level then drawnLevel = data.level end
    return realDraw(w, view, data)
end
local function sampleAt(cap)
    _G.GetMaxLevelForPlayerExpansion = function() return cap end
    drawnLevel = nil
    X.PreviewRefresh()
    return drawnLevel
end
eq(sampleAt(90), "Level 85", "preview sample: Level 85 under a higher cap")
eq(sampleAt(85), "Level 85", "preview sample: Level 85 at a cap of exactly 85")
eq(sampleAt(60), "Level 55", "preview sample: five below a lower cap")
X.Draw = realDraw
_G.GetMaxLevelForPlayerExpansion = function() return 90 end

---------------------------------------------------------------------------------
-- The XP bar alone
---------------------------------------------------------------------------------

local settings = ns.EUISettings()
settings.xpEnabled = true
ok, why = pcall(X.Apply)
check(ok, "an apply with the XP bar on runs", why)
local evFrame
for _, f in ipairs(frames) do
    if f.events.PLAYER_XP_UPDATE then evFrame = f end
end
check(evFrame ~= nil, "the XP bar registers its events")
evFrame = evFrame or { events = {} }
for _, e in ipairs(XP_EVENTS) do check(evFrame.events[e], "XP bar on: registered " .. e) end
for _, e in ipairs(FACTION_EVENTS) do check(not evFrame.events[e], "XP bar on: no faction event " .. e) end
check(next(updaters) ~= nil, "XP bar on: the bar joins the visibility service")
eq(unlocks, 1, "XP bar on: the Unlock Mode elements register on the first enabled apply")

-- Runs each timer still waiting, once. A Lua error in a callback is a
-- failure, never swallowed.
local scans = 0
X.ScanQuestXP = function()
    scans = scans + 1
    return 0, 0
end
local function fire()
    local due = {}
    for _, t in ipairs(timers) do
        if not t.canceled and not t.fired then due[#due + 1] = t end
    end
    for _, t in ipairs(due) do
        t.fired = true
        local done, err = pcall(t.fn)
        check(done, "a timer callback runs without a Lua error", err)
    end
end
fire()
eq(scans, 1, "XP bar on: the quest totals are scanned")

-- A tooltip open on the XP bar when combat starts, Hide Tooltip in Combat on
local xpFrame = unlockList and unlockList[1] and unlockList[1].getFrame()
local tipHidden = false
_G.GameTooltip.IsOwned = function(_, f) return f ~= nil and f == xpFrame end
_G.GameTooltip.Hide = function() tipHidden = true end
check(xpFrame ~= nil, "XP bar on: its Unlock element returns its frame")
combat = true
for fn in pairs(updaters) do fn() end
combat = false
check(tipHidden, "combat starts: the open XP tooltip comes down")

-- A shown state that is secret counts as hidden: the open tooltip comes down
-- and the minute clock stops.
local SECRET_STATE = {}
_G.issecretvalue = function(v) return v == SECRET_STATE end
local realIsShown = methods.IsShown
methods.IsShown = function() return SECRET_STATE end
tipHidden = false
local canceledBefore = 0
for _, t in ipairs(timers) do if t.canceled then canceledBefore = canceledBefore + 1 end end
for fn in pairs(updaters) do fn() end
local canceledAfter = 0
for _, t in ipairs(timers) do if t.canceled then canceledAfter = canceledAfter + 1 end end
check(tipHidden, "a secret shown state: the open XP tooltip comes down")
check(canceledAfter > canceledBefore, "a secret shown state: the minute clock stops")
methods.IsShown = realIsShown
_G.issecretvalue = nil

-- EllesmereUI's mouseover reveal enables the whole mouse, then shows the
-- bar; on a bar already shown that Show runs no OnShow.
check(xpFrame ~= nil and xpFrame.shown == true, "mouseover reveal: the XP bar is already shown")
if xpFrame then
    xpFrame:EnableMouse(true)
    xpFrame:Show()
    eq(xpFrame.click, false, "mouseover reveal on a shown bar: clicks still pass through")
    eq(xpFrame.motion, true, "mouseover reveal on a shown bar: hovering still reaches the tooltip")
end

settings.xpEnabled, settings.fbEnabled = false, true
ok, why = pcall(X.Apply)
check(ok, "an apply with the faction bar alone runs", why)
check(evFrame.events.UPDATE_FACTION, "faction bar on: registered UPDATE_FACTION")
check(not evFrame.events.PLAYER_XP_UPDATE, "faction bar on: no XP event")
check(not evFrame.events.PLAYER_LOGOUT, "faction bar on, no session yet: no logout save")

-- The XP bar back on after a gap with the faction bar on throughout: quest
-- events were not heard meanwhile, so the totals are scanned again.
settings.xpEnabled = true
X.Apply()
fire()
eq(scans, 2, "XP bar back on: the quest totals are scanned again")

-- A scan still waiting when the quest events go is dropped with the totals.
ok, why = pcall(evFrame.scripts.OnEvent, evFrame, "QUEST_LOG_UPDATE")
check(ok, "a quest log event runs without a Lua error", why)
settings.xpEnabled = false
X.Apply()
fire()
eq(scans, 2, "XP bar off with a scan waiting: that scan does not run")
settings.xpEnabled = true
X.Apply()
fire()
eq(scans, 3, "XP bar back on: one fresh scan")

-- The XP bar going off while the faction bar stays, with a session running.
X.SessionStart("login")
settings.xpEnabled = false
ok, why = pcall(X.Apply)
check(ok, "the XP bar going off under the faction bar runs", why)
local saved = core.db.perChar["Tester-Realm"] and core.db.perChar["Tester-Realm"].xp
eq(saved and saved.savedAt, 50000, "XP bar off under the faction bar: the session is saved")
check(evFrame.events.PLAYER_LOGOUT, "XP bar off under the faction bar: the logout save stays registered")
check(not evFrame.events.PLAYER_XP_UPDATE, "XP bar off under the faction bar: no XP event")

---------------------------------------------------------------------------------
-- Both off takes it all down
---------------------------------------------------------------------------------

-- A level gained while the XP bar was off, so the final save counts it unseen.
_G.UnitLevel = function() return 11 end
_G.UnitXPMax = function() return 1200 end
local aftersBefore = afters
settings.fbEnabled = false
ok, why = pcall(X.Apply)
check(ok, "an apply turning both bars off runs", why)
eq(afters, aftersBefore, "both off: the final save queues no next-frame work")
check(next(evFrame.events) == nil, "both off: every event is unregistered")
for i, t in ipairs(timers) do check(t.canceled or t.fired, "both off: timer " .. i .. " is canceled or has run") end
check(next(updaters) == nil, "both off: the visibility updater is gone")
eq(unlocks, 1, "both off: the Unlock Mode elements stay registered")

---------------------------------------------------------------------------------
-- Atlas lookups
---------------------------------------------------------------------------------

-- The client returns a new table on every atlas lookup and a bar redraws on
-- every XP event, so a redraw looks no atlas up.
local lookups = 0
_G.C_Texture = {
    GetAtlasInfo = function()
        lookups = lookups + 1
        return { width = 256, height = 34, file = 1 }
    end,
}
settings.xpFrameStyle, settings.xpFillStyle, settings.xpProfFill = "prof", "profession", "Alchemy"
local atlasWidget = X.NewWidget(_G.UIParent, "xp")
local atlasData = { fill = 40, questEnd = 50, restedEnd = 60, level = "Level 10", center = "400 / 1,000", right = "40.0%" }
local function drawTwice(label)
    ok, why = pcall(X.Draw, atlasWidget, X.Get, atlasData)
    check(ok, label .. ": a first draw runs", why)
    local first = lookups
    ok, why = pcall(X.Draw, atlasWidget, X.Get, atlasData)
    check(ok, label .. ": a redraw runs", why)
    eq(lookups, first, label .. ": a redraw looks no atlas up")
end
drawTwice("profession frame and fill")
check(lookups > 0, "profession frame and fill: the first draw looks its atlases up")
settings.xpFrameStyle = "blizzard"
drawTwice("Blizzard frame")

---------------------------------------------------------------------------------
-- Secret geometry
---------------------------------------------------------------------------------

-- A secret text width, frame level or visibility is never used: a text counts
-- as no width, a level falls back to the bottom, and the preview does not
-- redraw.
local SECRET_WIDTH, SECRET_LEVEL, SECRET_VISIBLE = 5000, 7, {}
_G.issecretvalue = function(v) return v == SECRET_WIDTH or v == SECRET_LEVEL or v == SECRET_VISIBLE end
methods.GetStringWidth = function() return SECRET_WIDTH end
methods.SetWidth = function(self, v) self.width = v end
ok, why = pcall(X.Draw, atlasWidget, X.Get, atlasData)
check(ok, "a secret text width: the draw runs", why)
local capped = 0
for _, fs in pairs(atlasWidget.texts) do
    if (fs.width or 0) ~= 0 then capped = capped + 1 end
end
eq(capped, 0, "a secret text width: no text is capped by it")
methods.GetStringWidth, methods.SetWidth = nil, nil

local realLevel = methods.GetFrameLevel
methods.GetFrameLevel = function() return SECRET_LEVEL end
local levelWidget = X.NewWidget(_G.UIParent, "fb")
eq(levelWidget.base, 0, "a secret frame level: a new bar's layers count from 0")
local levels = {}
methods.SetFrameLevel = function(_, v) levels[#levels + 1] = v end
ok, why = pcall(X.BuildPreviewHeader, Obj("Frame"), 800)
check(ok, "a secret frame level: the preview builds", why)
eq(levels[1], 0, "a secret frame level: the preview's stage sits at the bottom")
methods.GetFrameLevel, methods.SetFrameLevel = realLevel, nil

local realVisible = methods.IsVisible
methods.IsVisible = function() return SECRET_VISIBLE end
local draws = 0
local drawFn = X.Draw
X.Draw = function(...)
    draws = draws + 1
    return drawFn(...)
end
ok, why = pcall(X.PreviewRefresh)
check(ok, "a secret visibility: the refresh runs", why)
eq(draws, 0, "a secret visibility: the preview does not redraw")
X.Draw, methods.IsVisible, _G.issecretvalue = drawFn, realVisible, nil

---------------------------------------------------------------------------------
-- Text offsets
---------------------------------------------------------------------------------

-- A text's offsets move it from the spot its position gives it, inside the
-- bar and on its rows alike; at 0 it sits where it did.
do
    methods.SetPoint = function(self, point, rel, relPoint, x, y) self.pt = { point, rel, relPoint, x, y } end
    settings.xpFrameStyle, settings.xpFillStyle = "eui", "gradient"
    local offWidget = X.NewWidget(_G.UIParent, "xp")
    local offData = { fill = 40, questEnd = 50, restedEnd = 60, level = "Level 10", center = "400 / 1,000",
        right = "40.0%", levelTime = "Time this level: 20m" }
    local function pointOf(w, key)
        local pt = w.texts[key].pt or {}
        return tostring(pt[1]) .. " " .. tostring(pt[3]) .. " " .. tostring(pt[4]) .. " " .. tostring(pt[5])
    end
    ok, why = pcall(X.Draw, offWidget, X.Get, offData)
    check(ok, "text offsets at 0: the draw runs", why)
    eq(pointOf(offWidget, "center"), "CENTER CENTER 0 0", "text offsets at 0: the amount sits centered in the bar")
    eq(pointOf(offWidget, "levelTime"), "BOTTOMLEFT TOPLEFT 6 3", "text offsets at 0: the time this level sits on the first row above")
    settings.xpAmountOffX, settings.xpAmountOffY = 7, -3
    settings.xpLevelTimeOffX, settings.xpLevelTimeOffY = 5, 2
    ok, why = pcall(X.Draw, offWidget, X.Get, offData)
    check(ok, "text offsets: the draw runs", why)
    eq(pointOf(offWidget, "center"), "CENTER CENTER 7 -3", "text offsets: the amount moves by its own")
    eq(pointOf(offWidget, "levelTime"), "BOTTOMLEFT TOPLEFT 11 5", "text offsets: the time this level moves by its own")
    eq(pointOf(offWidget, "level"), "LEFT LEFT 6 0", "text offsets: the level text has none and stays put")
    settings.fbNameOffX, settings.fbNameOffY = 4, 1
    local offFaction = X.NewWidget(_G.UIParent, "fb")
    ok, why = pcall(X.Draw, offFaction, X.Get, { fill = 65, left = "Delve Companion - Level 20 - 65.0%", right = "(6.5K / 10.0K)" })
    check(ok, "faction text offsets: the draw runs", why)
    eq(pointOf(offFaction, "left"), "LEFT LEFT 9 1", "faction text offsets: the name moves by its own")
    eq(pointOf(offFaction, "right"), "RIGHT RIGHT -5 0", "faction text offsets: the values have none of their own set and stay put")
    settings.xpAmountOffX, settings.xpAmountOffY, settings.xpLevelTimeOffX, settings.xpLevelTimeOffY = nil, nil, nil, nil
    settings.fbNameOffX, settings.fbNameOffY = nil, nil
    methods.SetPoint = nil
end

finish()
