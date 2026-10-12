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
_G.hooksecurefunc = function() end
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
    loginHandlers, printed = {}, {}
    local ns = {}
    local chunk, err = loadfile("KitnUI_EUI/Core.lua")
    if not chunk then
        print("FAIL  could not load KitnUI_EUI/Core.lua: " .. tostring(err))
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
E.calls = {}
_G.KitnCommands.options()
eq(count(E, "ShowModule"), 0, "/kitn options opens nothing there")
eq(#printed, 1, "and says the panel is unavailable")

io.write(string.format("%d checks, %d failures\n", checks, failures))
os.exit(failures == 0 and 0 or 1)
