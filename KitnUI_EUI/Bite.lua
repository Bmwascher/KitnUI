-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/Bite.lua                                         ║
-- ║  Purpose: Bite Mode switches, registered as scalars in       ║
-- ║           Core.lua's DEFAULTS.profile.                       ║
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
    if not profile then return end
    local cast = profile.castBar
    if type(cast) ~= "table" then return end

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
            ReleaseKey(cast, key)
        end
    end
    RefreshCastBar()
end

-- The re-apply asserts only while this control's own state is on. That is
-- what makes a user's decision to switch it off survive a login: nothing
-- re-acquires it.
function ns.SetDarkCastBar(on)
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
