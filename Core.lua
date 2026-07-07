local addonName, ns = ...

local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

------------------------------------------------------------
-- Media paths + LibSharedMedia registration
------------------------------------------------------------

local FONT_PATH = "Interface\\AddOns\\KitnUI\\Media\\Fonts\\Expressway.TTF"
local BAR_TEXTURE_PATH = "Interface\\AddOns\\KitnUI\\Media\\Statusbars\\KitnUI_Bar"
ns.FONT = FONT_PATH

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM then
    LSM:Register("font", "Expressway", FONT_PATH)
    LSM:Register("statusbar", "KitnUI", BAR_TEXTURE_PATH)
end

------------------------------------------------------------
-- Shared namespace references
------------------------------------------------------------

ns.title = "|cffFF008CKitn|r|cffffffffUI|r"
-- TEST: all addon profiles (EllesmereUI + companions) import under this name so
-- testing doesn't overwrite your real "KitnUI" profiles. Revert to "KitnUI"
-- before shipping.
ns.profileName = "KitnUI - EUI Test"
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version")
ns.data = ns.data or {}
ns.db = nil

-- EllesmereUI readiness guard (checked before touching the EUI API / wizard).
function ns.EUIReady()
    return _G.EllesmereUI and EllesmereUI.ImportProfile and true or false
end

------------------------------------------------------------
-- Per-addon version tracking (X-headers in TOC)
------------------------------------------------------------

local addonVersionHeaders = {
    EllesmereUI       = "X-EllesmereUI-Version",
    Plater            = "X-Plater-Version",
    BigWigs           = "X-BigWigs-Version",
    NSRT              = "X-NSRT-Version",
    Blizzard_EditMode = "X-EditMode-Version",
    KitnEssentials    = "X-KitnEssentials-Version",
    BuffReminders     = "X-BuffReminders-Version",
    BlizzardCDM       = "X-BlizzardCDM-Version",
}

function ns.GetAddonDataVersion(addonKey)
    local header = addonVersionHeaders[addonKey]
    if not header then return nil end
    return C_AddOns.GetAddOnMetadata(addonName, header)
end

-- Which addons have updated data since last install, or new data never imported.
function ns.GetOutdatedAddons()
    local outdated = {}
    if not ns.db then return outdated end

    for addonKey, header in pairs(addonVersionHeaders) do
        local installed = ns.db.addonVersions and ns.db.addonVersions[addonKey]
        local current = C_AddOns.GetAddOnMetadata(addonName, header)
        local hasProfile = ns.db.profiles and ns.db.profiles[addonKey]

        if installed and current and installed ~= current then
            outdated[#outdated + 1] = {
                key = addonKey,
                oldVersion = installed,
                newVersion = current,
                isNew = false,
            }
        elseif not hasProfile and current then
            local hasData = ns.data[addonKey]
            if hasData then
                local empty = (type(hasData) == "string" and strtrim(hasData) == "")
                    or (type(hasData) == "table" and not next(hasData))
                if not empty then
                    outdated[#outdated + 1] = {
                        key = addonKey,
                        newVersion = current,
                        isNew = true,
                    }
                end
            end
        end
    end
    return outdated
end

------------------------------------------------------------
-- Saved variable defaults
------------------------------------------------------------

local defaults = {
    profiles = {},          -- [addonKey] = true when imported
    addonVersions = {},     -- [addonKey] = X-header version at time of import
    installedVersion = nil, -- addon version at last install
    perChar = {},           -- [charName-realm] = { loaded = true/false }
    devMode = false,        -- toggle dev-mode update popup (/kitn dev)
}

local function GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

------------------------------------------------------------
-- Color helpers (also used by Setup.lua / Installer.lua via ns)
------------------------------------------------------------

function ns.Color(text)
    return string.format("|cffFF008C%s|r", text)
end

-- Matches the green of the ReadyCheck-Ready checkmark texture used in the wizard,
-- so "available" / "Imported" text reads as the same green as the checks.
function ns.Green(text)
    return string.format("|cff4CC94C%s|r", text)
end

function ns.Red(text)
    return string.format("|cffFF5555%s|r", text)
end

function ns.Amber(text)
    return string.format("|cffE6B24C%s|r", text)
end

-- Soft cyan used for version numbers so they read as distinct from the pink brand
-- accent and the green/amber/red status colors.
function ns.Ver(text)
    return string.format("|cff7FD6E0%s|r", text)
end

function ns.ClassColor(text)
    local _, englishClass = UnitClass("player")
    local _, _, _, hex = GetClassColor(englishClass)
    return string.format("|cff%s%s|r", string.sub(hex, 3), text)
end

------------------------------------------------------------
-- Utility + per-character load state
------------------------------------------------------------

function ns:IsAddOnAvailable(addon)
    if not C_AddOns.DoesAddOnExist(addon) then return false end
    return IsAddOnLoaded(addon)
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
-- Slash commands (ns.OpenInstaller is assigned by Installer.lua)
------------------------------------------------------------

KitnCommands = KitnCommands or {}

KitnCommands["install"] = function()
    ConfirmOverwriteInstall(function()
        if ns.OpenInstaller then ns.OpenInstaller() end
    end)
end

KitnCommands["load"] = function()
    if not ns.db.profiles or not next(ns.db.profiles) then
        print(ns.title .. ": No profiles installed yet. Run /kitn install first.")
        return
    end
    if ns.OpenInstaller then ns.OpenInstaller(true) end
end

KitnCommands["cdm"] = function()
    if ns.OpenInstaller then ns.OpenInstaller(false, nil, true) end
end

KitnCommands["dev"] = function()
    ns.db.devMode = not ns.db.devMode
    if ns.db.devMode then
        print(ns.title .. ": Dev mode " .. ns.Green("enabled") .. ". Update popup will show on every login.")
    else
        print(ns.title .. ": Dev mode " .. ns.Red("disabled") .. ".")
    end
end

KitnCommands["reset"] = function()
    KitnUIDB = nil
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
    if ns.OpenInstaller then ns.OpenInstaller(false, keys) end
end

KitnCommands["version"] = function()
    print(string.format("|cffffffffKitnUI version %s|r", ns.version or "?"))

    local order = { "EllesmereUI", "Plater", "BigWigs", "NSRT", "Blizzard_EditMode", "KitnEssentials", "BuffReminders", "BlizzardCDM" }
    local names = {
        EllesmereUI = "EllesmereUI", Plater = "Plater", BigWigs = "BigWigs",
        NSRT = "Northern Sky Raid Tools", Blizzard_EditMode = "Edit Mode",
        KitnEssentials = "KitnEssentials", BuffReminders = "BuffReminders",
        BlizzardCDM = "Blizzard CDM",
    }
    for _, key in ipairs(order) do
        local current = ns.GetAddonDataVersion(key)
        local installed = ns.db and ns.db.addonVersions and ns.db.addonVersions[key]
        local isImported = ns.db and ns.db.profiles and ns.db.profiles[key]
        local status, color
        if isImported then
            if installed and current and installed ~= current then
                status = "Outdated (v" .. installed .. " -> v" .. current .. ")"
                color = "|cffFF0000"
            else
                status = "Imported" .. (current and (" v" .. current) or "")
                color = "|cff00FF00"
            end
        else
            status = "Not Imported" .. (current and (" v" .. current) or "")
            color = "|cffFF0000"
        end
        print("  " .. (names[key] or key) .. ": " .. color .. status .. "|r")
    end
end
KitnCommands["ver"] = KitnCommands["version"]
KitnCommands["v"] = KitnCommands["version"]

SLASH_KITN1 = "/kitn"
SLASH_KITN2 = "/kitnui"
SLASH_KITN3 = "/kui"
SlashCmdList["KITN"] = function(msg)
    msg = strlower(strtrim(msg))
    local cmd = KitnCommands[msg]
    if cmd then
        cmd()
    elseif msg == "" then
        print(ns.title .. " " .. (ns.version or "?"))
        print("  /kitn install  - Open the installer to import profiles")
        print("   |cffff8800Warning: This will overwrite personal customizations|r")
        print("  /kitn update   - Reimport only profiles that have been updated")
        print("  /kitn load     - Apply installed profiles to this character")
        print("  /kitn cdm      - Import Blizzard CDM layouts for your current class")
        print("  /kitn reset    - Reset installer state (does not remove addon profiles)")
        print("  /kitn version  - Show addon version")
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
-- SavedVariables init + boot (PLAYER_LOGIN)
------------------------------------------------------------

local function InitDB()
    if not KitnUIDB then KitnUIDB = CopyTable(defaults) end
    ns.db = KitnUIDB
    ns.db.profiles = ns.db.profiles or {}
    ns.db.addonVersions = ns.db.addonVersions or {}
    ns.db.perChar = ns.db.perChar or {}
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    InitDB()

    if not ns.EUIReady() then
        print(ns.title .. ": EllesmereUI not detected - installer unavailable.")
        return
    end

    local hasProfiles = ns.db.profiles and next(ns.db.profiles)

    -- First run: launch the installer
    if not hasProfiles and not ns.db.installedVersion then
        if ns.OpenInstaller then ns.OpenInstaller() end

    -- Version update: prompt to re-install (overall version or per-addon versions).
    -- Dev-mode: always show popup when version is unresolved (@project-version@).
    elseif hasProfiles and ns.db.installedVersion and ns.version
        and (ns.db.installedVersion ~= ns.version or ns.db.devMode)
        and ns.db.dismissedVersion ~= ns.version then
        local outdated = ns.GetOutdatedAddons()
        local updateText = ns.title .. " has been updated (" .. ns.db.installedVersion .. " -> " .. ns.version .. ")."
        if #outdated > 0 then
            local updated, new = {}, {}
            for _, info in ipairs(outdated) do
                if info.isNew then new[#new + 1] = info.key else updated[#updated + 1] = info.key end
            end
            if #updated > 0 then updateText = updateText .. "\n\nUpdated: " .. ns.Color(table.concat(updated, ", ")) end
            if #new > 0 then updateText = updateText .. "\n\nNew: " .. ns.Green(table.concat(new, ", ")) end
        end
        updateText = updateText .. "\n\nOpen the installer to apply changes?"

        StaticPopupDialogs["KITNUI_UPDATE"] = {
            text = updateText,
            button1 = "Update",
            button2 = "Later",
            OnAccept = function()
                local fresh = ns.GetOutdatedAddons()
                if #fresh > 0 then
                    local keys = {}
                    for _, info in ipairs(fresh) do keys[info.key] = true end
                    if ns.OpenInstaller then ns.OpenInstaller(false, keys) end
                elseif ns.OpenInstaller then
                    ns.OpenInstaller()
                end
            end,
            OnCancel = function() ns.db.dismissedVersion = ns.version end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("KITNUI_UPDATE")

    -- New character: prompt to load profiles via the wizard
    elseif hasProfiles and not ns:IsCharLoaded() then
        StaticPopupDialogs["KITNUI_LOAD"] = {
            text = ns.title .. ": Load your installed profiles onto this character?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function() if ns.OpenInstaller then ns.OpenInstaller(true) end end,
            OnCancel = function() ns:SetCharLoaded() end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("KITNUI_LOAD")
    end

    -- Login message + outdated profile notification
    C_Timer.After(2, function()
        local outdated = ns.GetOutdatedAddons()
        if #outdated > 0 then
            local updated, new = {}, {}
            for _, info in ipairs(outdated) do
                if info.isNew then
                    new[#new + 1] = ns.Green(info.key)
                else
                    updated[#updated + 1] = ns.Color(info.key) .. " (v" .. info.oldVersion .. " -> v" .. info.newVersion .. ")"
                end
            end
            if #updated > 0 then print(ns.title .. ": " .. ns.Red("Outdated: ") .. table.concat(updated, ", ")) end
            if #new > 0 then print(ns.title .. ": " .. ns.Green("New: ") .. table.concat(new, ", ")) end
            print(ns.title .. ": Run |cffFF008C/kitn update|r to update them.")
        else
            print(ns.title .. ": Type |cffFF008C/kitn install|r to open the installer.")
        end
    end)
end)
