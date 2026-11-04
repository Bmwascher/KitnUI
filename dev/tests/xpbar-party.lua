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
    eq(first.x, X.PartyLogic.MarkerX(91.2, w.bw, 3, 1), "at its percent")
    eq(first.tick.width, 3, "at the default width")
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

    -- The room reaches the label's far edge from the body, 15 at the default size.
    settings.xpPartyLabelOffY = 17
    X.Draw(w, X.Get, data)
    eq(w.above, first.label.point[5] + 15, "a label moved up: the room above reaches it")
    w.insetY = 5
    X.SyncMarkers(w, X.Get, data.markers)
    eq(w.above, first.label.point[5] + 15, "with the frame's inset too")
    settings.xpPartyLabelOffY = -100
    X.Draw(w, X.Get, data)
    eq(w.above, w.textAbove, "a label moved in: the around-texts' room is the least")
    eq(w.below, -(first.label.point[5] + w.bh), "an Above label moved past the bar: the room below reaches it")
    settings.xpPartyLabelSide, settings.xpPartyLabelOffY = "below", -17
    X.Draw(w, X.Get, data)
    eq(w.below, 15 - first.label.point[5], "a label moved down: the room below reaches it")
    settings.xpPartyLabelOffY = 100
    X.Draw(w, X.Get, data)
    eq(w.below, w.textBelow, "a label moved in from below: the around-texts' room is the least")
    eq(w.above, first.label.point[5] - w.bh, "a Below label moved past the bar: the room above reaches it")
    settings.xpPartyLabelSide, settings.xpPartyLabelOffY = nil, nil
    X.Draw(w, X.Get, data)

    -- A tick sits on a physical pixel, with a width of whole ones.
    _G.EllesmereUI.PP = { mult = 0.75 }
    settings.xpPartyMarkerWidth = 2
    X.SyncMarkers(w, X.Get, data.markers)
    eq(first.x, X.PartyLogic.MarkerX(91.2, w.bw, 2.25, 0.75), "a tick snaps at the UI's pixel size")
    eq(first.x % 0.75, 0, "to a whole pixel")
    eq(first.tick.width, 2.25, "with a whole-pixel width")
    _G.EllesmereUI.PP = nil
    X.SyncMarkers(w, X.Get, data.markers)
    eq(first.tick.width, 2, "and returns with it")
    settings.xpPartyMarkerWidth = nil
    X.SyncMarkers(w, X.Get, data.markers)

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

---------------------------------------------------------------------------------
-- The readers
---------------------------------------------------------------------------------

do
    eq(X.LevelCap(), 90, "the level cap from the expansion's and the player's cap")
    _G.GetMaxPlayerLevel = function() return 60 end
    eq(X.LevelCap(), 60, "the lower of the two")
    _G.GameRulesUtil = { GetEffectiveMaxLevelForPlayer = function() return 80 end }
    eq(X.LevelCap(), 80, "Blizzard's own rule first")
    _G.GameRulesUtil = { GetEffectiveMaxLevelForPlayer = function() return SECRET end }
    eq(X.LevelCap(), 60, "a secret answer falls back")
    _G.GameRulesUtil = nil
    _G.GetMaxLevelForPlayerExpansion, _G.GetMaxPlayerLevel = nil, nil
    eq(X.LevelCap(), nil, "with nothing to read, no cap")
    _G.GetMaxLevelForPlayerExpansion = function() return 90 end
    _G.GetMaxPlayerLevel = function() return 90 end

    eq(X.ReadPlain(nil), nil, "a missing function reads as nil")
    eq(X.ReadPlain(function() error("x") end), nil, "a raised error reads as nil")
    eq(X.ReadPlain(function() return SECRET end), nil, "a secret reads as nil")
    local a, b = X.ReadPlain(function() return 1, 2 end)
    eq(a, 1, "the first result")
    eq(b, 2, "and the second")
end

---------------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------------

do
    local function row(name, class, kind, pct, text)
        return { name = name, class = class, view = { kind = kind, pct = pct, text = text } }
    end
    local list = { row("Mirelle", "MAGE", "data", 45, "Lv 59  45.0%"), row("Dornak", "WARRIOR", "max", 100, "Lv 90  Max") }

    local accentFn
    local regAccent = EUI.RegAccent
    EUI.RegAccent = function(opts)
        accentFn = opts.fn
        return regAccent(opts)
    end

    -- Off, it makes nothing.
    local frameCount, unlockCount = #frames, unlocks
    X.PartyCardApply()
    X.PartyCardRefresh(list, 2, true)
    eq(#frames, frameCount, "card off: no frame")
    eq(unlocks, unlockCount, "card off: no Unlock Mode element")
    check(next(updaters) == nil, "card off: no visibility updater")
    check(next(listeners) == nil, "card off: no Unlock Mode listener")
    eq(accents, 0, "card off: no accent callback")
    X.PartyCardRefresh(list, 0, false)

    -- On, with both bars off.
    settings.xpPartyCard = true
    X.PartyCardApply()
    check(#frames > frameCount, "card on: it makes a frame with both bars off")
    eq(unlocks, unlockCount + 1, "card on: the Unlock Mode elements register")
    eq(accents, 1, "card on: one accent callback")
    check(next(updaters) ~= nil, "card on: a visibility updater")
    check(listeners.KitnUI_PartyXP ~= nil, "card on: an Unlock Mode listener")
    X.PartyCardApply()
    eq(unlocks, unlockCount + 1, "a second apply registers nothing more")
    eq(accents, 1, "and no second accent callback")

    local element
    for _, e in ipairs(unlockList) do
        if e.key == "KitnUI_PartyXP" then element = e end
    end
    check(element ~= nil, "the card's Unlock Mode element is in the list")
    eq(element.noResize, true, "with no resize controls")
    eq(element.isHidden(), false, "and not hidden")
    local card = element.getFrame()
    check(card ~= nil, "it returns the card")
    settings.xpPartyCard = false
    eq(element.isHidden(), true, "the switch off hides it")
    settings.xpPartyCard = true

    -- Clicks pass through, through the hover service's reveal too.
    card:EnableMouse(true)
    eq(card.click, false, "a reveal leaves clicks off")
    eq(card.motion, false, "and motion")

    -- Rows
    eq(card.shown, false, "the card waits for what is wanted")
    X.PartyCardRefresh(list, 2, true)
    eq(card.shown, true, "wanted shows it")
    local r1, r2 = card.rows[1], card.rows[2]
    eq(r1.name.text, "Mirelle", "a row holds the name")
    eq(r1.name.colorR, 0.1, "in the class color")
    eq(r1.text.text, list[1].view.text, "and its text")
    eq(r1.bar.value, 45, "and its percent")
    eq(r2.bar.value, 100, "a max row is full")
    eq(r2.bar.colorR, r2.bar.colorG, "and gray")
    eq(r2.bar.colorG, r2.bar.colorB, "all through")
    eq(card.kuiW, 264, "the default Width draws 264 at the ticker's default font size")
    eq(card.kuiW, X.Math.TickerWidth(X.Get("xpTickerFontSize")), "which is the ticker's width")
    eq(X.Get("xpPartyBackground"), X.Get("xpTickerBackground"), "and with the ticker's background")
    local height = card.kuiH
    check(height > 0, "and as tall as its rows")

    local texts = textCalls
    X.PartyCardRefresh(list, 2, true)
    eq(textCalls, texts, "an unchanged row sets no text")

    local away = row("Bram", "DRUID", "offline", 0, "offline")
    X.PartyCardRefresh({ list[1], away }, 2, true)
    eq(r2.name.colorR, r2.name.colorG, "an offline name is gray")
    eq(r2.name.text, "Bram", "and the row is the new member's")
    eq(r2.bar.value, 0, "with an empty bar")

    X.PartyCardRefresh(list, 1, true)
    eq(r2.shown, false, "a row left over hides")
    check(card.kuiH < height, "and the card shortens")
    X.PartyCardRefresh(list, 2, true)
    eq(r2.shown, true, "and it returns")

    -- Fill
    settings.xpPartyFill = "class"
    X.PartyCardRefresh(list, 2, true)
    eq(r1.bar.colorR, 0.1, "Class Color fills in the class color")
    settings.xpPartyFill = "custom"
    settings.xpPartyFillColorR, settings.xpPartyFillColorG, settings.xpPartyFillColorB = 0.9, 0.8, 0.7
    X.PartyCardRefresh(list, 2, true)
    eq(r1.bar.colorR, 0.9, "Custom fills in the Fill Color")
    settings.xpPartyFillColorR, settings.xpPartyFillColorG, settings.xpPartyFillColorB = nil, nil, nil
    settings.xpPartyFill = nil
    local accentReal = X.AccentColor
    X.AccentColor = function() return 0.25, 0.5, 0.75 end
    X.PartyCardRefresh(list, 2, true)
    eq(r1.bar.colorR, 0.25, "the accent is the default")
    X.AccentColor = function() return nil end
    X.PartyCardRefresh(list, 2, true)
    eq(r1.bar.colorR, X.Get("xpPartyFillColorR"), "no accent falls back to the Fill Color")
    X.AccentColor = accentReal

    -- Settings
    settings.xpPartyFontSize = 24
    X.PartyCardApply()
    check(card.kuiH > height, "row height follows Font Size")
    settings.xpPartyFontSize = nil
    settings.xpPartyWidth = 400
    X.PartyCardApply()
    eq(card.kuiW, 400, "Width is the setting")
    eq((element.getSize()), 400, "and Unlock Mode reads it")
    settings.xpTickerFontSize = 20
    X.PartyCardApply()
    eq(card.kuiW, 400, "a set Width leaves the ticker's font size alone")
    for _, low in ipairs({ 1, 159 }) do
        settings.xpPartyWidth = low
        X.PartyCardApply()
        eq(card.kuiW, 160, "a Width of " .. low .. " draws as 160")
        eq((element.getSize()), 160, "and Unlock Mode reads 160 at " .. low)
    end
    settings.xpPartyWidth = 0
    X.PartyCardApply()
    eq(card.kuiW, X.Math.TickerWidth(20), "a Width of 0 is the ticker's width")
    settings.xpTickerFontSize = 24
    eq((element.getSize()), X.Math.TickerWidth(24), "Unlock Mode reads the ticker's width, not the 0, before any redraw")
    settings.xpTickerFontSize = nil
    settings.xpPartyWidth = nil
    settings.xpPartyBackground = "none"
    X.PartyCardApply()
    eq(card.bg.shown, false, "Background None hides the background")
    settings.xpPartyBackground = nil
    X.PartyCardApply()
    eq(card.bg.shown, true, "and Card shows it")

    -- Every Width and Font Size on the page leaves the bar and the name room.
    for _, width in ipairs({ 160, 260, 600 }) do
        for _, size in ipairs({ 8, 12, 32 }) do
            settings.xpPartyWidth, settings.xpPartyFontSize = width, size
            X.PartyCardApply()
            local look, label = card.look, width .. " wide at size " .. size
            check(look.barW > 0, "the bar has room, " .. label, look.barW)
            check(look.nameW > look.pad, "and the name, " .. label, look.nameW)
            eq(look.nameW + look.barW, width - 2 * look.pad, "and the two fill the row, " .. label)
            eq(r1.text.width, look.barW, "a row's text is capped to its bar, " .. label)
            eq(r1.name.width, look.nameW - look.pad, "and its name to its column, " .. label)
        end
    end
    -- At 0, each of the ticker's font sizes with each of the card's own.
    for _, tickerSize in ipairs({ 8, 12, 32 }) do
        for _, size in ipairs({ 8, 12, 32 }) do
            settings.xpPartyWidth, settings.xpTickerFontSize, settings.xpPartyFontSize = 0, tickerSize, size
            X.PartyCardApply()
            local look, label = card.look, "at 0, the ticker at " .. tickerSize .. " and the card at " .. size
            eq(look.width, X.Math.TickerWidth(tickerSize), "the ticker's width, " .. label)
            check(look.barW > 0, "the bar has room, " .. label, look.barW)
            check(look.nameW > look.pad, "and the name, " .. label, look.nameW)
            eq(look.nameW + look.barW, look.width - 2 * look.pad, "and the two fill the row, " .. label)
        end
    end
    settings.xpTickerFontSize = nil
    settings.xpPartyWidth, settings.xpPartyFontSize = nil, nil
    X.PartyCardApply()
    eq(card.look.nameW, 90, "at the defaults the name column is its multiple of the font size")
    local tickerCard = X.NewCard(_G.UIParent)
    X.DrawCard(tickerCard, X.Get, { rate = "", ding = "", pauseText = "", n = 0, keys = {} })
    eq(card.look.pad, tickerCard.pad, "at the defaults its pad is the ticker's, so their text lines up")

    -- Visibility
    X.PartyCardRefresh(list, 2, false)
    eq(card.shown, false, "not wanted hides it")
    X.PartyCardRefresh(list, 2, true)
    visResult = false
    X.PartyCardVisibility()
    eq(card.shown, false, "a Visibility choice that says no hides it")
    visResult = "mouseover"
    X.PartyCardVisibility()
    check(mouseover[card] ~= nil, "Mouseover uses the hover service")
    eq(mouseover[card] and mouseover[card](), true, "while it is wanted")
    visResult = true
    X.PartyCardVisibility()
    eq(mouseover[card], nil, "and leaves it after")
    eq(card.shown, true, "and shows")

    -- Unlock Mode shows the sample whatever the party state.
    X.PartyCardRefresh(list, 0, false)
    eq(card.shown, false, "solo: hidden")
    listeners.KitnUI_PartyXP(true)
    eq(card.shown, true, "Unlock Mode shows it solo")
    eq(card.rows[4] and card.rows[4].shown, true, "with the four sample rows")
    listeners.KitnUI_PartyXP(false)
    eq(card.shown, false, "and returns to its rule")

    -- The sample
    local sample, n = X.PartySampleRows(X.Get)
    eq(n, 4, "the sample has four rows")
    eq(sample[1].view.kind, "data", "the player first, with data")
    eq(sample[2].view.kind, "data", "a member with data")
    eq(sample[2].view.pct, 91.2, "at 91.2%")
    eq(sample[2].name, "Milkers", "named Milkers")
    eq(sample[3].view.kind, "nodata", "one with no data")
    eq(sample[3].view.text, "Lv 57  no data", "at level 57")
    eq(sample[3].class, "WARLOCK", "a warlock")
    eq(sample[4].view.kind, "max", "and a member at Max")
    eq(sample[4].view.text, "Lv 60  Max", "at level 60 whatever the real cap")
    eq(sample[4].class, "HUNTER", "a hunter")
    settings.xpPartyShowSelf = false
    local _, withoutSelf = X.PartySampleRows(X.Get)
    eq(withoutSelf, 3, "Show Self off drops the player's row")
    settings.xpPartyShowSelf = nil
    local marks = X.PartySampleMarks()
    eq(marks.n, 1, "the sample has one tick")
    eq(marks[1].pct, 91.2, "the member with data")

    -- The accent, on and stopped
    X.PartyCardRefresh(list, 2, true)
    X.AccentColor = function() return 0.6, 0.6, 0.6 end
    accentFn()
    eq(r1.bar.colorR, 0.6, "an accent change repaints the card")

    -- Stop
    settings.xpPartyCard = false
    X.PartyCardApply()
    eq(card.shown, false, "the switch off hides the card")
    check(next(updaters) == nil, "and leaves the visibility service")
    eq(listeners.KitnUI_PartyXP, nil, "and the Unlock Mode listener")
    eq(element.getFrame(), card, "the element keeps its frame")
    X.AccentColor = function() return 0.7, 0.7, 0.7 end
    local stoppedTexts = textCalls
    accentFn()
    eq(r1.bar.colorR, 0.6, "a stopped card takes no accent change")
    X.PartyCardRefresh({ row("Bram", "DRUID", "offline", 0, "offline") }, 1, true)
    eq(textCalls, stoppedTexts, "and no rows")
    eq(card.shown, false, "and stays hidden")
    X.PartyCardVisibility()
    eq(card.shown, false, "whoever asks")
    X.PartyCardRefresh(list, 0, false)
    X.AccentColor = accentReal
    EUI.RegAccent = regAccent
    settings.xpPartyCard = nil

    local placed
    local placeReal = X.PlaceFrame
    X.PlaceFrame = function(_, key, pos) placed = { key, pos } end
    X.Set("xpPartyPos", { point = "TOP", relPoint = "TOP", x = 1, y = 2 })
    element.applyPos()
    eq(placed and placed[1], "KitnUI_PartyXP", "the card places by its own key")
    eq(placed and placed[2].x, 1, "from its saved spot")
    local loaded = element.loadPos()
    eq(loaded.y, 2, "the element reads a copy of the spot")
    element.clearPos()
    eq(element.loadPos(), nil, "and clears it")
    X.PlaceFrame = placeReal

    -- Where it sits. A plain frame stands in for the ticker's.
    local ticker = _G.CreateFrame("Frame")
    local tickerReal = X.TickerFrame
    local tickerOn = true
    X.TickerFrame = function() return tickerOn and ticker or nil end
    settings.xpPartyCard = true
    X.PartyCardApply()
    local function onTicker(label)
        eq(card.point[1], "TOPLEFT", label .. ": by its top left")
        eq(card.point[2], ticker, label .. ": on the ticker")
        eq(card.point[3], "BOTTOMLEFT", label .. ": at its bottom left")
        eq(card.point[4], 0, label .. ": with the left edges lined up")
        eq(card.point[5], 0, label .. ": and no gap")
    end
    local function atFirstSpot(label)
        eq(card.point[1], "LEFT", label .. ": by its left")
        eq(card.point[2], _G.UIParent, label .. ": on the screen")
        eq(card.point[4], 40, label .. ": at its first spot")
        eq(card.point[5], -40, label .. ": below the ticker's")
    end
    onTicker("never moved")

    tickerOn = false
    X.PartyCardVisibility()
    atFirstSpot("the ticker off")
    tickerOn = true
    X.PartyCardVisibility()
    onTicker("the ticker on again")

    -- A move keeps its own spot, and clearing it stacks again.
    element.savePos(nil, "CENTER", "CENTER", 5, 6)
    eq(settings.xpPartyPos and settings.xpPartyPos.x, 5, "a move is saved")
    eq(card.point[2], _G.UIParent, "a move leaves the ticker")
    X.PartyCardVisibility()
    eq(card.point[4], 5, "and stays on its spot while the ticker is there")
    element.clearPos()
    X.PartyCardVisibility()
    onTicker("its spot cleared")

    -- Its own link wins.
    local reapplied
    EUI.IsAnchored = function(key) return key == "KitnUI_PartyXP" end
    EUI.ReapplyOwnAnchor = function(key) reapplied = key end
    local points = pointCalls
    X.PartyCardVisibility()
    eq(reapplied, "KitnUI_PartyXP", "its own link places it")
    eq(pointCalls, points, "and the card sets no point of its own")
    EUI.IsAnchored, EUI.ReapplyOwnAnchor = nil, nil

    -- The ticker's links: back to the card gives the first spot, elsewhere stacks.
    local dbReal = _G.EllesmereUIDB
    local function withLinks(links, label, want)
        _G.EllesmereUIDB = { unlockAnchors = links }
        local placedOk, placeErr = pcall(X.PartyCardVisibility)
        check(placedOk, label .. ": no error", placeErr)
        want(label)
    end
    withLinks({ KitnUI_XPTicker = { target = "KitnUI_PartyXP" } }, "the ticker linked to the card", atFirstSpot)
    withLinks({ KitnUI_XPTicker = { target = "A" }, A = { target = "KitnUI_PartyXP" } }, "through another element", atFirstSpot)
    withLinks({ KitnUI_XPTicker = { target = "A" }, A = { target = "KitnUI_XPTicker" } }, "a chain that never ends", atFirstSpot)
    withLinks({ KitnUI_XPTicker = { target = "A" } }, "the ticker linked elsewhere", onTicker)
    withLinks({}, "no links", onTicker)
    _G.EllesmereUIDB = dbReal

    -- Unlock Mode: on the screen at the same spot, which a later placement keeps.
    methods.GetLeft = function() return 11 end
    methods.GetTop = function() return 22 end
    listeners.KitnUI_PartyXP(true)
    eq(card.point[2], _G.UIParent, "Unlock Mode: off the ticker, for its arrow keys")
    eq(card.point[3], "BOTTOMLEFT", "Unlock Mode: from the screen's corner")
    eq(card.point[4], 11, "Unlock Mode: at the card's left")
    eq(card.point[5], 22, "Unlock Mode: and its top")
    points = pointCalls
    X.PartyCardVisibility()
    eq(pointCalls, points, "Unlock Mode: a later placement leaves a dragged card alone")
    listeners.KitnUI_PartyXP(false)
    onTicker("Unlock Mode closed")
    eq(settings.xpPartyPos, nil, "Unlock Mode closed: nothing saved")

    -- A cleared spot ends the hold: the next placement stacks the card and reads
    -- its rect again.
    local function reflattens(label, leave)
        listeners.KitnUI_PartyXP(true)
        leave()
        methods.GetLeft = function() return 33 end
        X.PartyCardVisibility()
        eq(card.point[2], _G.UIParent, label .. ": on the screen again")
        eq(card.point[4], 33, label .. ": at the spot it reads now")
        methods.GetLeft = function() return 11 end
        listeners.KitnUI_PartyXP(false)
    end
    reflattens("its spot cleared", element.clearPos)
    reflattens("a save, then its spot cleared", function()
        element.savePos(nil, "CENTER", "CENTER", 7, 8)
        element.clearPos()
    end)
    -- A link undone or the ticker off and on moves nothing until the session
    -- closes: an unlink keeps the live spot for the save.
    local function staysUntilClose(label, leave)
        listeners.KitnUI_PartyXP(true)
        leave()
        methods.GetLeft = function() return 33 end
        X.PartyCardVisibility()
        eq(card.point[2], _G.UIParent, label .. ": on the screen")
        eq(card.point[4], 11, label .. ": where the session put it")
        methods.GetLeft = function() return 11 end
        listeners.KitnUI_PartyXP(false)
        onTicker(label .. ", then closed")
    end
    staysUntilClose("a link undone", function()
        EUI.IsAnchored = function(key) return key == "KitnUI_PartyXP" end
        EUI.ReapplyOwnAnchor = NOOP
        X.PartyCardVisibility()
        EUI.IsAnchored, EUI.ReapplyOwnAnchor = nil, nil
    end)
    staysUntilClose("the ticker off and on", function()
        tickerOn = false
        X.PartyCardVisibility()
        tickerOn = true
    end)

    -- A card that is not stacked: a drag or an arrow key stays until the save, and a
    -- session closed with no save goes back to where the card was.
    local function drag()
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 50, 60)
    end
    local function keepsDrag(label)
        listeners.KitnUI_PartyXP(true)
        drag()
        X.PartyCardVisibility()
        X.PartyCardRefresh(list, 2, true)
        eq(card.point[1], "TOPLEFT", label .. ": a redraw leaves a dragged card on its new point")
        eq(card.point[4], 50, label .. ": at its new spot")
        element.applyPos()
        eq(card.point[4], 50, label .. ": an apply leaves it there too")
        eq(element.noInitHook, true, label .. ": and EUI's position pass is left to that apply")
        element.savePos(nil, "CENTER", "CENTER", 50, 60)
        eq(card.point[1], "CENTER", label .. ": the save places it")
        listeners.KitnUI_PartyXP(false)
        eq(card.point[4], 50, label .. ": and it stays after closing")
        element.clearPos()
    end
    element.savePos(nil, "CENTER", "CENTER", 5, 6)
    keepsDrag("a saved spot")
    tickerOn = false
    X.PartyCardVisibility()
    keepsDrag("the first spot")
    tickerOn = true
    X.PartyCardVisibility()
    onTicker("its drag saved and cleared")

    element.savePos(nil, "CENTER", "CENTER", 5, 6)
    listeners.KitnUI_PartyXP(true)
    drag()
    element.applyPos()
    eq(card.point[1], "TOPLEFT", "an apply leaves a dragged card with a saved spot alone")
    listeners.KitnUI_PartyXP(false)
    eq(element.noInitHook, false, "closing hands the card back to EUI's position pass")
    eq(card.point[1], "CENTER", "a session closed with no save goes back to its point")
    eq(card.point[4], 5, "and to its spot")
    element.clearPos()
    X.PartyCardVisibility()
    onTicker("its spot cleared again")

    -- An apply in a session follows a visibility run's rule: a card on the screen
    -- stays, and one whose spot was cleared is worked out again.
    listeners.KitnUI_PartyXP(true)
    methods.GetLeft = function() return 33 end
    element.applyPos()
    eq(card.point[4], 11, "an apply leaves a stacked card where the session put it")
    element.clearPos()
    element.applyPos()
    eq(card.point[4], 33, "a cleared spot: an apply reads its rect again")
    methods.GetLeft = function() return 11 end
    listeners.KitnUI_PartyXP(false)
    onTicker("an apply in a session, then closed")
    listeners.KitnUI_PartyXP(true)
    X.PartyCardStop()
    eq(element.noInitHook, false, "a card stopped in a session hands back EUI's position pass")
    X.PartyCardApply()
    onTicker("and its next apply stacks it")

    -- A spec layout banks "never moved" and gets it back, so a spot saved in one
    -- layout stays out of another that never moved the card.
    local spotNever = element.loadRawPos()
    eq(spotNever.neverMoved, true, "a layout: a stacked card reads as never moved")
    element.savePos(nil, "CENTER", "CENTER", 9, 10)
    local spotMoved = element.loadRawPos()
    eq(spotMoved.x, 9, "a layout: a moved card gives its spot")
    spotMoved.rawPos, spotMoved.w = true, 264
    element.saveRawPos(nil, spotNever)
    eq(settings.xpPartyPos, nil, "a layout: never moved clears the spot")
    onTicker("a layout: never moved")
    element.saveRawPos(nil, spotMoved)
    eq(settings.xpPartyPos and settings.xpPartyPos.x, 9, "a layout: its spot comes back")
    eq(settings.xpPartyPos and settings.xpPartyPos.w, nil, "a layout: without the layout's own fields")
    eq(card.point[4], 9, "a layout: and the card goes to it")
    listeners.KitnUI_PartyXP(true)
    element.saveRawPos(nil, spotNever)
    eq(card.point[2], _G.UIParent, "a layout in a session: never moved stays on the screen")
    eq(card.point[4], 11, "a layout in a session: at the card's rect")
    element.saveRawPos(nil, spotMoved)
    eq(card.point[4], 9, "a layout in a session: its spot places a held card")
    element.saveRawPos(nil, spotNever)
    listeners.KitnUI_PartyXP(false)
    onTicker("a layout in a session, then closed")

    listeners.KitnUI_PartyXP(true)
    element.savePos(nil, "CENTER", "CENTER", 7, 8)
    eq(card.point[4], 7, "Unlock Mode: a save goes to its spot")
    listeners.KitnUI_PartyXP(false)
    eq(card.point[4], 7, "and it stays there after closing")
    element.clearPos()
    X.PartyCardVisibility()
    methods.GetLeft, methods.GetTop = nil, nil
    listeners.KitnUI_PartyXP(true)
    onTicker("Unlock Mode with an unreadable rect")
    listeners.KitnUI_PartyXP(false)

    X.TickerFrame = tickerReal
    settings.xpPartyCard = nil
    X.PartyCardApply()
end

check(X.LiveXPWidget() == nil, "no XP bar yet: no live widget")
check(type(X.CARD_BACKGROUNDS) == "table" and X.CARD_BACKGROUNDS.card ~= nil, "the card shares the ticker's backgrounds")

---------------------------------------------------------------------------------
-- The party path's world
---------------------------------------------------------------------------------

local LE_HOME, LE_INSTANCE = 1, 2
_G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = LE_HOME, LE_INSTANCE
local group = { home = false, instance = false, raid = false }
local units = {}
local me = { level = 10, xp = 100, max = 1000 }
local rosterReads = 0
local chat = { sends = {}, prefixes = 0, prefixResult = 0, result = 0, locked = false, raises = false }

_G.IsInRaid = function() return group.raid end
_G.IsInGroup = function(category)
    if category == LE_HOME then return group.home end
    if category == LE_INSTANCE then return group.instance end
    return group.home or group.instance
end
_G.GetNormalizedRealmName = function() return "Realm" end
_G.UnitExists = function(u)
    rosterReads = rosterReads + 1
    return units[u] ~= nil
end
_G.UnitInPartyIsAI = function(u) return units[u] ~= nil and units[u].ai == true end
_G.UnitIsPlayer = function(u) return units[u] ~= nil and units[u].ai ~= true end
_G.UnitIsConnected = function(u) return units[u] ~= nil and units[u].online ~= false end
_G.UnitFullName = function(u)
    if u == "player" then return "Tester", "Realm" end
    local p = units[u]
    if not p then return nil end
    if p.secretName then return SECRET, SECRET end
    return p.name, p.realm
end
_G.UnitClass = function(u)
    if u == "player" then return "Mage", "MAGE" end
    local p = units[u]
    if not p then return nil end
    if p.secretName then return SECRET, SECRET end
    return p.class, p.class
end
_G.UnitLevel = function(u)
    if u == "player" then return me.level end
    return units[u] and units[u].level
end
_G.UnitXP = function() return me.xp end
_G.UnitXPMax = function() return me.max end
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function()
        chat.prefixes = chat.prefixes + 1
        return chat.prefixResult
    end,
    SendAddonMessage = function(prefix, text, channel)
        if chat.raises then error("refused") end
        chat.sends[#chat.sends + 1] = { prefix = prefix, text = text, channel = channel }
        return chat.result
    end,
    InChatMessagingLockdown = function() return chat.locked end,
}

local loginQueues = 0
local whenKnown = ns.EUIWhenLoginKnown
ns.EUIWhenLoginKnown = function(fn)
    loginQueues = loginQueues + 1
    return whenKnown(fn)
end

-- The card's last refresh, kept on the way through.
local lastRows, lastN, lastWanted, refreshes
refreshes = 0
local refreshReal = X.PartyCardRefresh
X.PartyCardRefresh = function(rows, n, wanted)
    lastRows, lastN, lastWanted = rows, n, wanted
    refreshes = refreshes + 1
    return refreshReal(rows, n, wanted)
end

local function rowOf(name)
    for i = 1, lastN or 0 do
        if lastRows[i].name == name then return lastRows[i] end
    end
    return nil
end

-- Runs each timer still waiting, once. A Lua error in a callback is a failure.
local function fire()
    local due = {}
    for _, t in ipairs(timers) do
        if not t.canceled and not t.fired then due[#due + 1] = t end
    end
    for _, t in ipairs(due) do
        t.fired = true
        local done, why = pcall(t.fn)
        check(done, "a timer callback runs without a Lua error", why)
    end
end

local function waiting()
    local n = 0
    for _, t in ipairs(timers) do
        if not t.canceled and not t.fired then n = n + 1 end
    end
    return n
end

local partyFrame

local function ev(event, ...)
    local done, why = pcall(partyFrame.scripts.OnEvent, partyFrame, event, ...)
    check(done, event .. " runs without a Lua error", why)
end

local function eventList()
    local names = {}
    for e in pairs(partyFrame.events) do names[#names + 1] = e end
    table.sort(names)
    return table.concat(names, ",")
end

local function member(name, class, level)
    return { name = name, class = class, level = level }
end

local function join(...)
    units = {}
    for i = 1, select("#", ...) do units["party" .. i] = select(i, ...) end
    group.home = true
    ev("GROUP_ROSTER_UPDATE")
end

local function reset()
    X.PartyStop()
    units = {}
    group.home, group.instance, group.raid = false, false, false
    me.level, me.xp, me.max = 10, 100, 1000
    chat.sends, chat.result, chat.locked, chat.raises = {}, 0, false, false
    for k in pairs(settings) do
        if k:find("^xpParty") then settings[k] = nil end
    end
end

local function say(text, sender, channel, prefix)
    ev("CHAT_MSG_ADDON", prefix or "KitnUIXP", text, channel or "PARTY", sender or "Mirelle-Realm")
end

---------------------------------------------------------------------------------
-- What each state costs
---------------------------------------------------------------------------------

do
    -- At max level with every display off: nothing, however many applies run.
    me.level = 90
    local frameCount = #frames
    X.PartyApply()
    X.PartyApply()
    X.PartyApply()
    eq(#frames, frameCount, "at max, displays off: no frame")
    eq(#chat.sends, 0, "at max, displays off: no message")
    eq(chat.prefixes, 0, "at max, displays off: no prefix")
    eq(waiting(), 0, "at max, displays off: no timer")
    eq(loginQueues, 1, "the login read is queued once")

    -- Below max with Share My XP off and no display: the same.
    me.level = 10
    settings.xpPartyShare = false
    X.PartyApply()
    eq(#frames, frameCount, "Share off, no display: no frame")
    settings.xpPartyShare = nil

    -- Below max, solo, by default: one frame watching for a group.
    X.PartyApply()
    eq(#frames, frameCount + 1, "below max, solo: one frame")
    partyFrame = frames[#frames]
    eq(eventList(), "GROUP_ROSTER_UPDATE", "below max, solo: one event")
    eq(waiting(), 0, "below max, solo: no timer")
    eq(#chat.sends, 0, "below max, solo: no message")

    -- Reaching max level alone has no event of its own: the watcher stays until
    -- the next apply or roster change, and either ends it.
    me.level = 90
    eq(eventList(), "GROUP_ROSTER_UPDATE", "solo, reached max: the watcher stays")
    X.PartyApply()
    eq(eventList(), "", "solo, reached max: an apply ends it")
    me.level = 10
    X.PartyApply()
    me.level = 90
    join(member("Mirelle", "MAGE", 58))
    eq(eventList(), "", "solo, reached max: joining a party ends it")
    eq(waiting(), 0, "solo, reached max: with no timer")
    eq(#chat.sends, 0, "solo, reached max: and no message")
    reset()
    X.PartyApply()

    -- A prefix the client refuses goes no further, until it is held.
    chat.prefixResult = 3
    join(member("Mirelle", "MAGE", 58))
    eq(waiting(), 0, "a refused prefix: nothing is armed")
    fire()
    eq(#chat.sends, 0, "a refused prefix: nothing is sent")
    chat.prefixResult = 0
    ev("GROUP_ROSTER_UPDATE")
    eq(waiting(), 1, "a prefix held late: it arrives as if entering")
    fire()
    eq(chat.sends[1] and chat.sends[1].text, "R", "a prefix held late: it asks")
    reset()

    -- Joining a party shares.
    X.PartyApply()
    join(member("Mirelle", "MAGE", 58), member("Dornak", "WARRIOR", 90))
    local has = eventList()
    for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "UNIT_LEVEL", "UNIT_CONNECTION", "UNIT_NAME_UPDATE",
        "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN" }) do
        check(has:find(e, 1, true), "in a party, sharing: registered " .. e)
    end
    check(not has:find("ADDON_RESTRICTION", 1, true), "in a party, sharing: no restriction event")
    eq(waiting(), 1, "joining arms one slot")
    fire()
    eq(chat.sends[1] and chat.sends[1].text, "R", "the first message asks")
    eq(chat.sends[1] and chat.sends[1].channel, "PARTY", "on PARTY")
    eq(chat.sends[1] and chat.sends[1].prefix, "KitnUIXP", "with the prefix")
    eq(waiting(), 1, "the report takes the next slot")
    fire()
    local kind, level, cur, total = X.PartyLogic.ParseMessage(chat.sends[2] and chat.sends[2].text)
    eq(kind, "report", "the second message reports")
    eq(level, 10, "the level")
    eq(cur, 100, "the XP")
    eq(total, 1000, "and the total")
    eq(waiting(), 0, "then no timer while idle")

    -- Leaving unregisters the party set.
    units = {}
    group.home = false
    ev("GROUP_ROSTER_UPDATE")
    eq(eventList(), "GROUP_ROSTER_UPDATE", "leaving: back to one event")
    eq(lastN, 0, "leaving: no rows")

    -- A raid is as if solo, and its roster traffic reads no roster.
    group.home, group.raid = true, true
    units = { party1 = member("Mirelle", "MAGE", 58) }
    rosterReads = 0
    ev("GROUP_ROSTER_UPDATE")
    eq(eventList(), "GROUP_ROSTER_UPDATE", "in a raid: one event")
    eq(rosterReads, 0, "in a raid: a roster event reads no roster")
    fire()
    group.raid = false

    -- Followers alone count as solo.
    local follower = member("Brann", "WARRIOR", 80)
    follower.ai = true
    local before = #chat.sends
    join(follower)
    eq(eventList(), "GROUP_ROSTER_UPDATE", "followers only: one event")
    fire()
    eq(#chat.sends, before, "followers only: nothing is sent")
    settings.xpPartyCard = true
    X.PartyApply()
    eq(lastWanted, false, "followers only: the card stays hidden")
    settings.xpPartyCard = nil

    -- A follower beside a player has no row.
    join(follower, member("Mirelle", "MAGE", 58))
    eq(rowOf("Brann"), nil, "a follower has no row")
    check(rowOf("Mirelle") ~= nil, "beside a player who does")

    -- Share off with no display drops everything.
    settings.xpPartyShare = false
    X.PartyApply()
    eq(eventList(), "", "Share off, no display: no event")
    eq(waiting(), 0, "Share off, no display: no timer")
    reset()

    -- A display at max with an all-max party hears nothing.
    me.level = 90
    settings.xpPartyCard = true
    X.PartyApply()
    eq(eventList(), "GROUP_ROSTER_UPDATE", "a display on at max, solo: one event")
    local atMax = member("Dornak", "WARRIOR", 90)
    join(atMax)
    check(not eventList():find("CHAT_MSG_ADDON", 1, true), "a display at max, an all-max party: no messages heard")
    check(not eventList():find("PLAYER_XP_UPDATE", 1, true), "and no XP events")
    fire()
    eq(#chat.sends, 0, "and nothing sent")
    eq(lastWanted, false, "and the card hidden: nobody is below max")

    -- A member below max moves it to listening, which asks and never reports.
    units.party2 = member("Mirelle", "MAGE", 58)
    ev("GROUP_ROSTER_UPDATE")
    check(eventList():find("CHAT_MSG_ADDON", 1, true), "a member below max: messages heard")
    eq(lastWanted, true, "and the card shows")
    fire()
    eq(chat.sends[1] and chat.sends[1].text, "R", "it asks")
    fire()
    eq(#chat.sends, 1, "and never reports")
    say("R", "Mirelle-Realm")
    eq(waiting(), 0, "and a request sets no report")
    say("1 58 500 1000", "Mirelle-Realm")
    eq(rowOf("Mirelle").view.kind, "data", "it hears a report")

    -- That member reaching max moves it back.
    units.party2.level = 90
    ev("UNIT_LEVEL", "party2")
    check(not eventList():find("CHAT_MSG_ADDON", 1, true), "the member reaching max: no messages heard")
    eq(lastWanted, false, "and the card hides")
    reset()

    -- A level-up that reads the old level is read again one slot later, in every
    -- mode with a level event, sharing or not.
    settings.xpPartyShare = false
    settings.xpPartyCard = true
    me.level = 89
    X.PartyApply()
    join(member("Dornak", "WARRIOR", 90))
    eq(lastWanted, true, "a display below max, an all-max party: the card shows")
    ev("PLAYER_LEVEL_UP", 90)
    eq(waiting(), 1, "a level-up arms one slot to read the level again")
    me.level = 90
    fire()
    eq(lastWanted, false, "which finds max level and hides the card")
    check(not eventList():find("PLAYER_XP_UPDATE", 1, true), "and leaves the XP events")
    eq(waiting(), 0, "with nothing waiting")
    eq(#chat.sends, 0, "and no message")
    reset()

    -- Share off with a display on, below max: hears, asks, sends no XP.
    settings.xpPartyShare = false
    settings.xpPartyCard = true
    X.PartyApply()
    join(member("Mirelle", "MAGE", 58))
    check(eventList():find("PLAYER_XP_UPDATE", 1, true), "Share off, a display on: XP events for the player's row")
    fire()
    fire()
    eq(#chat.sends, 1, "Share off, a display on: one message")
    eq(chat.sends[1] and chat.sends[1].text, "R", "which carries no XP")
    me.xp = 200
    ev("PLAYER_XP_UPDATE")
    eq(waiting(), 0, "Share off: XP arms nothing")
    check(rowOf("Tester").view.text:find("20.0", 1, true), "and the player's row still moves")
    reset()

    -- XP gain off, in a party: no sharing until it is back on.
    local xpOff = true
    _G.IsXPUserDisabled = function() return xpOff end
    X.PartyApply()
    join(member("Mirelle", "MAGE", 58))
    fire()
    eq(#chat.sends, 0, "XP gain off: nothing is sent")
    check(eventList():find("ENABLE_XP_GAIN", 1, true), "XP gain off: it listens for the change")
    xpOff = false
    ev("ENABLE_XP_GAIN")
    fire()
    fire()
    eq(#chat.sends, 2, "XP gain back on: it asks and reports")
    xpOff = true
    ev("DISABLE_XP_GAIN")
    me.xp = 300
    ev("PLAYER_XP_UPDATE")
    eq(waiting(), 0, "XP gain off again: XP arms nothing")
    _G.IsXPUserDisabled = function() return false end
    reset()
end

---------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------

do
    X.PartyApply()
    join(member("Mirelle", "MAGE", 58))
    fire()
    fire()
    chat.sends = {}

    -- A burst merges.
    me.xp = 200
    ev("PLAYER_XP_UPDATE")
    me.xp = 250
    ev("PLAYER_XP_UPDATE")
    me.xp = 300
    ev("PLAYER_XP_UPDATE")
    eq(waiting(), 1, "a burst arms one slot")
    fire()
    eq(#chat.sends, 1, "a burst sends once")
    eq(select(2, X.PartyLogic.ParseMessage(chat.sends[1].text)), 10, "the level")
    eq(select(3, X.PartyLogic.ParseMessage(chat.sends[1].text)), 300, "with the newest XP")
    eq(waiting(), 0, "then nothing waits")

    -- An unchanged reading sends nothing.
    ev("PLAYER_XP_UPDATE")
    fire()
    eq(#chat.sends, 1, "an unchanged reading sends nothing")

    -- A join and a request each report.
    units.party2 = member("Dornak", "WARRIOR", 90)
    ev("GROUP_ROSTER_UPDATE")
    fire()
    eq(#chat.sends, 2, "a join reports")
    say("R", "Dornak-Realm")
    fire()
    eq(#chat.sends, 3, "a report request reports")
    say("R", "Stranger-Realm")
    eq(waiting(), 0, "a request from a non-member does nothing")

    -- An instance group changes the channel.
    group.instance = true
    ev("GROUP_ROSTER_UPDATE")
    fire()
    fire()
    eq(chat.sends[#chat.sends].channel, "INSTANCE_CHAT", "an instance group sends on INSTANCE_CHAT")
    eq(chat.sends[#chat.sends - 1].text, "R", "and the new channel asks again")
    for _, send in ipairs(chat.sends) do
        check(send.channel ~= "RAID", "never on RAID")
    end
    group.instance = false
    ev("GROUP_ROSTER_UPDATE")
    fire()
    fire()
    chat.sends = {}

    -- A secret reading sends nothing.
    local xpReal = _G.UnitXP
    _G.UnitXP = function() return SECRET end
    say("R", "Dornak-Realm")
    fire()
    eq(#chat.sends, 0, "a secret XP sends nothing")
    _G.UnitXP = xpReal

    -- A raised send error is caught.
    chat.raises = true
    say("R", "Dornak-Realm")
    fire()
    eq(#chat.sends, 0, "a raised send error sends nothing")
    chat.raises = false

    -- Max level, read at the event or only at the flush.
    me.xp = 900
    ev("PLAYER_XP_UPDATE")
    me.level = 90
    fire()
    eq(#chat.sends, 0, "a flush that finds max level sends nothing")
    check(not eventList():find("PLAYER_XP_UPDATE", 1, true), "and leaves sharing")
    reset()

    X.PartyApply()
    join(member("Mirelle", "MAGE", 58))
    fire()
    fire()
    chat.sends = {}
    me.level = 90
    ev("PLAYER_LEVEL_UP", 90)
    check(not eventList():find("PLAYER_XP_UPDATE", 1, true), "a level-up to max leaves sharing")
    eq(waiting(), 0, "with nothing waiting")
    fire()
    eq(#chat.sends, 0, "and no final report")
    reset()
end

---------------------------------------------------------------------------------
-- Refusals
---------------------------------------------------------------------------------

do
    X.PartyApply()
    join(member("Mirelle", "MAGE", 58))
    fire()
    fire()
    chat.sends = {}

    -- A lock read before the send.
    chat.locked = true
    me.xp = 200
    ev("PLAYER_XP_UPDATE")
    fire()
    eq(#chat.sends, 0, "a known lock: no send is made")
    eq(waiting(), 0, "and no timer runs inside it")
    chat.locked = false
    eq(waiting(), 0, "a lock lifting alone arms nothing")
    me.xp = 300
    ev("PLAYER_XP_UPDATE")
    fire()
    eq(#chat.sends, 1, "the next XP gain sends")
    eq(select(3, X.PartyLogic.ParseMessage(chat.sends[1].text)), 300, "with the newest XP")

    -- A send refused with 11.
    chat.sends = {}
    chat.result = 11
    me.xp = 400
    ev("PLAYER_XP_UPDATE")
    fire()
    eq(#chat.sends, 1, "the send was made")
    eq(waiting(), 0, "and 11 arms no timer")
    chat.result = 0
    me.xp = 500
    say("R", "Mirelle-Realm")
    fire()
    eq(#chat.sends, 2, "a report request sends what was held")
    eq(select(3, X.PartyLogic.ParseMessage(chat.sends[2].text)), 500, "with the newest XP")

    -- A secret lock reads as locked.
    chat.sends = {}
    chat.locked = SECRET
    me.xp = 600
    ev("PLAYER_XP_UPDATE")
    fire()
    eq(#chat.sends, 0, "a secret lock reads as locked")
    chat.locked = false
    ev("PLAYER_XP_UPDATE")
    fire()
    chat.sends = {}

    -- A throttle tries the next slot.
    chat.result = 3
    me.xp = 700
    ev("PLAYER_XP_UPDATE")
    fire()
    eq(waiting(), 1, "a throttle tries the next slot")
    chat.result = 0
    fire()
    eq(#chat.sends, 2, "and goes")
    eq(waiting(), 0, "then nothing waits")

    -- Not in a group is dropped until the roster changes.
    chat.sends = {}
    chat.result = 5
    me.xp = 800
    ev("PLAYER_XP_UPDATE")
    fire()
    eq(waiting(), 0, "not in a group: nothing waits")
    chat.result = 0
    me.xp = 850
    ev("PLAYER_XP_UPDATE")
    eq(waiting(), 0, "and XP arms nothing")
    ev("GROUP_ROSTER_UPDATE")
    eq(waiting(), 1, "a roster change lifts it")
    fire()
    eq(chat.sends[#chat.sends].channel, "PARTY", "and it sends")
    reset()

    -- A listener's refused request comes back with the roster.
    settings.xpPartyShare = false
    settings.xpPartyCard = true
    X.PartyApply()
    chat.result = 5
    join(member("Mirelle", "MAGE", 58))
    fire()
    eq(waiting(), 0, "a listener refused as not in a group: nothing waits")
    chat.result = 0
    chat.sends = {}
    ev("GROUP_ROSTER_UPDATE")
    eq(waiting(), 1, "a roster change lifts it")
    fire()
    eq(chat.sends[1] and chat.sends[1].text, "R", "and it asks again")
    eq(waiting(), 0, "once")
    reset()

    -- What a flush finds for itself leaves no timer past a refusal. Each change
    -- below reaches the game with no event, so only the flush can find it.
    local CHANGES = {
        ["a new channel"] = function() group.instance = true end,
        ["a new member"] = function() units.party2 = member("Vess", "DRUID", 57) end,
        ["a new mode"] = function()
            settings.xpPartyShare = false
            settings.xpPartyCard = true
        end,
    }
    for name, change in pairs(CHANGES) do
        for _, refusal in ipairs({ "a lock", "result 11" }) do
            local label = name .. " under " .. refusal
            X.PartyApply()
            join(member("Mirelle", "MAGE", 58))
            fire()
            fire()
            chat.sends = {}
            me.xp = 200
            ev("PLAYER_XP_UPDATE")
            change()
            if refusal == "a lock" then chat.locked = true else chat.result = 11 end
            fire()
            eq(waiting(), 0, label .. ": no timer is left")
            local tried = #chat.sends
            eq(tried, refusal == "a lock" and 0 or 1, label .. ": one try at most")
            fire()
            eq(#chat.sends, tried, label .. ": and no retry")
            chat.locked, chat.result = false, 0
            eq(waiting(), 0, label .. ": the refusal lifting alone arms nothing")
            me.xp = 300
            ev("PLAYER_XP_UPDATE")
            eq(waiting(), 1, label .. ": the next trigger arms one slot")
            fire()
            check(#chat.sends > tried, label .. ": and sends what was held")
            reset()
        end
    end
end

---------------------------------------------------------------------------------
-- Receipt
---------------------------------------------------------------------------------

do
    X.PartyApply()
    local mirelle = member("Mirelle", "MAGE", 58)
    join(mirelle, member("Dornak", "WARRIOR", 90), member("Vess", "DRUID", 57))
    fire()
    fire()

    eq(lastRows[1].name, "Tester", "the player's row comes first")
    eq(lastRows[2].name, "Mirelle", "then the party in the game's order")
    eq(rowOf("Mirelle").view.kind, "nodata", "nothing heard: no data")
    eq(rowOf("Dornak").view.kind, "max", "a max-level member reads Max with no message")
    eq(rowOf("Vess").view.kind, "nodata", "a member with no addon: no data")

    say("1 58 912 1000")
    eq(rowOf("Mirelle").view.kind, "data", "a report fills the row")
    eq(rowOf("Mirelle").view.pct, 91.2, "at its percent")

    local marks = X.PartyMarkerList()
    eq(marks, nil, "markers off: no list")
    settings.xpPartyMarkers = true
    marks = X.PartyMarkerList()
    eq(marks.n, 1, "markers on: only a member with data")
    eq(marks[1].name, "Mirelle", "by name")
    eq(marks[1].pct, 91.2, "at the percent")
    eq(marks[1].level, 58, "and level")
    eq(marks[1].class, "MAGE", "and class")

    local count = refreshes
    say("1 58 912 1000")
    eq(refreshes, count, "a repeat report redraws nothing")

    local bad = {
        { "1 58 100 1000", "Tester-Realm" },
        { "1 58 100 1000", "Stranger-Realm" },
        { "1 58 100 1000", "Mirelle-Realm", "RAID" },
        { "1 58 100 1000", "Mirelle-Realm", "GUILD" },
        { "1 58 100 1000", "Mirelle-Realm", "PARTY", "OtherPrefix" },
        { "1 58 5000 1000", "Mirelle-Realm" },
        { "2 58 100 1000", "Mirelle-Realm" },
        { "garbage", "Mirelle-Realm" },
        { SECRET, "Mirelle-Realm" },
        { "1 58 100 1000", SECRET },
        { "1 58 100 1000", "Mirelle-Realm", SECRET },
        { "1 58 100 1000", "Mirelle-Realm", "PARTY", SECRET },
    }
    for i, m in ipairs(bad) do
        say(m[1], m[2], m[3], m[4])
        eq(rowOf("Mirelle").view.pct, 91.2, "a refused message changes nothing, case " .. i)
    end
    say("1 58 100 1000", "Mirelle-Realm", "INSTANCE_CHAT")
    eq(rowOf("Mirelle").view.pct, 10, "INSTANCE_CHAT is heard")
    say("1 58 912 1000")

    -- A level-up drops the old pair, and a lock keeps it.
    mirelle.level = 59
    ev("UNIT_LEVEL", "party1")
    eq(rowOf("Mirelle").view.kind, "nodata", "a member's level-up reads no data")
    check(rowOf("Mirelle").view.text:find("59", 1, true), "at the new level")
    eq(X.PartyMarkerList().n, 0, "and has no marker")
    say("1 59 50 1000")
    eq(rowOf("Mirelle").view.pct, 5, "until the next report")
    chat.locked = true
    mirelle.level = 60
    ev("UNIT_LEVEL", "party1")
    eq(rowOf("Mirelle").view.kind, "data", "inside a lock the row keeps the pair")
    check(rowOf("Mirelle").view.text:find("59", 1, true), "at its own level")
    chat.locked = false
    ev("UNIT_NAME_UPDATE", "party1")
    eq(rowOf("Mirelle").view.kind, "nodata", "a pair kept in a lock gives way at the next redraw")

    -- Offline
    say("1 60 5 1000")
    eq(X.PartyMarkerList().n, 1, "a member with data has a marker")
    mirelle.online = false
    ev("UNIT_CONNECTION", "party1", false)
    eq(rowOf("Mirelle").view.kind, "offline", "an offline member reads offline")
    eq(X.PartyMarkerList().n, 0, "and has none")
    mirelle.online = true
    ev("UNIT_CONNECTION", "party1", true)

    -- Leaving removes the heard value.
    say("1 60 5 1000")
    units.party1 = member("Dornak", "WARRIOR", 90)
    units.party2 = member("Vess", "DRUID", 57)
    units.party3 = nil
    ev("GROUP_ROSTER_UPDATE")
    eq(rowOf("Mirelle"), nil, "a member who left has no row")
    units.party3 = mirelle
    ev("GROUP_ROSTER_UPDATE")
    eq(rowOf("Mirelle").view.kind, "nodata", "and returns with nothing heard")

    -- Show Self
    settings.xpPartyShowSelf = false
    X.PartyApply()
    eq(rowOf("Tester"), nil, "Show Self off drops the player's row")
    settings.xpPartyShowSelf = nil
    X.PartyApply()

    -- A /reload's memory is empty: leaving the group clears everything.
    say("1 60 5 1000")
    reset()
    X.PartyApply()
    join(member("Mirelle", "MAGE", 60))
    eq(rowOf("Mirelle").view.kind, "nodata", "heard values do not outlast a stop")
    reset()
end

---------------------------------------------------------------------------------
-- Secret values
---------------------------------------------------------------------------------

do
    X.PartyApply()
    local mirelle = member("Mirelle", "MAGE", 58)
    join(mirelle, member("Vess", "DRUID", 57))
    say("1 58 912 1000")
    settings.xpPartyMarkers = true

    mirelle.secretName = true
    ev("UNIT_NAME_UPDATE", "party1")
    check(rowOf("Mirelle") ~= nil, "a shown row keeps what it showed")
    eq(rowOf("Mirelle").view.pct, 91.2, "with its value")
    eq(X.PartyMarkerList().n, 1, "and its marker")

    local fresh = member("Bram", "MAGE", 50)
    fresh.secretName = true
    units.party3 = fresh
    ev("GROUP_ROSTER_UPDATE")
    eq(lastN, 3, "a new unreadable member gets no row")
    say("1 57 100 1000", "Vess-Realm")
    eq(rowOf("Vess").view.pct, 10, "others still hear")

    -- The heard value of an unreadable member survives a prune.
    units.party2 = nil
    units.party3 = nil
    ev("GROUP_ROSTER_UPDATE")
    check(rowOf("Mirelle") ~= nil, "a roster that cannot be fully read keeps its row")
    mirelle.secretName = nil
    fresh.secretName = nil
    units.party2 = fresh
    ev("UNIT_NAME_UPDATE", "party2")
    check(rowOf("Bram") ~= nil, "a readable roster adds the new member")
    eq(rowOf("Mirelle").view.pct, 91.2, "and the kept value is still there")
    reset()
end

---------------------------------------------------------------------------------
-- Through the funnel
---------------------------------------------------------------------------------

do
    reset()
    -- With both bars off, an apply still reaches the party path.
    X.Apply()
    eq(eventList(), "GROUP_ROSTER_UPDATE", "both bars off: an apply starts the watcher")
    settings.xpPartyShare = false
    X.Apply()
    eq(eventList(), "", "both bars off, Share off: an apply stops it")
    settings.xpPartyShare = nil

    -- The tooltip's party rows, on the leveling branch and the max-level one.
    local tipRows = {}
    _G.GameTooltip.AddLine = function(_, text, r, g, b)
        tipRows[#tipRows + 1] = { left = text, r = r, g = g, b = b }
    end
    _G.GameTooltip.AddDoubleLine = function(_, left, right, lr, lg, lb, rr, rg, rb)
        tipRows[#tipRows + 1] = { left = left, right = right, r = lr, g = lg, b = lb, rr = rr, rg = rg, rb = rb }
    end
    settings.xpEnabled = true
    settings.xpPartyTooltip = true
    X.Apply()
    local bar = X.LiveXPWidget()
    check(bar ~= nil, "the XP bar is on")
    local function hover()
        tipRows = {}
        bar.frame.scripts.OnEnter(bar.frame)
        return tipRows
    end
    local function headerAt(shown)
        for i = 1, #shown do
            if shown[i].left == "Party" then return i end
        end
        return nil
    end
    local function noBlankAtEdges(shown, label)
        check(shown[1].left ~= " ", label .. ": no blank line at the top")
        check(shown[#shown].left ~= " ", label .. ": none at the end")
    end
    local function noPartyRows(label)
        local shown = hover()
        eq(headerAt(shown), nil, label .. ": no party rows")
        noBlankAtEdges(shown, label)
    end
    local function memberRow(row, name, status, r, label)
        eq(row and row.left, name, label .. ": the name on the left")
        eq(row and row.right, status, label .. ": the status on the right")
        eq(row and row.r, r, label .. ": the name's color")
    end

    noPartyRows("solo")
    local trio = { member("Mirelle", "MAGE", 58), member("Dornak", "WARRIOR", 90), member("Vess", "DRUID", 57) }
    join(trio[1], trio[2], trio[3])
    say("1 58 912 1000")
    local rows = hover()
    local at = headerAt(rows)
    check(at ~= nil, "in a party: a header")
    eq(rows[at - 1].left, " ", "in a party: a blank line above the header")
    check(rows[at - 2].left ~= " ", "in a party: one blank line")
    memberRow(rows[at + 1], "Mirelle", "Lv 58 91.2%", 0.1, "a member with data")
    memberRow(rows[at + 2], "Dornak", "Lv 90 Max", 0.4, "a member at max")
    memberRow(rows[at + 3], "Vess", "Lv 57 no data", 0.7, "a member with no data")
    eq(rows[at + 1].rr, 1, "a status reads white")
    eq(#rows, at + 3, "the party's rows end the tooltip")
    noBlankAtEdges(rows, "in a party")

    -- An offline status reads gray beside the class-colored name, and an unknown
    -- class reads white.
    local tipAway = member("Bram", "MAGE", 57)
    tipAway.online = false
    join(tipAway, member("Odd", "MONK", 57))
    rows = hover()
    at = headerAt(rows)
    memberRow(rows[at + 1], "Bram", "offline", 0.1, "an offline member")
    eq(rows[at + 1].rr, 0.5, "an offline status reads gray")
    eq(rows[at + 1].rg, 0.5, "in its green")
    eq(rows[at + 1].rb, 0.5, "and its blue")
    memberRow(rows[at + 2], "Odd", "Lv 57 no data", 1, "an unknown class")
    eq(rows[at + 2].g, 1, "reads white in its green")
    eq(rows[at + 2].b, 1, "and its blue")

    join(trio[1], trio[2], trio[3])
    say("1 58 912 1000")
    me.level = 90
    X.Apply()
    rows = hover()
    eq(rows[1].left, "Level 90", "at max level: its own rows")
    eq(rows[2].left, "Max Level", "at max level: together")
    eq(rows[3].left, " ", "at max level: a blank line above the party")
    eq(rows[4].left, "Party", "at max level: the header")
    eq(rows[#rows].left, "Vess", "at max level: the last member ends the tooltip")
    me.level = 10
    settings.xpPartyTooltip = nil
    X.Apply()
    noPartyRows("the switch off")
    settings.xpPartyTooltip = true
    group.raid = true
    ev("GROUP_ROSTER_UPDATE")
    noPartyRows("in a raid")
    group.raid = false
    settings.xpPartyTooltip = nil

    -- The live bar draws its ticks from a report and from a redraw.
    settings.xpPartyMarkers = true
    X.Apply()
    join(member("Mirelle", "MAGE", 58))
    check(bar.ptHost == nil, "no data yet: no host")
    say("1 58 912 1000")
    check(bar.ptHost ~= nil, "a report draws the tick")
    eq(bar.ptMarks[1].on, true, "and it shows")
    eq(bar.ptMarks[1].x, X.PartyLogic.MarkerX(91.2, bar.bw, 2, 1), "at the member's percent")
    me.xp = 500
    ev("PLAYER_XP_UPDATE")
    eq(bar.ptMarks[1].on, true, "the bar's own XP keeps it")
    settings.xpWidth = 800
    X.Apply()
    eq(bar.ptMarks[1].x, X.PartyLogic.MarkerX(91.2, bar.bw, 3, 1), "a resize moves it")
    settings.xpWidth = nil
    settings.xpPartyMarkers = nil
    X.Apply()
    eq(bar.ptMarks[1].on, false, "the switch off hides it")

    -- The card works with the XP bar off, and the markers do not draw.
    settings.xpEnabled = false
    settings.xpPartyCard = true
    settings.xpPartyMarkers = true
    X.Apply()
    eq(lastWanted, true, "the XP bar off: the card still wants to show")
    say("1 58 913 1000")
    eq(bar.ptMarks[1].on, false, "the XP bar off: a report draws no tick on it")
    settings.xpPartyMarkers = nil

    -- The reset stops it all, and the next apply starts again.
    X.Teardown()
    eq(eventList(), "", "the reset unregisters everything")
    eq(waiting(), 0, "and cancels the timer")
    eq(lastN, 0, "and clears the rows")
    settings.xpPartyCard = nil
    reset()
    settings.xpEnabled = nil
    X.Apply()
    eq(eventList(), "GROUP_ROSTER_UPDATE", "an apply after the reset watches again")
    reset()

    -- A rising cap reaches a player at max level through the XP bar's own events,
    -- and the party path has none of its own.
    local function setCap(cap)
        _G.GetMaxLevelForPlayerExpansion = function() return cap end
        _G.GetMaxPlayerLevel = function() return cap end
    end
    settings.xpEnabled = true
    me.level = 90
    X.Apply()
    eq(eventList(), "", "at max, the XP bar on: the party path has no event")
    local capHeard
    for _, f in ipairs(frames) do
        if f.events.MAX_EXPANSION_LEVEL_UPDATED then capHeard = f end
    end
    check(capHeard ~= nil, "the XP bar listens for the cap")
    for _, capEvent in ipairs({ "MAX_EXPANSION_LEVEL_UPDATED", "PLAYER_MAX_LEVEL_UPDATE" }) do
        setCap(100)
        capHeard.scripts.OnEvent(capHeard, capEvent)
        eq(eventList(), "GROUP_ROSTER_UPDATE", capEvent .. ": a cap that rises wakes it")
        setCap(90)
        capHeard.scripts.OnEvent(capHeard, capEvent)
        eq(eventList(), "", capEvent .. ": and a cap that falls ends it")
    end
    settings.xpEnabled = nil
    X.Apply()

    -- With the XP bar off nothing tells it, until the next apply.
    X.PartyApply()
    eq(eventList(), "", "at max, the XP bar off: no event")
    setCap(100)
    eq(eventList(), "", "a cap that rises is not noticed")
    X.PartyApply()
    eq(eventList(), "GROUP_ROSTER_UPDATE", "until the next apply")
    setCap(90)
    reset()

    -- The card under the real ticker, through the funnel, in one load.
    settings.xpEnabled, settings.xpTickerEnabled, settings.xpPartyCard = true, true, true
    X.Apply()
    local partyElement
    for _, e in ipairs(unlockList) do
        if e.key == "KitnUI_PartyXP" then partyElement = e end
    end
    local card = partyElement.getFrame()
    local ticker = X.TickerFrame()
    check(ticker ~= nil, "the funnel: the ticker's frame exists when the card places itself")
    eq(card.point[2], ticker, "the funnel: the card sits under it")
    settings.xpTickerEnabled = false
    X.Apply()
    eq(X.TickerFrame(), nil, "the ticker off: no frame to stack under")
    eq(card.point[2], _G.UIParent, "the ticker off: the card leaves it at once")
    eq(card.point[5], -40, "the ticker off: for its first spot")
    settings.xpTickerEnabled = true
    X.Apply()
    eq(card.point[2], ticker, "the ticker on again: back under it")
    settings.xpEnabled = false
    X.Apply()
    eq(X.TickerFrame(), nil, "the XP bar off counts as the ticker off")
    eq(card.point[5], -40, "the XP bar off: its first spot")
    settings.xpEnabled = true
    settings.xpPartyPos = { point = "CENTER", relPoint = "CENTER", x = 3, y = 4 }
    X.Apply()
    eq(card.point[4], 3, "a saved spot: the card stays on it")

    -- A reset or a profile switch clears the spot, and the next apply stacks.
    X.Teardown()
    settings.xpPartyPos = nil
    X.Apply()
    eq(card.point[2], ticker, "after a reset: back under the ticker")

    -- Party Markers moves only the preview's samples.
    settings.xpPartyMarkers = true
    X.Apply()
    eq(card.point[2], ticker, "Party Markers on: the live card still stacks")
    settings.xpPartyMarkers = nil
    X.Apply()

    -- A changed ticker font size reaches the card through the apply every setter
    -- runs, whichever comes first, the change or the rows, and with the ticker off.
    settings.xpTickerFontSize = 16
    X.Apply()
    join(member("Mirelle", "MAGE", 58))
    eq(card.kuiW, X.Math.TickerWidth(16), "the funnel: a font size changed before the rows reaches the card")
    settings.xpTickerFontSize = 20
    X.Apply()
    eq(card.kuiW, X.Math.TickerWidth(20), "the funnel: one changed on a drawn card reaches it at once")
    settings.xpTickerEnabled = false
    settings.xpTickerFontSize = 24
    X.Apply()
    eq(card.kuiW, X.Math.TickerWidth(24), "the funnel: and with the ticker off")
    settings.xpTickerFontSize = nil
    settings.xpEnabled, settings.xpTickerEnabled, settings.xpPartyCard = nil, nil, nil
    X.Apply()
    reset()
end

finish()
