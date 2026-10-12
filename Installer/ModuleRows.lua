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

-- The link maps, each size-match map followed by its extras, which are keyed
-- by the same child and go where the link goes: a part's layout slice, and the
-- maps a Spec Overrides layer carries under the same names.
local SLICE_MAPS = {}
for _, map in ipairs(ns.EUI_LAYOUT_MAPS) do
    SLICE_MAPS[#SLICE_MAPS + 1] = map
    if ns.EUI_MATCH_EXTRAS[map] then SLICE_MAPS[#SLICE_MAPS + 1] = ns.EUI_MATCH_EXTRAS[map] end
end

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
    rows[#rows + 1] = { id = "general", label = "General", sub = "fonts, colors, scale" }
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
    for _, map in ipairs(SLICE_MAPS) do
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

-- A part's stored entry, or nil. Saved data can hold anything, so only a
-- table with a string version counts as one, and a skip label the tooltip
-- cannot format is read as absent.
function ns.EUIRowRecord(rowAt, id)
    local rec = isTable(rowAt) and rowAt[id] or nil
    if not (isTable(rec) and type(rec.version) == "string") then return nil end
    if rec.kitn ~= nil and type(rec.kitn) ~= "string" then return { version = rec.version } end
    return rec
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
    for id in pairs(rowAt) do
        local rec = ns.EUIRowRecord(rowAt, id)
        if rec and byVersion[rec.version] then anyBase = true end
    end
    local missing = {}
    if not anyBase then
        for _, row in ipairs(rows) do missing[row.id] = true end
        return nil, missing
    end
    local O = stampBase and ns.EUIDeepCopy(stampBase) or {}
    for _, row in ipairs(rows) do
        local rec = ns.EUIRowRecord(rowAt, row.id)
        if rec or not stampBase then
            local src = rec and byVersion[rec.version] or nil
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

-- KitnUI's folder holds the Top Bar's settings, its tb* keys, beside the
-- switch states of KitnUI's other pages and what those pages keep. The Top Bar
-- row is the tb* keys alone. Returns a shallow copy of t's keys on the `top`
-- side; a walk passes its tick, charged once per key read.
local function topBarKeys(t, top, tickFn)
    if not isTable(t) then return nil end
    local out = {}
    for k, v in pairs(t) do
        if tickFn then tickFn() end
        if (type(k) == "string" and k:sub(1, 2) == "tb") == top then out[k] = v end
    end
    return out
end

-- The reset's rule: one row from KitnUI's string, everything else as it is.
-- A Top Bar reset keeps the player's switch states: only a switch's own page
-- changes one, and releases what it holds when it does.
function ns.EUITakeSlice(merged, N, row, keyToFolder)
    local kept
    if row.id == TOP_BAR then
        kept = topBarKeys(isTable(merged.addons) and merged.addons[TOP_BAR], false) or {}
    end
    copySlice(merged, N, row, keyToFolder)
    if kept then
        if not isTable(merged.addons) then merged.addons = {} end
        local folder = merged.addons[TOP_BAR]
        if not isTable(folder) then
            folder = {}
            merged.addons[TOP_BAR] = folder
        end
        for k in pairs(topBarKeys(folder, false)) do folder[k] = nil end
        for k, v in pairs(kept) do folder[k] = v end
    end
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
    -- of zero is no proof it caught up (a level the string omits is inherited
    -- and counts nothing), and a part this version does not list may come back.
    -- An entry that is not a table with a version is skipped, as the composite
    -- base skips it: this runs after the import has landed.
    for id in pairs(oldAt) do rowAt[id] = ns.EUIRowRecord(oldAt, id) end
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

---------------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------------

local CHANNELS = { r = true, g = true, b = true, a = true }
local STEM_CHANNELS = { "R", "G", "B", "A" }

-- Keys that only wrap the group one level down.
local GROUP_WRAPPERS = {
    bars = true, cdmBars = true, positions = true, enabledFrames = true,
    frameSource = true, minimap = true, questTracker = true,
}

local GROUP_NAMES = {
    player = "Player", target = "Target", focus = "Focus", pet = "Pet",
    targettarget = "Target of Target", focustarget = "Focus Target", boss = "Boss Frames",
    MainBar = "Action Bar 1", Bar2 = "Action Bar 2", Bar3 = "Action Bar 3", Bar4 = "Action Bar 4",
    Bar5 = "Action Bar 5", Bar6 = "Action Bar 6", Bar7 = "Action Bar 7", Bar8 = "Action Bar 8",
    StanceBar = "Stance Bar", PetBar = "Pet Bar",
    health = "Health Bar", primary = "Primary Resource", secondary = "Class Resource", castBar = "Cast Bar",
    spec = "Spec Layouts", healerMana = "Healer Mana", palettes = "Palettes",
    fonts = "Fonts", customColors = "Colors", darkMode = "Dark Mode", euiAccent = "Accent Color",
}

local function tidy(key)
    local n = key:match("^%[(%d+)%]$")
    if n then return "#" .. n end
    local s = key:gsub("_", " ")
    s = s:gsub("(%l)(%u)", "%1 %2")
    s = s:gsub("(%a)(%d)", "%1 %2")
    return (s:lower())
end

local function capital(s) return (s:gsub("^%l", string.upper)) end

-- EllesmereUI stores a buff placed on a cooldown bar as -(base + spellID) in
-- the bar's assignedSpells, beside plain spell IDs. A cooldown claim marker,
-- -(claim base + cooldownID), lies past every hosted marker and names no spell.
local CDM_HOSTED_BASE, CDM_CLAIM_BASE = 2000000000, 3000000000

-- An answer from the walk's lookups (EUIRowDiff, opts.names), or nil: a name
-- from spec and spell, a spell ID from cooldown. Each answer is kept, so an ID
-- costs one lookup, and one unit of the walk's budget, however often it is
-- named.
local function lookup(labels, kind, id)
    local fn = labels[kind]
    if type(fn) ~= "function" or type(id) ~= "number" then return nil end
    local memoKey = kind .. "Memo"
    local memo = labels[memoKey]
    if not memo then
        memo = {}
        labels[memoKey] = memo
    end
    local found = memo[id]
    if found == nil then
        if labels.tick then labels.tick() end
        found = fn(id)
        local usable
        if kind == "cooldown" then
            usable = type(found) == "number" and found > 0
        else
            usable = type(found) == "string" and found ~= ""
        end
        if not usable then found = false end
        memo[id] = found
    end
    return found or nil
end

-- The spell one bar list entry names, or nil. assignedSpells holds spell IDs
-- as values; customSpellIDs and spellDurations are keyed by spell ID;
-- buffDisplayOrder holds "s<spellID>" or "c<cooldownID>", a cooldown read as
-- its spell through the cooldown lookup.
local function cdmSpellID(list, key, value, labels)
    if list == "assignedSpells" and key:match("^%[%d+%]$") and type(value) == "number" then
        if value > 0 then return value end
        if value <= -CDM_HOSTED_BASE and value > -CDM_CLAIM_BASE then return -value - CDM_HOSTED_BASE end
    elseif list == "customSpellIDs" or list == "spellDurations" then
        local id = tonumber(key:match("^%[(%d+)%]$") or "")
        if id and id > 0 then return id end
    elseif list == "buffDisplayOrder" and key:match("^%[%d+%]$") and type(value) == "string" then
        local prefix, digits = value:match("^([sc])(%d+)$")
        local id = tonumber(digits or "")
        if id and id > 0 then
            if prefix == "s" then return id end
            return lookup(labels, "cooldown", id)
        end
    end
    return nil
end

-- Top Bar settings the tidied key would misname. Any other tb key reads as
-- its tidied name without the prefix: "tbIconSize" is "Icon size".
local TOP_BAR_NAMES = {
    tbOff = "Hidden elements", tbOrder = "Element order", tbPos = "Bar position",
    tbSysPos = "FPS and latency position", tbSysSize = "FPS / MS size", tbUse24h = "24-hour clock",
    tbHideSerious = "Hide in keystones, raids and rated PvP", tbAccent = "Custom accent color",
    tbEnabled = "Top Bar on",
}

-- A Cooldown Manager path, cdmSpells.<specID>.<rest>: the spec is the group,
-- a spell list's entry is its spell, and anything under a bar names the bar.
-- An unnamed duration entry keeps its key, "#<spellID>".
local function cdmLabel(parts, labels, value)
    local specID = tonumber(parts[2]:match("^%[?(%d+)%]?$") or "")
    local group = lookup(labels, "spec", specID) or ("Spec " .. (specID and tostring(specID) or parts[2]))
    local bar = parts[3] == "barSpells" and parts[4] and capital(tidy(parts[4])) or nil
    local last = #parts
    while last > 2 and CHANNELS[parts[last]] do last = last - 1 end
    local item
    if bar and last == 6 then
        local spellID = cdmSpellID(parts[5], parts[6], value, labels)
        if spellID then
            item = lookup(labels, "spell", spellID)
            if not item and parts[5] ~= "spellDurations" then item = "spell " .. spellID end
        end
    end
    item = item or (labels.names and labels.names[table.concat(parts, ".", 1, last)]) or tidy(parts[last])
    if bar then item = item .. " (" .. bar .. ")" end
    return group, item
end

-- A Top Bar setting: its name, then what lies below it, as "Hidden elements (clock)".
local function topBarItem(parts)
    local last = #parts
    while last > 3 and CHANNELS[parts[last]] do last = last - 1 end
    local key = parts[3]
    local item = TOP_BAR_NAMES[key] or capital(tidy(key:sub(3)))
    if last > 3 then
        local below = {}
        for j = 4, last do below[#below + 1] = tidy(parts[j]) end
        item = item .. " (" .. table.concat(below, " ") .. ")"
    end
    return item
end

-- Unit frame aura lists keyed by spell ID: the Tracked Auras include and
-- exclude sets, and a buff filter's spells (playerAuraBars.pabFilters.list).
local SPELL_SETS = {
    debuffInclude = true, debuffExclude = true, debuffIncludeAnyCaster = true, debuffIncludeMine = true,
}

local function spellSet(parts, k)
    return SPELL_SETS[parts[k]] or (parts[k] == "spells" and parts[k - 3] == "pabFilters")
end

-- The keys parts[from..to] between a group and its setting, outermost first:
-- each reads by the name the walk found for it, a table name, its Unlock Mode
-- label, or tidied, and an index folds into the key it numbers.
local function labelContext(parts, from, to, unlock, names)
    local out = {}
    local j = from
    while j <= to do
        local key = parts[j]
        local name = names[table.concat(parts, ".", 1, j)] or GROUP_NAMES[key] or unlock[key] or tidy(key)
        if j < to and parts[j + 1]:match("^%[%d+%]$") then
            out[#out + 1] = names[table.concat(parts, ".", 1, j + 1)] or (name .. " " .. tidy(parts[j + 1]))
            j = j + 2
        else
            out[#out + 1] = name
            j = j + 1
        end
    end
    return out
end

-- (group, item) for one counted path. labels.unlock: element key -> Unlock
-- Mode label; labels.names: list-entry path -> that entry's name field;
-- labels.spec, labels.spell and labels.cooldown: the walk's lookups. value:
-- the setting's own value, which names a Cooldown Manager list entry. The
-- keys between the group and the setting follow the item as context:
-- "x (Action Bar 1)", "buff colors #1 (threshold specs #2)". An entry of a
-- spell-keyed aura list reads by its spell: "debuff exclude: <spell>".
function ns.EUISettingLabel(path, row, labels, value)
    labels = labels or {}
    local unlock, names = labels.unlock or {}, labels.names or {}
    if path == "uiScale" then return "General", "ui scale" end
    if path == "Spec Overrides" then return "Spec Overrides", "override set" end
    local child = path:match("^unlockLayout%.[^.]+%.(.+)$")
    if child then return "Positions", unlock[child] or capital(tidy(child)) end

    local parts = {}
    for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
    if parts[1] == "cdmSpells" and parts[2] then return cdmLabel(parts, labels, value) end
    if parts[1] == "addons" and parts[2] == TOP_BAR and parts[3] and parts[3]:sub(1, 2) == "tb" then
        return "Top Bar", topBarItem(parts)
    end
    local i = 1
    if parts[1] == "addons" then i = 3 end
    while parts[i] and GROUP_WRAPPERS[parts[i]] and parts[i + 1] do i = i + 1 end
    local group
    if i >= #parts then
        group = (row and row.id == "general" and GROUP_NAMES[parts[1]]) or "General"
    else
        local key = parts[i]
        group = names[table.concat(parts, ".", 1, i)] or GROUP_NAMES[key] or unlock[key] or capital(tidy(key))
    end
    local last = #parts
    while last > i and CHANNELS[parts[last]] do last = last - 1 end
    local item = names[table.concat(parts, ".", 1, last)]
    local contextEnd = last - 1
    if not item then
        local index = parts[last]:match("^%[(%d+)%]$")
        if index and last - 1 > i then
            local parent = tidy(parts[last - 1])
            local spellName = spellSet(parts, last - 1) and lookup(labels, "spell", tonumber(index))
            item = spellName and (parent .. ": " .. spellName) or (parent .. " #" .. index)
            contextEnd = last - 2
        else
            item = tidy(parts[last])
        end
    end
    local context = labelContext(parts, i + 1, contextEnd, unlock, names)
    if #context > 0 then item = item .. " (" .. table.concat(context, ", ") .. ")" end
    return group, item
end

local TIP_GROUPS, TIP_ITEMS = 6, 8

-- The hover list: { text, header } lines, capped. A group listing fewer
-- settings than it holds shows its total in its heading, and the settings of
-- the groups left out are counted in a last "+N more" line. A group's `n` and
-- the entry's `count` are the totals behind the capped lists the walk keeps;
-- without them the lists' own lengths are the totals.
function ns.EUITooltipLines(entry)
    local lines = {}
    local groups = isTable(entry) and entry.groups or {}
    local total, shown = 0, 0
    for gi = 1, #groups do total = total + (groups[gi].n or #groups[gi].items) end
    if isTable(entry) and type(entry.count) == "number" and entry.count > total then total = entry.count end
    for gi = 1, math.min(#groups, TIP_GROUPS) do
        local g = groups[gi]
        local n = g.n or #g.items
        local listed = math.min(#g.items, TIP_ITEMS)
        shown = shown + n
        lines[#lines + 1] = { text = n > listed and (g.name .. " (" .. n .. ")") or g.name, header = true }
        for ii = 1, listed do lines[#lines + 1] = { text = g.items[ii] } end
    end
    if total > shown then lines[#lines + 1] = { text = "+" .. (total - shown) .. " more" } end
    return lines
end

---------------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------------

-- A held override value, as the held-path set spells it.
local HELD_FKEY = "specOverride:"
ns.EUI_HELD_FKEY = HELD_FKEY

local function isColour(t)
    if not isTable(t) or next(t) == nil then return false end
    for k in pairs(t) do
        if not CHANNELS[k] then return false end
    end
    return true
end

local function hasKey(a, b, key)
    return (isTable(a) and a[key] ~= nil) or (isTable(b) and b[key] ~= nil)
end

-- "fillR" with "fillG" and "fillB" beside it is one colour, "fill".
local function stemOf(k, a, b)
    if type(k) ~= "string" then return nil end
    local stem, ch = k:match("^(.+)([RGBA])$")
    if stem and hasKey(a, b, stem .. "R") and hasKey(a, b, stem .. "G") and hasKey(a, b, stem .. "B") then
        return stem, ch
    end
    return nil
end

local Walker = {}
Walker.__index = Walker

-- One unit of work: one key read from a table being walked, scanned, copied or
-- compared. The walk runs in a coroutine that yields once a step's units are
-- spent, so no single node, layout scan or override comparison can hold a
-- frame past the budget. Outside that coroutine it never yields.
local function tick(w)
    w.units = w.units + 1
    if w.units >= w.budget and w.co and coroutine.running() == w.co then coroutine.yield() end
end

local function entryFor(w, id)
    local e = w.result[id]
    if not e then
        e = { count = 0, groups = {} }
        w.result[id] = e
        w.byName[id] = {}
    end
    return e
end

local function byGroupName(x, y) return x.name < y.name end
local function byText(x, y) return x < y end

-- Inserts v into a list kept sorted and at most `cap` long, in at most
-- `cap` + 1 comparisons.
local function insertCapped(list, v, cap, less)
    local i = #list + 1
    while i > 1 and less(v, list[i - 1]) do i = i - 1 end
    if i > cap then return end
    table.insert(list, i, v)
    if #list > cap then list[#list] = nil end
end

-- A part keeps its total, each group's total, and only the first groups and
-- settings by name, as many as the tooltip shows. A recorded setting costs the
-- same however many came before it, and nothing is left to sort at the end.
local function record(w, row, path, value)
    local e = entryFor(w, row.id)
    e.count = e.count + 1
    local group, item = ns.EUISettingLabel(path, row, w.labels, value)
    local g = w.byName[row.id][group]
    if not g then
        g = { name = group, items = {}, n = 0 }
        w.byName[row.id][group] = g
        insertCapped(e.groups, g, TIP_GROUPS, byGroupName)
    end
    g.n = g.n + 1
    insertCapped(g.items, item, TIP_ITEMS, byText)
end

-- The player's walk leaves out what KitnUI's own switches hold, and the health
-- fill the import's activation resets unless the player coloured it.
local function excluded(w, path)
    if not w.player then return false end
    if w.held[path] then return true end
    if w.healthCheck then
        local leaf = path:match(ns.EUI_HEALTH_PATH)
        if leaf and ns.EUI_HEALTH_LEAVES[leaf] then return true end
    end
    return false
end

-- Parallel arrays rather than a table per pending node. n is KitnUI's side,
-- read only by a reset's count (opts.against).
local function push(w, a, b, d, path, row, hasDefaults, fn, n)
    local i = w.top + 1
    w.top = i
    w.sa[i], w.sb[i], w.sd[i], w.sp[i], w.sr[i], w.sh[i], w.sf[i], w.sn[i] = a, b, d, path, row, hasDefaults, fn, n
end

-- Where the import inherits rather than deletes: a root key (the importer
-- builds on the active profile's copy), a module folder, a CDM spell entry.
-- Absent from KitnUI's string there, a setting stays the player's; absent
-- anywhere below, the merge deletes it (Merge.lua, unit and leaf).
local function inheritedAt(path)
    return not path:find(".", 1, true) or path:find("^addons%.[^.]+$") ~= nil
        or path:find("^cdmSpells%.[^.]+$") ~= nil
end

-- Marks KitnUI's side below a level its string does not carry: the reset
-- leaves everything there as the player has it.
local INHERIT = {}

-- a is the base side, b the side described. In the player's walk a setting one
-- side lacks reads as the registered default there, and is not counted when
-- the folder has none. In the update walk every difference counts; a level
-- KitnUI's string does not carry at all is stopped in visit.
local function differs(w, a, b, d, hasDefaults)
    if ns.EUISame(a, b) then return false end
    if not w.player then return true end
    if a ~= nil and b ~= nil then return true end
    if not hasDefaults then return false end
    if a == nil then return not ns.EUISame(b, d) end
    return not ns.EUISame(a, d)
end

-- A reset's count holds only the player's changes the reset alters: the
-- player's value against KitnUI's, a registered default standing in for an
-- absent side. Without opts.against every change counts.
local function replaced(w, b, n, d, hasDefaults)
    if not w.against then return true end
    if n == INHERIT then return false end
    local be, ne = b, n
    if hasDefaults then
        if be == nil then be = d end
        if ne == nil then ne = d end
    end
    return not ns.EUISame(be, ne)
end

local function channelOf(t, key)
    if isTable(t) then return t[key] end
    return nil
end

local function stemDiffers(w, a, b, d, hasDefaults, stem)
    local aHas, bHas, any = false, false, false
    for _, ch in ipairs(STEM_CHANNELS) do
        local av, bv = channelOf(a, stem .. ch), channelOf(b, stem .. ch)
        if av ~= nil then aHas = true end
        if bv ~= nil then bHas = true end
        if not ns.EUISame(av, bv) then any = true end
    end
    if not any then return false end
    if not w.player then return true end
    if aHas and bHas then return true end
    if not hasDefaults then return false end
    local side = aHas and a or b
    for _, ch in ipairs(STEM_CHANNELS) do
        if not ns.EUISame(channelOf(side, stem .. ch), channelOf(d, stem .. ch)) then return true end
    end
    return false
end

local function stemReplaced(w, b, n, d, hasDefaults, stem)
    if not w.against then return true end
    if n == INHERIT then return false end
    for _, ch in ipairs(STEM_CHANNELS) do
        local k = stem .. ch
        if replaced(w, channelOf(b, k), channelOf(n, k), channelOf(d, k), hasDefaults) then return true end
    end
    return false
end

local function visitKey(w, a, b, d, path, row, hasDefaults, n, k)
    tick(w)
    local stem, ch = stemOf(k, a, b)
    if stem then
        if ch ~= "R" then return end
        for _, c in ipairs(STEM_CHANNELS) do
            if excluded(w, ns.EUIJoinPath(path, stem .. c)) then return end
        end
        if stemDiffers(w, a, b, d, hasDefaults, stem) and stemReplaced(w, b, n, d, hasDefaults, stem) then
            record(w, row, ns.EUIJoinPath(path, stem))
        end
        return
    end
    local av, bv = channelOf(a, k), channelOf(b, k)
    local childPath = ns.EUIJoinPath(path, k)
    if type(k) == "number" then
        local named = (isTable(bv) and bv.name) or (isTable(av) and av.name)
        if type(named) == "string" then w.labels.names[childPath] = named end
    end
    local nv = n
    if n ~= INHERIT then nv = channelOf(n, k) end
    push(w, av, bv, channelOf(d, k), childPath, row, hasDefaults, nil, nv)
end

-- Every key either side holds is one tick, the second side's keys included
-- when the first already had them, so no table is read past the budget.
local function visit(w, a, b, d, path, row, hasDefaults, n)
    if excluded(w, path) then return end
    if inheritedAt(path) then
        if not w.player and b == nil then return end
        if w.against and n == nil then n = INHERIT end
    end
    local ta, tb = isTable(a), isTable(b)
    local descend = (ta or tb) and (ta or a == nil) and (tb or b == nil)
        and not isColour(a) and not isColour(b)
    if not descend then
        if differs(w, a, b, d, hasDefaults) and replaced(w, b, n, d, hasDefaults) then
            local value = b
            if value == nil then value = a end
            record(w, row, path, value)
        end
        return
    end
    if ta then
        for k in pairs(a) do visitKey(w, a, b, d, path, row, hasDefaults, n, k) end
    end
    if tb then
        for k in pairs(b) do
            tick(w)
            if not (ta and a[k] ~= nil) then visitKey(w, a, b, d, path, row, hasDefaults, n, k) end
        end
    end
end

-- One side's override stores with every held value and held position removed,
-- so a switch holding one down is not read as the player's own change.
local function withoutHeld(w, d)
    if not (w.player and w.heldAny and isTable(d)) then return d end
    local out = {}
    for k, v in pairs(d) do
        tick(w)
        out[k] = v
    end
    for _, storeKey in ipairs({ "specOverrides", "condOverrides" }) do
        if isTable(d[storeKey]) then
            local store = ns.EUIDeepCopy(d[storeKey], w.tickFn)
            for _, entry in pairs(store) do
                tick(w)
                if isTable(entry) and isTable(entry.values) then
                    for _, map in pairs(entry.values) do
                        tick(w)
                        if isTable(map) then
                            for fkey in pairs(w.heldFkeys) do
                                tick(w)
                                map[fkey] = nil
                            end
                        end
                    end
                end
            end
            out[storeKey] = store
        end
    end
    if isTable(d.unlockOverrideAnchors) then
        local store = ns.EUIDeepCopy(d.unlockOverrideAnchors, w.tickFn)
        for key in pairs(w.heldAnchors) do
            tick(w)
            store[key] = nil
        end
        out.unlockOverrideAnchors = next(store) and store or nil
    end
    return out
end

local function layoutMap(d, map)
    local ul = isTable(d) and d.unlockLayout
    return isTable(ul) and isTable(ul[map]) and ul[map] or nil
end

-- Every layout entry, owned by its child's row, counted once when it differs
-- (and, for a reset, when KitnUI's entry differs from the player's too).
local function layoutJob(w, B, rowById, bases, keyToFolder)
    local sources = {}
    for _, src in pairs(bases) do
        tick(w)
        sources[src] = true
    end
    for _, map in ipairs(ns.EUI_LAYOUT_MAPS) do
        local children = {}
        for child in pairs(layoutMap(B, map) or {}) do
            tick(w)
            children[child] = true
        end
        for src in pairs(sources) do
            for child in pairs(layoutMap(src, map) or {}) do
                tick(w)
                children[child] = true
            end
        end
        for child in pairs(children) do
            tick(w)
            local row = rowById[keyToFolder[child]]
            if row and bases[row.id] ~= nil then
                local path = "unlockLayout." .. map .. "." .. tostring(child)
                local am, bm = layoutMap(bases[row.id], map), layoutMap(B, map)
                local nm = w.against and layoutMap(w.against, map)
                local linkDiffers = not ns.EUISame(am and am[child], bm and bm[child], w.tickFn)
                if not excluded(w, path) and linkDiffers
                    and not (w.against and ns.EUISame(bm and bm[child], nm and nm[child], w.tickFn)) then
                    record(w, row, path)
                end
                -- A size-match extra counts apart from its link, as the merge
                -- counts it. KitnUI's reaches the player only with KitnUI's
                -- link, so the update walk reads it only where the link differs.
                local xmap = ns.EUI_MATCH_EXTRAS[map]
                if xmap and (w.player or linkDiffers) then
                    tick(w)
                    local xb = ns.EUIExtraOf(B, map, child)
                    if not ns.EUISame(ns.EUIExtraOf(bases[row.id], map, child), xb, w.tickFn)
                        and not (w.against and ns.EUISame(xb, ns.EUIExtraOf(w.against, map, child), w.tickFn)) then
                        record(w, row, "unlockLayout." .. xmap .. "." .. tostring(child))
                    end
                end
            end
        end
    end
end

local function inScale(v)
    local range = ns.EUI_SCALE_RANGE
    return type(v) == "number" and v >= range[1] and v <= range[2]
end

local function seedRow(w, row, src, B, defaults)
    local N = w.against
    if row.id == "overrides" then
        push(w, nil, nil, nil, nil, nil, nil, function(self)
            local ma = ns.EUIMaskedOverrideSet(withoutHeld(self, src), self.tickFn)
            local mb = ns.EUIMaskedOverrideSet(withoutHeld(self, B), self.tickFn)
            if ns.EUIOverrideSetsSame(ma, mb, self.tickFn) then return end
            -- A reset takes KitnUI's set whole: nothing is replaced when the
            -- player's already is KitnUI's.
            if N then
                local mn = ns.EUIMaskedOverrideSet(withoutHeld(self, N), self.tickFn)
                if ns.EUIOverrideSetsSame(mn, mb, self.tickFn) then return end
            end
            record(self, row, "Spec Overrides")
        end)
        return
    end
    if row.id == "general" then
        push(w, nil, nil, nil, nil, nil, nil, function(self)
            local bu, au = channelOf(B, "uiScale"), channelOf(src, "uiScale")
            if not inScale(bu) or ns.EUISame(au, bu) then return end
            -- A reset applies KitnUI's scale only inside the range.
            if N and not (inScale(N.uiScale) and not ns.EUISame(bu, N.uiScale)) then return end
            record(self, row, "uiScale")
        end)
        local keys = {}
        for k in pairs(isTable(src) and src or {}) do
            tick(w)
            keys[k] = true
        end
        for k in pairs(isTable(B) and B or {}) do
            tick(w)
            keys[k] = true
        end
        for k in pairs(keys) do
            tick(w)
            if type(k) == "string" and k ~= "uiScale" and ns.EUIRowOf(k, nil) == "general" then
                -- A General reset takes KitnUI's root tables whole, and
                -- EllesmereUI registers no defaults for them, so a setting only
                -- one side holds is one the reset changes: it counts.
                push(w, channelOf(src, k), channelOf(B, k), nil, k, row, true, nil, channelOf(N, k))
            end
        end
        return
    end
    local folder = row.id
    local d = defaults[folder]
    local a, b = channelOf(channelOf(src, "addons"), folder), channelOf(channelOf(B, "addons"), folder)
    local n = channelOf(channelOf(N, "addons"), folder)
    -- The player's walk reads the Top Bar row as the Top Bar's own settings;
    -- a switch state is KitnUI's, and a Reset keeps it.
    if folder == TOP_BAR and w.player then
        local tickFn = w.tickFn
        a, b = topBarKeys(a, true, tickFn), topBarKeys(b, true, tickFn)
        n, d = topBarKeys(n, true, tickFn), topBarKeys(d, true, tickFn)
    end
    push(w, a, b, d, "addons." .. folder, row, d ~= nil, nil, n)
    if folder == "EllesmereUICooldownManager" then
        push(w, channelOf(src, "cdmSpells"), channelOf(B, "cdmSpells"), nil, "cdmSpells", row, false,
            nil, channelOf(N, "cdmSpells"))
    end
end

-- A resumable walk: Step(budget) does at most `budget` units of work (tick)
-- and returns true once every row is counted. result[id] = { count,
-- groups = { {name, n, items} }, noBase }, groups and items capped
-- at what the tooltip shows. opts: player, noBase, missing, fallback, held,
-- defaults, unlock, against (KitnUI's side, for a reset's count), names
-- ({ spec = fn(id), spell = fn(id), cooldown = fn(id) }, the tooltip's
-- lookups; cooldown gives a cooldown's spell ID). Building the walker reads
-- no table: the first Step does the setup, under the budget.
function ns.EUIRowDiff(A, B, rows, keyToFolder, opts)
    opts = opts or {}
    local lookups = isTable(opts.names) and opts.names or {}
    local w = setmetatable({
        A = A, B = B, rows = rows or {}, keyToFolder = keyToFolder or {}, opts = opts,
        result = {}, byName = {}, top = 0, done = false, prepared = false, units = 0, budget = math.huge,
        sa = {}, sb = {}, sd = {}, sp = {}, sr = {}, sh = {}, sf = {}, sn = {},
        against = opts.against,
        player = opts.player and true or false,
        held = opts.held or {},
        heldFkeys = {}, heldAnchors = {}, heldAny = false,
        labels = {
            unlock = opts.unlock or {}, names = {},
            spec = lookups.spec, spell = lookups.spell, cooldown = lookups.cooldown,
        },
    }, Walker)
    w.tickFn = function() tick(w) end
    w.labels.tick = w.tickFn
    return w
end

-- The setup: the held paths, the health switch and each row's seeds, General's
-- scan of every root key among them. It runs inside the walk's coroutine and
-- ticks as the walk does, so a wide root or held set is spread over frames.
local function prepare(w)
    local A, B, opts = w.A, w.B, w.opts
    for path in pairs(w.held) do
        tick(w)
        if path:sub(1, #HELD_FKEY) == HELD_FKEY then
            w.heldFkeys[path:sub(#HELD_FKEY + 1)] = true
            w.heldAny = true
        else
            local key = path:match("^unlockOverrideAnchors%.(.+)$")
            if key then
                w.heldAnchors[key] = true
                w.heldAny = true
            end
        end
    end
    local rb = channelOf(channelOf(B, "addons"), "EllesmereUIResourceBars")
    local health = channelOf(rb, "health")
    w.healthCheck = w.player and not (isTable(health) and health.customColored == true)

    local defaults, missing = opts.defaults or {}, opts.missing or {}
    local rowById, bases = {}, {}
    for _, row in ipairs(w.rows) do
        tick(w)
        rowById[row.id] = row
        local entry = entryFor(w, row.id)
        local src = A
        if missing[row.id] then
            entry.noBase = true
            src = w.player and opts.fallback or nil
        elseif opts.noBase then
            entry.noBase = true
        end
        if not row.off and not (missing[row.id] and not w.player) then
            if src ~= nil then bases[row.id] = src end
            seedRow(w, row, src, B, defaults)
        end
    end
    push(w, nil, nil, nil, nil, nil, nil, function(self)
        layoutJob(self, B, rowById, bases, self.keyToFolder)
    end)
    w.prepared = true
end

local function drain(w)
    prepare(w)
    while w.top > 0 do
        tick(w)
        local i = w.top
        local a, b, d, path, row, hasDefaults, fn, n =
            w.sa[i], w.sb[i], w.sd[i], w.sp[i], w.sr[i], w.sh[i], w.sf[i], w.sn[i]
        w.sa[i], w.sb[i], w.sd[i], w.sp[i], w.sr[i], w.sh[i], w.sf[i], w.sn[i] =
            nil, nil, nil, nil, nil, nil, nil, nil
        w.top = i - 1
        if fn then fn(w) else visit(w, a, b, d, path, row, hasDefaults, n) end
    end
    w.byName = {}
    w.done = true
end

function Walker:Step(budget)
    if self.done then return true end
    self.budget, self.units = budget, 0
    self.co = self.co or coroutine.create(drain)
    local ok, err = coroutine.resume(self.co, self)
    if not ok then
        self.done = true
        error(err, 0)
    end
    return self.done
end

---------------------------------------------------------------------------------
-- Split links and override capture
---------------------------------------------------------------------------------

-- Every link whose child's row is ticked and whose target's row keeps the
-- player's copy, one per pair of rows, in row order.
function ns.EUISplitLinks(N, rows, ticked, keyToFolder)
    local ul = isTable(N) and N.unlockLayout
    if not isTable(ul) then return {} end
    local rowById, order = {}, {}
    for i, row in ipairs(rows) do
        rowById[row.id] = row
        order[row.id] = i
    end
    local out, seen = {}, {}
    for _, map in ipairs(ns.EUI_LAYOUT_MAPS) do
        for child, entry in pairs(isTable(ul[map]) and ul[map] or {}) do
            local target = entry
            if map == "anchors" then target = isTable(entry) and entry.target or nil end
            local childRow = rowById[keyToFolder[child]]
            local targetRow = type(target) == "string" and rowById[keyToFolder[target]] or nil
            if childRow and targetRow and childRow ~= targetRow and ticked[childRow.id]
                and not ticked[targetRow.id] and not targetRow.off then
                local pair = childRow.id .. "\31" .. targetRow.id
                if not seen[pair] then
                    seen[pair] = true
                    out[#out + 1] = { child = childRow, target = targetRow }
                end
            end
        end
    end
    table.sort(out, function(x, y)
        if order[x.child.id] ~= order[y.child.id] then return order[x.child.id] < order[y.child.id] end
        return order[x.target.id] < order[y.target.id]
    end)
    return out
end

local UNLOCK_STORES = { "specUnlockOverrides", "condUnlockOverrides" }

local function eachElementKey(P, fn)
    for key in pairs(isTable(P.unlockOverrideAnchors) and P.unlockOverrideAnchors or {}) do fn(key) end
    for _, storeKey in ipairs(UNLOCK_STORES) do
        local layouts = isTable(P[storeKey]) and P[storeKey].layouts
        for _, layer in pairs(isTable(layouts) and layouts or {}) do
            if isTable(layer) then
                for key in pairs(isTable(layer.elems) and layer.elems or {}) do fn(key) end
                -- A layer's links and extras can name a child it holds no
                -- element entry for, and applying the layer writes them all.
                for _, map in ipairs(SLICE_MAPS) do
                    for key in pairs(isTable(layer[map]) and layer[map] or {}) do fn(key) end
                end
            end
        end
    end
end

-- True when the player's Spec Overrides hold anything of this folder: a
-- captured value whose fkey names it, or a position of one of its elements.
function ns.EUIOverridesCapture(P, folder, keyToFolder)
    if not (isTable(P) and folder) then return false end
    local prefix = folder .. "\31"
    for _, storeKey in ipairs({ "specOverrides", "condOverrides" }) do
        for _, entry in pairs(isTable(P[storeKey]) and P[storeKey] or {}) do
            for _, map in pairs(isTable(entry) and isTable(entry.values) and entry.values or {}) do
                for fkey in pairs(isTable(map) and map or {}) do
                    if type(fkey) == "string" and fkey:sub(1, #prefix) == prefix then return true end
                end
            end
        end
    end
    local found = false
    eachElementKey(P, function(key)
        if keyToFolder[key] == folder then found = true end
    end)
    return found
end

-- A layout-shaped side holding every override element key, so the importer's
-- resolver classifies them alongside the layout's own keys.
function ns.EUIOverrideElementSide(P)
    local anchors = {}
    if isTable(P) then
        eachElementKey(P, function(key) anchors[key] = {} end)
    end
    return { unlockLayout = { anchors = anchors } }
end

---------------------------------------------------------------------------------
-- The settled record
---------------------------------------------------------------------------------

-- Stands for every part the pointers do not name.
local ALL = "*"

local function validId(v)
    return type(v) == "number" and v >= 1 and math.floor(v) == v
end

local function sound(entry)
    return isTable(entry) and type(entry.s) == "string"
end

-- The record read into fresh tables. Saved data can hold anything, so a value
-- of the wrong type is read as absent, and so dropped at this write.
local function cleanSettle(before)
    before = isTable(before) and before or {}
    local settled, at, pending, due = {}, {}, {}, {}
    for id, entry in pairs(isTable(before.settled) and before.settled or {}) do
        if validId(id) and sound(entry) then settled[id] = entry end
    end
    for part, v in pairs(isTable(before.at) and before.at or {}) do
        if type(part) == "string" and (v == false or validId(v)) then at[part] = v end
    end
    for part, v in pairs(isTable(before.pending) and before.pending or {}) do
        if type(part) == "string" and v == true then pending[part] = true end
    end
    for part, v in pairs(isTable(before.due) and before.due or {}) do
        if type(part) == "string" and v == true then due[part] = true end
    end
    return settled, at, pending, due
end

-- kind: "update" | "take" | "reset" (opts.parts, the parts installed;
-- opts.rows, the plan's rows), or "capture" (opts.id, opts.entry).
-- before: { settled, at, pending, due } as they stood. Returns the new
-- settled, at and pending, nil when empty, and the new due set. A full
-- install is CompleteSetup's own write.
function ns.EUISettleRecord(kind, before, opts)
    opts = opts or {}
    local settled, at, pending, due = cleanSettle(before)
    if kind == "update" or kind == "take" or kind == "reset" then
        -- An installed part has not settled: no snapshot, and not due until
        -- the session after this one.
        for part in pairs(opts.parts or {}) do
            at[part] = false
            pending[part] = true
            due[part] = nil
        end
        -- With every row named, no part reads the snapshot for every part.
        local unnamed = not (isTable(opts.rows) and opts.rows[1])
        for _, row in ipairs(isTable(opts.rows) and opts.rows or {}) do
            if not (isTable(row) and at[row.id] ~= nil) then unnamed = true end
        end
        if not unnamed then at[ALL] = nil end
    elseif kind == "capture" and validId(opts.id) and sound(opts.entry) then
        settled[opts.id] = opts.entry
        if due[ALL] then
            -- A part named in pending but not due was installed this session.
            local named = {}
            for part in pairs(pending) do
                if part ~= ALL and not due[part] then named[part] = false end
            end
            named[ALL] = opts.id
            at = named
        else
            for part in pairs(due) do at[part] = opts.id end
        end
        for part in pairs(due) do pending[part] = nil end
        due = {}
    end
    local used = {}
    for _, v in pairs(at) do
        if v then used[v] = true end
    end
    for id in pairs(settled) do
        if not used[id] then settled[id] = nil end
    end
    return next(settled) and settled or nil, next(at) and at or nil, next(pending) and pending or nil, due
end

-- The snapshot a part is measured from, or nil: its own pointer, else the one
-- for every part not named, and only a pointer to a sound entry.
function ns.EUISettledId(rec, part)
    rec = isTable(rec) and rec or {}
    local at = isTable(rec.at) and rec.at or {}
    local id = at[part]
    if id ~= false and not validId(id) then id = at[ALL] end
    local settled = isTable(rec.settled) and rec.settled or {}
    if validId(id) and sound(settled[id]) then return id end
    return nil
end

-- "due" (waiting from an earlier session), "pending" (installed this
-- session), "settled", or nil for a part with no snapshot and none waiting.
function ns.EUISettleState(rec, due, part)
    rec = isTable(rec) and rec or {}
    local at = isTable(rec.at) and rec.at or {}
    local named = at[part] == false or validId(at[part])
    local function marked(set)
        return isTable(set) and (set[part] == true or (not named and set[ALL] == true))
    end
    if marked(due) then return "due" end
    if marked(rec.pending) then return "pending" end
    if ns.EUISettledId(rec, part) then return "settled" end
    return nil
end

-- An export leaves out a module that was not loaded, so a snapshot holds a
-- folder part only when it carries the folder.
local function holdsPart(src, row)
    if row.id == "general" or row.id == "overrides" then return true end
    return isTable(src.addons) and src.addons[row.id] ~= nil
end

-- S: the composite base with each settled part's slice from its snapshot.
-- decodedById: id -> decoded, stripped data. A part keeps O's slice with no
-- snapshot, a failed decode, no base of its own, or a folder the snapshot
-- lacks. S is O itself when no part settles, nil when O is.
function ns.EUIComposeSettled(O, rows, rec, decodedById, keyToFolder, missing)
    if O == nil then return nil end
    decodedById, missing = decodedById or {}, missing or {}
    local S = O
    for _, row in ipairs(rows or {}) do
        local id = ns.EUISettledId(rec, row.id)
        local src = id and decodedById[id]
        if isTable(src) and not missing[row.id] and holdsPart(src, row) then
            if S == O then S = ns.EUIDeepCopy(O) end
            copySlice(S, src, row, keyToFolder or {})
        end
    end
    return S
end
