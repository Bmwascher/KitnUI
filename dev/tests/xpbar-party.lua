-- ╔══════════════════════════════════════════════════════════════╗
-- ║  xpbar-party.lua                                             ║
-- ║  Purpose: Gate for party XP's live path: the markers, the    ║
-- ║           card, what each state costs, sending, refusals,    ║
-- ║           receipt and secret values. Loads the SHIPPED code, ║
-- ║           never a copy.                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/xpbar-party.lua

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
local pointCalls, textCalls = 0, 0

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
methods.SetFrameLevel = function(self, v) self.level = v end
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
methods.SetPoint = function(self, ...)
    pointCalls = pointCalls + 1
    self.point = { ... }
end
methods.SetText = function(self, text)
    textCalls = textCalls + 1
    self.text = text
end
methods.SetVertexColor = function(self, r, g, b) self.colorR, self.colorG, self.colorB = r, g, b end
methods.SetTextColor = function(self, r, g, b) self.colorR, self.colorG, self.colorB = r, g, b end
methods.SetStatusBarColor = function(self, r, g, b) self.colorR, self.colorG, self.colorB = r, g, b end
methods.SetValue = function(self, v) self.value = v end
methods.SetSize = function(self, w, h) self.width, self.height = w, h end
methods.SetWidth = function(self, w) self.width = w end

_G.CreateFrame = function(kind, _, parent)
    local f = Obj(kind)
    f.parent = parent
    frames[#frames + 1] = f
    return f
end
_G.C_Timer = {
    After = NOOP,
    NewTicker = function() return { Cancel = NOOP } end,
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
_G.RAID_CLASS_COLORS = {
    MAGE = { r = 0.1, g = 0.2, b = 0.3 },
    WARRIOR = { r = 0.4, g = 0.5, b = 0.6 },
    DRUID = { r = 0.7, g = 0.8, b = 0.9 },
}
local SECRET = {}
_G.issecretvalue = function(v) return v == SECRET end

local updaters, listeners, mouseover = {}, {}, {}
local unlocks, accents = 0, 0
local visResult = true
local EUI = {
    Lite = { NewDB = function() return { profile = {} } end, _dbRegistry = {} },
    RegisterVisibilityUpdater = function(fn) updaters[fn] = true end,
    UnregisterVisibilityUpdater = function(fn) updaters[fn] = nil end,
    RegisterMouseoverTarget = function(frame, fn) mouseover[frame] = fn end,
    UnregisterMouseoverTarget = function(frame) mouseover[frame] = nil end,
    EvalVisibility = function() return visResult end,
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
function EUI.RegisterUnlockModeListener(_, owner, fn) listeners[owner] = fn end
function EUI.UnregisterUnlockModeListener(_, owner) listeners[owner] = nil end
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
local fh = assert(io.open("KitnUI_EUI/XPBar/XPBar.xml", "rb"))
local manifest = fh:read("*a")
fh:close()
for file in manifest:gmatch('<Script file="([^"]+)"') do load("KitnUI_EUI/XPBar/" .. file) end

local X = ns.XPBar
local settings = ns.EUISettings()

eq(#timers, 0, "at load: no timer")
eq(unlocks, 0, "at load: no Unlock Mode element")
eq(unlockList, nil, "at load: no element list")
eq(accents, 0, "at load: no accent callback")
check(next(updaters) == nil, "at load: no visibility updater")
check(next(listeners) == nil, "at load: no Unlock Mode listener")
check(next(mouseover) == nil, "at load: no mouseover target")
eq(settings.xpPartyCard, nil, "at load: nothing is written to the settings")

---------------------------------------------------------------------------------
-- The markers
---------------------------------------------------------------------------------

do
    check(type(X.SyncMarkers) == "function", "the markers load")
    local function tick(name, class, level, pct)
        return { name = name, class = class, level = level, pct = pct }
    end
    local data = {}
    X.XPView({ level = 59, cur = 94410, max = 209800, quest = 31470, rested = 52450, atMax = false, xpOff = false,
        levelTime = 1200, elapsed = 3600, gained = 90000 }, X.Get, data)
    data.levelTime, data.sessionTime, data.rate, data.compRested = nil, nil, nil, nil
    local w = X.NewWidget(_G.UIParent, "xp")
    eq(w.border.level, w.base + 13, "the border sits above the markers")
    eq(w.textHost.level, w.base + 14, "and the texts above the border")

    X.Draw(w, X.Get, data)
    eq(w.ptHost, nil, "no list makes no host")
    local frameCount = #frames
    data.markers = { n = 0 }
    X.Draw(w, X.Get, data)
    eq(w.ptHost, nil, "an empty list makes no host")
    eq(w.ptMarks, nil, "and no mark")
    eq(#frames, frameCount, "and no frame")

    local masked = {}
    local realMask = X.MaskEffect
    X.MaskEffect = function(_, region) masked[region] = true end
    data.markers = { n = 2, tick("Mirelle", "MAGE", 58, 91.2), tick("Vess", "DRUID", 57, 10) }
    X.Draw(w, X.Get, data)
    check(w.ptHost ~= nil, "a list makes the host")
    eq(w.ptHost.level, w.base + 12, "between the effects and the art")
    eq(#w.ptMarks, 2, "and one mark per member")
    local first, second = w.ptMarks[1], w.ptMarks[2]
    eq(first.tick.shown, true, "a tick shows")
    eq(first.tick.colorR, 0.1, "in its class color")
    eq(first.label.colorR, 0.1, "and so does its label")
    eq(first.x, X.PartyLogic.MarkerX(91.2, w.bw, 2, 1), "at its percent")
    eq(first.tick.width, 2, "at the default width")
    eq(first.tick.height, w.bh, "as tall as the bar")
    eq(masked[first.tick] and masked[second.tick], true, "each tick takes the bar's mask")
    check(type(first.label.text) == "string" and first.label.text:find("Mirelle", 1, true) ~= nil, "the label names the member")
    check(first.label.text:find("58", 1, true) ~= nil, "and its level, by default")
    check(w.above > w.textAbove, "a label Above takes a row above the bar")
    eq(w.below, w.textBelow, "and none below")

    -- A repeat touches nothing.
    local points, texts, frameTotal = pointCalls, textCalls, #frames
    X.SyncMarkers(w, X.Get, data.markers)
    eq(pointCalls, points, "a repeat places nothing")
    eq(textCalls, texts, "and sets no text")
    eq(#frames, frameTotal, "and makes no frame")

    -- One row further out than the around-texts.
    local roomBefore = w.textAbove
    data.levelTime = "Time this level: 5m"
    X.Draw(w, X.Get, data)
    check(w.textAbove > roomBefore, "an around-text takes room")
    check(w.above > w.textAbove, "and the label sits a row further out")
    eq(first.label.point[1], "BOTTOM", "above the tick")
    check(first.label.point[5] >= w.textAbove, "clear of that row", first.label.point[5])
    data.levelTime = nil

    settings.xpPartyLabelSide = "below"
    X.Draw(w, X.Get, data)
    eq(w.above, w.textAbove, "a label Below takes no room above")
    check(w.below > w.textBelow, "and a row below")
    eq(first.label.point[1], "TOP", "below the tick")
    settings.xpPartyLabelSide = nil

    settings.xpPartyLabelOffX, settings.xpPartyLabelOffY = 7, 9
    X.Draw(w, X.Get, data)
    eq(first.label.point[4], 7, "the X offset moves the label")
    check(first.label.point[5] >= 9, "and the Y offset")
    settings.xpPartyLabelOffX, settings.xpPartyLabelOffY = nil, nil

    -- The room reaches the label's far edge from the body, 14 at the default size.
    settings.xpPartyLabelOffY = 17
    X.Draw(w, X.Get, data)
    eq(w.above, first.label.point[5] + 14, "a label moved up: the room above reaches it")
    w.insetY = 5
    X.SyncMarkers(w, X.Get, data.markers)
    eq(w.above, first.label.point[5] + 14, "with the frame's inset too")
    settings.xpPartyLabelOffY = -100
    X.Draw(w, X.Get, data)
    eq(w.above, w.textAbove, "a label moved in: the around-texts' room is the least")
    eq(w.below, -(first.label.point[5] + w.bh), "an Above label moved past the bar: the room below reaches it")
    settings.xpPartyLabelSide, settings.xpPartyLabelOffY = "below", -17
    X.Draw(w, X.Get, data)
    eq(w.below, 14 - first.label.point[5], "a label moved down: the room below reaches it")
    settings.xpPartyLabelOffY = 100
    X.Draw(w, X.Get, data)
    eq(w.below, w.textBelow, "a label moved in from below: the around-texts' room is the least")
    eq(w.above, first.label.point[5] - w.bh, "a Below label moved past the bar: the room above reaches it")
    settings.xpPartyLabelSide, settings.xpPartyLabelOffY = nil, nil
    X.Draw(w, X.Get, data)

    -- A tick sits on a physical pixel, with a width of whole ones.
    _G.EllesmereUI.PP = { mult = 0.75 }
    X.SyncMarkers(w, X.Get, data.markers)
    eq(first.x, X.PartyLogic.MarkerX(91.2, w.bw, 2.25, 0.75), "a tick snaps at the UI's pixel size")
    eq(first.x % 0.75, 0, "to a whole pixel")
    eq(first.tick.width, 2.25, "with a whole-pixel width")
    _G.EllesmereUI.PP = nil
    X.SyncMarkers(w, X.Get, data.markers)
    eq(first.tick.width, 2, "and returns with it")

    settings.xpPartyLabel = "name"
    X.Draw(w, X.Get, data)
    eq(first.label.text, "Mirelle", "Name reads the name alone")
    settings.xpPartyLabel = "off"
    X.Draw(w, X.Get, data)
    eq(first.label.shown, false, "Off hides the label")
    eq(w.above, w.textAbove, "and takes no room")
    eq(first.tick.shown, true, "and keeps the tick")
    settings.xpPartyLabel = nil
    X.Draw(w, X.Get, data)
    eq(first.label.shown, true, "and the label returns")

    settings.xpPartyMarkerWidth = 6
    X.Draw(w, X.Get, data)
    eq(first.tick.width, 6, "Marker Width is the setting")
    settings.xpPartyMarkerWidth = nil

    data.markers = { n = 1, tick("Vess", "DRUID", 57, 10) }
    X.Draw(w, X.Get, data)
    eq(first.tick.colorR, 0.7, "a mark takes the next member's color")
    eq(second.tick.shown, false, "a mark left over hides")
    eq(second.label.shown, false, "with its label")
    data.markers = nil
    X.Draw(w, X.Get, data)
    eq(first.tick.shown, false, "no list hides every mark")
    eq(first.label.shown, false, "and every label")
    eq(w.above, w.textAbove, "and frees the row")
    data.markers = { n = 1, tick("Bram", "NOT_A_CLASS", 57, 10) }
    X.Draw(w, X.Get, data)
    eq(first.tick.colorR, 1, "an unknown class draws white")
    X.MaskEffect = realMask

    local fb, fbData = X.NewWidget(_G.UIParent, "fb"), {}
    X.FactionView({ kind = "standard", name = "Argent Dawn", label = "Revered", reaction = 7, cur = 13020, min = 0,
        max = 21000, isMax = false }, X.Get, fbData)
    fbData.markers = { n = 1, tick("A", "MAGE", 5, 5) }
    X.Draw(fb, X.Get, fbData)
    eq(fb.ptHost, nil, "the reputation bar has no markers")
end

finish()
