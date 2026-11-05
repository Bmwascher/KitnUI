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

_G.CreateFrame = function(kind, _, parent)
    local f = Obj(kind)
    f.parent = parent
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
local accentFn
local EUI = {
    Lite = { NewDB = function() return { profile = {} } end, _dbRegistry = {} },
    RegisterVisibilityUpdater = function(fn) updaters[fn] = true end,
    UnregisterVisibilityUpdater = function(fn) updaters[fn] = nil end,
    RegisterMouseoverTarget = NOOP,
    UnregisterMouseoverTarget = NOOP,
    EvalVisibility = function() return true end,
    MakeUnlockElement = function(opts) return opts end,
    RegAccent = function(entry)
        accents = accents + 1
        accentFn = entry.fn
    end,
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
-- Below max level sharing makes a frame of its own: xpbar-party.lua checks each
-- of its states. This file reads a level 10 character for the bars' own checks.
ns.EUISettings().xpPartyShare = false
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

-- The page builder itself with both bars off, against stubbed widgets. It
-- builds only the selected bar's sections, and the search prebuild builds
-- both; its one script hook goes on the faction view's Pinned dropdown, a
-- control of the options window.
local page = { hooks = {}, headers = {}, headerAt = {}, rows = {}, cogs = {}, texts = {}, full = {}, mounts = 0 }
do
    local function Control()
        local c = Obj("Control")
        c.HookScript = function(_, name, fn) page.hooks[#page.hooks + 1] = { name = name, fn = fn } end
        return c
    end
    -- Every word the page shows the player: labels, tooltips, buttons, choices.
    local function Shown(text)
        if type(text) == "string" then page.texts[#page.texts + 1] = text end
    end
    local function Touch(cfg)
        if type(cfg) ~= "table" then return end
        Shown(cfg.text)
        Shown(cfg.tooltip)
        Shown(cfg.buttonText)
        if type(cfg.values) == "table" then
            for _, label in pairs(cfg.values) do Shown(label) end
        end
        for _, key in ipairs({ "getValue", "disabled" }) do
            if type(cfg[key]) == "function" then
                local done, err = pcall(cfg[key])
                if not done and not page.touchErr then page.touchErr = key .. ": " .. tostring(err) end
            end
        end
    end
    EUI.Widgets = {
        SectionHeader = function(_, _parent, text, y)
            local f = Obj("Frame")
            f.GetPoint = function() return "TOPLEFT", nil, "TOPLEFT", 0, y end
            page.headers[#page.headers + 1] = text
            page.headerAt[text] = f
            Shown(text)
            return f, 20
        end,
        DualRow = function(_, _parent, _y, left, right)
            Touch(left)
            Touch(right)
            local row = { _leftRegion = { _control = Control() }, _rightRegion = { _control = Control() } }
            if type(right) == "table" and right.text then page.rows[right.text] = row end
            if type(left) == "table" and left.text then
                page.rows[left.text] = row
                page.full[left.text] = right == nil
                if left.text == "Bar" then page.barValues = left.values end
            end
            return row, 30
        end,
    }
    EUI.BuildInlineCog = function(rgn, opts)
        page.cogs[#page.cogs + 1] = { rgn = rgn, opts = opts }
        Shown(opts and opts.title)
        Shown(opts and opts.disabledTooltip)
        for _, row in ipairs(opts and opts.rows or {}) do Shown(row.label) end
    end
    function EUI.SetContentHeader(_, builder)
        page.mounts = page.mounts + 1
        builder(Obj("Frame"), 800)
    end
end
local function buildPage(label)
    page.hooks, page.headers, page.headerAt, page.rows, page.cogs, page.touchErr = {}, {}, {}, {}, {}, nil
    page.texts, page.full = {}, {}
    local height
    ok, why = pcall(function() height = ns.EUIPages["XP Bar"](Obj("Frame"), -10) end)
    check(ok, label .. ": the page builds", why)
    check(type(height) == "number" and height > 10, label .. ": it returns its height", height)
    check(page.touchErr == nil, label .. ": every control reads its value and state", page.touchErr)
end
local function has(text)
    for _, h in ipairs(page.headers) do
        if h == text then return true end
    end
    return false
end
local function cogTitled(title)
    for _, c in ipairs(page.cogs) do
        if c.opts and c.opts.title == title then return c end
    end
    return nil
end
-- The first word on the page a player would read as "faction", or nil.
local function factionWord()
    for _, t in ipairs(page.texts) do
        if t:lower():find("faction", 1, true) then return t end
    end
    return nil
end
local aftersAtPage = afters

buildPage("page, XP view")
eq(page.mounts, 1, "page, XP view: it mounts the preview header once")
check(has("XP BAR") and has("XP DISPLAY") and has("XP TOOLTIP") and has("SESSION"), "page, XP view: the XP bar's sections")
check(has("FRAME") and has("FILL") and has("TEXT") and has("SIZE") and has("DIVIDERS") and not has("XP APPEARANCE"),
    "page, XP view: the appearance in five sections")
check(not has("REPUTATION SOURCE") and not has("REPUTATION DISPLAY"), "page, XP view: no faction section")
check(has("POSITION"), "page, XP view: the position line")
eq(factionWord(), nil, "page, XP view: no word on the page reads faction")
check(page.rows["Reset Session on Reload"] ~= nil and page.rows["Reset Session on Reload"] == page.rows["Mute /played in Chat"],
    "page, XP view: the two session switches share a row")
eq(page.full["Reset XP Session Now"], true, "page, XP view: Reset XP Session Now has a row of its own")
eq(page.full["Position: use EUI Unlock Mode"], true, "page, XP view: the Unlock Mode line has a row of its own")
check(page.rows.Bar ~= nil, "page, XP view: without the header's picker the page carries its own")
check(page.barValues ~= nil and page.barValues == X.BAR_V, "page, XP view: its picker reads the shared labels")
eq(#page.hooks, 0, "page, XP view: no script hook")
eq(#frames, previewFrames, "page, XP view: no frame beyond the preview's own")
eq(#page.cogs, 9, "page, XP view: a cogwheel on the amount, on each around-text and on the effects' four")
local amountCog, levelCog = cogTitled("Amount Position"), cogTitled("Time This Level")
check(amountCog ~= nil and amountCog.rgn == (page.rows["Amount Position"] or {})._leftRegion,
    "page, XP view: the amount's cogwheel sits on Amount Position")
eq(amountCog and #amountCog.opts.rows, 2, "page, XP view: the amount's cogwheel holds X Offset and Y Offset")
check(levelCog ~= nil and levelCog.rgn == (page.rows["Time This Level"] or {})._leftRegion,
    "page, XP view: an around-text's cogwheel sits on its switch")
eq(levelCog and #levelCog.opts.rows, 3, "page, XP view: an around-text's cogwheel holds Position, X Offset and Y Offset")
eq(levelCog and levelCog.opts.rows[1].type, "dropdown", "page, XP view: the position first")
check(levelCog ~= nil and type(levelCog.opts.disabled) == "function" and type(levelCog.opts.disabledTooltip) == "string",
    "page, XP view: the cogwheel grays out, with its reason, while its text is off")
check(page.rows["Time This Level Position"] == nil, "page, XP view: no separate around-text position row")

X.SelectBar("fb")
buildPage("page, faction view")
check(has("REPUTATION BAR") and has("REPUTATION VISIBILITY") and has("REPUTATION SOURCE") and has("REPUTATION DISPLAY")
    and has("FRAME") and has("DIVIDERS"), "page, faction view: the reputation bar's sections")
check(not has("XP DISPLAY") and not has("SESSION"), "page, faction view: no XP section")
eq(factionWord(), nil, "page, faction view: every label reads reputation, none faction")
eq(page.full["Position: use EUI Unlock Mode"], true, "page, faction view: the Unlock Mode line has a row of its own")
eq(#page.hooks, 1, "page, faction view: one script hook")
eq(page.hooks[1] and page.hooks[1].name, "OnMouseDown", "page, faction view: on the Pinned dropdown's press")
if page.hooks[1] then
    ok, why = pcall(page.hooks[1].fn)
    check(ok, "page, faction view: a press on the Pinned dropdown runs", why)
end
eq(#page.cogs, 5, "page, faction view: a cogwheel on each text position and on the effects' three")
local nameCog = cogTitled("Name Position")
check(nameCog ~= nil and nameCog.rgn == (page.rows["Name Position"] or {})._leftRegion,
    "page, faction view: the name's cogwheel sits on Name Position")
eq(nameCog and #nameCog.opts.rows, 2, "page, faction view: it holds X Offset and Y Offset")
local factionFrames = #frames
buildPage("page, faction view again")
eq(#frames, factionFrames, "page, faction view: a rebuild creates no frame")

-- Fill Color stays usable under Standing Color: it fills the reputations
-- that have no standing color.
do
    local dualRow, fillColor = EUI.Widgets.DualRow, nil
    EUI.Widgets.DualRow = function(w, parent, y, left, right)
        if type(right) == "table" and right.text == "Fill Color" then fillColor = right end
        return dualRow(w, parent, y, left, right)
    end
    ns.EUISettings().fbFillMode = "standing"
    buildPage("page, faction view, Standing Color")
    EUI.Widgets.DualRow = dualRow
    check(fillColor ~= nil, "page, faction view: the Fill Color row is built")
    local off = fillColor and fillColor.disabled
    eq(type(off) == "function" and off() or false, false, "page, faction view: Fill Color is usable under Standing Color")
    local tip = fillColor and fillColor.tooltip
    check(type(tip) == "string" and tip:find("no standing color", 1, true) ~= nil,
        "page, faction view: Fill Color's tooltip names the reputations with no standing color")
    ns.EUISettings().fbFillMode = nil
end

EUI.IsSearchPrebuild = function() return true end
buildPage("page, search prebuild")
check(has("XP DISPLAY") and has("REPUTATION SOURCE"), "page, search prebuild: both bars' sections, so search finds every row")
eq(factionWord(), nil, "page, search prebuild: no word search lists reads faction")
EUI.IsSearchPrebuild = nil
X.SelectBar("xp")

eq(#timers, 0, "page with both bars off: no timer")
eq(afters, aftersAtPage, "page with both bars off: no next-frame work")
eq(eventNames(), "PLAYER_ENTERING_WORLD,PLAYER_LOGIN", "page with both bars off: only Core's boot events")
check(next(updaters) == nil, "page with both bars off: no visibility updater")
eq(unlocks, 0, "page with both bars off: no Unlock Mode element")
eq(accents, 0, "page with both bars off: no accent callback")

buildPage("page, XP view again")
local setCog = cogTitled("Amount Position")
if setCog then
    setCog.opts.rows[1].set(7)
    eq(ns.EUISettings().xpAmountOffX, 7, "page, XP view: the amount's X Offset is saved")
    eq(setCog.opts.rows[1].get(), 7, "page, XP view: and read back")
    ns.EUISettings().xpAmountOffX = nil
end

-- A click on a part of the preview scrolls to the row that sets it, then
-- glows it.
check(type(X.NavigateToSetting) == "function", "the page publishes its navigation")
if type(X.NavigateToSetting) == "function" then
    local scrolled, glowed, pending
    local realAfter = _G.C_Timer.After
    EUI.SmoothScrollTo = function(v) scrolled = v end
    EUI.ELLESMERE_GREEN = { r = 0, g = 1, b = 0 }
    EUI.MakeSettingGlow = function() return function(target) glowed = target end end
    _G.C_Timer.After = function(_, fn) pending = fn end
    local function click(key)
        scrolled, glowed, pending = nil, nil, nil
        X.NavigateToSetting(key)
    end
    buildPage("navigation, XP view")
    click("center")
    local display = page.headerAt["XP DISPLAY"]
    local displayY = display and select(5, display:GetPoint(1))
    eq(scrolled, displayY and math.abs(displayY) - 40, "navigation: the amount scrolls to XP DISPLAY")
    check(pending ~= nil, "navigation: the glow waits a moment")
    if pending then pending() end
    eq(glowed, page.rows["Amount Position"] and page.rows["Amount Position"]._leftRegion,
        "navigation: the glow lands on Amount Position")
    click("sessionTime")
    local stale = pending
    buildPage("navigation, rebuilt")
    if stale then stale() end
    eq(glowed, nil, "navigation: a page built again before the glow plays glows nothing")
    local amountRow = page.rows["Amount Position"]
    EUI.IsSearchPrebuild = function() return true end
    buildPage("navigation, search prebuild")
    EUI.IsSearchPrebuild = nil
    click("center")
    if pending then pending() end
    eq(glowed, amountRow and amountRow._leftRegion, "navigation: the search prebuild leaves the rows on screen in place")
    EUI.BuildLessCommonExpander = function(_parent, y) return false, y end
    buildPage("navigation, dividers collapsed")
    check(page.rows.Dividers == nil, "navigation: the collapsed divider rows are not built")
    click("body")
    if pending then pending() end
    eq(glowed, page.headerAt.DIVIDERS, "navigation: a part whose rows are collapsed glows its section")
    EUI.BuildLessCommonExpander = nil
    _G.C_Timer.After = realAfter
    EUI.SmoothScrollTo, EUI.MakeSettingGlow, EUI.ELLESMERE_GREEN = nil, nil, nil
end

-- The preview's sample: Level 59 at 94,410 of 209,800, which is 45%, on any
-- client and at any level cap.
local realDraw = X.Draw
local drawn
X.Draw = function(w, view, data)
    if data and data.level then drawn = data end
    return realDraw(w, view, data)
end
local function sampleAt(cap)
    _G.GetMaxLevelForPlayerExpansion = function() return cap end
    drawn = nil
    X.PreviewRefresh()
    return drawn or {}
end
for _, cap in ipairs({ 90, 85, 60 }) do
    local s = sampleAt(cap)
    eq(s.level, "Level 59", "preview sample: Level 59 at a cap of " .. cap)
    eq(s.center, "94.4K / 209.8K (115.4K)", "preview sample: the amount in the default short style at a cap of " .. cap)
    eq(s.right, "45.0% (85.0%)", "preview sample: 45% earned at a cap of " .. cap)
end
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
eq(unlockList and unlockList[2] and unlockList[2].label, "KitnUI Reputation Bar",
    "XP bar on: the reputation bar's Unlock Mode element reads Reputation Bar")

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

---------------------------------------------------------------------------------
-- The preview: the selected bar, the picker and the clickable parts
---------------------------------------------------------------------------------

do
    local kinds = {}
    local drawBar = X.Draw
    X.Draw = function(w, view, data)
        kinds[#kinds + 1] = w and w.kind or "?"
        return drawBar(w, view, data)
    end
    local function drawnKinds()
        for i = #kinds, 1, -1 do kinds[i] = nil end
        X.PreviewRefresh()
        return table.concat(kinds, ",")
    end
    local selects = type(X.SelectedBar) == "function" and type(X.SelectBar) == "function"
        and type(X.SelectorShown) == "function"
    check(selects, "the preview publishes its bar selection")
    eq(drawnKinds(), "xp", "the XP bar selected: the preview draws it alone")
    if selects then
        eq(X.SelectedBar(), "xp", "the preview opens on the XP bar")
        X.SelectBar("fb")
        eq(X.SelectedBar(), "fb", "the faction bar selected")
        eq(drawnKinds(), "fb", "the faction bar selected: the preview draws it alone")
        X.SelectBar("nope")
        eq(X.SelectedBar(), "fb", "an unknown bar selects nothing")
        X.SelectBar("xp")
        check(not X.SelectorShown(), "without the host's dropdown helper the header holds no picker")

        local picked
        local plainHeight = X.BuildPreviewHeader(Obj("Frame"), 800)
        EUI.BuildDropdownControl = function(_parent, _width, _level, values, order, getValue, setValue)
            picked = { values = values, order = order, get = getValue, set = setValue }
            return _G.CreateFrame("Button")
        end
        local before = #frames
        local pickHeight = X.BuildPreviewHeader(Obj("Frame"), 800)
        check(X.SelectorShown(), "the bar picker: the header holds it")
        eq(picked and table.concat(picked.order, ","), "xp,fb,tk", "the bar picker: the XP bar, the faction bar, then the card")
        eq(picked and picked.values.fb, "Reputation Bar", "the bar picker: names the reputation bar")
        check(picked ~= nil and picked.values == X.BAR_V and picked.order == X.BAR_O, "the bar picker: reads the shared labels")
        eq(picked and picked.get(), "xp", "the bar picker: reads the selection")
        if picked then picked.set("fb") end
        eq(X.SelectedBar(), "fb", "the bar picker: a pick selects the bar")
        if picked then picked.set("xp") end
        X.BuildPreviewHeader(Obj("Frame"), 800)
        eq(#frames, before + 1, "the bar picker: made once")
        eq(pickHeight - plainHeight, 56, "the bar picker: the header grows by its room")
        EUI.BuildDropdownControl = nil
    end

    local made = {}
    EUI.ELLESMERE_GREEN = { r = 0, g = 1, b = 0 }
    EUI.PP = { CreateBorder = NOOP }
    EUI.CreatePreviewHitOverlay = function(element, navigate, key, isText, level, opts)
        local btn = _G.CreateFrame("Button")
        made[#made + 1] = { key = key, btn = btn, element = element, navigate = navigate, isText = isText,
            level = level, parent = opts and opts.parent }
        return btn
    end
    ok, why = pcall(X.BuildPreviewHeader, Obj("Frame"), 800)
    check(ok, "clickable preview: the header builds", why)
    eq(#made, 15, "clickable preview: one overlay for each bar's frame, body, fill and texts")
    if #made > 0 then
        local madeOnce, framesOnce = #made, #frames
        ok, why = pcall(X.BuildPreviewHeader, Obj("Frame"), 800)
        check(ok, "clickable preview: a second mount builds", why)
        eq(#made, madeOnce, "clickable preview: a second mount makes no overlay")
        eq(#frames, framesOnce, "clickable preview: nor any frame")
        local byKey = {}
        for _, m in ipairs(made) do byKey[m.key] = byKey[m.key] or m end
        local function levelOf(key) return byKey[key] and byKey[key].level or 0 end
        check(levelOf("frame") < levelOf("body") and levelOf("body") < levelOf("fill") and levelOf("fill") < levelOf("rate"),
            "clickable preview: the frame's ring lowest, then the body, the fill and the texts")
        eq(byKey.rate and byKey.rate.isText, true, "clickable preview: a text's overlay is sized to its text")
        check(byKey.rate and byKey.rate.parent ~= nil, "clickable preview: an overlay hangs on its bar's frame")
        settings.xpShowRate = false
        X.PreviewRefresh()
        eq(byKey.rate and byKey.rate.btn.shown, false, "clickable preview: a text's overlay hides with its text")
        settings.xpShowRate = nil
        X.PreviewRefresh()
        eq(byKey.rate and byKey.rate.btn.shown, true, "clickable preview: and shows again with it")
        if byKey.center then
            ok, why = pcall(byKey.center.navigate, "center")
            check(ok, "clickable preview: a press runs", why)
        end
    end
    EUI.CreatePreviewHitOverlay, EUI.PP, EUI.ELLESMERE_GREEN = nil, nil, nil
    X.Draw = drawBar
end

-- A pick rebuilds the page, which keeps its scroll; the page then goes to
-- its top, so the player lands on the selected bar's first section.
do
    local calls = {}
    EUI.RefreshPage = function(_, force) calls[#calls + 1] = force == true and "refresh" or "refresh, not forced" end
    EUI.ScrollToTop = function() calls[#calls + 1] = "top" end
    local function pick(kind)
        for i = #calls, 1, -1 do calls[i] = nil end
        ok, why = pcall(X.SelectBar, kind)
        check(ok, "a pick of " .. kind .. " runs", why)
        return table.concat(calls, ",")
    end
    eq(pick("fb"), "refresh,top", "a pick of the faction bar rebuilds the page, then scrolls it to the top")
    eq(pick("fb"), "", "a pick of the bar already selected does nothing")
    eq(pick("nope"), "", "a pick of an unknown bar does nothing")
    EUI.ScrollToTop = nil
    eq(pick("xp"), "refresh", "without the host's scroll helper a pick still rebuilds the page")
    EUI.RefreshPage = nil
end

-- The reputation sample: Argent Dawn at Revered, 13,020 of 21,000, drawn
-- through the bar's own fill: Standing Color shows the client's Revered
-- color, Custom Color the Fill Color.
do
    local drawBar = X.Draw
    local rep
    X.Draw = function(w, view, data)
        if w and w.kind == "fb" then rep = data end
        return drawBar(w, view, data)
    end
    local function colorOf(d)
        return tostring(d.r) .. " " .. tostring(d.g) .. " " .. tostring(d.b)
    end
    local function drawRep()
        rep = nil
        X.PreviewRefresh()
        return rep or {}
    end
    local realColors = _G.FACTION_BAR_COLORS
    _G.FACTION_STANDING_LABEL7 = "Revered"
    _G.FACTION_BAR_COLORS = { [7] = { r = 0.1, g = 0.7, b = 0.2 } }
    settings.fbFillMode = "standing"
    X.SelectBar("fb")
    local repData = drawRep()
    eq(repData.left, "Argent Dawn - Revered - 62.0%", "reputation sample: Argent Dawn at Revered, 62%")
    eq(repData.right, "(13.0K / 21.0K)", "reputation sample: 13,020 of 21,000, short")
    eq(colorOf(repData), "0.1 0.7 0.2", "reputation sample: Standing Color fills it in the client's Revered color")
    settings.fbFillMode = "custom"
    eq(colorOf(drawRep()), "0.435 0.294 1", "reputation sample: Custom Color fills it in the Fill Color")
    settings.fbFillMode = "standing"
    _G.FACTION_BAR_COLORS = nil
    eq(colorOf(drawRep()), "0.435 0.294 1", "reputation sample: Standing Color without the client's colors falls back to the Fill Color")
    settings.fbFillMode = nil
    _G.FACTION_BAR_COLORS, _G.FACTION_STANDING_LABEL7 = realColors, nil
    X.SelectBar("xp")
    X.Draw = drawBar
end

-- Each kind's rank and total, on the one reused record
do
    local kind
    _G.C_Reputation = {
        GetFactionDataByID = function()
            return { name = "Test", reaction = 6, currentStanding = 4000, currentReactionThreshold = 3000, nextReactionThreshold = 9000 }
        end,
        IsFactionParagonForCurrentPlayer = function() return kind == "paragon" end,
        GetFactionParagonInfo = function() return 25000, 10000, nil, false end,
        IsMajorFaction = function() return kind == "renown" end,
    }
    _G.C_GossipInfo = {
        GetFriendshipReputation = function()
            if kind ~= "friendship" then return nil end
            return { friendshipFactionID = 5, standing = 700, reactionThreshold = 500, nextThreshold = 900, reaction = "Buddy" }
        end,
        GetFriendshipReputationRanks = function() return { currentLevel = 3 } end,
    }
    _G.C_MajorFactions = {
        GetMajorFactionData = function() return { renownLevel = 12, renownReputationEarned = 800, renownLevelThreshold = 2500 } end,
        HasMaximumRenown = function() return false end,
    }
    local function read(name)
        kind = name
        local rec = X.ResolveFaction("pinned", 5) or {}
        return rec.kind, rec.rank, rec.total
    end
    local k, rank, total = read("friendship")
    eq(k, "friendship", "faction reading: a friendship")
    eq(rank, 3, "faction reading: its rank is the friendship level")
    eq(total, 700, "faction reading: its total is the standing")
    k, rank, total = read("paragon")
    eq(k, "paragon", "faction reading: a paragon track")
    eq(rank, 2, "faction reading: its rank counts the rewards")
    eq(total, 25000, "faction reading: its total runs on")
    k, rank, total = read("renown")
    eq(k, "renown", "faction reading: a renown track")
    eq(rank, 12, "faction reading: its rank is the renown level")
    eq(total, 800, "faction reading: its total is the XP into that level")
    k, rank, total = read("standard")
    eq(k, "standard", "faction reading: a plain reputation")
    eq(rank, 6, "faction reading: its rank is the standing")
    eq(total, 4000, "faction reading: its total is the standing's value")
    _G.C_GossipInfo.GetFriendshipReputationRanks = function() return nil end
    local _, fallback = read("friendship")
    eq(fallback, 500, "faction reading: a friendship with no level falls back to its threshold")
    _G.C_Reputation, _G.C_GossipInfo, _G.C_MajorFactions = nil, nil, nil
end

---------------------------------------------------------------------------------
-- The effects on the live bars
---------------------------------------------------------------------------------

do
    local listener
    EUI.RegisterUnlockModeListener = function(_, _owner, fn) listener = fn end
    EUI.UnregisterUnlockModeListener = function() listener = nil end
    local xpNow = 100
    _G.UnitXP = function() return xpNow end

    local live
    local drawReal = X.Draw
    local liveDraws = 0
    X.Draw = function(w, view, data)
        if w.frame == xpFrame then
            live = w
            liveDraws = liveDraws + 1
        end
        return drawReal(w, view, data)
    end
    local levelPlays, gainPlays, passes, gainAmount = 0, 0, 0, nil
    local levelReal, gainReal, passReal = X.PlayLevelEffect, X.PlayGainEffect, X.PlayGain
    X.PlayLevelEffect = function(...)
        levelPlays = levelPlays + 1
        return levelReal(...)
    end
    X.PlayGainEffect = function(...)
        gainPlays = gainPlays + 1
        gainAmount = select(6, ...)
        return gainReal(...)
    end
    X.PlayGain = function(...)
        passes = passes + 1
        return passReal(...)
    end
    local function send(name, ...)
        ok, why = pcall(evFrame.scripts.OnEvent, evFrame, name, ...)
        check(ok, name .. " runs without a Lua error", why)
    end

    settings.xpEnabled = true
    ok, why = pcall(X.Apply)
    check(ok, "effects: an apply with the XP bar on runs", why)
    check(listener ~= nil, "effects: one Unlock Mode listener while a bar is on")
    check(live ~= nil, "effects: the live bar draws")
    eq(live and live.fxClip, nil, "effects: the first draw makes no effect frame while not ready")
    eq(evFrame.events.QUEST_TURNED_IN, true, "effects: default settings register QUEST_TURNED_IN")

    settings.xpGainQuestsOnly = false
    X.Apply()
    eq(evFrame.events.QUEST_TURNED_IN, nil, "effects: Quest Turn-Ins Only off does not")
    settings.xpGainQuestsOnly = nil
    settings.xpGainEffect = "off"
    X.Apply()
    eq(evFrame.events.QUEST_TURNED_IN, nil, "effects: a gain effect off does not")
    settings.xpGainEffect = nil
    _G.UnitLevel = function() return 90 end
    X.Apply()
    eq(evFrame.events.QUEST_TURNED_IN, nil, "effects: nor at max level when not already listening")
    _G.UnitLevel = function() return 11 end
    X.Apply()
    eq(evFrame.events.QUEST_TURNED_IN, true, "effects: back below max it does")

    send("PLAYER_XP_UPDATE")
    eq(gainPlays, 0, "effects: the first reading after an apply plays nothing")
    xpNow = 150
    send("PLAYER_XP_UPDATE")
    eq(gainPlays, 0, "effects: a kill plays nothing with Quest Turn-Ins Only on")
    send("QUEST_TURNED_IN", 1234, 50, 0)
    eq(gainPlays, 1, "effects: a quest after its reading plays")
    eq(gainAmount, 50, "effects: with the quest's amount")
    check(live and live.fxQuest ~= nil, "effects: the effect is active")
    eq(live and live.fxQuest == (live.fxSets and live.fxSets.wave), true, "effects: Energy Wave, the default")

    X.Apply()
    eq(live and live.fxQuest, nil, "effects: a settings apply stops it")

    send("QUEST_TURNED_IN", 1234, 50, 0)
    eq(gainPlays, 2, "effects: a quest before its reading plays at once")
    xpNow = 200
    send("PLAYER_XP_UPDATE")
    eq(gainPlays, 2, "effects: and its reading plays nothing more")
    X.Apply()
    xpNow = 250
    send("PLAYER_XP_UPDATE")
    send("QUEST_TURNED_IN", 1234, 0, 0)
    eq(gainPlays, 2, "effects: a quest with no XP plays nothing")

    settings.xpGainQuestsOnly = false
    X.Apply()
    xpNow = 300
    send("PLAYER_XP_UPDATE")
    eq(gainPlays, 3, "effects: with the switch off every gain plays")
    settings.xpGainQuestsOnly = nil

    settings.xpGainEffect = "off"
    X.Apply()
    local before = passes
    xpNow = 350
    send("PLAYER_XP_UPDATE")
    eq(gainPlays, 3, "effects: a gain effect off plays none")
    eq(passes, before + 1, "effects: the profession fill's pass runs on its own")
    settings.xpGainEffect = nil

    send("PLAYER_LEVEL_UP", 12)
    eq(levelPlays, 1, "effects: a level-up plays its effect")
    check(live and live.fxBusy ~= nil, "effects: and it runs")
    eq(live and live.fxBusy == (live.fxSets and live.fxSets.sweep), true, "effects: Sweep, the default")
    settings.xpLevelEffect = "off"
    X.Apply()
    send("PLAYER_LEVEL_UP", 13)
    eq(live and live.fxBusy, nil, "effects: and none with it off")
    settings.xpLevelEffect = nil

    settings.xpGainQuestsOnly = false
    X.Apply()
    xpNow = 375
    send("PLAYER_XP_UPDATE")
    check(live and live.fxBusy ~= nil, "effects: a gain is playing when Unlock Mode opens")
    if listener then listener(true) end
    eq(live and live.fxBusy, nil, "effects: opening Unlock Mode stops it")
    eq(X.UnlockActive, true, "effects: Unlock Mode is noted")
    xpNow = 400
    send("PLAYER_XP_UPDATE")
    eq(live and live.fxBusy, nil, "effects: Unlock Mode blocks a play")

    -- A drag lives only on the frame until the save.
    local placeFrame, placedCalls = X.PlaceFrame, 0
    X.PlaceFrame = function(...)
        placedCalls = placedCalls + 1
        return placeFrame(...)
    end
    X.ApplyVisibility()
    eq(placedCalls, 0, "unlock: a session's visibility run leaves placed frames where they are")
    unlockList[1].applyPos()
    eq(placedCalls, 0, "unlock: an apply leaves the XP bar where it is")
    eq(unlockList[1].noInitHook, true, "unlock: EUI's position pass is left to the XP bar's apply")
    eq(unlockList[2].noInitHook, true, "unlock: and to the Reputation bar's")
    eq(unlockList[3].noInitHook, true, "unlock: and to the ticker's")
    unlockList[1].savePos(nil, "CENTER", "CENTER", 3, 4)
    eq(placedCalls, 1, "unlock: a save places it")
    unlockList[1].clearPos()
    local drawsBefore = liveDraws
    if listener then listener(false) end
    eq(X.UnlockActive, false, "effects: leaving Unlock Mode is noted")
    check(liveDraws > drawsBefore, "effects: and redraws, which brings Ready Glow back")
    check(placedCalls > 1, "unlock: closing places the frames again")
    eq(unlockList[1].noInitHook, false, "unlock: closing hands the XP bar back to EUI's position pass")
    X.PlaceFrame = placeFrame
    settings.xpGainQuestsOnly = nil

    -- A spec layout banks each bar's "never moved" and gets it back.
    for spotIndex, spotKey in ipairs({ "xpPos", "fbPos" }) do
        local spotElem, spotHeld = unlockList[spotIndex], settings[spotKey]
        settings[spotKey] = nil
        local spotNever = spotElem.loadRawPos()
        eq(spotNever.neverMoved, true, spotKey .. ": a layout hears it never moved")
        spotElem.savePos(nil, "CENTER", "CENTER", 3, 4)
        local spotMoved = spotElem.loadRawPos()
        eq(spotMoved.x, 3, spotKey .. ": a layout hears its spot")
        spotElem.saveRawPos(nil, spotNever)
        eq(settings[spotKey], nil, spotKey .. ": never moved clears the spot")
        spotElem.saveRawPos(nil, spotMoved)
        eq(settings[spotKey] and settings[spotKey].x, 3, spotKey .. ": and its spot comes back")
        settings[spotKey] = spotHeld
    end

    -- A level whose completed quests cover the rest, for Ready Glow alone.
    local scan = X.ScanQuestXP
    settings.xpTooltip, settings.xpShowQuest, settings.xpShowCompRested = false, false, false
    X.Apply()
    eq(evFrame.events.QUEST_LOG_UPDATE, true, "effects: Ready Glow alone keeps the quest totals current")
    X.ScanQuestXP = function() return 5000, 0 end
    send("QUEST_LOG_UPDATE")
    fire()
    eq(live and live.fxReady and live.fxReady.on, true, "effects: Ready Glow starts when quests cover the level")
    X.ScanQuestXP = function() return 0, 0 end
    send("QUEST_LOG_UPDATE")
    fire()
    eq(live and live.fxReady and live.fxReady.on, false, "effects: and stops when they no longer do")
    X.ScanQuestXP = scan
    settings.xpTooltip, settings.xpShowQuest, settings.xpShowCompRested = nil, nil, nil

    -- The tooltip's rows in groups, for each order of quest rows: a blank line sits
    -- only between two groups that drew something.
    do
        local tipRows = {}
        _G.GameTooltip.AddLine = function(_, text) tipRows[#tipRows + 1] = text end
        _G.GameTooltip.AddDoubleLine = function(_, left) tipRows[#tipRows + 1] = left end
        local function hovered()
            tipRows = {}
            xpFrame.scripts.OnEnter(xpFrame)
            return table.concat(tipRows, ",")
        end
        local function withQuests(done, open)
            X.ScanQuestXP = function() return done, open end
            send("QUEST_LOG_UPDATE")
            fire()
            return hovered()
        end
        local function reads(text, part, label)
            check(text:find(part, 1, true) ~= nil, "tooltip: " .. label, text)
            check(text:sub(1, 8) == "Level 11", "tooltip: " .. label .. ", nothing above its first row", text)
            check(text:sub(-1) ~= " ", "tooltip: " .. label .. ", nothing below its last row", text)
        end
        X.Apply()
        reads(withQuests(0, 0), "Experience,Remaining, ,This session", "no quest rows, one blank line")
        reads(withQuests(5000, 7), "Remaining, ,Completed quests,Quests in progress, ,This session", "both quest rows")
        reads(withQuests(5000, 0), "Remaining, ,Completed quests, ,This session", "completed quests alone")
        reads(withQuests(0, 7), "Remaining, ,Quests in progress, ,This session", "quests in progress alone")
        reads(withQuests(0, 0), "Experience,Remaining, ,This session", "the quest rows gone again")
        X.ScanQuestXP = scan
        _G.IsResting = function() return true end
        reads(hovered(), "Remaining,Rested, ,This session", "the rested row in the first group")
        _G.IsResting = function() return false end
        _G.UnitLevel = function() return 90 end
        eq(hovered(), "Level 90,Max Level", "tooltip: at max level, its own rows with no blank line")
        _G.UnitLevel = function() return 11 end
        _G.GameTooltip.AddLine, _G.GameTooltip.AddDoubleLine = nil, nil
    end

    -- Two turn-ins close together, with each side first, play both gains.
    local gainsBefore = gainPlays
    X.Apply()
    send("QUEST_TURNED_IN", 1234, 50, 0)
    send("QUEST_TURNED_IN", 1235, 50, 0)
    xpNow = xpNow + 50
    send("PLAYER_XP_UPDATE")
    xpNow = xpNow + 50
    send("PLAYER_XP_UPDATE")
    eq(gainPlays, gainsBefore + 2, "effects: two quests before their readings play both")
    X.Apply()
    xpNow = xpNow + 50
    send("PLAYER_XP_UPDATE")
    xpNow = xpNow + 50
    send("PLAYER_XP_UPDATE")
    send("QUEST_TURNED_IN", 1234, 50, 0)
    send("QUEST_TURNED_IN", 1235, 50, 0)
    eq(gainPlays, gainsBefore + 4, "effects: two readings before their quests play both")

    -- A kill close to a turn-in, on either side, adds no play and no amount.
    gainsBefore = gainPlays
    X.Apply()
    xpNow = xpNow + 10
    send("PLAYER_XP_UPDATE")
    send("QUEST_TURNED_IN", 1234, 77, 0)
    xpNow = xpNow + 77
    send("PLAYER_XP_UPDATE")
    xpNow = xpNow + 10
    send("PLAYER_XP_UPDATE")
    eq(gainPlays, gainsBefore + 1, "effects: one play for a quest between two kills")
    eq(gainAmount, 77, "effects: with the quest's amount")

    -- A turn-in that levels plays beside the level effect, with either first; a
    -- level-up with no turn-in plays its effect alone.
    gainsBefore = gainPlays
    X.Apply()
    send("PLAYER_LEVEL_UP", 12)
    eq(gainPlays, gainsBefore, "effects: a level-up with no turn-in plays no gain")
    eq(live and live.fxQuest, nil, "effects: so its effect runs alone")
    send("QUEST_TURNED_IN", 1234, 5000, 0)
    eq(gainPlays, gainsBefore + 1, "effects: a turn-in after the level-up event plays")
    eq(gainAmount, 5000, "effects: with its amount")
    check(live and live.fxQuest ~= nil and live.fxBusy ~= nil, "effects: beside the level effect")
    X.Apply()
    send("QUEST_TURNED_IN", 1234, 5000, 0)
    send("PLAYER_LEVEL_UP", 12)
    eq(gainPlays, gainsBefore + 2, "effects: a turn-in before the level-up event plays")
    check(live and live.fxQuest ~= nil and live.fxBusy ~= nil, "effects: and the level effect leaves it running")

    -- Reaching max leaves one turn-in to hear, with the bar kept there, in each
    -- order of the level-up, the new level reading and the turn-in.
    gainsBefore = gainPlays
    X.Apply()
    _G.UnitLevel = function() return 90 end
    send("PLAYER_LEVEL_UP", 90)
    eq(evFrame.events.QUEST_TURNED_IN, true, "max level: the level-up leaves one turn-in to hear")
    send("QUEST_TURNED_IN", 1234, 5000, 0)
    eq(gainPlays, gainsBefore + 1, "max level: the quest that reached it plays")
    eq(gainAmount, 5000, "max level: with its amount")
    eq(evFrame.events.QUEST_TURNED_IN, nil, "max level: and nothing after it is heard")

    _G.UnitLevel = function() return 11 end
    X.Apply()
    _G.UnitLevel = function() return 91 end
    send("PLAYER_LEVEL_UP", 91)
    send("QUEST_TURNED_IN", 1234, 0, 0)
    eq(gainPlays, gainsBefore + 1, "max level: a turn-in with no XP plays nothing")
    eq(evFrame.events.QUEST_TURNED_IN, nil, "max level: and ends the listening too")

    _G.UnitLevel = function() return 11 end
    X.Apply()
    send("PLAYER_LEVEL_UP", 92)
    send("QUEST_TURNED_IN", 1234, 5000, 0)
    eq(gainPlays, gainsBefore + 2, "max level: a turn-in with the level still reading old plays")
    _G.UnitLevel = function() return 92 end
    send("QUEST_TURNED_IN", 1234, 5000, 0)
    eq(gainPlays, gainsBefore + 2, "max level: and it spent the listening, so the next plays nothing")
    eq(evFrame.events.QUEST_TURNED_IN, nil, "max level: which ends it")

    _G.UnitLevel = function() return 11 end
    X.Apply()
    _G.UnitLevel = function() return 93 end
    send("UPDATE_EXHAUSTION")
    eq(evFrame.events.QUEST_TURNED_IN, true, "max level: a new level reading before the level-up keeps listening")
    send("QUEST_TURNED_IN", 1234, 5000, 0)
    eq(gainPlays, gainsBefore + 3, "max level: and a turn-in before the level-up plays")
    send("PLAYER_LEVEL_UP", 93)
    eq(evFrame.events.QUEST_TURNED_IN, nil, "max level: and the level-up after it does not reopen")
    _G.UnitLevel = function() return 11 end

    -- With the switch off, a gain inside a level is its reading's, and any XP that
    -- crosses a level, kill or quest, plays the level effect alone.
    settings.xpGainQuestsOnly = false
    gainsBefore = gainPlays
    X.Apply()
    xpNow = xpNow + 77
    send("PLAYER_XP_UPDATE")
    eq(gainPlays, gainsBefore + 1, "switch off: a reading inside a level plays once")
    eq(gainAmount, 77, "switch off: with its rise")
    send("QUEST_TURNED_IN", 1234, 77, 0)
    eq(gainPlays, gainsBefore + 1, "switch off: and a stray quest event adds nothing")
    local xpBefore = xpNow
    X.Apply()
    gainsBefore = gainPlays
    xpNow = 60
    _G.UnitLevel = function() return 12 end
    send("PLAYER_XP_UPDATE")
    send("PLAYER_LEVEL_UP", 12)
    eq(gainPlays, gainsBefore, "switch off: XP across a level plays no gain")
    check(live and live.fxBusy ~= nil, "switch off: and plays the level effect")
    send("QUEST_TURNED_IN", 1234, 5000, 0)
    eq(gainPlays, gainsBefore, "switch off: nor does a stray quest event add one")
    eq(live and live.fxQuest, nil, "switch off: so the level effect runs alone")
    xpNow = xpBefore
    _G.UnitLevel = function() return 11 end
    settings.xpGainQuestsOnly = nil

    -- The reputation reading path
    local renown, standing, missing = 5, 100, false
    _G.C_Reputation = {
        GetFactionDataByID = function()
            if missing then return nil end
            return { name = "Test", reaction = 5, currentStanding = standing, currentReactionThreshold = 0, nextReactionThreshold = 3000 }
        end,
        IsMajorFaction = function() return true end,
        IsFactionParagonForCurrentPlayer = function() return false end,
    }
    _G.C_MajorFactions = {
        GetMajorFactionData = function()
            return { renownLevel = renown, renownReputationEarned = standing, renownLevelThreshold = 2500 }
        end,
        HasMaximumRenown = function() return false end,
    }
    settings.fbEnabled, settings.fbSource, settings.fbFactionID = true, "pinned", 5
    X.Apply()
    levelPlays, gainPlays = 0, 0
    send("UPDATE_FACTION")
    eq(levelPlays + gainPlays, 0, "reputation effects: the first reading after an apply plays nothing")
    renown, standing = 6, 0
    send("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 5, 6)
    eq(levelPlays, 1, "reputation effects: the renown event first plays the rank")
    send("UPDATE_FACTION")
    eq(levelPlays, 1, "reputation effects: and UPDATE_FACTION after it plays nothing more")
    renown = 7
    send("UPDATE_FACTION")
    eq(levelPlays, 2, "reputation effects: UPDATE_FACTION first plays the rank")
    send("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 5, 7)
    eq(levelPlays, 2, "reputation effects: and the renown event after it plays nothing more")
    standing = 40
    send("UPDATE_FACTION")
    eq(gainPlays, 1, "reputation effects: a rise is a gain")
    standing = 30
    send("UPDATE_FACTION")
    eq(gainPlays, 1, "reputation effects: a loss plays nothing")
    missing = true
    send("UPDATE_FACTION")
    missing, renown = false, 9
    send("UPDATE_FACTION")
    eq(levelPlays, 2, "reputation effects: a reading after no reputation only seeds")

    local fbFrame = unlockList[2].getFrame()
    check(fbFrame ~= nil, "reputation effects: the reputation bar exists")

    -- A hidden bar stops what it was playing.
    settings.xpGainQuestsOnly = false
    X.Apply()
    xpNow = xpNow + 50
    send("PLAYER_XP_UPDATE")
    check(live and live.fxBusy ~= nil, "effects: playing before the hide")
    xpFrame.scripts.OnHide(xpFrame)
    eq(live and live.fxBusy, nil, "effects: a hidden bar stops its effects")
    settings.xpGainQuestsOnly = nil

    if listener then listener(true) end
    settings.xpEnabled, settings.fbEnabled, settings.fbSource, settings.fbFactionID = false, false, nil, nil
    X.Apply()
    eq(listener, nil, "effects: both bars off leaves Unlock Mode's listeners")
    eq(X.UnlockActive, false, "effects: and clears its note")
    eq(unlockList[1].noInitHook, false, "effects: and hands the bars back to EUI's position pass")
    eq(evFrame.events.QUEST_TURNED_IN, nil, "effects: and unregisters QUEST_TURNED_IN")
    _G.C_Reputation, _G.C_MajorFactions = nil, nil
    X.Draw, X.PlayLevelEffect, X.PlayGainEffect, X.PlayGain = drawReal, levelReal, gainReal, passReal
    _G.UnitXP = function() return 100 end
    EUI.RegisterUnlockModeListener, EUI.UnregisterUnlockModeListener = nil, nil
end

-- Every new setting's default
for _, key in ipairs({
    "xpTickerEnabled", "xpTickerVisibility", "xpTickerHideResting", "xpTickerShowCurrent", "xpTickerHistoryRows",
    "xpTickerShowPlayed", "xpTickerShowPace", "xpTickerFont", "xpTickerOutline", "xpTickerFontSize", "xpTickerBackground",
    "xpGainEffect", "fbGainEffect", "xpGainQuestsOnly", "xpGainShowAmount", "fbGainShowAmount", "xpGainTextSize",
    "fbGainTextSize", "xpGainMatchBar", "fbGainMatchBar", "xpGainColorR", "xpGainColorG", "xpGainColorB", "fbGainColorR",
    "fbGainColorG", "fbGainColorB", "xpLevelEffect", "fbLevelEffect", "xpGlowSize", "fbGlowSize", "xpReadyGlow",
    "xpRestedStripes", "xpStripeSize", "xpTickerShowLine", "xpTickerGapBars",
}) do
    check(ns.EUI_DEFAULTS[key] ~= nil, "the default " .. key .. " exists")
end
eq(ns.EUI_DEFAULTS.xpStarSize, nil, "the star's size is not a setting")
eq(ns.EUI_DEFAULTS.xpTickerShowLine, true, "the ticker's XP Line is on by default")
eq(ns.EUI_DEFAULTS.xpTickerGapBars, true, "and so are its Gap Bars")

---------------------------------------------------------------------------------
-- The card through the funnel
---------------------------------------------------------------------------------

do
    settings.xpEnabled, settings.xpTickerEnabled = true, false
    ok, why = pcall(X.Apply)
    check(ok, "card off: an apply runs", why)
    local element = unlockList[3]
    eq(element and element.key, "KitnUI_XPTicker", "card: its Unlock element registers with the bars'")
    eq(element and element.noResize, true, "card: with no resize controls")
    eq(element and element.getFrame(), nil, "card off: no frame")
    settings.xpTickerEnabled = true
    ok, why = pcall(X.Apply)
    check(ok, "card on: an apply runs", why)
    local card = element and element.getFrame()
    check(card ~= nil, "card on: the card exists")
    eq(card and card.shown, true, "card on: and shows")
    settings.xpVisibility = "never"
    X.Apply()
    eq(card and card.shown, true, "card on: the XP bar's Visibility of Never leaves it showing")
    settings.xpVisibility = nil

    X.SessionStart("login")
    X.SessionPause(true)
    settings.xpTickerEnabled = false
    X.Apply()
    eq(X.SessionPaused(), false, "card off: a pause with no Start ends")
    eq(card and card.shown, false, "card off: and it hides")

    settings.xpTickerEnabled = true
    settings.xpEnabled, settings.fbEnabled = false, true
    X.Apply()
    eq(card and card.shown, false, "card: the XP bar off under the reputation bar hides it")
    settings.xpEnabled, settings.fbEnabled = true, false
    X.Apply()
    eq(card and card.shown, true, "card: and it returns with the XP bar")
    settings.xpEnabled = false
    X.Apply()
    eq(card and card.shown, false, "card: both bars off hides it")
    local tickerAccent, accentCalls = X.TickerAccent, 0
    X.TickerAccent = function() accentCalls = accentCalls + 1 end
    settings.xpFillStyle = "solid"
    if accentFn then accentFn() end
    eq(accentCalls, 1, "card: a new accent reaches it whatever the bar's fill style")
    X.TickerAccent, settings.xpFillStyle = tickerAccent, nil
    settings.xpTickerEnabled = nil

    local running, paused = {}, {}
    local function withTime(key)
        if key == "xpShowSessionTime" then return true end
        return X.Get(key)
    end
    X.XPView({ level = 10, cur = 1, max = 10, elapsed = 120, gained = 1 }, withTime, running)
    X.XPView({ level = 10, cur = 1, max = 10, elapsed = 120, gained = 1, paused = true }, withTime, paused)
    check(running.sessionTime ~= nil and running.sessionTime ~= paused.sessionTime,
        "paused: the session time carries a mark")

    -- Reaching max level, with the real reader and the real event path.
    local shownTime
    local drawForTime = X.Draw
    X.Draw = function(w, view, data)
        shownTime = data.sessionTime
        return drawForTime(w, view, data)
    end
    settings.xpEnabled, settings.xpShowSessionTime = true, true
    X.Apply()
    local onEvent = evFrame.scripts.OnEvent
    onEvent(evFrame, "PLAYER_LEVEL_UP", 12)
    X.SessionPause(true)
    eq(X.SessionPaused(), true, "reaching max level: paused on the way")
    local frozen = X.SessionGained()
    onEvent(evFrame, "PLAYER_LEVEL_UP", 90)
    eq(X.SessionPaused(), true, "reaching max level: a level-up with the level still reading old waits for its reading")
    _G.UnitLevel = function() return 90 end
    onEvent(evFrame, "PLAYER_XP_UPDATE")
    eq(X.SessionPaused(), false, "reaching max level: and its reading ends the pause")
    eq(X.SessionGained(), frozen, "reaching max level: with the XP still frozen")
    check(shownTime ~= nil and not shownTime:find("paused", 1, true),
        "reaching max level: and the bar stops saying paused")

    -- A level past the purchased limit that can still level, as a timerunner's.
    _G.GameRulesUtil = {
        IsPlayerAtEffectiveMaxLevel = function() return false end,
        CanShowExperienceBar = function() return true end,
    }
    _G.UnitLevel = function() return 91 end
    X.SessionPause(true)
    eq(X.SessionPaused(), true, "past the purchased limit: Pause works")
    onEvent(evFrame, "PLAYER_LEVEL_UP", 92)
    eq(X.SessionPaused(), true, "past the purchased limit: a level-up keeps the pause")
    X.SessionPause(false)
    X.SessionPause(true)
    eq(X.SessionPaused(), true, "past the purchased limit: Pause works after that level-up too")
    X.SessionPause(false)
    _G.GameRulesUtil, _G.UnitLevel = nil, function() return 11 end
    X.Draw = drawForTime
    settings.xpEnabled, settings.xpShowSessionTime = false, nil
    X.Apply()
end

---------------------------------------------------------------------------------
-- The preview: the sample card and playback
---------------------------------------------------------------------------------

do
    local cardShown, cardOut
    local drawCardReal = X.DrawCard
    X.DrawCard = function(card, view, data)
        cardShown, cardOut = card, data
        return drawCardReal(card, view, data)
    end
    local overlays = {}
    EUI.ELLESMERE_GREEN = { r = 0, g = 1, b = 0 }
    EUI.PP = { CreateBorder = NOOP }
    EUI.CreatePreviewHitOverlay = function(_element, navigate, key)
        local btn = _G.CreateFrame("Button")
        overlays[key] = { btn = btn, navigate = navigate }
        return btn
    end
    local navTo
    local navReal = X.NavigateToSetting
    X.NavigateToSetting = function(key) navTo = key end

    X.SelectBar("tk")
    eq(X.SelectedBar(), "tk", "sample card: the card can be selected")
    check(cardOut ~= nil, "sample card: it draws")
    eq(cardOut and cardOut.rate, "90.0K xp/hr", "sample card: the XP bar's rate")
    eq(cardOut and cardOut.ding, "Ding 1h 16m", "sample card: and its time to level")
    eq(cardOut and cardOut.arrow, "up", "sample card: with an arrow")
    eq(cardOut and cardOut.left[1], "Level 59", "sample card: the current level")
    eq(cardOut and cardOut.right[1], "20:00", "sample card: a 20-minute clock")
    eq(cardOut and cardOut.extra[1], "45%", "sample card: at 45%")
    eq(cardOut and cardOut.n, 6, "sample card: three completed levels, Played and the legend, by default")
    eq(cardOut and cardOut.left[2], "Level 58", "sample card: the newest completed level")
    eq(cardOut and cardOut.extra[2], "+7:05", "sample card: slower than the other characters")
    eq(cardOut and cardOut.extra[3], "-6:20", "sample card: faster than them")
    eq(cardOut and cardOut.extra[4], "-9:28|cffa8a8a8*|r", "sample card: a level only this character has, starred")
    eq(cardOut and cardOut.left[5], "Played", "sample card: Played after the levels")
    eq(cardOut and cardOut.extra[5], "vs account", "sample card: beside the main source")
    eq(cardOut and cardOut.extra[6], "* recent median 58:40", "sample card: and the legend last")
    check(cardOut and type(cardOut.share[1]) == "number", "sample card: the current level has its projected bar")
    settings.xpTickerHistoryRows = 2
    X.PreviewRefresh()
    eq(cardOut and cardOut.n, 4, "sample card: two levels on the slider drop the third and the legend")
    eq(cardOut and cardOut.extra[4], "vs account", "sample card: every shown level on account")
    settings.xpTickerHistoryRows = nil
    X.PreviewRefresh()
    eq(cardOut and cardOut.n, 6, "sample card: back to three, the legend returns")
    eq(cardOut and cardOut.extra[6], "* recent median 58:40", "sample card: naming the recent median again")
    settings.xpTickerShowCurrent = false
    X.PreviewRefresh()
    eq(cardOut and cardOut.extra[4], "vs account", "sample card: Current Level off keeps the footer on the shown levels")
    settings.xpTickerShowCurrent = nil
    X.PreviewRefresh()

    settings.xpTickerShowPace = true
    X.PreviewRefresh()
    eq(cardOut and cardOut.n, 7, "sample card: Pace shows with its switch")
    eq(cardOut and cardOut.left[7], "Pace", "sample card: on the last row")
    check(cardOut and cardOut.right[7] ~= "--", "sample card: with a sample character")
    eq(overlays.tkRow7 and overlays.tkRow7.btn.shown, true, "sample card: a shown row has its overlay")
    eq(overlays.tkRow8 and overlays.tkRow8.btn.shown, false, "sample card: a row not shown does not")
    settings.xpTickerShowPace = nil
    X.PreviewRefresh()
    eq(overlays.tkRow7 and overlays.tkRow7.btn.shown, false, "sample card: and its overlay goes with it")

    if overlays.tkBack then overlays.tkBack.navigate("tkBack") end
    eq(navTo, "tkBack", "sample card: the background leads to its own")
    if overlays.tkRow1 then overlays.tkRow1.navigate() end
    eq(navTo, "tkCurrent", "sample card: the first row leads to its own control")
    if overlays.tkRow5 then overlays.tkRow5.navigate() end
    eq(navTo, "tkPlayed", "sample card: a row leads to what it shows now")
    if overlays.tkValue1 then overlays.tkValue1.navigate() end
    eq(navTo, "tkCurrent", "sample card: a row's value leads where its label does")
    if overlays.tkValue5 then overlays.tkValue5.navigate() end
    eq(navTo, "tkPlayed", "sample card: on every row")
    for _, part in ipairs({ "tkTop", "tkDing", "tkArrow" }) do
        navTo = nil
        if overlays[part] then overlays[part].navigate() end
        eq(navTo, "tkTop", "sample card: the top line's " .. part .. " leads to the top line's control")
    end

    settings.xpTickerShowPace = true
    X.PreviewRefresh()
    eq(overlays.tkValue7 and overlays.tkValue7.btn.shown, true, "sample card: a shown row's value has its overlay")
    eq(overlays.tkValue8 and overlays.tkValue8.btn.shown, false, "sample card: a row not shown has none for its value")
    settings.xpTickerShowPace = nil
    eq(overlays.tkArrow and overlays.tkArrow.btn.shown, true, "sample card: the arrow has its overlay")
    local viewReal = X.TickerView
    X.TickerView = function(r, view, out)
        viewReal(r, view, out)
        out.arrow = nil
    end
    X.PreviewRefresh()
    eq(overlays.tkArrow and overlays.tkArrow.btn.shown, false, "sample card: an arrow not drawn has no overlay")
    X.TickerView = viewReal
    X.PreviewRefresh()
    eq(overlays.tkExtra2 and overlays.tkExtra2.btn.shown, true, "sample card: a level's gap has its overlay")
    navTo = nil
    if overlays.tkExtra2 then overlays.tkExtra2.navigate() end
    eq(navTo, "tkGapBars", "sample card: a gap leads to Gap Bars")
    navTo = nil
    if overlays.tkExtra5 then overlays.tkExtra5.navigate() end
    eq(navTo, "tkGapBars", "sample card: and so does the footer's source")
    navTo = nil
    if overlays.tkExtra1 then overlays.tkExtra1.navigate() end
    eq(navTo, "tkCurrent", "sample card: the current level's percent leads to Current Level")
    eq(overlays.tkLine and overlays.tkLine.btn.shown, true, "sample card: the XP line has its overlay")
    navTo = nil
    if overlays.tkLine then overlays.tkLine.navigate() end
    eq(navTo, "tkLine", "sample card: which leads to XP Line")
    settings.xpTickerShowLine, settings.xpTickerGapBars = false, false
    X.PreviewRefresh()
    eq(overlays.tkLine and overlays.tkLine.btn.shown, false, "sample card: no line, no overlay")
    eq(overlays.tkExtra2 and overlays.tkExtra2.btn.shown, false, "sample card: no gap, no overlay")
    settings.xpTickerShowLine, settings.xpTickerGapBars = nil, nil
    X.PreviewRefresh()

    local cardCount = #frames
    X.PreviewRefresh()
    eq(#frames, cardCount, "sample card: a redraw makes no frame")
    eq(X.PreviewPlay("gain"), nil, "sample card: a play with the card selected does nothing")

    -- With Party Markers on, the party card beside the ticker's sample and the sample
    -- XP bar under both. With it off, the party card under the ticker's sample.
    local drawnN, partyCard, barData, barWidget
    local drawParty, drawSample = X.DrawPartyCard, X.Draw
    X.DrawPartyCard = function(card, view, rows, n)
        partyCard, drawnN = card, n
        return drawParty(card, view, rows, n)
    end
    X.Draw = function(w, view, data)
        if w.kind == "xp" then barData, barWidget = data, w end
        return drawSample(w, view, data)
    end
    methods.SetPoint = function(self, point, rel, relPoint, x, y) self.pt = { point, rel, relPoint, x, y } end

    settings.xpPartyMarkers = true
    X.PreviewRefresh()
    eq(drawnN, 4, "party preview: four sample rows")
    eq(partyCard and partyCard.shown, true, "party preview: the card shows")
    eq(cardShown and cardShown.shown, true, "party preview: with the ticker's sample")
    eq(partyCard and partyCard.pt[2], cardShown, "party preview: beside it")
    eq(partyCard and partyCard.pt[3], "TOPRIGHT", "party preview: at its top right")
    eq(partyCard and partyCard.pt[5], 0, "party preview: with their tops aligned")
    local sideGap = partyCard and partyCard.pt[4] or 0
    check(sideGap > 0, "party preview: and a gap between them")
    eq(barWidget and barWidget.frame.shown, true, "party preview: the sample bar shows with Party Markers on")
    eq(barWidget and barWidget.ptMarks and barWidget.ptMarks[1].on, true, "party preview: with its tick")
    local pairWidth = cardShown.kuiW + sideGap + partyCard.kuiW
    eq(cardShown.pt[4], (X.Get("xpWidth") - pairWidth) / 2, "party preview: the two cards center as a pair over the bar")
    -- The bar clears the taller card, whichever that is.
    local function barBelowBoth(label)
        local top = math.max(cardShown.kuiH, partyCard.kuiH) + sideGap + (barWidget.above or 0)
        eq(barWidget.frame.pt[5], -top, "party preview: the bar below both, " .. label)
    end
    barBelowBoth("at the defaults")
    settings.xpPartyFontSize = 32
    X.PreviewRefresh()
    check(partyCard.kuiH > cardShown.kuiH, "party preview: a large party font makes the party card the taller")
    barBelowBoth("the party card taller")
    settings.xpPartyFontSize = nil
    settings.xpTickerFontSize = 32
    X.PreviewRefresh()
    check(cardShown.kuiH > partyCard.kuiH, "party preview: a large ticker font makes the ticker the taller")
    barBelowBoth("the ticker taller")
    eq(cardShown.pt[4], 0, "party preview: a pair wider than the bar starts at the left")
    settings.xpTickerFontSize = nil

    settings.xpPartyMarkers = false
    X.PreviewRefresh()
    eq(barWidget and barWidget.frame.shown, false, "party preview: the sample bar hides with Party Markers off")
    eq(cardShown.pt[4], 0, "party preview: and the cards fill the width")
    eq(partyCard and partyCard.pt[2], cardShown, "party preview: Party Markers off stacks the card on the ticker's sample")
    eq(partyCard and partyCard.pt[3], "BOTTOMLEFT", "party preview: at its bottom left")
    eq(partyCard and partyCard.pt[5], 0, "party preview: with no gap")
    settings.xpTickerFontSize = 20
    X.PreviewRefresh()
    eq(partyCard and partyCard.kuiW, X.Math.TickerWidth(20), "party preview: at Width 0 the card's sample follows the ticker's font size")
    settings.xpPartyWidth = 400
    X.PreviewRefresh()
    eq(partyCard and partyCard.kuiW, 400, "party preview: a set Width does not")
    settings.xpTickerFontSize, settings.xpPartyWidth = nil, nil
    settings.xpPartyMarkers = true
    X.PreviewRefresh()
    eq(barWidget and barWidget.frame.shown, true, "party preview: and returns")

    settings.xpPartyShowSelf = false
    X.PreviewRefresh()
    eq(drawnN, 3, "party preview: Show Self off drops a row")
    eq(overlays.pxName4 and overlays.pxName4.btn.shown, false, "party preview: and its overlay")
    settings.xpPartyShowSelf = nil
    X.PreviewRefresh()
    eq(overlays.pxName4 and overlays.pxName4.btn.shown, true, "party preview: which returns with it")

    if overlays.pxBack then overlays.pxBack.navigate("pxBack") end
    eq(navTo, "pxBack", "party preview: the background leads to its own")
    if overlays.pxName1 then overlays.pxName1.navigate() end
    eq(navTo, "pxFont", "party preview: a name leads to Party Font")
    if overlays.pxBar2 then overlays.pxBar2.navigate() end
    eq(navTo, "pxFill", "party preview: a bar leads to Party Fill")
    if overlays.pxText3 then overlays.pxText3.navigate() end
    eq(navTo, "pxSize", "party preview: a text leads to Party Font Size")

    local partyCount = #frames
    X.PreviewRefresh()
    eq(#frames, partyCount, "party preview: a redraw makes no frame")

    X.SelectBar("xp")
    eq(partyCard and partyCard.shown, false, "party preview: the card hides when a bar is selected")
    eq(barData and barData.markers, nil, "the XP view's preview draws no ticks")
    eq(barWidget and barWidget.ptMarks and barWidget.ptMarks[1].on, false, "and hides the sample's")
    settings.xpPartyMarkers = nil
    X.SelectBar("tk")
    methods.SetPoint = nil
    X.DrawPartyCard, X.Draw = drawParty, drawSample
    X.NavigateToSetting = navReal

    local bar
    local drawBar = X.Draw
    X.Draw = function(w, view, data)
        if w.kind == "xp" then bar = w end
        return drawBar(w, view, data)
    end
    X.SelectBar("xp")
    eq(cardShown and cardShown.shown, false, "playback: the card hides when a bar is selected")
    check(bar ~= nil, "playback: the XP bar draws")
    eq(bar and bar.fxReady and bar.fxReady.on, true, "playback: Ready Glow shows on the sample")
    settings.xpReadyGlow = false
    X.PreviewRefresh()
    eq(bar and bar.fxReady and bar.fxReady.on, false, "playback: while its switch is on")
    settings.xpReadyGlow = nil
    X.PreviewRefresh()

    X.PreviewPlay("gain")
    check(bar and bar.fxBusy ~= nil, "playback: Play Gain plays on the sample")
    X.SelectBar("fb")
    eq(bar and bar.fxBusy, nil, "playback: selecting another item stops it")
    eq(bar and bar.fxReady and bar.fxReady.on, false, "playback: and Ready Glow")
    X.SelectBar("xp")
    X.PreviewPlay("level")
    check(bar and bar.fxBusy ~= nil and bar.fxBusy.isLevel == true, "playback: Play Level-Up plays on the sample")
    local content = bar and bar.frame.parent
    check(content and content.scripts.OnHide ~= nil, "playback: the preview's content stops what plays when it hides")
    if content and content.scripts.OnHide then content.scripts.OnHide(content) end
    eq(bar and bar.fxBusy, nil, "playback: nothing plays once it hides")
    X.PreviewRestore()
    eq(bar and bar.fxReady and bar.fxReady.on, true, "playback: a cached revisit brings Ready Glow back")

    X.DrawCard, X.Draw = drawCardReal, drawBar
    EUI.CreatePreviewHitOverlay, EUI.PP, EUI.ELLESMERE_GREEN = nil, nil, nil
end

---------------------------------------------------------------------------------
-- The page's third view and the EFFECTS section
---------------------------------------------------------------------------------

do
    local function indexOf(text)
        for i, h in ipairs(page.headers) do
            if h == text then return i end
        end
        return nil
    end
    local function before(a, b)
        local ia, ib = indexOf(a), indexOf(b)
        return ia ~= nil and ib ~= nil and ia < ib
    end
    local function lastIndexOf(text)
        local last
        for i, h in ipairs(page.headers) do
            if h == text then last = i end
        end
        return last
    end

    buildPage("page, XP view with effects")
    check(has("EFFECTS"), "effects: the XP bar's page has the section")
    check(before("DIVIDERS", "EFFECTS"), "effects: after the appearance sections")
    check(before("EFFECTS", "XP TOOLTIP"), "effects: before XP TOOLTIP")
    check(page.rows["Gain Effect"] ~= nil and page.rows["Gain Effect"] == page.rows["Quest Turn-Ins Only"],
        "effects: Gain Effect and Quest Turn-Ins Only share a row")
    check(page.rows["Level-Up Effect"] ~= nil and page.rows["Level-Up Effect"] == page.rows["Show Amount Gained"],
        "effects: Level-Up Effect and Show Amount Gained share a row")
    check(page.rows["Ready Glow"] ~= nil and page.rows["Ready Glow"] == page.rows["Rested Stripes"],
        "effects: Ready Glow and Rested Stripes share a row")
    check(page.rows["Play Gain"] ~= nil and page.rows["Play Gain"] == page.rows["Play Level-Up"],
        "effects: the two play buttons share a row")
    for _, text in ipairs({ "Show +N", "+N Text Size", "Amount Text Size", "Match Bar Color", "Effect Color", "Glow Size",
        "Star Size", "Stripe Size" }) do
        eq(page.rows[text], nil, "effects: " .. text .. " has no row on the page")
    end

    local function wheel(title, rowText, side)
        local cog = cogTitled(title)
        local row = page.rows[rowText] or {}
        check(cog ~= nil and cog.rgn == row[side], "effects: the " .. title .. " cogwheel sits on " .. rowText)
        check(cog ~= nil and type(cog.opts.disabledTooltip) == "string" and cog.opts.rawTooltip == true,
            "effects: the " .. title .. " cogwheel grays with its reason, shown as written")
        return cog
    end
    local function grayed(cog)
        return cog and cog.opts.disabled and cog.opts.disabled()
    end
    local function cogRow(cog, label)
        for _, entry in ipairs(cog and cog.opts.rows or {}) do
            if entry.label == label then return entry end
        end
        return nil
    end
    local function spans(cog, label)
        local row = cogRow(cog, label)
        return row and (row.min .. "-" .. row.max)
    end
    local function writes(cog, label, key, expected, ...)
        local row = cogRow(cog, label)
        local redrawn = false
        local previewRefresh = X.PreviewRefresh
        X.PreviewRefresh = function() redrawn = true end
        if row then row.set(...) end
        X.PreviewRefresh = previewRefresh
        eq(settings[key], expected, "effects: " .. label .. " saves " .. key)
        eq(redrawn, true, "effects: " .. label .. " redraws the preview, for " .. key)
    end
    local function checkWheels(p, levelName)
        local gainWheel = wheel("Gain Effect", "Gain Effect", "_leftRegion")
        local levelWheel = wheel(levelName, levelName, "_leftRegion")
        local amountWheel = wheel("Show Amount Gained", "Show Amount Gained", "_rightRegion")
        local color = cogRow(gainWheel, "Effect Color")

        settings[p .. "GainEffect"], settings[p .. "GainMatchBar"], settings[p .. "GainShowAmount"] = "off", true, true
        eq(grayed(gainWheel), true, p .. " effects: the gain cogwheel grays with no gain effect")
        eq(grayed(amountWheel), true, p .. " effects: and the amount's")
        settings[p .. "GainEffect"] = "pulse"
        eq(grayed(gainWheel), false, p .. " effects: a gain effect opens the gain cogwheel")
        eq(grayed(amountWheel), false, p .. " effects: and the amount's, with the amount on")
        settings[p .. "GainShowAmount"] = false
        eq(grayed(amountWheel), true, p .. " effects: the amount's grays with the amount off")

        eq(color and color.disabled(), true, p .. " effects: Effect Color grays while it matches the bar")
        check(color ~= nil and type(color.disabledTooltip) == "string" and color.rawTooltip == true,
            p .. " effects: with its reason, shown as written")
        writes(gainWheel, "Match Bar Color", p .. "GainMatchBar", false, false)
        eq(color and color.disabled(), false, p .. " effects: Match Bar Color off opens Effect Color")
        writes(gainWheel, "Effect Color", p .. "GainColorG", 0.2, 0.1, 0.2, 0.3)
        eq(color and select(2, color.get()), 0.2, p .. " effects: Effect Color reads what it saved")

        settings[p .. "LevelEffect"] = "flash"
        eq(grayed(levelWheel), true, p .. " effects: Glow Size has nothing to offer unless the effect is Sweep")
        settings[p .. "LevelEffect"] = "sweep"
        eq(grayed(levelWheel), false, p .. " effects: Sweep opens its cogwheel")
        eq(spans(levelWheel, "Glow Size"), "2-32", p .. " effects: Glow Size's range")
        writes(levelWheel, "Glow Size", p .. "GlowSize", 20, 20)

        eq(spans(amountWheel, "Amount Text Size"), "8-32", p .. " effects: Amount Text Size's range")
        writes(amountWheel, "Amount Text Size", p .. "GainTextSize", 20, 20)

        for _, key in ipairs({ "GainEffect", "GainMatchBar", "GainShowAmount", "GainColorR", "GainColorG", "GainColorB",
            "LevelEffect", "GlowSize", "GainTextSize" }) do
            settings[p .. key] = nil
        end
    end

    checkWheels("xp", "Level-Up Effect")
    eq(cogTitled("Ready Glow"), nil, "effects: Ready Glow has no cogwheel")
    local stripeWheel = wheel("Rested Stripes", "Rested Stripes", "_rightRegion")
    settings.xpRestedStripes = false
    eq(grayed(stripeWheel), true, "effects: the stripes' cogwheel grays with the stripes off")
    settings.xpRestedStripes = true
    eq(grayed(stripeWheel), false, "effects: and opens with them on")
    eq(spans(stripeWheel, "Stripe Size"), "4-32", "effects: Stripe Size's range")
    writes(stripeWheel, "Stripe Size", "xpStripeSize", 20, 20)
    settings.xpRestedStripes, settings.xpStripeSize = nil, nil
    check(not has("TICKER AND PARTY"), "effects: the XP bar's page has no card section")

    X.SelectBar("fb")
    buildPage("page, reputation view with effects")
    check(has("EFFECTS"), "effects: the reputation bar's page has the section")
    check(before("DIVIDERS", "EFFECTS"), "effects: after its appearance sections")
    check(page.rows["Rank-Up Effect"] ~= nil, "effects: the reputation bar's moment is a rank-up")
    check(page.rows["Gain Effect"] ~= nil and page.rows["Gain Effect"] == page.rows["Show Amount Gained"],
        "effects: Gain Effect and Show Amount Gained share a row")
    eq(page.rows["Amount Text Size"], nil, "effects: Amount Text Size has no row on the page")
    checkWheels("fb", "Rank-Up Effect")
    check(page.rows["Play Gain"] ~= nil and page.rows["Play Gain"] == page.rows["Play Rank-Up"],
        "effects: its two play buttons share a row")
    eq(page.rows["Ready Glow"], nil, "effects: Ready Glow is the XP bar's")
    eq(page.rows["Rested Stripes"], nil, "effects: and Rested Stripes")
    eq(factionWord(), nil, "effects: every label reads reputation, none faction")

    -- The third view
    local enable
    local dualRow = EUI.Widgets.DualRow
    EUI.Widgets.DualRow = function(w, parent, y, left, right)
        if type(left) == "table" and left.text == "Enable XP Ticker" then enable = left end
        return dualRow(w, parent, y, left, right)
    end
    X.SelectBar("tk")
    settings.xpEnabled = false
    buildPage("page, card view")
    EUI.Widgets.DualRow = dualRow
    local sections = { "TICKER AND PARTY", "TICKER VISIBILITY", "TICKER ROWS", "TICKER STYLE",
        "PARTY CARD", "PARTY CARD STYLE", "POSITION" }
    for i, text in ipairs(sections) do
        check(has(text), "card view: its " .. text .. " section")
        if i > 1 then check(before(sections[i - 1], text), "card view: " .. text .. " follows " .. sections[i - 1]) end
    end
    check(not has("XP BAR") and not has("REPUTATION BAR") and not has("EFFECTS") and not has("FRAME"),
        "card view: no bar's sections")
    check(not has("TICKER TEXT") and not has("TICKER BACKGROUND"), "card view: TICKER STYLE replaces the two sections")
    check(enable ~= nil, "card view: Enable XP Ticker is built")
    eq(enable and enable.disabled(), true, "card view: grayed with the XP bar off")
    check(enable and type(enable.disabledTooltip) == "string", "card view: with a reason")
    eq(enable and enable.rawTooltip, true, "card view: shown as written, not wrapped")
    settings.xpEnabled = true
    eq(enable and enable.disabled(), false, "card view: usable with the XP bar on")
    settings.xpEnabled = false
    check(page.rows["Current Level"] ~= nil and page.rows["Current Level"] == page.rows["Level History Rows"],
        "card view: Current Level and Level History Rows share a row")
    check(page.rows.Played ~= nil and page.rows.Played == page.rows.Pace, "card view: Played and Pace share a row")
    check(page.rows["XP Line"] ~= nil and page.rows["XP Line"] == page.rows["Gap Bars"], "card view: XP Line and Gap Bars share a row")
    eq(page.full["Position: use EUI Unlock Mode"], true, "card view: the Unlock Mode line has a row of its own")
    eq(factionWord(), nil, "card view: no word on the page reads faction")

    -- A press on the sample card leads to its setting.
    local scrolled, glowed
    local realAfter = _G.C_Timer.After
    EUI.SmoothScrollTo = function(v) scrolled = v end
    EUI.ELLESMERE_GREEN = { r = 0, g = 1, b = 0 }
    EUI.MakeSettingGlow = function() return function(target) glowed = target end end
    _G.C_Timer.After = function(_, fn) fn() end
    buildPage("page, card view, navigation")
    for key, row in pairs({ tkCurrent = "Current Level", tkHistory = "Level History Rows", tkPlayed = "Played", tkPace = "Pace",
        tkTop = "Font", tkBack = "Background", tkLine = "XP Line", tkGapBars = "Gap Bars" }) do
        scrolled, glowed = nil, nil
        X.NavigateToSetting(key)
        check(scrolled ~= nil, "card view: " .. key .. " scrolls")
        check(glowed ~= nil and (glowed == page.rows[row] or glowed == page.rows[row]._leftRegion
            or glowed == page.rows[row]._rightRegion), "card view: " .. key .. " glows its row")
    end
    glowed = nil
    X.NavigateToSetting("tkTop")
    eq(glowed, page.rows.Font._leftRegion, "card view: the top line glows Font, on the left")
    glowed = nil
    X.NavigateToSetting("tkBack")
    eq(glowed, page.rows.Background._rightRegion, "card view: the background glows Background, on the right")
    _G.C_Timer.After = realAfter
    EUI.SmoothScrollTo, EUI.ELLESMERE_GREEN, EUI.MakeSettingGlow = nil, nil, nil

    EUI.IsSearchPrebuild = function() return true end
    buildPage("page, search prebuild with the card")
    check(has("XP DISPLAY") and has("REPUTATION SOURCE") and has("TICKER AND PARTY") and has("TICKER STYLE") and has("PARTY CARD"),
        "search prebuild: all three views, so search finds every row")
    check(lastIndexOf("EFFECTS") ~= indexOf("EFFECTS"), "search prebuild: both bars' EFFECTS")
    EUI.IsSearchPrebuild = nil

    -- The dropdowns and buttons play on the preview.
    local played = {}
    local previewPlay = X.PreviewPlay
    X.PreviewPlay = function(moment) played[#played + 1] = moment end
    local gainDrop, levelDrop, playGain
    EUI.Widgets.DualRow = function(w, parent, y, left, right)
        for _, cfg in ipairs({ left or false, right or false }) do
            if cfg and cfg.text == "Gain Effect" then gainDrop = cfg end
            if cfg and cfg.text == "Level-Up Effect" then levelDrop = cfg end
            if cfg and cfg.text == "Play Gain" then playGain = cfg end
        end
        return dualRow(w, parent, y, left, right)
    end
    X.SelectBar("xp")
    buildPage("page, XP view, playback")
    EUI.Widgets.DualRow = dualRow
    check(gainDrop ~= nil and levelDrop ~= nil and playGain ~= nil, "playback: the controls are built")
    if gainDrop and levelDrop and playGain then
        gainDrop.setValue("wave")
        eq(settings.xpGainEffect, "wave", "playback: the dropdown saves")
        eq(played[1], "gain", "playback: changing the gain effect plays it")
        levelDrop.setValue("sweep")
        eq(played[2], "level", "playback: changing the level effect plays it")
        playGain.onClick()
        eq(played[3], "gain", "playback: the button plays")
        settings.xpGainEffect = "surge"
        eq(gainDrop.getValue(), "surge", "playback: a style the client has shows as itself")
        settings.xpGainEffect, settings.xpLevelEffect = nil, nil
    end
    X.PreviewPlay = previewPlay

    -- A pick of the card rebuilds the page and goes to its top.
    local calls = {}
    EUI.RefreshPage = function() calls[#calls + 1] = "refresh" end
    EUI.ScrollToTop = function() calls[#calls + 1] = "top" end
    X.SelectBar("tk")
    eq(table.concat(calls, ","), "refresh,top", "a pick of the card rebuilds the page, then scrolls it to the top")
    EUI.RefreshPage, EUI.ScrollToTop = nil, nil
    X.SelectBar("xp")
end

---------------------------------------------------------------------------------
-- The party's rows in the third view
---------------------------------------------------------------------------------

do
    local cfgs = {}
    local dualRow = EUI.Widgets.DualRow
    EUI.Widgets.DualRow = function(w, parent, y, left, right)
        for _, cfg in ipairs({ left or false, right or false }) do
            if cfg and cfg.text then cfgs[cfg.text] = cfg end
        end
        return dualRow(w, parent, y, left, right)
    end

    eq(X.BAR_V.tk, "Ticker and Party", "the picker's third choice names both")
    eq(table.concat(X.BAR_O, ","), "xp,fb,tk", "and the picker has no fourth")

    X.SelectBar("tk")
    settings.xpEnabled = false
    buildPage("page, party rows")
    local function sameRow(a, b)
        check(page.rows[a] ~= nil and page.rows[a] == page.rows[b], "party rows: " .. a .. " and " .. b .. " share a row")
    end
    sameRow("Enable XP Ticker", "Enable Party Card")
    sameRow("Share My XP", "Party Tooltip Lines")
    sameRow("Party Markers", "Marker Label")
    sameRow("Party Visibility", "Show Self")
    sameRow("Party Background", "Party Width")
    sameRow("Party Font", "Party Outline")
    sameRow("Party Font Size", "Party Texture")
    sameRow("Font", "Outline")
    sameRow("Font Size", "Background")
    eq(cfgs["Party Width"].min, 0, "party rows: Party Width starts at 0")
    eq(cfgs["Party Width"].max, 600, "party rows: and keeps its maximum")
    eq(cfgs["Party Width"].getValue(), 0, "party rows: and sits at 0 by default")
    check(cfgs["Party Width"].tooltip:find("ticker", 1, true) ~= nil, "party rows: its tooltip says what 0 follows")
    check(page.rows["Party Fill"] ~= nil, "party rows: Party Fill has its row")
    for _, wheelOnly in ipairs({ "Marker Width", "Label Size", "Fill Color" }) do
        eq(page.rows[wheelOnly], nil, "party rows: " .. wheelOnly .. " sits in a cogwheel")
    end
    check(page.rows.Font ~= nil and page.rows.Font ~= page.rows["Party Font"], "party rows: the ticker's Font keeps its own row")
    eq(factionWord(), nil, "party rows: no word on the page reads faction")

    -- The cogwheels.
    local markerCog = cogTitled("Party Markers")
    check(markerCog ~= nil and markerCog.rgn == (page.rows["Party Markers"] or {})._leftRegion, "party rows: the markers' cogwheel sits on them")
    eq(markerCog and #markerCog.opts.rows, 1, "party rows: holding Marker Width")
    if markerCog then
        markerCog.opts.rows[1].set(4)
        eq(settings.xpPartyMarkerWidth, 4, "party rows: Marker Width saves")
        settings.xpPartyMarkerWidth = nil
    end
    local labelCog = cogTitled("Marker Label")
    check(labelCog ~= nil and labelCog.rgn == (page.rows["Marker Label"] or {})._rightRegion, "party rows: the label's cogwheel sits on it")
    eq(labelCog and #labelCog.opts.rows, 4, "party rows: holding its side, two offsets and its size")
    eq(labelCog and labelCog.opts.rows[1].type, "dropdown", "party rows: the side first")
    if labelCog then
        labelCog.opts.rows[1].set("below")
        eq(settings.xpPartyLabelSide, "below", "party rows: the side saves")
        settings.xpPartyLabelSide = nil
        labelCog.opts.rows[2].set(7)
        eq(settings.xpPartyLabelOffX, 7, "party rows: the X offset saves")
        settings.xpPartyLabelOffX = nil
        labelCog.opts.rows[4].set(20)
        eq(settings.xpPartyLabelSize, 20, "party rows: the size saves")
        settings.xpPartyLabelSize = nil
    end
    local fillCog = cogTitled("Party Fill")
    check(fillCog ~= nil and fillCog.rgn == (page.rows["Party Fill"] or {})._leftRegion, "party rows: the fill's cogwheel sits on it")
    if fillCog then
        fillCog.opts.rows[1].set(0.1, 0.2, 0.3)
        eq(settings.xpPartyFillColorG, 0.2, "party rows: Fill Color saves")
        settings.xpPartyFillColorR, settings.xpPartyFillColorG, settings.xpPartyFillColorB = nil, nil, nil
    end

    -- Grays. Enable Party Card and Share My XP work with the XP bar off.
    local shareOff = cfgs["Share My XP"] and cfgs["Share My XP"].disabled
    eq(shareOff and shareOff() or false, false, "party rows: Share My XP works with the XP bar off")
    local cardOff = cfgs["Enable Party Card"] and cfgs["Enable Party Card"].disabled
    eq(cardOff and cardOff() or false, false, "party rows: and so does Enable Party Card")
    check(type(cfgs["Share My XP"].tooltip) == "string", "party rows: Share My XP has a tooltip")
    eq(cfgs["Party Markers"].disabled(), true, "party rows: Party Markers grays with the XP bar off")
    check(type(cfgs["Party Markers"].disabledTooltip) == "string", "party rows: with a reason")
    eq(cfgs["Party Markers"].rawTooltip, true, "party rows: the markers' reason prints as written")
    eq(cfgs["Party Tooltip Lines"].disabled(), true, "party rows: the lines gray with the XP bar off")
    check(type(cfgs["Party Tooltip Lines"].disabledTooltip) == "string", "party rows: with a reason")
    eq(cfgs["Party Tooltip Lines"].rawTooltip, true, "party rows: the lines' reason prints as written")
    settings.xpEnabled = true
    eq(cfgs["Party Markers"].disabled(), false, "party rows: Party Markers works with the XP bar on")
    eq(cfgs["Party Tooltip Lines"].disabled(), false, "party rows: and the lines, with Show Tooltip on")
    settings.xpTooltip = false
    eq(cfgs["Party Tooltip Lines"].disabled(), true, "party rows: the lines gray with Show Tooltip off")
    settings.xpTooltip = nil
    eq(cfgs["Marker Label"].disabled(), true, "party rows: Marker Label grays with Party Markers off")
    eq(markerCog and markerCog.opts.disabled(), true, "party rows: and the markers' cogwheel")
    settings.xpPartyMarkers = true
    eq(cfgs["Marker Label"].disabled(), false, "party rows: and works with it on")
    eq(markerCog and markerCog.opts.disabled(), false, "party rows: and the cogwheel opens")
    eq(labelCog and labelCog.opts.disabled(), false, "party rows: with a label chosen, its cogwheel opens")
    settings.xpPartyLabel = "off"
    eq(labelCog and labelCog.opts.disabled(), true, "party rows: with Off chosen, it grays")
    settings.xpPartyLabel = nil
    settings.xpEnabled = false
    eq(cfgs["Marker Label"].disabled(), true, "party rows: and grays with the XP bar off")
    settings.xpPartyMarkers = nil
    for _, name in ipairs({ "Party Visibility", "Show Self", "Party Background", "Party Width", "Party Font", "Party Outline",
        "Party Font Size", "Party Texture", "Party Fill" }) do
        settings.xpPartyCard = false
        eq(cfgs[name].disabled(), true, "party rows: " .. name .. " grays with the card off")
        settings.xpPartyCard = true
        eq(cfgs[name].disabled(), false, "party rows: and works with it on")
    end
    eq(fillCog and fillCog.opts.disabled(), true, "party rows: the fill's cogwheel grays unless Fill is custom")
    settings.xpPartyFill = "custom"
    eq(fillCog and fillCog.opts.disabled(), false, "party rows: and opens with custom")
    settings.xpPartyFill = nil
    settings.xpPartyCard = nil

    -- A press on the sample leads to its setting.
    local scrolled, glowed
    local realAfter = _G.C_Timer.After
    EUI.SmoothScrollTo = function(v) scrolled = v end
    EUI.ELLESMERE_GREEN = { r = 0, g = 1, b = 0 }
    EUI.MakeSettingGlow = function() return function(target) glowed = target end end
    _G.C_Timer.After = function(_, fn) fn() end
    buildPage("page, party rows, navigation")
    for key, row in pairs({ pxFont = "Party Font", pxSize = "Party Font Size", pxFill = "Party Fill", pxBack = "Party Background" }) do
        scrolled, glowed = nil, nil
        X.NavigateToSetting(key)
        check(scrolled ~= nil, "party rows: " .. key .. " scrolls")
        check(glowed ~= nil and (glowed == page.rows[row] or glowed == page.rows[row]._leftRegion
            or glowed == page.rows[row]._rightRegion), "party rows: " .. key .. " glows its row")
    end
    for _, key in ipairs({ "frame", "body", "fill", "level", "center", "right", "levelTime", "sessionTime", "rate", "compRested" }) do
        glowed = nil
        X.NavigateToSetting(key)
        eq(glowed, page.rows["Party Markers"]._leftRegion, "party rows: the sample bar's " .. key .. " leads to Party Markers")
    end

    -- Collapsed, the style rows are not built, and their keys glow the section.
    EUI.BuildLessCommonExpander = function(_parent, y) return false, y end
    buildPage("page, party rows, collapsed")
    eq(page.rows["Party Font"], nil, "party rows: collapsed, no Party Font")
    eq(page.rows["Party Fill"], nil, "party rows: and no Party Fill")
    check(page.rows["Party Width"] ~= nil, "party rows: Party Width stays out of the collapsed section")
    for _, key in ipairs({ "pxFont", "pxSize", "pxFill" }) do
        glowed = nil
        X.NavigateToSetting(key)
        eq(glowed, page.headerAt["PARTY CARD STYLE"], "party rows: collapsed, " .. key .. " glows the section")
    end
    EUI.BuildLessCommonExpander = nil

    _G.C_Timer.After = realAfter
    EUI.SmoothScrollTo, EUI.ELLESMERE_GREEN, EUI.MakeSettingGlow = nil, nil, nil

    -- A setter reaches the party path.
    cfgs["Share My XP"].setValue(true)
    eq(settings.xpPartyShare, true, "party rows: Share My XP saves")
    cfgs["Share My XP"].setValue(false)
    eq(settings.xpPartyShare, false, "party rows: both ways")

    EUI.Widgets.DualRow = dualRow
    X.SelectBar("xp")
end

finish()
