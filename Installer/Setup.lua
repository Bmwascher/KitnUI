-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Setup.lua                                                   ║
-- ║  Purpose: Per-addon profile setup + import dispatch. Writes  ║
-- ║           each addon's SavedVariables and activates the      ║
-- ║           matching profile per spec.                         ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

---------------------------------------------------------------------------------
-- Setup dispatcher
---------------------------------------------------------------------------------

local setupFunctions = {}

function ns.SetupAddon(addonKey, import, ...)
    local fn = setupFunctions[addonKey]
    if not fn then
        print(ns.title .. ": No setup function for " .. addonKey)
        return false
    end
    return fn(addonKey, import, ...)
end

-- No v2 addon uses variant base-tracking: every addon ships exactly one profile
-- under its own key. Kept for structural parity.
local variantBase = {}
ns.variantBase = variantBase

local function CompleteSetup(addonKey)
    ns.db.profiles = ns.db.profiles or {}
    ns.db.profiles[addonKey] = true
    if variantBase[addonKey] then
        ns.db.profiles[variantBase[addonKey]] = true
    end
    ns.db.installedVersion = ns.version

    ns.db.addonVersions = ns.db.addonVersions or {}
    local trackKey = variantBase[addonKey] or addonKey
    local dataVersion = ns.GetAddonDataVersion(trackKey)
    if dataVersion then
        ns.db.addonVersions[trackKey] = dataVersion
    end

    local charKey = UnitName("player") .. "-" .. GetRealmName()
    ns.db.perChar[charKey] = ns.db.perChar[charKey] or {}
    ns.db.perChar[charKey].loaded = true
end

local function HasData(addonKey)
    local d = ns.data[addonKey]
    if not d then return false end
    if type(d) == "string" and strtrim(d) == "" then return false end
    if type(d) == "table" and not next(d) then return false end
    return true
end

---------------------------------------------------------------------------------
-- EllesmereUI (core import + per-spec assignment)
-- Public API used (all guarded): EllesmereUI.ImportProfileSilent(opts), opts =
-- {importString, profileName, disableAddons} -> ok, err[, "spec_locked"]. A
-- spec_locked result does NOT activate the profile, so the SetProfile(name)
-- call below is still required. Also used: EllesmereUI.SetProfile(name);
-- EllesmereUI.RefreshAllAddons().
---------------------------------------------------------------------------------

setupFunctions["EllesmereUI"] = function(addonKey, import)
    if not ns.EUIReady() then
        print(ns.title .. ": EllesmereUI API not available.")
        return false
    end

    if import then
        if not EllesmereUI.ImportProfileSilent then
            print(ns.title .. ": Your EllesmereUI is too old to import profiles. Please update EllesmereUI.")
            return false
        end

        if not HasData("EllesmereUI") then
            print(ns.title .. ": No EllesmereUI profile data found.")
            return false
        end

        -- Defaults are load-bearing and deliberately not passed:
        --   cleanSlate      (true)  deletes an existing same-name profile first,
        --                           purging the name-keyed CDM spell store, spec
        --                           assignments and sync targets an overwrite
        --                           would otherwise inherit.
        --   autoAssignSpecs (false) strips the exporter's spec assignments, which
        --                           would otherwise be written into account-wide
        --                           EllesmereUIDB.specProfiles on every user. With
        --                           KitnUI no longer assigning specs either, the
        --                           user's own assignments survive an install.
        --   applyUIScale    (true)  applies the UI scale baked into the string.
        local ok, err = EllesmereUI.ImportProfileSilent({
            importString  = ns.data.EllesmereUI,
            profileName   = ns.profileName,
            disableAddons = ns.GetEUIModuleSet(),
        })
        if not ok then
            print(ns.title .. ": EllesmereUI import failed - " .. (err or "unknown error"))
            return false
        end

        CompleteSetup(addonKey)

        -- The import's enable sweep just turned every module back on that the
        -- pack did not name, and the action bars are deliberately not named.
        -- Re-assert the disable set here so a caller that never reaches Finish
        -- still gets it. Idempotent, so the Finish-time pass is unaffected.
        ns.ApplyEUIModuleSet()
    end

    if EllesmereUI.SetProfile then EllesmereUI.SetProfile(ns.profileName) end

    -- Spec assignment is deliberately NOT done here. EllesmereUI already owns
    -- that question and asks it with its own "Assign Preset to Specs" dialog.
    -- Claiming every spec of the player's class first meant that dialog opened
    -- with choices already made on the user's behalf, and silently replaced
    -- assignments they had set themselves. Leaving it alone lets the dialog do
    -- its job with nothing pre-ticked.

    if EllesmereUI.RefreshAllAddons then EllesmereUI.RefreshAllAddons() end

    -- Write the default look once, and only on an import. The shipped profile is
    -- hand-authored, so a single text slot drifting from the preset would leave
    -- the config tab reading Custom on a fresh install with nothing wrong. This
    -- runs after SetProfile because the look is written into the ACTIVE profile's
    -- module data. The load path skips it on purpose: EllesmereUI profiles are
    -- account-wide, so an alt running /kitn load lands on the same profile and
    -- must not overwrite a look the user changed on their main.
    if import and ns.ApplyLook then ns.ApplyLook("dark") end
    return true
end

---------------------------------------------------------------------------------
-- Plater Nameplates
---------------------------------------------------------------------------------

setupFunctions["Plater"] = function(addonKey, import)
    if import then
        if not HasData("Plater") then
            print(ns.title .. ": No Plater data found.")
            return
        end

        local profileString = ns.data.Plater
        if not Plater or not Plater.DecompressData then
            print(ns.title .. ": Plater not loaded.")
            return
        end

        local profileData = Plater.DecompressData(profileString, "print")
        if not profileData then
            print(ns.title .. ": Failed to decompress Plater profile.")
            return
        end

        PlaterDB = PlaterDB or {}
        PlaterDB["profiles"] = PlaterDB["profiles"] or {}
        PlaterDB["profiles"][ns.profileName] = profileData

        local charKey = UnitName("player") .. " - " .. GetRealmName()
        PlaterDB["profileKeys"] = PlaterDB["profileKeys"] or {}
        PlaterDB["profileKeys"][charKey] = ns.profileName

        CompleteSetup(addonKey)
        return
    end

    if not PlaterDB or not PlaterDB.profiles or not PlaterDB.profiles[ns.profileName] then return end
    PlaterDB["profileKeys"] = PlaterDB["profileKeys"] or {}
    PlaterDB["profileKeys"][UnitName("player") .. " - " .. GetRealmName()] = ns.profileName
    Plater.db:SetProfile(ns.profileName)
end

---------------------------------------------------------------------------------
-- BigWigs
---------------------------------------------------------------------------------

setupFunctions["BigWigs"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No BigWigs data found. Add your profile data to Data.lua.")
            return
        end

        BigWigsAPI.RegisterProfile(ns.title, ns.data[addonKey], ns.profileName, function(success)
            if success then
                CompleteSetup(addonKey)
            end
        end)
        return
    end

    if not BigWigs3DB or not BigWigs3DB.profiles or not BigWigs3DB.profiles[ns.profileName] then return end
    local db = LibStub("AceDB-3.0"):New(BigWigs3DB)
    db:SetProfile(ns.profileName)
end

---------------------------------------------------------------------------------
-- Northern Sky Raid Tools
-- Decodes NSRT's export string (AceSerializer-3.0 + LibDeflate) and writes each
-- module's data directly into the account-wide NSRT global. NSRT has no profile
-- system, so there is nothing to activate on load.
---------------------------------------------------------------------------------

local function DecodeNSRTString(exportString)
    local LibDeflate = LibStub and LibStub("LibDeflate", true)
    local Serialize = LibStub and LibStub("AceSerializer-3.0", true)
    if not LibDeflate or not Serialize then
        return nil, "LibDeflate or AceSerializer-3.0 not available (is NSRT loaded?)"
    end

    local decoded = LibDeflate:DecodeForPrint(exportString)
    local decompressed = decoded and LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, "failed to decompress NSRT string"
    end

    local success, data = Serialize:Deserialize(decompressed)
    if not success or type(data) ~= "table" then
        return nil, "failed to deserialize NSRT data"
    end
    return data
end

setupFunctions["NSRT"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No NSRT data found.")
            return
        end
        if not IsAddOnLoaded("NorthernSkyRaidTools") then
            print(ns.title .. ": NorthernSkyRaidTools is not loaded.")
            return
        end

        local decoded, err = DecodeNSRTString(ns.data[addonKey])
        if not decoded then
            print(ns.title .. ": NSRT decode failed - " .. (err or "unknown error"))
            return
        end

        NSRT = NSRT or {}
        for k, v in pairs(decoded) do
            if type(v) == "table" and v.enabled and v.data ~= nil then
                NSRT[k] = v.data
            end
        end

        CompleteSetup(addonKey)
        return
    end

    -- Load is a no-op: NSRT is account-wide with no per-character profile.
end

---------------------------------------------------------------------------------
-- Blizzard Edit Mode
---------------------------------------------------------------------------------

-- Which of KitnUI's two Edit Mode layouts belongs to the current mode. Falls
-- back to the standard one whenever the Lulu layout has not been authored yet,
-- so a half-configured Lulu Mode still lands on a working layout. Both branches
-- of the setup function read from here, so they always agree with each other
-- inside one run.
--
-- Across runs they can differ, and that is deliberate rather than a hole. A full
-- install imports the EllesmereUI profile first, and that import deletes the
-- existing profile, which clears the config tab's switch states along with it.
-- So a re-install reads Lulu as off here and lands the standard layout, while
-- /kitn load on the same character reads it as still on. A re-install returning
-- to defaults is the intended outcome; this comment used to claim an invariant
-- that does not hold, which is the part that was wrong.
local function editModeTarget()
    if ns.LuluEnabled and ns.LuluEnabled()
        and ns.LuluLayoutName and HasData("Blizzard_EditMode_Lulu") then
        return "Blizzard_EditMode_Lulu", ns.LuluLayoutName()
    end
    return "Blizzard_EditMode", ns.profileName
end

setupFunctions["Blizzard_EditMode"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No Edit Mode data found. Add your layout string to Data.lua.")
            return false
        end

        if not (_G.EllesmereUI and EllesmereUI.ApplyPresetEditMode) then
            print(ns.title .. ": Your EllesmereUI is too old to import Edit Mode layouts. Please update EllesmereUI.")
            return false
        end

        local dataKey, layoutName = editModeTarget()

        if not ns.EditModeSlotFree(layoutName) then
            print(ns.title .. ": Edit Mode layout limit reached (5). Delete a layout and try again.")
            return false
        end

        -- EllesmereUI's importer. It reconciles the layout with this client's
        -- Edit Mode schema (without which newer per-system options are absent
        -- and never appear in Edit Mode), waits for EditModeManagerFrame's
        -- account settings, guards combat, forces the Account layout type, and
        -- de-dupes earlier copies of the same name.
        if not EllesmereUI.ApplyPresetEditMode(ns.data[dataKey], layoutName) then
            print(ns.title .. ": Edit Mode import failed. Open Edit Mode once, then try again out of combat.")
            return false
        end

        CompleteSetup(addonKey)
        return true
    end

    -- Load: activate the existing layout on this character. The index is the
    -- preset count plus the layout's position in the saved list.
    if not (C_EditMode and C_EditMode.GetLayouts) then return end
    local layouts = C_EditMode.GetLayouts()
    if not (layouts and layouts.layouts) then return end
    local _, wantedLayout = editModeTarget()
    for i, v in ipairs(layouts.layouts) do
        if v.layoutName == wantedLayout then
            C_EditMode.SetActiveLayout(Enum.EditModePresetLayoutsMeta.NumValues + i)
            return
        end
    end
end

---------------------------------------------------------------------------------
-- KitnEssentials
---------------------------------------------------------------------------------

setupFunctions["KitnEssentials"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No KitnEssentials data found.")
            return
        end

        if not IsAddOnLoaded("KitnEssentials") then
            print(ns.title .. ": KitnEssentials is not loaded.")
            return
        end

        local API = _G.KitnEssentialsAPI
        if not API or not API.DecodeProfileString then
            print(ns.title .. ": KitnEssentials API not available.")
            return
        end

        local profileData = API:DecodeProfileString(ns.data[addonKey])
        if not profileData or not next(profileData) then
            print(ns.title .. ": KitnEssentials decode failed.")
            return
        end

        KitnEssentialsDB = KitnEssentialsDB or {}
        KitnEssentialsDB.profiles = KitnEssentialsDB.profiles or {}
        KitnEssentialsDB.profiles[ns.profileName] = profileData

        local charKey = UnitName("player") .. " - " .. GetRealmName()
        KitnEssentialsDB.profileKeys = KitnEssentialsDB.profileKeys or {}
        KitnEssentialsDB.profileKeys[charKey] = ns.profileName

        local KE_addon = _G.KitnEssentials
        if KE_addon and KE_addon.db then
            KE_addon.db:SetProfile(ns.profileName)
        end

        CompleteSetup(addonKey)
        return
    end

    local API = _G.KitnEssentialsAPI
    if API and API.SetProfile then
        API:SetProfile(ns.profileName)
    end
end

---------------------------------------------------------------------------------
-- BuffReminders
---------------------------------------------------------------------------------

setupFunctions["BuffReminders"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No BuffReminders data found.")
            return
        end

        if not IsAddOnLoaded("BuffReminders") then
            print(ns.title .. ": BuffReminders is not loaded.")
            return
        end

        local BR = _G.BuffReminders
        if not BR or not BR.Import then
            print(ns.title .. ": BuffReminders API not available.")
            return
        end

        local success, err = BR:Import(ns.data[addonKey], ns.profileName)
        if success then
            BR:SetProfile(ns.profileName)
            CompleteSetup(addonKey)
        else
            print(ns.title .. ": BuffReminders import failed - " .. (err or "unknown error"))
        end
        return
    end

    local BR = _G.BuffReminders
    if BR and BR.SetProfile then
        BR:SetProfile(ns.profileName)
    end
end

---------------------------------------------------------------------------------
-- Blizzard Cooldown Manager (per-spec)
---------------------------------------------------------------------------------

setupFunctions["BlizzardCDM"] = function(_addonKey, import, specIndex)
    if import then
        local _, _, classId = UnitClass("player")
        local classData = ns.data.BlizzardCDM and ns.data.BlizzardCDM[classId]
        local specString = classData and classData[specIndex]

        if not specString or strtrim(specString) == "" then
            print(ns.title .. ": No CDM data for this spec. Add your layout string to Data.lua.")
            return
        end

        if not CooldownViewerSettings or not CooldownViewerSettings.GetLayoutManager then
            print(ns.title .. ": Blizzard Cooldown Manager is not available. Enable it in Settings > Gameplay > Combat.")
            return
        end

        local lm = CooldownViewerSettings:GetLayoutManager()
        if not lm then
            print(ns.title .. ": Could not get CDM Layout Manager.")
            return
        end

        local specName = select(2, GetSpecializationInfoForClassID(classId, specIndex)) or ("Spec" .. specIndex)
        local layoutName = "KUI - " .. specName
        local removedExisting = false
        local _, layouts = lm:EnumerateLayouts()
        if layouts then
            for layoutID, layout in pairs(layouts) do
                if layout and layout.layoutName == layoutName then
                    lm:RemoveLayout(layoutID)
                    removedExisting = true
                    break
                end
            end
        end

        -- If we didn't free a slot and layouts are maxed, bail out.
        if not removedExisting and lm.AreLayoutsFullyMaxed and lm:AreLayoutsFullyMaxed() then
            print(ns.title .. ": CDM layout limit reached. Delete a layout and try again.")
            return false
        end

        local layoutIDs = lm:CreateLayoutsFromSerializedData(specString)
        if layoutIDs and layoutIDs[1] then
            local importedID = layoutIDs[1]

            local _, postLayouts = lm:EnumerateLayouts()
            if not postLayouts or not postLayouts[importedID] then
                print(ns.title .. ": CDM layout limit reached. Delete a layout and try again.")
                return false
            end

            postLayouts[importedID].layoutName = layoutName
            lm:SaveLayouts()

            local currentSpec = C_SpecializationInfo.GetSpecialization()
            if currentSpec == specIndex then
                if lm.SetActiveLayoutByID then
                    lm:SetActiveLayoutByID(importedID)
                end
                lm:SaveLayouts()

                C_Timer.After(0, function()
                    if not InCombatLockdown() and lm.SetActiveLayoutByID then
                        lm:SetActiveLayoutByID(importedID)
                        lm:SaveLayouts()
                    end
                end)
            end

            ns.db.profiles = ns.db.profiles or {}
            ns.db.profiles["BlizzardCDM"] = ns.db.profiles["BlizzardCDM"] or {}
            ns.db.profiles["BlizzardCDM"][specIndex] = true
            ns.db.installedVersion = ns.version

            local charKey = UnitName("player") .. "-" .. GetRealmName()
            ns.db.perChar[charKey] = ns.db.perChar[charKey] or {}
            ns.db.perChar[charKey].loaded = true
            return true
        else
            print(ns.title .. ": Failed to import CDM layout.")
        end
        return false
    end
end

---------------------------------------------------------------------------------
-- EllesmereUI module set
-- Ownership: the standalone tools win, so the overlapping EllesmereUI modules
-- are turned off. Each EUI "module" is a SEPARATE addon folder; module on/off
-- is Blizzard's per-character addon state, not a SavedVariable, and it is not
-- carried in the !EUI_ export, so it can only be set post-import and takes
-- effect on the next ReloadUI.
---------------------------------------------------------------------------------

-- Built at call time, and a FRESH table every call, for two reasons. One member
-- is conditional: see the nameplates branch below; the rest are unconditional.
-- And ApplyEUIModuleSet appends to what this returns, while the same return also
-- becomes ImportProfileSilent's disableAddons, so a shared static set would let
-- that append leak into the import's strip list. Lulu Mode's action bars entry
-- is deliberately NOT part of this set; ApplyEUIModuleSet appends it separately
-- and explains why.
--
-- Used in two places, and both are needed:
--   * as ImportProfileSilent's disableAddons, where EllesmereUI ALSO strips
--     those modules out of the payload and filters cross-module layout anchors
--   * directly at Finish, because disableAddons only fires on an import. An alt
--     running /kitn load never imports, and addon enable state is per character,
--     so the alt would otherwise keep the modules on.
--
-- EllesmereUICooldownManager is deliberately NOT here. It is not a competing
-- cooldown display: it hooks Blizzard's own Cooldown Viewer and skins it. The
-- Blizzard CDM step supplies the spell layout for that same viewer, so the two
-- stack rather than fight. Listing it here stripped its settings AND its spell
-- layouts out of the import, which shipped Blizzard's raw look with KitnUI's
-- spell list.
-- Off on every install, with no condition attached. These are the EllesmereUI
-- modules KitnUI either replaces with a dedicated addon or deliberately leaves
-- to Blizzard, so there is nothing to detect: the pack is opinionated about
-- them either way. Note that disabling Blizz UI Enhanced also takes its Dragon
-- Riding skin with it, because that lives inside the same folder.
local ALWAYS_DISABLED = {
    "EllesmereUIQoL",
    "EllesmereUIAuraBuffReminders",
    "EllesmereUIBlizzardSkin",
    "EllesmereUIDamageMeters",
    "EllesmereUIMythicTimer",
    "EllesmereUIFriends",
    "EllesmereUIChat",
    "EllesmereUIBags",
}

function ns.GetEUIModuleSet()
    local set = {}
    for _, folder in ipairs(ALWAYS_DISABLED) do
        set[#set + 1] = folder
    end

    -- Conditional because EllesmereUI's nameplates are a real option when the
    -- user has no Plater. The list above has no such fallback question.
    if IsAddOnLoaded("Plater") then
        set[#set + 1] = "EllesmereUINameplates"
    end
    return set
end

-- A folder we can't see isn't installed, so there is nothing to disable. When
-- DoesAddOnExist is unavailable, assume it is present and let DisableAddOn
-- no-op on its own.
local function euiModuleInstalled(folder)
    if not C_AddOns.DoesAddOnExist then return true end
    return C_AddOns.DoesAddOnExist(folder)
end

-- Idempotent and safe: no-ops when C_AddOns is unavailable and skips any module
-- that isn't installed. Takes effect on the ReloadUI at the end of the flow.
function ns.ApplyEUIModuleSet()
    if not (C_AddOns and C_AddOns.DisableAddOn) then return end
    local set = ns.GetEUIModuleSet()

    -- Lulu Mode turns EllesmereUI's action bars off. It belongs here and NOT in
    -- GetEUIModuleSet: that set is also ImportProfileSilent's disableAddons,
    -- which strips the named modules' settings out of the imported payload.
    -- Naming the action bars there would throw away the bar configuration this
    -- addon exists to install. Enable state is all Lulu Mode needs, and the
    -- import's own enable sweep is undone by this pass because both only take
    -- effect at the reload and this one runs last.
    if ns.LuluEnabled and ns.LuluEnabled() then
        set[#set + 1] = "EllesmereUIActionBars"
    end

    for _, folder in ipairs(set) do
        if euiModuleInstalled(folder) then
            C_AddOns.DisableAddOn(folder)
        end
    end
end

---------------------------------------------------------------------------------
-- Finish installation
---------------------------------------------------------------------------------

function ns.FinishInstallation()
    ns.db.installedVersion = ns.version
    ns:SetCharLoaded()

    -- Runs on the install AND load paths. Addon enable state is per character,
    -- so an alt that only loads profiles still needs its own pass.
    ns.ApplyEUIModuleSet()

    -- Hide companion minimap icons (shared with the Extras "Clean Icons" button).
    ns.CleanMinimapIcons()

    ReloadUI()
end
