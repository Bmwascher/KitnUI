-- ╔══════════════════════════════════════════════════════════════╗
-- ║  topbar-eui-combat.lua                                       ║
-- ║  Purpose: Gate for the Top Bar's two ways into EllesmereUI's ║
-- ║           panel: both refuse in combat with its message.     ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/topbar-eui-combat.lua

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

local combat = false
local toggles, errors = 0, {}

_G.format = string.format
_G.InCombatLockdown = function() return combat end
_G.CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(script, handler) self.scripts[script] = handler end
    return frame
end
_G.EllesmereUI = {
    Toggle = function() toggles = toggles + 1 end,
    PrintError = function(msg) errors[#errors + 1] = msg end,
}

local ns = {
    EUI_INERT = false,
    EUI_TB_DEFAULT_ORDER = {},
    TopBar = { Apply = function() end },
}

local chunk = assert(loadfile("KitnUI_EUI/TopBar/Elements.lua"))
chunk("KitnUI_EUI", ns)

local REFUSAL = "Cannot open options during combat."

local function run(id, button, label)
    toggles, errors = 0, {}
    local el = ns.TopBar.ById[id]
    check(type(el) == "table" and type(el.onClick) == "function", label .. ": has a click handler")
    if el and el.onClick then el.onClick(nil, button) end
end

for _, case in ipairs({ { "clock", "RightButton" }, { "euiconfig", "LeftButton" } }) do
    local id, button = case[1], case[2]

    combat = true
    run(id, button, id .. " in combat")
    eq(toggles, 0, id .. ": in combat the panel is not opened")
    eq(errors[1], REFUSAL, id .. ": in combat EllesmereUI's own refusal is printed")

    combat = false
    run(id, button, id .. " out of combat")
    eq(toggles, 1, id .. ": out of combat the panel toggles")
    eq(#errors, 0, id .. ": out of combat nothing is printed")
end

eq(ns.TopBar.ById.euiconfig.secure, false, "euiconfig: a plain click handler, not a secure macro")

combat = false
run("euiconfig", "RightButton", "euiconfig right click")
eq(toggles, 0, "euiconfig: only the left button opens the panel")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
