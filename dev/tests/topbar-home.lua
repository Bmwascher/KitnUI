-- ╔══════════════════════════════════════════════════════════════╗
-- ║  topbar-home.lua                                             ║
-- ║  Purpose: Gate for the Top Bar Home button's secure action.  ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe dev/tests/topbar-home.lua

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

local frames = {}
local currentNeighborhood = "Neighborhood-A"
local canReturn = false
local applyCalls = 0
local houseListRequests = 0

_G.format = string.format
_G.C_Housing = {
    -- Counted, not ignored: the world-entry branch's list request is the only
    -- thing that repairs an arrival landing before the server settles the
    -- return flag, and nothing else in this file observes that call.
    GetPlayerOwnedHouses = function() houseListRequests = houseListRequests + 1 end,
    GetCurrentNeighborhoodGUID = function() return currentNeighborhood end,
}
_G.C_HousingNeighborhood = {
    CanReturnAfterVisitingHouse = function() return canReturn end,
}
_G.CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(script, handler) self.scripts[script] = handler end
    frames[#frames + 1] = frame
    return frame
end

local ns = {
    EUI_INERT = false,
    EUI_TB_DEFAULT_ORDER = {},
    TopBar = {
        Apply = function() applyCalls = applyCalls + 1 end,
    },
}

local chunk = assert(loadfile("KitnUI_EUI/TopBar/Elements.lua"))
chunk("KitnUI_EUI", ns)

local home = ns.TopBar.ById.home
check(type(home) == "table", "Elements.lua registers the Home element")

local housingWatcher
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_HOUSE_LIST_UPDATED then
        housingWatcher = frame
        break
    end
end
check(housingWatcher ~= nil, "the housing watcher exists")

if housingWatcher then
    check(housingWatcher.events.HOUSE_PLOT_ENTERED, "the watcher handles entering a housing plot")
    check(housingWatcher.events.HOUSE_PLOT_EXITED, "the watcher handles leaving a housing plot")
    -- The arrival trigger. HOUSE_PLOT_ENTERED was measured not firing on a
    -- teleport home, so without this the button has nothing to re-wire it.
    check(housingWatcher.events.PLAYER_ENTERING_WORLD, "the watcher handles entering the world")

    housingWatcher.scripts.OnEvent(housingWatcher, "PLAYER_HOUSE_LIST_UPDATED", {
        {
            neighborhoodGUID = "Neighborhood-A",
            houseGUID = "House-A",
            plotID = 7,
        },
    })
end

local button = { attributes = {} }
function button:SetAttribute(name, value) self.attributes[name] = value end
function button:SetScript() end
function button:HookScript() end

home.attrs(button)
eq(button.attributes.type1, "teleporthome", "left click teleports when return is unavailable")

canReturn = true
if housingWatcher then
    local before = applyCalls
    housingWatcher.scripts.OnEvent(housingWatcher, "HOUSE_PLOT_ENTERED")
    eq(applyCalls, before + 1, "entering the plot refreshes secure attributes")
end
home.attrs(button)
eq(button.attributes.type1, "returnhome", "left click returns from the selected home's neighborhood")

local tooltip = { lines = {} }
function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
home.tooltip(tooltip)
check(tooltip.lines[3] and tooltip.lines[3]:find("Return to Previous Location", 1, true),
    "the tooltip describes the active return action", tooltip.lines[3])

currentNeighborhood = "Neighborhood-B"
home.attrs(button)
eq(button.attributes.type1, "returnhome", "another owned house still exposes the available return action")

tooltip.lines = {}
home.tooltip(tooltip)
check(tooltip.lines[3] and tooltip.lines[3]:find("Return to Previous Location", 1, true),
    "another owned house still describes the available return action", tooltip.lines[3])

-- The regression this file could not catch before. The house never changes, so
-- a refresh gated on identity alone swallowed every hover and left the button
-- wired to a stale action for good.
local HOUSE_A = { { neighborhoodGUID = "Neighborhood-A", houseGUID = "House-A", plotID = 7 } }

if housingWatcher then
    canReturn = false
    local beforeChanged = applyCalls
    housingWatcher.scripts.OnEvent(housingWatcher, "PLAYER_HOUSE_LIST_UPDATED", HOUSE_A)
    eq(applyCalls, beforeChanged + 1, "an unchanged house with a changed action still refreshes")

    -- The other half of the same test: the change test must stay cheap, because
    -- the button re-requests the list from every hover.
    home.attrs(button)
    local beforeSame = applyCalls
    housingWatcher.scripts.OnEvent(housingWatcher, "PLAYER_HOUSE_LIST_UPDATED", HOUSE_A)
    eq(applyCalls, beforeSame, "an unchanged house and action does not refresh")

    -- PLAYER_ENTERING_WORLD carries isInitialLogin, not a house list. Routed
    -- into the list parser that boolean reads as an empty list and clears the
    -- cache, which would leave the button with no secure action at all.
    housingWatcher.scripts.OnEvent(housingWatcher, "PLAYER_ENTERING_WORLD", true)
    home.attrs(button)
    eq(button.attributes.type1, "teleporthome", "world entry leaves the cached house intact")

    -- The active half of that same branch, and the reason the event was added
    -- at all: arriving with the flag already flipped has to re-wire. Without
    -- this, dropping the change test from the world-entry branch still passes.
    canReturn = true
    local beforeArrival = applyCalls
    housingWatcher.scripts.OnEvent(housingWatcher, "PLAYER_ENTERING_WORLD", true)
    eq(applyCalls, beforeArrival + 1, "world entry re-wires when the return flag has flipped")

    -- The late net, as a sequence. An arrival that lands BEFORE the server
    -- settles the flag finds nothing to change, so the repair has to come from
    -- the list request the same branch fires.
    canReturn = false
    home.attrs(button)
    local beforeRequests = houseListRequests
    housingWatcher.scripts.OnEvent(housingWatcher, "PLAYER_ENTERING_WORLD", true)
    eq(houseListRequests, beforeRequests + 1, "world entry requests the house list")

    canReturn = true
    local beforeLate = applyCalls
    housingWatcher.scripts.OnEvent(housingWatcher, "PLAYER_HOUSE_LIST_UPDATED", HOUSE_A)
    eq(applyCalls, beforeLate + 1, "the late list answer re-wires after an early world entry")
end

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
