-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Existing.lua                               ║
-- ║  Purpose: Hide Existing: Blizzard's tracking bar, and        ║
-- ║           EllesmereUI's XP and reputation bars through its   ║
-- ║           own Visibility, given back when the switch goes.   ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar

local floor = math.floor

local ACTION_BARS = "EllesmereUIActionBars"
local XP_SECTION = "xpbar"
local KINDS = { "xp", "rep" }
local BAR_KEYS = { xp = "XPBar", rep = "RepBar" }
local ENABLE_KEYS = { xp = "xpEnabled", rep = "fbEnabled" }
local HIDE_KEYS = { xp = "xpHideExisting", rep = "fbHideExisting" }

-- A spec or conditional override on any of these owns the bar's Visibility.
local CAPTURE_FIELDS = { "barVisibility", "alwaysHidden", "visibilityModes", "visibilityOverride" }

-- Every field the Visibility write touches, so a note holds all of them.
local VIS_FIELDS = {
    "barVisibility", "alwaysHidden", "mouseoverEnabled", "mouseoverAlpha",
    "_savedBarAlpha", "combatHideEnabled", "combatShowEnabled", "visibilityModes",
}

local NEVER = { never = true }

local hiddenParent, blizzParent
local pending = {}
local regenFrame

-- The action bar profile while EllesmereUI draws its own XP and reputation
-- bars, nil while Blizzard's are on screen.
local function EUIBars()
    local profile = ns.EUIProfile and ns.EUIProfile(ACTION_BARS)
    if type(profile) ~= "table" or profile.useBlizzardDataBars then return nil end
    return profile
end

function X.UsesEUIBars()
    return EUIBars() ~= nil
end

local function WantsHiding(kind, release)
    if release then return false end
    return X.Get(ENABLE_KEYS[kind]) == true and X.Get(HIDE_KEYS[kind]) == true
end

local function BlizzardWanted(release)
    return (WantsHiding("xp", release) or WantsHiding("rep", release)) and EUIBars() == nil
end

---------------------------------------------------------------------------------
-- Blizzard's tracking bar
---------------------------------------------------------------------------------

-- The whole manager, never one container: each container is an Edit Mode
-- system that shows itself again on the manager's next event. XP,
-- reputation and Forever's pet XP share it, so either switch hides all three.
local function SyncBlizzard(release)
    local manager = _G.StatusTrackingBarManager
    if not (manager and manager.SetParent and manager.GetParent) then return end
    local want = BlizzardWanted(release)
    if want and not blizzParent then
        hiddenParent = hiddenParent or CreateFrame("Frame")
        hiddenParent:Hide()
        blizzParent = manager:GetParent() or UIParent
        manager:SetParent(hiddenParent)
    elseif not want and blizzParent then
        manager:SetParent(blizzParent)
        blizzParent = nil
    end
end

---------------------------------------------------------------------------------
-- First position
---------------------------------------------------------------------------------

local Plain = ns.EUIPlain

-- A frame's live center on screen, in UIParent's units, whatever it is
-- anchored to; nil when it has no rect or any part of it is secret.
local function ScreenCenter(frame)
    if not (frame and frame.GetCenter and frame.GetEffectiveScale) then return nil end
    local ok, x, y = pcall(frame.GetCenter, frame)
    if not ok then return nil end
    x, y = Plain(x), Plain(y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local s, u = Plain(frame:GetEffectiveScale()), Plain(UIParent:GetEffectiveScale())
    if type(s) ~= "number" or type(u) ~= "number" or u <= 0 then return nil end
    return x * s / u, y * s / u
end

-- Stores a found spot as the XP bar's first position while the player has
-- never placed it. Returns whether it stored one.
local function Seed(x, y)
    if not x or X.Get("xpPos") ~= nil then return false end
    X.Set("xpPos", { point = "CENTER", relPoint = "BOTTOMLEFT", x = floor(x + 0.5), y = floor(y + 0.5) })
    return true
end

-- Blizzard's tracking bar is hidden without a click, so with Hide Existing on
-- its spot is the XP bar's first one. EllesmereUI's bar is hidden only on a
-- click, and its spot is taken at that write: until then the XP bar keeps its
-- default spot, clear of the bar still on screen. Returns whether a spot was
-- stored.
function X.SeedPosition()
    if X.Get("xpPos") ~= nil or X.Get("xpHideExisting") ~= true or EUIBars() then return false end
    local x, y = ScreenCenter(_G.MainStatusTrackingBarContainer)
    if not x then x, y = ScreenCenter(_G.StatusTrackingBarManager) end
    return Seed(x, y)
end

---------------------------------------------------------------------------------
-- EllesmereUI's bars
---------------------------------------------------------------------------------

local function IsNever(EUI, store)
    local sel = EUI.GetVisibilitySelection(store, "barVisibility", true)
    return type(sel) == "table" and sel.never == true
end

-- EllesmereUI's own dropdown path: the module's ApplyMode keeps the companion
-- fields in step, then the three refreshes repaint the bar.
local function Write(EUI, store, selection, eab)
    EUI.SetVisibilitySelection(store, "barVisibility", selection, eab.VisibilityCompat.ApplyMode)
    if eab.RefreshRuntimeVisibility then pcall(eab.RefreshRuntimeVisibility, eab) end
    if eab.RefreshMouseover then pcall(eab.RefreshMouseover, eab) end
    if eab.ApplyCombatVisibility then pcall(eab.ApplyCombatVisibility, eab) end
end

local function Overridden(EUI, store, barKey)
    if EUI.VisOverrideValue and EUI.VisOverrideValue(store) then return true end
    if not EUI.SpecOverrides_IsCaptured then return false end
    for i = 1, #CAPTURE_FIELDS do
        if EUI.SpecOverrides_IsCaptured(ACTION_BARS, "bars", barKey, CAPTURE_FIELDS[i]) then return true end
    end
    return false
end

-- The bar's settings in the saved profile, for a module that is off. nil
-- when that profile cannot be reached, so the note stays held for a later
-- pass. A bar with no settings there holds no Never of KitnUI's, so a
-- detached empty table stands in and nothing is written.
local function StoredBar(kind)
    local stored = ns.EUIStoredProfile and ns.EUIStoredProfile(ACTION_BARS)
    if type(stored) ~= "table" or not ns.EUIApplyVisModeStored then return nil end
    local bars = stored.bars
    local settings = type(bars) == "table" and bars[BAR_KEYS[kind]] or nil
    return type(settings) == "table" and settings or {}
end

local function ProfileName()
    return ns.EUIActiveProfileName and ns.EUIActiveProfileName() or ""
end

local function Generation()
    return ns.EUIProfileGeneration and ns.EUIProfileGeneration() or 0
end

-- A selection as one comparable string, such as "in_combat,in_raid".
local function SelectionKey(sel)
    if type(sel) ~= "table" then return "" end
    local keys = {}
    for k, v in pairs(sel) do
        if v then keys[#keys + 1] = tostring(k) end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- Returns whether a note changed; whether an editing session held the write
-- back, in which case the claim waits for the next pass; and whether the XP
-- bar was given its first spot. claim is the kept claim record, or nil.
local function SyncEUI(kind, claim, release)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.GetVisibilitySelection and EUI.SetVisibilitySelection) then return false end
    local want = WantsHiding(kind, release) and EUIBars() ~= nil
    local note = ns.EUIPeekSnap(XP_SECTION, kind)
    local held = type(note) == "table" and note.prev ~= nil
    if not (want or held) then return false end

    local barKey = BAR_KEYS[kind]
    local eab = ns.EUIAddon(ACTION_BARS)
    local profile = ns.EUIProfile(ACTION_BARS)
    local store = type(profile) == "table" and type(profile.bars) == "table" and profile.bars[barKey] or nil
    local VC = type(eab) == "table" and eab.VisibilityCompat or nil
    local live = type(VC) == "table" and type(VC.ApplyMode) == "function" and type(store) == "table"
    if not live then
        -- The module is off: the only work left is a restore into the saved
        -- profile, which passes the same guards as a live write.
        if want or not held then return false end
        store = StoredBar(kind)
        if not store then return false end
    end
    -- A write inside an override editing session is banked as the player's
    -- own edit.
    if ns.EUIEditSessionActive and ns.EUIEditSessionActive() then return false, true end
    -- An override owns the setting: the note goes and nothing is written.
    if Overridden(EUI, store, barKey) then
        if not held then return false end
        note.prev = nil
        return true
    end
    if not live then
        if IsNever(EUI, store) then
            EUI.SetVisibilitySelection(store, "barVisibility", note.prev, ns.EUIApplyVisModeStored)
        end
        note.prev = nil
        return true
    end

    local never = IsNever(EUI, store)
    if want then
        if held then
            if never then return false end
            -- The player or EllesmereUI changed it since: that choice stands.
            note.prev = nil
            return true
        end
        -- Only a click may take the bar: only then is the current choice
        -- really the player's own, and not a value copied with a profile.
        if not claim or never then return false end
        local sel = EUI.GetVisibilitySelection(store, "barVisibility", true)
        -- Contents replaced since the click by a path no hook sees, such as
        -- the action bar module's own reset: what the player clicked on is
        -- gone, so the claim is too.
        if SelectionKey(sel) ~= claim.vis then return false end
        local rec = ns.EUISnap(XP_SECTION, kind)
        if not rec then return false end
        rec.prev = sel
        -- The XP bar takes the spot of the bar it now replaces, read before
        -- that bar is hidden.
        local moved = kind == "xp" and Seed(ScreenCenter(_G.EllesmereEAB_XPBar))
        Write(EUI, store, NEVER, eab)
        return true, false, moved
    end
    if never then Write(EUI, store, note.prev, eab) end
    note.prev = nil
    return true
end

function X.HoldsExisting(kind)
    local note = ns.EUIPeekSnap(XP_SECTION, kind)
    return type(note) == "table" and note.prev ~= nil
end

-- A claim is bound to what the player clicked on: the profile's name, its
-- contents generation (Core bumps it on every switch and every import, which
-- can refill the active profile under its own name), and the bar's
-- Visibility at the click. One reused record per bar.
local claimRecs = { xp = {}, rep = {} }

local function Stamp(kind)
    local rec = claimRecs[kind]
    local EUI = _G.EllesmereUI
    local profile = EUIBars()
    local bars = profile and profile.bars
    local store = type(bars) == "table" and bars[BAR_KEYS[kind]] or nil
    rec.profile, rec.gen = ProfileName(), Generation()
    rec.vis = nil
    if type(store) == "table" and EUI and EUI.GetVisibilitySelection then
        rec.vis = SelectionKey(EUI.GetVisibilitySelection(store, "barVisibility", true))
    end
    return rec
end

-- Drops every kept claim that can no longer land: its bar no longer wants
-- hiding, or the active profile was switched, renamed, deleted or refilled
-- since the click. Every sync runs it first, in combat too.
local function Prune(release)
    local profile, gen = ProfileName(), Generation()
    for i = 1, #KINDS do
        local kind = KINDS[i]
        local rec = pending[kind]
        if rec and (not WantsHiding(kind, release) or rec.profile ~= profile or rec.gen ~= gen) then
            pending[kind] = nil
        end
    end
end

-- Only an operation that can really run counts, so a click on a bar that is
-- off waits for nothing: a Blizzard move, a kept claim on a bar that wants
-- hiding, or a held note whose bar no longer does.
local function HasWork(release)
    if _G.StatusTrackingBarManager and BlizzardWanted(release) ~= (blizzParent ~= nil) then return true end
    for i = 1, #KINDS do
        local kind = KINDS[i]
        local wants = WantsHiding(kind, release)
        if pending[kind] and wants and EUIBars() then return true end
        if not wants and X.HoldsExisting(kind) then return true end
    end
    return false
end

local function OnRegen(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    X.SyncExisting()
end

-- claim: "xp" or "rep" when the call comes from a click on that bar's Enable
-- or Hide Existing switch. A claim is kept only for a bar that wants hiding,
-- stamped as above. release: give everything back whatever the switches say
-- (the reset). Both kinds of write wait out combat; whether anything waits
-- is decided again on every call, so a claim canceled or dropped in combat
-- leaves nothing listening.
function X.SyncExisting(claim, release)
    if BAR_KEYS[claim] and WantsHiding(claim, release) then pending[claim] = Stamp(claim) end
    Prune(release)
    if InCombatLockdown() then
        if HasWork(release) then
            if not regenFrame then
                regenFrame = CreateFrame("Frame")
                regenFrame:SetScript("OnEvent", OnRegen)
            end
            regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        elseif regenFrame then
            regenFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end
    if regenFrame then regenFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    SyncBlizzard(release)
    local changed, placed = false, false
    for i = 1, #KINDS do
        local kind = KINDS[i]
        local did, waiting, moved = SyncEUI(kind, pending[kind], release)
        if did then changed = true end
        if moved then placed = true end
        if not waiting then pending[kind] = nil end
    end
    -- An apply places the bars before this sync, and a claim that waited out
    -- combat lands with no apply at all.
    if placed and X.ApplyVisibility then X.ApplyVisibility() end
    if changed and ns.EUIRebuildForOwnership then ns.EUIRebuildForOwnership("XP Bar") end
end

ns.EUIRegisterHeld(XP_SECTION, function(noteKey, _, add)
    local barKey = BAR_KEYS[noteKey]
    if not barKey then return end
    local base = "addons." .. ACTION_BARS .. ".bars." .. barKey .. "."
    for i = 1, #VIS_FIELDS do add(base .. VIS_FIELDS[i]) end
end)

