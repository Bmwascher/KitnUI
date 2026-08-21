-- ╔══════════════════════════════════════════════════════════════╗
-- ║  lulu-minimap-keys.lua                                       ║
-- ║  Purpose: Gate for Lulu Mode's forced minimap key table.     ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe dev/tests/lulu-minimap-keys.lua
-- Exits non-zero on the first failure and prints what broke.
--
-- IT LOADS KitnUI_EUI/Lulu.lua AS A CHUNK. A pasted copy of the table could pass
-- every assertion here while the shipped one drifted, which is the one thing a
-- gate must not permit. The file takes its namespace from chunk varargs, so a
-- stub `ns` is all it takes.
--
-- WHAT THIS CAN AND CANNOT PROVE. It cannot see a minimap, so it says nothing
-- about whether 18 is a good Y offset. It proves the three things that are
-- invisible offline and expensive in game: that no key is held twice, that no
-- snapshot name is reused, and that every value is one EllesmereUI will actually
-- accept rather than clamp or ignore.

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

---------------------------------------------------------------------------------
-- Stubs: the surface Lulu.lua touches AT LOAD, and nothing more
---------------------------------------------------------------------------------

-- Lulu.lua only reaches the WoW API from inside functions. At load it assigns a
-- handful of ns fields and registers one re-apply callback, so the callback sink
-- is the whole stub.
local ns = {
    EUI_INERT = false,
    EUIRegisterReapply = function() end,
}

local chunk = assert(loadfile("KitnUI_EUI/Lulu.lua"))
chunk("KitnUI_EUI", ns)

local keys = ns.LuluMinimapKeys
check(type(keys) == "table", "Lulu.lua exports ns.LuluMinimapKeys")
if type(keys) ~= "table" then
    print(("%d checks, %d failed"):format(checks, failures))
    os.exit(1)
end

---------------------------------------------------------------------------------
-- The host's own accepted values
---------------------------------------------------------------------------------
--
-- Copied from the live EllesmereUI 8.9.x install on 2026-08-21:
--   MAP_POS  -- EllesmereUIOptions/EUI_Minimap_Options.lua:1198-1204
--   ROW_POS  -- EUI_Minimap_Options.lua:770-776
--   MAIL_POS -- EUI_Minimap_Options.lua:1077-1079 (corners are UPPERCASE, and
--               "button" is not; that is the host's casing, not a typo)
--   SHAPE    -- the shape dropdown, EUI_Minimap_Options.lua:196 (four values, not
--               two: "rectangular" and "textured_circle" are real and legal)
--
-- THIS CATCHES DRIFT ON KITNUI'S SIDE ONLY. Both halves of every comparison below
-- are frozen in this repo, so a host release that RENAMES one of these values
-- changes neither half: the gate keeps passing while the write goes dead in game.
-- What it does catch is a typo, a wrong casing, or a value invented here that the
-- host never accepted. The host side is re-checked by hand, against the citations
-- above, whenever EllesmereUI ships a release that touches the minimap.

local function set(...)
    local t = {}
    for _, v in ipairs({...}) do t[v] = true end
    return t
end

local MAP_POS = set("belowMap", "aboveMap", "topLeft", "top", "topRight",
                    "left", "right", "bottomLeft", "bottom", "bottomRight")
local ROW_POS = set("blUp", "blRight", "tlDown", "tlRight",
                    "brUp", "brLeft", "trLeft", "trDown")
local MAIL_POS = set("button", "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT")
local SHAPE = set("square", "rectangular", "circle", "textured_circle")

-- key -> what a legal value looks like. Every key in the table must appear here,
-- and every key here must appear in the table: the two lists are checked against
-- each other below, so a key added to Lulu.lua without a rule fails the gate
-- rather than slipping through unvalidated.
local RULES = {
    shape            = { kind = "enum",   values = SHAPE },
    clockPosition    = { kind = "enum",   values = MAP_POS },
    clockOffsetX     = { kind = "number", min = -500, max = 500 },
    clockOffsetY     = { kind = "number", min = -500, max = 500 },
    locationPosition = { kind = "enum",   values = MAP_POS },
    locationOffsetX  = { kind = "number", min = -500, max = 500 },
    locationOffsetY  = { kind = "number", min = -500, max = 500 },
    fpsPosition      = { kind = "enum",   values = MAP_POS },
    fpsOffsetX       = { kind = "number", min = -500, max = 500 },
    fpsOffsetY       = { kind = "number", min = -500, max = 500 },
    mailPosition     = { kind = "enum",   values = MAIL_POS },
    -- Mail's X is the one slider in the whole minimap page that is not -500..500.
    -- EUI_Minimap_Options.lua:1100 caps it at 100 while its own Y beside it (:1107)
    -- is the usual 500. Not a typo here; copy the host.
    mailOffsetX      = { kind = "number", min = -100, max = 100 },
    mailOffsetY      = { kind = "number", min = -500, max = 500 },
    diffTextPosition = { kind = "enum",   values = MAP_POS },
    diffTextOffsetX  = { kind = "number", min = -500, max = 500 },
    diffTextOffsetY  = { kind = "number", min = -500, max = 500 },
    btnRowPosition   = { kind = "enum",   values = ROW_POS },
    btnRowDistance   = { kind = "number", min = -20,  max = 60 },
}

---------------------------------------------------------------------------------
-- Structure
---------------------------------------------------------------------------------

local seenKey, seenSnap = {}, {}
for i = 1, #keys do
    local e = keys[i]
    local label = "entry " .. i
    if type(e) ~= "table" then
        check(false, label .. " is a table")
    else
        label = "key " .. tostring(e.key)
        check(type(e.key) == "string" and e.key ~= "", label .. " has a name")
        check(e.value ~= nil, label .. " has a value")

        -- The standing rule in ns.EUIOverride: no two controls may hold the same
        -- EllesmereUI key. Two entries for one key are two controls.
        check(not seenKey[e.key], label .. " is held only once")
        seenKey[e.key] = true

        -- Two entries sharing a snapshot name would have the second record the
        -- first one's forced value as the user's original.
        local snap = e.snap or e.key
        check(not seenSnap[snap], label .. " has its own snapshot name", snap)
        seenSnap[snap] = true

        local rule = RULES[e.key]
        check(rule ~= nil, label .. " has a validation rule in this gate")
        if rule then
            if rule.kind == "enum" then
                check(rule.values[e.value] == true,
                      label .. " uses a value EllesmereUI accepts", tostring(e.value))
            else
                check(type(e.value) == "number", label .. " is a number", type(e.value))
                if type(e.value) == "number" then
                    check(e.value >= rule.min and e.value <= rule.max,
                          label .. " is inside the host's slider range", e.value)
                    check(e.value == math.floor(e.value),
                          label .. " is a whole number", e.value)
                end
            end
        end
    end
end

for key in pairs(RULES) do
    check(seenKey[key] == true, "Lulu.lua still holds " .. key)
end

---------------------------------------------------------------------------------
-- The one rename that would strand a live note
---------------------------------------------------------------------------------
--
-- Users who already have Lulu Mode on keep their original minimap shape at
-- KitnUIDB.euiSnap.lulu[<profile>].minimapShape.prev. Rename that record and the
-- off path finds nothing to restore, leaving them a round minimap for good.

local shapeEntry
for i = 1, #keys do
    if keys[i].key == "shape" then shapeEntry = keys[i] end
end
check(shapeEntry ~= nil, "the shape entry exists")
if shapeEntry then
    eq(shapeEntry.snap, "minimapShape", "shape still snapshots under minimapShape")
end

print(("%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
