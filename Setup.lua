local _, ns = ...

local E = ns.E
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

------------------------------------------------------------
-- ElvUI profile decoder (handles compressed export strings)
------------------------------------------------------------

-- Decodes an ElvUI compressed export string into a profile table
-- If the data is already a table, returns it as-is
-- Handles raw strings like "!E1!..." or wrapped "{!E1!...}"
local function DecodeElvUIData(data)
    if type(data) == "table" then return CopyTable(data) end
    if type(data) ~= "string" or strtrim(data) == "" then return nil end

    local D = E:GetModule("Distributor")
    if not D then return nil end

    -- Strip wrapping curly braces if present (e.g. "{!E1!...}" -> "!E1!...")
    local cleanData = strtrim(data)
    if cleanData:sub(1, 1) == "{" and cleanData:sub(-1) == "}" then
        cleanData = cleanData:sub(2, -2)
    end

    local profileType, profileKey, profileData = D:Decode(cleanData)
    if profileData then
        return profileData
    end

    print(ns.title .. ": Failed to decode ElvUI data.")
    return nil
end

------------------------------------------------------------
-- Setup dispatcher
------------------------------------------------------------

local setupFunctions = {}

function ns.SetupAddon(addonKey, import, ...)
    local fn = setupFunctions[addonKey]
    if not fn then
        print(ns.title .. ": No setup function for " .. addonKey)
        return
    end
    fn(addonKey, import, ...)
end

-- Maps variant data keys to their base addon key for tracking
local variantBase = {
    Ayije_CDM_CastEmphasized = "Ayije_CDM",
    Ayije_CDM_Healer = "Ayije_CDM",
    Ayije_CDM_HealerDualResource = "Ayije_CDM",
    Ayije_CDM_Bite = "Ayije_CDM",
}
ns.variantBase = variantBase

local function CompleteSetup(addonKey)
    ns.db.profiles = ns.db.profiles or {}
    ns.db.profiles[addonKey] = true
    if variantBase[addonKey] then
        ns.db.profiles[variantBase[addonKey]] = true
    end
    ns.db.installedVersion = ns.version

    -- Track per-addon data version from TOC X-headers
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

------------------------------------------------------------
-- ElvUI Profile
-- useColor: if true, use the Colored (class color) variant
------------------------------------------------------------

setupFunctions["ElvUI"] = function(addonKey, import, useColor)
    if import then
        if not HasData("ElvUI") then
            print(ns.title .. ": No ElvUI profile data found. Add your exported profile to Data.lua.")
            return
        end

        -- Decode all profile variants (handles both compressed strings and raw tables)
        local elvData = DecodeElvUIData(ns.data.ElvUI)
        if not elvData then
            print(ns.title .. ": Failed to decode ElvUI profile data.")
            return
        end

        -- Write all profile variants into ElvDB
        ElvDB["profiles"] = ElvDB["profiles"] or {}
        ElvDB["profiles"][ns.profileName] = elvData

        if HasData("ElvUIClassColor") then
            local d = DecodeElvUIData(ns.data.ElvUIClassColor)
            if d then ElvDB["profiles"][ns.profileName .. " Colored"] = d end
        end
        if HasData("ElvUIHealer") then
            local d = DecodeElvUIData(ns.data.ElvUIHealer)
            if d then ElvDB["profiles"][ns.profileName .. " Healer"] = d end
        end
        if HasData("ElvUIHealerClassColor") then
            local d = DecodeElvUIData(ns.data.ElvUIHealerClassColor)
            if d then ElvDB["profiles"][ns.profileName .. " Healer Colored"] = d end
        end

        -- Write private profiles into ElvPrivateDB
        ElvPrivateDB["profiles"] = ElvPrivateDB["profiles"] or {}
        if HasData("ElvUIPrivate") then
            local privData = DecodeElvUIData(ns.data.ElvUIPrivate)
            if privData then
                ElvPrivateDB["profiles"][ns.profileName] = CopyTable(privData)
                ElvPrivateDB["profiles"][ns.profileName .. " Colored"] = CopyTable(privData)
                ElvPrivateDB["profiles"][ns.profileName .. " Healer"] = CopyTable(privData)
                ElvPrivateDB["profiles"][ns.profileName .. " Healer Colored"] = CopyTable(privData)
            end
        end

        -- Write global settings (e.g. custom datatext panels, aura indicators)
        if HasData("ElvUIGlobal") then
            local globalData = DecodeElvUIData(ns.data.ElvUIGlobal)
            if globalData then
                if globalData.datatexts and globalData.datatexts.customPanels then
                    E.global.datatexts = E.global.datatexts or {}
                    E.global.datatexts.customPanels = CopyTable(globalData.datatexts.customPanels)
                end
                if globalData.unitframe and globalData.unitframe.aurawatch then
                    E.global.unitframe = E.global.unitframe or {}
                    E.global.unitframe.aurawatch = CopyTable(globalData.unitframe.aurawatch)
                end
            end
        end

        -- Force 1440p UI scale
        E.db.general.UIScale = 0.5333333
        ElvDB.global.general.UIScale = 0.5333333

        CompleteSetup(addonKey)
    end

    -- Determine which profile to activate
    local activeProfile
    if useColor then
        activeProfile = ns.profileName .. " Colored"
    else
        activeProfile = ns.profileName
    end

    -- Set the active profile
    E.data:SetProfile(activeProfile)

    -- Set private profile key for this character (always base profile — private settings are shared)
    local charKey = UnitName("player") .. " - " .. GetRealmName()
    ElvPrivateDB["profileKeys"] = ElvPrivateDB["profileKeys"] or {}
    ElvPrivateDB["profileKeys"][charKey] = ns.profileName

    -- Set DualSpec profiles (auto-switch healer profile per spec)
    local className = UnitClass("player")
    if ElvDB["namespaces"] and ElvDB["namespaces"]["LibDualSpec-1.0"] then
        ElvDB["namespaces"]["LibDualSpec-1.0"]["char"] = ElvDB["namespaces"]["LibDualSpec-1.0"]["char"] or {}
        ElvDB["namespaces"]["LibDualSpec-1.0"]["char"][charKey] = ns.GetDualSpecConfig(className, useColor)
    end

    -- Ensure nameplates stay disabled
    E.private["nameplates"]["enable"] = false
end

------------------------------------------------------------
-- Details! Damage Meter
------------------------------------------------------------

setupFunctions["Details"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No Details data found. Export your profile and add it to Data.lua.")
            return
        end

        Details:EraseProfile(ns.profileName)
        Details:ImportProfile(ns.data[addonKey], ns.profileName, false, false, true)

        CompleteSetup(addonKey)
        return
    end

    if not Details:GetProfile(ns.profileName) then return end
    Details:ApplyProfile(ns.profileName)
end

------------------------------------------------------------
-- Plater Nameplates
------------------------------------------------------------

setupFunctions["Plater"] = function(addonKey, import)
    if import then
        if not ns.data.PlaterDB then
            print(ns.title .. ": No Plater data found.")
            return
        end

        -- Replace entire PlaterDB (includes profiles, plate_config, global settings, scripts, etc.)
        PlaterDB = ns.data.PlaterDB

        -- Set profile key for this character
        PlaterDB["profileKeys"] = PlaterDB["profileKeys"] or {}
        PlaterDB["profileKeys"][UnitName("player") .. " - " .. GetRealmName()] = ns.profileName

        CompleteSetup(addonKey)
        return
    end

    if not PlaterDB or not PlaterDB.profiles or not PlaterDB.profiles[ns.profileName] then return end
    PlaterDB["profileKeys"] = PlaterDB["profileKeys"] or {}
    PlaterDB["profileKeys"][UnitName("player") .. " - " .. GetRealmName()] = ns.profileName
    Plater.db:SetProfile(ns.profileName)
end

------------------------------------------------------------
-- BigWigs
------------------------------------------------------------

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

------------------------------------------------------------
-- WarpDeplete
------------------------------------------------------------

setupFunctions["WarpDeplete"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No WarpDeplete data found. Add your profile table to Data.lua.")
            return
        end

        WarpDepleteDB.profiles[ns.profileName] = ns.data[addonKey]
        WarpDeplete.db:SetProfile(ns.profileName)

        CompleteSetup(addonKey)
        return
    end

    if not WarpDepleteDB or not WarpDepleteDB.profiles or not WarpDepleteDB.profiles[ns.profileName] then return end
    WarpDeplete.db:SetProfile(ns.profileName)
end

------------------------------------------------------------
-- MRT / Method Raid Tools
------------------------------------------------------------

setupFunctions["MRT"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No MRT data found. Add your MRT table to Data.lua.")
            return
        end

        VMRT.Profiles = VMRT.Profiles or {}
        VMRT.Profiles[ns.profileName] = CopyTable(ns.data[addonKey])

        VMRT.ProfileKeys = VMRT.ProfileKeys or {}
        local realmKey = GetRealmName():gsub(" ", "")
        local charKey = UnitName("player") .. "-" .. realmKey
        VMRT.ProfileKeys[charKey] = ns.profileName

        CompleteSetup(addonKey)
        print(ns.title .. ": MRT profile saved. Reload UI (/reload) to activate it.")
        return
    end

    if not VMRT or not VMRT.Profiles or not VMRT.Profiles[ns.profileName] then return end
    VMRT.ProfileKeys = VMRT.ProfileKeys or {}
    local realmKey = GetRealmName():gsub(" ", "")
    local charKey = UnitName("player") .. "-" .. realmKey
    VMRT.ProfileKeys[charKey] = ns.profileName
end

------------------------------------------------------------
-- Blizzard Edit Mode
------------------------------------------------------------

setupFunctions["Blizzard_EditMode"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No Edit Mode data found. Add your layout string to Data.lua.")
            return
        end

        local layouts = C_EditMode.GetLayouts()

        -- Remove existing KitnUI layout if present
        for i = #layouts.layouts, 1, -1 do
            if layouts.layouts[i].layoutName == ns.profileName then
                tremove(layouts.layouts, i)
            end
        end

        local info = C_EditMode.ConvertStringToLayoutInfo(ns.data[addonKey])
        info.layoutName = ns.profileName
        info.layoutType = Enum.EditModeLayoutType.Account

        tinsert(layouts.layouts, info)
        C_EditMode.SaveLayouts(layouts)

        local newIndex = Enum.EditModePresetLayoutsMeta.NumValues + #layouts.layouts
        C_EditMode.SetActiveLayout(newIndex)

        CompleteSetup(addonKey)
        return
    end

    -- Load existing profile
    local layouts = C_EditMode.GetLayouts()
    for i, v in ipairs(layouts.layouts) do
        if v.layoutName == ns.profileName then
            C_EditMode.SetActiveLayout(Enum.EditModePresetLayoutsMeta.NumValues + i)
            return
        end
    end
end

------------------------------------------------------------
-- Ayije CDM (cooldown manager - 4 profiles, auto spec mapping)
------------------------------------------------------------

local cdmProfileNames = {
    Ayije_CDM = ns.profileName,
    Ayije_CDM_CastEmphasized = ns.profileName .. " CastEmphasized",
    Ayije_CDM_Healer = ns.profileName .. " Healer",
    Ayije_CDM_HealerDualResource = ns.profileName .. " HealerDualResource",
    Ayije_CDM_Bite = ns.profileName .. " Bite",
}

-- All 4 profile data keys to import
local cdmProfileKeys = { "Ayije_CDM", "Ayije_CDM_CastEmphasized", "Ayije_CDM_Healer", "Ayije_CDM_HealerDualResource", "Ayije_CDM_Bite" }

-- Per-class spec-to-profile mapping (mirrors atrocityUI)
local function GetAyijeCDMSpecProfiles(className)
    local base = ns.profileName
    local cast = ns.profileName .. " CastEmphasized"
    local heal = ns.profileName .. " Healer"
    local healDual = ns.profileName .. " HealerDualResource"

    local specOptions = {
        ["Death Knight"]  = { base, base, base, ["enabled"] = true },
        ["Demon Hunter"]  = { cast, base, cast, ["enabled"] = true },
        ["Druid"]         = { cast, base, base, heal, ["enabled"] = true },
        ["Evoker"]        = { cast, healDual, cast, ["enabled"] = true },
        ["Hunter"]        = { base, base, base, ["enabled"] = true },
        ["Mage"]          = { cast, cast, cast, ["enabled"] = true },
        ["Monk"]          = { base, heal, base, ["enabled"] = true },
        ["Paladin"]       = { healDual, base, base, ["enabled"] = true },
        ["Priest"]        = { heal, heal, cast, ["enabled"] = true },
        ["Rogue"]         = { base, base, base, ["enabled"] = true },
        ["Shaman"]        = { cast, base, heal, ["enabled"] = true },
        ["Warlock"]       = { cast, cast, cast, ["enabled"] = true },
        ["Warrior"]       = { base, base, base, ["enabled"] = true },
    }
    return specOptions[className]
end

setupFunctions["Ayije_CDM"] = function(addonKey, import)
    if import then
        -- Load the Options addon to get the full ImportProfile
        if not C_AddOns.IsAddOnLoaded("Ayije_CDM_Options") then
            C_AddOns.LoadAddOn("Ayije_CDM_Options")
        end

        local CDM_Addon = _G["Ayije_CDM"]

        -- Suppress the config frame that auto-opens during import
        local origRebuild = CDM_Addon.RebuildConfigFrame
        CDM_Addon.RebuildConfigFrame = function() end

        -- Import all 4 profiles
        for _, key in ipairs(cdmProfileKeys) do
            if ns.data[key] then
                local targetName = cdmProfileNames[key]

                -- Hook ImportProfileData to force our profile name
                local origImportProfileData = CDM_Addon.ImportProfileData
                CDM_Addon.ImportProfileData = function(self, _name, profileData)
                    return origImportProfileData(self, targetName, profileData)
                end

                local success, msg = CDM_Addon.API:ImportProfile(ns.data[key])

                -- Restore hook
                CDM_Addon.ImportProfileData = origImportProfileData

                if not success then
                    print(ns.title .. ": AyijeCDM import failed for " .. targetName .. " - " .. (msg or "unknown error"))
                end
            end
        end

        -- Restore config frame builder
        CDM_Addon.RebuildConfigFrame = origRebuild

        if _G["Ayije_CDMConfigFrame"] then
            _G["Ayije_CDMConfigFrame"]:Hide()
        end

        CompleteSetup("Ayije_CDM")
    end

    -- Set up spec-to-profile mapping and activate current spec's profile
    if not Ayije_CDMDB then return end

    local charKey = UnitName("player") .. " - " .. GetRealmName()
    local className = UnitClass("player")
    local specMapping = GetAyijeCDMSpecProfiles(className)
    if not specMapping then return end

    if not Ayije_CDMDB["specProfiles"] then
        Ayije_CDMDB["specProfiles"] = {}
    end
    Ayije_CDMDB["specProfiles"][charKey] = specMapping

    -- Set current profile to match active spec
    local currentSpecIndex = GetSpecialization() or 1
    local profileForCurrentSpec = specMapping[currentSpecIndex] or ns.profileName

    if not Ayije_CDMDB["profileKeys"] then
        Ayije_CDMDB["profileKeys"] = {}
    end
    Ayije_CDMDB["profileKeys"][charKey] = profileForCurrentSpec
end

------------------------------------------------------------
-- KitnEssentials (placeholder)
------------------------------------------------------------

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

        -- Decode the string, then write directly to the SavedVariable to avoid duplication
        local profileData = API:DecodeProfileString(ns.data[addonKey])
        if not profileData or not next(profileData) then
            print(ns.title .. ": KitnEssentials decode failed.")
            return
        end

        KitnEssentialsDB = KitnEssentialsDB or {}
        KitnEssentialsDB.profiles = KitnEssentialsDB.profiles or {}
        KitnEssentialsDB.profiles[ns.profileName] = profileData

        -- Set profileKey for this character
        local charKey = UnitName("player") .. " - " .. GetRealmName()
        KitnEssentialsDB.profileKeys = KitnEssentialsDB.profileKeys or {}
        KitnEssentialsDB.profileKeys[charKey] = ns.profileName

        -- Activate the profile via AceDB
        local KE_addon = _G.KitnEssentials
        if KE_addon and KE_addon.db then
            KE_addon.db:SetProfile(ns.profileName)
        end

        CompleteSetup(addonKey)
        return
    end

    -- Load: activate existing profile
    local API = _G.KitnEssentialsAPI
    if API and API.SetProfile then
        API:SetProfile(ns.profileName)
    end
end

------------------------------------------------------------
-- BuffReminders
------------------------------------------------------------

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

    -- Load: activate existing profile
    local BR = _G.BuffReminders
    if BR and BR.SetProfile then
        BR:SetProfile(ns.profileName)
    end
end

------------------------------------------------------------
-- Blizzard Cooldown Manager (per-spec)
------------------------------------------------------------

setupFunctions["BlizzardCDM"] = function(addonKey, import, specIndex)
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

        -- Remove existing layout with our profile name if present
        local _, layouts = lm:EnumerateLayouts()
        if layouts then
            local specName = select(2, GetSpecializationInfoForClassID(classId, specIndex)) or ("Spec" .. specIndex)
            local layoutName = "KUI - " .. specName
            for layoutID, layout in pairs(layouts) do
                if layout and layout.layoutName == layoutName then
                    lm:RemoveLayout(layoutID)
                    break
                end
            end
        end

        local layoutIDs = lm:CreateLayoutsFromSerializedData(specString)
        if layoutIDs and layoutIDs[1] then
            local importedID = layoutIDs[1]

            -- Rename the imported layout
            local _, importedLayouts = lm:EnumerateLayouts()
            if importedLayouts and importedLayouts[importedID] then
                local specName = select(2, GetSpecializationInfoForClassID(classId, specIndex)) or ("Spec" .. specIndex)
                importedLayouts[importedID].layoutName = "KUI - " .. specName
            end

            lm:SaveLayouts()

            -- Activate if this is the player's current spec
            -- Note: skip RefreshLayout to avoid tainting Blizzard's CooldownViewer frames.
            -- The UI reload at the end of the installer will apply the layout cleanly.
            local currentSpec = GetSpecialization()
            if currentSpec == specIndex then
                if lm.SetActiveLayoutByID then
                    lm:SetActiveLayoutByID(importedID)
                end
                lm:SaveLayouts()
            end

            -- Track per-spec install state
            ns.db.profiles = ns.db.profiles or {}
            ns.db.profiles["BlizzardCDM"] = ns.db.profiles["BlizzardCDM"] or {}
            ns.db.profiles["BlizzardCDM"][specIndex] = true
            ns.db.installedVersion = ns.version

            local charKey = UnitName("player") .. "-" .. GetRealmName()
            ns.db.perChar[charKey] = ns.db.perChar[charKey] or {}
            ns.db.perChar[charKey].loaded = true
        else
            print(ns.title .. ": Failed to import CDM layout.")
        end
        return
    end
end
