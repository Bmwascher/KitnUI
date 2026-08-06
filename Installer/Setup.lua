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

-- No v2 addon uses variant base-tracking yet (EllesmereUI color/healer variants
-- are tracked under the single "EllesmereUI" key). Kept for structural parity.
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
-- EllesmereUI (core import + per-spec healer/DPS swap)
-- Public API used (all guarded): EllesmereUI.ImportProfileSilent(opts), opts =
-- {importString, profileName, disableAddons} -> ok, err[, "spec_locked"]. A
-- spec_locked result does NOT activate the profile, so the SetProfile(name)
-- call below is still required. Also used: EllesmereUI.SetProfile(name);
-- EllesmereUI.AssignProfileToSpec(name, specID); EllesmereUI.RefreshAllAddons().
---------------------------------------------------------------------------------

-- Maps each spec index to its KitnUI EUI profile name. Healer specs get the
-- Healer variant; pure-DPS classes return nil (all specs use the base profile).
local function GetSpecProfileMap(className, useColor)
    local base   = useColor and (ns.profileName .. " Colored") or ns.profileName
    local healer = useColor and (ns.profileName .. " Healer Colored") or (ns.profileName .. " Healer")
    local maps = {
        ["Shaman"]  = { base, base, healer },
        ["Paladin"] = { healer, base, base },
        ["Priest"]  = { healer, healer, base },
        ["Monk"]    = { base, healer, base },
        ["Druid"]   = { base, base, base, healer },
        ["Evoker"]  = { base, healer, base },
    }
    return maps[className]
end

setupFunctions["EllesmereUI"] = function(addonKey, import, useColor)
    if not ns.EUIReady() then
        print(ns.title .. ": EllesmereUI API not available.")
        return false
    end

    local suffix     = useColor and " Colored" or ""
    local dpsName    = ns.profileName .. suffix
    local healerName = ns.profileName .. " Healer" .. suffix
    local dpsKey     = useColor and "EllesmereUIColored" or "EllesmereUI"
    local healerKey  = useColor and "EllesmereUIHealerColored" or "EllesmereUIHealer"

    if import then
        if not EllesmereUI.ImportProfileSilent then
            print(ns.title .. ": Your EllesmereUI is too old to import profiles. Please update EllesmereUI.")
            return false
        end

        -- DPS profile (fall back to the base export if a colored variant isn't authored yet)
        local importDpsKey = HasData(dpsKey) and dpsKey or "EllesmereUI"
        if not HasData(importDpsKey) then
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
        --                           EllesmereUIDB.specProfiles on every user.
        --                           Our own AssignProfileToSpec loop below is only
        --                           safe because this stays false.
        --   applyUIScale    (true)  applies the UI scale baked into the string.
        local modules = ns.GetEUIModuleSet()
        local ok, err = EllesmereUI.ImportProfileSilent({
            importString  = ns.data[importDpsKey],
            profileName   = dpsName,
            disableAddons = modules,
        })
        if not ok then
            print(ns.title .. ": EllesmereUI import failed - " .. (err or "unknown error"))
            return false
        end

        -- Healer profile (optional; its presence enables per-spec auto-swap)
        if HasData(healerKey) then
            local hok, herr = EllesmereUI.ImportProfileSilent({
                importString  = ns.data[healerKey],
                profileName   = healerName,
                disableAddons = modules,
            })
            if not hok then
                print(ns.title .. ": EllesmereUI healer import failed - " .. (herr or "unknown error"))
            end
        end

        CompleteSetup(addonKey)

        -- The import's enable sweep just turned every module back on that the
        -- pack did not name, and the action bars are deliberately not named.
        -- Re-assert the disable set here so a caller that never reaches Finish
        -- still gets it. Idempotent, so the Finish-time pass is unaffected.
        ns.ApplyEUIModuleSet()
    end

    -- Remember which variant is live so the installer can mark the active choice.
    -- Set on both import and load, since either path activates a specific variant.
    if ns.db then
        ns.db.variants = ns.db.variants or {}
        ns.db.variants.EllesmereUI = useColor and "color" or "dark"
    end

    -- The last import auto-activated its profile; force the DPS profile as default.
    if EllesmereUI.SetProfile then EllesmereUI.SetProfile(dpsName) end

    -- Assign healer/DPS profiles per spec (specID is the numeric id, not 1-4 index).
    local className, _, classID = UnitClass("player")
    local specMap = GetSpecProfileMap(className, useColor)
    if specMap and classID and EllesmereUI.AssignProfileToSpec then
        for specIndex, pName in ipairs(specMap) do
            local specID = GetSpecializationInfoForClassID(classID, specIndex)
            if specID and EllesmereUIDB and EllesmereUIDB.profiles and EllesmereUIDB.profiles[pName] then
                EllesmereUI.AssignProfileToSpec(pName, specID)
            end
        end
    end

    if EllesmereUI.RefreshAllAddons then EllesmereUI.RefreshAllAddons() end
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

        -- Cap check has to happen here: ApplyPresetEditMode returns a bare false
        -- and can't tell us the 5-layout limit was the reason. It de-dupes our
        -- own layout internally, so an existing KitnUI layout is a replacement,
        -- not an additional one, and must not count against the cap.
        local layouts = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
        if layouts and layouts.layouts then
            local hasOurs = false
            for _, layout in ipairs(layouts.layouts) do
                if layout.layoutName == ns.profileName then
                    hasOurs = true
                    break
                end
            end
            if #layouts.layouts >= 5 and not hasOurs then
                print(ns.title .. ": Edit Mode layout limit reached (5). Delete a layout and try again.")
                return false
            end
        end

        -- EllesmereUI's importer. It reconciles the layout with this client's
        -- Edit Mode schema (without which newer per-system options are absent
        -- and never appear in Edit Mode), waits for EditModeManagerFrame's
        -- account settings, guards combat, forces the Account layout type, and
        -- de-dupes earlier copies of the same name.
        if not EllesmereUI.ApplyPresetEditMode(ns.data[addonKey], ns.profileName) then
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
    for i, v in ipairs(layouts.layouts) do
        if v.layoutName == ns.profileName then
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

-- Built at call time because two of the three depend on whether the replacement
-- addon is actually loaded. Used in two places, and both are needed:
--   * as ImportProfileSilent's disableAddons, where EllesmereUI ALSO strips
--     those modules out of the payload and filters cross-module layout anchors
--   * directly at Finish, because disableAddons only fires on an import. An alt
--     running /kitn load never imports, and addon enable state is per character,
--     so the alt would otherwise keep the modules on.
function ns.GetEUIModuleSet()
    local set = { "EllesmereUICooldownManager" }
    if IsAddOnLoaded("Plater") then
        set[#set + 1] = "EllesmereUINameplates"
    end
    if IsAddOnLoaded("BuffReminders") then
        set[#set + 1] = "EllesmereUIAuraBuffReminders"
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
