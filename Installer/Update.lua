-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Update.lua                                                  ║
-- ║  Purpose: The EllesmereUI profile update: page state, the    ║
-- ║           two async decodes, the capture-merge-confirm       ║
-- ║           click, the apply with its two rollbacks, and       ║
-- ║           Restore previous. Everything that talks to         ║
-- ║           EllesmereUI lives here; the merge itself does not. ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

local NAME = ns.profileName
local BACKUP = ns.EUIBackupName
local RESOURCE_BARS = "EllesmereUIResourceBars"

local function isTable(v) return type(v) == "table" end
local function E() return _G.EllesmereUI end
local function DB() return _G.EllesmereUIDB end

-- Every sentence the flow shows. The design's sentences are reproduced
-- verbatim; the rest are this file's.
ns.EUI_UPDATE_TEXT = {
    promise = "Update keeps everything you changed and brings in everything KitnUI changed. Where you both changed the same thing, KitnUI's version is used.",
    replaces = "%d of your changes will be replaced because KitnUI changed the same things.",
    noBase = "KitnUI has no record of the profile you installed, so this update replaces your changes.",
    backupReplaced = "Your previous backup will be replaced.",
    overridesKept = "Your Spec Overrides are kept.",
    overridesTaken = "KitnUI's Spec Overrides replace yours. KitnUI's saved layouts may also replace bar and element positions, sizes and links you changed.",
    links = "Links from updated bars to modules KitnUI disables, to modules with no Unlock Mode checkbox, or that EllesmereUI cannot identify will be removed. These are not included in the count.",
    health = "Your custom health bar colour will be reset to the class colour. This is not included in the count.",
    moved = "Your profile keybind and sync-group membership move to the backup. Restore previous brings them back.",
    combat = "Cannot update in combat",
    notActive = "Switch to your KitnUI profile to update it.",
    unlock = "Save or exit Unlock Mode before updating.",
    unlockRestore = "Save or exit Unlock Mode before restoring.",
    establish = "Try again in a moment.",
    readFail = "Could not read your current profile.",
    preparing = "Preparing...",
    importFail = "EllesmereUI import failed",
    switchFail = "Could not switch to the backup.",
    switchFailUpdate = "Could not switch to the updated profile.",
    reloadScale = "Type /reload to put your UI scale back.",
    tailRestore = "Restore previous puts your previous profile back.",
    renameFail = "Could not back up your profile.",
    sync = "Your active profile and the backup share a sync group. Remove one of them from the group first.",
    notRestorable = "Switch to your KitnUI profile first",
    needsNewer = "Update needs a newer EllesmereUI.",
    updated = "Profile updated.",
    updatedReplaced = "Profile updated. %d of your changes were replaced.",
}
local T = ns.EUI_UPDATE_TEXT

---------------------------------------------------------------------------------
-- Base seeding and page state
---------------------------------------------------------------------------------

-- An account that installed the string shipping now has its base for free.
function ns.EUISeedBase()
    if not ns.db or ns.db.euiBase ~= nil then return end
    local stamp = ns.db.addonVersions and ns.db.addonVersions.EllesmereUI
    local shipped = ns.GetAddonDataVersion("EllesmereUI")
    if stamp and shipped and stamp == shipped and type(ns.data.EllesmereUI) == "string" then
        ns.db.euiBase = ns.data.EllesmereUI
    end
end

local REQUIRED = {
    "DecodeImportStringAsync", "DecodeImportString", "ExportProfile", "RenameProfile",
    "DeleteProfile", "ImportProfile", "BuildImportKeyToFolder", "FilterLayoutToFolders",
    "SetProfile",
}

-- EllesmereUI has no setter for a spec's profile, so write its table. Looked up
-- each time: EllesmereUI's options replace the table whole.
local function assignSpec(spec)
    local d = DB()
    if not isTable(d) then return end
    if not isTable(d.specProfiles) then d.specProfiles = {} end
    d.specProfiles[spec] = NAME
end

local function hasRequired(e)
    if not e or not isTable(e._ADDON_DB_MAP) then return false end
    for _, fn in ipairs(REQUIRED) do
        if type(e[fn]) ~= "function" then return false end
    end
    return true
end

-- "none" | "current" | "update" | "stale", plus the one line saying why a
-- stale profile cannot be updated.
function ns.EUIUpdateState()
    if not (ns.db and ns.db.profiles and ns.db.profiles.EllesmereUI) then return "none" end
    local stamp = ns.db.addonVersions and ns.db.addonVersions.EllesmereUI
    local shipped = ns.GetAddonDataVersion("EllesmereUI")
    if not (stamp and shipped and stamp ~= shipped) then return "current" end
    local e, d = E(), DB()
    local profiles = isTable(d) and d.profiles
    if not (isTable(profiles) and profiles[NAME]) then
        return "stale", "Your KitnUI profile is gone. Reset installs it again."
    end
    if d.activeProfile ~= NAME then return "stale", T.notActive end
    if not hasRequired(e) then return "stale", T.needsNewer end
    return "update"
end

-- "restore" when the backup can be put back from here, "switch" when the
-- player must be on their KitnUI profile first, nil when there is no backup.
function ns.EUIRestorable()
    local d = DB()
    local profiles = isTable(d) and d.profiles
    if not (isTable(profiles) and profiles[BACKUP] and ns.db and isTable(ns.db.euiBackup)) then return nil end
    if profiles[NAME] == nil or d.activeProfile == NAME then return "restore" end
    return "switch"
end

---------------------------------------------------------------------------------
-- The two decodes
---------------------------------------------------------------------------------

local cache = { gen = 0 }
ns.EUIDecodeCache = cache

function ns.EUICancelDecodes()
    cache.gen = cache.gen + 1
    if cache.handleO and cache.handleO.Cancel then cache.handleO:Cancel() end
    if cache.handleN and cache.handleN.Cancel then cache.handleN:Cancel() end
    cache.handleO, cache.handleN = nil, nil
    cache.O, cache.N = nil, nil
    cache.failedO, cache.failedN = false, false
    cache.running = false
end

local function decoded(payload)
    return isTable(payload) and isTable(payload.data) and payload or nil
end

-- O from the base, then N from the shipped string, into this cache; a stale
-- generation drops its result. onReady runs once both have finished.
function ns.EUIStartDecodes(onReady)
    ns.EUICancelDecodes()
    local e = E()
    if not (e and e.DecodeImportStringAsync) then return false end
    local gen = cache.gen
    cache.running = true

    local function startN()
        local handle = e.DecodeImportStringAsync(ns.data.EllesmereUI, function(payload)
            if cache.gen ~= gen then return end
            cache.N = decoded(payload)
            cache.failedN = cache.N == nil
            cache.handleN = nil
            cache.running = false
            if onReady then onReady() end
        end)
        if handle and cache.gen == gen and cache.running then cache.handleN = handle end
    end

    local base = ns.db and ns.db.euiBase
    if type(base) ~= "string" then
        cache.failedO = true
        startN()
        return true
    end
    local handle = e.DecodeImportStringAsync(base, function(payload)
        if cache.gen ~= gen then return end
        cache.O = decoded(payload)
        cache.failedO = cache.O == nil
        cache.handleO = nil
        startN()
    end)
    if handle and cache.gen == gen and cache.O == nil and not cache.failedO then cache.handleO = handle end
    return true
end

function ns.EUIDecodesReady()
    return not cache.running and (cache.N ~= nil or cache.failedN)
end

---------------------------------------------------------------------------------
-- The click: capture, merge, describe
---------------------------------------------------------------------------------

function ns.EUICurrentSpecID()
    local index = GetSpecialization and GetSpecialization() or 0
    if not index or index <= 0 then return nil end
    return GetSpecializationInfo(index)
end

local function assignedSpecs()
    local d = DB()
    local out = {}
    if isTable(d) and isTable(d.specProfiles) then
        for specID, name in pairs(d.specProfiles) do
            if name == NAME then out[#out + 1] = specID end
        end
        table.sort(out)
    end
    return out
end

local function willLock()
    local d = DB()
    local profiles = isTable(d) and d.profiles
    return ns.EUIWillLock(ns.EUICurrentSpecID(), isTable(d) and d.specProfiles, profiles and profiles[BACKUP] ~= nil)
end

local function healthResets(lock)
    local e = E()
    return not lock and e and e.IsModuleAddonLoaded and e.IsModuleAddonLoaded(RESOURCE_BARS) == true
end

-- The three refusals every click and every acceptance repeats.
local function refusal()
    if InCombatLockdown() then return T.combat end
    local d = DB()
    if not (isTable(d) and d.activeProfile == NAME) then return T.notActive end
    local e = E()
    if e and e._unlockModeActive then return T.unlock end
    return nil
end

-- Harvest and export the player's profile. The export's side effect, the
-- stored profile freshened from live, is what makes the later rename carry a
-- complete backup; the string is what the caller decodes, or discards.
function ns.EUIBankCurrent()
    local e = E()
    if not e then return nil, T.readFail end
    if e.Conditions_EstablishPending and e.Conditions_EstablishPending() then return nil, T.establish end
    if e.SpecOverrides_HarvestCurrent then e.SpecOverrides_HarvestCurrent() end
    local s = e.ExportProfile(NAME)
    if type(s) ~= "string" then return nil, T.readFail end
    return s
end

function ns.EUICaptureP()
    local s, err = ns.EUIBankCurrent()
    if not s then return nil, err end
    local payload = decoded(E().DecodeImportString(s))
    if not payload then return nil, T.readFail end
    return payload
end

local function movesToBackup()
    local d = DB()
    if not isTable(d) then return false end
    if isTable(d.profileKeybinds) and d.profileKeybinds[NAME] then return true end
    if isTable(d.syncedModules) then
        for _, targets in pairs(d.syncedModules) do
            if isTable(targets) and targets[NAME] then return true end
        end
    end
    return false
end

-- The click's inputs: the player's profile captured now, the two decodes
-- copied, all three folder-stripped, plus what the warnings read. Held on the
-- plan so a recount uses the profile the confirm described.
local function gatherInputs()
    local e, d = E(), DB()
    local P, err = ns.EUICaptureP()
    if not P then return nil, err end

    local stored = d.profiles[NAME]
    ns.EUISupplementP(P.data, isTable(stored) and stored.addons)

    local keep, strip, stripCDM = ns.EUIStripSets(e._ADDON_DB_MAP, ns.GetEUIModuleSet())
    local Od = cache.O and ns.EUIDeepCopy(cache.O.data) or nil
    local Nd = ns.EUIDeepCopy(cache.N.data)
    local Pd = P.data
    ns.EUIStripFolders(Od, strip, stripCDM)
    ns.EUIStripFolders(Nd, strip, stripCDM)
    ns.EUIStripFolders(Pd, strip, stripCDM)

    local metaK2F = ns.EUIOverlayMeta(cache.N.data.unlockLayoutMeta, Pd.unlockLayoutMeta)
    local storedLayout = isTable(stored) and stored.unlockLayout or nil
    return {
        O = Od, N = Nd, P = Pd,
        keep = keep,
        metaK2F = metaK2F,
        keyToFolder = ns.EUILayoutKeyToFolder({ Od, Nd, Pd }, metaK2F, e.BuildImportKeyToFolder),
        storedLayout = storedLayout,
        storedK2F = e.BuildImportKeyToFolder(isTable(storedLayout) and storedLayout or {}, metaK2F) or {},
    }
end

-- The merge over one set of inputs under one activation prediction.
local function buildPlan(inputs, lock)
    local e, d = E(), DB()
    local merged, report = ns.EUIThreeWayMerge(inputs.O, inputs.N, inputs.P, {
        keyToFolder = inputs.keyToFolder,
        healthReset = healthResets(lock),
    })
    local removed = ns.EUIFinalLayoutFilter(merged, report, inputs.metaK2F, inputs.keep, e)
    if not removed then return nil, T.readFail end
    if ns.db and ns.db.devMode then
        for _, path in ipairs(report.conflicts) do print(ns.title .. " conflict: " .. path) end
    end

    local Pd = inputs.P
    local health = Pd.addons and Pd.addons[RESOURCE_BARS] and Pd.addons[RESOURCE_BARS].health
    return {
        inputs = inputs,
        merged = merged,
        report = report,
        willLock = lock,
        noBase = report.noBase,
        warnLinks = ns.EUILinkWarning(merged, inputs.storedLayout, Pd.unlockLayout, removed, inputs.storedK2F),
        warnHealth = isTable(health) and health.customColored == true and healthResets(lock),
        warnMoved = movesToBackup(),
        backupExists = d.profiles[BACKUP] ~= nil,
    }
end

-- The click. Returns a plan the confirm describes and the acceptance applies,
-- or nil and a line.
function ns.EUIPrepareUpdate()
    local why = refusal()
    if why then return nil, why end
    if not ns.EUIDecodesReady() then return nil, T.preparing end
    if cache.failedN then return nil, T.importFail end
    local inputs, err = gatherInputs()
    if not inputs then return nil, err end
    return buildPlan(inputs, willLock())
end

-- The confirm's message, one sentence per line.
function ns.EUIConfirmText(plan)
    local lines = { T.promise }
    if plan.noBase then
        lines[#lines + 1] = T.noBase
    else
        lines[#lines + 1] = T.replaces:format(#plan.report.conflicts)
    end
    if plan.backupExists then lines[#lines + 1] = T.backupReplaced end
    if plan.report.overrideSet == "kitn" then
        lines[#lines + 1] = T.overridesTaken
    elseif plan.report.overrideSet == "player" then
        lines[#lines + 1] = T.overridesKept
    end
    if plan.warnLinks then lines[#lines + 1] = T.links end
    if plan.warnHealth then lines[#lines + 1] = T.health end
    if plan.warnMoved then lines[#lines + 1] = T.moved end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------------
-- The acceptance: backup, import, rollbacks
---------------------------------------------------------------------------------

local function refreshAll()
    local e = E()
    if e and e.RefreshAllAddons then e.RefreshAllAddons() end
end

-- True when the import had changed the scale. EllesmereUI applies the scale
-- only at startup, so the one the import put on screen stays until a reload.
local function restoreScale(rec)
    local d = DB()
    if not (isTable(d) and isTable(rec) and rec.scaleTaken) then return false end
    local changed = d.ppUIScale ~= rec.ppUIScale or d.ppUIScaleAuto ~= rec.ppUIScaleAuto
    d.ppUIScale = rec.ppUIScale
    d.ppUIScaleAuto = rec.ppUIScaleAuto
    return changed
end

local function rolledBack(err, ok, detail, scaled)
    local line = err .. (ok and " Your previous profile was put back." or (" Your previous profile is named " .. BACKUP .. "."))
    if scaled then line = line .. " " .. T.reloadScale end
    return false, line, detail
end

-- Nothing stored: the rename alone moves everything back.
local function rollbackA(err, detail)
    local e, d = E(), DB()
    e.RenameProfile(BACKUP, NAME)
    local ok = d.activeProfile == NAME
    local scaled = restoreScale(ns.db.euiBackup)
    ns.db.euiBackup = nil
    refreshAll()
    return rolledBack(err, ok, detail, scaled)
end

-- Stored without activating and the switch failed: remove the stored profile,
-- put the backup back under its name and its assignments back on it.
local function rollbackB(err, detail)
    local e, d = E(), DB()
    local rec = ns.db.euiBackup
    e.DeleteProfile(NAME)
    e.RenameProfile(BACKUP, NAME)
    local ok = d.activeProfile == NAME
    for _, spec in ipairs(isTable(rec) and rec.assignedSpecs or {}) do
        assignSpec(spec)
    end
    local scaled = restoreScale(rec)
    ns.db.euiBackup = nil
    refreshAll()
    return rolledBack(err, ok, detail, scaled)
end

-- Applies a confirmed plan. Returns true on success; false and a line on a
-- refusal or a failure, plus the importer's own error text when it raised one;
-- "reconfirm" and a new plan when the activation prediction changed while the
-- dialog was open.
function ns.EUIApplyUpdate(plan)
    local why = refusal()
    if why then return false, why end
    local e, d = E(), DB()
    local banked, err = ns.EUIBankCurrent()
    if not banked then return false, err end

    -- A prediction that moved while the dialog was open changes which leaves
    -- count; the recount runs over the inputs the confirm described, so edits
    -- made during the dialog stay out of the update and in the backup.
    local lock = willLock()
    if lock ~= plan.willLock then
        local fresh, reason = buildPlan(plan.inputs, lock)
        if not fresh then return false, reason end
        return "reconfirm", fresh
    end
    local assigned = assignedSpecs()
    plan.merged.assignedSpecs = assigned

    if d.profiles[BACKUP] then e.DeleteProfile(BACKUP) end
    ns.db.euiBackup = {
        version = ns.db.addonVersions and ns.db.addonVersions.EllesmereUI,
        base = ns.db.euiBase,
        assignedSpecs = assigned,
        colorsPullFrom = d.colorsPullFrom or false,
        ppUIScale = d.ppUIScale,
        ppUIScaleAuto = d.ppUIScaleAuto,
        scaleTaken = plan.merged.uiScale ~= nil,
    }
    e.RenameProfile(NAME, BACKUP)
    if not (d.profiles[BACKUP] and d.activeProfile == BACKUP) then
        ns.db.euiBackup = nil
        return false, T.renameFail
    end

    local ok, result, importErr, status = pcall(e.ImportProfile, { version = 3, type = "full", data = plan.merged }, NAME)
    local failed, detail = not ok or not result, nil
    if not ok then
        detail = tostring(result)
    elseif not result then
        detail = importErr
    end
    if failed then
        local line = T.importFail .. "."
        if d.profiles[NAME] == nil then
            return rollbackA(line, detail)
        elseif d.activeProfile ~= NAME then
            return rollbackB(line, detail)
        end
        -- The activation tail threw after the account writes: the merged
        -- profile is active and the backup is intact, so Restore is offered.
        refreshAll()
        return false, line .. " " .. T.tailRestore, detail
    end

    if status == "spec_locked" then
        e.SetProfile(NAME)
        if d.activeProfile ~= NAME then return rollbackB(T.switchFailUpdate) end
        if plan.merged.customColors and d.colorsApplyToAllProfiles ~= false then
            d.colorsPullFrom = NAME
        end
    end

    ns.CompleteSetup("EllesmereUI")
    ns.db.euiUpdateReport = {
        conflicts = plan.report.conflicts,
        kept = plan.report.kept,
        applied = plan.report.applied,
        noBase = plan.report.noBase,
        overrideSet = plan.report.overrideSet,
    }
    ns.euiUpdatedThisSession = ns.db.euiUpdateReport
    refreshAll()
    ns.ApplyEUIModuleSet()
    return true
end

function ns.EUIUpdateToast(plan)
    local n = #plan.report.conflicts
    if n > 0 then return T.updatedReplaced:format(n) end
    return T.updated
end

---------------------------------------------------------------------------------
-- Restore previous
---------------------------------------------------------------------------------

function ns.EUIRestorePrevious()
    if InCombatLockdown() then return false, "Cannot restore in combat" end
    local e, d = E(), DB()
    if not (hasRequired(e) and isTable(d) and isTable(d.profiles)) then return false, T.needsNewer end
    if e._unlockModeActive then return false, T.unlockRestore end
    if ns.EUIRestorable() ~= "restore" then return false, T.notRestorable end
    local rec = ns.db.euiBackup
    local active = d.activeProfile or "Default"
    if active ~= BACKUP and ns.EUISharesSyncGroup(d.syncedModules, active, BACKUP) then
        return false, T.sync
    end
    e.SetProfile(BACKUP)
    if d.activeProfile ~= BACKUP then return false, T.switchFail end
    if d.profiles[NAME] then e.DeleteProfile(NAME) end
    e.RenameProfile(BACKUP, NAME)
    if not (d.profiles[NAME] and d.activeProfile == NAME) then return false, "Could not restore the backup." end
    for _, spec in ipairs(isTable(rec.assignedSpecs) and rec.assignedSpecs or {}) do
        assignSpec(spec)
    end
    d.colorsPullFrom = rec.colorsPullFrom or nil
    if e.ApplyColorsToOUF then e.ApplyColorsToOUF() end
    local scaled = restoreScale(rec)
    ns.db.euiBase = rec.base
    ns.db.addonVersions = ns.db.addonVersions or {}
    ns.db.addonVersions.EllesmereUI = rec.version
    ns.db.euiUpdateReport = nil
    ns.db.euiBackup = nil
    refreshAll()
    ns.ApplyEUIModuleSet()
    return true, scaled and T.reloadScale or nil
end
