-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-plugin.lua                                              ║
-- ║  Purpose: Gate for how the KitnUI tab joins EllesmereUI's    ║
-- ║           panel: one plugin section through the public API,  ║
-- ║           nothing written into the panel's own tables, and   ║
-- ║           the calls that name the tab's module key.          ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/eui-plugin.lua

local failures = 0
local checks = 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        -- io.write: the stubs below replace print.
        io.write("FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or "") .. "\n")
    end
end

local function eq(actual, expected, label)
    check(actual == expected, label, "got " .. tostring(actual) .. ", wanted " .. tostring(expected))
end

---------------------------------------------------------------------------------
-- Stubs
---------------------------------------------------------------------------------

local core = { title = "KitnUI", profileName = "KitnUI", data = {}, db = { profiles = {} } }
_G.KitnUI_Shared = core
_G.InCombatLockdown = function() return false end
local hooked = {}
_G.hooksecurefunc = function(_, name) hooked[name] = true end
_G.C_Timer = { After = function() end }
_G.EllesmereUIDB = { profiles = {} }

local loginHandlers = {}
_G.CreateFrame = function()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f.RegisterUnitEvent() end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(_, fn)
        if self.events.PLAYER_LOGIN then loginHandlers[#loginHandlers + 1] = { frame = self, fn = fn } end
    end
    return f
end

local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end

-- An EllesmereUI with the plugin API when `plugins` is true, without it otherwise.
local function newEUI(plugins)
    local E = { calls = {}, ADDON_GROUPS = {}, Lite = { _dbRegistry = {} } }
    local function log(name, ...) E.calls[#E.calls + 1] = { name = name, ... } end
    E.RegisterModule = function(_, key) log("RegisterModule", key) end
    E.ShowModule = function(_, key) log("ShowModule", key) end
    E.InvalidateModulePageCache = function(_, key) log("Invalidate", key) end
    E.RefreshPage = function() log("RefreshPage") end
    E.GetActiveModule = function() return E.activeModule end
    E.GetActivePage = function() return E.activePage end
    E.SwitchProfile = function() end
    if plugins then
        E.registered = {}
        E.RegisterPlugin = function(id, spec)
            log("RegisterPlugin", id)
            E.registered[id] = spec
            return true
        end
        E.IsPluginRegistered = function(id) return E.registered[id] ~= nil end
        E.GetPluginModuleKey = function(id, key)
            local spec = E.registered[id]
            if not spec then return nil end
            for _, m in ipairs(spec.modules) do
                if m.key == key then return "plugin:" .. id .. ":" .. key end
            end
            return nil
        end
        E.OpenPlugin = function(id) log("OpenPlugin", id) return true end
    end
    return E
end

local function count(E, name)
    local n = 0
    for _, c in ipairs(E.calls) do if c.name == name then n = n + 1 end end
    return n
end

-- Loads Core.lua against `E` and fires login. Returns the tab's namespace.
local function boot(E)
    _G.EllesmereUI = E
    loginHandlers, printed, hooked = {}, {}, {}
    local ns = {}
    local chunk, err = loadfile("KitnUI_EUI/Core.lua")
    if not chunk then
        io.write("FAIL  could not load KitnUI_EUI/Core.lua: " .. tostring(err) .. "\n")
        os.exit(1)
    end
    chunk("KitnUI_EUI", ns)
    for _, h in ipairs(loginHandlers) do
        local ok, why = pcall(h.fn, h.frame, "PLAYER_LOGIN")
        check(ok, "login runs without an error", why)
    end
    return ns
end

---------------------------------------------------------------------------------
-- With the plugin API
---------------------------------------------------------------------------------

local E = newEUI(true)
local ns = boot(E)

-- The secret-value guard the tab's files share.
local SECRET = {}
_G.issecretvalue = function(v)
    assert(v ~= nil, "the check never sees nil")
    return v == SECRET
end
eq(ns.EUIPlain(SECRET), nil, "the secret guard: a secret value reads nil")
eq(ns.EUIPlain(5), 5, "the secret guard: a plain value passes")
eq(ns.EUIPlain(false), false, "the secret guard: false stays false")
eq(ns.EUIPlain(nil), nil, "the secret guard: nil stays nil")
_G.issecretvalue = nil
eq(ns.EUIPlain(SECRET), SECRET, "the secret guard: a client without the check passes the value")

eq(count(E, "RegisterPlugin"), 1, "the tab registers one plugin")
local spec = E.registered and E.registered.KitnUI
check(spec ~= nil, "under the id KitnUI")
if spec then
    eq(spec.label, "KitnUI", "its section reads KitnUI")
    eq(spec.position, "top", "and sits above EllesmereUI's own sections")
    eq(spec.modules and #spec.modules, 1, "with one module")
    local m = spec.modules and spec.modules[1] or {}
    eq(m.title, "KitnUI", "the module row reads KitnUI")
    eq(type(m.buildPage), "function", "the module builds its pages")
    eq(type(m.getHeaderBuilder), "function", "and supplies the Top Bar's header")
    eq(type(m.onPageCacheRestore), "function", "and restores the Top Bar's preview")
    local pages = m.pages or {}
    eq(table.concat(pages, ","), table.concat(ns.EUIPageOrder or {}, ","), "its tabs are the page order")
end
eq(count(E, "RegisterModule"), 0, "nothing registers through the panel's own module call")
eq(#E.ADDON_GROUPS, 0, "nothing is written into the panel's sidebar groups")
eq(E._addonInfoByFolder, nil, "nor into its sidebar info table")
eq(E._syncExempt, nil, "nor into its sync exemptions")
eq(ns.EUIPageOrder and ns.EUIPageOrder[#ns.EUIPageOrder], "XP Bar", "XP Bar is the last page")
if spec then
    local m = spec.modules and spec.modules[1] or {}
    local restored = 0
    local function xpHeader() end
    ns.XPBar = { BuildPreviewHeader = xpHeader, PreviewRestore = function() restored = restored + 1 end }
    eq(m.getHeaderBuilder and m.getHeaderBuilder("XP Bar"), xpHeader, "the XP Bar page supplies its preview header")
    if m.onPageCacheRestore then m.onPageCacheRestore("XP Bar") end
    eq(restored, 1, "and restores its preview on a cached revisit")
    eq(m.getHeaderBuilder and m.getHeaderBuilder("General"), nil, "a page without a preview supplies no header")
    ns.XPBar = nil
end

local key = "plugin:KitnUI:" .. ((spec and spec.modules and spec.modules[1] and spec.modules[1].key) or "?")
E.calls = {}
ns.EUIRebuildForOwnership()
check(E.calls[1] and E.calls[1].name == "Invalidate" and E.calls[1][1] == key,
    "a rebuild drops the cached pages under the plugin's module key", E.calls[1] and E.calls[1][1])
eq(count(E, "RefreshPage"), 1, "and refreshes the page")

E.calls, E.activeModule, E.activePage = {}, key, "General"
ns.EUIRebuildForOwnership("General")
eq(count(E, "RefreshPage"), 1, "a rebuild for the page showing refreshes it")
E.calls, E.activeModule = {}, "KitnUI"
ns.EUIRebuildForOwnership("General")
eq(count(E, "RefreshPage"), 0, "a rebuild while another module shows does not")

E.calls = {}
_G.KitnCommands.options()
eq(count(E, "OpenPlugin"), 1, "/kitn options opens the plugin")
eq(count(E, "ShowModule"), 0, "and not a module by the old key")
eq(#printed, 0, "and prints nothing")

---------------------------------------------------------------------------------
-- Without the plugin API
---------------------------------------------------------------------------------

E = newEUI(false)
boot(E)
eq(count(E, "RegisterModule"), 0, "an EllesmereUI without the plugin API registers nothing")
eq(#E.ADDON_GROUPS, 0, "and writes nothing into its sidebar")
eq(hooked.SwitchProfile, true, "but the switches' login work still runs there")
E.calls = {}
_G.KitnCommands.options()
eq(count(E, "ShowModule"), 0, "/kitn options opens nothing there")
check(printed[1] and printed[1]:find("needs EllesmereUI 9.4", 1, true), "and says the tab needs a newer EllesmereUI", printed[1])

---------------------------------------------------------------------------------
-- XP and faction bar defaults
---------------------------------------------------------------------------------

for _, forever in ipairs({ true, false }) do
    core.IS_FOREVER = forever
    local defaults = boot(newEUI(true)).EUI_DEFAULTS or {}
    local client = forever and "Forever" or "retail"
    eq(defaults.xpEnabled, forever, "the XP bar's default on " .. client)
    eq(defaults.fbEnabled, forever, "the faction bar's default on " .. client)
    eq(defaults.xpTickerEnabled, forever, "the XP ticker's default on " .. client)
end
core.IS_FOREVER = nil
local booted = boot(newEUI(true))
local xpDefaults = booted.EUI_DEFAULTS or {}
eq(xpDefaults.xpFrameStyle, "", "the XP bar's frame style defaults to the client's own")
eq(xpDefaults.fbFrameStyle, "", "and the faction bar's")
eq(xpDefaults.xpTexture, "KitnUI", "the XP bar's texture defaults to KitnUI's own")
eq(xpDefaults.fbTexture, "KitnUI", "the faction bar's texture defaults to KitnUI's own")
eq(xpDefaults.xpWidth, 600, "the XP bar defaults to 600 wide")
eq(xpDefaults.xpHeight, 30, "the XP bar defaults to 30 high")
eq(xpDefaults.fbWidth, 600, "the reputation bar defaults to 600 wide, as the XP bar")
eq(xpDefaults.fbHeight, 27, "the reputation bar defaults to 27 high")
eq(xpDefaults.fbFillMode, "standing", "the reputation bar defaults to Standing Color")
eq(xpDefaults.xpNumberStyle, "short", "the number style defaults to short")
eq(xpDefaults.xpGainEffect, "pulse", "the XP bar's gain effect defaults to Pulse")
eq(xpDefaults.fbGainEffect, "off", "the reputation bar's gain effect defaults to off")
eq(xpDefaults.xpGainQuestsOnly, true, "the XP bar's gain effect defaults to quest turn-ins only")
eq(xpDefaults.xpGainShowAmount, true, "the XP bar shows the amount gained by default")
eq(xpDefaults.fbGainShowAmount, true, "the reputation bar shows the amount gained by default")
eq(xpDefaults.xpLevelEffect, "flash", "the XP bar's level-up effect defaults to Flash")
eq(xpDefaults.fbLevelEffect, "flash", "the reputation bar's rank-up effect defaults to Flash")
eq(xpDefaults.xpReadyGlow, true, "Ready Glow defaults on")
eq(xpDefaults.xpRestedStripes, false, "Rested Stripes defaults off")
eq(xpDefaults.xpTickerVisibility, "always", "the card's Visibility defaults to Always")
eq(xpDefaults.xpTickerHideResting, true, "the card hides while resting by default")
eq(xpDefaults.xpTickerHistoryRows, 5, "the card shows five completed levels by default")
eq(xpDefaults.xpTickerShowPace, false, "Pace defaults off")
eq(xpDefaults.xpTickerBackground, "card", "the card's background defaults to Card")
eq(xpDefaults.xpTickerPos, nil, "the card has no default position")
for _, stem in ipairs({ "xpAmount", "xpLevelTime", "xpSessionTime", "xpRate", "xpCompRested", "fbName", "fbAmount" }) do
    eq(xpDefaults[stem .. "OffX"], 0, "the default " .. stem .. "OffX leaves the text where it was")
    eq(xpDefaults[stem .. "OffY"], 0, "the default " .. stem .. "OffY leaves the text where it was")
end
for defaultKey, defaultValue in pairs(xpDefaults) do
    local prefix = type(defaultKey) == "string" and defaultKey:sub(1, 2)
    if prefix == "xp" or prefix == "fb" then
        check(type(defaultValue) ~= "table", "the default " .. defaultKey .. " is a scalar")
    end
end
eq(xpDefaults.xpPos, nil, "the XP bar's position has no default")
eq(xpDefaults.fbPos, nil, "nor the faction bar's")

---------------------------------------------------------------------------------
-- Helpers the XP bars read
---------------------------------------------------------------------------------

check(type(booted.EUIActiveProfileName) == "function" and type(booted.EUIActiveProfileName()) == "string",
    "Core publishes the active profile's name")
local tipFn = booted.EUIOwnershipTip or function() return "" end
local tip = tipFn("Base.", "xpbar", true, "the bar", function() return true end)
check(tip:find("is holding the bar", 1, true) ~= nil, "an ownership tip takes the caller's own holding test", tip)
tip = tipFn("Base.", "xpbar", true, "the bar", function() return false end)
check(tip:find("not holding the bar", 1, true) ~= nil, "and says so when the caller's test holds nothing", tip)

-- The load's start, captured once on the first PLAYER_ENTERING_WORLD.
local realGetTime = _G.GetTime
_G.GetTime = function() return 500 end
_G.UnitXP = function() return 100 end
_G.UnitXPMax = function() return 1000 end
_G.UnitLevel = function() return 10 end
local seen
if booted.EUIWhenLoginKnown then booted.EUIWhenLoginKnown(function(kind) seen = kind end) end
eq(seen, nil, "a login waiter waits for PLAYER_ENTERING_WORLD")
for _, h in ipairs(loginHandlers) do
    if h.frame.events.PLAYER_ENTERING_WORLD then
        local ok, why = pcall(h.fn, h.frame, "PLAYER_ENTERING_WORLD", true, false)
        check(ok, "PLAYER_ENTERING_WORLD runs without an error", why)
    end
end
eq(seen, "login", "a login waiter runs with the load's kind")
eq(booted.EUILoginKind, "login", "the load's kind is a login")
local start = booted.EUILoadStart or {}
eq(start.time, 500, "the load's start time is captured")
eq(start.xp, 100, "with the XP")
eq(start.max, 1000, "the level's total")
eq(start.level, 10, "and the level")
_G.GetTime, _G.UnitXP, _G.UnitXPMax, _G.UnitLevel = realGetTime, nil, nil, nil

-- A reload flag that is secret counts as a login. The capture reads GetTime,
-- which the line above has just put back to its plain-Lua nil.
local SECRET_FLAG = {}
_G.issecretvalue = function(v) return v == SECRET_FLAG end
_G.GetTime = function() return 600 end
local secretBoot = boot(newEUI(true))
for _, h in ipairs(loginHandlers) do
    if h.frame.events.PLAYER_ENTERING_WORLD then
        local ok, why = pcall(h.fn, h.frame, "PLAYER_ENTERING_WORLD", false, SECRET_FLAG)
        check(ok, "PLAYER_ENTERING_WORLD with a secret reload flag runs without an error", why)
    end
end
eq(secretBoot.EUILoginKind, "login", "a secret reload flag counts as a login")
eq(secretBoot.EUILoadStart and secretBoot.EUILoadStart.time, 600, "a secret reload flag: the load's start is still captured")
_G.issecretvalue, _G.GetTime = nil, realGetTime

-- The contents generation, bumped by the two hooks that replace a profile's
-- contents and by nothing else.
local hookFns = {}
local realHook = _G.hooksecurefunc
_G.hooksecurefunc = function(_, name, fn)
    hooked[name] = true
    hookFns[name] = fn
end
local genE = newEUI(true)
genE.ApplyProfileData = function() end
genE.OnSpecSwitchComplete = function() end
local genNs = boot(genE)
_G.hooksecurefunc = realHook
local genOf = genNs.EUIProfileGeneration or function() return -1 end
local g0 = genOf()
if hookFns.ApplyProfileData then hookFns.ApplyProfileData({ addons = {} }) end
eq(genOf(), g0 + 1, "an import into the active profile bumps the contents generation")
if hookFns.SwitchProfile then hookFns.SwitchProfile("Other") end
eq(genOf(), g0 + 2, "and so does a profile switch")
if hookFns.OnSpecSwitchComplete then hookFns.OnSpecSwitchComplete() end
eq(genOf(), g0 + 2, "a spec switch alone does not")

io.write(string.format("%d checks, %d failures\n", checks, failures))
os.exit(failures == 0 and 0 or 1)
