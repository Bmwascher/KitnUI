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
eq(rows[7].sub, "fonts, colors, scale", "rows: the General row's sub")
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

-- Saved data can hold anything: an entry that is not a table with a string
-- version is read as no entry, so its row is measured from the stamp's base.
local badO, badMissing = ns.EUIComposeBase(simple, { [UF] = "x", [AB] = { kitn = "k" }, general = true },
    { S = stampBase }, "S", k2f)
eq(badO.addons[UF] and badO.addons[UF].v, "stamp", "compose: a malformed entry is read as absent")
eq(badO.addons[AB] and badO.addons[AB].v, "stamp", "compose: as is an entry with no version")
eq(badO.fonts and badO.fonts.f, "stamp", "compose: and a bare true")
check(not (badMissing[UF] or badMissing[AB] or badMissing.general), "compose: none of them is reported missing")
local readOk, readRec = pcall(ns.EUIRowRecord, "corrupt", UF)
check(readOk and readRec == nil, "record: a store that is not a table has no entries", readRec)
local soundOk, soundRec = pcall(ns.EUIRowRecord, { [UF] = { version = "V1" } }, UF)
check(soundOk and type(soundRec) == "table" and soundRec.version == "V1", "record: a sound entry is read", soundRec)

-- The tooltip formats the skip label, so one that is not a string is read as
-- absent, and the saved entry is left as it is until the next write.
local badKitn = { [UF] = { version = "V1", kitn = true } }
local kitnRec = ns.EUIRowRecord(badKitn, UF)
eq(kitnRec and kitnRec.version, "V1", "record: an entry with a malformed skip label is still read")
eq(kitnRec and kitnRec.kitn, nil, "record: without the label")
eq(badKitn[UF].kitn, true, "record: and the saved entry is not written")
eq((ns.EUIRowRecord({ [UF] = { version = "V1", kitn = "2.1.0" } }, UF) or {}).kitn, "2.1.0", "record: a string skip label is kept")
local keptAt = ns.EUIRecordRows("update", { rowAt = { B = { version = "V1", kitn = 5 } }, bases = { V1 = "s1" }, stamp = "V2" }, {
    rows = { { id = "B" } }, ticked = {}, changed = { B = true }, prior = { version = "V2", base = "s2" }, kitn = "k2",
})
eq(keptAt and keptAt.B and keptAt.B.version, "V1", "record: a waiting entry with a malformed label goes on waiting")
eq(keptAt and keptAt.B and keptAt.B.kitn, nil, "record: and the next write drops the label")

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

-- A Top Bar take is the Top Bar's own settings: the player's switches stay.
do
    local tbTaken = { addons = { [TOP_BAR] = {
        bite = true, darkCastBar = true, lulu = true, tbOpacity = 60, tbPos = { x = 1 },
    } } }
    local tbKitn = { addons = { [TOP_BAR] = { bite = false, darkCastBar = false, accentPink = true, tbOpacity = 85 } } }
    ns.EUITakeSlice(tbTaken, tbKitn, { id = TOP_BAR }, k2f)
    local tbFolder = tbTaken.addons[TOP_BAR]
    eq(tbFolder.tbOpacity, 85, "take: the Top Bar takes KitnUI's Top Bar settings")
    eq(tbFolder.tbPos, nil, "take: and none of the player's KitnUI's string lacks")
    check(tbFolder.bite == true and tbFolder.darkCastBar == true and tbFolder.lulu == true,
        "take: the player's switch states stay as they are")
    eq(tbFolder.accentPink, nil, "take: and KitnUI's are not added")
    local tbBare = {}
    ns.EUITakeSlice(tbBare, { addons = { [TOP_BAR] = { bite = true, tbOpacity = 85 } } }, { id = TOP_BAR }, k2f)
    local tbBareFolder = tbBare.addons and tbBare.addons[TOP_BAR]
    check(tbBareFolder and tbBareFolder.bite == nil and tbBareFolder.tbOpacity == 85,
        "take: with no folder of the player's, KitnUI's switch states still stay out")
end

-- Size-match extras go where the links a part owns go, keyed by the same child.
eq(ns.EUIRowOf("unlockLayout.heightMatchExtra.UF_Player", k2f), UF, "owner: a size-match extra by its child")
local xMerged = {
    addons = { [UF] = { v = "merged" }, [AB] = { v = "merged" } },
    unlockLayout = {
        widthMatch = { UF_Player = "UF_Target", AB_Main = "AB_Kitn" },
        widthMatchExtra = { AB_Main = 4 },
    },
}
local xReport = { conflicts = { "unlockLayout.widthMatchExtra.UF_Player", "unlockLayout.widthMatchExtra.AB_Main" } }
local xP = {
    addons = { [UF] = { v = "player" }, [AB] = { v = "player" } },
    unlockLayout = {
        widthMatch = { UF_Player = "UF_Target", AB_Main = "AB_Mine" },
        widthMatchExtra = { UF_Player = 6, AB_Main = 2 },
    },
}
ns.EUIKeepSlices(xMerged, xReport, xP, simple, { [AB] = true }, k2f)
eq(xMerged.unlockLayout.widthMatchExtra.UF_Player, 6, "keep: an unticked part gets the player's extra back beside the player's link")
eq(xMerged.unlockLayout.widthMatchExtra.AB_Main, 4, "keep: a ticked part keeps the merge's extra")
eq(#xReport.conflicts, 1, "keep: an unticked part's extra conflict leaves the report")
eq(xReport.conflicts[1], "unlockLayout.widthMatchExtra.AB_Main", "keep: and a ticked part's stays")
eq(ns.EUIByRow(xReport.conflicts, { [AB] = true }, k2f)[AB], 1, "by row: an extra's conflict counts under the part that owns the child")

local xTaken = { unlockLayout = { widthMatch = { UF_Player = "UF_Target" }, widthMatchExtra = { UF_Player = 6 } } }
ns.EUITakeSlice(xTaken, { unlockLayout = { widthMatch = { UF_Player = "UF_Kitn" } } }, { id = UF }, k2f)
eq(xTaken.unlockLayout.widthMatch.UF_Player, "UF_Kitn", "take: the part takes KitnUI's link")
eq(xTaken.unlockLayout.widthMatchExtra.UF_Player, nil, "take: and KitnUI's extra, here none, not the player's")

local xStamp = { unlockLayout = { widthMatch = { UF_Player = "UF_Target" }, widthMatchExtra = { UF_Player = 3 } } }
local xOlder = { unlockLayout = { widthMatch = { UF_Player = "UF_Target" }, widthMatchExtra = { UF_Player = 5 } } }
local xO = ns.EUIComposeBase(simple, { [UF] = { version = "V1" } }, { S = xStamp, V1 = xOlder }, "S", k2f)
eq(xO and xO.unlockLayout.widthMatchExtra and xO.unlockLayout.widthMatchExtra.UF_Player, 5,
    "compose: a part at an older version takes that version's extras with its links")

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

---------------------------------------------------------------------------------
-- The counting walk
---------------------------------------------------------------------------------

local wRows = {
    { id = UF, label = "Unit Frames" },
    { id = RB, label = "Resource Bars" },
    { id = CDM, label = "Cooldown Manager" },
    { id = "general", label = "General" },
    { id = "overrides", label = "Spec Overrides" },
}
local wK2F = { UF_Player = UF }

local function baseSide()
    return {
        addons = {
            [UF] = { player = { healthHeight = 20, width = 200.5, castbarFillColor = { r = 1, g = 0, b = 0 } } },
            [RB] = {
                castBar = { fillR = 1, fillG = 1, fillB = 1, height = 10 },
                health = { customColored = false, fillR = 0, fillG = 0, fillB = 0 },
            },
            [CDM] = { cdmBars = { bars = { { name = "Essential", iconSize = 30 } } } },
        },
        fonts = { global = "A" },
        uiScale = 0.8,
        unlockLayout = { anchors = { UF_Player = { target = "UIParent", x = 1 } } },
    }
end

local function changedSide()
    local s = baseSide()
    s.addons[UF].player.healthHeight = 22
    s.addons[UF].player.width = 200.50001
    s.addons[UF].player.castbarFillColor = { r = 0.5, g = 0, b = 0 }
    s.addons[RB].castBar.fillR = 0.2
    s.addons[RB].castBar.fillG = 0.2
    s.addons[CDM].cdmBars.bars[1].iconSize = 34
    s.fonts.global = "B"
    s.uiScale = 0.9
    s.unlockLayout.anchors.UF_Player.x = 5
    s.specOverrides = { { values = { default = { ["X\31y"] = 1 } } } }
    return s
end

local function walkAll(A, B, opts)
    local walker = ns.EUIRowDiff(A, B, wRows, wK2F, opts)
    walker:Step(math.huge)
    return walker.result
end

local function countOf(result, id) return result[id] and result[id].count or 0 end

local whole = walkAll(baseSide(), changedSide())
eq(countOf(whole, UF), 3, "walk: a leaf, a colour table and a position; a float inside tolerance is no change")
eq(countOf(whole, RB), 1, "walk: sibling channels are one colour")
eq(countOf(whole, CDM), 1, "walk: a list entry's setting")
eq(countOf(whole, "general"), 2, "walk: a font and the scale")
eq(countOf(whole, "overrides"), 1, "walk: a different override set counts once")

local stepped = ns.EUIRowDiff(baseSide(), changedSide(), wRows, wK2F)
local steps = 0
while not stepped:Step(1) do steps = steps + 1 end
check(steps > 5, "walk: one node per step takes many steps", steps)
for _, row in ipairs(wRows) do
    eq(countOf(stepped.result, row.id), countOf(whole, row.id), "walk: stepping one node at a time gives the same count for " .. row.id)
end

eq(whole[UF].groups[1].name, "Player", "names: the unit's group")
eq(whole[UF].groups[2].name, "Positions", "names: positions are their own group, groups sorted")
eq(whole[CDM].groups[1].name, "Essential", "names: a list entry is named by its name field")
eq(whole[CDM].groups[1].items[1], "icon size", "names: the setting is its key, split and lower-cased")
eq(whole[RB].groups[1].items[1], "fill", "names: sibling channels are named by their stem")

local outOfRange = changedSide()
outOfRange.uiScale = 2
eq(countOf(walkAll(baseSide(), outOfRange), "general"), 1, "walk: a scale outside the range is not counted")

local maskedBase, maskedSide = baseSide(), baseSide()
maskedBase.specUnlockOverrides = { active = 1 }
maskedSide.specUnlockOverrides = { active = 2 }
eq(countOf(walkAll(maskedBase, maskedSide), "overrides"), 0, "walk: overrides compare through the masks")

local addedByKitn = baseSide()
addedByKitn.addons[UF].player.newKey = 1
eq(countOf(walkAll(baseSide(), addedByKitn), UF), 1, "walk: a setting KitnUI adds is a change")
-- The merge deletes a setting KitnUI removed inside a folder, so that is a
-- change; a whole folder or root table its string lacks is inherited.
local droppedByKitn = baseSide()
droppedByKitn.addons[UF].player.healthHeight = nil
eq(countOf(walkAll(baseSide(), droppedByKitn), UF), 1, "walk: a setting KitnUI removed inside a folder is a change, so a removal alone makes a row tickable")
local folderGone = baseSide()
folderGone.addons[CDM] = nil
folderGone.fonts = nil
local inherited = walkAll(baseSide(), folderGone)
eq(countOf(inherited, CDM), 0, "walk: a folder KitnUI's string lacks is inherited, no change")
eq(countOf(inherited, "general"), 0, "walk: and so is a root table it lacks")

local noSlice = walkAll(nil, changedSide(), { missing = { [UF] = true } })
check(noSlice[UF].noBase and noSlice[UF].count == 0, "walk: a row with no base is marked, not walked")

---------------------------------------------------------------------------------
-- The player's walk
---------------------------------------------------------------------------------

local playerBase = baseSide()
playerBase.addons[UF].player.onlyBase = 3
local playerSide = baseSide()
playerSide.addons[UF].player.extra = 5
playerSide.addons[UF].player.extra2 = 7
playerSide.addons[RB].castBar.newLeaf = 1
local mine = walkAll(playerBase, playerSide, {
    player = true,
    defaults = { [UF] = { player = { extra = 5, extra2 = 5, onlyBase = 3 } } },
})
eq(countOf(mine, UF), 1, "player: an untouched default is no change, a changed one is, a missing side reads as the default")
eq(countOf(mine, RB), 0, "player: without defaults a one-sided setting is not counted")

local healthSide = baseSide()
healthSide.addons[RB].health.fillR = 0.5
eq(countOf(walkAll(baseSide(), healthSide, { player = true }), RB), 0, "player: the health fill is not counted while the class colour is on")
healthSide.addons[RB].health.customColored = true
eq(countOf(walkAll(baseSide(), healthSide, { player = true }), RB), 2, "player: with a custom health colour the switch and the fill count")

local heldBase = baseSide()
heldBase.specOverrides = { { values = { default = { ["X\31y"] = true } } } }
heldBase.unlockOverrideAnchors = { ERB_CastBar = { x = 1 } }
local heldSide = changedSide()
heldSide.specOverrides = { { values = { default = { ["X\31y"] = false } } } }
local heldMine = walkAll(heldBase, heldSide, {
    player = true,
    held = {
        ["addons." .. UF .. ".player.healthHeight"] = true,
        ["unlockLayout.anchors.UF_Player"] = true,
        [ns.EUI_HELD_FKEY .. "X\31y"] = true,
        ["unlockOverrideAnchors.ERB_CastBar"] = true,
    },
})
eq(countOf(heldMine, UF), 1, "held: a held setting and a held layout entry are not the player's")
eq(countOf(heldMine, "overrides"), 0, "held: a held override value and a held override position are not the player's")

local noBaseMine = walkAll(changedSide(), baseSide(), { player = true, noBase = true })
check(noBaseMine[UF].noBase and noBaseMine[UF].count > 0, "player: with no base the entry is marked for differs")
local fellBack = walkAll(nil, changedSide(), { player = true, missing = { [UF] = true }, fallback = changedSide() })
check(fellBack[UF].noBase and fellBack[UF].count == 0, "player: a row with no base is compared with KitnUI's string")

-- A General reset takes KitnUI's root tables whole, so a colour only the
-- player's copy holds is one the reset replaces, and it counts.
local colourSide = baseSide()
colourSide.customColors = { mine = { r = 1, g = 0, b = 0 } }
local colourBase = baseSide()
colourBase.customColors = {}
eq(countOf(walkAll(colourBase, colourSide, { player = true }), "general"), 1, "player: a General setting only the player holds counts")
eq(countOf(walkAll(colourSide, colourBase, { player = true }), "general"), 1, "player: and one only the base holds")

-- The Top Bar row counts the Top Bar's own settings, never the switch states
-- and switch settings that share its folder.
do
    local tbRows = { { id = TOP_BAR, label = "Top Bar" } }
    local function tbSide(on, opacity)
        local folder = { bite = on, darkCastBar = on, npArrowW = on and 30 or 24, tbOpacity = opacity }
        return { addons = { [TOP_BAR] = folder } }
    end
    local function tbCount(A, B, opts)
        local walker = ns.EUIRowDiff(A, B, tbRows, {}, opts)
        walker:Step(math.huge)
        return walker.result[TOP_BAR] and walker.result[TOP_BAR].count or 0
    end
    eq(tbCount(tbSide(false, 85), tbSide(true, 85), { player = true }), 0,
        "top bar: switches the player turned on are not Top Bar changes")
    eq(tbCount(tbSide(false, 85), tbSide(true, 60), { player = true }), 1, "top bar: a Top Bar setting the player changed is")
    eq(tbCount(tbSide(false, 85), tbSide(true, 85), { player = true, against = tbSide(false, 85) }), 0,
        "top bar: a Reset's count leaves them out too, as the Reset keeps them")
    local tbDefaults = { [TOP_BAR] = { bite = false, darkCastBar = false, npArrowW = 24, tbOpacity = 85 } }
    local tbAbsent = { addons = { [TOP_BAR] = { tbOpacity = 85 } } }
    eq(tbCount(tbAbsent, tbSide(true, 85), { player = true, defaults = tbDefaults }), 0,
        "top bar: a switch the base lacks, on against its default, is not counted either")
    eq(tbCount(tbSide(false, 85), tbSide(true, 60)), 4, "top bar: the update walk still counts every key that differs")
end

---------------------------------------------------------------------------------
-- Work per step
---------------------------------------------------------------------------------

-- Work is measured, not taken from the walker's own count: every key any
-- `pairs` loop reads, in the walk and in the merge helpers it borrows alike,
-- is counted from the walker's construction to its first yield and from one
-- yield to the next after that. Between two ticks the walk reads at
-- most a node's keys for the colour test (five a side) and one key more, so
-- a step of `budget` ticks reads at most (budget + 1) * READS_PER_TICK keys;
-- a loop that forgot to tick reads its whole table in one step and fails.
local READS_PER_TICK = 12
local realPairs = pairs
local reads = 0
local function countingPairs(t)
    return function(tt, k)
        reads = reads + 1
        return next(tt, k)
    end, t, nil
end

-- Counting starts before the walker is built, so whatever its construction
-- reads is charged to the first step.
local function maxReads(A, B, rowList, budget, opts)
    local most, stepCount = 0, 0
    _G.pairs = countingPairs
    reads = 0
    local walker = ns.EUIRowDiff(A, B, rowList, wK2F, opts)
    repeat
        local done = walker:Step(budget)
        stepCount = stepCount + 1
        if reads > most then most = reads end
        reads = 0
    until done
    _G.pairs = realPairs
    return most, stepCount, walker
end

local BOUND = (10 + 1) * READS_PER_TICK

-- Keys only one side holds, and keys both hold: the second side's scan reads
-- the shared keys too.
local wideBase, wideSide = baseSide(), baseSide()
wideBase.addons[UF].player.shared, wideSide.addons[UF].player.shared = {}, {}
wideSide.addons[UF].player.wide = {}
for i = 1, 500 do
    wideSide.addons[UF].player.wide["k" .. i] = i
    wideBase.addons[UF].player.shared["k" .. i] = i
    wideSide.addons[UF].player.shared["k" .. i] = i
end
local wideMost, wideSteps = maxReads(wideBase, wideSide, { wRows[1] }, 10)
check(wideMost <= BOUND, "work: a wide table is read a budget at a time", wideMost)
check(wideSteps >= 100, "work: over many steps", wideSteps)

-- Equal stores, so the comparison reads every key to say so: a value map, and
-- an unlock layer of plain values compared over the union of its keys.
local bigBase, bigSide = baseSide(), baseSide()
bigBase.specOverrides, bigSide.specOverrides = { { values = { default = {} } } }, { { values = { default = {} } } }
bigBase.specUnlockOverrides = { baselineLayout = { elems = {} }, layouts = {} }
bigSide.specUnlockOverrides = { baselineLayout = { elems = {} }, layouts = {} }
for i = 1, 300 do
    bigBase.specOverrides[1].values.default["F\31k" .. i] = i
    bigSide.specOverrides[1].values.default["F\31k" .. i] = i
    bigBase.specUnlockOverrides.baselineLayout["v" .. i] = i
    bigSide.specUnlockOverrides.baselineLayout["v" .. i] = i
end
local bigMost, bigSteps = maxReads(bigBase, bigSide, { wRows[5] }, 10)
check(bigMost <= BOUND, "work: the override comparison is read a budget at a time", bigMost)
check(bigSteps >= 60, "work: over many steps", bigSteps)
bigSide.specOverrides[1].values.default["F\31k300"] = 0
local bigWalker = ns.EUIRowDiff(bigBase, bigSide, { wRows[5] }, wK2F)
repeat until bigWalker:Step(10)
eq(countOf(bigWalker.result, "overrides"), 1, "work: and a stepped comparison still finds the difference")

-- Many recorded settings: each one costs the same, because only what the
-- tooltip shows is kept, in order, and nothing is sorted at the end.
local manyBase, manySide = baseSide(), baseSide()
manyBase.addons[UF].player.many, manySide.addons[UF].player.many = {}, {}
for i = 1, 500 do
    manyBase.addons[UF].player.many[string.format("s%03d", i)] = 0
    manySide.addons[UF].player.many[string.format("s%03d", i)] = 1
end
local manyMost, _, manyWalker = maxReads(manyBase, manySide, { wRows[1] }, 10)
check(manyMost <= BOUND, "work: recording many settings is read a budget at a time", manyMost)
local manyEntry = manyWalker.result[UF]
eq(manyEntry.count, 500, "record: every setting is counted")
local manyGroup
for _, g in ipairs(manyEntry.groups) do
    if g.name == "Player" then manyGroup = g end
end
eq(manyGroup and manyGroup.n, 500, "record: and every one in its group's total")
eq(manyGroup and #manyGroup.items, 8, "record: but only the eight the tooltip shows are kept")
eq(manyGroup and manyGroup.items[1], "s 001 (many)", "record: the first by name, with the key it sits under")
eq(manyGroup and manyGroup.items[8], "s 008 (many)", "record: in order")

-- The setup is work too: General's seeding scans every root key of both sides
-- (an unknown root key is General's), and the held set is parsed path by path.
-- A walker that did either while it was built would read them all at once.
local rootBase, rootSide, rootHeld = baseSide(), baseSide(), {}
for i = 1, 500 do
    rootBase["root" .. i] = i
    rootSide["root" .. i] = i
    rootHeld["addons." .. UF .. ".player.h" .. i] = true
end
local rootMost, rootSteps, rootWalker = maxReads(rootBase, rootSide, { wRows[4] }, 10, { player = true, held = rootHeld })
check(rootMost <= BOUND, "work: seeding a wide root and parsing a wide held set are read a budget at a time", rootMost)
check(rootSteps >= 100, "work: over many steps", rootSteps)
eq(countOf(rootWalker.result, "general"), 0, "work: and equal root keys are no change")

-- A wide folder behind the Top Bar row: its filter reads every key of both
-- sides, of KitnUI's side for a Reset and of the defaults, and charges each one.
do
    local tbWideRows = { { id = TOP_BAR, label = "Top Bar" } }
    local tbWideBase, tbWideSide = { addons = { [TOP_BAR] = {} } }, { addons = { [TOP_BAR] = {} } }
    local tbWideDefaults = {}
    for i = 1, 300 do
        tbWideBase.addons[TOP_BAR]["np" .. i] = i
        tbWideSide.addons[TOP_BAR]["np" .. i] = i + 1
        tbWideDefaults["np" .. i] = i
    end
    for _, t in ipairs({ tbWideBase.addons[TOP_BAR], tbWideSide.addons[TOP_BAR], tbWideDefaults }) do
        t.tbOpacity, t.tbSpacing = 85, 14
    end
    tbWideSide.addons[TOP_BAR].tbSpacing = 20
    local tbWideMost, tbWideSteps, tbWideWalker = maxReads(tbWideBase, tbWideSide, tbWideRows, 10,
        { player = true, defaults = { [TOP_BAR] = tbWideDefaults }, against = tbWideBase })
    check(tbWideMost <= BOUND, "work: the Top Bar filter over a wide folder is read a budget at a time", tbWideMost)
    check(tbWideSteps >= 90, "work: over many steps", tbWideSteps)
    eq(countOf(tbWideWalker.result, TOP_BAR), 1, "work: and only the Top Bar setting that differs counts")
end

-- A reset counts only the player's changes it alters.
local resetBase, resetPlayer, resetN = baseSide(), baseSide(), baseSide()
resetPlayer.addons[UF].player.healthHeight = 22
resetN.addons[UF].player.healthHeight = 22
resetPlayer.addons[UF].player.width = 300
resetN.addons[UF].player.width = 250
eq(countOf(walkAll(resetBase, resetPlayer, { player = true }), UF), 2, "reset count: both are the player's changes")
eq(countOf(walkAll(resetBase, resetPlayer, { player = true, against = resetN }), UF), 1,
    "reset count: a change already equal to KitnUI's is not replaced")
local resetNoFonts = baseSide()
resetNoFonts.fonts = nil
local fontsPlayer = baseSide()
fontsPlayer.fonts.global = "Mine"
eq(countOf(walkAll(resetBase, fontsPlayer, { player = true, against = resetNoFonts }), "general"), 0,
    "reset count: a root table KitnUI's string lacks stays the player's")

-- Size-match extras: read beside their own side's link, each one setting of
-- the part that owns the child.
local function matched(target, extra)
    local s = baseSide()
    s.unlockLayout.widthMatch = { UF_Player = target }
    s.unlockLayout.widthMatchExtra = { UF_Player = extra }
    return s
end
eq(countOf(walkAll(matched("UF_Target"), matched("UF_Target", 6), { player = true }), UF), 1,
    "player: an extra the player set on a link they kept is one of their changes")
eq(countOf(walkAll(matched("UF_Target"), matched("UF_Other", 6), { player = true }), UF), 2,
    "player: a changed link with an extra is two changes, the link and the extra")
local unlinked = matched("UF_Target", 6)
unlinked.unlockLayout.widthMatch = {}
eq(countOf(walkAll(matched("UF_Target"), unlinked, { player = true }), UF), 1,
    "player: an extra without its own side's link is no setting; the removed link is the one change")
eq(countOf(walkAll(matched("UF_Target"), matched("UF_Target", 4)), UF), 0,
    "walk: an extra KitnUI changes on a link it left alone is no change, since the player keeps that link")
eq(countOf(walkAll(matched("UF_Target", 3), matched("UF_Kitn")), UF), 2,
    "walk: a link KitnUI re-points takes KitnUI's extra with it, one change each")
eq(countOf(walkAll(matched("UF_Target"), matched("UF_Target", 6), { player = true, against = matched("UF_Target") }), UF), 1,
    "reset count: an extra KitnUI's part does not carry is replaced")
eq(countOf(walkAll(matched("UF_Target"), matched("UF_Target", 6), { player = true, against = matched("UF_Target", 6) }), UF), 0,
    "reset count: an extra equal to KitnUI's is not")
local xWalk = walkAll(matched("UF_Target"), matched("UF_Target", 6), { player = true })
eq(xWalk[UF] and xWalk[UF].groups[1] and xWalk[UF].groups[1].name, "Positions", "names: an extra is under Positions")

-- Many linked children with extras: the extras are read inside the ticked
-- child loop, a budget at a time.
local xWideBase, xWideSide = baseSide(), baseSide()
xWideBase.unlockLayout.widthMatch, xWideSide.unlockLayout.widthMatch = {}, {}
xWideSide.unlockLayout.widthMatchExtra = {}
for i = 1, 500 do
    wK2F["UF_W" .. i] = UF
    xWideBase.unlockLayout.widthMatch["UF_W" .. i] = "UF_Player"
    xWideSide.unlockLayout.widthMatch["UF_W" .. i] = "UF_Player"
    xWideSide.unlockLayout.widthMatchExtra["UF_W" .. i] = i
end
local xWideMost, _, xWideWalker = maxReads(xWideBase, xWideSide, { wRows[1] }, 10, { player = true })
check(xWideMost <= BOUND, "work: extras are read a budget at a time", xWideMost)
eq(countOf(xWideWalker.result, UF), 500, "work: and each differing extra counts once")
for i = 1, 500 do wK2F["UF_W" .. i] = nil end

-- A malformed extra that is a table is compared a budget at a time, against
-- the base and against KitnUI's side of a reset's count.
local function wideExtra()
    local t = {}
    for i = 1, 500 do t["k" .. i] = i end
    return t
end
local xTblMost, _, xTblWalker = maxReads(matched("UF_Target", wideExtra()), matched("UF_Target", wideExtra()),
    { wRows[1] }, 10, { player = true })
check(xTblMost <= BOUND, "work: a table-valued extra is compared a budget at a time", xTblMost)
eq(countOf(xTblWalker.result, UF), 0, "work: and an equal one is no change")
local xTblAgainst = maxReads(matched("UF_Target", 1), matched("UF_Target", wideExtra()), { wRows[1] }, 10,
    { player = true, against = matched("UF_Target", wideExtra()) })
check(xTblAgainst <= BOUND, "work: and so is one on KitnUI's side of a reset's count", xTblAgainst)

---------------------------------------------------------------------------------
-- Names and the tooltip
---------------------------------------------------------------------------------

local group, item = ns.EUISettingLabel("addons.EllesmereUIRaidFrames.frameWidth", { id = "EllesmereUIRaidFrames" })
eq(group, "General", "label: a flat module's setting is in General")
eq(item, "frame width", "label: camelCase split")
group, item = ns.EUISettingLabel("addons." .. RB .. ".ERB_Thing.height", { id = RB }, { unlock = { ERB_Thing = "Resource Thing" } })
eq(group, "Resource Thing", "label: the unlock label is the fallback group")
eq(item, "height", "label: the item")
group, item = ns.EUISettingLabel("addons." .. UF .. ".someGroup.leaf", { id = UF })
eq(group, "Some group", "label: the tidied key is the last fallback")
eq(item, "leaf", "label: a one-word item")
group, item = ns.EUISettingLabel("addons." .. AB .. ".bars.MainBar.buttonPadding", { id = AB })
eq(group, "Action Bar 1", "label: the group table, under a wrapper")
eq(item, "button padding", "label: the item under a wrapper")
group, item = ns.EUISettingLabel("unlockLayout.anchors.UF_Player", { id = UF }, { unlock = { UF_Player = "Player Frame" } })
eq(group, "Positions", "label: a layout entry is a position")
eq(item, "Player Frame", "label: named by its unlock label")
group, item = ns.EUISettingLabel("uiScale", { id = "general" })
eq(group, "General", "label: the scale's group")
eq(item, "ui scale", "label: the scale")

group = ns.EUISettingLabel("customColors.class", { id = "general" })
eq(group, "Colors", "label: the color group in American spelling")
group = ns.EUISettingLabel("euiAccent.r", { id = "general" })
eq(group, "Accent Color", "label: the accent group in American spelling")

local named = {
    spec = function(id) return id == 102 and "Balance Druid" or nil end,
    spell = function(id) return id == 191034 and "Starfall" or nil end,
}
group, item = ns.EUISettingLabel("cdmSpells.102.barSpells.buffs.assignedSpells.[2]", { id = CDM }, named, 191034)
eq(group, "Balance Druid", "label: a Cooldown Manager spec is named")
eq(item, "Starfall (Buffs)", "label: a list entry is its spell, with its bar")
_, item = ns.EUISettingLabel("cdmSpells.102.barSpells.cooldowns.assignedSpells.[1]", { id = CDM }, named, -(2000000000 + 191034))
eq(item, "Starfall (Cooldowns)", "label: a hosted buff marker is its spell")
_, item = ns.EUISettingLabel("cdmSpells.102.barSpells.cooldowns.assignedSpells.[3]", { id = CDM }, named, -6)
eq(item, "#3 (Cooldowns)", "label: an item or slot entry keeps its position")
_, item = ns.EUISettingLabel("cdmSpells.102.barSpells.cooldowns.assignedSpells.[4]", { id = CDM }, named, -(3000000000 + 191034))
eq(item, "#4 (Cooldowns)", "label: a cooldown claim marker is no hosted spell")
_, item = ns.EUISettingLabel("cdmSpells.102.barSpells.buffs.customSpellIDs.[191034]", { id = CDM }, named, true)
eq(item, "Starfall (Buffs)", "label: a custom spell is named by its key")
group, item = ns.EUISettingLabel("cdmSpells.1473.barSpells.buffs.assignedSpells.[1]", { id = CDM }, nil, 1234)
eq(group, "Spec 1473", "label: without a name the spec reads its ID")
eq(item, "spell 1234 (Buffs)", "label: and the spell its ID")
_, item = ns.EUISettingLabel("cdmSpells.102.barSpells.buffs.barSettings.iconSize", { id = CDM }, named, 30)
eq(item, "icon size (Buffs)", "label: a bar setting carries its bar")
_, item = ns.EUISettingLabel("cdmSpells.102.barSpells.buffs.spellDurations.[191034]", { id = CDM }, named, 12)
eq(item, "#191034 (Buffs)", "label: a list that holds durations names no spell")

group, item = ns.EUISettingLabel("addons." .. TOP_BAR .. ".tbOff.clock", { id = TOP_BAR })
eq(group, "Top Bar", "label: a Top Bar setting is in the Top Bar group")
eq(item, "Hidden elements (clock)", "label: named, with what lies below it")
_, item = ns.EUISettingLabel("addons." .. TOP_BAR .. ".tbIconSize", { id = TOP_BAR })
eq(item, "Icon size", "label: a Top Bar key without a table name reads its tidied name")
_, item = ns.EUISettingLabel("addons." .. TOP_BAR .. ".tbAccent", { id = TOP_BAR })
eq(item, "Custom accent color", "label: the accent color stem is named")
group, item = ns.EUISettingLabel("addons." .. TOP_BAR .. ".bite", { id = TOP_BAR })
eq(group, "General", "label: a switch state in KitnUI's folder keeps its old group")
eq(item, "bite", "label: and its old item")

-- The keys between a group and its setting stay with the item as context.
_, item = ns.EUISettingLabel("addons." .. AB .. ".barPositions.MainBar.x", { id = AB })
eq(item, "x (Action Bar 1)", "label: a middle key a table names reads by that name")
_, item = ns.EUISettingLabel("addons." .. AB .. ".barPositions.MainBar.[2].x", { id = AB })
eq(item, "x (Action Bar 1 #2)", "label: an indexed middle key keeps its table name")
group, item = ns.EUISettingLabel("addons." .. RB .. ".secondary.thresholdSpecs.[2].buffColors.[1]", { id = RB })
eq(group, "Class Resource", "label: the group is unchanged")
eq(item, "buff colors #1 (threshold specs #2)", "label: an index folds into the key it numbers")
local firstEntry, secondEntry
_, firstEntry = ns.EUISettingLabel("addons." .. RB .. ".secondary.thresholdSpecs.[1].buffColorEnabled", { id = RB })
_, secondEntry = ns.EUISettingLabel("addons." .. RB .. ".secondary.thresholdSpecs.[2].buffColorEnabled", { id = RB })
eq(firstEntry, "buff color enabled (threshold specs #1)", "label: one entry's setting names its entry")
check(firstEntry ~= secondEntry, "label: two entries' settings read apart", secondEntry)
_, item = ns.EUISettingLabel("addons." .. RB .. ".secondary.thresholdSpecs.[2].buffColorEnabled", { id = RB },
    { names = { ["addons." .. RB .. ".secondary.thresholdSpecs.[2]"] = "Balance" } })
eq(item, "buff color enabled (Balance)", "label: a named entry reads by its name")
_, item = ns.EUISettingLabel("addons." .. UF .. ".someGroup.inner.deeper.leaf", { id = UF })
eq(item, "leaf (inner, deeper)", "label: several middle keys, outermost first")
_, item = ns.EUISettingLabel("addons." .. UF .. ".someList.[3]", { id = UF })
eq(item, "#3", "label: an index under the group itself stays a position")

-- The walk's lookups: one per ID, each charged one unit of the budget.
do
    local cdmRows = { { id = CDM, label = "Cooldown Manager" } }
    local function spells(list)
        return { cdmSpells = { ["102"] = { barSpells = { buffs = { assignedSpells = list } } } } }
    end
    local calls = { spec = 0, spell = 0 }
    local names = {
        spec = function(id)
            calls.spec = calls.spec + 1
            return id == 102 and "Balance Druid" or nil
        end,
        spell = function(id)
            calls.spell = calls.spell + 1
            return id == 191034 and "Starfall" or nil
        end,
    }
    local A, B = spells({ 1, 2 }), spells({ 191034, 191034 })
    local plainWalk = ns.EUIRowDiff(A, B, cdmRows, {}, {})
    plainWalk:Step(math.huge)
    local namedWalk = ns.EUIRowDiff(A, B, cdmRows, {}, { names = names })
    namedWalk:Step(math.huge)
    local e = namedWalk.result[CDM]
    eq(e and e.count, 2, "names: both changed entries count")
    eq(e and e.groups[1] and e.groups[1].name, "Balance Druid", "names: the walk names the spec")
    eq(e and e.groups[1] and e.groups[1].items[1], "Starfall (Buffs)", "names: and the spell")
    eq(calls.spec, 1, "names: one lookup per spec")
    eq(calls.spell, 1, "names: one lookup per spell")
    eq(namedWalk.units - plainWalk.units, 2, "names: each lookup is one unit of the walk's budget")
end

local many = { groups = {} }
for gi = 1, 8 do
    local items = {}
    for ii = 1, (gi == 1 and 10 or 1) do items[ii] = "item" .. ii end
    many.groups[gi] = { name = "G" .. gi, items = items }
end
local tipLines = ns.EUITooltipLines(many)
local headers = 0
for _, line in ipairs(tipLines) do
    if line.header then headers = headers + 1 end
end
eq(headers, 6, "tooltip: at most six groups")
eq(tipLines[1].text, "G1 (10)", "tooltip: a group listing fewer settings than it holds shows its total")
eq(tipLines[10].text, "G2", "tooltip: with no +N more line of its own")
eq(tipLines[#tipLines].text, "+2 more", "tooltip: the settings of the groups left out are counted")

---------------------------------------------------------------------------------
-- Split links, override capture, override element keys
---------------------------------------------------------------------------------

local splitRows = {
    { id = UF, label = "Unit Frames" },
    { id = RB, label = "Resource Bars" },
    { id = CDM, label = "Cooldown Manager" },
    { id = NP, label = "Nameplates", off = "Plater chosen" },
}
local splitN = { unlockLayout = {
    anchors = {
        UF_Player = { target = "ERB_Health" },
        ERB_CastBar = { target = "CDM_cooldowns" },
        NP_Thing = { target = "UF_Player" },
        ERB_Power = { target = "NP_Bar" },
    },
    widthMatch = { ERB_Health = "UF_Player" },
} }
local splitK2F = { UF_Player = UF, ERB_Health = RB, ERB_CastBar = RB, CDM_cooldowns = CDM, ERB_Power = RB, NP_Thing = NP, NP_Bar = NP }
local splits = ns.EUISplitLinks(splitN, splitRows, { [UF] = true }, splitK2F)
eq(#splits, 1, "split: a ticked child against an unticked target")
check(splits[1] and splits[1].child.id == UF and splits[1].target.id == RB, "split: named by both rows")
splits = ns.EUISplitLinks(splitN, splitRows, { [RB] = true }, splitK2F)
eq(#splits, 2, "split: one reset row against every part keeping the player's copy, an off target left out")
check(splits[1] and splits[1].target.id == UF and splits[2].target.id == CDM, "split: in row order")
eq(#ns.EUISplitLinks(splitN, splitRows, { [UF] = true, [RB] = true, [CDM] = true }, splitK2F), 0, "split: nothing when both ends are ticked")

local capP = {
    specOverrides = { { values = { default = { [UF .. "\31player\30height"] = 1 } } } },
    condOverrides = { { values = { [71] = { [RB .. "\31castBar\30x"] = 1 } } } },
    unlockOverrideAnchors = { ERB_CastBar = {} },
    specUnlockOverrides = { layouts = { [3] = { elems = { CDM_x = {} } } } },
}
local capK2F = { ERB_CastBar = AB, CDM_x = CDM }
check(ns.EUIOverridesCapture(capP, UF, capK2F), "capture: a spec override value")
check(ns.EUIOverridesCapture(capP, RB, capK2F), "capture: a conditional override value under a spec id")
check(ns.EUIOverridesCapture(capP, AB, capK2F), "capture: an override position")
check(ns.EUIOverridesCapture(capP, CDM, capK2F), "capture: an element of an override layer")
check(not ns.EUIOverridesCapture(capP, "EllesmereUIMinimap", capK2F), "capture: nothing for a part none of them names")

local elementSide = ns.EUIOverrideElementSide(capP)
check(elementSide.unlockLayout.anchors.ERB_CastBar and elementSide.unlockLayout.anchors.CDM_x,
    "element keys: override positions and layer elements reach the resolver")

-- A layer's links and extras name children it can hold no element entry for;
-- a link's target is not one of them.
local layerK2F = { UF_Player = UF, UF_Target = UF, ERB_Health = RB, CDM_y = CDM }
local extraOnly = { condUnlockOverrides = { layouts = { [71] = { elems = {}, widthMatchExtra = { UF_Player = 4 } } } } }
local linkOnly = { specUnlockOverrides = { layouts = { [3] = {
    elems = {},
    heightMatch = { ERB_Health = "UF_Target" },
    anchors = { CDM_y = { target = "ERB_Health" } },
} } } }
check(ns.EUIOverridesCapture(extraOnly, UF, layerK2F), "capture: a layer's size-match extra for a child with no element entry")
check(ns.EUIOverridesCapture(linkOnly, RB, layerK2F), "capture: a layer's size-match link for a child with no element entry")
check(ns.EUIOverridesCapture(linkOnly, CDM, layerK2F), "capture: a layer's anchor for a child with no element entry")
check(not ns.EUIOverridesCapture(linkOnly, UF, layerK2F), "capture: a link's target is no capture of the target's part")
local layerSide = ns.EUIOverrideElementSide({
    specUnlockOverrides = linkOnly.specUnlockOverrides,
    condUnlockOverrides = extraOnly.condUnlockOverrides,
})
local layerKeys = layerSide.unlockLayout.anchors
check(layerKeys.UF_Player and layerKeys.ERB_Health and layerKeys.CDM_y,
    "element keys: a layer's links and extras reach the resolver")
eq(layerKeys.UF_Target, nil, "element keys: but not a link's target")

---------------------------------------------------------------------------------
-- The settled record and the settled composite
---------------------------------------------------------------------------------

do
    -- An update or a take marks only what it installs, and drops a snapshot
    -- no pointer names any more.
    local snSettled, snAt, snPending, snDue = ns.EUISettleRecord("update", {
        settled = { [1] = { s = "one" }, [2] = { s = "two" } },
        at = { ["*"] = 1, [UF] = 2 },
    }, { parts = { [UF] = true } })
    check(snAt and snAt["*"] == 1 and snAt[UF] == false, "settle: an update marks the part it installs and keeps the others'")
    check(snPending and snPending[UF] and not snPending["*"], "settle: the installed part waits for the next session")
    check(snSettled and snSettled[1] and snSettled[2] == nil, "settle: a snapshot no part points at is dropped")
    eq(next(snDue), nil, "settle: nothing is due")

    snSettled, snAt = ns.EUISettleRecord("take", { settled = { [1] = { s = "one" } }, at = { ["*"] = 1 } },
        { parts = { general = true } })
    check(snAt and snAt.general == false and snAt["*"] == 1 and snSettled and snSettled[1],
        "settle: a take marks the part it takes")

    -- The snapshot for every part goes once every row is named.
    local twoRows = { { id = UF }, { id = "general" } }
    local starAt = select(2, ns.EUISettleRecord("take", { settled = { [1] = { s = "one" } }, at = { ["*"] = 1 } },
        { parts = { general = true }, rows = twoRows }))
    eq(starAt and starAt["*"], 1, "settle: while a row is not named, the one for every part stays")
    snSettled, snAt = ns.EUISettleRecord("update", {
        settled = { [1] = { s = "one" }, [2] = { s = "two" } }, at = { ["*"] = 1, [UF] = 2 },
    }, { parts = { general = true }, rows = twoRows })
    check(snAt and snAt["*"] == nil and snAt.general == false and snAt[UF] == 2,
        "settle: naming the last row drops the pointer for every part")
    check(snSettled and snSettled[1] == nil and snSettled[2], "settle: and its snapshot with it")

    -- A part due its snapshot and installed again this session leaves due.
    local _, rsAt, rsPending, rsDue = ns.EUISettleRecord("reset", {
        settled = { [1] = { s = "one" } }, at = { ["*"] = 1, [AB] = false },
        pending = { [AB] = true }, due = { [AB] = true },
    }, { parts = { [AB] = true } })
    check(rsAt and rsAt[AB] == false and rsPending and rsPending[AB], "settle: a reset marks its part")
    eq(rsDue[AB], nil, "settle: and a part installed again is no longer due")

    -- The capture after a full install: every part but one installed since.
    local snEntry = { s = "snap", held = {} }
    snSettled, snAt, snPending, snDue = ns.EUISettleRecord("capture", {
        at = { [AB] = false }, pending = { ["*"] = true, [AB] = true }, due = { ["*"] = true },
    }, { id = 1, entry = snEntry })
    check(snSettled and snSettled[1] == snEntry, "capture: records the snapshot under its id")
    check(snAt and snAt["*"] == 1 and snAt[AB] == false, "capture: for every part but one installed this session")
    check(snPending and snPending[AB] and not snPending["*"], "capture: which alone still waits")
    eq(next(snDue), nil, "capture: and nothing is due")

    -- A capture of named parts points only those.
    snSettled, snAt, snPending = ns.EUISettleRecord("capture", {
        settled = { [1] = { s = "one" } }, at = { ["*"] = 1, [UF] = false, [AB] = false },
        pending = { [UF] = true, [AB] = true }, due = { [UF] = true },
    }, { id = 2, entry = { s = "two" } })
    check(snAt and snAt[UF] == 2 and snAt[AB] == false and snAt["*"] == 1, "capture: a named due part gets the new snapshot")
    check(snSettled and snSettled[1] and snSettled[2], "capture: beside the one the others keep")
    check(snPending and snPending[AB] and not snPending[UF], "capture: and the part installed since still waits")
    snSettled = ns.EUISettleRecord("capture", { settled = { [1] = { s = "one" } }, at = { ["*"] = 1 } },
        { id = 0, entry = { s = "x" } })
    check(snSettled and snSettled[1] and snSettled[0] == nil, "capture: a bad id records nothing")

    -- Saved data can hold anything: a value of the wrong type is read as
    -- absent, and dropped at the write.
    local snOk, snBad, snBadAt, snBadPending, snBadDue = pcall(ns.EUISettleRecord, "take", {
        settled = { [1] = { s = 5 }, x = { s = "s" }, [2] = { s = "two" } },
        at = { [UF] = "bad", ["*"] = 2, [AB] = 0.5 },
        pending = { [UF] = "yes", general = true },
        due = "corrupt",
    }, { parts = {} })
    check(snOk, "settle: a malformed record raises nothing", snBad)
    check(snOk and snBad and snBad[2] and snBad[1] == nil and snBad.x == nil, "settle: only sound snapshots are kept")
    check(snOk and snBadAt and snBadAt["*"] == 2 and snBadAt[UF] == nil and snBadAt[AB] == nil, "settle: and sound pointers")
    check(snOk and snBadPending and snBadPending.general and snBadPending[UF] == nil, "settle: and true marks")
    check(snOk and type(snBadDue) == "table" and next(snBadDue) == nil, "settle: a due set that is not a table is empty")

    -- A part's snapshot and state.
    local snRecord = {
        settled = { [1] = { s = "a" }, [2] = { s = "b" } },
        at = { ["*"] = 1, [UF] = 2, [AB] = false, [CDM] = 9 },
        pending = { [AB] = true, [RB] = true },
    }
    eq(ns.EUISettledId(snRecord, UF), 2, "state: a named part's own snapshot")
    eq(ns.EUISettledId(snRecord, "general"), 1, "state: an unnamed part's is the one for every part")
    eq(ns.EUISettledId(snRecord, AB), nil, "state: a part installed since has none, not the one for every part")
    eq(ns.EUISettledId(snRecord, CDM), nil, "state: a pointer to no snapshot is none")
    eq(ns.EUISettleState(snRecord, {}, UF), "settled", "state: settled")
    eq(ns.EUISettleState(snRecord, {}, AB), "pending", "state: installed this session is pending")
    eq(ns.EUISettleState(snRecord, { [RB] = true }, RB), "due", "state: waiting from an earlier session is due")
    local snAll = { settled = { [1] = { s = "a" } }, at = { [UF] = 1 }, pending = { ["*"] = true } }
    eq(ns.EUISettleState(snAll, { ["*"] = true }, "general"), "due", "state: after a full install every part not named is due")
    eq(ns.EUISettleState(snAll, {}, "general"), "pending", "state: and pending in the session of the install")
    eq(ns.EUISettleState(snAll, { ["*"] = true }, UF), "settled", "state: the mark for every part skips a named one")
    eq(ns.EUISettleState({}, {}, UF), nil, "state: a profile from before snapshots has no state")

    -- The settled composite. The export left out Action Bars, which was not
    -- loaded, and the Spec Overrides snapshot did not decode.
    local snRows = { { id = UF }, { id = AB }, { id = "general" }, { id = "overrides" } }
    local snO = {
        addons = { [UF] = { v = "O" }, [AB] = { v = "O" } },
        fonts = { f = "O" },
        unlockLayout = { anchors = { UF_Player = { s = "O" } } },
        specOverrides = { "O" },
    }
    local snSnap = {
        addons = { [UF] = { v = "S" } },
        fonts = { f = "S" },
        unlockLayout = { anchors = { UF_Player = { s = "S" } } },
    }
    local snRec = { settled = { [1] = { s = "one" }, [2] = { s = "two" } }, at = { ["*"] = 1, overrides = 2 } }
    local snS = ns.EUIComposeSettled(snO, snRows, snRec, { [1] = snSnap }, k2f, {})
    eq(snS.addons[UF].v, "S", "compose: a part with a snapshot takes its slice")
    eq(snS.unlockLayout.anchors.UF_Player.s, "S", "compose: with its layout entries")
    eq(snS.fonts.f, "S", "compose: General too")
    eq(snS.addons[AB].v, "O", "compose: a folder part the snapshot lacks keeps the base's")
    eq(snS.specOverrides[1], "O", "compose: a part whose snapshot did not decode keeps the base's")
    eq(select("#", ns.EUIComposeSettled(snO, snRows, snRec, { [1] = snSnap }, k2f, {})), 1,
        "compose: it returns the composite alone")
    eq(snO.addons[UF].v, "O", "compose: the base is not written")
    local snMissing = ns.EUIComposeSettled(snO, snRows, snRec, { [1] = snSnap }, k2f, { [UF] = true })
    eq(snMissing.addons[UF].v, "O", "compose: a part with no base of its own keeps the base's")
    local snNone = ns.EUIComposeSettled(snO, snRows, {}, {}, k2f, {})
    check(rawequal(snNone, snO), "compose: with nothing settled the base is used as it is")
    local snPart = ns.EUIComposeSettled(snO, snRows, { settled = { [1] = { s = "one" } }, at = { [UF] = 1 } },
        { [1] = snSnap }, k2f, {})
    eq(snPart.fonts.f, "O", "compose: a part with no snapshot keeps the base's")
    eq(ns.EUIComposeSettled(nil, snRows, snRec, { [1] = snSnap }, k2f, {}), nil, "compose: no base gives no composite")
end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
