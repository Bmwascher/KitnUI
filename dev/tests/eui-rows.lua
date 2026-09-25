-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-rows.lua                                                ║
-- ║  Purpose: Gate for the EllesmereUI parts: rows, ownership,   ║
-- ║           the composite base, the slice swap, the counting   ║
-- ║           walk, names, split links and the per-part record.  ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/eui-rows.lua

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

local ns = { profileName = "KitnUI", title = "KitnUI", data = {} }
for _, file in ipairs({ "Installer/Merge.lua", "Installer/MergeInputs.lua", "Installer/ModuleRows.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", ns)
end

local UF, AB, RB = "EllesmereUIUnitFrames", "EllesmereUIActionBars", "EllesmereUIResourceBars"
local CDM, NP = "EllesmereUICooldownManager", "EllesmereUINameplates"
local DATABARS, TOP_BAR = "EllesmereUIDataBars", "KitnUI_EUI"

local function rowIds(list)
    local ids = {}
    for i, row in ipairs(list) do ids[i] = row.id end
    return table.concat(ids, ",")
end

---------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------

local map = {
    { folder = AB, display = "Action Bars" },
    { folder = NP, display = "Nameplates" },
    { folder = UF, display = "Unit Frames" },
    { folder = CDM, display = "Cooldown Manager" },
    { folder = RB, display = "Resource Bars" },
    { folder = DATABARS, display = "DataBars" },
    { folder = "EllesmereUIMinimap", display = "Minimap" },
}
local roster = { { folder = RB, display = "Resource & Cast Bars" } }
local nAddons = { [AB] = {}, [NP] = {}, [UF] = {}, [CDM] = {}, [RB] = {}, [DATABARS] = {}, [TOP_BAR] = {} }

local rows = ns.EUIRows(map, roster, nAddons, { DATABARS, NP })
eq(rowIds(rows), table.concat({ AB, NP, UF, CDM, RB, TOP_BAR, "general", "overrides" }, ","),
    "rows: map order, always-off and absent modules dropped, then Top Bar, General, Spec Overrides")
eq(rows[2].off, "Plater chosen", "rows: Nameplates is kept and marked off")
eq(rows[1].off, nil, "rows: a kept module is not off")
eq(rows[5].label, "Resource & Cast Bars", "rows: the roster's name wins")
eq(rows[1].label, "Action Bars", "rows: the map's name is the fallback")
eq(rows[6].label, "Top Bar", "rows: the Top Bar row's label")
eq(rows[6].sub, "KitnUI", "rows: the Top Bar row's sub")
eq(rows[7].sub, "fonts, colours, scale", "rows: the General row's sub")
eq(rows[8].sub, "all or nothing", "rows: the Spec Overrides row's sub")

nAddons[TOP_BAR] = nil
eq(rowIds(ns.EUIRows(map, roster, nAddons, {})), table.concat({ AB, NP, UF, CDM, RB, DATABARS, "general", "overrides" }, ","),
    "rows: no Top Bar row without its folder, and nothing dropped with nothing disabled")

local unread = ns.EUIRows(nil, nil, { [UF] = {}, [AB] = {} }, {})
eq(rowIds(unread), table.concat({ AB, UF, "general", "overrides" }, ","), "rows: an unreadable map lists the payload's folders, sorted")
eq(unread[1].label, AB, "rows: with no name anywhere the folder is the label")
eq(rowIds(ns.EUIRows({ { folder = UF } }, nil, { [UF] = {}, [AB] = {} }, {})), table.concat({ UF, "general", "overrides" }, ","),
    "rows: a readable map that leaves a payload folder out gives it no row")
eq(rowIds(ns.EUIRows({ { folder = UF }, "unreadable" }, nil, { [UF] = {}, [AB] = {} }, {})), table.concat({ UF, AB, "general", "overrides" }, ","),
    "rows: a partly unreadable map lends that folder a row")

---------------------------------------------------------------------------------
-- Ownership
---------------------------------------------------------------------------------

local k2f = { UF_Player = UF, AB_Main = AB }
eq(ns.EUIRowOf("addons." .. UF .. ".player.healthHeight", k2f), UF, "owner: a module leaf")
eq(ns.EUIRowOf("cdmSpells.spec.x", k2f), CDM, "owner: the spell store is the Cooldown Manager's")
eq(ns.EUIRowOf("unlockLayout.anchors.UF_Player", k2f), UF, "owner: a layout entry by its child")
eq(ns.EUIRowOf("unlockLayout.widthMatch.Unknown", k2f), nil, "owner: an unresolved child has no row")
eq(ns.EUIRowOf("Spec Overrides", k2f), "overrides", "owner: the override set")
eq(ns.EUIRowOf("unlockOverrideAnchors.ERB_CastBar", k2f), "overrides", "owner: an override store")
eq(ns.EUIRowOf("uiScale", k2f), "general", "owner: the scale")
eq(ns.EUIRowOf("fonts.global", k2f), "general", "owner: a font")
eq(ns.EUIRowOf("customRootKey", k2f), "general", "owner: any other walked root key")
eq(ns.EUIRowOf("assignedSpecs", k2f), nil, "owner: a key the merge decides itself")

---------------------------------------------------------------------------------
-- Composite base
---------------------------------------------------------------------------------

local simple = {
    { id = UF, label = "Unit Frames" },
    { id = AB, label = "Action Bars" },
    { id = "general", label = "General" },
    { id = "overrides", label = "Spec Overrides" },
}
local stampBase = {
    addons = { [UF] = { v = "stamp" }, [AB] = { v = "stamp" } },
    fonts = { f = "stamp" },
    uiScale = 0.8,
    unlockLayout = { anchors = { UF_Player = { s = "stamp" }, AB_Main = { s = "stamp" } } },
    specOverrides = { "stamp" },
}
local olderBase = {
    addons = { [UF] = { v = "older" } },
    fonts = { f = "older" },
    unlockLayout = { anchors = { UF_Player = { s = "older" } } },
}
local O, missing = ns.EUIComposeBase(simple, { [UF] = { version = "V1" }, [AB] = { version = "none" } },
    { S = stampBase, V1 = olderBase }, "S", k2f)
eq(O.addons[UF].v, "older", "compose: a row at an older version takes that version's folder")
eq(O.unlockLayout.anchors.UF_Player.s, "older", "compose: and its layout entries")
eq(O.addons[AB], nil, "compose: a row at none contributes no folder")
eq(O.unlockLayout.anchors.AB_Main, nil, "compose: and no layout entries")
check(missing[AB] and not missing[UF], "compose: the none row is reported missing")
eq(O.fonts.f, "stamp", "compose: a row with no record comes from the stamp's base")
eq(O.uiScale, 0.8, "compose: the scale comes from the stamp's base")
eq(O.specOverrides[1], "stamp", "compose: the overrides come from the stamp's base")
eq(stampBase.addons[UF].v, "stamp", "compose: the decoded base is not written")

local noO, allMissing = ns.EUIComposeBase(simple, nil, {}, "S", k2f)
eq(noO, nil, "compose: no base anywhere is nil")
check(allMissing[UF] and allMissing.general, "compose: and every row is missing")

local partO, partMissing = ns.EUIComposeBase(simple, { [UF] = { version = "V1" } }, { V1 = olderBase }, "S", k2f)
eq(partO.addons[UF].v, "older", "compose: without the stamp's base an older row still has its slice")
check(partMissing[AB] and partMissing.general and partMissing.overrides and not partMissing[UF],
    "compose: and every row without a record is missing")

---------------------------------------------------------------------------------
-- Slice swap, conflicts by row, slice take
---------------------------------------------------------------------------------

local merged = {
    addons = { [UF] = { v = "merged" }, [AB] = { v = "merged" } },
    fonts = { f = "merged" },
    uiScale = 0.8,
    unlockLayout = { anchors = { UF_Player = { s = "merged" }, AB_Main = { s = "merged" } }, widthMatch = {}, heightMatch = {} },
    specOverrides = { "kitn" },
}
local report = {
    conflicts = { "addons." .. UF .. ".v", "addons." .. AB .. ".v", "fonts.f", "uiScale", "Spec Overrides",
        "unlockLayout.anchors.UF_Player" },
    overrideSet = "kitn",
}
local P = {
    addons = { [UF] = { v = "player" } },
    fonts = { f = "player" },
    uiScale = 0.7,
    unlockLayout = { anchors = { UF_Player = { s = "player" } } },
    specOverrides = { "player" },
}
ns.EUIKeepSlices(merged, report, P, simple, { [AB] = true }, k2f)
eq(merged.addons[UF].v, "player", "keep: an unticked module takes the player's folder")
eq(merged.addons[AB].v, "merged", "keep: a ticked module keeps the merge")
eq(merged.unlockLayout.anchors.UF_Player.s, "player", "keep: an unticked module's layout entry is the player's")
eq(merged.unlockLayout.anchors.AB_Main.s, "merged", "keep: a ticked module's layout entry is the merge's")
eq(merged.fonts.f, "player", "keep: an unticked General takes the player's fonts")
eq(merged.uiScale, nil, "keep: an unticked General applies no scale")
eq(merged.specOverrides[1], "player", "keep: unticked Spec Overrides are the player's")
eq(report.overrideSet, "player", "keep: and the report says so")
eq(#report.conflicts, 1, "keep: only the ticked row's conflict remains")
eq(report.conflicts[1], "addons." .. AB .. ".v", "keep: and it is that one")
local byRow = ns.EUIByRow(report.conflicts, { [AB] = true }, k2f)
eq(byRow[AB], 1, "by row: the ticked row counts its conflict")
eq(byRow[UF], nil, "by row: an unticked row is absent")

local bare = { addons = { [UF] = { v = 1 } } }
local bareReport = { conflicts = {} }
ns.EUIKeepSlices(bare, bareReport, { addons = {} }, simple, { [AB] = true, general = true }, k2f)
eq(bare.addons[UF], nil, "keep: a folder the player lacks is left out, so the import inherits it")
eq(bareReport.overrideSet, "none", "keep: unticked Spec Overrides with none of the player's is none")

local offRows = { { id = NP, label = "Nameplates", off = "Plater chosen" } }
local offMerged = { addons = { [NP] = { v = "kitn" } } }
ns.EUIKeepSlices(offMerged, { conflicts = {} }, { addons = { [NP] = { v = "player" } } }, offRows, { [NP] = true }, k2f)
eq(offMerged.addons[NP].v, "player", "keep: an off row is never taken, ticked or not")

local taken = { addons = { [UF] = { v = "player" } }, fonts = { f = "player" } }
local N = {
    addons = { [UF] = { v = "kitn" } },
    fonts = { f = "kitn" },
    uiScale = 0.9,
    unlockLayout = { anchors = { UF_Player = { s = "kitn" } } },
}
ns.EUITakeSlice(taken, N, { id = UF }, k2f)
eq(taken.addons[UF].v, "kitn", "take: the row's folder is KitnUI's")
eq(taken.unlockLayout.anchors.UF_Player.s, "kitn", "take: and its layout entries")
eq(taken.fonts.f, "player", "take: another row is untouched")
ns.EUITakeSlice(taken, N, { id = "general" }, k2f)
eq(taken.fonts.f, "kitn", "take: General takes KitnUI's fonts")
eq(taken.uiScale, 0.9, "take: and a scale inside the range")
N.uiScale = 2
ns.EUITakeSlice(taken, N, { id = "general" }, k2f)
eq(taken.uiScale, nil, "take: a scale outside the range is not applied")

---------------------------------------------------------------------------------
-- The per-part record
---------------------------------------------------------------------------------

local rowsR = { { id = "A" }, { id = "B" }, { id = "C" } }
local at, bs = ns.EUIRecordRows("update", { stamp = "V1" }, {
    rows = rowsR, ticked = { A = true }, changed = { A = true, B = true },
    prior = { version = "V1", base = "str1" }, kitn = "2.1.0",
})
eq(at.A, nil, "record: a ticked row stands at the new stamp")
eq(at.B.version, "V1", "record: an unticked changed row stays at the version it had")
eq(at.B.kitn, "2.1.0", "record: with the KitnUI version that skipped it")
eq(at.C, nil, "record: an unticked unchanged row with no record gets none")
eq(bs.V1, "str1", "record: the version's string is kept")

at, bs = ns.EUIRecordRows("update", { rowAt = at, bases = bs, stamp = "V2" }, {
    rows = rowsR, ticked = { A = true }, changed = { A = true, B = true, C = true },
    prior = { version = "V2", base = "str2" }, kitn = "2.2.0",
})
eq(at.B.version, "V1", "record: a row already waiting keeps its own entry")
eq(at.B.kitn, "2.1.0", "record: and the version that first skipped it")
eq(at.C.version, "V2", "record: a newly skipped row takes the prior stamp")
check(bs.V1 == "str1" and bs.V2 == "str2", "record: both strings are kept")

at, bs = ns.EUIRecordRows("update", { stamp = "V1" }, {
    rows = rowsR, ticked = {}, changed = { B = true }, prior = { version = "V1" }, kitn = "k",
})
eq(at.B.version, "none", "record: with no base the row stands at none")
eq(bs, nil, "record: and no string is stored")

-- A folder skipped at V1 that the V2 string drops leaves the list; when V3
-- brings it back it is measured from V1, not from a version it never took.
at, bs = ns.EUIRecordRows("update", { rowAt = { Gone = { version = "V1", kitn = "k1" } }, bases = { V1 = "s1" }, stamp = "V2" }, {
    rows = rowsR, ticked = { A = true }, changed = { A = true }, prior = { version = "V2", base = "s2" }, kitn = "k2",
})
eq(at and at.Gone and at.Gone.version, "V1", "record: a waiting row this version does not list goes on waiting")
eq(bs and bs.V1, "s1", "record: with its string")
eq(bs and bs.V2, nil, "record: and no string no record names")
at, bs = ns.EUIRecordRows("update", { rowAt = at, bases = bs, stamp = "V3" }, {
    rows = { { id = "Gone" } }, ticked = {}, changed = { Gone = true }, prior = { version = "V3", base = "s3" }, kitn = "k3",
})
eq(at and at.Gone and at.Gone.version, "V1", "record: listed again, it still waits from V1")
eq(bs and bs.V1, "s1", "record: with the V1 string")

-- General skipped at V1; the V2 string omits fonts, which the importer
-- inherits, so V2 counts no General change. General still stands at V1 until
-- it is ticked.
local genR = { { id = "general" }, { id = "A" } }
at, bs = ns.EUIRecordRows("update", { rowAt = { general = { version = "V1", kitn = "k1" } }, bases = { V1 = "s1" }, stamp = "V2" }, {
    rows = genR, ticked = { A = true }, changed = { A = true }, prior = { version = "V2", base = "s2" }, kitn = "k2",
})
eq(at and at.general and at.general.version, "V1", "record: a waiting row with no counted change goes on waiting")
eq(bs and bs.V1, "s1", "record: its string stays")
at, bs = ns.EUIRecordRows("update", { rowAt = at, bases = bs, stamp = "V3" }, {
    rows = genR, ticked = { general = true }, changed = { general = true }, prior = { version = "V3", base = "s3" }, kitn = "k3",
})
eq(at, nil, "record: ticked in a later update, the waiting row is cleared")
eq(bs, nil, "record: and its string pruned")

-- Nameplates skipped at V1, then off (Plater chosen) through the V2 update:
-- it still has the V1 settings, so it goes on waiting from V1.
local offR = { { id = "A" }, { id = "NP", off = "Plater chosen" } }
at, bs = ns.EUIRecordRows("update", { rowAt = { NP = { version = "V1", kitn = "k1" } }, bases = { V1 = "s1" }, stamp = "V2" }, {
    rows = offR, ticked = { A = true }, changed = { A = true }, prior = { version = "V2", base = "s2" }, kitn = "k2",
})
eq(at and at.NP and at.NP.version, "V1", "record: an off row keeps its waiting record")
eq(bs and bs.V1, "s1", "record: and its string")
at, bs = ns.EUIRecordRows("update", { stamp = "V2" }, {
    rows = offR, ticked = { A = true }, changed = { A = true }, prior = { version = "V2", base = "s2" }, kitn = "k2",
})
eq(at and at.NP and at.NP.version, "V2", "record: an off row with no record waits from the stamp it stood at")
eq(at and at.NP and at.NP.kitn, nil, "record: but carries no skip, so its tooltip names none")
eq(bs and bs.V2, "s2", "record: with that version's string")

at, bs = ns.EUIRecordRows("take", { rowAt = { B = { version = "V1" }, C = { version = "V2" } }, bases = { V1 = "s1", V2 = "s2" }, stamp = "V3" },
    { ticked = { B = true } })
eq(at.B, nil, "record: a taken row is cleared")
eq(at.C.version, "V2", "record: a row not taken keeps its entry")
eq(bs.V1, nil, "record: a version no row names is pruned")
eq(bs.V2, "s2", "record: a named version stays")

at, bs = ns.EUIRecordRows("reset", { rowAt = { B = { version = "V1" } }, bases = { V1 = "s1" }, stamp = "V3" },
    { row = "B", shipped = { version = "V3", base = "s3" }, kitn = "k" })
eq(at, nil, "record: a reset at the stamp's version clears the row")
eq(bs, nil, "record: and prunes its string")
at, bs = ns.EUIRecordRows("reset", { stamp = "V2" }, { row = "B", shipped = { version = "V3", base = "s3" }, kitn = "k" })
eq(at.B.version, "V3", "record: a reset ahead of the stamp records the shipped version")
eq(at.B.kitn, nil, "record: and no skip")
eq(bs.V3, "s3", "record: with the shipped string")
at, bs = ns.EUIRecordRows("reset", { rowAt = { B = { version = "V1" } }, bases = { V1 = "s1" }, stamp = "V2" },
    { row = "B", shipped = { base = "s3" }, kitn = "k" })
eq(at and at.B and at.B.version, "V1", "record: with no shipped version nothing is written under a missing key")
eq(bs and bs.V1, "s1", "record: and the strings stay")
at, bs = ns.EUIRecordRows("reset", { rowAt = { B = { version = "V1" } }, bases = { V1 = "s1" } },
    { row = "B", shipped = { base = "s3" }, kitn = "k" })
eq(at and at.B and at.B.version, "V1", "record: with neither a shipped version nor a stamp the record stands")
eq(bs and bs.V1, "s1", "record: with its string")

-- Saved data can hold anything: an entry that is not a table with a version
-- is skipped rather than raising after the import has landed.
at, bs = ns.EUIRecordRows("update", { rowAt = { Bad = "x", Worse = { kitn = "k" }, B = { version = "V1" } }, bases = { V1 = "s1" }, stamp = "V2" }, {
    rows = rowsR, ticked = {}, changed = {}, prior = { version = "V2", base = "s2" }, kitn = "k2",
})
check(at and at.Bad == nil and at.Worse == nil, "record: malformed entries are dropped")
eq(at and at.B and at.B.version, "V1", "record: a sound one stays")
eq(bs and bs.V1, "s1", "record: with its string")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
