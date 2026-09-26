-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-merge-inputs.lua                                        ║
-- ║  Purpose: Gate for what surrounds the merge: the folder      ║
-- ║           strip, the stored-folder supplement, the layout    ║
-- ║           key resolver, the final endpoint filter, the       ║
-- ║           activation prediction and the two warnings.        ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe dev/tests/eui-merge-inputs.lua

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

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local ns = { profileName = "KitnUI" }
for _, file in ipairs({ "Installer/Merge.lua", "Installer/MergeInputs.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", ns)
end

eq(ns.EUIBackupName, "KitnUI (before update)", "backup profile name")

-- Strip sets ------------------------------------------------------------------

local MAP = {
    { folder = "EllesmereUIUnitFrames" },
    { folder = "EllesmereUIActionBars" },
    { folder = "EllesmereUICooldownManager" },
    { folder = "EllesmereUIChat" },
    { folder = "EllesmereUIChatBubbles", hostAddon = "EllesmereUIChat" },
    { folder = 7 },
    "garbage",
}

local keep, strip, stripCDM = ns.EUIStripSets(MAP, { "EllesmereUIActionBars", "EllesmereUIChat" })
check(keep.EllesmereUIUnitFrames and keep.EllesmereUICooldownManager, "strip: unnamed folders are kept")
check(strip.EllesmereUIActionBars and strip.EllesmereUIChat, "strip: named folders are stripped")
check(strip.EllesmereUIChatBubbles and not keep.EllesmereUIChatBubbles, "strip: a folder hosted by a stripped addon goes with it")
eq(count(keep) + count(strip), 5, "strip: malformed entries are ignored")
eq(stripCDM, false, "strip: CDM kept when not named")

local _, _, cdm = ns.EUIStripSets(MAP, { "EllesmereUICooldownManager" })
eq(cdm, true, "strip: CDM named strips the spell store")

local k2, s2 = ns.EUIStripSets(nil, nil)
eq(count(k2) + count(s2), 0, "strip: nil map yields empty sets")

local data = {
    addons = { EllesmereUIUnitFrames = { a = 1 }, EllesmereUIActionBars = { b = 2 } },
    cdmSpells = { [71] = { "x" } },
    unlockLayout = { anchors = { EllesmereUIActionBars_1 = { "p" } } },
}
ns.EUIStripFolders(data, { EllesmereUIActionBars = true }, true)
check(data.addons.EllesmereUIUnitFrames and not data.addons.EllesmereUIActionBars, "strip folders: removes the stripped folder only")
eq(data.cdmSpells, nil, "strip folders: CDM spell store goes when CDM is stripped")
check(data.unlockLayout.anchors.EllesmereUIActionBars_1 ~= nil, "strip folders: the layout is left for the final filter")
ns.EUIStripFolders(nil, {}, false)
ns.EUIStripFolders({ addons = { X = {} }, cdmSpells = {} }, {}, false)
check(true, "strip folders: tolerates nil data and empty strip")
local keepCDM = { cdmSpells = { [71] = {} } }
ns.EUIStripFolders(keepCDM, {}, false)
check(keepCDM.cdmSpells ~= nil, "strip folders: CDM spell store stays when CDM is kept")

-- Supplement P ----------------------------------------------------------------

local p = { addons = { EllesmereUIUnitFrames = { a = 1 } } }
local storedAddons = { EllesmereUIUnitFrames = { a = 99 }, EllesmereUITooltip = { t = { 1, 2 } }, Bad = "no" }
ns.EUISupplementP(p, storedAddons)
eq(p.addons.EllesmereUIUnitFrames.a, 1, "supplement: an exported folder is not overwritten")
check(p.addons.EllesmereUITooltip and p.addons.EllesmereUITooltip.t[2] == 2, "supplement: an unexported stored folder is copied in")
check(p.addons.EllesmereUITooltip ~= storedAddons.EllesmereUITooltip, "supplement: the copy is not the stored table")
eq(p.addons.Bad, nil, "supplement: a non-table stored entry is skipped")
local noAddons = {}
ns.EUISupplementP(noAddons, { X = { y = 1 } })
check(noAddons.addons and noAddons.addons.X.y == 1, "supplement: creates addons when P has none")
ns.EUISupplementP(nil, storedAddons)
ns.EUISupplementP(p, nil)
check(true, "supplement: tolerates nil on either side")

-- Overlay meta ----------------------------------------------------------------

local meta = ns.EUIOverlayMeta(
    { keyToFolder = { A_1 = "EllesmereUIActionBars", U_1 = "EllesmereUIUnitFrames" } },
    { keyToFolder = { A_1 = "EllesmereUIActionBarsNew", C_1 = "EllesmereUIChat" } })
eq(meta.A_1, "EllesmereUIActionBarsNew", "overlay: P's entry wins on a shared key")
eq(meta.U_1, "EllesmereUIUnitFrames", "overlay: N-only key survives")
eq(meta.C_1, "EllesmereUIChat", "overlay: P-only key survives")
eq(count(ns.EUIOverlayMeta(nil, { keyToFolder = "x" })), 0, "overlay: tolerates nil and malformed meta")

-- Layout key resolver ---------------------------------------------------------

local resolveCalls = {}
local function resolve(union, m)
    resolveCalls[#resolveCalls + 1] = { union = union, meta = m }
    local out = {}
    for _, map in ipairs({ "anchors", "widthMatch", "heightMatch" }) do
        for child in pairs(union[map] or {}) do out[child] = m[child] or "unmapped" end
    end
    return out
end
local sides = {
    { unlockLayout = { anchors = { A_1 = { "x" } } } },
    nil,
    { unlockLayout = { anchors = { B_1 = { "y" } }, widthMatch = { C_1 = "D_1" } } },
    { unlockLayout = "bad" },
}
local k2f = ns.EUILayoutKeyToFolder(sides, { A_1 = "FA", B_1 = "FB" }, resolve)
eq(k2f.A_1, "FA", "resolver: first side's anchor resolves")
eq(k2f.B_1, "FB", "resolver: later side's anchor resolves")
eq(k2f.C_1, "unmapped", "resolver: a widthMatch child with no meta is classified by the resolver")
eq(#resolveCalls, 1, "resolver: one resolver call over the union")
check(resolveCalls[1].union.heightMatch ~= nil, "resolver: every map is present in the union")
eq(count(ns.EUILayoutKeyToFolder({}, {}, function() return nil end)), 0, "resolver: nil from the resolver reads as empty")

-- Final layout filter ---------------------------------------------------------

local api = {
    BuildImportKeyToFolder = function(ul, m)
        local out = {}
        local function add(key)
            if type(key) == "string" and out[key] == nil then out[key] = m[key] end
        end
        for _, map in ipairs({ "anchors", "widthMatch", "heightMatch" }) do
            for child, v in pairs(ul[map] or {}) do
                add(child)
                if map == "anchors" then add(type(v) == "table" and v.target or nil) else add(v) end
            end
        end
        return out
    end,
    -- Mirrors the shipped filter's rule: an edge survives only when BOTH of
    -- its endpoints resolve to a surviving folder.
    FilterLayoutToFolders = function(ul, keepSet, k2fIn)
        local function endpointOK(key)
            return type(key) == "string" and k2fIn[key] ~= nil and keepSet[k2fIn[key]] == true
        end
        local out = { anchors = {}, widthMatch = {}, heightMatch = {}, phantomBounds = {} }
        for child, info in pairs(ul.anchors or {}) do
            if type(info) == "table" and endpointOK(child) and endpointOK(info.target) then out.anchors[child] = info end
        end
        for _, map in ipairs({ "widthMatch", "heightMatch" }) do
            for child, target in pairs(ul[map] or {}) do
                if endpointOK(child) and endpointOK(target) then out[map][child] = target end
            end
            -- An extra survives only beside a surviving link.
            local xmap = map .. "Extra"
            out[xmap] = {}
            for child, px in pairs(ul[xmap] or {}) do
                if out[map][child] ~= nil then out[xmap][child] = px end
            end
        end
        return out
    end,
}
local merged = {
    unlockLayout = {
        anchors = {
            A_1 = { target = "A_2", point = "TOP" },
            A_3 = { target = "B_1", point = "TOP" },
            B_1 = { target = "A_1", point = "TOP" },
            Z_1 = { target = "A_1", point = "TOP" },
        },
        widthMatch = { A_1 = "A_2", A_2 = "B_1" },
        heightMatch = {},
        phantomBounds = {},
    },
    unlockLayoutMeta = { keyToFolder = {} },
}
local report = { conflicts = { "unlockLayout.anchors.A_1", "unlockLayout.anchors.B_1", "addons.FA.x",
    "unlockLayout.widthMatch.A_1", "unlockLayout.anchors.A_3", "unlockLayout.widthMatch.A_2" } }
local removed = ns.EUIFinalLayoutFilter(merged, report, { A_1 = "FA", A_2 = "FA", A_3 = "FA", B_1 = "FB" }, { FA = true }, api)
check(removed["anchors.B_1"] and removed["anchors.Z_1"], "filter: stripped-owner and unmapped entries are removed")
check(removed["anchors.A_3"] and removed["widthMatch.A_2"], "filter: a kept child whose target crosses the strip boundary is removed")
eq(removed["anchors.A_1"], nil, "filter: a kept-owner entry with a kept target stays")
eq(count(removed), 4, "filter: exactly the removed entries are reported")
eq(#report.conflicts, 3, "filter: conflicts under removed entries are struck")
check(report.conflicts[1] == "unlockLayout.anchors.A_1" and report.conflicts[2] == "addons.FA.x" and report.conflicts[3] == "unlockLayout.widthMatch.A_1", "filter: surviving conflicts keep their order")
eq(merged.unlockLayout.anchors.B_1, nil, "filter: the merged layout is the filtered one")
eq(merged.unlockLayout.anchors.A_3, nil, "filter: no targetless anchor survives")
eq(merged.unlockLayoutMeta, nil, "filter: the meta is dropped from the payload")

local nilApi = { BuildImportKeyToFolder = function() return nil end, FilterLayoutToFolders = api.FilterLayoutToFolders }
local untouched = { unlockLayout = { anchors = { A_1 = { target = "A_2" } } }, unlockLayoutMeta = {} }
eq(ns.EUIFinalLayoutFilter(untouched, { conflicts = {} }, {}, { FA = true }, nilApi), nil, "filter: a nil resolver result is refused")
check(untouched.unlockLayout.anchors.A_1 ~= nil, "filter: a refused filter leaves the layout alone")
local nilFilter = { BuildImportKeyToFolder = api.BuildImportKeyToFolder, FilterLayoutToFolders = function() return nil end }
eq(ns.EUIFinalLayoutFilter(untouched, { conflicts = {} }, { A_1 = "FA", A_2 = "FA" }, { FA = true }, nilFilter), nil, "filter: a nil filter result is refused")

local noLayout = { unlockLayoutMeta = {} }
local r2 = { conflicts = { "addons.FA.x" } }
eq(count(ns.EUIFinalLayoutFilter(noLayout, r2, {}, {}, api)), 0, "filter: no layout removes nothing")
eq(noLayout.unlockLayoutMeta, nil, "filter: no layout still drops the meta")
eq(#r2.conflicts, 1, "filter: no layout leaves conflicts alone")

do
    local m = { unlockLayout = {
        anchors = {}, phantomBounds = {},
        widthMatch = { A_1 = "A_2", A_3 = "B_1" },
        heightMatch = { A_2 = "A_1" },
        widthMatchExtra = { A_1 = 4, A_3 = 6 },
        heightMatchExtra = { A_2 = -2 },
    } }
    local rep = { conflicts = { "unlockLayout.widthMatchExtra.A_1", "unlockLayout.widthMatchExtra.A_3",
        "unlockLayout.widthMatch.A_3", "unlockLayout.heightMatchExtra.A_2" } }
    local gone = ns.EUIFinalLayoutFilter(m, rep, { A_1 = "FA", A_2 = "FA", A_3 = "FA", B_1 = "FB" }, { FA = true }, api)
    check(gone["widthMatch.A_3"], "filter: a link crossing the strip boundary is removed")
    eq(#rep.conflicts, 2, "filter: an extra's conflict is struck with its removed link")
    check(rep.conflicts[1] == "unlockLayout.widthMatchExtra.A_1" and rep.conflicts[2] == "unlockLayout.heightMatchExtra.A_2",
        "filter: extras on surviving links keep their conflicts")
    eq(m.unlockLayout.widthMatchExtra.A_1, 4, "filter: a surviving link keeps its extra")
    eq(m.unlockLayout.widthMatchExtra.A_3, nil, "filter: a removed link's extra goes with it")
end

-- Activation prediction -------------------------------------------------------

local B = ns.EUIBackupName
eq(ns.EUIWillLock(nil, { [71] = "Other" }, false), false, "willLock: no spec never locks")
eq(ns.EUIWillLock(71, nil, false), false, "willLock: no assignments never locks")
eq(ns.EUIWillLock(71, { [71] = "KitnUI" }, false), false, "willLock: assigned to KitnUI does not lock")
eq(ns.EUIWillLock(71, { [71] = "Other" }, false), true, "willLock: assigned elsewhere locks")
eq(ns.EUIWillLock(71, { [71] = B }, true), false, "willLock: assigned to the backup that will be deleted does not lock")
eq(ns.EUIWillLock(71, { [71] = B }, false), true, "willLock: assigned to a stale backup name with no backup profile locks")
eq(ns.EUIWillLock(72, { [71] = "Other" }, false), false, "willLock: another spec's assignment is irrelevant")

-- Link warning ----------------------------------------------------------------

local storedK2F = { A_1 = "FA", B_1 = "FB", U_1 = "FU" }
local mergedAddons = { addons = { FA = {}, FB = {} }, unlockLayout = { anchors = {} } }
eq(ns.EUILinkWarning({ addons = { FA = {} } }, { anchors = { A_1 = 1 } }, nil, { ["anchors.A_1"] = true }, storedK2F), false,
    "link: no merged layout means the backup's layout is kept whole")
eq(ns.EUILinkWarning(mergedAddons, nil, nil, { ["anchors.A_1"] = true }, storedK2F), true,
    "link: a final-filter removal from an imported folder warns")
eq(ns.EUILinkWarning(mergedAddons, nil, nil, { ["anchors.U_1"] = true }, storedK2F), false,
    "link: a removal from a folder not imported does not warn")
eq(ns.EUILinkWarning(mergedAddons, nil, nil, { ["anchors.Q_1"] = true }, storedK2F), false,
    "link: a removal the stored meta cannot place does not warn")
eq(ns.EUILinkWarning(mergedAddons, { anchors = { B_1 = 1 } }, { anchors = {} }, {}, storedK2F), true,
    "link: a stored entry the export lacks warns")
eq(ns.EUILinkWarning(mergedAddons, { anchors = { B_1 = 1 } }, { anchors = { B_1 = 1 } }, {}, storedK2F), false,
    "link: a stored entry the export carries does not warn")
eq(ns.EUILinkWarning(mergedAddons, { widthMatch = { U_1 = "X" } }, nil, {}, storedK2F), false,
    "link: a stored entry from a folder not imported does not warn")

-- Sync group ------------------------------------------------------------------

local synced = { chat = { KitnUI = true, Other = true }, bars = { [B] = true } }
eq(ns.EUISharesSyncGroup(synced, "KitnUI", "Other"), true, "sync: both in one group")
eq(ns.EUISharesSyncGroup(synced, "KitnUI", B), false, "sync: in different groups")
eq(ns.EUISharesSyncGroup(nil, "a", "b"), false, "sync: nil store")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
