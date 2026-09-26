-- ╔══════════════════════════════════════════════════════════════╗
-- ║  MergeInputs.lua                                             ║
-- ║  Purpose: What goes into the three-way merge and what comes  ║
-- ║           out of it: the folder strip, the stored-folder     ║
-- ║           supplement, the layout key resolver, the final     ║
-- ║           endpoint filter, the activation prediction and the ║
-- ║           confirm's warnings. Pure; EllesmereUI's own        ║
-- ║           functions arrive as arguments.                     ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

local function isTable(v) return type(v) == "table" end

ns.EUIBackupName = "KitnUI (before update)"

-- The partition ImportProfileSilent makes: a folder is stripped when it, or
-- the addon hosting it, is in the disable list. Returns the kept set, the
-- stripped set, and whether the CDM spell store goes with them.
function ns.EUIStripSets(map, disableList)
    local disable = {}
    for _, folder in ipairs(disableList or {}) do disable[folder] = true end
    local keep, strip = {}, {}
    for _, entry in ipairs(isTable(map) and map or {}) do
        if isTable(entry) and type(entry.folder) == "string" then
            if disable[entry.folder] or (entry.hostAddon and disable[entry.hostAddon]) then
                strip[entry.folder] = true
            else
                keep[entry.folder] = true
            end
        end
    end
    return keep, strip, disable["EllesmereUICooldownManager"] == true
end

-- Removes the stripped folders and, when CDM is stripped, the spell store.
-- The layout is left alone: it is filtered once, after the merge.
function ns.EUIStripFolders(data, strip, stripCDM)
    if not isTable(data) then return end
    if isTable(data.addons) then
        for folder in pairs(strip) do data.addons[folder] = nil end
    end
    if stripCDM then data.cdmSpells = nil end
end

-- The export skips modules that are not loaded; their stored tables are
-- copied in so a folder the player has settings for is never read as absent.
function ns.EUISupplementP(pdata, storedAddons)
    if not isTable(pdata) or not isTable(storedAddons) then return end
    if not isTable(pdata.addons) then pdata.addons = {} end
    for folder, t in pairs(storedAddons) do
        if pdata.addons[folder] == nil and isTable(t) then
            pdata.addons[folder] = ns.EUIDeepCopy(t)
        end
    end
end

-- N's key-to-folder meta with P's overlaid; both come from the same registry.
function ns.EUIOverlayMeta(nMeta, pMeta)
    local out = {}
    local function take(meta)
        local k2f = isTable(meta) and meta.keyToFolder
        if not isTable(k2f) then return end
        for key, folder in pairs(k2f) do out[key] = folder end
    end
    take(nMeta)
    take(pMeta)
    return out
end

-- Child key -> owning folder for every layout key on any side, through the
-- importer's own resolver so an unmapped key classifies the way it will at
-- import. `resolve` is the game addon's `BuildImportKeyToFolder`.
function ns.EUILayoutKeyToFolder(sides, metaK2F, resolve)
    local union = { anchors = {}, widthMatch = {}, heightMatch = {} }
    for _, d in pairs(sides) do
        local ul = isTable(d) and d.unlockLayout
        if isTable(ul) then
            for _, map in ipairs(ns.EUI_LAYOUT_MAPS) do
                if isTable(ul[map]) then
                    for child, v in pairs(ul[map]) do
                        if union[map][child] == nil then union[map][child] = v end
                    end
                end
            end
        end
    end
    return resolve(union, metaK2F) or {}
end

-- The shipped endpoint filter, applied once to the merged layout with the
-- complete surviving-folder set. Every conflict under a removed entry is
-- struck, an extra's with its link's. Returns the removed entries as a set
-- of "map.child" keys, or nil when either resolver answers with something
-- other than a table.
function ns.EUIFinalLayoutFilter(merged, report, metaK2F, keepSet, api)
    local ul = merged.unlockLayout
    if not isTable(ul) then
        merged.unlockLayoutMeta = nil
        return {}
    end
    local k2f = api.BuildImportKeyToFolder(ul, metaK2F)
    if not isTable(k2f) then return nil end
    local out = api.FilterLayoutToFolders(ul, keepSet, k2f)
    if not isTable(out) then return nil end
    local removed = {}
    for _, map in ipairs(ns.EUI_LAYOUT_MAPS) do
        if isTable(ul[map]) then
            for child in pairs(ul[map]) do
                if not (isTable(out[map]) and out[map][child] ~= nil) then
                    removed[map .. "." .. tostring(child)] = true
                end
            end
        end
    end
    local linkMapOf = {}
    for map, xmap in pairs(ns.EUI_MATCH_EXTRAS) do linkMapOf[xmap] = map end
    local kept = {}
    for _, path in ipairs(report.conflicts) do
        local map, child = path:match("^unlockLayout%.([^.]+)%.(.+)$")
        if not (map and removed[(linkMapOf[map] or map) .. "." .. child]) then kept[#kept + 1] = path end
    end
    report.conflicts = kept
    merged.unlockLayout = out
    merged.unlockLayoutMeta = nil
    return removed
end

-- The importer's activation gate, evaluated against the assignment state it
-- will see: the previous backup deleted (its assignments cleared) and the
-- profile's own assignments re-pointed at the new profile.
function ns.EUIWillLock(specID, specProfiles, backupExists)
    if not specID then return false end
    local assignedNow = isTable(specProfiles) and specProfiles[specID] or nil
    if backupExists and assignedNow == ns.EUIBackupName then assignedNow = nil end
    return assignedNow ~= nil and assignedNow ~= ns.profileName
end

-- True when a link from an imported child will be removed by either filter:
-- the export's (a stored entry P lacks) or the final one (an entry removed
-- after the merge). Only when the payload carries a layout at all, because
-- otherwise the importer keeps the backup's layout whole.
function ns.EUILinkWarning(merged, storedLayout, exportedLayout, removedByFinal, storedK2F)
    if not isTable(merged.unlockLayout) then return false end
    local addons = isTable(merged.addons) and merged.addons or {}
    local function imported(child)
        local folder = storedK2F[child]
        return folder ~= nil and addons[folder] ~= nil
    end
    for key in pairs(removedByFinal or {}) do
        local child = key:match("^%w+%.(.+)$")
        if child and imported(child) then return true end
    end
    if isTable(storedLayout) then
        for _, map in ipairs(ns.EUI_LAYOUT_MAPS) do
            local stored = storedLayout[map]
            local exported = isTable(exportedLayout) and exportedLayout[map]
            if isTable(stored) then
                for child in pairs(stored) do
                    if not (isTable(exported) and exported[child] ~= nil) and imported(child) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- True when any module's sync group names both profiles.
function ns.EUISharesSyncGroup(syncedModules, a, b)
    if not isTable(syncedModules) then return false end
    for _, targets in pairs(syncedModules) do
        if isTable(targets) and targets[a] and targets[b] then return true end
    end
    return false
end
