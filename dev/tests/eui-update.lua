-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-update.lua                                              ║
-- ║  Purpose: Gate for the update flow against a stub           ║
-- ║           EllesmereUI: page state, the decode cache, the     ║
-- ║           click's refusals and plan, the acceptance with its ║
-- ║           two rollbacks, and Restore previous.               ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\WoW-Dev\lua51\bin\lua.exe dev/tests/eui-update.lua

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
-- Stubs: the game, the installer's own namespace, and EllesmereUI
---------------------------------------------------------------------------------

local game = { combat = false, spec = 1, specID = 71 }
_G.InCombatLockdown = function() return game.combat end
_G.GetSpecialization = function() return game.spec end
_G.GetSpecializationInfo = function() return game.specID end

local ns = { profileName = "KitnUI", data = {}, title = "KitnUI" }
for _, file in ipairs({ "Installer/Merge.lua", "Installer/MergeInputs.lua", "Installer/ModuleRows.lua", "Installer/Update.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", ns)
end

-- The confirms color each run of text; the checks read the words alone, and
-- the color checks read the raw text.
local function plain(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local rawConfirmText, rawResetText = ns.EUIConfirmText, ns.EUIResetText
ns.EUIConfirmText = function(p) return plain(rawConfirmText(p)) end
ns.EUIResetText = function(p) return plain(rawResetText(p)) end

local SHIPPED = "2026.09.19"
local calls = {}
local function bump(name) calls[name] = (calls[name] or 0) + 1 end

ns.GetAddonDataVersion = function(key) return key == "EllesmereUI" and SHIPPED or nil end
ns.GetEUIModuleSet = function() return { "EllesmereUIActionBars" } end
ns.ApplyEUIModuleSet = function() bump("apply") end
ns.CompleteSetup = function(key)
    bump("complete")
    ns.db.profiles[key] = true
    ns.db.addonVersions[key] = SHIPPED
    if key == "EllesmereUI" then
        ns.db.euiBase = ns.data.EllesmereUI
        ns.db.euiRowAt, ns.db.euiBases = nil, nil
        ns.db.euiSettled, ns.db.euiSettledAt = nil, nil
        ns.db.euiSettlePending = { ["*"] = true }
        ns.euiSettleDue = {}
    end
end

-- Strings are tokens into this table; "decoding" is a deep copy of the entry.
local strings = {}
local function encode(token, payload) strings[token] = payload return token end
local function decodeToken(token)
    local p = strings[token]
    if not p then return nil, "Not a valid EllesmereUI string." end
    return ns.EUIDeepCopy(p)
end

local E = {}
_G.EllesmereUI = E
local db
_G.EllesmereUIDB = nil

local function resetDB()
    db = {
        activeProfile = "KitnUI",
        profiles = {},
        specProfiles = {},
        syncedModules = {},
        profileKeybinds = {},
        colorsPullFrom = nil,
        colorsApplyToAllProfiles = nil,
        colorsSectionPullFrom = nil,
        colorsSectionApplyAll = nil,
        ppUIScale = 0.9,
        ppUIScaleAuto = false,
    }
    _G.EllesmereUIDB = db
end

E._ADDON_DB_MAP = {
    { folder = "EllesmereUIUnitFrames" },
    { folder = "EllesmereUIActionBars" },
    { folder = "EllesmereUIResourceBars" },
    { folder = "EllesmereUICooldownManager" },
}
E._unlockModeActive = false
E.establishPending = false
E.Conditions_EstablishPending = function() return E.establishPending end
E.SpecOverrides_HarvestCurrent = function() bump("harvest") end
E.IsModuleAddonLoaded = function() return true end
E.RefreshAllAddons = function() bump("refresh") end
E.ApplyColorsToOUF = function() bump("colors") end
E.DecodeImportString = decodeToken
E.asyncMode = "sync"
E.DecodeImportStringAsync = function(s, onDone)
    local payload, err = decodeToken(s)
    if E.asyncMode == "sync" then
        onDone(payload, err)
        return nil
    end
    local run = { cancelled = false }
    run.Cancel = function() run.cancelled = true end
    E.pending = E.pending or {}
    E.pending[#E.pending + 1] = {
        run = run,
        fire = function() if not run.cancelled then onDone(payload, err) end end,
        -- A decoder that ignores Cancel: the cache's own generation check is
        -- what must drop the result.
        fireRaw = function() onDone(payload, err) end,
    }
    return run
end
function E.FirePending()
    local list = E.pending or {}
    E.pending = {}
    for _, p in ipairs(list) do p.fire() end
end

-- What the live profile holds: the export freshens the stored copy from it.
E.live = nil
E.ExportProfile = function(name)
    bump("export")
    if E.exportFails then return nil end
    local stored = db.profiles[name]
    if not stored then return nil end
    if E.live then
        for k, v in pairs(E.live) do stored[k] = ns.EUIDeepCopy(v) end
    end
    return encode("export:" .. name, { version = 3, type = "full", data = ns.EUIDeepCopy(stored) })
end
-- The per-section color sources (class, power, class resource), each with
-- its own pointer or reading the shared one. Installed only by
-- freshInstall({ colors94 = true }); without them the stub has the single
-- shared pointer of the older EllesmereUI.
local COLOR_SECTIONS = { "class", "power", "classResource" }
local function sectionApplyAll(s)
    local own = db.colorsSectionApplyAll and db.colorsSectionApplyAll[s]
    if own ~= nil then return own end
    return db.colorsApplyToAllProfiles ~= false
end
local colors94 = {
    PointColorSectionsAt = function(name)
        local t, sharedUsed = db.colorsSectionPullFrom, false
        for _, s in ipairs(COLOR_SECTIONS) do
            if sectionApplyAll(s) then
                if t and t[s] ~= nil then t[s] = name else sharedUsed = true end
            end
        end
        if sharedUsed then db.colorsPullFrom = name end
    end,
    ColorSourcesProfileRemoved = function(name)
        if db.colorsPullFrom == name then db.colorsPullFrom = nil end
        for s, n in pairs(db.colorsSectionPullFrom or {}) do
            if n == name then db.colorsSectionPullFrom[s] = nil end
        end
    end,
    ColorSourcesProfileRenamed = function(old, new)
        if db.colorsPullFrom == old then db.colorsPullFrom = new end
        for s, n in pairs(db.colorsSectionPullFrom or {}) do
            if n == old then db.colorsSectionPullFrom[s] = new end
        end
    end,
}
local function setColors94(on)
    for k, fn in pairs(colors94) do E[k] = on and fn or nil end
end

E.RenameProfile = function(old, new)
    bump("rename")
    if E.renameFails then return end
    db.profiles[new] = db.profiles[old]
    db.profiles[old] = nil
    if db.activeProfile == old then db.activeProfile = new end
    for spec, name in pairs(db.specProfiles) do
        if name == old then db.specProfiles[spec] = new end
    end
    if E.ColorSourcesProfileRenamed then E.ColorSourcesProfileRenamed(old, new) end
end
E.DeleteProfile = function(name)
    bump("delete")
    db.profiles[name] = nil
    for spec, n in pairs(db.specProfiles) do
        if n == name then db.specProfiles[spec] = nil end
    end
    if E.ColorSourcesProfileRemoved then
        E.ColorSourcesProfileRemoved(name)
    elseif db.colorsPullFrom == name then
        db.colorsPullFrom = nil
    end
    if db.activeProfile == name then db.activeProfile = "Default" end
end
E.SetProfile = function(name)
    bump("set")
    if E.switchFails then return end
    if db.profiles[name] then db.activeProfile = name end
end
-- The resolver classifies every endpoint, children and targets alike. The
-- filter keeps a link only when both endpoints resolve to a kept folder, and
-- an extra only beside a surviving link.
E.BuildImportKeyToFolder = function(ul, meta)
    local out = {}
    local function add(key)
        if type(key) == "string" and out[key] == nil then out[key] = meta[key] end
    end
    for _, map in ipairs({ "anchors", "widthMatch", "heightMatch" }) do
        for child, v in pairs(ul[map] or {}) do
            add(child)
            if map == "anchors" then add(type(v) == "table" and v.target or nil) else add(v) end
        end
    end
    return out
end
local SCREEN_EDGES = { SCREEN_LEFT = true, SCREEN_RIGHT = true, SCREEN_TOP = true, SCREEN_BOTTOM = true }
E.IsScreenEdgeKey = function(key) return SCREEN_EDGES[key] ~= nil end
E.FilterLayoutToFolders = function(ul, keepSet, k2f)
    local function endpointOK(key)
        return type(key) == "string" and k2f[key] ~= nil and keepSet[k2f[key]] == true
    end
    local out = { anchors = {}, widthMatch = {}, heightMatch = {}, phantomBounds = {} }
    for child, info in pairs(ul.anchors or {}) do
        local edge = E.IsScreenEdgeKey and E.IsScreenEdgeKey(info and info.target)
        if type(info) == "table" and endpointOK(child) and (endpointOK(info.target) or edge) then out.anchors[child] = info end
    end
    for map, xmap in pairs({ widthMatch = "widthMatchExtra", heightMatch = "heightMatchExtra" }) do
        for child, target in pairs(ul[map] or {}) do
            if endpointOK(child) and endpointOK(target) then out[map][child] = target end
        end
        out[xmap] = {}
        for child, px in pairs(ul[xmap] or {}) do
            if out[map][child] ~= nil then out[xmap][child] = px end
        end
    end
    return out
end
do
    local kept = E.FilterLayoutToFolders({ anchors = { bar = { target = "SCREEN_TOP" } } }, { Mod = true }, { bar = "Mod" })
    check(kept.anchors.bar ~= nil, "stub: an anchor to a screen edge is kept, as the real filter keeps it")
end
-- "activate" | "spec_locked" | "throw_before" | "throw_scale" | "throw_stored" | "throw_active"
E.importMode = "activate"
E.ImportProfile = function(payload, name)
    bump("import")
    E.lastImport = payload
    if E.importMode == "throw_before" then error("boom before store") end
    if E.importMode == "false_silent" then return false end
    if E.importMode == "false_said" then return false, "bad payload" end
    if E.importMode == "throw_scale" then
        if payload.data.uiScale then
            db.ppUIScale = payload.data.uiScale
            db.ppUIScaleAuto = false
        end
        error("boom after the scale")
    end
    db.profiles[name] = ns.EUIDeepCopy(payload.data)
    db.profiles[name].assignedSpecs = nil
    for _, spec in ipairs(payload.data.assignedSpecs or {}) do db.specProfiles[spec] = name end
    if payload.data.uiScale then
        db.ppUIScale = payload.data.uiScale
        db.ppUIScaleAuto = false
    end
    if E.importMode == "throw_stored" then error("boom after store") end
    if E.importMode == "spec_locked" then return true, nil, "spec_locked" end
    db.activeProfile = name
    if payload.data.customColors then
        if E.PointColorSectionsAt then
            E.PointColorSectionsAt(name)
        elseif db.colorsApplyToAllProfiles ~= false then
            db.colorsPullFrom = name
        end
    end
    if E.importMode == "throw_active" then error("boom in the tail") end
    return true
end

---------------------------------------------------------------------------------
-- Fixtures
---------------------------------------------------------------------------------

local F = "EllesmereUIUnitFrames"
local function payload(t)
    return { version = 3, type = "full", data = t }
end
local function base()
    return {
        addons = { [F] = { x = 1, y = 2 }, EllesmereUIActionBars = { bars = 3 } },
        fonts = { global = "F" },
        unlockLayout = { anchors = {}, widthMatch = {}, heightMatch = {}, phantomBounds = {} },
        unlockLayoutMeta = { keyToFolder = {} },
    }
end

local O_STR = encode("O", payload(base()))
local nData = base()
nData.addons[F].x = 5
nData.fonts.global = "G"
nData.uiScale = 0.8
local N_STR = encode("N", payload(nData))
ns.data.EllesmereUI = N_STR

local function freshInstall(opts)
    opts = opts or {}
    resetDB()
    setColors94(opts.colors94)
    calls = {}
    E.live = nil
    E.importMode = "activate"
    E.exportFails, E.renameFails, E.switchFails = nil, nil, nil
    E._unlockModeActive = false
    E.establishPending = false
    E.asyncMode = "sync"
    E.pending = nil
    game.combat = false
    ns.db = {
        profiles = { EllesmereUI = true },
        addonVersions = { EllesmereUI = opts.stamp or "2026.08.22" },
        euiBase = opts.base == nil and O_STR or opts.base,
    }
    ns.euiUpdatedThisSession = nil
    ns.euiSettleDue, ns.euiSettleOpen = nil, nil
    ns.EUIBeginVisit()
    local p = base()
    p.addons[F].y = 9
    db.profiles.KitnUI = p
    db.specProfiles[71] = "KitnUI"
    ns.EUICancelDecodes()
end

---------------------------------------------------------------------------------
-- Base seeding
---------------------------------------------------------------------------------

ns.db = { profiles = {}, addonVersions = { EllesmereUI = SHIPPED } }
ns.EUISeedBase()
eq(ns.db.euiBase, N_STR, "seed: a current stamp seeds the base with the shipped string")
ns.db = { profiles = {}, addonVersions = { EllesmereUI = "old" } }
ns.EUISeedBase()
eq(ns.db.euiBase, nil, "seed: a stale stamp seeds nothing")
ns.db = { profiles = {}, addonVersions = { EllesmereUI = SHIPPED }, euiBase = "kept" }
ns.EUISeedBase()
eq(ns.db.euiBase, "kept", "seed: an existing base is never overwritten")

---------------------------------------------------------------------------------
-- Page state and restorable
---------------------------------------------------------------------------------

freshInstall()
eq(ns.EUIUpdateState(), "update", "state: stale, active, API present is update")
ns.db.addonVersions.EllesmereUI = SHIPPED
eq(ns.EUIUpdateState(), "current", "state: matching stamp is current")
ns.db.profiles.EllesmereUI = nil
eq(ns.EUIUpdateState(), "none", "state: never installed is none")

freshInstall()
db.activeProfile = "Other"
local st, why = ns.EUIUpdateState()
eq(st, "stale", "state: another active profile is stale")
eq(why, "Switch to your KitnUI profile to update it.", "state: the reason names the switch")
freshInstall()
local saved = E.ImportProfile
E.ImportProfile = nil
st, why = ns.EUIUpdateState()
eq(st, "stale", "state: a missing API is stale")
eq(why, "Update needs a newer EllesmereUI.", "state: the reason names EllesmereUI")
E.ImportProfile = saved
freshInstall()
saved = E.SetProfile
E.SetProfile = nil
st = ns.EUIUpdateState()
eq(st, "stale", "state: a missing SetProfile is stale")
E.SetProfile = saved
freshInstall()
local savedMap = E._ADDON_DB_MAP
E._ADDON_DB_MAP = nil
eq(ns.EUIUpdateState(), "stale", "state: no db map is stale")
E._ADDON_DB_MAP = savedMap
freshInstall()
db.profiles.KitnUI = nil
db.activeProfile = "Default"
eq(ns.EUIUpdateState(), "stale", "state: a deleted profile is stale")

freshInstall()
eq(ns.EUIRestorable(), nil, "restorable: nothing without a backup")
db.profiles[ns.EUIBackupName] = base()
eq(ns.EUIRestorable(), nil, "restorable: a backup profile without a record is not restorable")
ns.db.euiBackup = { assignedSpecs = {} }
eq(ns.EUIRestorable(), "restore", "restorable: backup and record with KitnUI active")
db.activeProfile = "Other"
eq(ns.EUIRestorable(), "switch", "restorable: KitnUI exists and is not active needs a switch")
db.profiles.KitnUI = nil
eq(ns.EUIRestorable(), "restore", "restorable: the recovery state with no KitnUI restores")

---------------------------------------------------------------------------------
-- The decode cache
---------------------------------------------------------------------------------

freshInstall()
local readyCalls = 0
ns.EUIStartDecodes(function() readyCalls = readyCalls + 1 end)
eq(readyCalls, 1, "decodes: synchronous decodes call onReady once")
check(ns.EUIDecodesReady(), "decodes: ready after both")
check(ns.EUIDecodeCache.O and ns.EUIDecodeCache.O.data.addons[F].x == 1, "decodes: O is the base")
check(ns.EUIDecodeCache.N and ns.EUIDecodeCache.N.data.addons[F].x == 5, "decodes: N is the shipped string")

freshInstall()
E.asyncMode = "async"
readyCalls = 0
ns.EUIStartDecodes(function() readyCalls = readyCalls + 1 end)
check(not ns.EUIDecodesReady(), "decodes: not ready while O is in flight")
check(ns.EUIDecodeCache.handleO ~= nil, "decodes: the O handle is held")
E.FirePending()
check(not ns.EUIDecodesReady(), "decodes: not ready while N is in flight")
check(ns.EUIDecodeCache.handleO == nil and ns.EUIDecodeCache.handleN ~= nil, "decodes: O handle released, N handle held")
E.FirePending()
check(ns.EUIDecodesReady() and readyCalls == 1, "decodes: ready once N lands")

freshInstall()
E.asyncMode = "async"
readyCalls = 0
ns.EUIStartDecodes(function() readyCalls = readyCalls + 1 end)
local handle = ns.EUIDecodeCache.handleO
ns.EUICancelDecodes()
check(handle.cancelled, "decodes: cancel calls the live handle's Cancel")
E.FirePending()
check(ns.EUIDecodeCache.O == nil and readyCalls == 0, "decodes: a cancelled run stores nothing")
check(not ns.EUIDecodesReady(), "decodes: cancelled is not ready")

freshInstall()
E.asyncMode = "async"
readyCalls = 0
ns.EUIStartDecodes(function() readyCalls = readyCalls + 1 end)
local stale = E.pending
E.pending = nil
ns.EUIStartDecodes(function() readyCalls = readyCalls + 1 end)
for _, p in ipairs(stale) do p.fireRaw() end
check(ns.EUIDecodeCache.O == nil and ns.EUIDecodeCache.N == nil, "decodes: a stale generation's result is dropped")
eq(readyCalls, 0, "decodes: a stale generation reports nothing")
E.FirePending()
local staleN = E.pending
E.pending = nil
ns.EUICancelDecodes()
for _, p in ipairs(staleN) do p.fireRaw() end
check(ns.EUIDecodeCache.N == nil and not ns.EUIDecodesReady() and readyCalls == 0, "decodes: a cancelled N delivered anyway is dropped")
ns.EUIStartDecodes(function() readyCalls = readyCalls + 1 end)
E.FirePending()
E.FirePending()
check(ns.EUIDecodesReady(), "decodes: the restarted run completes")
eq(readyCalls, 1, "decodes: and reports once")

freshInstall({ base = false })
ns.EUIStartDecodes()
check(ns.EUIDecodesReady() and ns.EUIDecodeCache.failedO and ns.EUIDecodeCache.O == nil, "decodes: no base is the failed-O state")
freshInstall({ base = "garbage" })
ns.EUIStartDecodes()
check(ns.EUIDecodesReady() and ns.EUIDecodeCache.failedO, "decodes: an undecodable base is the failed-O state")
freshInstall()
ns.data.EllesmereUI = "garbage"
ns.EUIStartDecodes()
check(ns.EUIDecodesReady() and ns.EUIDecodeCache.failedN, "decodes: an undecodable shipped string is the failed-N state")
ns.data.EllesmereUI = N_STR

-- Saved data can hold anything: a stored base under a key that is not a
-- version string is skipped, not sorted beside the others.
freshInstall()
ns.db.euiBases = { ["2026.08.01"] = O_STR, [5] = O_STR }
local sortOk, sortErr = pcall(ns.EUIStartDecodes)
check(sortOk, "decodes: a base stored under a key that is not a version string raises nothing", sortErr)
check(ns.EUIDecodeCache.byVersion["2026.08.01"] ~= nil and ns.EUIDecodeCache.byVersion[5] == nil,
    "decodes: and only version strings are decoded")

---------------------------------------------------------------------------------
-- The click
---------------------------------------------------------------------------------

local plan, reason, _

freshInstall()
plan, reason = ns.EUIPrepareUpdate()
eq(plan, nil, "click: refuses before the decodes ran")
eq(reason, "Preparing...", "click: the refusal is the preparing line")

freshInstall()
ns.EUIStartDecodes()
game.combat = true
_, reason = ns.EUIPrepareUpdate()
eq(reason, "Cannot update in combat", "click: combat refusal")
game.combat = false
db.activeProfile = "Other"
_, reason = ns.EUIPrepareUpdate()
eq(reason, "Switch to your KitnUI profile to update it.", "click: inactive refusal")
db.activeProfile = "KitnUI"
E._unlockModeActive = true
_, reason = ns.EUIPrepareUpdate()
eq(reason, "Save or exit Unlock Mode before updating.", "click: unlock mode refusal")
E._unlockModeActive = false
E.establishPending = true
_, reason = ns.EUIPrepareUpdate()
eq(reason, "Try again in a moment.", "click: establish pending refusal")
eq(calls.harvest, nil, "click: no harvest while establish is pending")
E.establishPending = false
E.exportFails = true
_, reason = ns.EUIPrepareUpdate()
eq(reason, "Could not read your current profile.", "click: export failure refusal")
E.exportFails = nil

freshInstall()
ns.data.EllesmereUI = "garbage"
ns.EUIStartDecodes()
_, reason = ns.EUIPrepareUpdate()
eq(reason, "EllesmereUI import failed", "click: a failed N decode refuses")
ns.data.EllesmereUI = N_STR

freshInstall()
ns.EUIStartDecodes()
E.live = { fonts = { global = "Live" } }
plan, reason = ns.EUIPrepareUpdate()
check(plan ~= nil, "click: a plan is produced", reason)
eq(calls.harvest, 1, "click: the harvest ran once")
eq(calls.export, 1, "click: the export ran once")
eq(db.profiles.KitnUI.fonts.global, "Live", "click: the export freshened the stored profile")
eq(plan.merged.addons[F].x, 5, "click: Kitn's change is applied")
eq(plan.merged.addons[F].y, 9, "click: the player's change is kept")
eq(plan.merged.fonts.global, "G", "click: font changed on both sides is a conflict resolved to Kitn")
eq(#plan.report.conflicts, 1, "click: one conflict counted")
eq(plan.merged.addons.EllesmereUIActionBars, nil, "click: the disabled folder is stripped")
eq(plan.merged.uiScale, 0.8, "click: N's valid scale is taken")
eq(plan.merged.unlockLayoutMeta, nil, "click: the meta is dropped")
check(plan.merged.unlockLayout and plan.merged.unlockLayout.phantomBounds ~= nil, "click: the four layout maps are emitted")
eq(plan.willLock, false, "click: assigned to KitnUI does not lock")
eq(plan.noBase, false, "click: base known")
eq(plan.backupExists, false, "click: no backup yet")
eq(plan.warnMoved, false, "click: nothing moves to the backup")

local text = ns.EUIConfirmText(plan)
check(text:find("1 of your changes is replaced", 1, true), "confirm: the count line", text)
check(text:find("KitnUI's version is used", 1, true), "confirm: the promise line")
check(not text:find("previous backup", 1, true), "confirm: no backup line without a backup")
check(not text:find("Spec Overrides", 1, true), "confirm: no override line when no side carries one")

freshInstall({ base = false })
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
eq(plan.noBase, true, "click: no base plan")
eq(plan.merged.addons[F].y, 2, "click: no base replaces the player's change")
text = ns.EUIConfirmText(plan)
check(text:find("so the parts you tick replace yours.", 1, true), "confirm: the no-base lead", text)
check(not text:find("of your changes", 1, true), "confirm: and no total", text)
check(text:find(F .. ": replaces yours", 1, true), "confirm: with no base a ticked part replaces the player's changes", text)
check(not text:find("none of yours", 1, true), "confirm: and no part claims none of theirs is replaced", text)

-- One part with no base of its own: that part's line says so, and a part
-- with its base still counts.
freshInstall()
ns.db.euiRowAt = { [F] = { version = "none" } }
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
eq(plan.noBase, false, "click: one part without a base is not the no-base path")
check(plan.inputs.missing[F], "click: that part is missing its base")
text = ns.EUIConfirmText(plan)
check(text:find(F .. ": replaces yours", 1, true), "confirm: that part replaces the player's changes", text)
check(not text:find(F .. ": none of yours", 1, true) and not text:find(F .. ": 2 of yours", 1, true),
    "confirm: with no count of its own", text)
check(text:find("General: none of yours", 1, true), "confirm: a part with its base still counts", text)

freshInstall()
db.profiles[ns.EUIBackupName] = base()
db.profileKeybinds.KitnUI = "F5"
db.specProfiles[71] = "Other"
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
eq(plan.backupExists, true, "click: a previous backup is noticed")
eq(plan.warnMoved, true, "click: a keybind moves to the backup")
eq(plan.willLock, true, "click: assigned elsewhere locks")
text = ns.EUIConfirmText(plan)
check(text:find("Your previous backup will be replaced.", 1, true), "confirm: the backup line")
check(text:find("keybind", 1, true), "confirm: the moved line")

-- The confirm's groups and colors, on the one-conflict update: the player's
-- live font against KitnUI's.
freshInstall()
ns.EUIStartDecodes()
E.live = { fonts = { global = "Live" } }
plan = ns.EUIPrepareUpdate()
eq(#plan.report.conflicts, 1, "confirm: the color fixture has one conflict")
local raw = rawConfirmText(plan)
check(raw:find("|cffffffff" .. F .. "|r", 1, true), "confirm: a part's name is white", raw)
check(raw:find("|cffE6B24C1|r", 1, true), "confirm: the total's count is amber", raw)
text = ns.EUIConfirmText(plan)
eq(text:find("Your changes are kept and KitnUI's come in.", 1, true), 1, "confirm: the lead comes first")
check(text:find("\n\n", 1, true), "confirm: groups are set apart by a blank line", text)
check(text:find("Restore previous puts back your profile as it is now.", 1, true),
    "confirm: a visit's first change promises the profile as it is now", text)
local function totalLine(conflicts)
    return ns.EUIConfirmText({ inputs = { rows = {}, missing = {} }, ticked = {}, byRow = {},
        report = { conflicts = conflicts }, noBase = false })
end
check(totalLine({}):find("None of your changes are replaced.", 1, true), "confirm: the zero total")
check(totalLine({ "a", "b" }):find("2 of your changes are replaced because", 1, true), "confirm: the plural total")
check(not ns.EUI_UPDATE_TEXT.health:find("colour", 1, true) and ns.EUI_UPDATE_TEXT.health:find("class color", 1, true),
    "text: the health line in American spelling")

-- Match extras through the click. O, N and P share one width link whose
-- endpoints the meta places, and P carries an extra on it. These prove what
-- the update hands the importer, not what the importer stores.
local EXTRAS_META = { keyToFolder = { player_cb = F, player = F, target = F, bar_ab = "EllesmereUIActionBars" } }

local function linkExtras(d, target)
    d.unlockLayout.widthMatch = { player_cb = target }
    d.unlockLayoutMeta = ns.EUIDeepCopy(EXTRAS_META)
end

local function resetExtras()
    for _, d in ipairs({ strings.O.data, nData }) do
        d.unlockLayout.widthMatch, d.unlockLayoutMeta = {}, { keyToFolder = {} }
    end
end

local function prepareExtras(nTarget)
    linkExtras(strings.O.data, "player")
    linkExtras(nData, nTarget)
    freshInstall()
    linkExtras(db.profiles.KitnUI, "player")
    db.profiles.KitnUI.unlockLayout.widthMatchExtra = { player_cb = 6 }
    ns.EUIStartDecodes()
    return ns.EUIPrepareUpdate()
end

do
    local kept = prepareExtras("player")
    eq(kept.merged.unlockLayout.widthMatchExtra.player_cb, 6, "extras: the plan keeps the player's extra on a link Kitn left alone")
    eq(#kept.report.conflicts, 0, "extras: and adds nothing to the count")
    eq(ns.EUIApplyUpdate(kept), true, "extras: the kept plan applies")
    eq(E.lastImport.data.unlockLayout.widthMatchExtra.player_cb, 6, "extras: the payload handed to the importer carries the extra")
    local moved = prepareExtras("target")
    eq(moved.merged.unlockLayout.widthMatch.player_cb, "target", "extras: Kitn's re-pointed link is taken")
    eq(moved.merged.unlockLayout.widthMatchExtra.player_cb, nil, "extras: the player's extra is dropped with the link")
    check(ns.EUIConfirmText(moved):find("1 of your changes is replaced", 1, true),
        "extras: the confirm counts the dropped extra")
    eq(moved.byRow[F], 1, "extras: the dropped extra counts under the part that owns the bar")
    -- Unticked, the part keeps the player's link and the extra beside it, and
    -- the dropped extra leaves the count with the link.
    local unticked = ns.EUIPrepareUpdate({ general = true })
    eq(unticked and unticked.merged.unlockLayout.widthMatch.player_cb, "player", "extras: an unticked part keeps the player's link")
    eq(unticked and unticked.merged.unlockLayout.widthMatchExtra.player_cb, 6, "extras: and the player's extra beside it")
    eq(unticked and #unticked.report.conflicts, 0, "extras: with nothing of that part counted")
    -- A part reset takes KitnUI's link and KitnUI's extra, none here, and its
    -- count holds the extra it replaces beside the player's own change.
    local extrasReset = ns.EUIPrepareReset(F, { defaults = {}, held = {}, unlock = {} })
    eq(extrasReset and extrasReset.merged.unlockLayout.widthMatch.player_cb, "target", "extras: a part reset takes KitnUI's link")
    eq(extrasReset and extrasReset.merged.unlockLayout.widthMatchExtra.player_cb, nil, "extras: and KitnUI's extra, not the player's")
    eq(extrasReset and extrasReset.yours, 2, "extras: the reset's count holds the player's change and the extra")
    resetExtras()
end

---------------------------------------------------------------------------------
-- The acceptance
---------------------------------------------------------------------------------

local ok, err

freshInstall()
ns.EUIStartDecodes()
E.live = { fonts = { global = "Live" } }
plan = ns.EUIPrepareUpdate()
calls = {}
ok, err = ns.EUIApplyUpdate(plan)
eq(ok, true, "apply: succeeds", err)
eq(calls.harvest, 1, "apply: re-banks before the rename")
eq(calls.export, 1, "apply: re-exports before the rename")
check(db.profiles[ns.EUIBackupName] ~= nil, "apply: the backup profile exists")
eq(db.profiles[ns.EUIBackupName].addons[F].y, 9, "apply: the backup holds the player's profile")
eq(db.profiles[ns.EUIBackupName].fonts.global, "Live", "apply: the backup holds the live font")
eq(db.profiles.KitnUI.fonts.global, "G", "apply: the conflict went Kitn's way")
eq(db.activeProfile, "KitnUI", "apply: KitnUI is active")
eq(db.profiles.KitnUI.addons[F].x, 5, "apply: the stored profile is the merge")
eq(db.specProfiles[71], "KitnUI", "apply: the assignment points at the new profile")
eq(E.lastImport.data.assignedSpecs[1], 71, "apply: the payload carried the fresh assignments")
eq(ns.db.addonVersions.EllesmereUI, SHIPPED, "apply: the stamp is current")
eq(ns.db.euiBase, N_STR, "apply: the base is the shipped string")
eq(ns.db.euiBackup.version, "2026.08.22", "apply: the record holds the old stamp")
eq(ns.db.euiBackup.base, O_STR, "apply: the record holds the old base")
eq(ns.db.euiBackup.colorsPullFrom, false, "apply: nil colour source is recorded as false")
eq(ns.db.euiBackup.scaleTaken, true, "apply: the scale was taken")
eq(ns.db.euiBackup.ppUIScale, 0.9, "apply: the record holds the old scale")
eq(ns.db.euiUpdateReport.kept, plan.report.kept, "apply: the report is stored")
eq(calls.complete, 1, "apply: CompleteSetup ran")
eq(calls.refresh, 1, "apply: refresh ran")
eq(calls.apply, 1, "apply: the module set was re-applied")
eq(ns.EUIUpdateToast(plan), "Profile updated. 1 of your changes was replaced.", "apply: the toast counts")
eq(ns.EUIUpdateToast({ report = { conflicts = { "a", "b" } } }), "Profile updated. 2 of your changes were replaced.",
    "apply: the plural toast")
eq(ns.EUIUpdateToast({ report = { conflicts = {} } }), "Profile updated.", "apply: the zero toast")
eq(ns.EUIUpdateState(), "current", "apply: the page reads current")
eq(ns.EUIRestorable(), "restore", "apply: restore is offered")

-- A second update in a new visit replaces the previous backup.
ns.EUIBeginVisit()
ns.db.addonVersions.EllesmereUI = "2026.08.22"
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
calls = {}
ok, err = ns.EUIApplyUpdate(plan)
eq(ok, true, "apply twice: succeeds", err)
eq(calls.delete, 1, "apply twice: the previous backup is deleted")

-- Refusals at acceptance.
freshInstall()
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
game.combat = true
_, err = ns.EUIApplyUpdate(plan)
eq(err, "Cannot update in combat", "apply: combat refusal")
game.combat = false
E.exportFails = true
_, err = ns.EUIApplyUpdate(plan)
eq(err, "Could not read your current profile.", "apply: export failure refuses before the rename")
eq(calls.rename, nil, "apply: nothing renamed on a refusal")
E.exportFails = nil

-- Reconfirm when the activation prediction changed: the recount runs over
-- the inputs the confirm described, so an edit made during the dialog is
-- banked and not merged.
freshInstall()
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
db.specProfiles[71] = "Other"
E.live = { addons = { [F] = { x = 1, y = 50 }, EllesmereUIActionBars = { bars = 3 } } }
calls = {}
ok, err = ns.EUIApplyUpdate(plan)
eq(ok, "reconfirm", "apply: a changed prediction asks again")
eq(err.willLock, true, "apply: the fresh plan carries the new prediction")
eq(calls.rename, nil, "apply: nothing renamed before the second confirm")
eq(calls.export, 1, "apply: the dialog edit was banked once")
eq(err.merged.addons[F].y, 9, "apply: the recount merges the profile the confirm described")
eq(db.profiles.KitnUI.addons[F].y, 50, "apply: the dialog edit is in the stored profile the rename will carry")
check(err.inputs == plan.inputs, "apply: the fresh plan holds the same inputs")
ok, err = ns.EUIApplyUpdate(err)
eq(ok, true, "apply: the second confirm applies", err)
eq(db.profiles.KitnUI.addons[F].y, 9, "apply: the applied profile is the described merge")
eq(db.profiles[ns.EUIBackupName].addons[F].y, 50, "apply: the backup holds the dialog edit")

-- A conflict path is printed under the dev-mode flag only.
freshInstall()
ns.EUIStartDecodes()
E.live = { fonts = { global = "Mine" } }
local printed = {}
local savedPrint = _G.print
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
plan = ns.EUIPrepareUpdate()
_G.print = savedPrint
eq(#plan.report.conflicts, 1, "click: one conflict for the printing case")
eq(#printed, 0, "click: nothing printed without dev mode")
ns.db.devMode = true
printed = {}
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
plan = ns.EUIPrepareUpdate()
_G.print = savedPrint
ns.db.devMode = nil
eq(#printed, #plan.report.conflicts, "click: dev mode prints each conflict path")
check(printed[1] and printed[1]:find("fonts.global", 1, true), "click: the printed line names the path")

-- A re-pointed link whose new target sits in a disabled module is removed
-- by the filter; the extra it displaced is not counted, the warning shows.
do
    local cut = prepareExtras("bar_ab")
    eq(cut.merged.unlockLayout.widthMatch.player_cb, nil, "extras: a link into a disabled module is removed by the filter")
    eq(#cut.report.conflicts, 0, "extras: the displaced extra's count is struck with its link")
    eq(cut.warnLinks, true, "extras: the links warning shows instead")
    resetExtras()
end

-- A resolver that answers nothing refuses the click.
freshInstall()
ns.EUIStartDecodes()
saved = E.FilterLayoutToFolders
E.FilterLayoutToFolders = function() return nil end
plan, err = ns.EUIPrepareUpdate()
eq(plan, nil, "click: a nil filter result refuses")
eq(err, "Could not read your current profile.", "click: with the read-failure line")
E.FilterLayoutToFolders = saved

-- spec_locked path.
freshInstall()
db.specProfiles[71] = "Other"
nData.customColors = { a = 1 }
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
E.importMode = "spec_locked"
ok, err = ns.EUIApplyUpdate(plan)
eq(ok, true, "spec_locked: succeeds", err)
eq(db.activeProfile, "KitnUI", "spec_locked: SetProfile made it active")
eq(db.colorsPullFrom, "KitnUI", "spec_locked: the colour source is redirected")
eq(calls.set, 1, "spec_locked: one switch")
db.colorsApplyToAllProfiles = false
freshInstall()
db.specProfiles[71] = "Other"
db.colorsApplyToAllProfiles = false
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
E.importMode = "spec_locked"
ns.EUIApplyUpdate(plan)
eq(db.colorsPullFrom, nil, "spec_locked: no redirect when colours do not apply to all")
nData.customColors = nil

-- Rollback A: thrown before the store.
freshInstall()
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
E.importMode = "throw_before"
calls = {}
local detail
ok, err, detail = ns.EUIApplyUpdate(plan)
eq(ok, false, "rollback A: reports failure")
check(err:find("EllesmereUI import failed.", 1, true) and err:find("put back", 1, true), "rollback A: the failure and the outcome are named", err)
check(not err:find("boom", 1, true), "rollback A: the raw error stays out of the toast line", err)
check(detail and detail:find("boom before store", 1, true), "rollback A: the raw error comes back apart", detail)
check(not err:find("/reload", 1, true), "rollback A: no reload asked for when the scale never moved", err)
eq(db.profiles[ns.EUIBackupName], nil, "rollback A: the backup name is gone")
eq(db.profiles.KitnUI.addons[F].y, 9, "rollback A: the player's profile is back under its name")
eq(db.activeProfile, "KitnUI", "rollback A: and active")
eq(db.specProfiles[71], "KitnUI", "rollback A: assignments followed the rename back")
eq(ns.db.euiBackup, nil, "rollback A: the record is cleared")
eq(ns.db.addonVersions.EllesmereUI, "2026.08.22", "rollback A: not stamped")

-- Rollback A on a refusal rather than a throw: the importer's own words, when it
-- gives any, are the detail; none is invented when it gives none.
freshInstall()
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
E.importMode = "false_said"
ok, err, detail = ns.EUIApplyUpdate(plan)
eq(ok, false, "refused import: reports failure")
check(err:find("EllesmereUI import failed.", 1, true) and err:find("put back", 1, true), "refused import: the failure and the outcome are named", err)
eq(detail, "bad payload", "refused import: the importer's message is the detail")
freshInstall()
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
E.importMode = "false_silent"
ok, err, detail = ns.EUIApplyUpdate(plan)
eq(ok, false, "silent refusal: reports failure")
check(err:find("EllesmereUI import failed.", 1, true), "silent refusal: the failure is named", err)
eq(db.activeProfile, "KitnUI", "silent refusal: the player's profile is back")
eq(detail, nil, "silent refusal: no detail is invented")

-- Rollback A after the importer wrote the scale and then threw: the scale
-- goes back with the profile.
freshInstall()
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
eq(plan.merged.uiScale, 0.8, "rollback A scale: the plan takes N's scale")
E.importMode = "throw_scale"
ok, err = ns.EUIApplyUpdate(plan)
eq(ok, false, "rollback A scale: reports failure")
check(err:find("put back", 1, true), "rollback A scale: rolled back A", err)
check(err:find("Type /reload to put your UI scale back.", 1, true), "rollback A scale: asks for a reload", err)
eq(db.ppUIScale, 0.9, "rollback A scale: the scale is put back")
eq(db.ppUIScaleAuto, false, "rollback A scale: and its auto flag")
eq(db.profiles.KitnUI.addons[F].y, 9, "rollback A scale: the player's profile is back")
eq(calls.refresh, 1, "rollback A: refreshed")
eq(calls.complete, nil, "rollback A: CompleteSetup did not run")

-- Rollback B: stored, spec_locked, switch failed.
freshInstall()
db.specProfiles[71] = "Other"
db.specProfiles[72] = "KitnUI"
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
E.importMode = "spec_locked"
E.switchFails = true
calls = {}
ok, err, detail = ns.EUIApplyUpdate(plan)
eq(ok, false, "rollback B: reports failure")
check(err:find("Could not switch to the updated profile", 1, true), "rollback B: names the switch", err)
check(err:find("Type /reload to put your UI scale back.", 1, true), "rollback B: asks for a reload after the scale moved", err)
eq(detail, nil, "rollback B: no importer error to report")
eq(db.profiles[ns.EUIBackupName], nil, "rollback B: the backup name is gone")
eq(db.profiles.KitnUI.addons[F].y, 9, "rollback B: the player's profile is back")
eq(db.activeProfile, "KitnUI", "rollback B: and active")
eq(db.specProfiles[72], "KitnUI", "rollback B: the assignment is re-pointed")
eq(db.ppUIScale, 0.9, "rollback B: the scale the import wrote is restored")
eq(ns.db.euiBackup, nil, "rollback B: the record is cleared")
eq(calls.delete, 1, "rollback B: the stored profile was deleted")

-- Rollback B: thrown after the store, before activation.
freshInstall()
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
E.importMode = "throw_stored"
ok, err, detail = ns.EUIApplyUpdate(plan)
eq(ok, false, "rollback B (thrown): reports failure")
check(err:find("EllesmereUI import failed.", 1, true) and err:find("put back", 1, true), "rollback B (thrown): the failure and the outcome are named", err)
check(detail and detail:find("boom after store", 1, true), "rollback B (thrown): the raw error comes back apart", detail)
check(err:find("Type /reload to put your UI scale back.", 1, true), "rollback B (thrown): asks for a reload after the scale moved", err)
eq(db.activeProfile, "KitnUI", "rollback B (thrown): the player's profile is active")
eq(db.profiles.KitnUI.addons[F].y, 9, "rollback B (thrown): and is the player's")

-- Thrown in the activation tail: no rollback, backup kept.
freshInstall()
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
E.importMode = "throw_active"
calls = {}
ok, err, detail = ns.EUIApplyUpdate(plan)
eq(ok, false, "tail error: reports failure")
check(err:find("Restore previous puts your previous profile back.", 1, true), "tail error: points at Restore", err)
check(detail and detail:find("boom in the tail", 1, true), "tail error: the error is reported apart", detail)
eq(db.activeProfile, "KitnUI", "tail error: the merged profile stays active")
eq(db.profiles.KitnUI.addons[F].x, 5, "tail error: and is the merge")
check(db.profiles[ns.EUIBackupName] ~= nil, "tail error: the backup profile is kept")
check(ns.db.euiBackup ~= nil, "tail error: the record is kept")
eq(ns.db.addonVersions.EllesmereUI, "2026.08.22", "tail error: not stamped")
eq(calls.refresh, 1, "tail error: refreshed")
eq(ns.EUIUpdateState(), "update", "tail error: update is offered again")
eq(ns.EUIRestorable(), "restore", "tail error: restore is offered")

---------------------------------------------------------------------------------
-- Restore previous
---------------------------------------------------------------------------------

freshInstall()
db.specProfiles[72] = "KitnUI"
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
ok, err = ns.EUIApplyUpdate(plan)
eq(ok, true, "restore setup: the update succeeded", err)
saved = E.DeleteProfile
E.DeleteProfile = nil
calls = {}
ok, err = ns.EUIRestorePrevious()
eq(ok, false, "restore: a missing API refuses")
eq(err, "Update needs a newer EllesmereUI.", "restore: with the EllesmereUI line")
check(calls.set == nil and calls.rename == nil, "restore: and touches nothing")
E.DeleteProfile = saved
E.live = { fonts = { global = "Edited" } }
calls = {}
ok, err = ns.EUIRestorePrevious()
eq(ok, true, "restore: succeeds", err)
eq(calls.set, 1, "restore: switched to the backup first")
eq(calls.delete, 1, "restore: deleted the merged profile")
eq(db.profiles[ns.EUIBackupName], nil, "restore: the backup name is gone")
eq(db.profiles.KitnUI.addons[F].y, 9, "restore: the player's profile is back")
eq(db.activeProfile, "KitnUI", "restore: and active")
check(db.specProfiles[71] == "KitnUI" and db.specProfiles[72] == "KitnUI", "restore: assignments are back")
eq(db.ppUIScale, 0.9, "restore: the scale is back")
eq(err, "Type /reload to put your UI scale back.", "restore: asks for a reload after the scale moved")
eq(db.colorsPullFrom, nil, "restore: the colour source is back to nil")
eq(calls.colors, 1, "restore: colours re-applied")
eq(ns.db.euiBase, O_STR, "restore: the base is the backup's")
eq(ns.db.addonVersions.EllesmereUI, "2026.08.22", "restore: the stamp is the backup's")
eq(ns.db.euiUpdateReport, nil, "restore: the report is cleared")
eq(ns.db.euiBackup, nil, "restore: the record is cleared")
eq(ns.EUIUpdateState(), "update", "restore: update is offered again")
eq(ns.EUIRestorable(), nil, "restore: nothing left to restore")

-- Refusals.
freshInstall()
ns.EUIStartDecodes()
ns.EUIApplyUpdate(ns.EUIPrepareUpdate())
game.combat = true
_, err = ns.EUIRestorePrevious()
eq(err, "Cannot restore in combat", "restore: combat refusal")
game.combat = false
E._unlockModeActive = true
_, err = ns.EUIRestorePrevious()
eq(err, "Save or exit Unlock Mode before restoring.", "restore: unlock mode refusal")
E._unlockModeActive = false
db.activeProfile = "Other"
db.profiles.Other = {}
_, err = ns.EUIRestorePrevious()
eq(err, "Switch to your KitnUI profile first", "restore: not restorable while another profile is active")
db.activeProfile = "KitnUI"
db.syncedModules.chat = { KitnUI = true, [ns.EUIBackupName] = true }
_, err = ns.EUIRestorePrevious()
check(err and err:find("share a sync group", 1, true), "restore: shared sync group refusal", err)
db.syncedModules.chat = nil
E.switchFails = true
_, err = ns.EUIRestorePrevious()
eq(err, "Could not switch to the backup.", "restore: switch failure refusal")
E.switchFails = nil

-- Recovery state: KitnUI gone, backup active.
freshInstall()
ns.EUIStartDecodes()
ns.EUIApplyUpdate(ns.EUIPrepareUpdate())
E.DeleteProfile("KitnUI")
db.activeProfile = ns.EUIBackupName
db.syncedModules.chat = { [ns.EUIBackupName] = true, Default = true }
calls = {}
ok, err = ns.EUIRestorePrevious()
eq(ok, true, "recovery: restores with the backup active", err)
eq(calls.delete, nil, "recovery: nothing to delete")
eq(db.activeProfile, "KitnUI", "recovery: KitnUI is active again")
check(db.syncedModules.chat.KitnUI == nil, "recovery: sync membership is EllesmereUI's to move")

---------------------------------------------------------------------------------
-- Parts: a ticked update, the record it leaves, and nothing ticked
---------------------------------------------------------------------------------

-- The stub map carries no names, so a module row is labelled by its folder.
freshInstall()
ns.EUIStartDecodes()
E.live = { addons = { [F] = { x = 7, y = 9 }, EllesmereUIActionBars = { bars = 3 } } }
local partPlan, partWhy = ns.EUIPrepareUpdate({ [F] = true })
check(partPlan ~= nil, "parts: a ticked plan is produced", partWhy)
eq(partPlan.kind, "update", "parts: a stale stamp is an update")
check(partPlan.ticked[F] and not partPlan.ticked.general, "parts: only the ticked row is taken")
check(partPlan.changed[F] and partPlan.changed.general and not partPlan.changed.overrides, "parts: the rows KitnUI changes")
eq(partPlan.merged.fonts.global, "F", "parts: an unticked General keeps the player's fonts")
eq(partPlan.merged.uiScale, nil, "parts: and applies no scale")
eq(partPlan.merged.addons[F].x, 5, "parts: the ticked row takes KitnUI's change")
eq(partPlan.byRow[F], 1, "parts: the ticked row's replaced count")
local partText = ns.EUIConfirmText(partPlan)
check(partText:find(F .. ": 1 of yours replaced", 1, true), "parts: the confirm names the ticked row's replaced changes", partText)
check(not partText:find("General:", 1, true), "parts: an unticked row has no confirm line", partText)
eq(ns.EUISkippedNote(partPlan), "Skipped: General -- take them any time from /kitn install, EllesmereUI > Modules.",
    "parts: the skipped note")

calls = {}
local partOk, partErr = ns.EUIApplyUpdate(partPlan)
eq(partOk, true, "parts: the update applies", partErr)
eq(ns.euiVisitBacked, true, "visit: the first change backs the visit")
eq(ns.db.addonVersions.EllesmereUI, SHIPPED, "parts: the stamp moves")
eq(ns.db.euiRowAt and ns.db.euiRowAt.general and ns.db.euiRowAt.general.version, "2026.08.22",
    "parts: the skipped row stays at the old version")
eq(ns.db.euiBases and ns.db.euiBases["2026.08.22"], O_STR, "parts: with its string")
eq(ns.db.euiUpdateReport.skipped[1], "General", "parts: the report names the skipped row")
eq(ns.db.euiUpdateReport.byRow[F], 1, "parts: and the replaced count per row")
eq(ns.EUIUpdateState(), "current", "parts: the page reads current")

---------------------------------------------------------------------------------
-- The decode chain, then take the skipped row through the scratch path
---------------------------------------------------------------------------------

local decodedStrings = {}
local realAsync = E.DecodeImportStringAsync
E.DecodeImportStringAsync = function(s, onDone)
    decodedStrings[#decodedStrings + 1] = s
    return realAsync(s, onDone)
end
ns.EUIStartDecodes()
E.DecodeImportStringAsync = realAsync
eq(#decodedStrings, 2, "decodes: each distinct string is decoded once")
check(ns.EUIDecodeCache.N == ns.EUIDecodeCache.O, "decodes: a shipped string equal to the base is not decoded again")
eq(ns.EUIDecodeCache.byVersion["2026.08.22"] and ns.EUIDecodeCache.byVersion["2026.08.22"].data.addons[F].x, 1,
    "decodes: an older base lands under its version")

local moved = {}
ns.EUIMoveProfileRecords = function(from, to) moved[#moved + 1] = from .. ">" .. to end
local scratchDeletedAfterMove
local realDelete = E.DeleteProfile
E.DeleteProfile = function(name)
    if name == ns.EUIScratchName then scratchDeletedAfterMove = #moved > 0 end
    return realDelete(name)
end
db.profileKeybinds.KitnUI = "F5"
local takePlan, takeWhy = ns.EUIPrepareUpdate({ general = true })
check(takePlan ~= nil, "take: a plan is produced", takeWhy)
eq(takePlan.kind, "take", "take: a current stamp takes skipped rows")
eq(takePlan.scratch, true, "visit: a later change in the visit takes the scratch path")
eq(takePlan.merged.fonts.global, "G", "take: the waiting row takes KitnUI's change from its own base")
local takeText = ns.EUIConfirmText(takePlan)
check(not takeText:find("Your previous backup will be replaced.", 1, true), "visit: the scratch path replaces no backup", takeText)
check(takeText:find("are removed; set them again in EllesmereUI", 1, true), "visit: the scratch path warns the keybind is removed", takeText)
check(takeText:find(ns.EUI_UPDATE_TEXT.restoreEarlier, 1, true), "visit: the take promises the backup taken earlier in the visit", takeText)
local backupProfile, backupRec = db.profiles[ns.EUIBackupName], ns.db.euiBackup
calls = {}
local takeOk, takeErr = ns.EUIApplyUpdate(takePlan)
E.DeleteProfile = realDelete
ns.EUIMoveProfileRecords = nil
eq(takeOk, true, "take: applies", takeErr)
eq(ns.db.euiRowAt, nil, "take: the taken row is cleared")
eq(ns.db.euiBases, nil, "take: and its string pruned")
eq(ns.db.addonVersions.EllesmereUI, SHIPPED, "take: the stamp is unchanged")
eq(calls.complete, nil, "take: CompleteSetup does not run")
eq(db.profiles[ns.EUIScratchName], nil, "visit: the scratch profile is deleted")
check(db.profiles[ns.EUIBackupName] == backupProfile, "visit: the visit's backup profile is kept")
check(ns.db.euiBackup == backupRec, "visit: and its record")
eq(moved[1], ns.EUIScratchName .. ">KitnUI", "visit: the notes move back to the new profile")
eq(scratchDeletedAfterMove, true, "visit: before the scratch profile is deleted")
eq(db.activeProfile, "KitnUI", "visit: KitnUI is active")

freshInstall()
ns.EUIStartDecodes()
local noneA, noneWhyA = ns.EUIPrepareUpdate({})
eq(noneA, nil, "parts: nothing ticked refuses")
eq(noneWhyA, "Tick at least one part first.", "parts: with the tick line")
local noneB, noneWhyB = ns.EUIPrepareUpdate({ overrides = true })
eq(noneB, nil, "parts: a ticked row with no change is nothing ticked")
eq(noneWhyB, "Tick at least one part first.", "parts: with the tick line again")

---------------------------------------------------------------------------------
-- Rollbacks on the scratch path
---------------------------------------------------------------------------------

freshInstall()
ns.EUIStartDecodes()
ns.EUIApplyUpdate(ns.EUIPrepareUpdate({ [F] = true }))
ns.EUIStartDecodes()
local rbaPlan = ns.EUIPrepareUpdate({ general = true })
E.importMode = "throw_before"
local rbaOk, rbaErr = ns.EUIApplyUpdate(rbaPlan)
eq(rbaOk, false, "rollback A': reports failure")
check(rbaErr and rbaErr:find("put back", 1, true), "rollback A': the profile is put back", rbaErr)
eq(db.profiles[ns.EUIScratchName], nil, "rollback A': no scratch profile is left")
eq(db.activeProfile, "KitnUI", "rollback A': KitnUI is active")
check(db.profiles[ns.EUIBackupName] ~= nil and ns.db.euiBackup ~= nil, "rollback A': the visit's backup stands")
check(ns.db.euiRowAt and ns.db.euiRowAt.general, "rollback A': the record is untouched")

freshInstall()
db.specProfiles[72] = "KitnUI"
ns.EUIStartDecodes()
ns.EUIApplyUpdate(ns.EUIPrepareUpdate({ [F] = true }))
ns.EUIStartDecodes()
local rbbPlan = ns.EUIPrepareUpdate({ general = true })
E.importMode = "spec_locked"
E.switchFails = true
local rbbOk, rbbErr = ns.EUIApplyUpdate(rbbPlan)
eq(rbbOk, false, "rollback B': reports failure")
check(rbbErr and rbbErr:find("Could not switch to the updated profile", 1, true), "rollback B': names the switch", rbbErr)
eq(db.profiles[ns.EUIScratchName], nil, "rollback B': no scratch profile is left")
eq(db.activeProfile, "KitnUI", "rollback B': KitnUI is active")
eq(db.specProfiles[72], "KitnUI", "rollback B': the assignments are re-pointed")
eq(db.ppUIScale, 0.9, "rollback B': the scale the import wrote is put back")
check(db.profiles[ns.EUIBackupName] ~= nil and ns.db.euiBackup ~= nil, "rollback B': the visit's backup stands")

freshInstall()
ns.EUIStartDecodes()
ns.EUIApplyUpdate(ns.EUIPrepareUpdate({ [F] = true }))
db.profiles[ns.EUIScratchName] = { mine = true }
ns.EUIStartDecodes()
local ownOk, ownErr = ns.EUIApplyUpdate(ns.EUIPrepareUpdate({ general = true }))
eq(ownOk, true, "scratch: a later change applies beside a profile already holding the scratch name", ownErr)
eq(db.profiles[ns.EUIScratchName] and db.profiles[ns.EUIScratchName].mine, true, "scratch: that profile is left alone")
eq(db.profiles[ns.EUIScratchName .. " 2"], nil, "scratch: and the numbered scratch profile is deleted after")

freshInstall()
ns.EUIStartDecodes()
ns.EUIApplyUpdate(ns.EUIPrepareUpdate({ [F] = true }))
ns.EUIStartDecodes()
local stuckPlan = ns.EUIPrepareUpdate({ general = true })
E.renameFails = true
calls = {}
local stuckOk, stuckErr = ns.EUIApplyUpdate(stuckPlan)
E.renameFails = nil
eq(stuckOk, false, "scratch: a rename that fails stops the change")
eq(stuckErr, "Could not move your profile aside for the update. Nothing was imported.", "scratch: with its own line, not the backup's")
eq(calls.import, nil, "scratch: and nothing is imported")

---------------------------------------------------------------------------------
-- Restore puts the record back and ends the visit's backing
---------------------------------------------------------------------------------

freshInstall()
ns.db.euiRowAt = { general = { version = "2026.08.01", kitn = "k" } }
ns.db.euiBases = { ["2026.08.01"] = O_STR }
ns.EUIStartDecodes()
ns.EUIApplyUpdate(ns.EUIPrepareUpdate())
eq(ns.db.euiRowAt, nil, "record: a full update clears it")
local restoredOk, restoredErr = ns.EUIRestorePrevious()
eq(restoredOk, true, "restore: succeeds after a visit", restoredErr)
eq(ns.db.euiRowAt and ns.db.euiRowAt.general and ns.db.euiRowAt.general.version, "2026.08.01", "restore: the record from before the visit is back")
eq(ns.db.euiBases and ns.db.euiBases["2026.08.01"], O_STR, "restore: with its strings")
eq(ns.euiVisitBacked, false, "restore: the next change takes a fresh backup")

---------------------------------------------------------------------------------
-- A part reset
---------------------------------------------------------------------------------

local ctx = { defaults = {}, held = {}, unlock = {} }
freshInstall()
ns.EUIStartDecodes()
local resetPlan, resetWhy = ns.EUIPrepareReset(F, ctx)
check(resetPlan ~= nil, "reset: a plan is produced", resetWhy)
eq(resetPlan.kind, "reset", "reset: the kind")
eq(resetPlan.merged.addons[F].x, 5, "reset: the row is KitnUI's")
eq(resetPlan.merged.addons[F].y, 2, "reset: the player's change in the row is replaced")
eq(resetPlan.merged.fonts.global, "F", "reset: another row stays the player's")
eq(resetPlan.yours, 1, "reset: the player's changes to the row are counted")
eq(resetPlan.captured, false, "reset: no Spec Overrides capture the row")
eq(#resetPlan.splits, 0, "reset: no split link")
local resetText = ns.EUIResetText(resetPlan)
check(resetText:find(F .. " goes back to KitnUI's version. Your 1 change to " .. F .. " will be replaced. Your other parts are not touched.", 1, true),
    "reset: the confirm's first line", resetText)
check(rawResetText(resetPlan):find("|cffE6B24CYour 1 change to " .. F .. " will be replaced.|r", 1, true),
    "reset: the count sentence is amber")
check(resetText:find("Restore previous puts back your profile as it is now.", 1, true), "reset: the visit's first change promises the profile as it is now", resetText)
check(not resetText:find("before this visit", 1, true), "reset: never the profile from before the visit, which a full reset may have replaced", resetText)
check(not resetText:find("Spec Overrides also hold", 1, true), "reset: no capture line", resetText)
calls = {}
local resetOk, resetErr = ns.EUIApplyUpdate(resetPlan)
eq(resetOk, true, "reset: applies", resetErr)
eq(db.profiles.KitnUI.addons[F].y, 2, "reset: the stored profile has KitnUI's row")
eq(ns.db.addonVersions.EllesmereUI, "2026.08.22", "reset: the stamp is unchanged")
eq(calls.complete, nil, "reset: CompleteSetup does not run")
eq(ns.db.euiRowAt and ns.db.euiRowAt[F] and ns.db.euiRowAt[F].version, SHIPPED, "reset: a row reset ahead of the stamp stands at the shipped version")
eq(ns.db.euiBases and ns.db.euiBases[SHIPPED], N_STR, "reset: with the shipped string")
eq(ns.EUIUpdateToast(resetPlan), F .. " reset to KitnUI's version.", "reset: the toast")
ns.EUIStartDecodes()
local laterReset = ns.EUIPrepareReset("general", ctx)
local laterText = laterReset and ns.EUIResetText(laterReset) or ""
check(laterText:find("Restore previous puts back the backup taken earlier in this visit, undoing every change since then.", 1, true),
    "reset: a later change in the visit promises the earlier backup", laterText)

freshInstall()
db.profiles.KitnUI.specOverrides = { { values = { default = { [F .. "\31x"] = 3 } } } }
ns.EUIStartDecodes()
local capPlan = ns.EUIPrepareReset(F, ctx)
eq(capPlan and capPlan.captured, true, "reset: a captured row is noticed")
check(capPlan and ns.EUIResetText(capPlan):find("Your Spec Overrides also hold settings for " .. F .. "; they apply again when you change spec.", 1, true),
    "reset: and named in the confirm")

-- A reset imports the whole profile, so the final layout filter runs over the
-- parts it leaves alone too: a link removed there is named, as an update names it.
freshInstall()
db.profiles.KitnUI.addons.Quickdraw = { shown = true }
db.profiles.KitnUI.unlockLayout.anchors = { QD_Bar = { target = "UIParent" } }
db.profiles.KitnUI.unlockLayoutMeta = { keyToFolder = { QD_Bar = "Quickdraw" } }
ns.EUIStartDecodes()
local linkReset, linkResetWhy = ns.EUIPrepareReset(F, ctx)
check(linkReset ~= nil, "reset: a plan is produced beside a link the filter removes", linkResetWhy)
eq(linkReset and linkReset.warnLinks, true, "reset: the removed link is noticed")
check(linkReset and ns.EUIResetText(linkReset):find(ns.EUI_UPDATE_TEXT.links, 1, true),
    "reset: the removed link is named in the confirm")

freshInstall()
db.profiles.KitnUI.addons[F].x = 5
ns.EUIStartDecodes()
local equalPlan = ns.EUIPrepareReset(F, ctx)
eq(equalPlan and equalPlan.yours, 1, "reset: a change already equal to KitnUI's value is not counted as replaced")

-- Without a shipped version the list still shows, but a part reset has no
-- version to record the part at, so it refuses before anything imports.
freshInstall()
ns.EUIStartDecodes()
local realShipped = ns.GetAddonDataVersion
ns.GetAddonDataVersion = function() return nil end
local noVerPlan, noVerWhy = ns.EUIPrepareReset(F, ctx)
ns.GetAddonDataVersion = realShipped
eq(noVerPlan, nil, "reset: without a shipped version it refuses")
eq(noVerWhy, "EllesmereUI import failed", "reset: with the import line")
eq(db.profiles[ns.EUIBackupName], nil, "reset: and nothing is backed up or imported")

-- A take would clear the part's record without stamping what it installed, so
-- the part would read waiting again against a stamped base that differs from
-- KitnUI's string. It refuses the same way.
freshInstall()
ns.db.euiRowAt = { general = { version = "2026.08.01", kitn = "k" } }
ns.db.euiBases = { ["2026.08.01"] = O_STR }
ns.EUIStartDecodes()
ns.GetAddonDataVersion = function() return nil end
local noVerTake, noVerTakeWhy = ns.EUIPrepareUpdate({ general = true })
ns.GetAddonDataVersion = realShipped
check(ns.data.EllesmereUI ~= ns.db.euiBase, "take: KitnUI's string differs from the stamped base")
eq(noVerTake, nil, "take: without a shipped version it refuses")
eq(noVerTakeWhy, "EllesmereUI import failed", "take: with the import line")
eq(ns.db.euiRowAt and ns.db.euiRowAt.general and ns.db.euiRowAt.general.version, "2026.08.01", "take: and the part still waits")

---------------------------------------------------------------------------------
-- List readiness
---------------------------------------------------------------------------------

freshInstall()
ns.db.addonVersions.EllesmereUI = SHIPPED
eq(ns.EUIListReady(), true, "list: ready on a full EllesmereUI")
local readyMap = E._ADDON_DB_MAP
E._ADDON_DB_MAP = nil
eq(ns.EUIUpdateState(), "current", "list: a current profile stays current without the map")
eq(ns.EUIListReady(), false, "list: but gets no list")
E._ADDON_DB_MAP = { "unreadable", { display = "no folder" } }
eq(ns.EUIListReady(), true, "list: a map whose entries cannot be read is still a map")
ns.EUIStartDecodes()
local unreadInputs = ns.EUIPageInputs()
local unreadIds = {}
for _, row in ipairs(unreadInputs and unreadInputs.rows or {}) do unreadIds[#unreadIds + 1] = row.id end
eq(table.concat(unreadIds, ","), F .. ",general,overrides",
    "list: its rows come from the payload's folders, the always-off one left out")

-- With that map an update still keeps the links of the payload's folders.
freshInstall()
local linkN = base()
linkN.addons[F].x = 5
linkN.unlockLayout.anchors = { UF_Player = { target = "UF_Target" } }
linkN.unlockLayoutMeta = { keyToFolder = { UF_Player = F, UF_Target = F } }
ns.data.EllesmereUI = encode("N-links", payload(linkN))
ns.EUIStartDecodes()
local linkPlan, linkWhy = ns.EUIPrepareUpdate()
ns.data.EllesmereUI = N_STR
check(linkPlan ~= nil, "list: an unreadable map still updates", linkWhy)
check(linkPlan and linkPlan.merged.unlockLayout.anchors.UF_Player ~= nil, "list: and keeps a link of the payload's folders")
check(linkPlan and linkPlan.merged.addons.EllesmereUIActionBars == nil, "list: while a disabled folder is still stripped")

-- One readable entry and one that cannot be read: a folder only the payload
-- names keeps its links too, beside the readable entry's.
freshInstall()
E._ADDON_DB_MAP = { { folder = F }, "unreadable" }
local RBF = "EllesmereUIResourceBars"
local partN = base()
partN.addons[RBF] = { z = 1 }
partN.unlockLayout.anchors = { UF_Player = { target = "UF_Target" }, ERB_Health = { target = "ERB_Power" } }
partN.unlockLayoutMeta = { keyToFolder = { UF_Player = F, UF_Target = F, ERB_Health = RBF, ERB_Power = RBF } }
ns.data.EllesmereUI = encode("N-partial", payload(partN))
ns.EUIStartDecodes()
local partMapPlan, partMapWhy = ns.EUIPrepareUpdate()
ns.data.EllesmereUI = N_STR
check(partMapPlan ~= nil, "list: a partly unreadable map still updates", partMapWhy)
check(partMapPlan and partMapPlan.merged.unlockLayout.anchors.ERB_Health ~= nil,
    "list: and keeps a link of a folder only the payload names")
check(partMapPlan and partMapPlan.merged.unlockLayout.anchors.UF_Player ~= nil,
    "list: beside a link of the readable entry's folder")
check(partMapPlan and partMapPlan.merged.addons.EllesmereUIActionBars == nil,
    "list: while a disabled folder is still stripped")
E._ADDON_DB_MAP = readyMap

---------------------------------------------------------------------------------
-- The settled record through the flow
---------------------------------------------------------------------------------

do
    -- An update installs only the parts it ticks: the others keep their
    -- snapshot, although it runs CompleteSetup.
    freshInstall()
    ns.db.euiSettled = { [1] = { s = O_STR, held = {} } }
    ns.db.euiSettledAt = { ["*"] = 1, overrides = false }
    ns.db.euiSettlePending = { overrides = true }
    ns.EUIStartDecodes()
    E.live = { addons = { [F] = { x = 7, y = 9 }, EllesmereUIActionBars = { bars = 3 } } }
    local snOk, snErr = ns.EUIApplyUpdate(ns.EUIPrepareUpdate({ [F] = true }))
    eq(snOk, true, "settle: a ticked update applies", snErr)
    eq(calls.complete, 1, "settle: the update ran CompleteSetup")
    local snAt = ns.db.euiSettledAt or {}
    eq(snAt["*"], 1, "settle: an update keeps the snapshot of the parts it does not tick")
    eq(snAt[F], false, "settle: the ticked part has none until it settles")
    eq(snAt.overrides, false, "settle: nor has a part already waiting")
    eq(ns.db.euiSettled and ns.db.euiSettled[1] and ns.db.euiSettled[1].s, O_STR, "settle: the kept snapshot stays")
    local snPending = ns.db.euiSettlePending or {}
    check(snPending[F] and snPending.overrides and not snPending["*"],
        "settle: the ticked part waits beside the one already waiting")
    local snRec = ns.db.euiBackup or {}
    check(snRec.euiSettledAt and snRec.euiSettledAt["*"] == 1 and snRec.euiSettledAt[F] == nil,
        "settle: the backup holds the pointers from before the update")
    eq(snRec.euiSettled and snRec.euiSettled[1] and snRec.euiSettled[1].s, O_STR, "settle: with the snapshot they name")
    check(snRec.euiSettlePending and snRec.euiSettlePending.overrides, "settle: and what was waiting")

    -- Restore puts the record back, and nothing is due until the next login.
    ns.euiSettleDue = { overrides = true }
    local snRestored, snRestoreErr = ns.EUIRestorePrevious()
    eq(snRestored, true, "settle: restore succeeds", snRestoreErr)
    snAt = ns.db.euiSettledAt or {}
    check(snAt["*"] == 1 and snAt[F] == nil and snAt.overrides == false, "settle: restore puts the pointers back")
    check(ns.db.euiSettlePending and ns.db.euiSettlePending.overrides and not ns.db.euiSettlePending[F],
        "settle: restore puts the waiting set back")
    check(type(ns.euiSettleDue) == "table" and next(ns.euiSettleDue) == nil, "settle: restore leaves nothing due this session")

    -- A take marks the part it takes.
    freshInstall({ stamp = SHIPPED })
    ns.db.euiRowAt = { general = { version = "2026.08.22", kitn = "k" } }
    ns.db.euiBases = { ["2026.08.22"] = O_STR }
    ns.db.euiSettled = { [1] = { s = O_STR, held = {} } }
    ns.db.euiSettledAt = { ["*"] = 1 }
    ns.EUIStartDecodes()
    local snTake, snTakeWhy = ns.EUIPrepareUpdate({ general = true })
    eq(snTake and snTake.kind, "take", "settle: a take", snTakeWhy)
    if snTake then ns.EUIApplyUpdate(snTake) end
    snAt = ns.db.euiSettledAt or {}
    check(snAt.general == false and snAt["*"] == 1, "settle: a take marks the part it takes and keeps the others' snapshot")
    check(ns.db.euiSettlePending and ns.db.euiSettlePending.general, "settle: the taken part waits for the next session")

    -- A part reset marks its part, on a profile from before snapshots too.
    freshInstall()
    ns.EUIStartDecodes()
    local snReset = ns.EUIPrepareReset(F, ctx)
    if snReset then ns.EUIApplyUpdate(snReset) end
    eq(ns.db.euiSettledAt and ns.db.euiSettledAt[F], false, "settle: a part reset marks its part")
    check(ns.db.euiSettlePending and ns.db.euiSettlePending[F] and not ns.db.euiSettlePending["*"],
        "settle: and only its part waits")
end

---------------------------------------------------------------------------------
-- The settled snapshot in the Modules read
---------------------------------------------------------------------------------

do
    -- The profile as it settled after its install: the player's own y, and a
    -- font EllesmereUI rewrote while it settled.
    local snData = base()
    snData.addons[F].y = 9
    snData.fonts.global = "Live"
    local SN_STR = encode("settled-S", payload(snData))
    local function snInstall(held)
        freshInstall()
        ns.db.euiSettled = { [1] = { s = SN_STR, held = held or {} } }
        ns.db.euiSettledAt = { ["*"] = 1 }
        ns.EUIStartDecodes()
        E.live = { fonts = { global = "Live" } }
    end
    -- "Your copy" for one part, walked as the Modules page walks it.
    local function snYours(side, id)
        if not side then return nil end
        local snCtx = ns.EUIPlayerContext()
        local snHeld = ns.EUISettledHeld and ns.EUISettledHeld(snCtx.held) or snCtx.held
        local snWalker = ns.EUIRowDiff(side.S or side.O or side.N, side.P, side.rows, side.keyToFolder, {
            player = true, noBase = side.O == nil, missing = side.missing, fallback = side.N,
            held = snHeld, defaults = snCtx.defaults, unlock = snCtx.unlock,
        })
        snWalker:Step(math.huge)
        local entry = snWalker.result[id]
        return entry and entry.count or 0
    end

    snInstall()
    local snSide, snWhy = ns.EUIReadPlayer()
    check(snSide ~= nil, "settled: the read succeeds", snWhy)
    eq(snYours(snSide, F), 0, "settled: a part as it settled holds no change of the player's")
    eq(snYours(snSide, "general"), 0, "settled: nor does a font EllesmereUI rewrote while it settled")
    eq(snSide and snSide.settledRows, nil, "settled: the read carries no list of settled parts")
    E.live = { fonts = { global = "Mine" } }
    eq(snYours(ns.EUIReadPlayer(), "general"), 1, "settled: a change made after it counts")

    snInstall({ ["fonts.global"] = true })
    E.live = { fonts = { global = "Mine" } }
    local snHeldNow = ns.EUIPlayerContext().held
    eq(ns.EUISettledHeld and ns.EUISettledHeld(snHeldNow)["fonts.global"], true,
        "settled: a path a switch held at the capture is held for Your copy")
    eq(snHeldNow["fonts.global"], nil, "settled: but not in the context a Reset uses")
    eq(snYours(ns.EUIReadPlayer(), "general"), 0, "settled: so a value a switch held then is not counted")

    -- The confirms stay cautious: a click reads no snapshot.
    snInstall()
    local snPlan, snPlanWhy = ns.EUIPrepareUpdate()
    check(snPlan ~= nil, "settled: an update plan is produced", snPlanWhy)
    if snPlan then
        eq(snPlan.inputs.S, nil, "settled: a click's inputs carry no composite")
        eq(#snPlan.report.conflicts, 1, "settled: the confirm counts a value EllesmereUI rewrote as the player's")
        local snText = ns.EUIConfirmText(snPlan)
        check(snText:find("General: 1 of yours replaced", 1, true), "settled: in the confirm's part line", snText)
        check(snText:find("1 of your changes is replaced", 1, true), "settled: and its total", snText)
        eq(ns.EUIUpdateToast(snPlan), "Profile updated. 1 of your changes was replaced.", "settled: and the toast")
    end
    local snReset = ns.EUIPrepareReset("general", ctx)
    eq(snReset and snReset.yours, 1, "settled: a Reset counts from KitnUI's string")

    -- Only the Modules page's decodes take in the snapshot, and once.
    freshInstall()
    ns.db.euiSettled = { [1] = { s = SN_STR, held = {} } }
    ns.db.euiSettledAt = { ["*"] = 1 }
    local snDecoded = {}
    local snAsync = E.DecodeImportStringAsync
    E.DecodeImportStringAsync = function(s, onDone)
        snDecoded[#snDecoded + 1] = s
        return snAsync(s, onDone)
    end
    ns.EUIStartDecodes()
    eq(#snDecoded, 2, "settled: the standard page and the updater list decode no snapshot")
    snDecoded = {}
    ns.EUIListReadsSettled = function() return true end
    ns.EUIStartDecodes()
    eq(#snDecoded, 3, "settled: the Modules page's decodes take it in")
    check(ns.EUIDecodeCache.bySettled and ns.EUIDecodeCache.bySettled[1], "settled: under its id")
    snDecoded = {}
    ns.db.euiSettled[1].s = O_STR
    ns.EUIStartDecodes()
    eq(#snDecoded, 2, "settled: a snapshot equal to a base is not decoded again")
    ns.EUIListReadsSettled = nil

    -- The timed capture records after the page's decodes landed.
    freshInstall()
    ns.db.euiSettlePending = { ["*"] = true }
    ns.euiSettleDue, ns.euiSettleOpen = { ["*"] = true }, true
    ns.EUIStartDecodes()
    eq(ns.EUISettleCapture(), true, "settled: the capture records after the decodes landed")
    eq(ns.db.euiSettledAt and ns.db.euiSettledAt["*"], 1, "settled: for every part")
    snDecoded = {}
    local snLate, snLateWhy = ns.EUIReadPlayer()
    check(snLate ~= nil, "settled: the read after it goes ahead", snLateWhy)
    check(snLate and snLate.S and snLate.S ~= snLate.O, "settled: and composes from the snapshot the decodes missed")
    eq(snYours(snLate, F), 0, "settled: which counts nothing of the player's")
    eq(#snDecoded, 0, "settled: decoded in the read's own frame, not by the chain")

    -- A change from an earlier session, due its snapshot.
    freshInstall()
    ns.db.euiSettlePending = { ["*"] = true }
    ns.euiSettleDue, ns.euiSettleOpen = { ["*"] = true }, false
    ns.EUIStartDecodes()
    local snEarly, snEarlyWhy = ns.EUIReadPlayer()
    check(snEarly == nil and snEarlyWhy == "Try again in a moment.", "settled: before the settle timer the read waits", snEarlyWhy)
    eq(calls.export, nil, "settled: and exports nothing")
    check(ns.EUIPrepareUpdate() ~= nil, "settled: an update does not wait")
    check(ns.EUIPrepareReset(F, ctx) ~= nil, "settled: nor does a Reset")
    ns.euiSettleOpen = true
    snEarly, snEarlyWhy = ns.EUIReadPlayer()
    check(snEarly ~= nil, "settled: after the timer, with the capture refused, the read goes ahead", snEarlyWhy)
    eq(ns.db.euiSettled, nil, "settled: and records nothing")
    ns.euiSettleDue, ns.euiSettleOpen = nil, nil
    E.DecodeImportStringAsync = snAsync
end

---------------------------------------------------------------------------------
-- A decoder that keeps its callbacks keeps no decoded payload
---------------------------------------------------------------------------------

do
    -- EllesmereUI's driver keeps its last callback after the run ends; this
    -- stub keeps every one it is handed.
    local keptCallbacks = {}
    local keepAsync = E.DecodeImportStringAsync
    E.DecodeImportStringAsync = function(s, onDone)
        keptCallbacks[#keptCallbacks + 1] = onDone
        return keepAsync(s, onDone)
    end
    -- A weak-keyed watch empties once a full collection finds nothing else
    -- that reaches the payload.
    local function watch(p)
        local w = setmetatable({}, { __mode = "k" })
        if p then w[p] = true end
        return w
    end
    local function released(w)
        collectgarbage("collect")
        collectgarbage("collect")
        return next(w) == nil
    end

    freshInstall()
    ns.EUIStartDecodes()
    check(ns.EUIDecodesReady() and ns.EUIDecodeCache.O ~= nil, "release: the chain lands")
    local landedWatch = watch(ns.EUIDecodeCache.O)
    ns.EUICancelDecodes()
    eq(released(landedWatch), true, "release: a landed chain's payload goes with the cache, though the decoder keeps its callbacks")

    freshInstall()
    E.asyncMode = "deferred"
    ns.EUIStartDecodes()
    E.FirePending()
    check(ns.EUIDecodeCache.O ~= nil and not ns.EUIDecodesReady(), "release: the chain is half way")
    local halfWatch = watch(ns.EUIDecodeCache.O)
    ns.EUICancelDecodes()
    eq(released(halfWatch), true, "release: a cancelled chain's payload goes, though its next decode is still pending")
    check(#keptCallbacks > 0, "release: the stub kept the callbacks it was handed")

    E.DecodeImportStringAsync = keepAsync
    E.asyncMode, E.pending = "sync", nil
end

---------------------------------------------------------------------------------
-- Per-section color sources
---------------------------------------------------------------------------------

do
    freshInstall({ colors94 = true })
    db.profiles.Other = base()
    db.colorsSectionPullFrom = { class = "KitnUI", power = "Other" }
    db.colorsPullFrom = "Other"
    nData.customColors = { a = 1 }
    ns.EUIStartDecodes()
    local secOk, secErr = ns.EUIApplyUpdate(ns.EUIPrepareUpdate())
    eq(secOk, true, "sections: the update applies", secErr)
    secOk, secErr = ns.EUIRestorePrevious()
    eq(secOk, true, "sections: Restore succeeds", secErr)
    eq(db.colorsSectionPullFrom and db.colorsSectionPullFrom.class, "KitnUI", "sections: Restore puts back a section that pulled from KitnUI")
    eq(db.colorsSectionPullFrom and db.colorsSectionPullFrom.power, "Other", "sections: and one that pulled from another profile")
    eq(db.colorsPullFrom, "Other", "sections: and the shared source")

    -- A record written before the section sources existed keeps the
    -- player's current ones through the delete and the rename.
    freshInstall({ colors94 = true })
    db.profiles.Other = base()
    ns.EUIStartDecodes()
    ns.EUIApplyUpdate(ns.EUIPrepareUpdate())
    ns.db.euiBackup.colorsSectionPullFrom = nil
    db.colorsSectionPullFrom = { class = "KitnUI", power = "Other", classResource = ns.EUIBackupName }
    ns.EUIRestorePrevious()
    local kept = db.colorsSectionPullFrom or {}
    eq(kept.class, "KitnUI", "sections: an older record keeps a current section that pulls from KitnUI")
    eq(kept.power, "Other", "sections: and one that pulls from another profile")
    eq(kept.classResource, "KitnUI", "sections: and one that pulled from the backup follows it to its name")
    nData.customColors = nil

    -- The scratch path: the section follows the profile back to its name
    -- rather than going with the scratch profile's delete.
    freshInstall({ colors94 = true })
    ns.EUIStartDecodes()
    ns.EUIApplyUpdate(ns.EUIPrepareUpdate({ [F] = true }))
    db.colorsSectionPullFrom = { class = "KitnUI" }
    ns.EUIStartDecodes()
    local scrOk, scrErr = ns.EUIApplyUpdate(ns.EUIPrepareUpdate({ general = true }))
    eq(scrOk, true, "sections: a later change of the visit applies", scrErr)
    eq(db.profiles[ns.EUIScratchName], nil, "sections: through the scratch path")
    eq(db.colorsSectionPullFrom.class, "KitnUI", "sections: a section that pulled from KitnUI still does")

    -- spec_locked: the importer points nothing, so the update points every
    -- section that applies to all profiles, its own source or the shared one.
    freshInstall({ colors94 = true })
    db.profiles.Other = base()
    db.specProfiles[71] = "Other"
    db.colorsApplyToAllProfiles = false
    db.colorsSectionApplyAll = { class = true }
    db.colorsSectionPullFrom = { class = "Other" }
    nData.customColors = { a = 1 }
    ns.EUIStartDecodes()
    local lockPlan = ns.EUIPrepareUpdate()
    E.importMode = "spec_locked"
    local lockOk, lockErr = ns.EUIApplyUpdate(lockPlan)
    eq(lockOk, true, "sections: spec_locked applies", lockErr)
    eq(db.colorsSectionPullFrom.class, "KitnUI", "sections: spec_locked points a section that applies to all")
    eq(db.colorsPullFrom, nil, "sections: and leaves the shared source when no section reads it")
    nData.customColors = nil
end


print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
