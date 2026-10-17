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

local function RunOutOfCombat(fn)
    if not InCombatLockdown() then
        fn()
        return
    end
    combatPending[#combatPending + 1] = fn
    if not combatWatcher then
        combatWatcher = CreateFrame("Frame")
        combatWatcher:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local queued = combatPending
            combatPending = {}
            for i = 1, #queued do
                pcall(queued[i])
            end
        end)
    end
    combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
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
-- release cannot hand back.
--
-- The entries are deliberately NOT told apart. Nothing durable identifies one:
-- an entry's group id is REASSIGNED to a surviving holder when a group is
-- deleted, so two entries can end up carrying the same id, and a store index
-- moves when an entry is removed. So the maps that share a map key share one
-- record instead. That rests on those maps holding the same original, which
-- SlotsDisagree below is what keeps true.
local function AddSlot(found, index, key, map)
    local slot = index[key]
    if not slot then
        slot = { key = key, maps = {} }
        index[key] = slot
        found[#found + 1] = slot
    end
    slot.maps[#slot.maps + 1] = map
end

local function CollectMaps(store, prefix, fkey, found, index)
    if type(store) ~= "table" then return end
    for i = 1, #store do
        local entry = store[i]
        local values = (type(entry) == "table") and entry.values or nil
        local defaults = (type(values) == "table") and values.default or nil
        if type(defaults) == "table" and defaults[fkey] ~= nil then
            AddSlot(found, index, prefix .. "default", defaults)
            for mapKey, map in pairs(values) do
                if mapKey ~= "default" and type(map) == "table" and map[fkey] ~= nil then
                    AddSlot(found, index, prefix .. mapKey, map)
                end
            end
        end
    end
end

-- A slot's membership is not fixed for the life of a hold. Changing a group's
-- specs creates a map that was not there at the claim, and the user can author a
-- value in it: that map is not this addon's to write or to hand back, and giving
-- it the recorded original would destroy what they wrote.
--
-- So only the maps still carrying what was forced -- or already back at the
-- original -- are treated as ours. Records claimed before this test existed carry
-- no forced value and take every map, which is what they did before.
local function OursInSlot(record, fkey, map)
    if record.forced == nil then return true end
    local current = map[fkey]
    return current == record.forced or current == record.prev
end

-- The whole slot goes back before the record is cleared. ns.EUIRestore clears
-- the recorded original on its way out, so restoring map by map would give the
-- first map its value and leave every other one forced.
local function RestoreSlot(slot, record, fkey)
    if record.prev == nil then return end

    local mine = {}
    for i = 1, #slot.maps do
        local map = slot.maps[i]
        if OursInSlot(record, fkey, map) then mine[#mine + 1] = map end
    end

    -- Nothing left that this addon put there. The record still has to go, or the
    -- switch reads as holding something forever.
    if #mine == 0 then
        record.prev = nil
        record.forced = nil
        return
    end

    for i = 1, #mine - 1 do
        if record.prev == ns.EUI_ABSENT then
            mine[i][fkey] = nil
        else
            mine[i][fkey] = record.prev
        end
    end
    ns.EUIRestore(mine[#mine], record, fkey)
    record.forced = nil
end

-- The claim takes the whole slot: every map in it is a claim-time member. A
-- re-apply takes only what is still ours, so a map that joined since keeps
-- whatever the user put in it.
local function HoldSlot(slot, record, fkey, value, claiming)
    if not claiming and record.prev == nil then return end

    local wrote = false
    for i = 1, #slot.maps do
        local map = slot.maps[i]
        if claiming or OursInSlot(record, fkey, map) then
            ns.EUIOverride(map, record, fkey, value, claiming)
            wrote = true
        end
    end

    -- The marker follows what was actually written, and only after the whole
    -- slot: moved inside the loop it would change what the maps after it count
    -- as ours. It has to follow, because the palette is read afresh on every
    -- claim and a slot that was out of the store during one of them would
    -- otherwise be testing against a colour no map holds any more, and the
    -- release would disown its own work. A record with no marker is one claimed
    -- before this test existed and must keep none.
    if wrote and record.forced ~= nil then record.forced = value end
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
    local found, index = {}, {}
    CollectMaps(prof.specOverrides, "", fkey, found, index)
    CollectMaps(prof.condOverrides, COND_PREFIX, fkey, found, index)
    if #found == 0 then return nil end
    return found
end

-- One record per slot rests on the maps in it holding the same original, which
-- is how they start and how every ordinary harvest keeps them: the host derives
-- all of them from the same live value. The group-membership editor is the one
-- path that breaks it. Adding a spec to a group seeds that spec's map from the
-- group's own entry, and it SKIPS entries whose group already conflicts with the
-- new membership, so one map key can end up holding two different values.
--
-- A claim over a disagreeing slot cannot be given back: one recorded original
-- would be handed to both maps and the other one destroyed. So the claim is
-- refused, before anything at all is written. The OFF path never refuses -- it
-- returns what was taken, which is the claim-time value, and a slot that
-- disagrees now was equal then.
local function SlotsDisagree(fkeys, keep)
    for i = 1, #fkeys do
        local fkey = fkeys[i]
        local slots = CapturedMaps(fkey)
        if slots then
            for j = 1, #slots do
                if not keep or keep(fkey, slots[j].key) then
                    local maps = slots[j].maps
                    local first = maps[1][fkey]
                    for k = 2, #maps do
                        if maps[k][fkey] ~= first then return true end
                    end
                end
            end
        end
    end
    return false
end

local DIVERGENT_REFUSAL =
    "Cannot take this over, because your spec overrides hold two different saved "
    .. "values for the same setting and turning this off again could only give "
    .. "one of them back. Make those overrides agree and try again."

local function RefuseIfDivergent(fkeys, keep)
    if not SlotsDisagree(fkeys, keep) then return false end
    ns.EUIRefuse(DIVERGENT_REFUSAL, true)
    return true
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

local DARK_CAST_FKEYS = {}
for i = 1, #DARK_CAST_BAR_KEYS do
    DARK_CAST_FKEYS[i] = ERB_FOLDER .. FS .. "castBar" .. PS .. DARK_CAST_BAR_KEYS[i]
end

-- The export paths a held note covers, for the per-part count. A note keyed
-- "<key>\31<slot>" holds that key in an override slot.
local function DescribeResourceKeys(section, path, keys)
    local owned = {}
    for i = 1, #keys do owned[keys[i]] = true end
    ns.EUIRegisterHeld(section, function(noteKey, _, add)
        local key = noteKey:match("^([^\31]+)\31") or noteKey
        if not owned[key] then return end
        if key == noteKey then
            add("addons." .. ERB_FOLDER .. "." .. path .. "." .. key)
        else
            add(ns.EUI_HELD_FKEY .. ERB_FOLDER .. FS .. path .. PS .. key)
        end
    end)
end

DescribeResourceKeys(DARK_SECTION, "castBar", DARK_CAST_BAR_KEYS)

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

-- While the switch is on this addon owns the key and the re-apply re-asserts it,
-- which is what the ownership sentence on the page promises. This test is for the
-- other window: EllesmereUI's own per-module dark switches turn the bar light
-- again without releasing anything, and until the next trigger the user is
-- looking at a settings row that invites them to set a colour of their own.
-- Handing the recorded original back over that would destroy what they chose, so
-- only a value still carrying what was forced is taken back. The record goes
-- either way, or the switch would read as holding something it does not.
local function ReleaseKey(tbl, section, key)
    local record = ns.EUIPeekSnap(section, key)
    if not record then return end
    if OursInSlot(record, key, tbl) then
        ns.EUIRestore(tbl, record, key)
    else
        record.prev = nil
    end
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
                if claiming then record.forced = value end
                HoldSlot(slot, record, fkey, value, claiming)
            else
                RestoreSlot(slot, record, fkey)
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
        local slot = maps[i]
        for j = 1, #slot.maps do
            if slot.maps[j][TEXTURE_FKEY] == "blizzard" then return true end
        end
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
--
-- Refused in combat rather than queued, here and in ns.SetBiteMode.
-- EllesmereUI's toggle sends the opposite of what its getter reads, and a
-- queued click leaves the switch unchanged until the fight ends, so a second
-- click in the same fight would repeat the first instead of undoing it. The
-- host gates its own ways into the panel in combat, but not every one, so
-- these switches can be clicked mid-fight.
function ns.SetDarkCastBar(on)
    if ns.EUIRefuseInCombat("Dark Cast Bar", true) then return end
    if EditSessionActive() then
        ns.EUIRefuse(EDIT_SESSION_REFUSAL, true)
        return
    end
    if on and RefuseIfDivergent(DARK_CAST_FKEYS) then return end
    local settings = ns.EUISettings and ns.EUISettings() or nil
    if not settings then return end
    settings.darkCastBar = on and true or false
    ApplyDarkCastBar(on, true)
    ns.EUIRebuildForOwnership("General")
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
    end)
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
local GAP_LEVEL = 0xcc / 255
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
    ns.EUIRefuse(EDIT_SESSION_REFUSAL, true)
    return true
end

local GAP_FKEYS = {}
for i = 1, #GAP_KEYS do
    GAP_FKEYS[i] = ERB_FOLDER .. FS .. GAP_PATH .. PS .. GAP_KEYS[i]
end

DescribeResourceKeys(GAP_SECTION, GAP_PATH, GAP_KEYS)

-- Every reason this claim must be refused, gathered for the switch on the
-- General page: it has to answer before EllesmereUI's own dark switch is
-- written, and that write cannot be taken back.
function ns.EUIRefuseResourceGapClaim()
    if ns.EUIRefuseIfEditSession() then return true end
    return RefuseIfDivergent(GAP_FKEYS)
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
        if claiming then ns.EUIRefuse(EDIT_SESSION_REFUSAL, true) end
        return
    end
    if on and claiming and RefuseIfDivergent(GAP_FKEYS) then return end
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
                    if claiming then record.forced = false end
                    HoldSlot(slot, record, SPELL_TEXT_FKEY, false, claiming)
                else
                    RestoreSlot(slot, record, SPELL_TEXT_FKEY)
                end
            end
        end
    end

    RefreshResourceBars()
end

local CAST_KEY, POWER_KEY = "ERB_CastBar", "ERB_Power"
local REPOSITIONED_KEYS = { CAST_KEY, POWER_KEY }

local CDM_FOLDER = "EllesmereUICooldownManager"
local BUFF_OFFSET_KEY = "addOffsetY"
local BUFF_OFFSET_PREFIX = "buffOffset" .. FS

-- Buff offset records name a bar by its key: deleting a bar shifts every later
-- index, so the fkey is rebuilt from the current index on each pass.
local function BuffOffsetFKey(index)
    return CDM_FOLDER .. FS .. "cdmBars" .. PS .. "bars" .. PS .. tostring(index) .. PS .. BUFF_OFFSET_KEY
end

-- The stored profile is read on the release path only, where a switched-off
-- module still holds values that have to be handed back.
local function CdmBars(forWriting)
    local profile = ns.EUIProfile and ns.EUIProfile(CDM_FOLDER) or nil
    if not profile and not forWriting then
        profile = ns.EUIStoredProfile and ns.EUIStoredProfile(CDM_FOLDER) or nil
    end
    local cdm = (type(profile) == "table") and profile.cdmBars or nil
    local bars = (type(cdm) == "table") and cdm.bars or nil
    return (type(bars) == "table") and bars or nil
end

local function BarIndexByKey(bars, barKey)
    if not (bars and barKey) then return nil end
    for i = 1, #bars do
        local bar = bars[i]
        if type(bar) == "table" and bar.key == barKey then return i end
    end
    return nil
end

-- "buffOffset\31<bar>\31<spec>" holds one override slot.
local function ParseBuffOffsetKey(noteKey)
    if type(noteKey) ~= "string" then return nil end
    if noteKey:sub(1, #BUFF_OFFSET_PREFIX) ~= BUFF_OFFSET_PREFIX then return nil end
    return noteKey:sub(#BUFF_OFFSET_PREFIX + 1):match("^([^\31]+)\31(.+)$")
end

-- darkWasOn remembers a switch state, not a setting, so it holds no path.
ns.EUIRegisterHeld(BITE_SECTION, function(noteKey, note, add)
    if noteKey == "showSpellText" then
        add("addons." .. ERB_FOLDER .. ".castBar.showSpellText")
    elseif noteKey:match("^spellText\31") then
        add(ns.EUI_HELD_FKEY .. SPELL_TEXT_FKEY)
    elseif noteKey == CAST_KEY or noteKey == POWER_KEY then
        add("unlockLayout.anchors." .. noteKey)
    elseif noteKey == "override:" .. CAST_KEY or noteKey == "override:" .. POWER_KEY then
        add("unlockOverrideAnchors." .. noteKey:sub(#"override:" + 1))
    else
        local barKey = ParseBuffOffsetKey(noteKey)
        local index = BarIndexByKey(CdmBars(false), barKey)
        -- While the panel is open the maps carry the player's own value again,
        -- so a record put back for it holds nothing.
        if not index or (type(note) == "table" and note.shown) then return end
        add(ns.EUI_HELD_FKEY .. BuffOffsetFKey(index))
    end
end)

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
-- The set is every spec listed by a group that stores a position for this
-- element; SwapWanted tests the current spec against it.
local function SwapSpecSet()
    local set = {}
    local entries = OverrideEntriesFor(CAST_KEY)
    local prof = entries and ProfileRoot() or nil
    local groups = prof and prof.specOverrideGroups
    if type(groups) ~= "table" then return set end
    for _, group in ipairs(groups) do
        if type(group) == "table" and entries[group.id] then
            for _, sid in ipairs(group.specs or {}) do set[sid] = true end
        end
    end
    return set
end

local function CurrentSpecID()
    local EUI = _G.EllesmereUI
    if not EUI then return nil end
    local specID = EUI._specID
    if (not specID or specID == 0) and EUI._RefreshSpecID then
        pcall(EUI._RefreshSpecID)
        specID = EUI._specID
    end
    if not specID or specID == 0 then return nil end
    return specID
end

local function SwapWanted()
    local specID = CurrentSpecID()
    return (specID ~= nil and SwapSpecSet()[specID]) and true or false
end

-- Buff offset: on a swap spec, a Cooldown Manager bar standing on the power bar
-- or cast bar loses its vertical Additional Bar Offset, which only existed to
-- clear the cast bar the swap moves away.
--
-- Only an offset the spec store captures is held, and only in the swap specs'
-- own maps: the shared default and the conditional maps are read by every
-- spec, and an uncaptured offset is one live value every spec shares.
--
-- The hold lasts only while EllesmereUI's panel is closed. Every editor action
-- that banks or copies these values (an override session, Remove Override, a
-- bar delete, the Default view) happens with the panel open, so its opening
-- puts the claim-time values back and its close forces 0 again into the maps
-- that still carry them. Any other value is the player's, and that slot is
-- let go.
local BUFF_OFFSET_FORCED = 0
local STACK_KEYS = { [CAST_KEY] = true, [POWER_KEY] = true }
local CHAIN_LIMIT = 8

local function UsableBarKey(key)
    return type(key) == "string" and key ~= "" and not key:find(FS, 1, true)
end

local function SlotRecordKey(barKey, slotKey)
    return BUFF_OFFSET_PREFIX .. barKey .. FS .. slotKey
end

local function ClearRecord(record)
    record.prev = nil
    record.forced = nil
    record.fkey = nil
    record.shown = nil
end

local function Nonzero(v)
    return type(v) == "number" and v ~= 0
end

local function SlotNonzero(slot, fkey)
    for i = 1, #slot.maps do
        if Nonzero(slot.maps[i][fkey]) then return true end
    end
    return false
end

local function SlotCarries(slot, fkey, value)
    for i = 1, #slot.maps do
        if slot.maps[i][fkey] == value then return true end
    end
    return false
end

-- EllesmereUI's own slider stores 0 as absent.
local function LiveReadsForced(v)
    return v == nil or v == BUFF_OFFSET_FORCED
end

-- Stops at the first stack element, so the swap re-targeting those two links
-- does not change the answer.
local function StandsOnStack(anchors, barKey)
    local key = "CDM_" .. barKey
    local seen = {}
    for _ = 1, CHAIN_LIMIT do
        if seen[key] then return false end
        seen[key] = true
        local link = anchors[key]
        local target = (type(link) == "table") and link.target or nil
        if type(target) ~= "string" then return false end
        if STACK_KEYS[target] then return true end
        key = target
    end
    return false
end

-- Keyed by spec id, without the default slot.
local function SpecSlots(fkey)
    local prof = ProfileRoot()
    local found = {}
    if prof then CollectMaps(prof.specOverrides, "", fkey, found, {}) end
    local slots = {}
    for i = 1, #found do
        if found[i].key ~= "default" then slots[found[i].key] = found[i] end
    end
    return slots
end

-- Read at the click only. A bar is judged by its swap specs' maps, never by
-- live: the click is made inside the panel, where live holds the shared
-- default. A bar the spec store does not capture has no slots and is left
-- alone.
local function BuffOffsetCandidates()
    local list = {}
    local anchors = AnchorDB()
    local bars = CdmBars(true)
    if not (anchors and bars) then return list end
    local swapSpecs = SwapSpecSet()
    for i = 1, #bars do
        local bar = bars[i]
        if type(bar) == "table" and UsableBarKey(bar.key) and StandsOnStack(anchors, bar.key) then
            local fkey = BuffOffsetFKey(i)
            local claim = {}
            for slotKey, slot in pairs(SpecSlots(fkey)) do
                local specID = tonumber(slotKey)
                if specID and swapSpecs[specID] and SlotNonzero(slot, fkey) then
                    claim[#claim + 1] = slot
                end
            end
            if #claim > 0 then
                list[#list + 1] = { key = bar.key, fkey = fkey, slots = claim }
            end
        end
    end
    return list
end

-- Only the slots the claim would take are compared: the default and the
-- conditional maps are never written, so their copies may disagree.
local function BuffOffsetRefuseIfDivergent(candidates)
    local fkeys, claimed = {}, {}
    for i = 1, #candidates do
        local c = candidates[i]
        local set = {}
        for j = 1, #c.slots do set[c.slots[j].key] = true end
        fkeys[#fkeys + 1] = c.fkey
        claimed[c.fkey] = set
    end
    if #fkeys == 0 then return false end
    return RefuseIfDivergent(fkeys, function(fkey, slotKey)
        return claimed[fkey][slotKey] == true
    end)
end

-- A missing reader counts as the view being up, which writes nothing.
local function CapturedLiveWritable()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.SpecOverrides_ViewActive) then return false end
    local ok, active = pcall(EUI.SpecOverrides_ViewActive)
    return (ok and not active) and true or false
end

-- The resolver overlays the applied condition's values on keys the spec store
-- does not capture, so it is read only for a bar whose own spec slot was held,
-- where the spec value always wins.
local function EffectiveValue(fkey)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.SpecOverrides_PeekEffectiveValues) then return nil, false end
    local ok, map = pcall(EUI.SpecOverrides_PeekEffectiveValues, CDM_FOLDER)
    if not ok or type(map) ~= "table" then return nil, false end
    local value = map[fkey]
    if value == nil then return nil, false end
    if value == EUI.SPECOV_NIL then return nil, true end
    return value, true
end

-- Walking the notes rather than the bars lets a pass clear a record whose
-- bar or map has gone.
local function HeldByBar()
    local byBar = {}
    local notes = ns.EUIPeekNotes(BITE_SECTION)
    if not notes then return byBar end
    for noteKey, record in pairs(notes) do
        local barKey, slotKey = ParseBuffOffsetKey(noteKey)
        if barKey and type(record) == "table" and record.prev ~= nil then
            local held = byBar[barKey]
            if not held then
                held = { slots = {} }
                byBar[barKey] = held
            end
            held.slots[slotKey] = record
        end
    end
    return byBar
end

-- For the open panel: the claim-time value goes back into every map still
-- carrying the forced one, and the record stays.
local function PutBackSlot(slot, record, fkey)
    if record.shown then return end
    for i = 1, #slot.maps do
        local map = slot.maps[i]
        if map[fkey] == BUFF_OFFSET_FORCED then map[fkey] = record.prev end
    end
    record.shown = true
end

-- The close. Any map no longer carrying the claim-time value was set in the
-- panel, and the whole slot is let go: its copies share one record, so holding
-- the others would make the player's value look like this switch's.
local function ReassertSlot(slot, record, fkey)
    if not record.shown then
        HoldSlot(slot, record, fkey, BUFF_OFFSET_FORCED, false)
        return
    end
    for i = 1, #slot.maps do
        if slot.maps[i][fkey] ~= record.prev then
            ClearRecord(record)
            return
        end
    end
    for i = 1, #slot.maps do slot.maps[i][fkey] = BUFF_OFFSET_FORCED end
    record.shown = nil
end

-- mode is "held" (switch on, panel closed), "shown" (switch on, panel open) or
-- "off" (the release).
local function SettleBar(bar, fkey, held, mode, applied, specID)
    local slots = SpecSlots(fkey)
    local ownKey = specID and tostring(specID) or nil
    local own = ownKey and held.slots[ownKey] or nil
    local ownSlot = own and slots[ownKey] or nil
    -- Read before the loop below can let the record go or put its maps back.
    local ownPrev = ownSlot and own.prev or nil
    local ownWasHeld = ownSlot and not own.shown

    for slotKey, record in pairs(held.slots) do
        local slot = slots[slotKey]
        if not slot then
            ClearRecord(record)
        elseif mode == "off" then
            -- With the panel open the maps already carry the original or the
            -- player's value, so the release only lets go.
            if record.shown then ClearRecord(record) else RestoreSlot(slot, record, fkey) end
        else
            record.fkey = fkey
            if mode == "shown" then PutBackSlot(slot, record, fkey) else ReassertSlot(slot, record, fkey) end
        end
    end

    if not CapturedLiveWritable() then return false end
    local live = bar[BUFF_OFFSET_KEY]
    if mode == "held" and applied then
        if ownSlot and own.prev ~= nil and SlotCarries(ownSlot, fkey, BUFF_OFFSET_FORCED) then
            bar[BUFF_OFFSET_KEY] = BUFF_OFFSET_FORCED
        end
    elseif ownWasHeld and LiveReadsForced(live) then
        -- The 0 in live came from this switch's map. At the release live takes
        -- what the host would apply; on the opening panel it goes back before
        -- the host banks live; on a closed panel without the swap it is put
        -- back as the cast bar is.
        local value, known
        if mode == "off" then value, known = EffectiveValue(fkey) end
        if known then
            bar[BUFF_OFFSET_KEY] = value
        else
            bar[BUFF_OFFSET_KEY] = ownPrev
        end
    end
    return bar[BUFF_OFFSET_KEY] ~= live
end

-- A bar that cannot be found. With the module's data gone entirely, the maps
-- are put back at the fkey of the last pass that found the bar; a record put
-- back for the open panel already carries its value. No record is kept,
-- because nothing later could place it.
local function ReleaseUnplaced(held, useRecordedFKey)
    for slotKey, record in pairs(held.slots) do
        local slot = useRecordedFKey and not record.shown and record.fkey and SpecSlots(record.fkey)[slotKey]
        if slot then RestoreSlot(slot, record, record.fkey) else ClearRecord(record) end
    end
end

-- Set by the panel's own callbacks and read when a pass runs, not when it is
-- queued: the close's pass lands 0.1 s later, and a force close that flashes
-- the panel straight back open must not force 0 under it.
local panelShown = false
local watchingShow, watchingHide, profileHooked = false, false, false

-- Whether any profile holds a buff offset record, so the callbacks and hooks
-- do no reads or walks once the last hold is released. Counted by every pass
-- and, while it reads true, by every re-apply; it starts true so the first
-- re-apply counts the saved records.
local anyHeld = true

-- For the open panel only: after a close the pass Core queues repaints, and a
-- repaint run first at the end of a fight would show the gap until it does.
local function RepaintAnchors()
    if not panelShown then return end
    local EUI = _G.EllesmereUI
    if EUI and EUI.ReapplyAllUnlockAnchors then pcall(EUI.ReapplyAllUnlockAnchors) end
end

-- Plain table writes, done at once even in combat. The host repaints only
-- when its own view write changes a live value, and after this the offset
-- already equals the default it shows, so the repaint is this switch's; only
-- it waits out a fight.
local function PutBackAll()
    local bars = CdmBars(false)
    local specID = CurrentSpecID()
    local wrote = false
    for barKey, held in pairs(HeldByBar()) do
        local index = BarIndexByKey(bars, barKey)
        if index then
            if SettleBar(bars[index], BuffOffsetFKey(index), held, "shown", false, specID) then wrote = true end
        else
            for slotKey, record in pairs(held.slots) do
                local slot = record.fkey and SpecSlots(record.fkey)[slotKey]
                if slot then PutBackSlot(slot, record, record.fkey) end
            end
        end
    end
    if wrote then RunOutOfCombat(RepaintAnchors) end
end

-- Runs inside the panel's OnShow, a frame before EllesmereUI's Default view
-- banks live into the current spec's map, so the values are back by then.
local function OnPanelShown()
    panelShown = true
    if anyHeld then PutBackAll() end
end

-- Core's own hide callback queues the re-apply that holds again.
local function OnPanelHidden()
    panelShown = false
end

-- A switch or delete inside the open panel brings in another profile's holds
-- with no show to put them back, and the panel stays editable meanwhile. The
-- switch has already closed the Default view, so live is put back too.
local function OnProfileChanged()
    if panelShown and anyHeld then PutBackAll() end
end

-- Registered once a record exists in any profile, so a player who never uses
-- the hold adds nothing to the panel's lists. Each list is registered once,
-- even when the other fails. Without both nothing is held, and the flag is
-- kept only from then on, read from the frame as it stands because the click
-- is made inside the open panel.
local function WatchPanel()
    if watchingShow and watchingHide then return true end
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterOnShow and EUI.RegisterOnHide) then return false end
    watchingShow = watchingShow or pcall(EUI.RegisterOnShow, EUI, OnPanelShown)
    watchingHide = watchingHide or pcall(EUI.RegisterOnHide, EUI, OnPanelHidden)
    if not (watchingShow and watchingHide) then return false end
    local frame = _G.EllesmereUIFrame
    panelShown = (frame and frame.IsVisible and frame:IsVisible()) and true or false
    if not profileHooked then
        profileHooked = true
        if EUI.SwitchProfile then hooksecurefunc(EUI, "SwitchProfile", OnProfileChanged) end
        if EUI.DeleteProfile then hooksecurefunc(EUI, "DeleteProfile", OnProfileChanged) end
    end
    return true
end

-- Every profile's notes, not the active one's: a profile switched to inside
-- the open panel needs the callbacks already in place.
local function AnyBuffRecord()
    local root = ns.db and ns.db.euiSnap
    local sect = root and root[BITE_SECTION]
    if type(sect) ~= "table" then return false end
    for _, notes in pairs(sect) do
        if type(notes) == "table" then
            for noteKey, record in pairs(notes) do
                if ParseBuffOffsetKey(noteKey) and type(record) == "table" and record.prev ~= nil then
                    return true
                end
            end
        end
    end
    return false
end

-- Inside the open panel each slot keeps its value until the close. The click
-- is always made inside the panel, so holding at once with the panel closed
-- is defensive.
local function ClaimBuffOffsets(candidates)
    if #candidates == 0 or not WatchPanel() then return end
    for i = 1, #candidates do
        local c = candidates[i]
        for j = 1, #c.slots do
            local slot = c.slots[j]
            local record = ns.EUISnap(BITE_SECTION, SlotRecordKey(c.key, slot.key))
            if record then
                local value = panelShown and slot.maps[1][c.fkey] or BUFF_OFFSET_FORCED
                HoldSlot(slot, record, c.fkey, value, true)
                record.forced = BUFF_OFFSET_FORCED
                record.fkey = c.fkey
                record.shown = panelShown or nil
            end
        end
    end
end

-- Stands down inside an editing session, which would take any write as the
-- user's edit; the next re-apply catches up. Returns false only when a click
-- is refused, which happens before anything is written.
local function ApplyBuffOffset(on, claiming)
    if EditSessionActive() then return true end
    local bars = CdmBars(on)
    if on and claiming then
        if not bars then return true end
        -- ApplyAnchors refuses this click when the layout store is unreadable,
        -- so nothing is claimed or re-asserted ahead of that refusal.
        if not AnchorDB() then return true end
        local candidates = BuffOffsetCandidates()
        if BuffOffsetRefuseIfDivergent(candidates) then return false end
        ClaimBuffOffsets(candidates)
    end

    local heldBars = HeldByBar()
    if next(heldBars) == nil then
        anyHeld = AnyBuffRecord()
        return true
    end
    -- Without both panel callbacks nothing would put the originals back for
    -- the open panel, so saved holds are given back instead. Only a hold
    -- needs the live bars; a release falls back to the stored ones and then
    -- to each record's own fkey.
    local mode = "off"
    if on and WatchPanel() then mode = panelShown and "shown" or "held" end
    if mode == "off" then
        bars = bars or CdmBars(false)
    elseif not bars then
        return true
    end
    local applied = mode == "held" and ns.BaselineLive() and SwapWanted()
    local specID = CurrentSpecID()
    for barKey, held in pairs(heldBars) do
        local index = BarIndexByKey(bars, barKey)
        if index then
            SettleBar(bars[index], BuffOffsetFKey(index), held, mode, applied, specID)
        else
            ReleaseUnplaced(held, bars == nil)
        end
    end
    anyHeld = AnyBuffRecord()

    local EUI = _G.EllesmereUI
    if EUI and EUI.ReapplyAllUnlockAnchors and not InCombatLockdown() then
        pcall(EUI.ReapplyAllUnlockAnchors)
    end
    return true
end

-- The release branch is what the reset relies on: it turns the switch off and
-- then runs every re-apply while the records still exist. The idle test comes
-- before RunOutOfCombat, so a switch that is off and holds nothing queues
-- nothing in combat.
ns.EUIRegisterReapply(function()
    -- Saved records are found at the first re-apply. After that only a claim
    -- makes one, and its own pass counts it, so a false count cannot go stale;
    -- a true one is recounted here, before the idle return, because a profile
    -- delete or a reset drops notes without a pass.
    if anyHeld then anyHeld = AnyBuffRecord() end
    if anyHeld and not (watchingShow and watchingHide) then WatchPanel() end
    if not ns.BiteEnabled() and not ns.EUIHolds(BITE_SECTION) then return end
    RunOutOfCombat(function()
        if ns.BiteEnabled() then
            ApplyBuffOffset(true, false)
        elseif ns.EUIHolds(BITE_SECTION) then
            ApplyBuffOffset(false, false)
        end
    end)
end)

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
        ns.EUIRefuse(EDIT_SESSION_REFUSAL, true)
        return
    end
    -- Both key sets, before the anchors move. Bite Mode turns Dark Cast Bar on as
    -- a side effect, and a refusal discovered at that point would leave the
    -- anchors swapped and the spell text held with the switch half on.
    if on and RefuseIfDivergent({ SPELL_TEXT_FKEY }) then return end
    if on and not ns.DarkCastBarEnabled() and RefuseIfDivergent(DARK_CAST_FKEYS) then
        return
    end
    if on and not ns.BaselineLive() then
        ns.EUIRefuse("Bite Mode cannot be turned on while a spec override layout is active. Switch back to your normal layout and try again.", true)
        return
    end

    local settings = ns.EUISettings and ns.EUISettings() or nil
    if not settings then return end
    if not ApplyBuffOffset(on, true) then return end

    if on then
        -- The anchor half runs FIRST and its answer decides the rest. It
        -- returns false when EllesmereUI's layout store is unreadable, and a
        -- state written before that answer would leave the row reading on
        -- while owning and applying nothing.
        if not ApplyAnchors(true, true) then
            ns.EUIRefuse("Bite Mode could not read EllesmereUI's saved layout. Reload and try again.", true)
            return
        end
        local record = ns.EUISnap(BITE_SECTION, "darkWasOn")
        -- Written once per activation. Nothing sends a second ON before an
        -- OFF clears the marker, so the guard is defensive: a second ON would
        -- record the state the first produced, Dark Cast Bar already on.
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
    if ns.EUIRefuseInCombat("Bite Mode", true) then return end
    CommitBite(on)
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
    end)
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
    end)
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
