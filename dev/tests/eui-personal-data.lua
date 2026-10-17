-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-personal-data.lua                                       ║
-- ║  Purpose: Gate that the shipped EllesmereUI string carries   ║
-- ║           no Raid Frames Extra Frames data, and that the     ║
-- ║           cleaning script finds and clears every form of it. ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/eui-personal-data.lua
-- The shipped-string checks need LibDeflate (see dev/scripts/eui-personal.lua)
-- and are skipped, not failed, without it.

local failures = 0
local checks = 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        io.write("FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or "") .. "\n")
    end
end

local function eq(actual, expected, label)
    check(actual == expected, label, "got " .. tostring(actual) .. ", wanted " .. tostring(expected))
end

local M = dofile("dev/scripts/eui-personal.lua")

local FS, PS = "\31", "\30"
local POSITION = "EllesmereUIRaidFrames" .. FS .. "extraFrames" .. PS .. "position"
local OTHER = "EllesmereUIRaidFrames" .. FS .. "petFrames" .. PS .. "extraWidth"

local function defaults()
    return {
        showTanks = false, position = "right", freePos = { x = 100, y = -120 },
        freeHorizontal = false, players = {}, extraWidth = 0, extraHeight = 0, wrapAfter = 0,
    }
end

local function payloadWith(extra)
    return { version = 3, type = "full", data = {
        addons = { EllesmereUIRaidFrames = { extraFrames = extra, petFrames = { extraWidth = 2 } } },
        specOverrides = {}, condOverrides = {},
    } }
end

---------------------------------------------------------------------------------
-- Serializer
---------------------------------------------------------------------------------

local sample = { 1, "two", true, false, 4.5, { nested = { "x" } }, key = POSITION, [10] = "sparse" }
check(M.DeepEqual(M.Deserialize(M.Serialize(sample)), sample), "a table survives serialize and deserialize")
eq(M.Serialize({ "ab" }), "{s2:ab}", "strings are length-prefixed")
eq(M.Serialize({ k = 3 }), "{Ks1:kn3;}", "hash keys are tagged K and numbers end in a semicolon")

---------------------------------------------------------------------------------
-- Findings
---------------------------------------------------------------------------------

eq(#M.Findings(payloadWith(defaults())), 0, "the defaults are clean")

local named = defaults()
named.players = { "Alpha-Realm", "Beta-Realm" }
local f = M.Findings(payloadWith(named))
eq(#f, 1, "a name list is found")
check(f[1] and f[1]:find("2 names", 1, true), "and the finding counts the names", f[1])

local moved = defaults()
moved.position = "free"
eq(#M.Findings(payloadWith(moved)), 1, "a changed position is found")

local extraKey = defaults()
extraKey.freeRect = { 1, 2, 3, 4 }
eq(#M.Findings(payloadWith(extraKey)), 1, "an optional key beyond the defaults is found")

eq(#M.Findings(payloadWith(nil)), 1, "an absent block is found, since the update would read it as removed")

local noFolder = { data = { addons = {} } }
eq(#M.Findings(noFolder), 0, "a profile without Raid Frames has nothing to find")

check(M.IsTarget(POSITION), "an Extra Frames setting key is a target")
check(M.IsTarget("EllesmereUIRaidFrames" .. FS .. "extraFrames"), "the whole block's key is a target")
check(not M.IsTarget("EllesmereUIRaidFrames" .. FS .. "extraFramesX" .. PS .. "a"), "a longer name is not")
check(not M.IsTarget(OTHER), "another block's extraWidth is not")
check(not M.IsTarget(5), "a non-string key is not")

---------------------------------------------------------------------------------
-- Clean
---------------------------------------------------------------------------------

local p = payloadWith(named)
p.data.specOverrides = {
    { crumb = "first", values = { default = { [OTHER] = 1 } } },
    { crumb = "extra", values = { default = { [POSITION] = "free" }, [65] = { [POSITION] = "right" } } },
    { crumb = "mixed", values = { default = { [POSITION] = "free", [OTHER] = 3 } } },
    { crumb = "last", values = { default = { [OTHER] = 4 } } },
}
p.data.condOverrides = {
    { crumb = "cond", values = { default = { [POSITION] = "left" }, [1] = { [POSITION] = "right" } } },
}
eq(#M.Findings(p), 4, "the block, two spec entries and one conditional entry are found")

M.Clean(p)
local d = p.data
check(M.DeepEqual(d.addons.EllesmereUIRaidFrames.extraFrames, defaults()), "the block is reset to the defaults")
eq(d.addons.EllesmereUIRaidFrames.petFrames.extraWidth, 2, "another block is untouched")
eq(#d.specOverrides, 3, "the Extra-Frames-only entry is removed")
local crumbs = {}
for _, e in ipairs(d.specOverrides) do crumbs[#crumbs + 1] = e.crumb end
eq(table.concat(crumbs, ","), "first,mixed,last", "the rest keep their order with no gap")
eq(d.specOverrides[2].values.default[POSITION], nil, "the mixed entry loses its Extra Frames key")
eq(d.specOverrides[2].values.default[OTHER], 3, "and keeps its other key")
eq(#d.condOverrides, 0, "a conditional entry for Extra Frames is removed")
eq(#M.Findings(p), 0, "nothing is found after cleaning")

local snapshot = M.Deserialize(M.Serialize(p))
M.Clean(p)
check(M.DeepEqual(p, snapshot), "cleaning twice changes nothing more")

local bare = { data = { addons = {} } }
M.Clean(bare)
eq(bare.data.addons.EllesmereUIRaidFrames, nil, "cleaning never adds a Raid Frames folder")

---------------------------------------------------------------------------------
-- The shipped string
---------------------------------------------------------------------------------

local _, s = M.ReadData(M.DATA_PATH)
local lib, why = M.LoadLibDeflate()
if s == "" then
    io.write("skip: shipped-string checks, the string is empty\n")
elseif not lib then
    io.write("skip: shipped-string checks, " .. why .. "\n")
else
    local shipped, err = M.Decode(lib, s)
    check(type(shipped) == "table", "the shipped string decodes", err)
    if type(shipped) == "table" then
        local found = M.Findings(shipped)
        check(#found == 0, "the shipped string has no Extra Frames data; run: lua dev/scripts/eui-personal.lua --clean",
            table.concat(found, "; "))
        check(M.DeepEqual(M.Decode(lib, M.Encode(lib, shipped)), shipped),
            "the shipped profile survives encode and decode")
    end
end

io.write(string.format("%d checks, %d failures\n", checks, failures))
os.exit(failures == 0 and 0 or 1)
