local _, ns = ...

local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

-- Shorthand for the wizard's shared frame (SubTitle / Desc1..3 / Option1..4).
local function WF() return ns.Wizard.frame end

-- Apply a button emphasis variant if the shell supports it (added in the visual
-- pass); a safe no-op until W:SetButtonVariant exists.
local function SetVariant(btn, variant)
    if btn and ns.Wizard.SetButtonVariant then ns.Wizard:SetButtonVariant(btn, variant) end
end

-- After a successful page action, hand primary emphasis from the action button to
-- Next and mark the action button "done".
local function HandoffToNext(actionBtn, doneText)
    if actionBtn then
        if doneText and actionBtn._lbl then actionBtn._lbl:SetText(doneText) end
        SetVariant(actionBtn, "done")
    end
    SetVariant(WF().Next, "primary")
end

-- Inline green ready-check texture (the Expressway font has no check glyph).
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"

------------------------------------------------------------
-- Install chime + toast notification
------------------------------------------------------------

local function PlayInstallSound()
    PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01, "Master")
end

local toastFrame
local function ShowInstallToast(message, r, g, b)
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
    text:SetTextColor(r or 1, g or 1, b or 1)
    text:SetShadowColor(0, 0, 0, 0.6)
    text:SetShadowOffset(1, -1)

    UIFrameFadeIn(f, 0.2, 0, 1)
    f:Show()

    C_Timer.After(2, function()
        UIFrameFadeOut(f, 1.5, 1, 0)
        C_Timer.After(1.6, function() f:Hide() end)
    end)

    toastFrame = f
end

local function SuccessToast(name, action)
    ShowInstallToast("|cffFF008C" .. name .. "|r " .. action)
end

------------------------------------------------------------
-- Per-addon overwrite confirmation (EllesmereUI's styled popup)
------------------------------------------------------------

-- Profiles that existed BEFORE this session opened; only these trigger overwrite
-- warnings, so imports made during the current session don't re-prompt.
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
    if preSessionProfiles[addonKey] and _G.EllesmereUI and EllesmereUI.ShowConfirmPopup then
        EllesmereUI:ShowConfirmPopup({
            title = "Overwrite?",
            message = ns.Color(displayName) .. " has already been imported. Overwrite with the fresh profile?",
            confirmText = "Overwrite",
            cancelText = "Cancel",
            onConfirm = callback,
        })
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
            return ns.Red("Out of date") .. " (" .. installed .. " -> " .. current .. ")"
        end
        return CHECK .. " " .. ns.Green("Imported")
    else
        return ns.Amber("Not Imported")
    end
end

local function GetVersionLine(addonKey)
    local current = ns.GetAddonDataVersion(addonKey)
    return current and ("Version: " .. ns.Ver(current)) or ""
end

-- Real profile lookup: the sidebar shows a completed check only for addons that
-- are actually imported, not merely stepped past.
function ns.IsAddonImported(addonKey)
    return (ns.db and ns.db.profiles and ns.db.profiles[addonKey]) ~= nil
end

local function ShowStatusAndVersion(addonKey)
    WF().Desc2:SetText("Status: " .. GetImportStatus(addonKey))
    WF().Desc3:SetText(GetVersionLine(addonKey))
end

local function ShowLoadStatusAndVersion(addonKey)
    WF().Desc2:SetText("Status: Ready to load")
    WF().Desc3:SetText(GetVersionLine(addonKey))
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

local function BuildCDMStatusText(classId, numSpecs)
    local parts = {}
    for i = 1, numSpecs do
        local _, specName = GetSpecializationInfoForClassID(classId, i)
        if specName then
            parts[#parts + 1] = specName .. ": " .. GetCDMSpecStatus(i)
        end
    end
    return table.concat(parts, " | ")
end

------------------------------------------------------------
-- Addon step list (order = installer page order)
------------------------------------------------------------

local addonSteps = {
    { key = "EllesmereUI",       display = "EllesmereUI Profile",     checkAddon = "EllesmereUI",          alwaysAvailable = true,  desc = "Your full UI: unit frames, action bars, nameplates, cast bars, and more. Healer specs auto-swap to the Healer variant." },
    { key = "Plater",            display = "Plater Nameplates",       checkAddon = "Plater",               alwaysAvailable = false, desc = "Curated Plater nameplates tuned to match the KitnUI look." },
    { key = "BuffReminders",     display = "BuffReminders",           checkAddon = "BuffReminders",        alwaysAvailable = false, desc = "Flags missing raid buffs, food, and flasks right on your HUD so you never pull under-prepped." },
    { key = "BigWigs",           display = "BigWigs",                 checkAddon = "BigWigs",              alwaysAvailable = false, desc = "Boss timers and warnings, positioned and styled for KitnUI." },
    { key = "NSRT",              display = "Northern Sky Raid Tools", checkAddon = "NorthernSkyRaidTools", alwaysAvailable = false, desc = "Northern Sky raid tooling: assignments, timers, and note sync." },
    { key = "KitnEssentials",    display = "KitnEssentials",          checkAddon = "KitnEssentials",       alwaysAvailable = false, desc = "Kitn's own quality-of-life addon: cooldowns, dungeon tools, and cleanups." },
    { key = "Blizzard_EditMode", display = "Edit Mode",               checkAddon = "Blizzard_EditMode",    alwaysAvailable = true,  desc = "The KitnUI HUD layout (frame positions) for Blizzard Edit Mode." },
    { key = "BlizzardCDM",       display = "Blizzard CDM",            checkAddon = nil,                    alwaysAvailable = true,  desc = "Per-spec Cooldown Manager layouts for your class." },
}

local function stepDesc(addonKey)
    for _, s in ipairs(addonSteps) do if s.key == addonKey then return s.desc end end
    return ""
end

------------------------------------------------------------
-- Install-mode pages
------------------------------------------------------------

local function WelcomePage()
    local f = WF()
    f.SubTitle:SetText("Welcome to " .. ns.Color("KitnUI"))
    f.Desc1:SetText("A complete, curated interface \226\128\148 unit frames, action bars, nameplates, "
        .. "boss timers, and cooldowns, all tuned to work together out of the box.")
    f.Desc2:SetText("\n" .. ns.Red("WARNING") .. ": importing overwrites each addon's current settings. "
        .. "Only the addons you click are changed \226\128\148 exit now to keep everything as it is.")
    f.Desc3:SetText("Some changes finish applying on reload. Reinstall anytime with /kitn install.")
end

local function EllesmereUIPage()
    local f = WF()
    f.SubTitle:SetText("EllesmereUI Profile")
    f.Desc1:SetText(stepDesc("EllesmereUI"))
    ShowStatusAndVersion("EllesmereUI")
    ns.Wizard:SetOption(1, "Dark Mode", function()
        ConfirmImport("EllesmereUI", "EllesmereUI Profile", function()
            ns.SetupAddon("EllesmereUI", true, false)
            ShowStatusAndVersion("EllesmereUI")
            SuccessToast("EllesmereUI Dark Mode", "profile imported!")
            PlayInstallSound()
            HandoffToNext(WF().Option1, CHECK .. " Imported")
        end)
    end)
    ns.Wizard:SetOption(2, ns.ClassColor("Class Color"), function()
        ConfirmImport("EllesmereUI", "EllesmereUI Profile", function()
            ns.SetupAddon("EllesmereUI", true, true)
            ShowStatusAndVersion("EllesmereUI")
            SuccessToast("EllesmereUI Class Color", "profile imported!")
            PlayInstallSound()
            HandoffToNext(WF().Option2, CHECK .. " Imported")
        end)
    end)
    SetVariant(WF().Option1, "selectable")
    SetVariant(WF().Option2, "selectable")
end

local function SimpleInstallPage(addonKey, displayName)
    return function()
        local f = WF()
        f.SubTitle:SetText(displayName)
        f.Desc1:SetText(stepDesc(addonKey))
        ShowStatusAndVersion(addonKey)
        ns.Wizard:SetOption(1, "Install", function()
            ConfirmImport(addonKey, displayName, function()
                ns.SetupAddon(addonKey, true)
                ShowStatusAndVersion(addonKey)
                SuccessToast(displayName, "imported!")
                PlayInstallSound()
                HandoffToNext(WF().Option1, CHECK .. " Re-import")
            end)
        end)
        SetVariant(WF().Option1, "primary")
    end
end

local function EditModePage()
    local f = WF()
    f.SubTitle:SetText("Blizzard Edit Mode")
    f.Desc1:SetText(stepDesc("Blizzard_EditMode") .. "\n" ..
        ns.Amber("After importing, set the layout on your other specs too."))
    ShowStatusAndVersion("Blizzard_EditMode")
    ns.Wizard:SetOption(1, "Install", function()
        ConfirmImport("Blizzard_EditMode", "Edit Mode", function()
            local success = ns.SetupAddon("Blizzard_EditMode", true)
            if success then
                ShowStatusAndVersion("Blizzard_EditMode")
                SuccessToast("Edit Mode", "imported!")
                PlayInstallSound()
                HandoffToNext(WF().Option1, CHECK .. " Re-import")
            else
                WF().Desc2:SetText(ns.Red("Layout limit reached (5). Delete a layout and try again."))
                ShowInstallToast("Layout limit reached!", 1, 0.2, 0.2)
            end
        end)
    end)
    SetVariant(WF().Option1, "primary")
end

------------------------------------------------------------
-- Blizzard CDM page (per-spec option buttons + persistent "Import All Specs")
------------------------------------------------------------

local cdmAllButton
local function BlizzardCDMPage()
    local f = WF()
    f.SubTitle:SetText("Blizzard Cooldown Manager")

    local cdmEnabled = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("cooldownViewerEnabled") == "1"
    if not cdmEnabled then
        f.Desc1:SetText(ns.Red("Cooldown Manager is disabled."))
        f.Desc2:SetText("Enable it in Settings > Gameplay > Combat > Cooldown Manager.")
        if cdmAllButton then cdmAllButton:Hide() end
        return
    end

    local _, _, classId = UnitClass("player")
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId)
    local classData = ns.data.BlizzardCDM and ns.data.BlizzardCDM[classId]
    if not classData or not next(classData) then
        f.Desc1:SetText("No CDM layouts available for your class yet.")
        f.Desc2:SetText("Add your layout strings to Data/Classes/BlizzardCDM.lua.")
        if cdmAllButton then cdmAllButton:Hide() end
        return
    end

    f.Desc1:SetText(stepDesc("BlizzardCDM"))
    f.Desc2:SetText(BuildCDMStatusText(classId, numSpecs))
    f.Desc3:SetText(GetVersionLine("BlizzardCDM"))

    -- Persistent "Import All Specs" button, above the option row.
    if not cdmAllButton then
        cdmAllButton = CreateFrame("Button", "KitnUICDMAllButton", f)
        cdmAllButton:SetSize(170, 30)
        ns.Wizard:StyleButton(cdmAllButton, "Import All Specs", 13, function()
            if cdmAllButton._onClick then cdmAllButton._onClick() end
        end)
        SetVariant(cdmAllButton, "selectable")
    end
    cdmAllButton._onClick = function()
        ConfirmImport("BlizzardCDM", "Blizzard CDM (All Specs)", function()
            local imported, failed = 0, 0
            for i = 1, numSpecs do
                local specData = classData[i]
                if specData and strtrim(specData) ~= "" then
                    if ns.SetupAddon("BlizzardCDM", true, i) then
                        imported = imported + 1
                    else
                        failed = failed + 1
                    end
                end
            end
            WF().Desc2:SetText(BuildCDMStatusText(classId, numSpecs))
            if failed > 0 then
                ShowInstallToast(imported .. " imported, " .. failed .. " failed (layout limit?)", 1, 0.8, 0.2)
            else
                SuccessToast("All specs", "layouts imported!")
            end
            PlayInstallSound()
            SetVariant(WF().Next, "primary")
        end)
    end
    cdmAllButton:Show()

    -- Per-spec option buttons (Option1..4, with spec icons)
    for i = 1, math.min(numSpecs, 4) do
        local _, specName, _, specIcon = GetSpecializationInfoForClassID(classId, i)
        local specData = classData[i]
        local label = specName or ("Spec " .. i)
        if specName and specIcon then
            label = "|T" .. specIcon .. ":14:14:0:0|t " .. specName
        end

        if specData and strtrim(specData) ~= "" then
            ns.Wizard:SetOption(i, label, function()
                ConfirmImport("BlizzardCDM", "Blizzard CDM", function()
                    local success = ns.SetupAddon("BlizzardCDM", true, i)
                    WF().Desc2:SetText(BuildCDMStatusText(classId, numSpecs))
                    if success then
                        SuccessToast(specName or "CDM", "layout imported!")
                        PlayInstallSound()
                        SetVariant(WF().Next, "primary")
                    else
                        WF().Desc2:SetText(ns.Red("Layout limit reached. Delete a layout and try again."))
                        ShowInstallToast("Layout limit reached!", 1, 0.2, 0.2)
                    end
                end)
            end)
        else
            ns.Wizard:SetOption(i, label, function()
                print(ns.title .. ": No data for " .. (specName or "this spec") .. ".")
            end)
        end
    end

    -- Fit the spec buttons to one row, center "Import All Specs" above them, and mark
    -- the shown buttons as selectable peers.
    local shown = math.min(numSpecs, 4)
    local w = ns.Wizard:FitOptions(shown)
    cdmAllButton:ClearAllPoints()
    cdmAllButton:SetPoint("BOTTOM", WF().Option1, "TOP", (shown - 1) * (w + 10) / 2, 14)
    for i = 1, shown do
        if WF()["Option" .. i] and WF()["Option" .. i]:IsShown() then
            SetVariant(WF()["Option" .. i], "selectable")
        end
    end
end

local function ExtrasPage()
    local f = WF()
    f.SubTitle:SetText("Extras")
    f.Desc1:SetText("Optional cleanup and quality-of-life tweaks. None are required; they just complete the KitnUI look and feel. Run any of them as many times as you like.")
    f.Desc2:SetText("")
    f.Desc3:SetText("")

    local slot = 1
    -- Chat Setup: full chat reconfigure (position, font, timestamps, named tabs).
    ns.Wizard:SetOption(slot, "Chat Setup", function()
        if ns.RunChatSetup() then
            SuccessToast("Chat", "configured!")
            PlayInstallSound()
        end
    end)
    SetVariant(WF()["Option" .. slot], "selectable")
    slot = slot + 1

    -- Optimize Settings: hook KitnEssentials' OptimizeAll (only when it's present).
    if IsAddOnLoaded("KitnEssentials") then
        ns.Wizard:SetOption(slot, "Optimize Settings", function()
            if ns.RunOptimize() then
                SuccessToast("Settings", "optimized!")
                PlayInstallSound()
            else
                ShowInstallToast("KitnEssentials not available", 1, 0.8, 0.2)
            end
        end)
        SetVariant(WF()["Option" .. slot], "selectable")
        slot = slot + 1
    end

    -- Clean Icons: hide companion minimap buttons.
    ns.Wizard:SetOption(slot, "Clean Icons", function()
        ns.RunCleanIcons()  -- shows its own popup; no toast (it overlapped the popup)
        PlayInstallSound()
    end)
    SetVariant(WF()["Option" .. slot], "selectable")
end

local function FinishPage()
    local f = WF()
    f.SubTitle:SetText("Installation Complete")
    f.Desc1:SetText("You're all set! Click " .. ns.Green("Finish") .. " to reload your UI and apply all changes.")
    f.Desc2:SetText("You can re-run this installer anytime with " .. ns.Color("/kitn install"))
    ns.Wizard:SetOption(1, "Finish", function() ns.FinishInstallation() end)
    ns.Wizard:CenterOption1()
end

------------------------------------------------------------
-- Load-mode pages (activate existing profiles, no reimport)
------------------------------------------------------------

local function WelcomeLoadPage()
    local f = WF()
    f.SubTitle:SetText(ns.Color("KitnUI") .. " Profile Loader")
    f.Desc1:SetText("This loads the " .. ns.Color("KitnUI") .. " profiles onto this character.\nIt will not reimport anything - just apply existing profiles.")
    f.Desc2:SetText("Click " .. ns.Green("Finish") .. " at the end to reload and apply changes.")
    ns.Wizard:SetOption(1, "Load All", function()
        for _, step in ipairs(addonSteps) do
            if ns.db and ns.db.profiles and ns.db.profiles[step.key] and step.key ~= "BlizzardCDM" then
                ns.SetupAddon(step.key)  -- load mode: activate existing profile, no reimport
            end
        end
        SuccessToast("All profiles", "loaded!")
        PlayInstallSound()
        SetVariant(WF().Next, "primary")
    end)
    SetVariant(WF().Option1, "primary")
end

local function EllesmereUILoadPage()
    local f = WF()
    f.SubTitle:SetText("EllesmereUI Profile")
    f.Desc1:SetText("Activate the EllesmereUI profile on this character.")
    ShowLoadStatusAndVersion("EllesmereUI")
    ns.Wizard:SetOption(1, "Dark Mode", function()
        ns.SetupAddon("EllesmereUI", false, false)
        WF().Desc2:SetText("Status: " .. ns.Green("Loaded"))
        SuccessToast("EllesmereUI Dark Mode", "profile loaded!")
        PlayInstallSound()
    end)
    ns.Wizard:SetOption(2, ns.ClassColor("Class Color"), function()
        ns.SetupAddon("EllesmereUI", false, true)
        WF().Desc2:SetText("Status: " .. ns.Green("Loaded"))
        SuccessToast("EllesmereUI Class Color", "profile loaded!")
        PlayInstallSound()
    end)
end

local function SimpleLoadPage(addonKey, displayName)
    return function()
        local f = WF()
        f.SubTitle:SetText(displayName)
        f.Desc1:SetText("Activate the " .. ns.Color(displayName) .. " profile on this character.")
        ShowLoadStatusAndVersion(addonKey)
        ns.Wizard:SetOption(1, "Load", function()
            ns.SetupAddon(addonKey)
            WF().Desc2:SetText("Status: " .. ns.Green("Loaded"))
            SuccessToast(displayName, "loaded!")
            PlayInstallSound()
        end)
    end
end

local function EditModeLoadPage()
    local f = WF()
    f.SubTitle:SetText("Blizzard Edit Mode")
    f.Desc1:SetText("Load the " .. ns.Color("KitnUI") .. " Edit Mode layout on this character.")
    ShowLoadStatusAndVersion("Blizzard_EditMode")
    ns.Wizard:SetOption(1, "Load", function()
        ns.SetupAddon("Blizzard_EditMode")
        WF().Desc2:SetText("Status: " .. ns.Green("Loaded"))
        SuccessToast("Edit Mode", "loaded!")
        PlayInstallSound()
    end)
end

local function FinishLoadPage()
    local f = WF()
    f.SubTitle:SetText("Profile Loading Complete")
    f.Desc1:SetText("You're all set! Click " .. ns.Green("Finish") .. " to reload your UI and apply all changes.")
    f.Desc2:SetText("You can load profiles again with " .. ns.Color("/kitn load"))
    ns.Wizard:SetOption(1, "Finish", function() ns.FinishInstallation() end)
    ns.Wizard:CenterOption1()
end

------------------------------------------------------------
-- Update-mode pages
------------------------------------------------------------

local function WelcomeUpdatePage()
    local f = WF()
    f.SubTitle:SetText(ns.Color("KitnUI") .. " Profile Update")
    f.Desc1:SetText("New or updated addon profiles are available.\n\n" ..
        ns.Red("WARNING") .. ": Each step overwrites your current settings for that addon.")
    f.Desc2:SetText("Click " .. ns.Green("Next") .. " to begin.")
end

local function FinishUpdatePage()
    local f = WF()
    f.SubTitle:SetText("Update Complete")
    f.Desc1:SetText("All updated profiles have been reimported! Click " .. ns.Green("Finish") .. " to reload.")
    f.Desc2:SetText("You can check for updates anytime with " .. ns.Color("/kitn update"))
    ns.Wizard:SetOption(1, "Finish", function() ns.FinishInstallation() end)
    ns.Wizard:CenterOption1()
end

------------------------------------------------------------
-- CDM-only mode intro
------------------------------------------------------------

local function WelcomeCDMPage()
    local f = WF()
    f.SubTitle:SetText("Blizzard Cooldown Manager")
    f.Desc1:SetText("Import Blizzard Cooldown Manager layouts for your current class.\n\n" ..
        "Blizzard only allows importing layouts for the class you are currently logged into.")
    f.Desc2:SetText("To import another class later, run " .. ns.Color("/kitn cdm") .. " on that character.")
end

------------------------------------------------------------
-- Build installer data for ns.Wizard:Queue()
------------------------------------------------------------

function ns:GetInstallerData(profileLoadMode, updateKeys, cdmMode)
    local pages, stepTitles, stepKeys = {}, {}, {}

    -- CDM-only mode: intro + CDM page + finish
    if cdmMode then
        tinsert(pages, WelcomeCDMPage); tinsert(stepTitles, "Introduction"); tinsert(stepKeys, false)
        tinsert(pages, BlizzardCDMPage); tinsert(stepTitles, "Blizzard CDM"); tinsert(stepKeys, "BlizzardCDM")
        tinsert(pages, FinishPage); tinsert(stepTitles, "Finish"); tinsert(stepKeys, false)
        return { Name = ns.Color("KitnUI") .. " Blizzard CDM", Pages = pages, StepTitles = stepTitles, StepKeys = stepKeys }
    end

    -- Welcome (always first)
    if profileLoadMode then
        tinsert(pages, WelcomeLoadPage)
    elseif updateKeys then
        tinsert(pages, WelcomeUpdatePage)
    else
        tinsert(pages, WelcomePage)
    end
    tinsert(stepTitles, "Welcome"); tinsert(stepKeys, false)

    -- Addon pages
    for _, step in ipairs(addonSteps) do
        if profileLoadMode then
            local isImported = ns.db and ns.db.profiles and ns.db.profiles[step.key]
            if isImported and step.key ~= "BlizzardCDM" then
                if step.key == "EllesmereUI" then
                    tinsert(pages, EllesmereUILoadPage)
                elseif step.key == "Blizzard_EditMode" then
                    tinsert(pages, EditModeLoadPage)
                else
                    tinsert(pages, SimpleLoadPage(step.key, step.display))
                end
                tinsert(stepTitles, step.short or step.display); tinsert(stepKeys, step.key)
            end
        elseif not (updateKeys and not updateKeys[step.key]) then
            local available = step.alwaysAvailable
            if not available and step.checkAddon then
                available = IsAddOnLoaded(step.checkAddon)
            end
            if available then
                if step.key == "EllesmereUI" then
                    tinsert(pages, EllesmereUIPage)
                elseif step.key == "Blizzard_EditMode" then
                    tinsert(pages, EditModePage)
                elseif step.key == "BlizzardCDM" then
                    tinsert(pages, BlizzardCDMPage)
                else
                    tinsert(pages, SimpleInstallPage(step.key, step.display))
                end
                tinsert(stepTitles, step.short or step.display); tinsert(stepKeys, step.key)
            end
        end
    end

    -- Extras (install mode only)
    if not profileLoadMode and not updateKeys then
        tinsert(pages, ExtrasPage)
        tinsert(stepTitles, "Extras"); tinsert(stepKeys, false)
    end

    -- Finish (always last)
    if profileLoadMode then
        tinsert(pages, FinishLoadPage)
    elseif updateKeys then
        tinsert(pages, FinishUpdatePage)
    else
        tinsert(pages, FinishPage)
    end
    tinsert(stepTitles, "Finish"); tinsert(stepKeys, false)

    return {
        Name = profileLoadMode and (ns.Color("KitnUI") .. " Profile Loader")
            or updateKeys and (ns.Color("KitnUI") .. " Profile Update")
            or (ns.Color("KitnUI") .. " Installation"),
        Pages = pages,
        StepTitles = stepTitles,
        StepKeys = stepKeys,
    }
end

------------------------------------------------------------
-- Open the installer (called from Core boot + /kitn slash commands)
------------------------------------------------------------

function ns.OpenInstaller(profileLoadMode, updateKeys, cdmMode)
    if InCombatLockdown() then
        print(ns.title .. ": Cannot open the installer during combat.")
        return
    end
    if not ns.EUIReady() then
        print(ns.title .. ": EllesmereUI is not ready.")
        return
    end
    ns.SnapshotProfiles()
    ns.installerIsLoadMode = profileLoadMode or false
    ns.Wizard:Queue(ns:GetInstallerData(profileLoadMode, updateKeys, cdmMode))
end

-- Hide the persistent CDM "Import All" button whenever the page changes.
ns.Wizard.ResetExtras = function()
    if cdmAllButton then cdmAllButton:Hide() end
end
