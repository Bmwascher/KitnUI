-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/Bite.lua                                         ║
-- ║  Purpose: Bite Mode and Dark Cast Bar, two switches that     ║
-- ║           hold EllesmereUI cast bar settings and anchors     ║
-- ║           down and hand them back on switch-off.             ║
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

local function RefreshCastBar()
    local addon = ns.EUIAddon and ns.EUIAddon(ERB_FOLDER) or nil
    if not (addon and addon.ApplyAll) then return end
    if InCombatLockdown() then return end
    pcall(addon.ApplyAll, addon)
end

local function OverrideStore()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.GetActiveProfileData) then return nil end
    local ok, prof = pcall(EUI.GetActiveProfileData)
    if not ok or type(prof) ~= "table" then return nil end
    if type(prof.specOverrides) ~= "table" then return nil end
    return prof.specOverrides
end

-- Indices shift when an entry is removed, so the store is scanned rather than
-- remembered by position, and records key off the fkey and the map key.
local function CapturedMaps(fkey)
    local store = OverrideStore()
    if not store then return nil end
    for i = 1, #store do
        local entry = store[i]
        local values = (type(entry) == "table") and entry.values or nil
        local defaults = (type(values) == "table") and values.default or nil
        if type(defaults) == "table" and defaults[fkey] ~= nil then
            local found = { { map = defaults, key = "default" } }
            for mapKey, map in pairs(values) do
                if mapKey ~= "default" and type(map) == "table" and map[fkey] ~= nil then
                    found[#found + 1] = { map = map, key = mapKey }
                end
            end
            return found
        end
    end
    return nil
end

-- bgA is written at full opacity deliberately: Resource Bars paints its own
-- dark background that way and ignores the palette's alpha.
local function DarkValues()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.GetDarkModeFill and EUI.GetDarkModeBg) then return nil end
    local okFill, fr, fg, fb = pcall(EUI.GetDarkModeFill)
    local okBg, br, bg, bb = pcall(EUI.GetDarkModeBg)
    if not (okFill and okBg) then return nil end
    if not (fr and fg and fb and br and bg and bb) then return nil end
    return {
        classColored    = false,
        fillR           = fr,
        fillG           = fg,
        fillB           = fb,
        bgR             = br,
        bgG             = bg,
        bgB             = bb,
        bgA             = 1,
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
local function HoldKey(cast, key, value, claiming)
    local record = claiming and ns.EUISnap(DARK_SECTION, key) or ns.EUIPeekSnap(DARK_SECTION, key)
    if not record then return end
    if claiming then
        record.forced = value
    elseif record.prev == nil then
        return
    end
    ns.EUIOverride(cast, record, key, record.forced, claiming)
end

local function ReleaseKey(cast, key)
    local record = ns.EUIPeekSnap(DARK_SECTION, key)
    if not record then return end
    ns.EUIRestore(cast, record, key)
    record.forced = nil
end

local function DarkStoreKey(key, mapKey)
    return key .. FS .. mapKey
end

-- Every key this control owns gets the same store treatment spell text gets,
-- so a captured colour key cannot be banked out of a spec and returned after
-- switch-off.
local function ApplyDarkStore(key, value, on, claiming)
    local fkey = ERB_FOLDER .. FS .. "castBar" .. PS .. key
    local maps = CapturedMaps(fkey)
    if not maps then return end
    for i = 1, #maps do
        local slot = maps[i]
        local record = (on and claiming)
            and ns.EUISnap(DARK_SECTION, DarkStoreKey(key, slot.key))
            or ns.EUIPeekSnap(DARK_SECTION, DarkStoreKey(key, slot.key))
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

-- Both branches call the store half explicitly. The ON branch computes the
-- palette values only when claiming; afterwards HoldKey re-reads what it
-- recorded. texture is conditional, but once claimed it is re-asserted like
-- any other owned key, because HoldKey reads the record rather than
-- re-testing the live value.
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
                HoldKey(cast, key, value, claiming)
                ApplyDarkStore(key, value, true, claiming)
            end
        end
    else
        for _, key in ipairs(DARK_CAST_BAR_KEYS) do
            ApplyDarkStore(key, nil, false, false)
            if cast then ReleaseKey(cast, key) end
        end
    end
    RefreshCastBar()
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
        -- Re-read inside the closure. A profile switch re-points db.profile in
        -- place, so a table captured before a fight writes the old profile.
        local settings = ns.EUISettings and ns.EUISettings() or nil
        if not settings then return end
        settings.darkCastBar = on and true or false
        ApplyDarkCastBar(on, true)
        ns.EUIRebuildForOwnership("General")
    end, true, false) then
        print(ns.title .. ": Dark Cast Bar is queued until you leave combat. Switching, importing or deleting a profile, or changing spec, before then cancels it.")
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

    RefreshCastBar()
end

local CAST_KEY, POWER_KEY = "ERB_CastBar", "ERB_Power"

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

local function ApplyAnchors(on, claiming)
    if not ns.BaselineLive() then return false end
    local anchors = AnchorDB()
    if not anchors then return false end

    if on then
        local castRecord = claiming and ns.EUISnap(BITE_SECTION, CAST_KEY)
            or ns.EUIPeekSnap(BITE_SECTION, CAST_KEY)
        local powerRecord = claiming and ns.EUISnap(BITE_SECTION, POWER_KEY)
            or ns.EUIPeekSnap(BITE_SECTION, POWER_KEY)
        ns.EUIOverride(anchors, castRecord, CAST_KEY,
            Forced(Original(castRecord, anchors[CAST_KEY]), "CDM_cooldowns", "TOP", true), claiming)
        ns.EUIOverride(anchors, powerRecord, POWER_KEY,
            Forced(Original(powerRecord, anchors[POWER_KEY]), CAST_KEY, "TOP", false), claiming)
    else
        local castRecord = ns.EUIPeekSnap(BITE_SECTION, CAST_KEY)
        local powerRecord = ns.EUIPeekSnap(BITE_SECTION, POWER_KEY)
        if castRecord then ns.EUIRestore(anchors, castRecord, CAST_KEY) end
        if powerRecord then ns.EUIRestore(anchors, powerRecord, POWER_KEY) end
    end

    local EUI = _G.EllesmereUI
    if EUI and EUI.ReapplyAllUnlockAnchors and not InCombatLockdown() then
        pcall(EUI.ReapplyAllUnlockAnchors)
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
        Refuse("Bite Mode is queued until you leave combat. Switching, importing or deleting a profile, or changing spec, before then cancels it.")
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
