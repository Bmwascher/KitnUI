-- ╔══════════════════════════════════════════════════════════════╗
-- ║  topbar-unlock.lua                                           ║
-- ║  Purpose: Gate for the Top Bar and FPS readout in Unlock     ║
-- ║           Mode: a drag holds until saved, a saved spot and   ║
-- ║           a link stay as they are.                           ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/topbar-unlock.lua

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

local NOOP = function() end
local settings = {}
local combat = false
local frames, elements, listeners = {}, {}, {}

-- Records its points, and answers anything else with nothing.
local function NewFrame(name)
    local frame = { events = {}, scripts = {}, shown = true, point = false, pointCalls = 0 }
    frame.RegisterEvent = function(self, event) self.events[event] = true end
    frame.UnregisterEvent = function(self, event) self.events[event] = nil end
    frame.SetScript = function(self, script, fn) self.scripts[script] = fn end
    frame.ClearAllPoints = function(self) self.point = false end
    frame.SetPoint = function(self, ...)
        self.point = { ... }
        self.pointCalls = self.pointCalls + 1
    end
    frame.GetWidth = function() return 10 end
    frame.GetHeight = function() return 10 end
    frame.Show = function(self) self.shown = true end
    frame.Hide = function(self) self.shown = false end
    frame.IsShown = function(self) return self.shown end
    frame.CreateTexture = function() return NewFrame() end
    frame.CreateFontString = function() return NewFrame() end
    frame.CreateAnimationGroup = function() return NewFrame() end
    frame.CreateAnimation = function() return NewFrame() end
    if name then _G[name] = frame end
    frames[#frames + 1] = frame
    return setmetatable(frame, { __index = function() return NOOP end })
end

_G.format = string.format
_G.UIParent = NewFrame()
_G.STANDARD_TEXT_FONT = "font"
_G.InCombatLockdown = function() return combat end
_G.CreateFrame = function(_, name) return NewFrame(name) end
_G.CopyTable = function(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end
_G.C_Timer = { After = NOOP, NewTicker = function() return { Cancel = NOOP } end }
_G.RegisterStateDriver, _G.UnregisterStateDriver = NOOP, NOOP
_G.IsInInstance = function() return false end
_G.GetFramerate = function() return 60 end
_G.GetNetStats = function() return 0, 0, 20, 20 end

local EUI = { MakeUnlockElement = function(opts) return opts end }
function EUI.RegisterUnlockElements(_, list)
    for _, e in ipairs(list) do elements[e.key] = e end
end
function EUI.RegisterUnlockModeListener(_, owner, fn) listeners[owner] = fn end
_G.EllesmereUI = EUI

-- A fresh load of both files, through to the login that registers their elements.
local function boot()
    frames, elements, listeners = {}, {}, {}
    local loaded = {
        TopBar = { Elements = {}, ById = {}, DEFAULT_ORDER = { left = {}, centre = {}, right = {} } },
        EUI_DEFAULTS = {
            tbEnabled = true, tbOpacity = 100, tbAccentOpacity = 100, tbAccentOverride = false,
            tbAccentR = 1, tbAccentG = 1, tbAccentB = 1, tbIconSize = 20, tbSpacing = 14,
            tbClockSize = 12, tbSysSize = 12, tbFade = false, tbFadeTime = 0.25, tbTooltips = true,
            tbBackdrop = true, tbUse24h = false, tbServerTime = false,
        },
        EUISettings = function() return settings end,
        EUIRegisterReapply = NOOP,
        EUIPlain = function(v) return v end,
    }
    for _, file in ipairs({
        "KitnUI_EUI/XPBar/Math.lua", "KitnUI_EUI/TopBar/Bar.lua", "KitnUI_EUI/TopBar/Readouts.lua",
    }) do
        assert(loadfile(file))("KitnUI_EUI", loaded)
    end
    for _, f in ipairs(frames) do
        if f.events.PLAYER_LOGIN and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_LOGIN") end
    end
    return loaded
end

local function session(on)
    for _, fn in pairs(listeners) do fn(on) end
end

local function drag(target)
    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 50, 60)
end

local ns = boot()
local barElement, fpsElement = elements.KitnUI_TopBar, elements.KitnUI_TopBarFPS
check(barElement ~= nil, "the bar's element registers")
check(fpsElement ~= nil, "the readout's element registers")
ns.TopBar.Apply()
local bar, fps = ns.TopBar.Frame(), _G.KitnUITopBarSys

local function atDefault(label)
    eq(bar.point[1], "TOP", label .. ": the bar by its top")
    eq(bar.point[2], _G.UIParent, label .. ": on the screen")
    eq(bar.point[4], 0, label .. ": at its default")
    eq(fps.point[2], bar, label .. ": the readout on the bar")
    eq(fps.point[3], "BOTTOM", label .. ": under it")
end
atDefault("never moved")

-- A player's saved spots: read as they are, and left as they are.
local savedBar = { point = "CENTER", relPoint = "CENTER", x = 12, y = -34 }
local savedFps = { point = "CENTER", relPoint = "CENTER", x = 56, y = -78 }

local function useSaved()
    settings.tbPos, settings.tbSysPos = savedBar, savedFps
    ns.TopBar.Apply()
end

local function onSaved(label)
    eq(settings.tbPos, savedBar, label .. ": the bar's saved spot is the table it was")
    eq(savedBar.x, 12, label .. ": unchanged")
    eq(bar.point[1], "CENTER", label .. ": the bar by its center")
    eq(bar.point[4], 12, label .. ": at its X")
    eq(bar.point[5], -34, label .. ": and its Y")
    eq(settings.tbSysPos, savedFps, label .. ": the readout's saved spot is the table it was")
    eq(fps.point[1], "CENTER", label .. ": the readout by its center")
    eq(fps.point[4], 56, label .. ": at its X")
    eq(fps.point[5], -78, label .. ": and its Y")
end

useSaved()
onSaved("a saved spot")
session(true)
session(false)
onSaved("a session that touches nothing")

-- A drag lives only on the frame until the save, whatever else places it.
session(true)
eq(barElement.noInitHook, true, "session: EUI's position pass is left to the bar's apply")
eq(fpsElement.noInitHook, true, "session: and to the readout's")
drag(bar)
drag(fps)
ns.TopBar.Apply()
eq(bar.point[1], "TOPLEFT", "session: an Apply leaves a dragged bar where it is")
eq(fps.point[1], "TOPLEFT", "session: an Apply leaves a dragged readout where it is")
barElement.applyPos()
fpsElement.applyPos()
eq(bar.point[1], "TOPLEFT", "session: an apply leaves a dragged bar where it is")
eq(fps.point[1], "TOPLEFT", "session: an apply leaves a dragged readout where it is")
session(false)
eq(barElement.noInitHook, false, "closing hands the bar back to EUI's position pass")
eq(fpsElement.noInitHook, false, "closing hands the readout back too")
onSaved("a session closed with no save")

-- A save stores, and closing places.
session(true)
drag(bar)
drag(fps)
barElement.savePos(nil, "CENTER", "CENTER", 50, 60)
fpsElement.savePos(nil, "CENTER", "CENTER", 70, 80)
eq(bar.point[1], "TOPLEFT", "a save keeps the bar on its drag until closing")
session(false)
eq(bar.point[1], "CENTER", "closing puts the bar on its saved point")
eq(bar.point[4], 50, "at the saved spot")
eq(fps.point[4], 70, "and the readout at its own")
eq(settings.tbPos and settings.tbPos.x, 50, "the bar's spot is stored")
eq(settings.tbSysPos and settings.tbSysPos.x, 70, "and the readout's")
useSaved()

-- With no saved spot, closing with no save goes back to the default.
settings.tbPos, settings.tbSysPos = nil, nil
ns.TopBar.Apply()
atDefault("no saved spot")
session(true)
drag(bar)
drag(fps)
session(false)
atDefault("no saved spot, closed with no save")
eq(settings.tbPos, nil, "nothing stored for the bar")
eq(settings.tbSysPos, nil, "nothing stored for the readout")

-- A link owns a linked frame: closing puts it back on the link, and the link stays.
local reapplied = {}
_G.EllesmereUIDB = { unlockAnchors = { KitnUI_TopBarFPS = { target = "KitnUI_TopBar", side = "BOTTOM" } } }
EUI.IsAnchored = function(key) return key == "KitnUI_TopBarFPS" end
EUI.ReapplyOwnAnchor = function(key) reapplied[#reapplied + 1] = key end
local fpsCalls = fps.pointCalls
session(true)
session(false)
eq(reapplied[1], "KitnUI_TopBarFPS", "a linked readout goes back on its link")
eq(#reapplied, 1, "and nothing else does")
eq(fps.pointCalls, fpsCalls, "and it takes no point of its own")
eq(_G.EllesmereUIDB.unlockAnchors.KitnUI_TopBarFPS.target, "KitnUI_TopBar", "and the link stays")
reapplied = {}
EUI.IsAnchored = function(key) return key == "KitnUI_TopBar" end
local barCalls = bar.pointCalls
session(true)
session(false)
eq(reapplied[1], "KitnUI_TopBar", "a linked bar goes back on its link")
eq(bar.pointCalls, barCalls, "and takes no point of its own")
EUI.IsAnchored, EUI.ReapplyOwnAnchor, _G.EllesmereUIDB = nil, nil, nil
useSaved()

-- The bar parents secure buttons, so a close in combat places it when combat ends.
session(true)
drag(bar)
combat = true
session(false)
eq(bar.point[1], "TOPLEFT", "closing in combat leaves the bar for later")
eq(barElement.noInitHook, false, "closing in combat still hands it back")
combat = false
for _, f in ipairs(frames) do
    if f.events.PLAYER_REGEN_ENABLED and f.scripts.OnEvent then f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED") end
end
onSaved("combat over")

-- A spec layout reads a saved spot as it is stored, banks "never moved" and gets
-- it back. EUI calls applyPos straight after each write, as these do.
for _, case in ipairs({
    { barElement, "tbPos", bar, 12 },
    { fpsElement, "tbSysPos", fps, 56 },
}) do
    local elem, key, target, savedX = case[1], case[2], case[3], case[4]
    local spotSaved = elem.loadRawPos()
    eq(spotSaved.x, savedX, key .. ": a layout reads the saved spot as it is stored")
    eq(spotSaved.neverMoved, nil, key .. ": with no flag")
    eq(settings[key].x, savedX, key .. ": and reading it changes nothing")
    settings[key] = nil
    local spotNever = elem.loadRawPos()
    eq(spotNever.neverMoved, true, key .. ": nothing saved reads as never moved")
    elem.savePos(nil, "CENTER", "CENTER", 9, 10)
    elem.saveRawPos(nil, spotNever)
    elem.applyPos()
    eq(settings[key], nil, key .. ": never moved clears a spot saved in another layout")
    eq(target.point[1], "TOP", key .. ": and the frame goes to its default")
    spotSaved.rawPos, spotSaved.w = true, 100
    elem.saveRawPos(nil, spotSaved)
    elem.applyPos()
    eq(settings[key].x, savedX, key .. ": its spot comes back")
    eq(settings[key].w, nil, key .. ": without the layout's own fields")
    eq(target.point[4], savedX, key .. ": and the frame goes to it")
    session(true)
    drag(target)
    elem.saveRawPos(nil, spotNever)
    elem.applyPos()
    eq(target.point[1], "TOPLEFT", key .. ": in a session a layout's write waits for closing")
    session(false)
    eq(target.point[1], "TOP", key .. ": and closing places it")
    elem.saveRawPos(nil, spotSaved)
    elem.applyPos()
end

-- A bar first made during a session is placed once, then held.
do
    settings.tbPos, settings.tbSysPos = nil, nil
    local again = boot()
    session(true)
    again.TopBar.Apply()
    local late = again.TopBar.Frame()
    eq(late.point[1], "TOP", "a bar first made in a session is placed")
    drag(late)
    again.TopBar.Apply()
    eq(late.point[1], "TOPLEFT", "and then held")
    session(false)
    eq(late.point[1], "TOP", "and closing places it again")
end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
