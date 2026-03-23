local _, ns = ...

local E = ns.E
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

-- Color helpers (ns.Color, ns.Green, ns.Red, ns.ClassColor) defined in Core.lua

------------------------------------------------------------
-- Install chime + toast notification
------------------------------------------------------------

local function PlayInstallSound()
    PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01, "Master")
end

local toastFrame
local function ShowInstallToast(message)
    if toastFrame then toastFrame:Hide() end

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(150)
    f:SetSize(400, 40)
    f:SetPoint("TOP", UIParent, "TOP", 0, -190)

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont(ns.FONT or "Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
    text:SetPoint("CENTER")
    text:SetText(message)
    text:SetTextColor(1, 1, 1)
    text:SetShadowColor(0, 0, 0, 0.6)
    text:SetShadowOffset(1, -1)

    UIFrameFadeIn(text, 0.2, 0, 1)
    f:Show()

    C_Timer.After(2, function()
        UIFrameFadeOut(text, 1.5, 1, 0)
        C_Timer.After(1.6, function()
            f:Hide()
        end)
    end)

    toastFrame = f
end

------------------------------------------------------------
-- Per-addon overwrite confirmation
------------------------------------------------------------

-- Snapshot of profiles that existed BEFORE this installer session opened.
-- Only these trigger overwrite warnings; imports made during the current
-- session do not re-prompt.
local preSessionProfiles = {}

function ns.SnapshotProfiles()
    wipe(preSessionProfiles)
    if ns.db and ns.db.profiles then
        for k, v in pairs(ns.db.profiles) do
            preSessionProfiles[k] = v
        end
    end
end

local function ConfirmImport(addonKey, displayName, callback)
    if preSessionProfiles[addonKey] then
        StaticPopupDialogs["KITNUI_CONFIRM_IMPORT"] = {
            text = ns.Color(displayName) .. " has already been imported.\nOverwrite with fresh profile?",
            button1 = "Overwrite",
            button2 = "Cancel",
            OnAccept = callback,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("KITNUI_CONFIRM_IMPORT")
    else
        callback()
    end
end

------------------------------------------------------------
-- Status helpers
------------------------------------------------------------

local function GetImportStatus(addonKey)
    if ns.db and ns.db.profiles and ns.db.profiles[addonKey] then
        local installed = ns.db.addonVersions and ns.db.addonVersions[addonKey]
        local current = ns.GetAddonDataVersion(addonKey)
        if installed and current and installed ~= current then
            return ns.Red("Outdated") .. " (v" .. installed .. " -> v" .. current .. ")"
        end
        return ns.Green("Imported")
    else
        return ns.Red("Not Imported")
    end
end

local function GetVersionLine(addonKey)
    local current = ns.GetAddonDataVersion(addonKey)
    return current and ("Version: " .. ns.Color(current)) or ""
end

local function ShowStatusAndVersion(addonKey)
    PluginInstallFrame.Desc2:SetText("Status: " .. GetImportStatus(addonKey))
    PluginInstallFrame.Desc3:SetText(GetVersionLine(addonKey))
end

local function ShowLoadStatusAndVersion(addonKey)
    PluginInstallFrame.Desc2:SetText("Status: Ready to load")
    PluginInstallFrame.Desc3:SetText(GetVersionLine(addonKey))
end

local function GetCDMSpecStatus(specIndex)
    local _, _, classId = UnitClass("player")
    local classData = ns.data.BlizzardCDM and ns.data.BlizzardCDM[classId]
    local specData = classData and classData[specIndex]
    if specData and strtrim(specData) ~= "" then
        return ns.Green("available")
    else
        return ns.Red("no data")
    end
end

------------------------------------------------------------
-- Addon list (order determines installer page order)
-- Each entry: { key, displayName, checkAddon, alwaysAvailable }
------------------------------------------------------------

local addonSteps = {
    { key = "ElvUI",           display = "ElvUI Profile",         checkAddon = "ElvUI",           alwaysAvailable = true },
    { key = "Details",         display = "Details",               checkAddon = "Details",          alwaysAvailable = false,  showWhenMissing = true },
    { key = "Plater",          display = "Plater Nameplates",     checkAddon = "Plater",           alwaysAvailable = false,  showWhenMissing = true },
    { key = "BigWigs",         display = "BigWigs",               checkAddon = "BigWigs",          alwaysAvailable = false,  showWhenMissing = true },
    { key = "WarpDeplete",     display = "WarpDeplete",           checkAddon = "WarpDeplete",      alwaysAvailable = false,  showWhenMissing = true },
    { key = "MRT",             display = "Method Raid Tools",     checkAddon = "MRT",              alwaysAvailable = false,  showWhenMissing = false },
    { key = "Blizzard_EditMode", display = "Edit Mode",           checkAddon = "Blizzard_EditMode", alwaysAvailable = true },
    { key = "Ayije_CDM",       display = "Ayije CDM",            checkAddon = "Ayije_CDM",        alwaysAvailable = false,  showWhenMissing = true },
    { key = "KitnEssentials",  display = "KitnEssentials",       checkAddon = "KitnEssentials",   alwaysAvailable = false,  showWhenMissing = true },
    { key = "BuffReminders",   display = "BuffReminders",        checkAddon = "BuffReminders",    alwaysAvailable = false,  showWhenMissing = true },
    { key = "BlizzardCDM",     display = "Blizzard CDM",         checkAddon = nil,                alwaysAvailable = true },
}

------------------------------------------------------------
-- Page builder functions
------------------------------------------------------------

-- Disabled page for missing/unloaded addons
local function DisabledAddonPage(displayName, checkAddon)
    return function()
        PluginInstallFrame.SubTitle:SetFormattedText(displayName)
        if checkAddon and C_AddOns.DoesAddOnExist(checkAddon) then
            PluginInstallFrame.Desc1:SetText(ns.Red(displayName .. " is disabled.") .. "\nEnable it in the addon list and reload to unlock this step.")
        else
            PluginInstallFrame.Desc1:SetText(ns.Red(displayName .. " is not installed.") .. "\nInstall it to unlock this step.")
        end
    end
end

-- Simple single-button install page
local function SimpleInstallPage(addonKey, displayName)
    return function()
        PluginInstallFrame.SubTitle:SetFormattedText(displayName)
        PluginInstallFrame.Desc1:SetText("Click below to import the " .. ns.Color(displayName) .. " profile.")
        ShowStatusAndVersion(addonKey)
        PluginInstallFrame.Option1:Show()
        PluginInstallFrame.Option1:SetScript("OnClick", function()
            ConfirmImport(addonKey, displayName, function()
                ns.SetupAddon(addonKey, true)
                ShowStatusAndVersion(addonKey)
                ShowInstallToast(displayName .. " imported!")
                PlayInstallSound()
            end)
        end)
        PluginInstallFrame.Option1:SetText("Install")
    end
end

-- Simple single-button load page (activate existing profile without reimporting)
local function SimpleLoadPage(addonKey, displayName)
    return function()
        PluginInstallFrame.SubTitle:SetFormattedText(displayName)
        PluginInstallFrame.Desc1:SetText("Click below to load the " .. ns.Color(displayName) .. " profile on this character.")
        ShowLoadStatusAndVersion(addonKey)
        PluginInstallFrame.Option1:Show()
        PluginInstallFrame.Option1:SetScript("OnClick", function()
            ns.SetupAddon(addonKey)
            PluginInstallFrame.Desc2:SetText("Status: " .. ns.Green("Loaded"))
            ShowInstallToast(displayName .. " loaded!")
            PlayInstallSound()
        end)
        PluginInstallFrame.Option1:SetText("Load")
    end
end

-- ElvUI load page (apply existing profile, no reimport)
local function ElvUILoadPage()
    PluginInstallFrame.SubTitle:SetFormattedText("ElvUI Profile")
    PluginInstallFrame.Desc1:SetText("Select the ElvUI profile to load on this character.")
    ShowLoadStatusAndVersion("ElvUI")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ns.SetupAddon("ElvUI", false, false)
        PluginInstallFrame.Desc2:SetText("Status: " .. ns.Green("Loaded"))
        ShowInstallToast("ElvUI profile loaded!")
        PlayInstallSound()
    end)
    PluginInstallFrame.Option1:SetText("Normal")
    PluginInstallFrame.Option2:Show()
    PluginInstallFrame.Option2:SetScript("OnClick", function()
        ns.SetupAddon("ElvUI", false, true)
        PluginInstallFrame.Desc2:SetText("Status: " .. ns.Green("Loaded"))
        ShowInstallToast("ElvUI Class Color profile loaded!")
        PlayInstallSound()
    end)
    PluginInstallFrame.Option2:SetText(ns.ClassColor("Class Color"))
end

-- EditMode load page
local function EditModeLoadPage()
    PluginInstallFrame.SubTitle:SetFormattedText("Blizzard Edit Mode")
    PluginInstallFrame.Desc1:SetText("Click below to load the " .. ns.Color("KitnUI") .. " Edit Mode layout on this character.")
    ShowLoadStatusAndVersion("Blizzard_EditMode")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ns.SetupAddon("Blizzard_EditMode")
        PluginInstallFrame.Desc2:SetText("Status: " .. ns.Green("Loaded"))
        ShowInstallToast("Edit Mode loaded!")
        PlayInstallSound()
    end)
    PluginInstallFrame.Option1:SetText("Load")
end

-- AyijeCDM load page
local function AyijeCDMLoadPage()
    PluginInstallFrame.SubTitle:SetFormattedText("Ayije Cooldown Manager")
    PluginInstallFrame.Desc1:SetText("Click below to load " .. ns.Color("Ayije CDM") .. " profiles on this character.\nThis will set spec-specific profiles automatically.")
    ShowLoadStatusAndVersion("Ayije_CDM")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ns.SetupAddon("Ayije_CDM")
        PluginInstallFrame.Desc2:SetText("Status: " .. ns.Green("Loaded"))
        ShowInstallToast("Ayije CDM loaded!")
        PlayInstallSound()
    end)
    PluginInstallFrame.Option1:SetText("Load")
end

-- Welcome page
local function WelcomePage()
    PluginInstallFrame.SubTitle:SetFormattedText("Welcome to " .. ns.Color("KitnUI"))
    PluginInstallFrame.Desc1:SetText(
        ns.Red("WARNING") .. ": This will overwrite settings for each addon you choose to import.\n" ..
        "Exit now if you'd like to keep your current settings.\n" ..
        "Only the addons you click will be changed."
    )
    local desc2 = ns.Color("Some changes may not be applied until you finish the installation.") .. "\n\n" ..
        "To reinstall at any time, run " .. ns.Color("/kitn install")
    if not IsAddOnLoaded("ElvUI_Anchor") then
        if C_AddOns.DoesAddOnExist("ElvUI_Anchor") then
            desc2 = ns.Red("ElvUI_Anchor is disabled!") .. "\nEnable it in the addon list and reload, or some UI elements may be mispositioned.\n\n" .. desc2
        else
            desc2 = ns.Red("ElvUI_Anchor is not installed!") .. "\nSome UI elements may be mispositioned without it.\n\n" .. desc2
        end
    end
    PluginInstallFrame.Desc2:SetText(desc2)
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ns:FinishInstallation()
    end)
    PluginInstallFrame.Option1:SetText("Skip")
end

-- ElvUI page (Normal / Class Color options)
local function ElvUIPage()
    PluginInstallFrame.SubTitle:SetFormattedText("ElvUI Profile")
    PluginInstallFrame.Desc1:SetText("Select the ElvUI profile you'd like to use.\nThis configures your unit frames, action bars, chat, and more.")
    ShowStatusAndVersion("ElvUI")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ConfirmImport("ElvUI", "ElvUI Profile", function()
            ns.SetupAddon("ElvUI", true, false)
            ShowStatusAndVersion("ElvUI")
            ShowInstallToast("ElvUI profile imported!")
            PlayInstallSound()
        end)
    end)
    PluginInstallFrame.Option1:SetText("Normal")
    PluginInstallFrame.Option2:Show()
    PluginInstallFrame.Option2:SetScript("OnClick", function()
        ConfirmImport("ElvUI", "ElvUI Profile", function()
            ns.SetupAddon("ElvUI", true, true)
            ShowStatusAndVersion("ElvUI")
            ShowInstallToast("ElvUI Class Color profile imported!")
            PlayInstallSound()
        end)
    end)
    PluginInstallFrame.Option2:SetText(ns.ClassColor("Class Color"))
end

-- Edit Mode page
local function EditModePage()
    PluginInstallFrame.SubTitle:SetFormattedText("Blizzard Edit Mode")
    PluginInstallFrame.Desc1:SetText("Import the " .. ns.Color("KitnUI") .. " Edit Mode layout for your HUD positioning.\n" .. ns.Red("After importing, set the layout on your other specializations too."))
    ShowStatusAndVersion("Blizzard_EditMode")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ConfirmImport("Blizzard_EditMode", "Edit Mode", function()
            ns.SetupAddon("Blizzard_EditMode", true)
            ShowStatusAndVersion("Blizzard_EditMode")
            ShowInstallToast("Edit Mode imported!")
            PlayInstallSound()
        end)
    end)
    PluginInstallFrame.Option1:SetText("Install")
end

-- Ayije CDM page (imports all 4 profiles + sets spec mapping)
local function AyijeCDMPage()
    PluginInstallFrame.SubTitle:SetFormattedText("Ayije Cooldown Manager")
    PluginInstallFrame.Desc1:SetText("Click below to import all " .. ns.Color("Ayije CDM") .. " profiles.\nSpec-specific profiles will be assigned automatically.")
    ShowStatusAndVersion("Ayije_CDM")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ConfirmImport("Ayije_CDM", "Ayije CDM", function()
            ns.SetupAddon("Ayije_CDM", true)
            ShowStatusAndVersion("Ayije_CDM")
            ShowInstallToast("Ayije CDM imported!")
            PlayInstallSound()
        end)
    end)
    PluginInstallFrame.Option1:SetText("Install")
end

-- KitnEssentials page (placeholder)
local function KitnEssentialsPage()
    PluginInstallFrame.SubTitle:SetFormattedText("KitnEssentials")
    PluginInstallFrame.Desc1:SetText("Import the " .. ns.Color("KitnEssentials") .. " configuration.")
    ShowStatusAndVersion("KitnEssentials")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ConfirmImport("KitnEssentials", "KitnEssentials", function()
            ns.SetupAddon("KitnEssentials", true)
            ShowStatusAndVersion("KitnEssentials")
            ShowInstallToast("KitnEssentials imported!")
            PlayInstallSound()
        end)
    end)
    PluginInstallFrame.Option1:SetText("Install")
end

-- Blizzard CDM page (per-spec buttons)
local function BlizzardCDMPage()
    PluginInstallFrame.SubTitle:SetFormattedText("Blizzard Cooldown Manager")

    -- Check if CDM is enabled
    local cdmEnabled = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("cooldownViewerEnabled") == "1"
    if not cdmEnabled then
        PluginInstallFrame.Desc1:SetText(ns.Red("Cooldown Manager is disabled."))
        PluginInstallFrame.Desc2:SetText("Enable it in Settings > Gameplay > Combat > Cooldown Manager.")
        return
    end

    local _, _, classId = UnitClass("player")
    local numSpecs = GetNumSpecializationsForClassID(classId)

    local classData = ns.data.BlizzardCDM and ns.data.BlizzardCDM[classId]
    if not classData or not next(classData) then
        PluginInstallFrame.Desc1:SetText("No CDM layouts available for your class yet.")
        PluginInstallFrame.Desc2:SetText("Export your CDM layouts and add them to Data.lua.")
        return
    end

    PluginInstallFrame.Desc1:SetText("Import cooldown layouts for each spec.")

    -- Build status text
    local statusParts = {}
    for i = 1, numSpecs do
        local _, specName = GetSpecializationInfoForClassID(classId, i)
        if specName then
            statusParts[#statusParts + 1] = specName .. ": " .. GetCDMSpecStatus(i)
        end
    end
    PluginInstallFrame.Desc2:SetText(table.concat(statusParts, " | "))
    PluginInstallFrame.Desc3:SetText(GetVersionLine("BlizzardCDM"))

    -- Show spec buttons using Option1-4 (ElvUI PluginInstaller supports up to 4)
    for i = 1, math.min(numSpecs, 4) do
        local optionBtn = PluginInstallFrame["Option" .. i]
        if optionBtn then
            local _, specName, _, specIcon = GetSpecializationInfoForClassID(classId, i)
            local specData = classData[i]

            optionBtn:Show()
            if specName and specIcon then
                optionBtn:SetText("|T" .. specIcon .. ":14:14:0:0|t " .. specName)
            elseif specName then
                optionBtn:SetText(specName)
            end

            if specData and strtrim(specData) ~= "" then
                optionBtn:SetScript("OnClick", function()
                    ConfirmImport("BlizzardCDM", "Blizzard CDM", function()
                        ns.SetupAddon("BlizzardCDM", true, i)
                        -- Refresh status
                        local parts = {}
                        for j = 1, numSpecs do
                            local _, sn = GetSpecializationInfoForClassID(classId, j)
                            if sn then
                                parts[#parts + 1] = sn .. ": " .. GetCDMSpecStatus(j)
                            end
                        end
                        PluginInstallFrame.Desc2:SetText(table.concat(parts, " | "))
                        ShowInstallToast((specName or "CDM") .. " layout imported!")
                        PlayInstallSound()
                    end)
                end)
            else
                optionBtn:SetScript("OnClick", function()
                    print(ns.title .. ": No data for " .. (specName or "this spec") .. ".")
                end)
            end
        end
    end
end

-- Finish page
local function FinishPage()
    PluginInstallFrame.SubTitle:SetFormattedText("Installation Complete")
    PluginInstallFrame.Desc1:SetText("You're all set! Click " .. ns.Green("Finish") .. " to reload your UI and apply all changes.")
    PluginInstallFrame.Desc2:SetText("You can re-run this installer anytime with " .. ns.Color("/kitn install"))
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ns:FinishInstallation()
    end)
    PluginInstallFrame.Option1:SetText("Finish")
end

-- Welcome page for profile load mode
local function WelcomeLoadPage()
    PluginInstallFrame.SubTitle:SetFormattedText(ns.Color("KitnUI") .. " Profile Loader")
    PluginInstallFrame.Desc1:SetText(
        "This will load the " .. ns.Color("KitnUI") .. " profiles onto this character.\n" ..
        "It will not reimport anything — just apply existing profiles."
    )
    PluginInstallFrame.Desc2:SetText("Please click " .. ns.Green("Finish") .. " at the end to reload and apply changes.")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ns:FinishInstallation()
    end)
    PluginInstallFrame.Option1:SetText("Skip")
end

-- Welcome page for update mode
local function WelcomeUpdatePage()
    PluginInstallFrame.SubTitle:SetFormattedText(ns.Color("KitnUI") .. " Profile Update")
    PluginInstallFrame.Desc1:SetText(
        "New or updated addon profiles are available to import.\n\n" ..
        ns.Red("WARNING") .. ": Each step will overwrite your current settings for that addon."
    )
    PluginInstallFrame.Desc2:SetText("Click " .. ns.Green("Next") .. " to begin, or " .. ns.Red("Skip") .. " to close without updating.")
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ns:FinishInstallation()
    end)
    PluginInstallFrame.Option1:SetText("Skip")
end

-- Finish page for update mode
local function FinishUpdatePage()
    PluginInstallFrame.SubTitle:SetFormattedText("Update Complete")
    PluginInstallFrame.Desc1:SetText("All updated profiles have been reimported! Click " .. ns.Green("Finish") .. " to reload.")
    PluginInstallFrame.Desc2:SetText("You can check for updates anytime with " .. ns.Color("/kitn update"))
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ns:FinishInstallation()
    end)
    PluginInstallFrame.Option1:SetText("Finish")
end

-- Welcome page for CDM mode
local function WelcomeCDMPage()
    PluginInstallFrame.SubTitle:SetFormattedText("Blizzard Cooldown Manager")
    PluginInstallFrame.Desc1:SetText(
        "Use this step to import Blizzard Cooldown Manager layouts for your current class.\n\n" ..
        "Blizzard only allows importing layouts for the class you are currently logged into."
    )
    PluginInstallFrame.Desc2:SetText("If you need to import another class later, run " .. ns.Color("/kitn cdm") .. " on that character.")
end

-- Finish page for profile load mode
local function FinishLoadPage()
    PluginInstallFrame.SubTitle:SetFormattedText("Profile Loading Complete")
    PluginInstallFrame.Desc1:SetText("You're all set! Click " .. ns.Green("Finish") .. " to reload your UI and apply all changes.")
    PluginInstallFrame.Desc2:SetText("You can load profiles again with " .. ns.Color("/kitn load"))
    PluginInstallFrame.Option1:Show()
    PluginInstallFrame.Option1:SetScript("OnClick", function()
        ns:FinishInstallation()
    end)
    PluginInstallFrame.Option1:SetText("Finish")
end

------------------------------------------------------------
-- Build installer data for E:GetModule("PluginInstaller"):Queue()
------------------------------------------------------------

function ns:GetInstallerData(profileLoadMode, updateKeys, cdmMode)
    local pages = {}
    local stepTitles = {}

    -- CDM-only mode: just show intro + CDM page + finish
    if cdmMode then
        tinsert(pages, WelcomeCDMPage)
        tinsert(stepTitles, "Introduction")
        tinsert(pages, BlizzardCDMPage)
        tinsert(stepTitles, "Blizzard CDM")
        tinsert(pages, FinishPage)
        tinsert(stepTitles, "Finish")
        return {
            Title = ns.Color("KitnUI"),
            Name = ns.Color("KitnUI") .. " Blizzard CDM",
            tutorialImage = "Interface\\AddOns\\KitnUI\\Media\\Textures\\KitnUI",
            tutorialImageSize = { 180, 180 },
            tutorialImagePoint = { 0, 10 },
            Pages = pages,
            StepTitles = stepTitles,
            StepTitlesColor = { 1, 1, 1 },
            StepTitlesColorSelected = { 1.0, 0, 0.549 },
            StepTitleWidth = 200,
            StepTitleButtonWidth = 200,
            StepTitleTextJustification = "CENTER",
        }
    end

    -- Welcome page (always first)
    if profileLoadMode then
        tinsert(pages, WelcomeLoadPage)
    elseif updateKeys then
        tinsert(pages, WelcomeUpdatePage)
    else
        tinsert(pages, WelcomePage)
    end
    tinsert(stepTitles, "Welcome")

    -- Addon pages
    for _, step in ipairs(addonSteps) do
        -- In load mode, only show addons that have been previously imported
        if profileLoadMode then
            local isImported = ns.db and ns.db.profiles and ns.db.profiles[step.key]
            if isImported and step.key ~= "BlizzardCDM" then
                if step.key == "ElvUI" then
                    tinsert(pages, ElvUILoadPage)
                elseif step.key == "Blizzard_EditMode" then
                    tinsert(pages, EditModeLoadPage)
                elseif step.key == "Ayije_CDM" then
                    tinsert(pages, AyijeCDMLoadPage)
                else
                    tinsert(pages, SimpleLoadPage(step.key, step.display))
                end
                tinsert(stepTitles, step.display)
            end
        else
            -- In update mode, skip addons that aren't in the update set
            if updateKeys and not updateKeys[step.key] then
                -- skip: not outdated
            else
                local available = step.alwaysAvailable

                if not available and step.checkAddon then
                    available = IsAddOnLoaded(step.checkAddon)
                end

                if available then
                    if step.key == "ElvUI" then
                        tinsert(pages, ElvUIPage)
                    elseif step.key == "Blizzard_EditMode" then
                        tinsert(pages, EditModePage)
                    elseif step.key == "Ayije_CDM" then
                        tinsert(pages, AyijeCDMPage)
                    elseif step.key == "KitnEssentials" then
                        tinsert(pages, KitnEssentialsPage)
                    elseif step.key == "BlizzardCDM" then
                        tinsert(pages, BlizzardCDMPage)
                    else
                        tinsert(pages, SimpleInstallPage(step.key, step.display))
                    end
                    tinsert(stepTitles, step.display)
                end
            end
        end
    end

    -- Finish page (always last)
    if profileLoadMode then
        tinsert(pages, FinishLoadPage)
    elseif updateKeys then
        tinsert(pages, FinishUpdatePage)
    else
        tinsert(pages, FinishPage)
    end
    tinsert(stepTitles, "Finish")

    return {
        Title = ns.Color("KitnUI"),
        Name = profileLoadMode and (ns.Color("KitnUI") .. " Profile Loader")
            or updateKeys and (ns.Color("KitnUI") .. " Profile Update")
            or (ns.Color("KitnUI") .. " Installation"),
        tutorialImage = "Interface\\AddOns\\KitnUI\\Media\\Textures\\KitnUI",
        tutorialImageSize = { 180, 180 },
        tutorialImagePoint = { 0, 10 },
        Pages = pages,
        StepTitles = stepTitles,
        StepTitlesColor = { 1, 1, 1 },
        StepTitlesColorSelected = { 1.0, 0, 0.549 },
        StepTitleWidth = 200,
        StepTitleButtonWidth = 200,
        StepTitleTextJustification = "CENTER",
    }
end
