-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-merge.lua                                               ║
-- ║  Purpose: Gate for the three-way merge: the walk rules, the  ║
-- ║           inherited units, sequences, layout leaves, the     ║
-- ║           override set and the special keys.                 ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe dev/tests/eui-merge.lua

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

local function has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local ns = {}
local chunk, err = loadfile("Installer/Merge.lua")
if not chunk then
    print("FAIL  could not load Installer/Merge.lua: " .. tostring(err))
    os.exit(1)
end
chunk("KitnUI", ns)

check(type(ns.EUIThreeWayMerge) == "function", "ns.EUIThreeWayMerge is defined")
check(type(ns.EUISame) == "function", "ns.EUISame is defined")
check(type(ns.EUIDeepCopy) == "function", "ns.EUIDeepCopy is defined")

local same = ns.EUISame
local merge = ns.EUIThreeWayMerge

-- One folder, one payload shape, so every fixture below reads the same way.
local F = "EllesmereUIUnitFrames"
local function payload(addonTable, extra)
    local d = { addons = { [F] = addonTable } }
    for k, v in pairs(extra or {}) do d[k] = v end
    return d
end

---------------------------------------------------------------------------------
-- same
---------------------------------------------------------------------------------

eq(same(10000, 10001), false, "integers one apart are not the same")
eq(same(328.00001, 328.00003), true, "a float one part in ten thousand off is the same")
eq(same(0.5, 0.5039), false, "one 8-bit colour step is not the same")
eq(same(0, 0.00005), true, "near zero the tolerance is absolute 1e-4")
eq(same(1, 1.0), true, "an integer and its float form are equal by ==")
eq(same({ a = 1 }, { a = 1 }), true, "equal tables are the same")
eq(same({ a = 1 }, { a = 1, b = 2 }), false, "a table with an extra key is not the same")
eq(same({}, nil), false, "an empty table and nil are not the same")
eq(same("a", { "a" }), false, "a scalar and a table are not the same")

---------------------------------------------------------------------------------
-- Walk rules 1-4
---------------------------------------------------------------------------------

do
    local O = payload({ x = 1, y = 2.5, z = "a", keep = true, gone = 5 })
    local N = payload({ x = 1, y = 3.5, z = "a", keep = true, gone = 5 })
    local P = payload({ x = 1, y = 2.5, z = "b", keep = true, gone = 5, mine = 7 })
    local m, r = merge(O, N, P)
    eq(m.addons[F].y, 3.5, "Kitn's change is applied when the player kept the base")
    eq(m.addons[F].z, "b", "the player's change is kept when Kitn did not touch the key")
    eq(m.addons[F].mine, 7, "a key only the player has is kept")
    eq(#r.conflicts, 0, "no conflict when the player never touched what Kitn changed")
    eq(r.noBase, false, "a base was given")
end

do
    local O = payload({ y = 2.5 })
    local N = payload({ y = 3.5 })
    local P = payload({ y = 4.5 })
    local m, r = merge(O, N, P)
    eq(m.addons[F].y, 3.5, "Kitn wins a conflict")
    eq(#r.conflicts, 1, "the conflict is counted once")
    eq(r.conflicts[1], "addons." .. F .. ".y", "the conflict path names the leaf")
end

do
    local O = payload({ y = 2.5 })
    local N = payload({ y = 3.5 })
    local P = payload({ y = 3.5 })
    local m, r = merge(O, N, P)
    eq(m.addons[F].y, 3.5, "a player who already made Kitn's change gets it")
    eq(#r.conflicts, 0, "and is not counted")
end

do
    local O = payload({ keep = true, gone = 5 })
    local N = payload({ keep = true })
    local P = payload({ keep = true, gone = 5 })
    local m, r = merge(O, N, P)
    eq(m.addons[F].gone, nil, "a key Kitn removed is removed")
    eq(#r.conflicts, 0, "an untouched removal is not a conflict")
    local P2 = payload({ keep = true, gone = 6 })
    local m2, r2 = merge(O, N, P2)
    eq(m2.addons[F].gone, nil, "a key Kitn removed is removed even when the player changed it")
    eq(#r2.conflicts, 1, "and that removal is counted")
end

do
    local O = payload({ keep = true, x = 1 })
    local N = payload({ keep = true, x = 1 })
    local P = payload({ keep = true })
    local m = merge(O, N, P)
    eq(m.addons[F].x, nil, "a key the player removed stays removed when Kitn did not touch it")
end

do
    local O = payload({ sub = { a = 1, b = 2 } })
    local N = payload({ sub = { a = 1, b = 2 } })
    local P = payload({})
    local m = merge(O, N, P)
    eq(m.addons[F].sub, nil, "a subtree the player removed stays removed (rule 3)")
end

do
    local O = payload({ sub = { a = 1, b = 2 } })
    local N = payload({})
    local P = payload({ sub = { a = 1, b = 2, mine = 3 } })
    local m, r = merge(O, N, P)
    check(type(m.addons[F].sub) == "table", "a removed subtree keeps the player's own key inside it")
    eq(m.addons[F].sub.mine, 3, "the player-only key survives the removal")
    eq(m.addons[F].sub.a, nil, "Kitn's removal inside it applies")
    eq(#r.conflicts, 0, "nothing counted when the player only added")
    local P2 = payload({ sub = { a = 1, b = 2 } })
    local m2 = merge(O, N, P2)
    eq(m2.addons[F].sub, nil, "a removed subtree with nothing of the player's inside goes (rule 4)")
end

do
    local O = payload({ v = 1 })
    local N = payload({ v = { a = 1 } })
    local P = payload({ v = 1 })
    local m = merge(O, N, P)
    check(type(m.addons[F].v) == "table" and m.addons[F].v.a == 1, "a scalar O against a table N is a leaf disagreement, N taken")
    local O2 = payload({ v = { a = 1 } })
    local N2 = payload({ v = 1 })
    local P2 = payload({ v = { a = 1 } })
    local m2 = merge(O2, N2, P2)
    eq(m2.addons[F].v, 1, "a table O against a scalar N is a leaf disagreement, N taken")
end

do
    local O = payload({ t = {} })
    local N = payload({ t = {} })
    local P = payload({})
    local m = merge(O, N, P)
    eq(m.addons[F].t, nil, "empty on O and N, absent on P: the player's removal stands")
    local m2 = merge(payload({}), payload({ t = {} }), payload({}))
    check(type(m2.addons[F].t) == "table", "a table Kitn added arrives even when empty")
end

---------------------------------------------------------------------------------
-- Inherited units: folders, CDM specs, appearance roots
---------------------------------------------------------------------------------

do
    local O = { addons = { [F] = { x = 1 }, Gone = { a = 1 } } }
    local N = { addons = { [F] = { x = 1 } } }
    local P = { addons = { [F] = { x = 1 }, Gone = { a = 2, mine = 3 } } }
    local m, r = merge(O, N, P)
    eq(m.addons.Gone, nil, "a folder Kitn dropped is omitted so the importer inherits it whole")
    eq(#r.conflicts, 0, "and nothing is counted for it")
end

do
    local O = { addons = { [F] = { x = 1 } } }
    local N = { addons = { [F] = { x = 1 }, New = { a = 2 } } }
    local P = { addons = { [F] = { x = 1 } } }
    local m, r = merge(O, N, P)
    check(type(m.addons.New) == "table" and m.addons.New.a == 2, "a folder Kitn introduced arrives whole")
    eq(#r.conflicts, 0, "with no conflict")
    eq(r.applied, 1, "and counted as applied once")
    local N2 = { addons = { [F] = { x = 1 }, Same = { a = 2 } } }
    local O2 = { addons = { [F] = { x = 1 }, Same = { a = 2 } } }
    local m2 = merge(O2, N2, P)
    eq(m2.addons.Same, nil, "a folder absent from P and unchanged by Kitn is omitted (inherited)")
end

do
    local O = { addons = {}, cdmSpells = { [71] = { a = 1 }, [72] = { b = 1 } } }
    local N = { addons = {}, cdmSpells = { [71] = { a = 1 }, [72] = { b = 2 } } }
    local P = { addons = {}, cdmSpells = { [71] = { a = 1, mine = 1 } } }
    local m, r = merge(O, N, P)
    check(type(m.cdmSpells[72]) == "table" and m.cdmSpells[72].b == 2, "a spec absent from P that Kitn changed arrives whole")
    eq(#r.conflicts, 0, "with nothing counted")
    eq(m.cdmSpells[71].mine, 1, "a spec both have is walked")
    local N2 = { addons = {}, cdmSpells = { [71] = { a = 1 }, [72] = { b = 1 } } }
    local m2 = merge(O, N2, P)
    eq(m2.cdmSpells[72], nil, "a spec absent from P with N unchanged is omitted")
end

do
    local O = { addons = {}, fonts = { global = "F" }, darkMode = true, euiAccent = { 1, 0, 0 } }
    local N = { addons = {}, darkMode = false }
    local P = { addons = {}, fonts = { global = "F", size = 12 }, darkMode = true, euiAccent = { 1, 0, 0 } }
    local m, r = merge(O, N, P)
    eq(m.fonts, nil, "an appearance root Kitn dropped is omitted so the player keeps it whole")
    eq(m.euiAccent, nil, "the same for the accent")
    eq(m.darkMode, false, "a scalar root Kitn changed is applied")
    eq(#r.conflicts, 0, "nothing counted for the dropped roots")
end

---------------------------------------------------------------------------------
-- Sequences
---------------------------------------------------------------------------------

do
    local O = payload({ bars = { "A", "B" } })
    local N = payload({ bars = { "A" } })
    local P = payload({ bars = { "A", "B", "C" } })
    local m, r = merge(O, N, P)
    local bars = m.addons[F].bars
    eq(bars[1], "A", "the surviving first entry")
    eq(bars[2], "C", "the player's appended entry moves down into the hole")
    eq(bars[3], nil, "the list is dense")
    eq(#r.conflicts, 0, "zero conflicts: the player's B equals the base's")
    local reached = 0
    for _ in ipairs(bars) do reached = reached + 1 end
    eq(reached, 2, "an ipairs walk reaches the appended entry")
end

do
    local O = payload({ bars = { "A", "B" } })
    local N = payload({ bars = { "A" } })
    local P = payload({ bars = { "A", "B2", "C" } })
    local m, r = merge(O, N, P)
    eq(m.addons[F].bars[2], "C", "Kitn's removal wins over the player's change")
    eq(#r.conflicts, 1, "and is counted once")
    eq(r.conflicts[1], "addons." .. F .. ".bars.[2]", "at the pre-compaction index")
end

do
    local O = payload({ bars = { "A" } })
    local N = payload({ bars = { "A", "B" } })
    local P = payload({ bars = { "A", "C" } })
    local m, r = merge(O, N, P)
    eq(m.addons[F].bars[2], "B", "Kitn's added entry wins the index the player also filled")
    eq(#r.conflicts, 1, "counted once")
end

do
    local O = payload({ map = { [1] = "a", [3] = "c" } })
    local N = payload({ map = { [1] = "a" } })
    local P = payload({ map = { [1] = "a", [3] = "c", [5] = "e" } })
    local m = merge(O, N, P)
    eq(m.addons[F].map[5], "e", "a numeric map with a gap keeps its keys")
    eq(m.addons[F].map[2], nil, "and is not compacted")
end

do
    ns.EUI_SEQUENCE_EXEMPT["addons." .. F .. ".slots"] = true
    local O = payload({ slots = { "a", "b" } })
    local N = payload({ slots = { "a" } })
    local P = payload({ slots = { "a", "b", "c" } })
    local m = merge(O, N, P)
    eq(m.addons[F].slots[3], "c", "an exempt positional map keeps its index")
    eq(m.addons[F].slots[2], nil, "and its hole")
    ns.EUI_SEQUENCE_EXEMPT["addons." .. F .. ".slots"] = nil
end

do
    -- A map keyed by a small counter id reads as a dense list once it is
    -- dense; the frozen exemption keeps its keys when N drops one.
    local RF = "EllesmereUIRaidFrames"
    local function rf(inds)
        return { addons = { [RF] = { bm2 = { specs = { healers = { inds = inds } } } } } }
    end
    local O = rf({ { id = 1000001, filters = { [1] = true, [2] = true, [3] = true } } })
    local N = rf({ { id = 1000001, filters = { [1] = true, [2] = true } } })
    local P = rf({ { id = 1000001, filters = { [1] = true, [2] = true, [3] = true, [4] = true } } })
    local m, r = merge(O, N, P)
    local filters = m.addons[RF].bm2.specs.healers.inds[1].filters
    eq(filters[4], true, "the player's filter 4 keeps its id when Kitn drops filter 3")
    eq(filters[3], nil, "the dropped id stays dropped")
    eq(#r.conflicts, 0, "no conflict when P matches O where Kitn changed")

    -- The wildcard matches one component only: the same shape under another
    -- key is still a list and compacts.
    local O2 = rf({ { id = 1, order = { "a", "b", "c" } } })
    local N2 = rf({ { id = 1, order = { "a", "c" } } })
    local m2 = merge(O2, N2, ns.EUIDeepCopy(O2))
    eq(m2.addons[RF].bm2.specs.healers.inds[1].order[2], "c", "a list beside an exempt map still compacts")

    local CDM = "EllesmereUICooldownManager"
    local function cdm(mappings)
        return { addons = { [CDM] = { spec = { [102] = { mappings = mappings, selectedMapping = 3 } } } } }
    end
    local O3 = cdm({ { name = "a" }, { name = "b" }, { name = "c" } })
    local N3 = cdm({ { name = "a" }, { name = "b" } })
    local P3 = cdm({ { name = "a" }, { name = "b" }, { name = "c" }, { name = "d" } })
    local m3 = merge(O3, N3, P3)
    local slot4 = m3.addons[CDM].spec[102].mappings[4]
    eq(slot4 and slot4.name, "d", "a numeric spec key matches the wildcard")
    eq(m3.addons[CDM].spec[102].mappings[3], nil, "and the slot the selection points at is not renumbered")
end

---------------------------------------------------------------------------------
-- Layout entries as leaves
---------------------------------------------------------------------------------

local k2f = { bar1 = F, bar2 = F, gone1 = "Dropped", other1 = "EllesmereUIActionBars" }

do
    local O = { addons = { [F] = { x = 1 }, Dropped = { a = 1 } },
        unlockLayout = { anchors = { bar1 = { target = "x", dx = 1 }, gone1 = { target = "y", dx = 1 } } } }
    local N = { addons = { [F] = { x = 1 } },
        unlockLayout = { anchors = { bar1 = { target = "x", dx = 2 } } } }
    local P = { addons = { [F] = { x = 1 }, Dropped = { a = 1 } },
        unlockLayout = { anchors = { bar1 = { target = "x", dx = 3 }, gone1 = { target = "y", dx = 9 } } } }
    local m, r = merge(O, N, P, { keyToFolder = k2f })
    eq(m.unlockLayout.anchors.bar1.dx, 2, "an anchor is compared whole and Kitn's wins")
    eq(#r.conflicts, 1, "the player's different anchor is one conflict")
    eq(r.conflicts[1], "unlockLayout.anchors.bar1", "named by its child")
    eq(m.unlockLayout.anchors.gone1, nil, "an anchor owned by a dropped module is not walked")
    check(type(m.unlockLayout.widthMatch) == "table" and type(m.unlockLayout.heightMatch) == "table"
        and type(m.unlockLayout.phantomBounds) == "table", "the four maps always exist")
    eq(count(m.unlockLayout.phantomBounds), 0, "phantomBounds is emitted empty")
end

do
    local O = { addons = { [F] = { x = 1 } }, unlockLayout = { anchors = { bar1 = { target = "a" } } } }
    local N = { addons = { [F] = { x = 1 } } }
    local P = { addons = { [F] = { x = 1 } }, unlockLayout = { anchors = { bar1 = { target = "b" } } } }
    local m, r = merge(O, N, P, { keyToFolder = k2f })
    check(type(m.unlockLayout) == "table", "N without a layout still yields a layout table on the walked branch")
    eq(m.unlockLayout.anchors.bar1, nil, "the anchor Kitn removed is gone")
    eq(#r.conflicts, 1, "and counted, because the player had changed it")
    -- The importer boundary this shape exists for: an empty table makes it
    -- drop the base's entries for imported children; nil would keep them all.
    local function importerKeeps(payloadLayout, baseEntry)
        if payloadLayout == nil then return baseEntry end
        return payloadLayout.anchors.bar1
    end
    eq(importerKeeps(m.unlockLayout, { target = "b" }), nil, "a stubbed importer drops the anchor rather than keeping the backup's")
end

do
    local O = { addons = { [F] = { x = 1 } }, unlockLayout = { anchors = {} } }
    local N = { addons = { [F] = { x = 1 } }, unlockLayout = { anchors = {} } }
    local P = { addons = { [F] = { x = 1 } }, unlockLayout = { anchors = { bar1 = { target = "other1" } } } }
    local m = merge(O, N, P, { keyToFolder = k2f })
    check(m.unlockLayout.anchors.bar1 ~= nil, "a player-only link from an imported child is kept by the walk")
end

-- P carries both extras tables beside its links, as the export writes them;
-- O and N carry none unless a case gives them some.
local function sided(wm, wx, hm, hx)
    return { addons = { [F] = { x = 1 } },
        unlockLayout = { anchors = {}, widthMatch = wm or {}, heightMatch = hm or {}, phantomBounds = {},
            widthMatchExtra = wx, heightMatchExtra = hx } }
end

local function extraIn(m, xmap, child)
    local t = m.unlockLayout and m.unlockLayout[xmap]
    return t and t[child]
end

do
    local O = sided({ bar1 = "other1" }, nil, { bar2 = "other1" })
    local N = sided({ bar1 = "other1" }, nil, { bar2 = "other1" })
    local P = sided({ bar1 = "other1" }, { bar1 = 6 }, { bar2 = "other1" }, { bar2 = -3 })
    local m, r = merge(O, N, P, { keyToFolder = k2f })
    eq(extraIn(m, "widthMatchExtra", "bar1"), 6, "extras: the player's width extra rides the link Kitn left alone")
    eq(extraIn(m, "heightMatchExtra", "bar2"), -3, "extras: and the player's height extra")
    eq(#r.conflicts, 0, "extras: an extra kept with its link counts nothing")
end

do
    local O, N = sided({ bar1 = "other1" }), sided({ bar1 = "other1" })
    local m, r = merge(O, N, sided({ bar1 = "bar2" }, { bar1 = 6 }), { keyToFolder = k2f })
    eq(m.unlockLayout.widthMatch.bar1, "bar2", "extras: the player's re-pointed link is kept")
    eq(extraIn(m, "widthMatchExtra", "bar1"), 6, "extras: with the player's extra")
    eq(#r.conflicts, 0, "extras: and nothing is counted for either")
    local O2 = sided({ bar1 = "other1" }, { bar1 = 4 })
    local N2 = sided({ bar1 = "other1" }, { bar1 = 2 })
    local m2, r2 = merge(O2, N2, sided({ bar1 = "other1" }, { bar1 = 4 }), { keyToFolder = k2f })
    eq(extraIn(m2, "widthMatchExtra", "bar1"), 4, "extras: Kitn's extra change on a link it left alone does not reach the player")
    eq(#r2.conflicts, 0, "extras: and counts nothing")
    local m3 = merge(O2, N2, sided({ bar1 = "other1" }), { keyToFolder = k2f })
    eq(extraIn(m3, "widthMatchExtra", "bar1"), nil, "extras: nor replaces an extra the player cleared")
end

do
    local O = sided({ bar1 = "other1" })
    local N = sided({ bar1 = "bar2" })
    local P = sided({ bar1 = "other1" }, { bar1 = 6 })
    local m, r = merge(O, N, P, { keyToFolder = k2f })
    eq(m.unlockLayout.widthMatch.bar1, "bar2", "extras: Kitn's re-pointed link is taken")
    eq(extraIn(m, "widthMatchExtra", "bar1"), nil, "extras: with Kitn's extra, none, in place of the player's")
    eq(#r.conflicts, 1, "extras: the dropped extra is one change replaced")
    eq(r.conflicts[1], "unlockLayout.widthMatchExtra.bar1", "extras: named by its map and child")
    local _, r2 = merge(O, N, sided({ bar1 = "bar2" }, { bar1 = 6 }), { keyToFolder = k2f })
    eq(#r2.conflicts, 1, "extras: counted when the player's link already equals Kitn's")
    local m3, r3 = merge(O, sided({}), P, { keyToFolder = k2f })
    eq(m3.unlockLayout.widthMatch.bar1, nil, "extras: Kitn's removal of the link is taken")
    eq(extraIn(m3, "widthMatchExtra", "bar1"), nil, "extras: and the extra goes with it")
    eq(#r3.conflicts, 1, "extras: counted when Kitn removed the link")
    check(has(r3.conflicts, "unlockLayout.widthMatchExtra.bar1"), "extras: the removal's count is the extra")
    local m4, r4 = merge(O, N, sided({ bar1 = "other2" }, { bar1 = 6 }), { keyToFolder = k2f })
    eq(#r4.conflicts, 2, "extras: a changed link and its extra are two changes")
    check(has(r4.conflicts, "unlockLayout.widthMatch.bar1") and has(r4.conflicts, "unlockLayout.widthMatchExtra.bar1"),
        "extras: the link and the extra are both named")
    eq(extraIn(m4, "widthMatchExtra", "bar1"), nil, "extras: and the extra is gone")
end

do
    local O = sided({ bar1 = "other1" }, { bar1 = 4 })
    local N = sided({ bar1 = "bar2" }, { bar1 = 2 })
    local m, r = merge(O, N, sided({ bar1 = "other1" }, { bar1 = 4 }), { keyToFolder = k2f })
    eq(extraIn(m, "widthMatchExtra", "bar1"), 2, "extras: Kitn's extra rides Kitn's link")
    eq(#r.conflicts, 0, "extras: the player's extra equal to the base's is not their change")
    local _, r2 = merge(O, N, sided({ bar1 = "other1" }, { bar1 = 2 }), { keyToFolder = k2f })
    eq(#r2.conflicts, 0, "extras: the player's extra equal to Kitn's loses nothing")
    local _, r3 = merge(O, N, sided({ bar1 = "other1" }, { bar1 = 7 }), { keyToFolder = k2f })
    eq(#r3.conflicts, 1, "extras: the player's own extra is counted")
    local _, r4 = merge(O, N, sided({ bar1 = "other1" }), { keyToFolder = k2f })
    eq(#r4.conflicts, 1, "extras: clearing the base's extra is a change Kitn's replaces")
end

do
    local O, N = sided({}), sided({})
    local m, r = merge(O, N, sided({ bar1 = "other1" }, { bar1 = 5 }), { keyToFolder = k2f })
    eq(extraIn(m, "widthMatchExtra", "bar1"), 5, "extras: a player-only link keeps its extra")
    eq(#r.conflicts, 0, "extras: and counts nothing")
    local m2, r2 = merge(sided({ bar1 = "other1" }), sided({ bar1 = "other1" }), sided({}, { bar1 = 5 }), { keyToFolder = k2f })
    eq(extraIn(m2, "widthMatchExtra", "bar1"), nil, "extras: an extra without its own side's link is ignored")
    eq(#r2.conflicts, 0, "extras: and counts nothing either")
    local m3 = merge(O, N, sided({ gone1 = "other1" }, { gone1 = 5 }), { keyToFolder = k2f })
    eq(extraIn(m3, "widthMatchExtra", "gone1"), nil, "extras: a child whose module is not carried gets none")
    local m4 = merge({ addons = { [F] = { x = 1 } } }, { addons = { [F] = { x = 1 } } }, { addons = { [F] = { x = 1 } } })
    check(type(m4.unlockLayout.widthMatchExtra) == "table" and type(m4.unlockLayout.heightMatchExtra) == "table",
        "extras: both extras tables always exist on the walked branch")
end

---------------------------------------------------------------------------------
-- The override set
---------------------------------------------------------------------------------

local function overrides(t)
    local d = { addons = { [F] = { x = 1 } } }
    for k, v in pairs(t) do d[k] = v end
    return d
end

do
    local base = { specOverrides = { { fkey = "a", values = { default = 1 } } },
        specUnlockOverrides = { active = 1, baselineLayout = { anchors = { a = 1 }, widthMatch = {}, heightMatch = {}, cdmPos = { X = 10 }, elems = {} }, layouts = {} },
        specBmOverrides = { active = 2, baselineLayout = { iconZoom = 0.1 }, layouts = {} } }
    local O = overrides(ns.EUIDeepCopy(base))
    local N = overrides(ns.EUIDeepCopy(base))
    N.specUnlockOverrides.active = nil
    N.specBmOverrides.active = 7
    N.specUnlockOverrides.baselineLayout.anchors = { z = 9 }
    local P = overrides(ns.EUIDeepCopy(base))
    P.specOverrides[1].values.default = 5
    P.specUnlockOverrides.baselineLayout.cdmPos.X = 99
    local m, r = merge(O, N, P)
    eq(r.overrideSet, "player", "O and N differing only in the masks keep the player's set")
    eq(m.specOverrides[1].values.default, 5, "the player's set is carried")
    eq(m.specUnlockOverrides.baselineLayout.cdmPos.X, 99, "with its geometry untouched")
    eq(#r.conflicts, 0, "no conflict")
end

do
    local base = { specBmOverrides = { active = 2, baselineLayout = { iconZoom = 0.1 }, layouts = {} } }
    local O = overrides(ns.EUIDeepCopy(base))
    local N = overrides(ns.EUIDeepCopy(base))
    N.specBmOverrides.baselineLayout.iconZoom = 0.2
    local P = overrides(ns.EUIDeepCopy(base))
    P.specBmOverrides.baselineLayout.iconZoom = 0.15
    local m, r = merge(O, N, P)
    eq(r.overrideSet, "kitn", "a Buff Manager baseline change takes Kitn's set")
    eq(m.specBmOverrides.baselineLayout.iconZoom, 0.2, "carried whole")
    eq(#r.conflicts, 1, "one conflict when the player differs from both")
    eq(r.conflicts[1], "Spec Overrides", "named Spec Overrides")
    local P2 = overrides(ns.EUIDeepCopy(base))
    local _, r2 = merge(O, N, P2)
    eq(#r2.conflicts, 0, "no conflict when the player's set equals the base")
    local _, r3 = merge(O, N, overrides(ns.EUIDeepCopy(N)))
    eq(#r3.conflicts, 0, "no conflict when the player's set already equals Kitn's")
end

do
    -- Measured on a pure install: element sizes are live and class-bound, an
    -- element exists only where the character registers it, and the id
    -- counters are bookkeeping. None of them may select a set or count.
    local function withElems(elems, extra)
        local d = overrides({
            specOverrides = { { fkey = "a", values = { default = 1 } } },
            specUnlockOverrides = { active = 1, baselineLayout = { anchors = {}, widthMatch = {}, heightMatch = {},
                cdmPos = { X = 10 }, elems = elems }, layouts = {} },
            condOverrideNextId = 1,
        })
        for k, v in pairs(extra or {}) do d[k] = v end
        return d
    end
    local O = withElems({ TopBar = { point = "TOP", relPoint = "TOP", x = 0, y = -2, w = 467, h = 30 } })
    local N = withElems({ TopBar = { point = "TOP", relPoint = "TOP", x = 0, y = -2, w = 467, h = 30 } })
    N.specOverrides[1].values.default = 2
    local P = withElems({
        TopBar = { point = "TOP", relPoint = "TOP", x = 0, y = -2, w = 449, h = 30 },
        TotemTracker = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, w = 100, h = 20 },
    })
    P.condOverrideNextId = nil
    local m, r = merge(O, N, P)
    eq(r.overrideSet, "kitn", "a Kitn override change takes Kitn's set")
    eq(#r.conflicts, 0, "a size drift, an extra element and a missing counter count nothing")
    eq(m.specOverrides[1].values.default, 2, "the carried set is Kitn's")
    eq(m.condOverrideNextId, 1, "the carried set keeps its counter")

    local P6 = withElems({ TopBar = { point = "TOP", relPoint = "TOP", x = 0, y = -2, w = 467, h = 30 } })
    P6.condOverrideNextId = 7
    P6.specOverrideNextId = 9
    local _, r6 = merge(O, N, P6)
    eq(#r6.conflicts, 0, "counters that differ on every side count nothing")
    local N7 = withElems({ TopBar = { point = "TOP", relPoint = "TOP", x = 0, y = -2, w = 467, h = 30 } })
    N7.specOverrideNextId = 3
    local m7, r7 = merge(O, N7, ns.EUIDeepCopy(O))
    eq(r7.overrideSet, "player", "O and N differing only in a counter keep the player's set")
    eq(m7.specOverrideNextId, nil, "and the player's set is carried as it is")

    local N2 = withElems({ TopBar = { point = "TOP", relPoint = "TOP", x = 0, y = -2, w = 480, h = 32 } })
    local _, r2 = merge(O, N2, ns.EUIDeepCopy(P))
    eq(r2.overrideSet, "player", "O and N differing only in element sizes keep the player's set")

    local P3 = withElems({ TopBar = { point = "TOP", relPoint = "TOP", x = 40, y = -2, w = 449, h = 30 } })
    local _, r3 = merge(O, N, P3)
    eq(#r3.conflicts, 1, "a moved element still counts when Kitn's set is taken")

    local N4 = withElems({ TopBar = { point = "TOP", relPoint = "TOP", x = 0, y = -2, w = 467, h = 30 } })
    N4.specUnlockOverrides.layouts[1] = { elems = { TopBar = { point = "TOP", relPoint = "TOP", x = 0, y = -2, w = 470, h = 30 } } }
    local O4 = ns.EUIDeepCopy(N4)
    O4.specUnlockOverrides.layouts[1].elems.TopBar.w = 460
    local _, r4 = merge(O4, N4, ns.EUIDeepCopy(O4))
    eq(r4.overrideSet, "player", "a fork layer's size drift does not select a set")

    local N5 = withElems({}, { condAppliedGid = 1 })
    local m5 = merge(withElems({}, { condAppliedGid = 1 }), N5, withElems({}))
    eq(m5.condAppliedGid, 1, "the applied conditional pointer is taken from N")
end

do
    local base = { specUnlockOverrides = { baselineLayout = { anchors = {}, cdmPos = { X = 10, Y = 20 } }, layouts = {} } }
    local O = overrides(ns.EUIDeepCopy(base))
    O.addons[F].cdmBarPositions = { X = 10, Y = 20 }
    local N = overrides(ns.EUIDeepCopy(base))
    N.specUnlockOverrides.baselineLayout.cdmPos.Y = 25
    N.addons[F].cdmBarPositions = { X = 10, Y = 25 }
    local P = overrides(ns.EUIDeepCopy(base))
    P.specUnlockOverrides.baselineLayout.cdmPos.X = 15
    P.addons[F].cdmBarPositions = { X = 15, Y = 20 }
    local m, r = merge(O, N, P)
    eq(r.overrideSet, "kitn", "a Kitn bar move in the baseline takes Kitn's set")
    eq(#r.conflicts, 1, "exactly one conflict")
    eq(r.conflicts[1], "Spec Overrides", "named Spec Overrides: the set is one path")
    eq(m.specUnlockOverrides.baselineLayout.cdmPos.X, 10, "the carried baseline holds Kitn's X, which the converge will apply")
    eq(m.addons[F].cdmBarPositions.X, 15, "while the module table's walk kept the player's X until then")
end

do
    local O = overrides({ specUnlockOverrides = { layouts = { [1] = { cdmPos = { X = 1 } } } } })
    local N = overrides({ specUnlockOverrides = { layouts = { [1] = { cdmPos = { X = 2 } } } } })
    local P = overrides({ specUnlockOverrides = { layouts = { [1] = { cdmPos = { X = 3 } } } } })
    local m, r = merge(O, N, P)
    eq(r.overrideSet, "kitn", "a fork change takes Kitn's set")
    eq(m.specUnlockOverrides.layouts[1].cdmPos.X, 2, "carried whole")
    eq(#r.conflicts, 1, "one conflict when the player differs")
end

do
    -- Selection is O against N; the count is P against both.
    local noBase = overrides({ specOverrides = {} })
    local withBase = overrides({ specOverrides = {}, specUnlockOverrides = { baselineLayout = { cdmPos = { X = 1 } }, layouts = {} } })
    local _, r1 = merge(noBase, withBase, ns.EUIDeepCopy(noBase))
    eq(r1.overrideSet, "kitn", "O = P without a baseline, N adds one: Kitn's set")
    eq(#r1.conflicts, 0, "zero conflicts")
    local _, r2 = merge(withBase, ns.EUIDeepCopy(withBase), ns.EUIDeepCopy(noBase))
    eq(r2.overrideSet, "player", "O = N with a baseline, P lacks it: the player's set")
    eq(#r2.conflicts, 0, "zero conflicts whatever else P edited")
    local N3 = ns.EUIDeepCopy(withBase)
    N3.specUnlockOverrides.baselineLayout.cdmPos.X = 2
    local _, r3 = merge(withBase, N3, ns.EUIDeepCopy(noBase))
    eq(r3.overrideSet, "kitn", "different baseline geometry: Kitn's set")
    eq(#r3.conflicts, 1, "one conflict when P lacks the baseline and differs from both")
end

do
    -- The current harvest writes both extras tables into every layer and banks
    -- a Player Aura Bars element raw from its stored position; the base and
    -- Kitn's string hold neither.
    local visual = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 3, y = -30, w = 200, h = 20 }
    local function raw(x, design, w)
        return { point = "TOPLEFT", relPoint = "TOPLEFT", x = x, y = -4, design = design, rawPos = true, w = w or 200, h = 20 }
    end
    local function layer(elem, wx)
        return { anchors = {}, widthMatch = { bar1 = "other1" }, heightMatch = {}, cdmPos = { X = 10 },
            elems = { PlayerBuffs = elem }, widthMatchExtra = wx, heightMatchExtra = wx and {} or nil }
    end
    local function set(default, baseElem, forkElem, baseWx, forkWx)
        return overrides({
            specOverrides = { { fkey = "a", values = { default = default } } },
            specUnlockOverrides = { baselineLayout = layer(baseElem, baseWx), layouts = { [1] = layer(forkElem, forkWx) } },
        })
    end
    local O, N = set(1, visual, visual), set(2, visual, visual)
    local m, r = merge(O, N, set(1, raw(10), raw(10), { bar1 = 5 }, {}))
    eq(r.overrideSet, "kitn", "layer format: Kitn's changed set is taken")
    eq(#r.conflicts, 0, "layer format: extras tables and raw positions alone are not the player's change")
    eq(m.specOverrides[1].values.default, 2, "layer format: the carried set is Kitn's")
    local _, r2 = merge(O, N, set(1, raw(10), raw(10), {}, { bar1 = 5 }))
    eq(#r2.conflicts, 1, "layer format: an extra the player set inside a layer is their change")
    eq(r2.conflicts[1], "Spec Overrides", "layer format: counted as the override set")
    local masked = ns.EUIMaskedOverrideSet(set(1, raw(10), raw(10), { bar1 = 5 }, {}))
    eq(masked.specUnlockOverrides.baselineLayout.widthMatchExtra, nil, "layer format: the masked baseline carries no extras")
    local _, r3 = merge(O, ns.EUIDeepCopy(O), set(1, raw(10), raw(10), { bar1 = 5 }, {}))
    eq(r3.overrideSet, "player", "layer format: an unchanged Kitn set keeps the player's")

    local rO, rN = set(1, raw(10), raw(10)), set(2, raw(10), raw(10))
    local _, r4 = merge(rO, rN, set(1, raw(10), raw(12)))
    eq(#r4.conflicts, 1, "raw positions: a moved raw element counts")
    local _, r5 = merge(rO, rN, set(1, raw(10), raw(10, true)))
    eq(#r5.conflicts, 1, "raw positions: a changed design flag counts")
    local _, r6 = merge(rO, rN, set(1, raw(10), raw(10, nil, 180)))
    eq(#r6.conflicts, 0, "raw positions: a raw size drift does not")
    local _, r7 = merge(rO, set(1, raw(10), visual), set(1, raw(10), raw(10)))
    eq(r7.overrideSet, "player", "raw positions: a format-only difference does not select Kitn's set")
end

---------------------------------------------------------------------------------
-- Special keys
---------------------------------------------------------------------------------

do
    local O = { addons = {}, uiScale = 0.9, assignedSpecs = { 1 }, _migrations = { a = 1 }, unlockLayoutMeta = { keyToFolder = {} },
        blizzSkinGlobals = { x = 1 }, clickCast = { y = 1 } }
    local N = { addons = {}, uiScale = 0.8, assignedSpecs = { 2 }, _migrations = { a = 2 }, unlockLayoutMeta = { keyToFolder = {} },
        blizzSkinGlobals = { x = 2 }, applyBlizzSkinGlobals = true, clickCast = { y = 2 }, tbbPositions = {}, layoutExcluded = true }
    local P = { addons = {}, uiScale = 1.0, assignedSpecs = { 3 } }
    local m, r = merge(O, N, P)
    eq(m.assignedSpecs[1], 3, "assignedSpecs is the player's")
    eq(m._migrations.a, 2, "_migrations is Kitn's when a table")
    eq(m.unlockLayoutMeta, nil, "the meta never reaches the importer")
    eq(m.blizzSkinGlobals, nil, "BlizzardSkin globals are stripped")
    eq(m.applyBlizzSkinGlobals, nil, "and their apply flag")
    eq(m.clickCast, nil, "transport data is stripped")
    eq(m.tbbPositions, nil, "and per-character positions")
    eq(m.layoutExcluded, nil, "and the exclusion stamp")
    eq(m.uiScale, 0.8, "Kitn changed the scale to a valid value: taken")
    check(has(r.conflicts, "uiScale"), "and the player's different scale is one conflict")
    eq(m.applyUIScale, nil, "applyUIScale is never set")
end

do
    local O = { addons = {}, uiScale = 0.9 }
    local N = { addons = {} }
    local P = { addons = {}, uiScale = 1.0 }
    local m, r = merge(O, N, P)
    eq(m.uiScale, nil, "N without a scale leaves the player's alone")
    eq(#r.conflicts, 0, "and counts nothing")
    local N2 = { addons = {}, uiScale = 2.0 }
    local m2, r2 = merge(O, N2, P)
    eq(m2.uiScale, nil, "N out of range leaves the player's alone")
    eq(#r2.conflicts, 0, "and counts nothing")
    local N3 = { addons = {}, uiScale = 0.9 }
    local m3 = merge(O, N3, P)
    eq(m3.uiScale, nil, "N unchanged from O leaves the player's alone")
end

do
    local O = { addons = {}, _migrations = { a = 1 } }
    local N = { addons = {} }
    local P = { addons = {}, _migrations = { a = 1 } }
    local m = merge(O, N, P)
    eq(m._migrations, nil, "no migrations from N: absent, the importer keeps the backup's stamps")
end

---------------------------------------------------------------------------------
-- Importer-reset leaves
---------------------------------------------------------------------------------

do
    local RB = "EllesmereUIResourceBars"
    local function rb(colored, r)
        return { addons = { [RB] = { health = { customColored = colored, fillR = r, fillG = 0, fillB = 0 } } } }
    end
    local O, N, P = rb(false, 0), rb(true, 1), rb(true, 0.5)
    local _, r1 = merge(O, N, P, { healthReset = true })
    eq(#r1.conflicts, 0, "health leaves are not counted when the importer will reset them")
    local _, r2 = merge(O, N, P, { healthReset = false })
    eq(#r2.conflicts, 1, "and are counted when it will not (stored without activating, or module unloaded)")
end

---------------------------------------------------------------------------------
-- The no-base branch
---------------------------------------------------------------------------------

do
    local N = { addons = { [F] = { x = 1 } }, unlockLayout = { anchors = { bar1 = { target = "a" }, gone1 = { target = "b" } }, widthMatch = {}, heightMatch = {}, phantomBounds = {} },
        assignedSpecs = { 2 }, uiScale = 0.8, clickCast = { y = 1 }, specOverrides = { { fkey = "k" } } }
    local P = { addons = { [F] = { x = 5, mine = 1 } }, assignedSpecs = { 3 }, uiScale = 1.0 }
    local m, r = merge(nil, N, P, { keyToFolder = k2f })
    eq(r.noBase, true, "no base is reported")
    eq(m.addons[F].x, 1, "Kitn's value replaces the player's")
    eq(m.addons[F].mine, nil, "player-only keys are not kept")
    eq(m.assignedSpecs[1], 3, "the assignments are still the player's")
    eq(m.uiScale, 0.8, "the scale rule still applies")
    eq(m.clickCast, nil, "transport data is still stripped")
    eq(m.unlockLayout.anchors.bar1.target, "a", "N's layout entries for carried modules stay")
    eq(m.unlockLayout.anchors.gone1, nil, "an entry whose module N's addons lack is pruned")
    eq(m.specOverrides[1].fkey, "k", "N's override set stands")
end

do
    local N = { addons = { [F] = { x = 1 } } }
    local P = { addons = { [F] = { x = 5 } } }
    local m = merge(nil, N, P)
    eq(m.unlockLayout, nil, "a shipped string without a layout keeps N's shape on the no-base branch")
end

do
    local N = sided({ bar1 = "other1", gone1 = "other1" }, { bar1 = 3, gone1 = 4 })
    local m, r = merge(nil, N, sided({ bar1 = "other1" }, { bar1 = 9 }), { keyToFolder = k2f })
    eq(extraIn(m, "widthMatchExtra", "bar1"), 3, "no base: Kitn's extra is carried")
    eq(extraIn(m, "widthMatchExtra", "gone1"), nil, "no base: a pruned child's extra is pruned")
    eq(#r.conflicts, 0, "no base: nothing is counted")
end

do
    -- A root unit that is a scalar on one side and a table on another is a
    -- leaf: N's whole value, applied, no conflict, no walk into a string.
    local O = { addons = {}, fonts = "old" }
    local N = { addons = {}, fonts = { global = "new" } }
    local P = { addons = {}, fonts = "old" }
    local ok, m, r = pcall(merge, O, N, P)
    check(ok, "a scalar root unit against a table does not error")
    eq(m and m.fonts and m.fonts.global, "new", "N's table is taken whole")
    eq(r and r.applied, 1, "and counted as applied")
    eq(r and #r.conflicts, 0, "with no conflict when P equals O")
    local m2, r2 = merge({ addons = {}, fonts = { global = "a" } }, { addons = {}, fonts = "flat" },
        { addons = {}, fonts = { global = "b" } })
    eq(m2.fonts, "flat", "the reverse takes N's scalar")
    eq(#r2.conflicts, 1, "and counts the conflict when P changed the table")
end

do
    -- The exporter's subset stamps never survive either branch.
    local stamped = { addons = {}, overridesIncluded = true, overridesExcluded = true, partialImport = true }
    local m = merge(stamped, ns.EUIDeepCopy(stamped), ns.EUIDeepCopy(stamped))
    check(m.overridesIncluded == nil and m.overridesExcluded == nil and m.partialImport == nil,
        "the walk drops the three stamps")
    local m2 = merge(nil, ns.EUIDeepCopy(stamped), ns.EUIDeepCopy(stamped))
    check(m2.overridesIncluded == nil and m2.overridesExcluded == nil and m2.partialImport == nil,
        "the no-base copy drops them too")
end

do
    -- The no-base copy carries N's override set and says so.
    local N = overrides({ specOverrides = { { fkey = "a", values = { default = 1 } } } })
    local _, r = merge(nil, N, overrides({ specOverrides = { { fkey = "b", values = { default = 2 } } } }))
    eq(r.overrideSet, "kitn", "no base: N's set is the carried one")
    local _, r2 = merge(nil, { addons = {} }, overrides({ specOverrides = { { fkey = "b" } } }))
    eq(r2.overrideSet, "none", "no base and no set in N: none")
end

do
    -- The retained anchor: Kitn changed an override value, so N's set is
    -- taken; O and N share an element's root anchor that P offset. The
    -- walk keeps P's anchor in the layout it emits.
    local function withAnchor(x, default)
        local d = overrides({
            specOverrides = { { fkey = "a", values = { default = default } } },
            specUnlockOverrides = { baselineLayout = { anchors = {}, widthMatch = {}, heightMatch = {},
                elems = { A_1 = { point = "TOP", relPoint = "TOP", x = 0, y = 0, w = 100, h = 20 } } }, layouts = {} },
        })
        d.addons = { FA = { on = true } }
        d.unlockLayout = { anchors = { A_1 = { target = "A_2", point = "TOP", relPoint = "BOTTOM", x = x, y = 0 } },
            widthMatch = {}, heightMatch = {}, phantomBounds = {} }
        return d
    end
    local O, N, P = withAnchor(0, 1), withAnchor(0, 2), withAnchor(25, 1)
    local m, r = merge(O, N, P, { keyToFolder = { A_1 = "FA", A_2 = "FA" } })
    eq(r.overrideSet, "kitn", "retained anchor: Kitn's set is taken")
    local kept = m.unlockLayout.anchors.A_1
    check(type(kept) == "table" and kept.target == "A_2" and kept.point == "TOP" and kept.relPoint == "BOTTOM"
        and kept.x == 25 and kept.y == 0, "retained anchor: the player's anchor survives the walk whole")

    -- The importer boundary, mirrored: an activated import copies the merged
    -- anchors into the carried baseline. The flush, mirrored: an element the
    -- baseline anchors (a table with a target) never has its position
    -- written. Both are mirrors of the reference and prove the shape the
    -- merge hands over, nothing more.
    local carried = m.specUnlockOverrides.baselineLayout
    carried.anchors = ns.EUIDeepCopy(m.unlockLayout.anchors)
    local function anchorOwned(key)
        local info = carried.anchors[key]
        return type(info) == "table" and info.target ~= nil
    end
    local writes = {}
    for key, e in pairs(carried.elems) do
        if e.point and not anchorOwned(key) then writes[key] = true end
    end
    eq(carried.anchors.A_1.x, 25, "retained anchor: the carried baseline holds the kept anchor")
    check(anchorOwned("A_1"), "retained anchor: the carried anchor is one the flush treats as owning")
    eq(writes.A_1, nil, "retained anchor: the flush paints no position for the anchored element")
    eq(#r.conflicts, 0, "retained anchor: nothing is counted when P kept O's override value")
    eq(r.kept, 1, "retained anchor: the offset is the one kept edit")
end

do
    -- A root unit that is a sequence compacts like any walked sequence.
    local O = { fonts = { "A", "B" } }
    local N = { fonts = { "A" } }
    local P = { fonts = { "A", "B", "C" } }
    local m, r = merge(O, N, P)
    eq(#m.fonts, 2, "a sequence root unit is dense after the walk")
    check(m.fonts[1] == "A" and m.fonts[2] == "C", "with N's removal and P's addition")
    eq(#r.conflicts, 0, "and nothing counted when P's dropped entry equals O's")
    local m2 = merge({ addons = { FA = { list = { "A", "B" } } } }, { addons = { FA = { list = { "A" } } } },
        { addons = { FA = { list = { "A", "B", "C" } } } })
    eq(#m2.addons.FA.list, 2, "a sequence inside a folder unit compacts too")
end

do
    -- The merge reads its inputs and writes none of them, so a plan can be
    -- rebuilt from the same three tables.
    local O = { addons = { FA = { x = 1, list = { "a", "b" } } }, fonts = { global = "f" } }
    local N = { addons = { FA = { x = 2, list = { "a" } } }, fonts = { global = "g" } }
    local P = { addons = { FA = { x = 3, list = { "a", "b", "c" } } }, fonts = { global = "h" },
        specOverrides = { { fkey = "a" } } }
    local cO, cN, cP = ns.EUIDeepCopy(O), ns.EUIDeepCopy(N), ns.EUIDeepCopy(P)
    merge(O, N, P)
    check(ns.EUISame(O, cO) and ns.EUISame(N, cN) and ns.EUISame(P, cP), "the inputs are untouched by a merge")
end

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
