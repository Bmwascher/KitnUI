local _, ns = ...

local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

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

------------------------------------------------------------
-- EllesmereUI (core import + per-spec healer/DPS swap)
-- Public API used (all guarded): EllesmereUI.ImportProfile(str, name) ->
-- ok, err[, "spec_locked"] (auto-activates); EllesmereUI.SetProfile(name);
-- EllesmereUI.AssignProfileToSpec(name, specID); EllesmereUI.RefreshAllAddons().
------------------------------------------------------------

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
        -- DPS profile (fall back to the base export if a colored variant isn't authored yet)
        local importDpsKey = HasData(dpsKey) and dpsKey or "EllesmereUI"
        if not HasData(importDpsKey) then
            print(ns.title .. ": No EllesmereUI profile data found.")
            return false
        end
        local ok, err = EllesmereUI.ImportProfile(ns.data[importDpsKey], dpsName)
        if not ok then
            print(ns.title .. ": EllesmereUI import failed - " .. (err or "unknown error"))
            return false
        end
        ns.ApplyEUIOverrides(dpsName)

        -- Healer profile (optional; its presence enables per-spec auto-swap)
        if HasData(healerKey) then
            local hok, herr = EllesmereUI.ImportProfile(ns.data[healerKey], healerName)
            if hok then
                ns.ApplyEUIOverrides(healerName)
            else
                print(ns.title .. ": EllesmereUI healer import failed - " .. (herr or "unknown error"))
            end
        end

        CompleteSetup(addonKey)
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

-- Account-global overrides that do NOT travel in a profile export. Per-module
-- media ("sm:<name>") and settings DO ride inside the !EUI_ payload (verified
-- against EllesmereUI_Profiles.lua), so they need no poking here. ppUIScale is
-- the one relevant global: EllesmereUIDB.ppUIScale (verified EllesmereUI.lua
-- 1817/1836, account-global). Set ns.EUI_UISCALE only if KitnUI wants a specific
-- scale; otherwise this no-ops.
function ns.ApplyEUIOverrides(profileName)
    if not (EllesmereUIDB and EllesmereUIDB.profiles and EllesmereUIDB.profiles[profileName]) then return end

    if ns.EUI_UISCALE then EllesmereUIDB.ppUIScale = ns.EUI_UISCALE end
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
-- Northern Sky Raid Tools
-- Decodes NSRT's export string (AceSerializer-3.0 + LibDeflate) and writes each
-- module's data directly into the account-wide NSRT global. NSRT has no profile
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

        for i = #layouts.layouts, 1, -1 do
            if layouts.layouts[i].layoutName == ns.profileName then
                tremove(layouts.layouts, i)
            end
        end

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

    local layouts = C_EditMode.GetLayouts()
    for i, v in ipairs(layouts.layouts) do
        if v.layoutName == ns.profileName then
            C_EditMode.SetActiveLayout(Enum.EditModePresetLayoutsMeta.NumValues + i)
            return
        end
    end
end

------------------------------------------------------------
-- KitnEssentials
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

    local BR = _G.BuffReminders
    if BR and BR.SetProfile then
        BR:SetProfile(ns.profileName)
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

------------------------------------------------------------
-- Finish installation
-- Ownership: the standalone tools win, so disable the overlapping EllesmereUI
-- modules. Each EUI "module" is a SEPARATE addon folder; EUI's own toggle uses
-- C_AddOns.DisableAddOn + ReloadUI (verified EllesmereUI.lua:6682). Module on/off
-- is Blizzard's per-character addon state -- not a SavedVariable and not carried
-- in the !EUI_ export -- so it can only be set post-import, and takes effect on
-- the ReloadUI below.
------------------------------------------------------------

-- Disable one EllesmereUI module addon by folder name. Idempotent and safe:
-- no-ops if C_AddOns is unavailable or the module isn't installed.
function ns.DisableEUIModule(folder)
    if not (C_AddOns and C_AddOns.DisableAddOn) then return end
    if C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist(folder) then return end
    C_AddOns.DisableAddOn(folder)
end

function ns.FinishInstallation()
    ns.db.installedVersion = ns.version
    ns:SetCharLoaded()

    -- Disable EUI's built-ins that the standalone tools replace. Nameplates and
    -- AuraBuffReminders only when their replacement addon is present; the
    -- CooldownManager always (BlizzardCDM is the intended cooldown UI).
    if IsAddOnLoaded("Plater") then ns.DisableEUIModule("EllesmereUINameplates") end
    if IsAddOnLoaded("BuffReminders") then ns.DisableEUIModule("EllesmereUIAuraBuffReminders") end
    ns.DisableEUIModule("EllesmereUICooldownManager")

    -- Hide companion minimap icons (ported from Legacy/Core.lua FinishInstallation)
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBIcon then
        for _, broker in ipairs({ "BigWigs", "Plater", "NSRT" }) do
            if LDBIcon:IsRegistered(broker) then LDBIcon:Hide(broker) end
        end
    end
    if IsAddOnLoaded("BigWigs") and type(BigWigsIconDB) == "table" then BigWigsIconDB.hide = true end
    if IsAddOnLoaded("Plater") and PlaterDBChr and PlaterDBChr.minimap then PlaterDBChr.minimap.hide = true end

    ReloadUI()
end
