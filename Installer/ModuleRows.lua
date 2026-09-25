-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ModuleRows.lua                                              ║
-- ║  Purpose: The EllesmereUI update one part at a time: the     ║
-- ║           parts, which part owns a setting, the composite    ║
-- ║           base, the slice swap, the counting walk and the    ║
-- ║           per-part record. Pure; EllesmereUI's tables        ║
-- ║           arrive as arguments.                               ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

local function isTable(v) return type(v) == "table" end

local CDM = "EllesmereUICooldownManager"
local NAMEPLATES = "EllesmereUINameplates"
local TOP_BAR = "KitnUI_EUI"

local OVERRIDE_KEYS = {}
for _, key in ipairs(ns.EUI_OV_KEYS) do OVERRIDE_KEYS[key] = true end

---------------------------------------------------------------------------------
-- Parts
---------------------------------------------------------------------------------

-- One row per module the shipped payload carries, in EllesmereUI's order, then
-- the Top Bar, General and Spec Overrides. A module KitnUI always switches off
-- is left out; Nameplates stays, marked off, because Plater is the player's
-- choice. A map that cannot be read still lists the payload's folders.
function ns.EUIRows(map, roster, nAddons, disableList)
    nAddons = isTable(nAddons) and nAddons or {}
    local display = {}
    for _, entry in ipairs(isTable(roster) and roster or {}) do
        if isTable(entry) and type(entry.folder) == "string" and type(entry.display) == "string" then
            display[entry.folder] = entry.display
        end
    end
    local disabled = {}
    for _, folder in ipairs(disableList or {}) do disabled[folder] = true end

    local rows, seen = {}, {}
    local function add(folder, fallback)
        if seen[folder] or folder == TOP_BAR or nAddons[folder] == nil then return end
        seen[folder] = true
        if disabled[folder] and folder ~= NAMEPLATES then return end
        rows[#rows + 1] = {
            id = folder,
            label = display[folder] or fallback or folder,
            off = disabled[folder] and "Plater chosen" or nil,
        }
    end
    local named, unreadable = false, false
    for _, entry in ipairs(isTable(map) and map or {}) do
        if isTable(entry) and type(entry.folder) == "string" then
            named = true
            add(entry.folder, type(entry.display) == "string" and entry.display or nil)
        else
            unreadable = true
        end
    end
    -- Only a map that cannot be fully read lends rows to the payload's other
    -- folders: a readable map that leaves a folder out means EllesmereUI does
    -- not know it, and the final filter would drop its links.
    if unreadable or not named then
        local rest = {}
        for folder in pairs(nAddons) do
            if type(folder) == "string" and not seen[folder] and folder ~= TOP_BAR then rest[#rest + 1] = folder end
        end
        table.sort(rest)
        for _, folder in ipairs(rest) do add(folder) end
    end

    if nAddons[TOP_BAR] ~= nil then
        rows[#rows + 1] = { id = TOP_BAR, label = "Top Bar", sub = "KitnUI" }
    end
    rows[#rows + 1] = { id = "general", label = "General", sub = "fonts, colours, scale" }
    rows[#rows + 1] = { id = "overrides", label = "Spec Overrides", sub = "all or nothing" }
    return rows
end

-- The row a merge path belongs to, or nil for the keys the merge decides on
-- its own. A folder row's id is its folder.
function ns.EUIRowOf(path, keyToFolder)
    if path == "Spec Overrides" then return "overrides" end
    if path == "uiScale" then return "general" end
    local root, rest = path:match("^([^.]+)(.*)$")
    if not root then return nil end
    if root == "addons" then return rest:match("^%.([^.]+)") end
    if root == "cdmSpells" then return CDM end
    if root == "unlockLayout" then
        local child = rest:match("^%.[^.]+%.(.+)$")
        return child and keyToFolder and keyToFolder[child] or nil
    end
    if OVERRIDE_KEYS[root] then return "overrides" end
    if ns.EUI_SPECIAL_KEYS[root] then return nil end
    return "general"
end

---------------------------------------------------------------------------------
-- Slices
---------------------------------------------------------------------------------

-- Replaces `into`'s slice for one row with `from`'s: absent in `from` means
-- absent in `into`, which the importer reads as "inherit".
local function copySlice(into, from, row, keyToFolder)
    from = isTable(from) and from or {}
    local copy = ns.EUIDeepCopy
    if row.id == "overrides" then
        for key in pairs(OVERRIDE_KEYS) do into[key] = copy(from[key]) end
        return
    end
    if row.id == "general" then
        local keys = {}
        for k in pairs(into) do keys[k] = true end
        for k in pairs(from) do keys[k] = true end
        for k in pairs(keys) do
            if type(k) == "string" and ns.EUIRowOf(k, keyToFolder) == "general" then into[k] = copy(from[k]) end
        end
        return
    end
    local folder = row.id
    if isTable(from.addons) and from.addons[folder] ~= nil then
        if not isTable(into.addons) then into.addons = {} end
        into.addons[folder] = copy(from.addons[folder])
    elseif isTable(into.addons) then
        into.addons[folder] = nil
    end
    if folder == CDM then into.cdmSpells = copy(from.cdmSpells) end
    local fromLayout = isTable(from.unlockLayout) and from.unlockLayout or {}
    for _, map in ipairs(ns.EUI_LAYOUT_MAPS) do
        local dst = isTable(into.unlockLayout) and into.unlockLayout[map]
        if isTable(dst) then
            for child in pairs(dst) do
                if keyToFolder[child] == folder then dst[child] = nil end
            end
        end
        for child, v in pairs(isTable(fromLayout[map]) and fromLayout[map] or {}) do
            if keyToFolder[child] == folder then
                if not isTable(into.unlockLayout) then into.unlockLayout = {} end
                if not isTable(into.unlockLayout[map]) then into.unlockLayout[map] = {} end
                into.unlockLayout[map][child] = copy(v)
            end
        end
    end
end

-- The one base the merge takes: each row's slice from the decoded base of the
-- version it stands at, the rest from the stamp's. A row with no base of its
-- own is left empty, so the merge replaces the player's changes there alone.
-- Returns nil when no row has a base, which is the merge's no-base path.
function ns.EUIComposeBase(rows, rowAt, byVersion, stamp, keyToFolder)
    rowAt = isTable(rowAt) and rowAt or {}
    byVersion = byVersion or {}
    local stampBase = stamp and byVersion[stamp] or nil
    local anyBase = stampBase ~= nil
    for _, rec in pairs(rowAt) do
        if isTable(rec) and byVersion[rec.version] then anyBase = true end
    end
    local missing = {}
    if not anyBase then
        for _, row in ipairs(rows) do missing[row.id] = true end
        return nil, missing
    end
    local O = stampBase and ns.EUIDeepCopy(stampBase) or {}
    for _, row in ipairs(rows) do
        local rec = rowAt[row.id]
        if rec or not stampBase then
            local src = isTable(rec) and byVersion[rec.version] or nil
            copySlice(O, src, row, keyToFolder)
            if not src then missing[row.id] = true end
        end
    end
    return O, missing
end

-- After the merge: every row the player did not tick, and every off row, is put
-- back to the player's copy, and its conflicts leave the report.
function ns.EUIKeepSlices(merged, report, P, rows, ticked, keyToFolder)
    local kept = {}
    for _, row in ipairs(rows) do
        if row.off or not ticked[row.id] then
            kept[row.id] = true
            copySlice(merged, P, row, keyToFolder)
            if row.id == "general" then
                merged.uiScale = nil
            elseif row.id == "overrides" then
                report.overrideSet = next(ns.EUIMaskedOverrideSet(P)) and "player" or "none"
            end
        end
    end
    local conflicts = {}
    for _, path in ipairs(report.conflicts) do
        local id = ns.EUIRowOf(path, keyToFolder)
        if not (id and kept[id]) then conflicts[#conflicts + 1] = path end
    end
    report.conflicts = conflicts
end

-- Replaced changes per ticked row, from the conflicts that reach the import.
function ns.EUIByRow(conflicts, ticked, keyToFolder)
    local byRow = {}
    for id in pairs(ticked) do byRow[id] = 0 end
    for _, path in ipairs(conflicts) do
        local id = ns.EUIRowOf(path, keyToFolder)
        if id and byRow[id] then byRow[id] = byRow[id] + 1 end
    end
    return byRow
end

-- The reset's rule: one row from KitnUI's string, everything else as it is.
function ns.EUITakeSlice(merged, N, row, keyToFolder)
    copySlice(merged, N, row, keyToFolder)
    if row.id == "general" then
        local nu = isTable(N) and N.uiScale
        local range = ns.EUI_SCALE_RANGE
        merged.uiScale = (type(nu) == "number" and nu >= range[1] and nu <= range[2]) and nu or nil
    end
end

---------------------------------------------------------------------------------
-- The per-part record
---------------------------------------------------------------------------------

-- kind: "update" | "take" | "reset". before: { rowAt, bases, stamp } as they
-- stood before the action. Returns the new rowAt and bases, nil when empty.
function ns.EUIRecordRows(kind, before, opts)
    local oldAt = isTable(before.rowAt) and before.rowAt or {}
    local rowAt, bases = {}, {}
    for v, s in pairs(isTable(before.bases) and before.bases or {}) do bases[v] = s end

    -- A waiting part is cleared only by being ticked, taken or reset. A count
    -- of zero is no proof it caught up: a level the string omits is inherited
    -- and counts nothing. A part this version does not list may come back. In
    -- both cases it still stands at its own version.
    -- A stored entry that is not a table with a version is skipped, as the
    -- composite base skips it: this runs after the import has landed.
    for id, rec in pairs(oldAt) do
        if isTable(rec) and type(rec.version) == "string" then rowAt[id] = rec end
    end
    if kind == "update" then
        local prior = opts.prior or {}
        local version = (prior.base and prior.version) or "none"
        for id in pairs(opts.ticked) do rowAt[id] = nil end
        for _, row in ipairs(opts.rows) do
            local id = row.id
            -- An off row keeps the player's copy through the update, so it
            -- starts waiting from the version it stood at, change or not: its
            -- changes are not counted while it is off.
            if not rowAt[id] and not opts.ticked[id] and (row.off or opts.changed[id]) then
                -- kitn marks a skip, which the tooltip names; an off row was
                -- not skipped by the player.
                rowAt[id] = { version = version, kitn = not row.off and opts.kitn or nil }
                if version ~= "none" then bases[version] = prior.base end
            end
        end
    elseif kind == "take" then
        for id in pairs(opts.ticked) do rowAt[id] = nil end
    elseif kind == "reset" then
        local shipped = opts.shipped or {}
        -- With no shipped version the part cannot be placed, so nothing is
        -- written, even when the stamp is missing too.
        if shipped.version == nil then return next(rowAt) and rowAt or nil, next(bases) and bases or nil end
        if shipped.version == before.stamp then
            rowAt[opts.row] = nil
        elseif shipped.base ~= nil then
            rowAt[opts.row] = { version = shipped.version }
            bases[shipped.version] = shipped.base
        end
    end

    local named = {}
    for _, rec in pairs(rowAt) do named[rec.version] = true end
    for v in pairs(bases) do
        if not named[v] then bases[v] = nil end
    end
    return next(rowAt) and rowAt or nil, next(bases) and bases or nil
end
