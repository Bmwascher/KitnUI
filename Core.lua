local addonName, ns = ...

local E, L, V, P, G = unpack(ElvUI)
local EP = LibStub("LibElvUIPlugin-1.0")
local KitnUI = E:NewModule("KitnUI", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0")

local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

------------------------------------------------------------
-- Media paths
------------------------------------------------------------

local FONT_PATH = "Interface\\AddOns\\KitnUI\\Media\\Fonts\\Expressway.TTF"
ns.FONT = FONT_PATH
local BAR_TEXTURE_PATH = "Interface\\AddOns\\KitnUI\\Media\\Statusbars\\KitnUI_Bar"

------------------------------------------------------------
-- Register media with LibSharedMedia
------------------------------------------------------------

local LSM = LibStub("LibSharedMedia-3.0")
LSM:Register("font", "Expressway", FONT_PATH)
LSM:Register("statusbar", "KitnUI", BAR_TEXTURE_PATH)

------------------------------------------------------------
-- Shared namespace references
------------------------------------------------------------

ns.E = E
ns.KitnUI = KitnUI
ns.title = "|cffFF008CKitn|r|cffffffffUI|r"
ns.profileName = "KitnUI"
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version")
ns.data = {}
ns.db = nil

------------------------------------------------------------
-- Per-addon version tracking (X-headers in TOC)
------------------------------------------------------------

-- Maps addon keys to their TOC X-header names
local addonVersionHeaders = {
    ElvUI           = "X-ElvUI-Version",
    Details         = "X-Details-Version",
    Plater          = "X-Plater-Version",
    BigWigs         = "X-BigWigs-Version",
    WarpDeplete     = "X-WarpDeplete-Version",
    MRT             = "X-MRT-Version",
    Blizzard_EditMode = "X-EditMode-Version",
    Ayije_CDM       = "X-AyijeCDM-Version",
    KitnEssentials  = "X-KitnEssentials-Version",
    BlizzardCDM     = "X-BlizzardCDM-Version",
}

-- Read current version from TOC for a given addon key
function ns.GetAddonDataVersion(addonKey)
    local header = addonVersionHeaders[addonKey]
    if not header then return nil end
    return C_AddOns.GetAddOnMetadata(addonName, header)
end

-- Check which addons have outdated profiles since last install
function ns.GetOutdatedAddons()
    local outdated = {}
    if not ns.db or not ns.db.addonVersions then return outdated end

    for addonKey, header in pairs(addonVersionHeaders) do
        local installed = ns.db.addonVersions[addonKey]
        local current = C_AddOns.GetAddOnMetadata(addonName, header)
        if installed and current and installed ~= current then
            outdated[#outdated + 1] = {
                key = addonKey,
                oldVersion = installed,
                newVersion = current,
            }
        end
    end
    return outdated
end

------------------------------------------------------------
-- Saved variable defaults
------------------------------------------------------------

local defaults = {
    profiles = {},          -- [addonKey] = true when imported
    addonVersions = {},     -- [addonKey] = "X-header version" at time of import
    installedVersion = nil, -- addon version at last install
    perChar = {},           -- [charName-realm] = { loaded = true/false }
}

local function GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

------------------------------------------------------------
-- Color helpers (also used by Installer.lua via ns)
------------------------------------------------------------

function ns.Color(text)
    return string.format("|cffFF008C%s|r", text)
end

function ns.Green(text)
    return string.format("|cff00ff00%s|r", text)
end

function ns.Red(text)
    return string.format("|cffff0000%s|r", text)
end

function ns.ClassColor(text)
    local _, englishClass = UnitClass("player")
    local _, _, _, hex = GetClassColor(englishClass)
    return string.format("|cff%s%s|r", string.sub(hex, 3), text)
end

------------------------------------------------------------
-- Utility: check if an addon is loaded
------------------------------------------------------------

function ns:IsAddOnAvailable(addon)
    if not C_AddOns.DoesAddOnExist(addon) then return false end
    return IsAddOnLoaded(addon)
end

-- Forward declaration (defined below after ShutDownDetails)
local OpenInstaller

------------------------------------------------------------
-- Set KitnUI font as ElvUI default
------------------------------------------------------------

local function SetFont()
    E.db["general"]["font"] = "Expressway"
    E:UpdateMedia()
    E:UpdateFontTemplates()
end

------------------------------------------------------------
-- DualSpec profile config per class
-- Maps each spec index to the correct ElvUI profile name
-- (healer specs get the Healer profile variant)
------------------------------------------------------------

function ns.GetDualSpecConfig(className, useColor)
    local normal = {
        ["Shaman"] = {
            ns.profileName,               -- [1] Elemental
            ns.profileName,               -- [2] Enhancement
            ns.profileName .. " Healer",  -- [3] Restoration
            ["enabled"] = true,
        },
        ["Paladin"] = {
            ns.profileName .. " Healer",  -- [1] Holy
            ns.profileName,               -- [2] Protection
            ns.profileName,               -- [3] Retribution
            ["enabled"] = true,
        },
        ["Priest"] = {
            ns.profileName .. " Healer",  -- [1] Discipline
            ns.profileName .. " Healer",  -- [2] Holy
            ns.profileName,               -- [3] Shadow
            ["enabled"] = true,
        },
        ["Monk"] = {
            ns.profileName,               -- [1] Brewmaster
            ns.profileName .. " Healer",  -- [2] Mistweaver
            ns.profileName,               -- [3] Windwalker
            ["enabled"] = true,
        },
        ["Druid"] = {
            ns.profileName,               -- [1] Balance
            ns.profileName,               -- [2] Feral
            ns.profileName,               -- [3] Guardian
            ns.profileName .. " Healer",  -- [4] Restoration
            ["enabled"] = true,
        },
        ["Evoker"] = {
            ns.profileName,               -- [1] Devastation
            ns.profileName .. " Healer",  -- [2] Preservation
            ns.profileName,               -- [3] Augmentation
            ["enabled"] = true,
        },
    }

    local color = {
        ["Shaman"] = {
            ns.profileName .. " Colored",              -- [1]
            ns.profileName .. " Colored",              -- [2]
            ns.profileName .. " Healer Colored",       -- [3]
            ["enabled"] = true,
        },
        ["Paladin"] = {
            ns.profileName .. " Healer Colored",       -- [1]
            ns.profileName .. " Colored",              -- [2]
            ns.profileName .. " Colored",              -- [3]
            ["enabled"] = true,
        },
        ["Priest"] = {
            ns.profileName .. " Healer Colored",       -- [1]
            ns.profileName .. " Healer Colored",       -- [2]
            ns.profileName .. " Colored",              -- [3]
            ["enabled"] = true,
        },
        ["Monk"] = {
            ns.profileName .. " Colored",              -- [1]
            ns.profileName .. " Healer Colored",       -- [2]
            ns.profileName .. " Colored",              -- [3]
            ["enabled"] = true,
        },
        ["Druid"] = {
            ns.profileName .. " Colored",              -- [1]
            ns.profileName .. " Colored",              -- [2]
            ns.profileName .. " Colored",              -- [3]
            ns.profileName .. " Healer Colored",       -- [4]
            ["enabled"] = true,
        },
        ["Evoker"] = {
            ns.profileName .. " Colored",              -- [1]
            ns.profileName .. " Healer Colored",       -- [2]
            ns.profileName .. " Colored",              -- [3]
            ["enabled"] = true,
        },
    }

    if not normal[className] then
        return { ["enabled"] = false }
    end

    if useColor then
        return color[className]
    else
        return normal[className]
    end
end

------------------------------------------------------------
-- Load profiles onto current character (opens GUI)
------------------------------------------------------------

function ns:LoadProfiles()
    if not self.db.profiles or not next(self.db.profiles) then return end
    OpenInstaller(true)  -- profileLoadMode = true
end

function ns:IsCharLoaded()
    local key = GetCharKey()
    return self.db.perChar[key] and self.db.perChar[key].loaded
end

function ns:SetCharLoaded()
    local key = GetCharKey()
    self.db.perChar[key] = self.db.perChar[key] or {}
    self.db.perChar[key].loaded = true
end

------------------------------------------------------------
-- Finish installation (called from the Finish page)
------------------------------------------------------------

function ns:FinishInstallation()
    local db = ns.db
    db.installedVersion = ns.version
    db.perChar[GetCharKey()] = db.perChar[GetCharKey()] or {}
    db.perChar[GetCharKey()].loaded = true

    -- Ensure ElvUI private settings are applied
    E.private["nameplates"]["enable"] = false
    if not E.private["bags"] then E.private["bags"] = {} end
    E.private["bags"]["enable"] = false

    -- Re-enable ElvUI incompatible addon warnings now that install is done
    E.global.ignoreIncompatible = false

    -- Flag to re-show Details windows after reload
    -- (ShutDownDetails closed them when the installer opened)
    if IsAddOnLoaded("Details") then
        ns.db.showDetailsAfterReload = true
    end

    -- Hide minimap icons
    local LDBIcon = LibStub("LibDBIcon-1.0", true)

    -- LibDBIcon addons: Hide() sets db.hide = true (idempotent)
    if LDBIcon then
        for _, broker in ipairs({ "Details", "BigWigs", "Plater" }) do
            if LDBIcon:IsRegistered(broker) then
                LDBIcon:Hide(broker)
            end
        end
    end

    -- BigWigs: also set its own SavedVariable
    if IsAddOnLoaded("BigWigs") and type(BigWigsIconDB) == "table" then
        BigWigsIconDB.hide = true
    end

    -- Plater: also set its per-character SavedVariable
    if IsAddOnLoaded("Plater") and PlaterDBChr and PlaterDBChr.minimap then
        PlaterDBChr.minimap.hide = true
    end

    -- SimulationCraft & Wago: slash command toggles
    -- Only run once per character to avoid toggling icons back on
    local charKey = GetCharKey()
    db.perChar[charKey] = db.perChar[charKey] or {}
    if not db.perChar[charKey].minimapHidden then
        if IsAddOnLoaded("Simulationcraft") then
            DEFAULT_CHAT_FRAME.editBox:SetText("/simc minimap")
            ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
        end
        if IsAddOnLoaded("WagoUI") then
            DEFAULT_CHAT_FRAME.editBox:SetText("/wago minimap")
            ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
        end
        db.perChar[charKey].minimapHidden = true
    end

    -- MRT: custom minimap button (not LibDBIcon)
    if IsAddOnLoaded("MRT") then
        if VMRT and VMRT.Addon then VMRT.Addon.IconMiniMapHide = true end
        if MRT and MRT.MiniMapIcon then MRT.MiniMapIcon:Hide() end
    end

    ReloadUI()
end

------------------------------------------------------------
-- Shut down Details windows before opening installer
------------------------------------------------------------

local function ShutDownDetails()
    if IsAddOnLoaded("Details") and Details.ShutDownAllInstances then
        Details:ShutDownAllInstances()
    end
end

------------------------------------------------------------
-- Open the installer (with Details shutdown)
------------------------------------------------------------

local INSTALLER_WIDTH = 650
local INSTALLER_HEIGHT = 500
local installerHooked = false
local kitnInstallerActive = false

local function ResizeInstallerFrame()
    local f = PluginInstallFrame
    if not f then return end

    f:Size(INSTALLER_WIDTH, INSTALLER_HEIGHT)

    -- Widen text to match new frame width
    local textWidth = INSTALLER_WIDTH - 40
    if f.Desc1 then f.Desc1:Width(textWidth) end
    if f.Desc2 then f.Desc2:Width(textWidth) end
    if f.Desc3 then f.Desc3:Width(textWidth) end
    if f.Desc4 then f.Desc4:Width(textWidth) end

    -- Scale up fonts
    if f.SubTitle then f.SubTitle:FontTemplate(nil, 18, nil) end
    if f.Desc1 then f.Desc1:FontTemplate(nil, 14, nil) end
    if f.Desc2 then f.Desc2:FontTemplate(nil, 14, nil) end
    if f.Desc3 then f.Desc3:FontTemplate(nil, 14, nil) end
    if f.Desc4 then f.Desc4:FontTemplate(nil, 14, nil) end

    -- Scale up logo
    if f.tutorialImage then f.tutorialImage:Size(200, 200) end

    -- Widen option buttons (ElvUI defaults are 100px with 3+ buttons, too small for icon+text)
    local btnWidth = 140
    if f.Option3:IsShown() or f.Option4:IsShown() then
        f.Option1:Width(btnWidth)
        f.Option2:Width(btnWidth)
        if f.Option3:IsShown() then f.Option3:Width(btnWidth) end
        if f.Option4:IsShown() then f.Option4:Width(btnWidth) end
    elseif f.Option2:IsShown() then
        f.Option1:Width(btnWidth)
        f.Option2:Width(btnWidth)
    end
end

OpenInstaller = function(profileLoadMode, updateKeys, cdmMode)
    if InCombatLockdown() then
        print(ns.title .. ": Cannot open installer during combat.")
        return
    end

    ShutDownDetails()
    ns.SnapshotProfiles()

    kitnInstallerActive = true
    ns.installerIsLoadMode = profileLoadMode or false

    local PI = E:GetModule("PluginInstaller")

    -- Hook BEFORE Queue so page 1's SetPage call is caught
    if not installerHooked then
        hooksecurefunc(PI, "SetPage", function()
            if kitnInstallerActive then
                ResizeInstallerFrame()
            end
        end)
        hooksecurefunc(PI, "CloseInstall", function()
            kitnInstallerActive = false
        end)
        installerHooked = true
    end

    PI:Queue(ns:GetInstallerData(profileLoadMode, updateKeys, cdmMode))
end

------------------------------------------------------------
-- Confirmation popup for /kitn install when already installed
------------------------------------------------------------

local function ConfirmOverwriteInstall(fn)
    if ns.db and ns.db.perChar[GetCharKey()] then
        StaticPopupDialogs["KITNUI_OVERWRITE_CONFIRM"] = {
            text = ns.title .. ": You have already installed profiles. This will overwrite any local changes. If you just want to load profiles on a new character, use /kitn load instead.\n\nContinue?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = fn,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("KITNUI_OVERWRITE_CONFIRM")
    else
        fn()
    end
end

------------------------------------------------------------
-- Slash commands
------------------------------------------------------------

KitnCommands = KitnCommands or {}

KitnCommands["install"] = function()
    ConfirmOverwriteInstall(function()
        OpenInstaller()
    end)
end

KitnCommands["load"] = function()
    if not ns.db.profiles or not next(ns.db.profiles) then
        print(ns.title .. ": No profiles installed yet. Run /kitn install first.")
        return
    end
    OpenInstaller(true)
end

KitnCommands["cdm"] = function()
    OpenInstaller(false, nil, true)
end

KitnCommands["reset"] = function()
    KitnUIElvDB = nil
    ReloadUI()
end

KitnCommands["update"] = function()
    local outdated = ns.GetOutdatedAddons()
    if #outdated == 0 then
        print(ns.title .. ": All profiles are up to date.")
        return
    end
    local keys = {}
    for _, info in ipairs(outdated) do
        keys[info.key] = true
    end
    OpenInstaller(false, keys)
end

KitnCommands["version"] = function()
    print(string.format("|cffffffffKitnUI version %s|r", ns.version or "?"))

    local order = { "ElvUI", "Details", "Plater", "BigWigs", "WarpDeplete", "MRT", "Blizzard_EditMode", "Ayije_CDM", "KitnEssentials", "BlizzardCDM" }
    local names = {
        ElvUI = "ElvUI", Details = "Details", Plater = "Plater", BigWigs = "BigWigs",
        WarpDeplete = "WarpDeplete", MRT = "MRT", Blizzard_EditMode = "Edit Mode",
        Ayije_CDM = "Ayije CDM", KitnEssentials = "KitnEssentials", BlizzardCDM = "Blizzard CDM",
    }
    for _, key in ipairs(order) do
        local current = ns.GetAddonDataVersion(key)
        local installed = ns.db and ns.db.addonVersions and ns.db.addonVersions[key]
        local isImported = ns.db and ns.db.profiles and ns.db.profiles[key]
        local status, color
        if isImported then
            if installed and current and installed ~= current then
                status = "Outdated (v" .. installed .. " -> v" .. current .. ")"
                color = "|cffFF0000"  -- red
            else
                status = "Imported" .. (current and (" v" .. current) or "")
                color = "|cff00FF00"  -- green
            end
        else
            status = "Not Imported" .. (current and (" v" .. current) or "")
            color = "|cffFF0000"  -- red
        end
        print("  " .. (names[key] or key) .. ": " .. color .. status .. "|r")
    end
end
KitnCommands["ver"] = KitnCommands["version"]
KitnCommands["v"] = KitnCommands["version"]

-- Slash commands
SLASH_KITN1 = "/kitn"
SLASH_KITN2 = "/kitnui"
SLASH_KITN3 = "/kui"
SlashCmdList["KITN"] = function(msg)
    msg = strlower(strtrim(msg))
    local cmd = KitnCommands[msg]
    if cmd then
        cmd()
    elseif msg == "" then
        print(ns.title .. " v" .. (ns.version or "?"))
        print("  /kitn install  - Open the installer to import profiles")
        print("   |cffff8800Warning: This will overwrite personal customizations|r")
        print("  /kitn update   - Reimport only profiles that have been updated")
        print("  /kitn load     - Apply installed profiles to this character")
        print("  /kitn cdm      - Import Blizzard CDM layouts for your current class")
        print("  /kitn reset    - Reset installer state (does not remove addon profiles)")
        print("  /kitn version  - Show addon version")
        -- Print help lines registered by other Kitn addons (e.g. KitnEssentials)
        if KitnHelpLines then
            for _, line in ipairs(KitnHelpLines) do
                print(line)
            end
        end
    else
        print(ns.title .. ": Unknown command '" .. msg .. "'. Type |cffFF008C/kitn|r for help.")
    end
end

------------------------------------------------------------
-- ElvUI Module Initialize (called by ElvUI after all modules load)
------------------------------------------------------------

function KitnUI:Initialize()
    -- Initialize saved variables
    if not KitnUIElvDB then
        KitnUIElvDB = CopyTable(defaults)
    end
    ns.db = KitnUIElvDB

    -- Ensure tables exist
    ns.db.profiles = ns.db.profiles or {}
    ns.db.addonVersions = ns.db.addonVersions or {}
    ns.db.perChar = ns.db.perChar or {}

    -- Skip ElvUI's own installer
    E.private.install_complete = E.version

    -- Hide Lua error popups on first install
    if not ns.db.installedVersion then
        SetCVar("ScriptErrors", "0")
    end

    -- Disable ElvUI nameplates (Plater handles them)
    if not E.private.nameplates then E.private.nameplates = {} end
    E.private.nameplates.enable = false

    -- Disable ElvUI bags
    if not E.private.bags then E.private.bags = {} end
    E.private.bags.enable = false

    -- Disable bag skins (so Blizzard bags look normal)
    if not E.private.skins then E.private.skins = {} end
    if not E.private.skins.blizzard then E.private.skins.blizzard = {} end
    E.private.skins.blizzard.bags = false

    -- Ignore ElvUI incompatible addon warnings (re-enabled after install finishes)
    E.global.ignoreIncompatible = true

    -- Re-show Details windows after install reload
    if ns.db.showDetailsAfterReload and IsAddOnLoaded("Details") then
        ns.db.showDetailsAfterReload = nil
        C_Timer.After(1, function()
            DEFAULT_CHAT_FRAME.editBox:SetText("/details show")
            ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
        end)
    end

    -- Suppress Details first-run popups and news
    if IsAddOnLoaded("Details") then
        Details:AddDefaultCustomDisplays()
        Details:SetTutorialCVar("STREAMER_PLUGIN_FIRSTRUN", true)
        Details.auto_open_news_window = false
        Details:SetTutorialCVar("version_announce", 1)
        Details.character_first_run = false
        Details.is_first_run = false
    end

    -- Disable BigWigs feature share popup
    if IsAddOnLoaded("BigWigs") then
        C_Timer.After(0.1, function() BW_FEAT_SHARE = false end)
    end

    -- Set font for new characters
    if not ns.db.perChar[GetCharKey()] then
        SetFont()
    end

    local hasProfiles = ns.db.profiles and next(ns.db.profiles)
    local charKey = GetCharKey()

    -- First run: launch the installer
    if not hasProfiles and not ns.db.installedVersion then
        OpenInstaller()

    -- Version update: prompt to re-install (check both overall version and per-addon versions)
    elseif hasProfiles and ns.db.installedVersion and ns.version and ns.db.installedVersion ~= ns.version then
        local outdated = ns.GetOutdatedAddons()
        local updateText = ns.title .. " has been updated (v" .. ns.db.installedVersion .. " -> v" .. ns.version .. ")."
        if #outdated > 0 then
            local names = {}
            for _, info in ipairs(outdated) do
                names[#names + 1] = info.key
            end
            updateText = updateText .. "\n\nUpdated profiles: " .. ns.Color(table.concat(names, ", "))
        end
        updateText = updateText .. "\n\nOpen the installer to apply changes?"

        StaticPopupDialogs["KITNUI_ELV_UPDATE"] = {
            text = updateText,
            button1 = "Update",
            button2 = "Later",
            OnAccept = function()
                local fresh = ns.GetOutdatedAddons()
                if #fresh > 0 then
                    local keys = {}
                    for _, info in ipairs(fresh) do
                        keys[info.key] = true
                    end
                    OpenInstaller(false, keys)
                else
                    OpenInstaller()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("KITNUI_ELV_UPDATE")

    -- New character: prompt to load profiles via GUI
    elseif hasProfiles and not ns:IsCharLoaded() then
        StaticPopupDialogs["KITNUI_ELV_LOAD"] = {
            text = ns.title .. ": Load your installed profiles onto this character?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function() OpenInstaller(true) end,
            OnCancel = function() ns:SetCharLoaded() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("KITNUI_ELV_LOAD")
    end

    -- Login message + outdated profile notification
    C_Timer.After(2, function()
        local outdated = ns.GetOutdatedAddons()
        if #outdated > 0 then
            local names = {}
            for _, info in ipairs(outdated) do
                names[#names + 1] = ns.Color(info.key) .. " (v" .. info.oldVersion .. " -> v" .. info.newVersion .. ")"
            end
            print(ns.title .. ": " .. ns.Red("Outdated profiles: ") .. table.concat(names, ", "))
            print(ns.title .. ": Run |cffFF008C/kitn update|r to update them.")
        else
            print(ns.title .. ": Type |cffFF008C/kitn install|r to open the installer.")
        end
    end)

    -- Register with LibElvUIPlugin
    EP:RegisterPlugin(addonName, function() end)
end

E:RegisterModule(KitnUI:GetName())
