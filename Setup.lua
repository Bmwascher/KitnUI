local _, ns = ...

local E = ns.E
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

------------------------------------------------------------
-- Details auto-run script (persisted via PLAYER_LOGOUT)
------------------------------------------------------------

local DETAILS_ZONE_SCRIPT = [[local function setup(id, segType, attr, subAttr, titleOverride)
    local i = Details:GetInstance(id)
    i:SetSegmentType(segType, true)
    i:SetDisplay(nil, attr, subAttr)
    if titleOverride then i.menu_attribute_string:SetText(titleOverride) end
end

if (Details.zone_type == "party") then
    setup(1, 1, DETAILS_ATTRIBUTE_DAMAGE, 1)
    setup(2, 0, DETAILS_ATTRIBUTE_DAMAGE, 1, "Damage Overall")
    setup(3, 1, DETAILS_ATTRIBUTE_MISC, 5)
end
if (Details.zone_type == "raid" or Details.zone_type == "none") then
    setup(1, 1, DETAILS_ATTRIBUTE_DAMAGE, 1)
    setup(2, 1, DETAILS_ATTRIBUTE_HEAL, 1)
    setup(3, 1, DETAILS_ATTRIBUTE_MISC, 5)
end]]

-- Frame that re-writes our auto-run script to _detalhes_global on logout,
-- after Details has saved its own CodeTable. Fires every logout/reload
-- as long as the flag is set in our saved vars.
local detailsLogoutFrame = CreateFrame("Frame")
detailsLogoutFrame:RegisterEvent("PLAYER_LOGOUT")
detailsLogoutFrame:SetScript("OnEvent", function()
    if ns.db and ns.db.detailsRunCode and _detalhes_global then
        _detalhes_global["run_code"] = _detalhes_global["run_code"] or {}
        _detalhes_global["run_code"]["on_zonechanged"] = DETAILS_ZONE_SCRIPT
    end
end)

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

    local _profileType, _profileKey, profileData = D:Decode(cleanData)
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
        return false
    end
    return fn(addonKey, import, ...)
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

        -- Import only the 2 profiles matching the selected theme (DPS + Healer)
        ElvDB["profiles"] = ElvDB["profiles"] or {}

        local dpsKey, healerKey, dpsData, healerData
        if useColor then
            dpsKey = ns.profileName .. " Colored"
            healerKey = ns.profileName .. " Healer Colored"
            dpsData = HasData("ElvUIClassColor") and DecodeElvUIData(ns.data.ElvUIClassColor)
            healerData = HasData("ElvUIHealerClassColor") and DecodeElvUIData(ns.data.ElvUIHealerClassColor)
        else
            dpsKey = ns.profileName
            healerKey = ns.profileName .. " Healer"
            dpsData = DecodeElvUIData(ns.data.ElvUI)
            healerData = HasData("ElvUIHealer") and DecodeElvUIData(ns.data.ElvUIHealer)
        end

        if not dpsData then
            print(ns.title .. ": Failed to decode ElvUI profile data.")
            return
        end
        ElvDB["profiles"][dpsKey] = dpsData
        if healerData then ElvDB["profiles"][healerKey] = healerData end

        -- Write single private profile (all variants share it via profileKey)
        ElvPrivateDB["profiles"] = ElvPrivateDB["profiles"] or {}
        if HasData("ElvUIPrivate") then
            local privData = DecodeElvUIData(ns.data.ElvUIPrivate)
            if privData then
                ElvPrivateDB["profiles"][ns.profileName] = privData
            end
        end

        -- Merge global settings into ElvDB.global (deep merge preserves keys not in export)
        if HasData("ElvUIGlobal") then
            local globalData = DecodeElvUIData(ns.data.ElvUIGlobal)
            if globalData then
                if not ElvDB.global then ElvDB.global = {} end
                E:CopyTable(ElvDB.global, globalData)
            end
        end

        -- Import aura filters via ElvUI's Distributor API
        if HasData("ElvUIFilters") then
            local D = E:GetModule("Distributor")
            if D then
                local filterString = strtrim(ns.data.ElvUIFilters)
                local profileType, profileKey, profileData = D:Decode(filterString)
                if profileData then
                    D:SetImportedProfile(profileType, profileKey, profileData, true)
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

    -- Set profile keys so ElvUI loads the correct profiles on reload
    local charKey = UnitName("player") .. " - " .. GetRealmName()
    ElvDB["profileKeys"] = ElvDB["profileKeys"] or {}
    ElvDB["profileKeys"][charKey] = activeProfile
    ElvPrivateDB["profileKeys"] = ElvPrivateDB["profileKeys"] or {}
    ElvPrivateDB["profileKeys"][charKey] = ns.profileName

    -- Suppress reload popups triggered by SV writes and filter imports (handled by our own reload)
    StaticPopup_Hide("CONFIG_RL")
    StaticPopup_Hide("ELVUI_CONFIG_IMPORT_RELOAD")

    -- Set DualSpec profiles (auto-switch healer profile per spec)
    local className = UnitClass("player")
    ElvDB["namespaces"] = ElvDB["namespaces"] or {}
    ElvDB["namespaces"]["LibDualSpec-1.0"] = ElvDB["namespaces"]["LibDualSpec-1.0"] or {}
    ElvDB["namespaces"]["LibDualSpec-1.0"]["char"] = ElvDB["namespaces"]["LibDualSpec-1.0"]["char"] or {}
    ElvDB["namespaces"]["LibDualSpec-1.0"]["char"][charKey] = ns.GetDualSpecConfig(className, useColor)

    -- Force hideVoiceButtons on all profile variants (doesn't persist through export)
    for _, pName in ipairs({
        ns.profileName, ns.profileName .. " Colored",
        ns.profileName .. " Healer", ns.profileName .. " Healer Colored",
    }) do
        if ElvDB["profiles"] and ElvDB["profiles"][pName] then
            ElvDB["profiles"][pName]["chat"] = ElvDB["profiles"][pName]["chat"] or {}
            ElvDB["profiles"][pName]["chat"]["hideVoiceButtons"] = true
        end
    end

    -- Ensure nameplates stay disabled
    E.private["nameplates"] = E.private["nameplates"] or {}
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
        -- Args: (string, name, bImportAutoRunCode, bIsFromImportPrompt, overwriteExisting)
        -- Both auto-run flags must be true for run_code scripts to be imported from the profile string.
        Details:ImportProfile(ns.data[addonKey], ns.profileName, true, true, true)

        -- Flag for PLAYER_LOGOUT handler to persist auto-run scripts.
        -- Details stores run_code globally (not per-profile) and overwrites _detalhes_global.run_code
        -- on logout with its internal CodeTable. Our logout handler fires after to re-inject the script.
        ns.db.detailsRunCode = true

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
        if not HasData("Plater") then
            print(ns.title .. ": No Plater data found.")
            return
        end

        local profileString = ns.data.Plater
        if not Plater or not Plater.DecompressData then
            print(ns.title .. ": Plater not loaded.")
            return
        end

        -- Decompress the profile export string into a table
        local profileData = Plater.DecompressData(profileString, "print")
        if not profileData then
            print(ns.title .. ": Failed to decompress Plater profile.")
            return
        end

        -- Write only our profile (preserves user's other profiles and data)
        PlaterDB = PlaterDB or {}
        PlaterDB["profiles"] = PlaterDB["profiles"] or {}
        PlaterDB["profiles"][ns.profileName] = profileData

        -- Set profile key for this character
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
-- Retained alongside NSRT as a fallback; not wired into the installer
-- flow (see Installer.lua addonSteps). Kept so re-enabling is a one-line
-- change if NSRT adoption is reversed.
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
-- Northern Sky Raid Tools
-- Decodes NSRT's export string (AceSerializer-3.0 + LibDeflate) and
-- writes each module's data directly into the account-wide NSRT global,
-- matching what NSRT's own ImportFromTable does. NSRT has no profile
-- system, so there is nothing to activate on load.
------------------------------------------------------------

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

        -- Check layout limit (Blizzard allows max 5 custom layouts)
        if #layouts.layouts >= 5 then
            print(ns.title .. ": Edit Mode layout limit reached (5). Delete a layout and try again.")
            return false
        end

        local info = C_EditMode.ConvertStringToLayoutInfo(ns.data[addonKey])
        info.layoutName = ns.profileName
        info.layoutType = Enum.EditModeLayoutType.Account

        tinsert(layouts.layouts, info)
        C_EditMode.SaveLayouts(layouts)

        local newIndex = Enum.EditModePresetLayoutsMeta.NumValues + #layouts.layouts
        C_EditMode.SetActiveLayout(newIndex)

        CompleteSetup(addonKey)
        return true
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
        ["Demon Hunter"]  = { cast, cast, cast, ["enabled"] = true },
        ["Druid"]         = { cast, base, base, heal, ["enabled"] = true },
        ["Evoker"]        = { cast, healDual, cast, ["enabled"] = true },
        ["Hunter"]        = { base, cast, base, ["enabled"] = true },
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

setupFunctions["Ayije_CDM"] = function(_addonKey, import)
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
-- Baganator
-- Writes a named KitnUI profile into BAGANATOR_CONFIG.Profiles and sets it
-- as the active profile for this character. Only runs on explicit install
-- or load action — never on PLAYER_LOGIN — so user changes within the
-- profile persist across reloads (unlike AUI's approach).
--
-- Category groups are decoded from a JSON export string (Baganator's
-- Customise > Categories > Export) and merged into the profile. Array
-- fields are converted to the hashmap form Baganator stores internally.
------------------------------------------------------------

local function DecodeBaganatorCategories(jsonString)
    if not C_EncodingUtil or not C_EncodingUtil.DeserializeJSON then
        return nil, "C_EncodingUtil.DeserializeJSON not available"
    end

    local success, import = pcall(C_EncodingUtil.DeserializeJSON, jsonString)
    if not success or type(import) ~= "table" or type(import.categories) ~= "table" then
        return nil, "invalid Baganator export"
    end

    local out = {
        custom_categories = {},
        category_sections = {},
        category_modifications = {},
        category_hidden = {},
        category_display_order = {},
        -- Sentinels that stop Baganator from reimporting its stock defaults
        -- over our data on first boot (Initialize.lua:145). 999 stays above
        -- any DefaultImportVersion Baganator will realistically ship.
        category_default_import = 999,
        -- Our data is written in the post-migration format; skip the
        -- MigrateFormat loop (Initialize.lua:3-77).
        category_migration = 5,
    }

    for _, c in ipairs(import.categories) do
        local source = c.source or c.name
        out.custom_categories[source] = {
            name = c.name,
            search = c.search or "",
        }
    end

    for _, m in ipairs(import.modifications or {}) do
        if m.source then
            local mod = {}
            if type(m.priority) == "number" then mod.priority = m.priority end
            if m.showGroupPrefix ~= nil then mod.showGroupPrefix = m.showGroupPrefix end
            if m.group then mod.group = m.group end
            if m.color then mod.color = m.color end
            if type(m.items) == "table" then
                mod.addedItems = mod.addedItems or {}
                for _, itemID in ipairs(m.items) do
                    mod.addedItems["i:" .. tostring(itemID)] = true
                end
            end
            if type(m.pets) == "table" then
                mod.addedItems = mod.addedItems or {}
                for _, petID in ipairs(m.pets) do
                    mod.addedItems["p:" .. tostring(petID)] = true
                end
            end
            if type(m.hideIn) == "table" then
                local h = {}
                for _, key in ipairs(m.hideIn) do
                    h[key] = true
                end
                mod.hideIn = h
            end
            out.category_modifications[m.source] = mod
        end
    end

    -- Every custom category needs a modifications entry with a priority,
    -- matching Baganator's own import behaviour.
    for source in pairs(out.custom_categories) do
        out.category_modifications[source] = out.category_modifications[source] or { priority = 0 }
        if out.category_modifications[source].priority == nil then
            out.category_modifications[source].priority = 0
        end
    end

    -- C_EncodingUtil.DeserializeJSON converts numeric-string object keys
    -- (e.g. "1") into Lua numbers. Baganator looks up sections via the string
    -- form (derived from display_order entries like "_1"), so coerce keys
    -- back to strings here.
    if type(import.sections) == "table" then
        for id, s in pairs(import.sections) do
            if type(s) == "table" and type(s.name) == "string" then
                local entry = { name = s.name }
                if s.color then entry.color = s.color end
                out.category_sections[tostring(id)] = entry
            end
        end
    end

    if type(import.hidden) == "table" then
        for _, source in ipairs(import.hidden) do
            out.category_hidden[source] = true
        end
    end

    if type(import.order) == "table" then
        for i, entry in ipairs(import.order) do
            out.category_display_order[i] = entry
        end
    end

    return out
end

setupFunctions["Baganator"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No Baganator data found.")
            return
        end

        BAGANATOR_CONFIG = BAGANATOR_CONFIG or {}
        BAGANATOR_CONFIG.Profiles = BAGANATOR_CONFIG.Profiles or {}

        local src = ns.data[addonKey]
        local profile = {}

        -- Copy non-JSON fields (view modes, seen_welcome, etc.) into the profile.
        for k, v in pairs(src) do
            if k ~= "categoriesJSON" then
                profile[k] = type(v) == "table" and CopyTable(v) or v
            end
        end

        -- Decode category groups and merge into the profile.
        if type(src.categoriesJSON) == "string" and strtrim(src.categoriesJSON) ~= "" then
            local decoded, err = DecodeBaganatorCategories(src.categoriesJSON)
            if decoded then
                for k, v in pairs(decoded) do
                    profile[k] = v
                end
            else
                print(ns.title .. ": Baganator categories decode failed - " .. (err or "unknown error"))
            end
        end

        BAGANATOR_CONFIG.Profiles[ns.profileName] = profile

        -- Activate the KitnUI profile for this character (per-char SavedVar)
        BAGANATOR_CURRENT_PROFILE = ns.profileName

        CompleteSetup(addonKey)
        return
    end

    -- Load: activate the existing KitnUI profile for this character
    if BAGANATOR_CONFIG and BAGANATOR_CONFIG.Profiles and BAGANATOR_CONFIG.Profiles[ns.profileName] then
        BAGANATOR_CURRENT_PROFILE = ns.profileName
    end
end

------------------------------------------------------------
-- Blizzard Cooldown Manager (per-spec)
------------------------------------------------------------

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

        -- Remove existing layout with our profile name if present
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

        -- Count layouts after removal to check for room
        local layoutCount = 0
        local _, currentLayouts = lm:EnumerateLayouts()
        if currentLayouts then
            for _ in pairs(currentLayouts) do layoutCount = layoutCount + 1 end
        end

        -- If we didn't free a slot and layouts are at or above the limit, bail out.
        -- Blizzard CDM allows ~10 layouts; AreLayoutsFullyMaxed is unreliable for off-specs.
        if not removedExisting and lm.AreLayoutsFullyMaxed and lm:AreLayoutsFullyMaxed() then
            print(ns.title .. ": CDM layout limit reached. Delete a layout and try again.")
            return false
        end

        local layoutIDs = lm:CreateLayoutsFromSerializedData(specString)
        if layoutIDs and layoutIDs[1] then
            local importedID = layoutIDs[1]

            -- Verify the layout was actually created
            local _, postLayouts = lm:EnumerateLayouts()
            if not postLayouts or not postLayouts[importedID] then
                print(ns.title .. ": CDM layout limit reached. Delete a layout and try again.")
                return false
            end

            -- Rename the imported layout
            postLayouts[importedID].layoutName = layoutName

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

                -- Deferred re-activation for safety (matches AUI)
                C_Timer.After(0, function()
                    if not InCombatLockdown() and lm.SetActiveLayoutByID then
                        lm:SetActiveLayoutByID(importedID)
                        lm:SaveLayouts()
                    end
                end)
            end

            -- Track per-spec install state
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
