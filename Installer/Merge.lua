-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Merge.lua                                                   ║
-- ║  Purpose: The three-way profile merge for the EllesmereUI    ║
-- ║           update: pure functions over decoded payload data.  ║
-- ║           Nothing here touches a frame or an EllesmereUI     ║
-- ║           call; the flow in Update.lua supplies the inputs.  ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- Relative tolerance for float leaves, with a floor of 1 so values near zero
-- compare on an absolute 1e-4. Integers compare exactly: integer-valued keys
-- are identifiers (group ids, spell ids, counters) and never drift.
local FLOAT_TOLERANCE = 1e-4

local function isTable(v) return type(v) == "table" end
local function isInteger(v) return type(v) == "number" and math.floor(v) == v end

local function same(a, b)
    if a == b then return true end
    local ta, tb = type(a), type(b)
    if ta == "number" and tb == "number" then
        if isInteger(a) and isInteger(b) then return false end
        return math.abs(a - b) <= FLOAT_TOLERANCE * math.max(1, math.abs(a), math.abs(b))
    end
    if ta ~= "table" or tb ~= "table" then return false end
    for k, v in pairs(a) do
        if not same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
ns.EUISame = same

local function deepCopy(v)
    if not isTable(v) then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = deepCopy(x) end
    return c
end
ns.EUIDeepCopy = deepCopy

local function joinPath(path, k)
    local part = type(k) == "number" and ("[" .. k .. "]") or tostring(k)
    if path == "" then return part end
    return path .. "." .. part
end

-- The keys the importer takes as one set. Decided whole, never walked.
local OV_KEYS = {
    "specOverrides", "specOverrideGroups", "specOverrideNextId",
    "condOverrides", "condOverrideGroups", "condOverrideNextId",
    "specUnlockOverrides", "condUnlockOverrides",
    "specBmOverrides", "condBmOverrides", "specDmOverrides", "condDmOverrides",
    "unlockOverrideAnchors",
}
ns.EUI_OV_KEYS = OV_KEYS

-- Top-level keys the walk never visits: decided by the special-key rules
-- below, or transport and account data the exporter strips too.
local SPECIAL = {
    unlockLayout = true, unlockLayoutMeta = true, assignedSpecs = true,
    _migrations = true, uiScale = true, applyUIScale = true,
    blizzSkinGlobals = true, applyBlizzSkinGlobals = true,
    clickCast = true, spellAssignments = true, trackedBuffBars = true,
    tbbPositions = true, _importEstablishPending = true, layoutExcluded = true,
    condAppliedGid = true,
    overridesIncluded = true, overridesExcluded = true, partialImport = true,
}
for _, key in ipairs(OV_KEYS) do SPECIAL[key] = true end

-- Levels whose children the importer takes or inherits whole and never deletes.
local ROOT_UNITS = { fonts = true, customColors = true, darkMode = true, euiAccent = true }
local UNIT_PARENTS = { addons = true, cdmSpells = true }

-- Leaves the importer overwrites with the class colour when it activates the
-- import with Resource Bars loaded; excluded from the count then.
local HEALTH_PATH = "^addons%.EllesmereUIResourceBars%.health%.(%w+)$"
local HEALTH_LEAVES = { customColored = true, fillR = true, fillG = true, fillB = true }

-- Dense numeric-keyed tables whose index carries meaning: a slot another
-- setting points at, a colour's channels, a group number, or a map keyed by a
-- small counter id. Compacting one would rename its entries. Keyed by path
-- prefix; `*` matches one path component. Frozen from the enumeration of the
-- shipped payload; every other numeric-keyed table in it is an ordered list
-- whose entries carry their own identity, or is keyed by spell id.
ns.EUI_SEQUENCE_EXEMPT = {
    ["addons.EllesmereUICooldownManager.cdmBars.bars"] = true,
    ["addons.EllesmereUICooldownManager.spec.*.mappings"] = true,
    ["addons.EllesmereUIQuickdraw.palettes"] = true,
    ["addons.EllesmereUIQuickdraw.selectColor"] = true,
    ["addons.EllesmereUIRaidFrames.visibleGroups"] = true,
    ["addons.EllesmereUIRaidFrames.bm2.specs.*.inds.*.filters"] = true,
    ["addons.EllesmereUIRaidFrames.dmDebuff.fxList.*.filters"] = true,
    ["addons.EllesmereUIUnitFrames.playerAuraBars.customBuffBars.*.filters"] = true,
    ["addons.EllesmereUIUnitFrames.playerAuraBars.customDebuffBars.*.filters"] = true,
    ["addons.EllesmereUIUnitFrames.playerAuraBars.pabSpecBars.*.buffBars.*.filters"] = true,
}

local function isSequence(t)
    if t == nil then return true end
    local n = 0
    for k in pairs(t) do
        if not isInteger(k) or k < 1 then return false end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local exemptPatterns = {}

-- One anchored pattern per prefix: magic characters escaped, `*` widened to a
-- whole component. A path beneath the prefix is tested with its tail cut.
local function exemptPattern(prefix)
    local pattern = exemptPatterns[prefix]
    if not pattern then
        pattern = prefix:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%1"):gsub("%*", "[^.]+")
        pattern = "^" .. pattern .. "$"
        exemptPatterns[prefix] = pattern
    end
    return pattern
end

local function isExempt(path)
    for prefix in pairs(ns.EUI_SEQUENCE_EXEMPT) do
        local pattern = exemptPattern(prefix)
        local head = path
        while head do
            if head:find(pattern) then return true end
            head = head:match("^(.+)%.[^.]+$")
        end
    end
    return false
end

local function compact(t)
    local idx = {}
    for k in pairs(t) do idx[#idx + 1] = k end
    table.sort(idx)
    local out = {}
    for i, k in ipairs(idx) do out[i] = t[k] end
    return out
end

local function leaf(ctx, merged, k, ov, nv, pv, path)
    local report = ctx.report
    if same(ov, nv) then
        merged[k] = pv
        if not same(pv, nv) then report.kept = report.kept + 1 end
        return
    end
    merged[k] = nv
    report.applied = report.applied + 1
    if not same(pv, ov) and not same(pv, nv) and not ctx.excluded(path) then
        report.conflicts[#report.conflicts + 1] = path
    end
end

local function unionKeys(o, n, p)
    local keys = {}
    if o then for k in pairs(o) do keys[k] = true end end
    if n then for k in pairs(n) do keys[k] = true end end
    if p then for k in pairs(p) do keys[k] = true end end
    return keys
end

local walk

-- One inherited unit: absent from N is inherited (nothing counted); absent from
-- P is taken whole from N when Kitn changed it, else inherited.
local function unit(ctx, merged, k, ov, nv, pv, path)
    if nv == nil then
        merged[k] = nil
    elseif pv == nil then
        if same(ov, nv) then
            merged[k] = nil
        else
            merged[k] = deepCopy(nv)
            ctx.report.applied = ctx.report.applied + 1
        end
    elseif (ov ~= nil and not isTable(ov)) or (nv ~= nil and not isTable(nv))
        or (pv ~= nil and not isTable(pv)) then
        leaf(ctx, merged, k, ov, nv, pv, path)
    else
        local sub = walk(ctx, ov, nv, pv, path, false)
        if isSequence(ov) and isSequence(nv) and isSequence(pv) and not isExempt(path) then
            sub = compact(sub)
        end
        merged[k] = sub
    end
end

function walk(ctx, o, n, p, path, unitsBelow)
    local merged = {}
    for k in pairs(unionKeys(o, n, p)) do
        local ov, nv, pv = o and o[k], n and n[k], p and p[k]
        local kp = joinPath(path, k)
        local skip = path == "" and SPECIAL[k]
        if skip then
            merged[k] = nil
        elseif unitsBelow or (path == "" and ROOT_UNITS[k]) then
            unit(ctx, merged, k, ov, nv, pv, kp)
        elseif (ov ~= nil and not isTable(ov)) or (nv ~= nil and not isTable(nv))
            or (not isTable(ov) and not isTable(nv)) then
            leaf(ctx, merged, k, ov, nv, pv, kp)
        elseif pv ~= nil and not isTable(pv) then
            leaf(ctx, merged, k, ov, nv, pv, kp)
        elseif pv == nil and same(ov, nv) then
            merged[k] = nil
        else
            local sub = walk(ctx, ov, nv, pv, kp, path == "" and UNIT_PARENTS[k] or false)
            if next(sub) == nil and nv == nil then
                merged[k] = nil
            else
                if isSequence(ov) and isSequence(nv) and isSequence(pv) and not isExempt(kp) then
                    sub = compact(sub)
                end
                merged[k] = sub
            end
        end
    end
    return merged
end

-- Every payload key present on any side that names a bar-layout child, with
-- the folder that owns the child, from the caller's key-to-folder table.
local LAYOUT_MAPS = { "anchors", "widthMatch", "heightMatch" }
ns.EUI_LAYOUT_MAPS = LAYOUT_MAPS

local function layoutMap(d, map)
    local ul = d and d.unlockLayout
    return isTable(ul) and isTable(ul[map]) and ul[map] or nil
end

-- Each size-match map's extras: pixels added to the matched size, keyed by
-- the child like its link and meaningful only beside that link.
local MATCH_EXTRAS = { widthMatch = "widthMatchExtra", heightMatch = "heightMatchExtra" }
ns.EUI_MATCH_EXTRAS = MATCH_EXTRAS

-- A side's extra for a child it links in `map`; nil without that link.
local function extraOf(d, map, child)
    local links, extras = layoutMap(d, map), layoutMap(d, MATCH_EXTRAS[map])
    if not (links and extras and links[child] ~= nil) then return nil end
    return extras[child]
end

-- Layout entries are leaves compared whole, walked last, over children whose
-- owner is present in merged.addons; the root, its four maps and the two
-- extras maps always exist. An extra follows the link the leaf wrote, and a
-- player's extra lost to Kitn's link counts when it was the player's change.
local function mergeLayout(ctx, O, N, P, merged)
    local out = { anchors = {}, widthMatch = {}, heightMatch = {}, phantomBounds = {},
        widthMatchExtra = {}, heightMatchExtra = {} }
    local addons = isTable(merged.addons) and merged.addons or {}
    for _, map in ipairs(LAYOUT_MAPS) do
        local om, nm, pm = layoutMap(O, map), layoutMap(N, map), layoutMap(P, map)
        local xmap = MATCH_EXTRAS[map]
        for child in pairs(unionKeys(om, nm, pm)) do
            local owner = ctx.keyToFolder[child]
            if owner and addons[owner] ~= nil then
                local ov, nv, pv = om and om[child], nm and nm[child], pm and pm[child]
                leaf(ctx, out[map], child, ov, nv, pv, joinPath(joinPath("unlockLayout", map), child))
                if xmap then
                    local ox, nx, px = extraOf(O, map, child), extraOf(N, map, child), extraOf(P, map, child)
                    if same(ov, nv) then
                        out[xmap][child] = px
                    else
                        out[xmap][child] = nx
                        if pv ~= nil and not same(px, ox) and not same(px, nx) then
                            ctx.report.conflicts[#ctx.report.conflicts + 1] = joinPath(joinPath("unlockLayout", xmap), child)
                        end
                    end
                end
            end
        end
    end
    merged.unlockLayout = out
end

-- The no-base copy can carry an entry for a module its addons table lacks.
local function pruneLayout(ctx, merged)
    local ul = merged.unlockLayout
    if not isTable(ul) then return end
    local addons = isTable(merged.addons) and merged.addons or {}
    local function prune(map)
        if not isTable(ul[map]) then return end
        for child in pairs(ul[map]) do
            local owner = ctx.keyToFolder[child]
            if not (owner and addons[owner] ~= nil) then ul[map][child] = nil end
        end
    end
    for _, map in ipairs(LAYOUT_MAPS) do
        prune(map)
        if MATCH_EXTRAS[map] then prune(MATCH_EXTRAS[map]) end
    end
end

-- The override set with the masks applied: the three spec stores' `active`
-- pointer, the unlock baseline's link maps and match extras (the importer
-- rewrites them from the merged layout), and the two id counters.
local LAYER_STORES = { specUnlockOverrides = true, specBmOverrides = true, specDmOverrides = true }
local BASELINE_LINKS = { anchors = true, widthMatch = true, heightMatch = true,
    widthMatchExtra = true, heightMatchExtra = true }
local COUNTERS = { specOverrideNextId = true, condOverrideNextId = true }
local UNLOCK_STORES = { specUnlockOverrides = true, condUnlockOverrides = true }

local function maskedSet(d)
    local set = {}
    for _, key in ipairs(OV_KEYS) do
        local v = d and d[key]
        if COUNTERS[key] then
            v = nil
        elseif LAYER_STORES[key] and isTable(v) then
            local c = {}
            for k2, v2 in pairs(v) do
                if k2 ~= "active" then c[k2] = v2 end
            end
            if key == "specUnlockOverrides" and isTable(c.baselineLayout) then
                local b = {}
                for k3, v3 in pairs(c.baselineLayout) do
                    if not BASELINE_LINKS[k3] then b[k3] = v3 end
                end
                c.baselineLayout = b
            end
            v = c
        end
        set[key] = v
    end
    return set
end
ns.EUIMaskedOverrideSet = maskedSet

-- An unlock layer's element entries carry live sizes and exist only for the
-- elements the character registers, so two sets are compared over the
-- elements both hold, sizes ignored; positions and everything else compare.
-- An entry banked raw (`rawPos`) holds a stored offset where the other form
-- holds an on-screen one, so a raw entry against the other form is the same.
local function elemsSame(a, b)
    if not (isTable(a) and isTable(b)) then return true end
    for key, ea in pairs(a) do
        local eb = b[key]
        if eb ~= nil then
            if not (isTable(ea) and isTable(eb)) then
                if not same(ea, eb) then return false end
            elseif (ea.rawPos == true) == (eb.rawPos == true) then
                for k in pairs(unionKeys(ea, eb)) do
                    if k ~= "w" and k ~= "h" and not same(ea[k], eb[k]) then return false end
                end
            end
        end
    end
    return true
end

-- A layer's match extras compare with an absent table read as empty, so a
-- layer written before extras existed matches one holding none.
local LAYER_EXTRAS = { widthMatchExtra = true, heightMatchExtra = true }
local NO_EXTRAS = {}

local function layerSame(a, b)
    if not (isTable(a) and isTable(b)) then return same(a, b) end
    for k in pairs(unionKeys(a, b)) do
        if k == "elems" then
            if not elemsSame(a.elems, b.elems) then return false end
        elseif LAYER_EXTRAS[k] then
            if not same(a[k] or NO_EXTRAS, b[k] or NO_EXTRAS) then return false end
        elseif not same(a[k], b[k]) then
            return false
        end
    end
    return true
end

local function unlockStoreSame(a, b)
    if not (isTable(a) and isTable(b)) then return same(a, b) end
    for k in pairs(unionKeys(a, b)) do
        if k == "baselineLayout" then
            if not layerSame(a[k], b[k]) then return false end
        elseif k == "layouts" and isTable(a[k]) and isTable(b[k]) then
            for gid in pairs(unionKeys(a[k], b[k])) do
                if not layerSame(a[k][gid], b[k][gid]) then return false end
            end
        elseif not same(a[k], b[k]) then
            return false
        end
    end
    return true
end

local function setsSame(a, b)
    for _, key in ipairs(OV_KEYS) do
        if UNLOCK_STORES[key] then
            if not unlockStoreSame(a[key], b[key]) then return false end
        elseif not same(a[key], b[key]) then
            return false
        end
    end
    return true
end
ns.EUIOverrideSetsSame = setsSame

local function copyOverrides(from, merged)
    for _, key in ipairs(OV_KEYS) do
        merged[key] = deepCopy(from and from[key])
    end
end

local function decideOverrides(ctx, O, N, P, merged)
    local mO, mN, mP = maskedSet(O), maskedSet(N), maskedSet(P)
    if setsSame(mO, mN) then
        copyOverrides(P, merged)
        ctx.report.overrideSet = next(mP) and "player" or "none"
        return
    end
    copyOverrides(N, merged)
    ctx.report.overrideSet = "kitn"
    if not setsSame(mP, mO) and not setsSame(mP, mN) then
        ctx.report.conflicts[#ctx.report.conflicts + 1] = "Spec Overrides"
    end
end

local SCALE_MIN, SCALE_MAX = 0.40, 1.15

local function specialKeys(ctx, O, N, P, merged)
    merged.assignedSpecs = deepCopy(P and P.assignedSpecs)
    merged._migrations = isTable(N._migrations) and deepCopy(N._migrations) or nil
    -- The applied conditional group is a pointer the activation re-establishes;
    -- taken as the install takes it.
    merged.condAppliedGid = N.condAppliedGid
    merged.unlockLayoutMeta = nil
    local nu = N.uiScale
    local ou = O and O.uiScale
    if type(nu) == "number" and nu >= SCALE_MIN and nu <= SCALE_MAX and not same(ou, nu) then
        merged.uiScale = nu
        local pu = P and P.uiScale
        if not same(pu, ou) and not same(pu, nu) then
            ctx.report.conflicts[#ctx.report.conflicts + 1] = "uiScale"
        end
    else
        merged.uiScale = nil
    end
    merged.applyUIScale = nil
    merged.blizzSkinGlobals = nil
    merged.applyBlizzSkinGlobals = nil
    merged.clickCast = nil
    merged.spellAssignments = nil
    merged.trackedBuffBars = nil
    merged.tbbPositions = nil
    merged._importEstablishPending = nil
    merged.layoutExcluded = nil
    -- A subset export's stamps would make the importer keep the player's
    -- override stores; the merged payload is always a full one.
    merged.overridesIncluded = nil
    merged.overridesExcluded = nil
    merged.partialImport = nil
end

-- opts.keyToFolder: child key -> owning folder for every layout key on any side.
-- opts.healthReset: true when the importer's activation will reset the health
-- colour, so those leaves are never counted.
function ns.EUIThreeWayMerge(O, N, P, opts)
    opts = opts or {}
    local report = { conflicts = {}, kept = 0, applied = 0, noBase = O == nil }
    local keyToFolder = opts.keyToFolder or {}
    local ctx = {
        report = report,
        keyToFolder = keyToFolder,
        excluded = function(path)
            if not opts.healthReset then return false end
            local leafName = path:match(HEALTH_PATH)
            return leafName ~= nil and HEALTH_LEAVES[leafName] == true
        end,
    }
    local merged
    if O == nil then
        merged = deepCopy(N)
        pruneLayout(ctx, merged)
        report.overrideSet = next(maskedSet(N)) and "kitn" or "none"
    else
        merged = walk(ctx, O, N, P, "", false)
        mergeLayout(ctx, O, N, P, merged)
        decideOverrides(ctx, O, N, P, merged)
    end
    specialKeys(ctx, O, N, P, merged)
    return merged, report
end
