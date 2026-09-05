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
