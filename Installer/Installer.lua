-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Installer.lua                                               ║
-- ║  Purpose: Installer wizard pages + flow. Builds the page and ║
-- ║           step list per mode (install/load/update/cdm) and   ║
-- ║           drives the imports.                                ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

-- Shorthand for the wizard's shared frame (SubTitle / Desc1..3 / Option1..4).
local function WF() return ns.Wizard.frame end

-- Apply a button emphasis variant if the shell supports it; a safe no-op
-- otherwise.
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

---------------------------------------------------------------------------------
-- Install chime + toast notification
---------------------------------------------------------------------------------

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

-- Named in the window's accent, because the toast is drawn over the window while
-- the installer runs. The failure and warning toasts call ShowInstallToast with
-- their own fixed red or amber instead: those colours carry a meaning the accent
-- would erase.
local function SuccessToast(name, action)
    ShowInstallToast(ns.WizardColor(name) .. " " .. action)
end

---------------------------------------------------------------------------------
-- Per-addon overwrite confirmation (EllesmereUI's styled popup)
---------------------------------------------------------------------------------

-- Profiles that existed BEFORE this session opened; only these trigger overwrite
-- warnings, so imports made during the current session don't re-prompt.
local preSessionProfiles = {}

function ns.SnapshotProfiles()
    wipe(preSessionProfiles)
    if ns.db and ns.db.profiles then
        for k, v in pairs(ns.db.profiles) do
            -- BlizzardCDM's entry is a TABLE that the import writes into.
            -- Copying the reference would let this session's own imports appear
            -- in what is meant to be a frozen picture, so revisiting the CDM
            -- page would ask to overwrite a layout this run just created. Every
            -- other entry is a plain flag.
            if type(v) == "table" then
                local copy = {}
                for ik, iv in pairs(v) do copy[ik] = iv end
                preSessionProfiles[k] = copy
            else
                preSessionProfiles[k] = v
            end
        end
    end
end

-- `alreadyImported` overrides the default table-level test. CDM passes one,
-- because "this account imported some spec of some class" is not a reason to
-- warn the character in front of you.
local function ConfirmImport(addonKey, displayName, callback, alreadyImported)
    if alreadyImported ~= nil then
        if alreadyImported and _G.EllesmereUI and EllesmereUI.ShowConfirmPopup then
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
        return
    end

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

---------------------------------------------------------------------------------
-- Status helpers
---------------------------------------------------------------------------------

-- Three-way import state, and the single owner of the version compare: the status
-- line and the action button's emphasis both read it.
--   "none"     no profile was ever imported
--   "stale"    imported, but the shipped profile is a different version
--   "current"  imported and matching what ships
local function GetImportState(addonKey)
    if not (ns.db and ns.db.profiles and ns.db.profiles[addonKey]) then return "none" end
    local installed = ns.db.addonVersions and ns.db.addonVersions[addonKey]
    local current = ns.GetAddonDataVersion(addonKey)
    if installed and current and installed ~= current then return "stale" end
    return "current"
end

local function GetImportStatus(addonKey)
    local state = GetImportState(addonKey)
    if state == "none" then return ns.Amber("Not Imported") end
    if state == "stale" then return ns.Amber("Update available") end
    return CHECK .. " " .. ns.Green("Imported")
end

-- Label and emphasis for an addon page's action button. An import already
-- matching what ships needs no action, so the page opens the way it looks after a
-- successful one: the action goes quiet and Next carries the emphasis. An older
-- import is relabelled so the button agrees with the status line above it;
-- updateText covers pages whose action reads as more than the bare verb.
local function ApplyActionState(addonKey, updateText)
    local btn = WF().Option1
    if not btn then return end
    local state = GetImportState(addonKey)
    if state == "current" then
        HandoffToNext(btn, CHECK .. " Re-import")
    else
        if state == "stale" and btn._lbl then btn._lbl:SetText(updateText or "Update") end
        SetVariant(btn, "primary")
    end
end

-- Version line: the current profile version (cyan). When an older profile is
-- installed, append the installed version in a muted "(was X)" tag so the delta
-- lives here instead of cluttering the status word above.
local function GetVersionLine(addonKey)
    local current = ns.GetAddonDataVersion(addonKey)
    if not current then return "" end
    local installed = ns.db and ns.db.addonVersions and ns.db.addonVersions[addonKey]
    if installed and installed ~= current then
        return "Version: " .. ns.Ver(current) .. "  |cff9d9d9d(was " .. installed .. ")|r"
    end
    return "Version: " .. ns.Ver(current)
end

-- Real profile lookup: the sidebar shows a completed check only for addons that
-- are actually imported, not merely stepped past.
--
-- CDM answers per class. A non-empty table only means some character on this
-- account imported something, which would put a completed sidebar check beside
-- page rows reading "not imported".
function ns.IsAddonImported(addonKey)
    if addonKey == "BlizzardCDM" then return ns.HasCDMForCurrentClass() end
    return (ns.db and ns.db.profiles and ns.db.profiles[addonKey]) ~= nil
end

local function ShowStatusAndVersion(addonKey)
    if ns.Wizard.ShowStatusHeader then ns.Wizard:ShowStatusHeader("PROFILE STATUS") end
    WF().Desc2:SetText("Status: " .. GetImportStatus(addonKey))
    WF().Desc3:SetText(GetVersionLine(addonKey))
end

local function ShowLoadStatusAndVersion(addonKey)
    if ns.Wizard.ShowStatusHeader then ns.Wizard:ShowStatusHeader("PROFILE STATUS") end
    WF().Desc2:SetText("Status: Ready to load")
    WF().Desc3:SetText(GetVersionLine(addonKey))
end

-- One label per state from ns.GetCDMSpecState. Three colours only: green is done,
-- amber is an action worth taking, red is a layout this character does not have.
local cdmStateLabel = {
    nodata    = function() return ns.Red("no data") end,
    missing   = function() return ns.Red("not imported") end,
    untracked = function() return ns.Amber("untracked") end,
    current   = function() return ns.Green("up to date") end,
    stale     = function() return ns.Amber("update available") end,
}

-- The same three states as a mark, for the per-spec buttons. One set of ready-check
-- art, so the marks are drawn to sit together, and each colour matches the word
-- cdmStateLabel gives the same state.
local CDM_MARK_X    = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t"
local CDM_MARK_WAIT = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t"
local cdmStateMark = {
    nodata    = CDM_MARK_X,
    missing   = CDM_MARK_X,
    untracked = CDM_MARK_WAIT,
    stale     = CDM_MARK_WAIT,
    current   = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t",
}

-- Rows come from ns.GetCDMSpecRows, the single owner of the specialization API
-- on the status surfaces. The icon leads each entry so this line and the buttons
-- below it identify a spec the same way.
local function CDMSpecIcon(row)
    if not row.specIcon then return "" end
    return "|T" .. row.specIcon .. ":14:14:0:0|t "
end

local function BuildCDMStatusText(rows)
    local parts = {}
    for _, row in ipairs(rows or {}) do
        local label = cdmStateLabel[row.state]
        parts[#parts + 1] = CDMSpecIcon(row) .. row.specName .. ": " .. (label and label() or row.state)
    end
    return table.concat(parts, " | ")
end

---------------------------------------------------------------------------------
-- Addon step list (order = installer page order)
---------------------------------------------------------------------------------

local addonSteps = {
    { key = "EllesmereUI",       display = "EllesmereUI",             checkAddon = "EllesmereUI",          alwaysAvailable = true,  desc = "Your full UI: unit frames, action bars, nameplates, cast bars, and more. It is ONE profile, not a set: every DPS spec, healer, and the Dark and Colored looks are all baked into it. Switch between them in KitnUI's EllesmereUI tab." },
    -- PLATER IS DORMANT, NOT REMOVED. Its data file ships an empty string, so
    -- offering the step would put a tickbox in the wizard whose only possible
    -- outcome is "No Plater data found." in chat. `dormant` hides it: the page
    -- builder below skips a dormant step for install and update pages, and does
    -- NOT skip it for load pages. That asymmetry is the point -- an install from
    -- an older KitnUI has a real Plater profile in PlaterDB, and /kitn load on
    -- an alt must still re-select it. Remove `dormant` once the data file
    -- carries a real export.
    { key = "Plater",            display = "Plater Nameplates",       checkAddon = "Plater",               alwaysAvailable = false, dormant = true, desc = "Curated Plater nameplates tuned to match the KitnUI look." },
    { key = "BuffReminders",     display = "BuffReminders",           checkAddon = "BuffReminders",        alwaysAvailable = false, desc = "Flags missing raid buffs, food, and flasks right on your HUD so you never pull under-prepped." },
    { key = "BigWigs",           display = "BigWigs",                 checkAddon = "BigWigs",              alwaysAvailable = false, desc = "Boss timers and warnings, positioned and styled for KitnUI." },
    { key = "NSRT",              display = "Northern Sky Raid Tools", checkAddon = "NorthernSkyRaidTools", alwaysAvailable = false, desc = "Northern Sky raid tooling: assignments, timers, and note sync." },
    { key = "KitnEssentials",    display = "KitnEssentials",          checkAddon = "KitnEssentials",       alwaysAvailable = false, desc = "Kitn's own quality-of-life addon: cooldowns, dungeon tools, and cleanups." },
    { key = "Baganator",         display = "Baganator",               checkAddon = "Baganator",            alwaysAvailable = false, desc = "Category-sorted bags and bank, with the KitnUI group layout and search rules." },
    { key = "Blizzard_EditMode", display = "Edit Mode",               checkAddon = "Blizzard_EditMode",    alwaysAvailable = true,  desc = "The KitnUI HUD layout (frame positions) for Blizzard Edit Mode." },
    { key = "BlizzardCDM",       display = "Blizzard CDM",            checkAddon = nil,                    alwaysAvailable = true,  desc = "Per-spec Cooldown Manager layouts for your class." },
}

local function stepDesc(addonKey)
    for _, s in ipairs(addonSteps) do if s.key == addonKey then return s.desc end end
    return ""
end

---------------------------------------------------------------------------------
-- Install-mode pages
---------------------------------------------------------------------------------

-- The window's two looks, offered here because the Welcome page has no action of
-- its own to compete with. The keys are what ns.SetInstallerTheme speaks; the
-- labels are the names the options panel gives the same two designs.
local WIZARD_THEMES = {
    { key = "default", label = "KitnUI" },
    { key = "alt",     label = "KitnUI Rasta" },
}

local function ShowThemeOptions()
    local alt = ns.UsesAltTheme and ns.UsesAltTheme()
    local current = alt and "alt" or "default"
    for i, theme in ipairs(WIZARD_THEMES) do
        ns.Wizard:SetOption(i, theme.label, function()
            -- Repainting is the writer's job: a click that could not be stored
            -- must not leave the window showing a theme nothing remembers.
            if not ns.SetInstallerTheme(theme.key) then
                ShowInstallToast("Could not identify this character - theme not saved", 1, 0.8, 0.2)
            end
        end)
        SetVariant(WF()["Option" .. i], current == theme.key and "selected" or "selectable")
    end
    ns.Wizard:SetOptionHint("INSTALLER THEME (" .. ns.WizardColor(current == "alt" and "RASTA" or "KITN") .. ")")
end

local function WelcomePage()
    local f = WF()
    f.SubTitle:SetText("Welcome to " .. ns.WizardColor("KitnUI"))
    ns.Wizard:SetTitleIcon(true)
    f.Desc1:SetText("A complete, curated interface \226\128\148 unit frames, action bars, nameplates, "
        .. "boss timers, and cooldowns, all tuned to work together out of the box.")
    f.Desc2:SetText("\n" .. ns.Red("WARNING") .. ": importing overwrites each addon's current settings. "
        .. "Only the addons you click are changed \226\128\148 exit now to keep everything as it is.")
    f.Desc3:SetText("Some changes finish applying on reload. Reinstall anytime with /kitn install.")
    ShowThemeOptions()
end

-- The two EllesmereUI appearance presets, offered on this page once the profile
-- is in. KitnUI_EUI/General.lua owns them: the KEYS are what ns.ApplyLook and
-- ns.CurrentLook speak, and the labels are copies of its LOOKS table. Both
-- functions arrive through the EXPORTS bridge in KitnUI_EUI/Core.lua and are nil
-- when that addon is missing, so every use below is guarded.
local EUI_LOOKS = {
    { key = "dark",  label = "Dark" },
    { key = "color", label = "Colored" },
}

-- Forward-declared: the look buttons rebuild the page they sit on, which is the
-- only thing that moves the highlight onto the look just applied.
local EllesmereUIPage

-- A standing choice, not one of the page's actions, so the looks get their own
-- captioned row above the action row instead of sitting beside Install as equals.
-- Built once and reused like the CDM page's button; ResetExtras hides them.
local lookRow, lookCaption

local function BuildLookRow(parent)
    if lookRow then return end
    lookRow = {}
    for i, look in ipairs(EUI_LOOKS) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(150, 30)  -- under the action row's 165x34: a choice, not the action
        ns.Wizard:StyleButton(b, look.label, 13, function()
            if b._onClick then b._onClick() end
        end)
        if i == 1 then
            b:SetPoint("BOTTOMLEFT", parent.Option1, "TOPLEFT", 0, 44)
        else
            b:SetPoint("LEFT", lookRow[i - 1], "RIGHT", 10, 0)
        end
        lookRow[i] = b
    end
    if EllesmereUI and EllesmereUI.MakeFont then
        lookCaption = EllesmereUI.MakeFont(parent, 11, "", 1, 1, 1, 0.5)
        lookCaption:SetJustifyH("LEFT")
        lookCaption:SetPoint("BOTTOMLEFT", lookRow[1], "TOPLEFT", 0, 10)
    end
end

local function HideLookRow()
    if not lookRow then return end
    for _, b in ipairs(lookRow) do b:Hide() end
    if lookCaption then lookCaption:Hide() end
end

-- Names the look that is live right now, the way the config page's own section
-- header does. The caption is the only thing that reports Custom, which marks no
-- button.
local function LookCaptionText(current)
    local name = "CUSTOM"
    for _, look in ipairs(EUI_LOOKS) do
        if look.key == current then name = look.label:upper() end
    end
    return "APPEARANCE (" .. ns.WizardColor(name) .. ")"
end

local function ShowLookOptions()
    if not (ns.ApplyLook and ns.IsAddonImported("EllesmereUI")) then
        -- No profile yet: say where the looks live rather than offering them.
        HideLookRow()
        ns.Wizard:SetOptionHint("Dark and Colored are a preset in KitnUI's EllesmereUI tab, not separate profiles.")
        return
    end
    ns.Wizard:HideOptionHint()
    BuildLookRow(WF())
    -- nil is Custom: the user has hand-edited a colour, so neither look is live
    -- and neither button is marked.
    local current = ns.CurrentLook and ns.CurrentLook() or nil
    for i, look in ipairs(EUI_LOOKS) do
        local b = lookRow[i]
        b._onClick = function()
            -- ns.ApplyLook is the RAW apply. The combat refusal lives in the
            -- config page's own wrapper, not in it, so without this guard a
            -- mid-fight click stores a look the screen never finishes painting.
            if InCombatLockdown() then
                ShowInstallToast("Appearance cannot be changed in combat", 1, 0.8, 0.2)
                return
            end
            ns.ApplyLook(look.key)
            EllesmereUIPage()
        end
        SetVariant(b, current == look.key and "selected" or "selectable")
        b:Show()
    end
    if lookCaption then
        lookCaption:SetText(LookCaptionText(current))
        lookCaption:Show()
    end
end

function EllesmereUIPage()
    local f = WF()
    -- Hand-written, unlike the generic pages that title themselves from the
    -- step's `display` field, so keep the two in step by hand.
    f.SubTitle:SetText("EllesmereUI")
    f.Desc1:SetText(stepDesc("EllesmereUI"))
    ShowStatusAndVersion("EllesmereUI")
    -- Bail out before the success feedback when the import fails, so a failure
    -- cannot announce itself as a success.
    ns.Wizard:SetOption(1, "Install Profile", function()
        ConfirmImport("EllesmereUI", "EllesmereUI Profile", function()
            if not ns.SetupAddon("EllesmereUI", true) then
                ShowInstallToast("EllesmereUI import failed", 1, 0.2, 0.2)
                return
            end
            ShowStatusAndVersion("EllesmereUI")
            SuccessToast("EllesmereUI", "profile imported!")
            PlayInstallSound()
            HandoffToNext(WF().Option1, CHECK .. " Re-import")
            -- The import applies Dark (Setup.lua), so the buttons appear already
            -- marked. Called here rather than only at page entry so a first
            -- install does not have to leave and come back to see them.
            ShowLookOptions()
        end)
    end)
    ApplyActionState("EllesmereUI", "Update Profile")
    ShowLookOptions()
end

local function SimpleInstallPage(addonKey, displayName)
    return function()
        local f = WF()
        f.SubTitle:SetText(displayName)
        f.Desc1:SetText(stepDesc(addonKey))
        ShowStatusAndVersion(addonKey)
        ns.Wizard:SetOption(1, "Install", function()
            ConfirmImport(addonKey, displayName, function()
                -- `== false`, never `not`: a setup function that succeeded
                -- returns nothing, so a plain truth test would report every
                -- successful step as a failure. Only an EXPLICIT false is a
                -- refusal, which is what stops a failed import being announced
                -- as a successful one.
                if ns.SetupAddon(addonKey, true) == false then
                    ShowInstallToast(displayName .. " import failed", 1, 0.2, 0.2)
                    return
                end
                ShowStatusAndVersion(addonKey)
                SuccessToast(displayName, "imported!")
                PlayInstallSound()
                HandoffToNext(WF().Option1, CHECK .. " Re-import")
            end)
        end)
        ApplyActionState(addonKey)
    end
end

---------------------------------------------------------------------------------
-- Northern Sky Raid Tools page (the generic install page plus the nickname field)
---------------------------------------------------------------------------------

-- Hidden when NSRT cannot be read at all: a box that can never save anything is
-- worse than no box. An NSRT that is simply missing a nickname reads as "", not
-- nil, so the people the field is actually for still get it.
local function ShowNicknameInput()
    local current = ns.GetNSRTNickname and ns.GetNSRTNickname()
    if not current then return end
    -- 48, not NSRT's own 12. NSRT counts CHARACTERS (its Utf8Sub cut) while the
    -- EditBox budget counts something this addon cannot establish from the API
    -- reference, and a UTF-8 character runs to four bytes: a 12 at the box would
    -- clip a Cyrillic or Korean name that NSRT stores perfectly well. 48 holds
    -- any 12-character name under either reading, and NSRT still makes the
    -- authoritative cut on write, which the read-back after commit displays.
    ns.Wizard:ShowInput({
        label       = "YOUR NICKNAME",
        text        = current,
        placeholder = "Type a nickname",
        maxLetters  = 48,
        onCommit    = function(value)
            ns.SetNSRTNickname(value)
            -- Read back what NSRT actually kept. A trimmed, truncated or refused
            -- value then shows in the box instead of being assumed saved.
            ns.Wizard:SetInputText(ns.GetNSRTNickname() or "")
        end,
    })
end

-- NSRT gets a hand-written page rather than SimpleInstallPage only so it can
-- carry the nickname field. The install half below is SimpleInstallPage's,
-- unchanged, `== false` refusal test included.
--
-- The field and the import do not interact: the nickname is not profile content
-- and NSRT carries it across its own profile writes. See Setup.lua.
local function NSRTPage()
    local f = WF()
    f.SubTitle:SetText("Northern Sky Raid Tools")
    f.Desc1:SetText(stepDesc("NSRT"))
    ShowStatusAndVersion("NSRT")
    ns.Wizard:SetOption(1, "Install", function()
        ConfirmImport("NSRT", "Northern Sky Raid Tools", function()
            if ns.SetupAddon("NSRT", true) == false then
                ShowInstallToast("Northern Sky Raid Tools import failed", 1, 0.2, 0.2)
                return
            end
            ShowStatusAndVersion("NSRT")
            SuccessToast("Northern Sky Raid Tools", "imported!")
            PlayInstallSound()
            HandoffToNext(WF().Option1, CHECK .. " Re-import")
        end)
    end)
    ApplyActionState("NSRT")
    ShowNicknameInput()
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
                -- Kept generic: the setup function already printed the specific
                -- reason, and a false return covers several causes that naming
                -- any one of them would mislabel.
                WF().Desc2:SetText(ns.Red("Edit Mode import failed. See chat for the reason."))
                ShowInstallToast("Edit Mode import failed", 1, 0.2, 0.2)
            end
        end)
    end)
    ApplyActionState("Blizzard_EditMode")
end

---------------------------------------------------------------------------------
-- Blizzard CDM page (per-spec option buttons + persistent "Import All Specs")
---------------------------------------------------------------------------------

-- Spec icon names the spec, status mark answers whether it needs anything.
local function CDMSpecLabel(row)
    local label = CDMSpecIcon(row) .. row.specName
    local mark = cdmStateMark[row.state]
    if mark then label = label .. " " .. mark end
    return label
end

-- Re-label the spec buttons from fresh rows. Every site that refreshes the status
-- text calls this too, so a mark cannot outlive the words it matches.
local function RefreshCDMSpecLabels(rows)
    for i = 1, math.min(#rows, 4) do
        local btn = WF()["Option" .. i]
        if btn and btn._lbl then btn._lbl:SetText(CDMSpecLabel(rows[i])) end
    end
end

local cdmAllButton

-- Smaller type than the wizard default: the spec buttons narrow to fit four across
-- and each already carries a spec icon and a status mark.
local CDM_SPEC_FONT = 13

-- Emphasis for the all-specs button, from the same reading the marks come from.
-- Specs with nothing shipped are excluded by GetOutdatedCDMSpecs, so a class KitnUI
-- cannot fully serve still reaches the finished state rather than asking forever.
local function ApplyCDMActionState()
    if not cdmAllButton then return end
    if #ns.GetOutdatedCDMSpecs() > 0 then
        if cdmAllButton._lbl then cdmAllButton._lbl:SetText("Import All Specs") end
        SetVariant(cdmAllButton, "primary")
    else
        HandoffToNext(cdmAllButton, CHECK .. " Re-import All")
    end
end

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

    -- The class id and the rows come from ONE guarded call.
    local classId, rows = ns.GetCDMSpecRows()
    local classData = classId and ns.data.BlizzardCDM and ns.data.BlizzardCDM[classId]
    if not classId or #rows == 0 or not classData or not next(classData) then
        f.Desc1:SetText("No CDM layouts available for your class yet.")
        f.Desc2:SetText("Add your layout strings to Data/Classes/BlizzardCDM.lua.")
        if cdmAllButton then cdmAllButton:Hide() end
        return
    end
    local numSpecs = #rows
    local preCDM = preSessionProfiles.BlizzardCDM

    f.Desc1:SetText(stepDesc("BlizzardCDM"))
    if ns.Wizard.ShowStatusHeader then ns.Wizard:ShowStatusHeader("PROFILE STATUS") end
    f.Desc2:SetText(BuildCDMStatusText(rows))
    f.Desc3:SetText(ns.SummarizeCDMRows(rows) .. " |cff9d9d9d(this class)|r")

    -- Persistent "Import All Specs" button, above the option row.
    if not cdmAllButton then
        cdmAllButton = CreateFrame("Button", "KitnUICDMAllButton", f)
        -- Larger than a spec button: one press does the work of all of them, so it
        -- should not read as a fourth peer sitting above the row.
        cdmAllButton:SetSize(290, 30)
        ns.Wizard:StyleButton(cdmAllButton, "Import All Specs", 14, function()
            if cdmAllButton._onClick then cdmAllButton._onClick() end
        end)
    end
    cdmAllButton._onClick = function()
        ConfirmImport("BlizzardCDM", "Blizzard CDM (All Specs)", function()
            local imported, failed, skipped = ns.ImportCDMAllSpecs()
            local _, freshRows = ns.GetCDMSpecRows()
            WF().Desc2:SetText(BuildCDMStatusText(freshRows))
            WF().Desc3:SetText(ns.SummarizeCDMRows(freshRows) .. " |cff9d9d9d(this class)|r")
            RefreshCDMSpecLabels(freshRows)
            if failed > 0 then
                ShowInstallToast(imported .. " imported, " .. failed .. " failed (see chat)", 1, 0.8, 0.2)
            elseif skipped then
                -- The page hides this button when the Cooldown Manager is off,
                -- but it reads that CVar once at render and the user can switch
                -- it off in Blizzard's settings while the wizard is open. Zero
                -- failures then means nothing was attempted, not that it worked.
                ShowInstallToast("Cooldown Manager is off - nothing imported (see chat)", 1, 0.8, 0.2)
            else
                SuccessToast("All specs", "layouts imported!")
            end
            PlayInstallSound()
            ApplyCDMActionState()
        end, ns.CDMNeedsOverwriteConfirm(preCDM, classId, nil))
    end
    cdmAllButton:Show()
    -- Outside the creation guard: the variant resolves the accent when it is set,
    -- so a button styled once would keep the old theme's colours after a swap.
    ApplyCDMActionState()

    -- Per-spec option buttons (Option1..4).
    for i = 1, math.min(numSpecs, 4) do
        local row = rows[i]
        local specName = row.specName
        local specData = classData[i]
        local label = CDMSpecLabel(row)

        if specData and strtrim(specData) ~= "" then
            ns.Wizard:SetOption(i, label, function()
                ConfirmImport("BlizzardCDM", "Blizzard CDM", function()
                    local success = ns.SetupAddon("BlizzardCDM", true, i)
                    local _, freshRows = ns.GetCDMSpecRows()
                    WF().Desc2:SetText(BuildCDMStatusText(freshRows))
                    WF().Desc3:SetText(ns.SummarizeCDMRows(freshRows) .. " |cff9d9d9d(this class)|r")
                    RefreshCDMSpecLabels(freshRows)
                    if success then
                        SuccessToast(specName, "layout imported!")
                        PlayInstallSound()
                        ApplyCDMActionState()
                    else
                        -- The cause is NOT named here. The setup function fails
                        -- on several paths and prints the real reason to chat on
                        -- every one; this branch cannot tell them apart.
                        WF().Desc2:SetText(ns.Red("Import failed. See chat for the reason."))
                        ShowInstallToast("Import failed!", 1, 0.2, 0.2)
                    end
                end, ns.CDMNeedsOverwriteConfirm(preCDM, classId, i))
            end, CDM_SPEC_FONT)
        else
            ns.Wizard:SetOption(i, label, function()
                print(ns.title .. ": No data for " .. (specName or "this spec") .. ".")
            end, CDM_SPEC_FONT)
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
    f.Desc1:SetText("Optional cleanup and quality-of-life tweaks. None are required; they just complete the KitnUI look and feel. Run any of them as many times as you like.\n\n" ..
        ns.Amber("Chat Setup") .. " rebuilds your chat from scratch, so any tabs or channels you set up yourself are replaced.")
    f.Desc2:SetText("")
    f.Desc3:SetText("")

    local slot = 1
    -- Chat Setup: resets the chat windows, then rebuilds the KitnUI tab set,
    -- channels and CVars on top. The reset is why Desc1 above warns about it.
    ns.Wizard:SetOption(slot, "Chat Setup", function()
        if ns.RunChatSetup() then
            if ns.sessionExtras then ns.sessionExtras.chat = true end
            -- Account-wide opt-in. WoW's chat layout is per character, so this is
            -- what lets a later /kitn load rebuild it on an alt.
            if ns.db and ns.db.extras then ns.db.extras.chat = true end
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
                if ns.sessionExtras then ns.sessionExtras.optimize = true end
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
        if ns.sessionExtras then ns.sessionExtras.cleanIcons = true end
        ns.RunCleanIcons()  -- shows its own popup; no toast (it overlapped the popup)
        PlayInstallSound()
    end)
    SetVariant(WF()["Option" .. slot], "selectable")
end

-- Finish-recap labels + display order (BlizzardCDM's value is a per-spec table).
local recapNames = {
    EllesmereUI = "EllesmereUI", Plater = "Plater", BigWigs = "BigWigs",
    NSRT = "Northern Sky Raid Tools", Blizzard_EditMode = "Edit Mode",
    KitnEssentials = "KitnEssentials", BuffReminders = "BuffReminders",
    Baganator = "Baganator", BlizzardCDM = "Blizzard CDM",
}
local recapOrder = { "EllesmereUI", "Plater", "BuffReminders", "BigWigs", "NSRT", "KitnEssentials", "Baganator", "Blizzard_EditMode", "BlizzardCDM" }

local function IsProfileImported(key)
    -- Per class, like ns.IsAddonImported: the recap describes the character that
    -- just ran the wizard, not the account.
    if key == "BlizzardCDM" then return ns.HasCDMForCurrentClass() end
    local v = ns.db and ns.db.profiles and ns.db.profiles[key]
    return v and (type(v) ~= "table" or next(v)) and true or false
end

local function BuildImportedList()
    local list = {}
    for _, key in ipairs(recapOrder) do
        if IsProfileImported(key) then
            list[#list + 1] = recapNames[key] or key
        end
    end
    return list
end

-- Addons that had a page this session but weren't imported. A missing addon was
-- never offered (no step), so it isn't counted as skipped.
local function BuildSkippedList()
    local wasStep = {}
    local keys = ns.Wizard and ns.Wizard.stepKeys
    if keys then
        for _, key in ipairs(keys) do if key then wasStep[key] = true end end
    end
    local list = {}
    for _, key in ipairs(recapOrder) do
        if wasStep[key] and not IsProfileImported(key) then
            list[#list + 1] = recapNames[key] or key
        end
    end
    return list
end

local function FinishPage()
    local f = WF()
    f.SubTitle:SetText("Installation Complete")
    ns.Wizard:SetTitleIcon(true)
    f.Desc1:SetText("You're all set! Click " .. ns.Green("Finish") .. " to reload your UI and apply all changes.")

    -- Full-install recap. sessionExtras is non-nil only in the plain install flow;
    -- CDM-only mode reuses this page but skips the summary.
    if ns.sessionExtras then
        if ns.Wizard.ShowStatusHeader then ns.Wizard:ShowStatusHeader("INSTALL SUMMARY") end
        local imported, skipped = BuildImportedList(), BuildSkippedList()
        local lines = {}
        if #imported > 0 then
            lines[#lines + 1] = CHECK .. " " .. ns.Green("Imported (" .. #imported .. "):") ..
                "  |cffcfcfcf" .. table.concat(imported, ", ") .. "|r"
        end
        if #skipped > 0 then
            lines[#lines + 1] = ns.Amber("Skipped (" .. #skipped .. "):") ..
                "  |cff9d9d9d" .. table.concat(skipped, ", ") .. "|r"
        end
        f.Desc2:SetText(table.concat(lines, "\n"))

        local ex = {}
        if ns.sessionExtras.chat then ex[#ex + 1] = "Chat Setup" end
        if ns.sessionExtras.optimize then ex[#ex + 1] = "Optimize" end
        if ns.sessionExtras.cleanIcons then ex[#ex + 1] = "Clean Icons" end
        f.Desc3:SetText("Extras run: " ..
            (#ex > 0 and ("|cffcfcfcf" .. table.concat(ex, ", ") .. "|r") or "|cff9d9d9dnone|r"))
    end

    ns.Wizard:SetOption(1, "Finish", function() ns.FinishInstallation() end)
    ns.Wizard:CenterOption1()
end

---------------------------------------------------------------------------------
-- Load-mode pages (activate existing profiles, no reimport)
---------------------------------------------------------------------------------

local function WelcomeLoadPage()
    local f = WF()
    f.SubTitle:SetText(ns.WizardColor("KitnUI") .. " Profile Loader")
    ns.Wizard:SetTitleIcon(true)
    f.Desc1:SetText("This loads the " .. ns.WizardColor("KitnUI") .. " profiles onto this character.\nNothing is reimported except the Cooldown Manager layouts, which every character has to be given its own copy of.")
    f.Desc2:SetText("Click " .. ns.Green("Finish") .. " at the end to reload and apply changes.")
    ns.Wizard:SetOption(1, "Load All", function()
        -- Refusals are counted, not discarded. KitnUI's own record can say a
        -- profile is installed while the addon's copy of it has since been
        -- deleted or reset; that step prints and returns false, and announcing
        -- "All profiles loaded!" over it would report the one thing that did not
        -- happen. `== false` because a step that succeeded returns nothing.
        local refused = 0
        for _, step in ipairs(addonSteps) do
            if ns.db and ns.db.profiles and ns.db.profiles[step.key] and step.key ~= "BlizzardCDM" then
                -- load mode: activate existing profile, no reimport
                if ns.SetupAddon(step.key) == false then refused = refused + 1 end
            end
        end

        -- CDM is handled apart from the loop above because it is the one step
        -- with nothing to activate: its layouts belong to the character, not the
        -- account (see ns.ImportCDMAllSpecs). Gated on the account having used
        -- CDM at all, so a player who skipped that step is not given it here.
        local cdmFailed, cdmSkipped = 0, false
        if ns.db and ns.db.profiles and ns.db.profiles.BlizzardCDM then
            local _, failed, skipped = ns.ImportCDMAllSpecs()
            cdmFailed, cdmSkipped = failed, skipped
        end

        -- Counted apart from the profiles above rather than added to them: a
        -- blocked spec is one layout of one addon, and rolling it into the
        -- profile count reports three blocked specs as three lost profiles.
        local trouble = {}
        if refused > 0 then
            trouble[#trouble + 1] = format("%d profile%s", refused, refused == 1 and "" or "s")
        end
        if cdmFailed > 0 then
            trouble[#trouble + 1] = format("%d CDM layout%s", cdmFailed, cdmFailed == 1 and "" or "s")
        end

        if #trouble > 0 then
            ShowInstallToast(table.concat(trouble, " and ") .. " could not be loaded - see chat", 1, 0.2, 0.2)
        elseif cdmSkipped then
            -- Nothing failed, but "All profiles loaded!" would still be a lie:
            -- the Cooldown Manager step never ran. Amber, and the chat line the
            -- skip printed says how to turn it on.
            ShowInstallToast("Profiles loaded, CDM layouts skipped - see chat", 1, 0.8, 0.2)
            PlayInstallSound()
        else
            SuccessToast("All profiles", "loaded!")
            PlayInstallSound()
        end
        SetVariant(WF().Next, "primary")
    end)
    SetVariant(WF().Option1, "primary")
end

local function EllesmereUILoadPage()
    local f = WF()
    f.SubTitle:SetText("EllesmereUI")
    f.Desc1:SetText("Activate the EllesmereUI profile on this character.")
    ShowLoadStatusAndVersion("EllesmereUI")
    ns.Wizard:SetOption(1, "Load Profile", function()
        -- The last load-mode caller to honour the refusal contract. The setup
        -- function rechecks EllesmereUI's API at click time, not only when the
        -- installer opened, so a host that went away in between refuses here --
        -- and saying "profile loaded!" over that would be the one wrong answer.
        if ns.SetupAddon("EllesmereUI", false) == false then
            ShowInstallToast("EllesmereUI load failed", 1, 0.2, 0.2)
            return
        end
        WF().Desc2:SetText("Status: " .. ns.Green("Loaded"))
        SuccessToast("EllesmereUI", "profile loaded!")
        PlayInstallSound()
        SetVariant(WF().Next, "primary")
    end)
end

-- The load-mode twin of NSRTPage. It exists for the field alone: the nickname is
-- account-wide in NSRT but binds to the character that sets it, so an alt is
-- exactly when someone wants to set one, and /kitn load is the only wizard an alt
-- runs. There is nothing to keep in step: both pages read and write the one live
-- value in NSRT, so they cannot disagree.
local function NSRTLoadPage()
    local f = WF()
    f.SubTitle:SetText("Northern Sky Raid Tools")
    f.Desc1:SetText("Activate the " .. ns.WizardColor("Northern Sky Raid Tools") .. " profile on this character.")
    ShowLoadStatusAndVersion("NSRT")
    ns.Wizard:SetOption(1, "Load", function()
        if ns.SetupAddon("NSRT") == false then
            ShowInstallToast("Northern Sky Raid Tools load failed", 1, 0.2, 0.2)
            return
        end
        WF().Desc2:SetText("Status: " .. ns.Green("Loaded"))
        SuccessToast("Northern Sky Raid Tools", "loaded!")
        PlayInstallSound()
    end)
    ShowNicknameInput()
end

local function SimpleLoadPage(addonKey, displayName)
    return function()
        local f = WF()
        f.SubTitle:SetText(displayName)
        f.Desc1:SetText("Activate the " .. ns.WizardColor(displayName) .. " profile on this character.")
        ShowLoadStatusAndVersion(addonKey)
        ns.Wizard:SetOption(1, "Load", function()
            -- `== false` for the same reason the install page uses it: a loader
            -- that succeeded returns nothing, so only an explicit refusal counts.
            if ns.SetupAddon(addonKey) == false then
                ShowInstallToast(displayName .. " load failed", 1, 0.2, 0.2)
                return
            end
            WF().Desc2:SetText("Status: " .. ns.Green("Loaded"))
            SuccessToast(displayName, "loaded!")
            PlayInstallSound()
        end)
    end
end

local function EditModeLoadPage()
    local f = WF()
    f.SubTitle:SetText("Blizzard Edit Mode")
    f.Desc1:SetText("Load the " .. ns.WizardColor("KitnUI") .. " Edit Mode layout on this character.")
    ShowLoadStatusAndVersion("Blizzard_EditMode")
    ns.Wizard:SetOption(1, "Load", function()
        -- `== false`, same as every other load page. This one used to discard the
        -- answer entirely and toast "loaded!" whatever happened.
        if ns.SetupAddon("Blizzard_EditMode") == false then
            ShowInstallToast("Edit Mode load failed", 1, 0.2, 0.2)
            return
        end
        WF().Desc2:SetText("Status: " .. ns.Green("Loaded"))
        SuccessToast("Edit Mode", "loaded!")
        PlayInstallSound()
    end)
end

local function FinishLoadPage()
    local f = WF()
    f.SubTitle:SetText("Profile Loading Complete")
    ns.Wizard:SetTitleIcon(true)
    f.Desc1:SetText("You're all set! Click " .. ns.Green("Finish") .. " to reload your UI and apply all changes.")
    f.Desc2:SetText("You can load profiles again with " .. ns.WizardColor("/kitn load"))
    ns.Wizard:SetOption(1, "Finish", function() ns.FinishInstallation() end)
    ns.Wizard:CenterOption1()
end

---------------------------------------------------------------------------------
-- Update-mode pages
---------------------------------------------------------------------------------

local function WelcomeUpdatePage()
    local f = WF()
    f.SubTitle:SetText(ns.WizardColor("KitnUI") .. " Profile Update")
    ns.Wizard:SetTitleIcon(true)
    f.Desc1:SetText("New or updated addon profiles are available.\n\n" ..
        ns.Red("WARNING") .. ": Each step overwrites your current settings for that addon.")
    f.Desc2:SetText("Click " .. ns.Green("Next") .. " to begin.")
end

local function FinishUpdatePage()
    local f = WF()
    f.SubTitle:SetText("Update Complete")
    ns.Wizard:SetTitleIcon(true)
    f.Desc1:SetText("All updated profiles have been reimported! Click " .. ns.Green("Finish") .. " to reload.")
    f.Desc2:SetText("You can check for updates anytime with " .. ns.WizardColor("/kitn update"))
    ns.Wizard:SetOption(1, "Finish", function() ns.FinishInstallation() end)
    ns.Wizard:CenterOption1()
end

---------------------------------------------------------------------------------
-- CDM-only mode intro
---------------------------------------------------------------------------------

local function WelcomeCDMPage()
    local f = WF()
    f.SubTitle:SetText("Blizzard Cooldown Manager")
    ns.Wizard:SetTitleIcon(true)
    f.Desc1:SetText("Import Blizzard Cooldown Manager layouts for your current class.\n\n" ..
        "Blizzard only allows importing layouts for the class you are currently logged into.")
    f.Desc2:SetText("To import another class later, run " .. ns.WizardColor("/kitn cdm") .. " on that character.")
end

---------------------------------------------------------------------------------
-- Build installer data for ns.Wizard:Queue()
---------------------------------------------------------------------------------

function ns:GetInstallerData(profileLoadMode, updateKeys, cdmMode)
    local pages, stepTitles, stepKeys = {}, {}, {}

    -- CDM-only mode: intro + CDM page + finish
    if cdmMode then
        tinsert(pages, WelcomeCDMPage); tinsert(stepTitles, "Introduction"); tinsert(stepKeys, false)
        tinsert(pages, BlizzardCDMPage); tinsert(stepTitles, "Blizzard CDM"); tinsert(stepKeys, "BlizzardCDM")
        tinsert(pages, FinishPage); tinsert(stepTitles, "Finish"); tinsert(stepKeys, false)
        return { Name = ns.WizardColor("KitnUI") .. " Blizzard CDM", Pages = pages, StepTitles = stepTitles, StepKeys = stepKeys }
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
                elseif step.key == "NSRT" then
                    tinsert(pages, NSRTLoadPage)
                elseif step.key == "Blizzard_EditMode" then
                    tinsert(pages, EditModeLoadPage)
                else
                    tinsert(pages, SimpleLoadPage(step.key, step.display))
                end
                tinsert(stepTitles, step.short or step.display); tinsert(stepKeys, step.key)
            end
        elseif not step.dormant and not (updateKeys and not updateKeys[step.key]) then
            local available = step.alwaysAvailable
            if not available and step.checkAddon then
                available = IsAddOnLoaded(step.checkAddon)
            end
            if available then
                if step.key == "EllesmereUI" then
                    tinsert(pages, EllesmereUIPage)
                elseif step.key == "NSRT" then
                    tinsert(pages, NSRTPage)
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
        Name = profileLoadMode and (ns.WizardColor("KitnUI") .. " Profile Loader")
            or updateKeys and (ns.WizardColor("KitnUI") .. " Profile Update")
            or (ns.WizardColor("KitnUI") .. " Installation"),
        Pages = pages,
        StepTitles = stepTitles,
        StepKeys = stepKeys,
    }
end

---------------------------------------------------------------------------------
-- Open the installer (called from Core boot + /kitn slash commands)
---------------------------------------------------------------------------------

function ns.OpenInstaller(profileLoadMode, updateKeys, cdmMode)
    if InCombatLockdown() then
        print(ns.title .. ": Cannot open the installer during combat.")
        return
    end
    if not ns.EUIReady() then
        local reason = ns.EUIMissingReason and ns.EUIMissingReason()
        if reason == "missing" then
            print(ns.title .. ": EllesmereUI is not installed. KitnUI imports its profiles into EllesmereUI, so install it first.")
        elseif reason == "disabled" then
            print(ns.title .. ": EllesmereUI is installed but disabled. Enable it and reload, then try again.")
        elseif reason == "loaderror" then
            print(ns.title .. ": EllesmereUI is enabled but could not load. Update it, then try again.")
        else
            print(ns.title .. ": This EllesmereUI is too old for the installer. Update EllesmereUI and try again.")
        end
        return
    end
    ns.SnapshotProfiles()
    ns.installerIsLoadMode = profileLoadMode or false
    -- Read by FinishInstallation: all three finish pages share one finish
    -- function, and two of the modes must not write another addon's settings.
    ns.installerIsCDMMode = cdmMode or false
    ns.installerIsUpdateMode = updateKeys ~= nil
    -- Read by ns.ApplyCharacterWork, which runs once per wizard rather than once
    -- per session: a second wizard is a second set of choices to apply.
    ns.characterWorkApplied = false
    -- Track Extras clicks for the Finish recap; only the plain install flow has an
    -- Extras page, so nil in load/update/cdm mode (which skip the recap).
    ns.sessionExtras = (not profileLoadMode and not updateKeys and not cdmMode) and {} or nil
    ns.Wizard:Queue(ns:GetInstallerData(profileLoadMode, updateKeys, cdmMode))
end

-- Hide the persistent per-page extras whenever the page changes: the CDM
-- "Import All" button, the appearance look row, and the NSRT nickname field.
-- All are built once and reused, so nothing hides them on the way out but this.
ns.Wizard.ResetExtras = function()
    if cdmAllButton then cdmAllButton:Hide() end
    HideLookRow()
    if ns.Wizard.HideInput then ns.Wizard:HideInput() end
end
