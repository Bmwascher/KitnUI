-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/Bite.lua                                         ║
-- ║  Purpose: Bite Mode, Dark Cast Bar and the resource bar      ║
-- ║           seam colour, which hold EllesmereUI settings       ║
-- ║           and anchors down and hand them back on             ║
-- ║           switch-off.                                        ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

local ERB_FOLDER = "EllesmereUIResourceBars"
local FS, PS = "\31", "\30"

-- Passes on nil, which means the baseline layout is live and also covers a
-- profile with no override store at all. An EllesmereUI without the reader is
-- treated as baseline, because it has no other layout to be on.
local function BaselineLive()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.SpecOverrides_UnlockActive) then return true end
    local ok, active = pcall(EUI.SpecOverrides_UnlockActive)
    if not ok then return true end
    return active == nil
end

ns.BaselineLive = BaselineLive

-- The toggle has already animated to the new position and never re-reads its
-- getter, so a refused click keeps showing a state that did not happen without
-- a rebuild.
local function Refuse(message)
    print(ns.title .. ": " .. message)
    local EUI = _G.EllesmereUI
    if EUI and EUI.RefreshPage then pcall(EUI.RefreshPage, EUI, true) end
end

-- An override editing session watches every value write, and reads a forced
-- value that matches the group's default as the user reverting it, which
-- deletes the captured override outright. Nothing recorded here could put that
-- back, so both switches stand down until the session ends.
local function EditSessionActive()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.SpecOverrides_EditSessionActive) then return false end
    local ok, active = pcall(EUI.SpecOverrides_EditSessionActive)
    return (ok and active) and true or false
end

local EDIT_SESSION_REFUSAL =
    "Cannot change this while an override editing session is open, because the "
    .. "session would take the change as your own edit. Close it and try again."

local combatWatcher
local combatPending = {}

local function DropClaims()
    local kept = {}
    for i = 1, #combatPending do
        if not combatPending[i].claiming then kept[#kept + 1] = combatPending[i] end
    end
    combatPending = kept
end

local function RunOutOfCombat(fn, claiming, superseding)
    if not InCombatLockdown() then
        fn()
        return true
    end
    if superseding then DropClaims() end
    combatPending[#combatPending + 1] = { run = fn, claiming = claiming and true or false }
    if not combatWatcher then
        combatWatcher = CreateFrame("Frame")
        combatWatcher:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local queued = combatPending
            combatPending = {}
            for i = 1, #queued do
                pcall(queued[i].run)
            end
        end)
    end
    combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    return false
end

local function CastProfile(forWriting)
    local profile = ns.EUIProfile and ns.EUIProfile(ERB_FOLDER) or nil
    if profile then return profile end
    if forWriting then return nil end
    return ns.EUIStoredProfile and ns.EUIStoredProfile(ERB_FOLDER) or nil
end

local function RefreshResourceBars()
    local addon = ns.EUIAddon and ns.EUIAddon(ERB_FOLDER) or nil
    if not (addon and addon.ApplyAll) then return end
    if InCombatLockdown() then return end
    pcall(addon.ApplyAll, addon)
end

local function ProfileRoot()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.GetActiveProfileData) then return nil end
    local ok, prof = pcall(EUI.GetActiveProfileData)
    if not ok or type(prof) ~= "table" then return nil end
    return prof
end

-- Indices shift when an entry is removed, so a store is scanned rather than
-- remembered by position, and records key off the fkey and the map key.
--
-- EVERY capturing entry is collected, not the first. The resource bar migration
-- builds one entry per differing spec and copies the same default and every spec
-- map into each of them, so one fkey can live in several entries at once; the
-- host harvests and applies all of them, and a slot this scan skips is one the
-- release cannot hand back. The first entry keeps the bare map key so records
-- already saved in the field keep their names, and later ones take the entry's
-- group id, which those migrated entries always carry and never share.
local function CollectMaps(store, prefix, fkey, found)
    if type(store) ~= "table" then return found end
    local seen = 0
    for i = 1, #store do
        local entry = store[i]
        local values = (type(entry) == "table") and entry.values or nil
        local defaults = (type(values) == "table") and values.default or nil
        if type(defaults) == "table" and defaults[fkey] ~= nil then
            seen = seen + 1
            local tag = prefix
            if seen > 1 then
                local id = entry.group
                if type(id) ~= "string" and type(id) ~= "number" then id = seen end
                tag = prefix .. "e" .. tostring(id) .. FS
            end
            found = found or {}
            found[#found + 1] = { map = defaults, key = tag .. "default" }
            for mapKey, map in pairs(values) do
                if mapKey ~= "default" and type(map) == "table" and map[fkey] ~= nil then
                    found[#found + 1] = { map = map, key = tag .. mapKey }
                end
            end
        end
    end
    return found
end

-- Both override stores, because the conditional one banks live values at its own
-- transitions exactly as the spec store does and can hold a key the spec store
-- has not captured. A forced value left uncovered there is adopted as the user's
-- own with nothing left to give back. Only the conditional map keys carry a
-- prefix, so the two stores cannot share a record and the spec-side record names
-- are the ones already in the field.
local COND_PREFIX = "cond" .. FS

local function CapturedMaps(fkey)
    local prof = ProfileRoot()
    if not prof then return nil end
    local found = CollectMaps(prof.specOverrides, "", fkey, nil)
    return CollectMaps(prof.condOverrides, COND_PREFIX, fkey, found)
end

-- The fill follows EllesmereUI's own Dark Mode colour, so the cast bar matches
-- whatever the rest of the dark frames are using. The background does not, and
-- is a fixed panel grey instead: Dark Mode's own background swatch
-- is a mid grey at full opacity, and a cast bar needs its unfilled track one step
-- lighter than the fill, not several, or the track disappears into the bar.
local BG_LEVEL, BG_ALPHA = 0x24 / 255, 0.9

local function DarkValues()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.GetDarkModeFill) then return nil end
    local ok, fr, fg, fb = pcall(EUI.GetDarkModeFill)
    if not ok then return nil end
    if not (fr and fg and fb) then return nil end
    return {
        classColored    = false,
        fillR           = fr,
        fillG           = fg,
        fillB           = fb,
        bgR             = BG_LEVEL,
        bgG             = BG_LEVEL,
        bgB             = BG_LEVEL,
        bgA             = BG_ALPHA,
        gradientEnabled = false,
    }
end

local DARK_CAST_BAR_KEYS = {
    "classColored", "fillR", "fillG", "fillB",
    "bgR", "bgG", "bgB", "bgA",
    "gradientEnabled", "texture",
}

local DARK_SECTION = "darkcastbar"

-- claiming is true only on a user click. A re-apply must never create a
-- record, because only at the click can this addon honestly say what the
-- value was before it touched anything.
--
-- The forced value is stored ON the record at claim time and re-read from
-- there afterwards. It cannot be recomputed on a re-apply: the palette is
-- read live, and the spec freezes these colours at the click. record.prev
-- belongs to ns.EUIOverride; record.forced is this file's own field and is
-- inert to EUIHolds, which tests prev only.
local function HoldKey(tbl, section, key, value, claiming)
    local record = claiming and ns.EUISnap(section, key) or ns.EUIPeekSnap(section, key)
    if not record then return end
    if claiming then
        record.forced = value
    elseif record.prev == nil then
        return
    end
    ns.EUIOverride(tbl, record, key, record.forced, claiming)
end

local function ReleaseKey(tbl, section, key)
    local record = ns.EUIPeekSnap(section, key)
    if not record then return end
    ns.EUIRestore(tbl, record, key)
    record.forced = nil
end

local function DarkStoreKey(key, mapKey)
    return key .. FS .. mapKey
end

-- Every key this control owns gets the same store treatment spell text gets,
-- so a captured colour key cannot be banked out of a spec and returned after
-- switch-off.
local function ApplyDarkStore(section, path, key, value, on, claiming)
    local fkey = ERB_FOLDER .. FS .. path .. PS .. key
    local maps = CapturedMaps(fkey)
    if not maps then return end
    for i = 1, #maps do
        local slot = maps[i]
        local record = (on and claiming)
            and ns.EUISnap(section, DarkStoreKey(key, slot.key))
            or ns.EUIPeekSnap(section, DarkStoreKey(key, slot.key))
        if record then
            if on then
                ns.EUIOverride(slot.map, record, fkey, value, claiming)
            else
                ns.EUIRestore(slot.map, record, fkey)
            end
        end
    end
end

local TEXTURE_FKEY = ERB_FOLDER .. FS .. "castBar" .. PS .. "texture"

-- The texture test reads the captured values too, not only the live one.
-- Opening EllesmereUI's panel while the current spec belongs to an override
-- group swaps the default values in live and puts the spec's own values back
-- on close. The click happens inside that panel, so the live texture at claim
-- time can be the default while the spec's captured value is "blizzard".
-- Testing the live value alone would skip the claim, and the spec's
-- "blizzard" would return on close with nothing owning it, which defeats the
-- colour write entirely.
local function TextureNeedsClaim(cast)
    if cast.texture == "blizzard" then return true end
    local maps = CapturedMaps(TEXTURE_FKEY)
    if not maps then return false end
    for i = 1, #maps do
        if maps[i].map[TEXTURE_FKEY] == "blizzard" then return true end
    end
    return false
end

-- The ON branch computes the palette values only when claiming; afterwards
-- HoldKey re-reads what it recorded. texture is conditional at claim time, but
-- once claimed it is re-asserted like any other owned key, because HoldKey
-- reads the record rather than re-testing the live value.
local function ApplyDarkCastBar(on, claiming)
    local profile = CastProfile(on)
    -- Nothing is forced into a module that is not loaded. The OFF path
    -- continues without a live table, because the captured store still holds
    -- values that have to be handed back.
    if on and not profile then return end
    local cast = profile and profile.castBar or nil
    if type(cast) ~= "table" then cast = nil end
    if on and not cast then return end

    if on then
        local values = claiming and DarkValues() or nil
        if claiming and not values then return end
        for _, key in ipairs(DARK_CAST_BAR_KEYS) do
            local claim = true
            local value
            if claiming then
                value = values[key]
                if key == "texture" then
                    value = "none"
                    claim = TextureNeedsClaim(cast)
                end
            else
                -- The store half has no record of its own to read the frozen
                -- value from, and a nil write here would DELETE the captured
                -- key rather than force it.
                local held = ns.EUIPeekSnap(DARK_SECTION, key)
                value = held and held.forced
                claim = (value ~= nil)
            end
            if claim then
                HoldKey(cast, DARK_SECTION, key, value, claiming)
                ApplyDarkStore(DARK_SECTION, "castBar", key, value, true, claiming)
            end
        end
    else
        for _, key in ipairs(DARK_CAST_BAR_KEYS) do
            ApplyDarkStore(DARK_SECTION, "castBar", key, nil, false, false)
            if cast then ReleaseKey(cast, DARK_SECTION, key) end
        end
    end
    RefreshResourceBars()
end

-- The re-apply asserts only while this control's own state is on. That is
-- what makes a user's decision to switch it off survive a login: nothing
-- re-acquires it.
function ns.SetDarkCastBar(on)
    if EditSessionActive() then
        Refuse(EDIT_SESSION_REFUSAL)
        return
    end
    if not RunOutOfCombat(function()
        -- Tested again here, not only before queueing: a session can be opened
        -- during the fight this click is waiting out, and the queued write
        -- would land inside it.
        if EditSessionActive() then
            Refuse(EDIT_SESSION_REFUSAL)
            return
        end
        -- Re-read inside the closure. A profile switch re-points db.profile in
        -- place, so a table captured before a fight writes the old profile.
        local settings = ns.EUISettings and ns.EUISettings() or nil
        if not settings then return end
        settings.darkCastBar = on and true or false
        ApplyDarkCastBar(on, true)
        ns.EUIRebuildForOwnership("General")
    end, true, false) then
        print(ns.title .. ": Dark Cast Bar is queued until you leave combat. Switching, importing or deleting a profile, changing spec, or changing EllesmereUI's Dark Mode, before then cancels it.")
    end
end

-- The elseif branch is NOT optional. ns.EUIResetAll turns every switch off and
-- THEN runs the re-applies, so that each page hands its originals back while
-- the snapshots still exist. A callback that does nothing when its switch is
-- off would leave EllesmereUI holding forced colours with nothing left that
-- remembers the originals.
ns.EUIRegisterReapply(function()
    RunOutOfCombat(function()
        if ns.DarkCastBarEnabled() then
            ApplyDarkCastBar(true, false)
        elseif ns.EUIHolds("darkcastbar") then
            ApplyDarkCastBar(false, false)
        end
    end, false, true)
end)

local BITE_SECTION = "bite"
local SPELL_TEXT_FKEY = ERB_FOLDER .. FS .. "castBar" .. PS .. "showSpellText"

local GAP_SECTION = "darkresourcegap"
local GAP_PATH = "secondary"
local GAP_KEYS = { "gapColorEnabled", "gapR", "gapG", "gapB", "gapA" }

-- With the bar's own gap colour switched off there is no seam to colour: at full
-- fill opacity the gap layer is not drawn at all and the black showing through is
-- the bar's backdrop, and below it the module paints the gaps black itself while
-- its dark theme is on. Either way the colour keys are unreachable until that
-- switch is on, so this control owns the switch as well as the colour.
local GAP_LEVEL = 0x4f / 255
local GAP_VALUES = {
    gapColorEnabled = true,
    gapR = GAP_LEVEL,
    gapG = GAP_LEVEL,
    gapB = GAP_LEVEL,
    gapA = 1,
}

-- Shared with the switches on the General page and with the reset, which have
-- to refuse before they change anything at all: a write inside an override
-- editing session is taken by EllesmereUI as the user's own edit and cannot be
-- handed back.
function ns.EUIEditSessionActive()
    return EditSessionActive()
end

function ns.EUIRefuseIfEditSession()
    if not EditSessionActive() then return false end
    Refuse(EDIT_SESSION_REFUSAL)
    return true
end

-- The module's own dark switch for this bar, read from the shared provider list
-- rather than tracked here, so the two can never disagree. nil means unreadable,
-- which is not the same as off and must never release a hold.
local function ResourceBarsDark()
    local EUI = _G.EllesmereUI
    local toggles = EUI and EUI._darkModeToggles
    if type(toggles) ~= "table" then return nil end
    for i = 1, #toggles do
        local provider = toggles[i]
        if type(provider) == "table" and provider.id == "resourceBars"
           and type(provider.isOn) == "function" then
            local ok, on = pcall(provider.isOn)
            if not ok then return nil end
            return on and true or false
        end
    end
    return nil
end

function ns.ApplyResourceGap(on, claiming)
    if EditSessionActive() then
        if claiming then Refuse(EDIT_SESSION_REFUSAL) end
        return
    end
    local profile = CastProfile(on)
    if on and not profile then return end
    local bar = profile and profile.secondary or nil
    if type(bar) ~= "table" then bar = nil end
    if on and not bar then return end

    for _, key in ipairs(GAP_KEYS) do
        if on then
            HoldKey(bar, GAP_SECTION, key, GAP_VALUES[key], claiming)
            ApplyDarkStore(GAP_SECTION, GAP_PATH, key, GAP_VALUES[key], true, claiming)
        else
            ApplyDarkStore(GAP_SECTION, GAP_PATH, key, nil, false, false)
            if bar then ReleaseKey(bar, GAP_SECTION, key) end
        end
    end

    RefreshResourceBars()
end

-- spellTextSide is never touched here: EllesmereUI's own dropdown writes both
-- keys, and this control owns the visibility half only, so a user's chosen
-- side survives the round trip.
local function ApplySpellText(on, claiming)
    local profile = CastProfile(on)
    if on and not profile then return end
    if profile and type(profile.castBar) == "table" then
        local record = (on and claiming)
            and ns.EUISnap(BITE_SECTION, "showSpellText")
            or ns.EUIPeekSnap(BITE_SECTION, "showSpellText")
        if record then
            if on then
                ns.EUIOverride(profile.castBar, record, "showSpellText", false, claiming)
            else
                ns.EUIRestore(profile.castBar, record, "showSpellText")
            end
        end
    end

    local maps = CapturedMaps(SPELL_TEXT_FKEY)
    if maps then
        for i = 1, #maps do
            local slot = maps[i]
            local key = "spellText" .. FS .. slot.key
            local record = (on and claiming)
                and ns.EUISnap(BITE_SECTION, key) or ns.EUIPeekSnap(BITE_SECTION, key)
            if record then
                if on then
                    ns.EUIOverride(slot.map, record, SPELL_TEXT_FKEY, false, claiming)
                else
                    ns.EUIRestore(slot.map, record, SPELL_TEXT_FKEY)
                end
            end
        end
    end

    RefreshResourceBars()
end

local CAST_KEY, POWER_KEY = "ERB_CastBar", "ERB_Power"
local REPOSITIONED_KEYS = { CAST_KEY, POWER_KEY }

local function AnchorDB()
    local db = _G.EllesmereUIDB
    if type(db) ~= "table" then return nil end
    if type(db.unlockAnchors) ~= "table" then return nil end
    return db.unlockAnchors
end

local function Forced(previous, target, side, flipSign)
    local offsetY = tonumber(previous and previous.offsetY) or 0
    if flipSign then offsetY = -offsetY end
    return {
        target  = target,
        side    = side,
        offsetX = tonumber(previous and previous.offsetX) or 0,
        offsetY = offsetY,
    }
end

-- The entry as it was before this switch touched it. No record yet means the
-- live entry is still the user's own, which is the claiming call. A recorded
-- absence means there was no entry, so the forced one starts from zero offsets.
-- Reading the LIVE entry on a re-apply would negate an already-negated offset.
local function Original(record, live)
    if record == nil or record.prev == nil then return live end
    if record.prev == ns.EUI_ABSENT then return nil end
    return record.prev
end

local function CopyAnchorEntry(entry)
    if type(entry) ~= "table" then return nil end
    local copy = {}
    for k, v in pairs(entry) do
        if type(v) == "table" then
            local inner = {}
            for ik, iv in pairs(v) do inner[ik] = iv end
            copy[k] = inner
        else
            copy[k] = v
        end
    end
    return copy
end

-- The stored baseline layer, not the live table, is what a later layer change
-- re-applies. EllesmereUI skips banking live into it while a settings view or
-- an editing session is open, so a release that touched only the live table can
-- be undone by the next layer change with the records already consumed. Only
-- the release mirrors: while the switch is on, the re-apply re-asserts anyway.
-- A profile with no group layers has no such store and nothing to mirror.
local function MirrorToBaselineLayer(anchors, key)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.GetActiveProfileData) then return end
    local ok, prof = pcall(EUI.GetActiveProfileData)
    if not ok or type(prof) ~= "table" then return end
    local store = prof.specUnlockOverrides
    local layer = (type(store) == "table") and store.baselineLayout or nil
    if type(layer) ~= "table" or type(layer.anchors) ~= "table" then return end
    layer.anchors[key] = CopyAnchorEntry(anchors[key])
end

-- Put the recorded value back WITHOUT releasing the record. The switch is still
-- on and still owns the key; this spec simply does not want the forced state.
-- ns.EUIRestore would clear the record, and the next spec that does want the
-- forced state would then have nothing left to compute it from.
local function RevertLive(tbl, record, key)
    if not (tbl and record and key) then return end
    if record.prev == nil then return end
    if record.prev == ns.EUI_ABSENT then
        tbl[key] = nil
    else
        tbl[key] = record.prev
    end
end

-- A spec override group can store its own position for an element in
-- `unlockOverrideAnchors[element][gid]`, and while that group is active
-- EllesmereUI positions the element from that entry and ignores the shared link
-- outright. A group pinning the cast bar above the class resource bar therefore
-- survives this switch's re-target and closes a loop: cast bar above class
-- resource, class resource above power, power above cast bar. Every layout pass
-- raises all three, so the stack walks off the top of the screen. Holding the
-- whole per-element table down for as long as the switch is on removes the loop.
-- The group's captured VALUES are untouched, so what it changes about the bar's
-- appearance survives; only its position yields.
local function OverrideAnchorStore()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.GetActiveProfileData) then return nil end
    local ok, prof = pcall(EUI.GetActiveProfileData)
    if not ok or type(prof) ~= "table" then return nil end
    if type(prof.unlockOverrideAnchors) ~= "table" then return nil end
    return prof.unlockOverrideAnchors
end

-- Keyed apart from the link records: the two halves hold different stores under
-- the same element name, and one snapshot cannot describe both.
local function OverrideSnapKey(key)
    return "override:" .. key
end

-- The record first, the live store only when nothing is held: while the switch
-- holds this element down the live store reads empty, and the test below still
-- has to know what was there.
local function OverrideEntriesFor(key)
    local record = ns.EUIPeekSnap(BITE_SECTION, OverrideSnapKey(key))
    if record and record.prev ~= nil then
        if record.prev == ns.EUI_ABSENT then return nil end
        return (type(record.prev) == "table") and record.prev or nil
    end
    local store = OverrideAnchorStore()
    local entries = store and store[key]
    return (type(entries) == "table") and entries or nil
end

-- Which specs get the bar swap. Not a shipped spec list: the specs that want it
-- are the ones an override group already repositions the cast bar for, which is
-- the only thing they share (the set spans casters and two melee specs) and
-- which follows the user's own groups when they edit them. Every other spec
-- keeps its cast bar where it is and takes the appearance half only.
--
-- Mirrors EllesmereUI's own owner lookup: the first group in creation order
-- that both stores a position for this element and lists the current spec.
local function SwapWanted()
    local entries = OverrideEntriesFor(CAST_KEY)
    if not entries then return false end
    local EUI = _G.EllesmereUI
    if not EUI or not EUI.GetActiveProfileData then return false end
    local specID = EUI._specID
    if (not specID or specID == 0) and EUI._RefreshSpecID then
        pcall(EUI._RefreshSpecID)
        specID = EUI._specID
    end
    if not specID or specID == 0 then return false end
    local ok, prof = pcall(EUI.GetActiveProfileData)
    if not ok or type(prof) ~= "table" then return false end
    local groups = prof.specOverrideGroups
    if type(groups) ~= "table" then return false end
    for _, group in ipairs(groups) do
        if type(group) == "table" and entries[group.id] then
            for _, sid in ipairs(group.specs or {}) do
                if sid == specID then return true end
            end
        end
    end
    return false
end

local function ApplyOverrideAnchors(on, swap, claiming)
    local store = OverrideAnchorStore()
    if not store then return end
    for i = 1, #REPOSITIONED_KEYS do
        local key = REPOSITIONED_KEYS[i]
        local snapKey = OverrideSnapKey(key)
        if on then
            local record = claiming and ns.EUISnap(BITE_SECTION, snapKey)
                or ns.EUIPeekSnap(BITE_SECTION, snapKey)
            ns.EUIOverride(store, record, key, nil, claiming)
            if not swap then RevertLive(store, record, key) end
        else
            local record = ns.EUIPeekSnap(BITE_SECTION, snapKey)
            if record then ns.EUIRestore(store, record, key) end
        end
    end
end

local function ApplyAnchors(on, claiming)
    if not ns.BaselineLive() then return false end
    local anchors = AnchorDB()
    if not anchors then return false end

    -- Answered before the hold, which empties the store the test reads.
    local swap = on and SwapWanted()

    ApplyOverrideAnchors(on, swap, claiming)

    if on then
        local castRecord = claiming and ns.EUISnap(BITE_SECTION, CAST_KEY)
            or ns.EUIPeekSnap(BITE_SECTION, CAST_KEY)
        local powerRecord = claiming and ns.EUISnap(BITE_SECTION, POWER_KEY)
            or ns.EUIPeekSnap(BITE_SECTION, POWER_KEY)
        -- Recorded on every spec, forced only on the ones that want the swap:
        -- the record is what a later spec computes its forced value from, so it
        -- is claimed at the click whether or not this spec uses it.
        ns.EUIOverride(anchors, castRecord, CAST_KEY,
            Forced(Original(castRecord, anchors[CAST_KEY]), "CDM_cooldowns", "TOP", true), claiming)
        ns.EUIOverride(anchors, powerRecord, POWER_KEY,
            Forced(Original(powerRecord, anchors[POWER_KEY]), CAST_KEY, "TOP", false), claiming)
        -- Gated on the record, like the release below. Mirroring without one
        -- would write the stored baseline from a value this switch does not own,
        -- and an absent live entry would delete the layer's entry outright.
        if not swap then
            if castRecord and castRecord.prev ~= nil then
                RevertLive(anchors, castRecord, CAST_KEY)
                MirrorToBaselineLayer(anchors, CAST_KEY)
            end
            if powerRecord and powerRecord.prev ~= nil then
                RevertLive(anchors, powerRecord, POWER_KEY)
                MirrorToBaselineLayer(anchors, POWER_KEY)
            end
        end
    else
        local castRecord = ns.EUIPeekSnap(BITE_SECTION, CAST_KEY)
        local powerRecord = ns.EUIPeekSnap(BITE_SECTION, POWER_KEY)
        -- Ownership is `prev ~= nil`, never the record's existence: a release
        -- clears the value and leaves the table behind, so testing the table
        -- would let a later pass mirror a key this switch has already given up.
        if castRecord and castRecord.prev ~= nil then
            ns.EUIRestore(anchors, castRecord, CAST_KEY)
            MirrorToBaselineLayer(anchors, CAST_KEY)
        end
        if powerRecord and powerRecord.prev ~= nil then
            ns.EUIRestore(anchors, powerRecord, POWER_KEY)
            MirrorToBaselineLayer(anchors, POWER_KEY)
        end
    end

    local EUI = _G.EllesmereUI
    if EUI and not InCombatLockdown() then
        -- Releases every element the override store stopped holding, repainting
        -- it through its normal owner before the links re-assert.
        if EUI._ReapplyOverrideAnchors then pcall(EUI._ReapplyOverrideAnchors) end
        if EUI.ReapplyAllUnlockAnchors then pcall(EUI.ReapplyAllUnlockAnchors) end
    end
    return true
end

-- ns.EUIPeekSnap never seeds a record, so this is side-effect free.
local function BiteHoldsAnchors()
    local record = ns.EUIPeekSnap(BITE_SECTION, CAST_KEY)
    return (record and record.prev ~= nil) and true or false
end

ns.BiteHoldsAnchors = BiteHoldsAnchors

local function CommitBite(on)
    if EditSessionActive() then
        Refuse(EDIT_SESSION_REFUSAL)
        return
    end
    if on and not ns.BaselineLive() then
        Refuse("Bite Mode cannot be turned on while a spec override layout is active. Switch back to your normal layout and try again.")
        return
    end

    local settings = ns.EUISettings and ns.EUISettings() or nil
    if not settings then return end

    if on then
        -- The anchor half runs FIRST and its answer decides the rest. It
        -- returns false when EllesmereUI's layout store is unreadable, and a
        -- state written before that answer would leave the row reading on
        -- while owning and applying nothing.
        if not ApplyAnchors(true, true) then
            Refuse("Bite Mode could not read EllesmereUI's saved layout. Reload and try again.")
            return
        end
        local record = ns.EUISnap(BITE_SECTION, "darkWasOn")
        -- Written once per activation. Two clicks can queue in one fight, and
        -- the second would otherwise record the state the FIRST one produced,
        -- which is Dark Cast Bar already on.
        if record and record.darkWasOn == nil then
            record.darkWasOn = ns.DarkCastBarEnabled()
        end
    else
        ApplyAnchors(false, true)
    end

    settings.bite = on and true or false
    ApplySpellText(on, true)

    if on then
        if not ns.DarkCastBarEnabled() then ns.SetDarkCastBar(true) end
    else
        local record = ns.EUIPeekSnap(BITE_SECTION, "darkWasOn")
        local wasOn = record and record.darkWasOn
        if wasOn == false and ns.DarkCastBarEnabled() then ns.SetDarkCastBar(false) end
        if record then record.darkWasOn = nil end
    end

    ns.EUIRebuildForOwnership("General")
end

function ns.SetBiteMode(on)
    if not RunOutOfCombat(function() CommitBite(on) end, true, false) then
        Refuse("Bite Mode is queued until you leave combat. Switching, importing or deleting a profile, changing spec, or changing EllesmereUI's Dark Mode, before then cancels it.")
    end
end

-- The anchor half is gated inside ApplyAnchors; the spell text half is not,
-- because a captured setting is re-asserted on every spec change regardless
-- of layer and must be re-held.
--
-- The elseif branch restores BOTH halves, not just the anchors. A reset turns
-- the switch off and then runs the re-applies so each page hands its
-- originals back while the snapshots still exist; restoring only the anchors
-- would leave the spell text forced with nothing left that remembers the
-- original.
ns.EUIRegisterReapply(function()
    RunOutOfCombat(function()
        if ns.BiteEnabled() then
            ApplyAnchors(true, false)
            ApplySpellText(true, false)
        elseif ns.EUIHolds("bite") then
            ApplyAnchors(false, false)
            ApplySpellText(false, false)
            -- Released here too, so the next activation samples Dark Cast Bar
            -- afresh instead of reading a marker from the previous one.
            local record = ns.EUIPeekSnap(BITE_SECTION, "darkWasOn")
            if record then record.darkWasOn = nil end
        end
    end, false, true)
end)

-- The ownership sentence on the General page is a string fixed when the row is
-- built, and it reads BOTH the module's dark switch and whether this control is
-- holding. Either can move without that page's own click path running, so both
-- are tracked here. The FIRST observation rebuilds as well: nothing orders the
-- login re-apply ahead of the page being built, so a page built first with a
-- since-changed input would otherwise keep its sentence until an input moved
-- again.
local gapTipSeen, gapTipDark, gapTipHeld = false, nil, false

ns.EUIRegisterReapply(function()
    RunOutOfCombat(function()
        -- Only an explicit false releases. An unreadable switch is not an off
        -- switch, and releasing on one would hand the seam back to black.
        local dark = ResourceBarsDark()
        if dark == true then
            ns.ApplyResourceGap(true, false)
        elseif dark == false and ns.EUIHolds(GAP_SECTION) then
            ns.ApplyResourceGap(false, false)
        end

        local held = ns.EUIHolds(GAP_SECTION)
        if not gapTipSeen or dark ~= gapTipDark or held ~= gapTipHeld then
            gapTipSeen, gapTipDark, gapTipHeld = true, dark, held
            ns.EUIRebuildForOwnership("General")
        end
    end, false, true)
end)

local function Settings()
    return ns.EUISettings and ns.EUISettings() or nil
end

function ns.BiteEnabled()
    local s = Settings()
    return (s and s.bite) and true or false
end

function ns.DarkCastBarEnabled()
    local s = Settings()
    return (s and s.darkCastBar) and true or false
end
