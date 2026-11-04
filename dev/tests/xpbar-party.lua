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
    eq(card.kuiW, 264, "the card is its Width")
    eq(card.kuiW, X.Math.TickerWidth(X.Get("xpTickerFontSize")), "which starts as the ticker's width")
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
    eq(sample[3].view.kind, "max", "a member at Max")
    eq(sample[4].view.kind, "nodata", "and one with no data")
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

    -- The hold lasts only while the card stays stacked: each of these, inside a
    -- session, has the next placement stack it and read its rect again.
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
    reflattens("a link made and undone", function()
        EUI.IsAnchored = function(key) return key == "KitnUI_PartyXP" end
        EUI.ReapplyOwnAnchor = NOOP
        X.PartyCardVisibility()
        EUI.IsAnchored, EUI.ReapplyOwnAnchor = nil, nil
    end)
    reflattens("the ticker off and on", function()
        tickerOn = false
        X.PartyCardVisibility()
        tickerOn = true
    end)

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

finish()
