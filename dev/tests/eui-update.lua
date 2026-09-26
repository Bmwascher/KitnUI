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
for _, file in ipairs({ "Installer/Merge.lua", "Installer/MergeInputs.lua", "Installer/Update.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", ns)
end

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
    if key == "EllesmereUI" then ns.db.euiBase = ns.data.EllesmereUI end
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
E.RenameProfile = function(old, new)
    bump("rename")
    if E.renameFails then return end
    db.profiles[new] = db.profiles[old]
    db.profiles[old] = nil
    if db.activeProfile == old then db.activeProfile = new end
    for spec, name in pairs(db.specProfiles) do
        if name == old then db.specProfiles[spec] = new end
    end
end
E.DeleteProfile = function(name)
    bump("delete")
    db.profiles[name] = nil
    for spec, n in pairs(db.specProfiles) do
        if n == name then db.specProfiles[spec] = nil end
    end
    if db.colorsPullFrom == name then db.colorsPullFrom = nil end
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
E.FilterLayoutToFolders = function(ul, keepSet, k2f)
    local function endpointOK(key)
        return type(key) == "string" and k2f[key] ~= nil and keepSet[k2f[key]] == true
    end
    local out = { anchors = {}, widthMatch = {}, heightMatch = {}, phantomBounds = {} }
    for child, info in pairs(ul.anchors or {}) do
        if type(info) == "table" and endpointOK(child) and endpointOK(info.target) then out.anchors[child] = info end
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
    if payload.data.customColors and db.colorsApplyToAllProfiles ~= false then db.colorsPullFrom = name end
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
check(text:find("1 of your changes will be replaced", 1, true), "confirm: the count line", text)
check(text:find("KitnUI's version is used", 1, true), "confirm: the promise line")
check(not text:find("previous backup", 1, true), "confirm: no backup line without a backup")
check(not text:find("Spec Overrides", 1, true), "confirm: no override line when no side carries one")

freshInstall({ base = false })
ns.EUIStartDecodes()
plan = ns.EUIPrepareUpdate()
eq(plan.noBase, true, "click: no base plan")
eq(plan.merged.addons[F].y, 2, "click: no base replaces the player's change")
text = ns.EUIConfirmText(plan)
check(text:find("replaces your changes", 1, true), "confirm: the no-base line")

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
    check(ns.EUIConfirmText(moved):find("1 of your changes will be replaced", 1, true),
        "extras: the confirm counts the dropped extra")
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
eq(ns.EUIUpdateToast(plan), "Profile updated. 1 of your changes were replaced.", "apply: the toast counts")
eq(ns.EUIUpdateToast({ report = { conflicts = {} } }), "Profile updated.", "apply: the zero toast")
eq(ns.EUIUpdateState(), "current", "apply: the page reads current")
eq(ns.EUIRestorable(), "restore", "apply: restore is offered")

-- A second update replaces the previous backup.
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

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
