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

-- THE RETURN CONTRACT, which every setup function below and every caller in
-- Installer.lua obeys:
--
--   Success returns NOTHING.
--   A refusal PRINTS why, then returns an explicit `false`.
--
-- Callers must test `== false`, never `not`. A successful call usually returns
-- nil, so a plain truth test would report every success as a failure. This is
-- what stops the wizard toasting "loaded!" over a step that did nothing.
--
-- Some producers return `true` on success instead, and that is deliberate:
-- EllesmereUI in both modes, NSRT in both modes, Edit Mode install, and CDM
-- install. Four callers in Installer.lua TEST truthiness and depend on it --
-- EllesmereUIPage, EditModePage, and BlizzardCDMPage's two import paths (the
-- "Import All Specs" button and the per-spec buttons) -- so do not harmonise
-- those. Named rather than numbered on purpose: the line numbers this comment
-- used to carry went stale the first time a page was added above them. A `true`
-- is also harmless under an `== false` test, which is how NSRT's callers read it.
--
-- NSRT's load path used to return nothing on the grounds that it was account-wide
-- with nothing to activate, so doing nothing was success. v2.0.1 rebuilt the
-- import on NSAPI's profile support, so it now has a real profile to load and a
-- missing one is a genuine refusal. That carve-out is retired, not forgotten.
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
    else
        -- Load only. EllesmereUI.SetProfile returns silently when the named
        -- profile is gone, and this function returns true unconditionally below,
        -- so without this check a user whose profile was deleted is told it
        -- loaded. The import branch above has just created the profile, so it
        -- must not run this.
        local profiles = _G.EllesmereUIDB and EllesmereUIDB.profiles
        if type(profiles) ~= "table" or not profiles[ns.profileName] then
            print(ns.title .. ": The KitnUI EllesmereUI profile is not installed.")
            return false
        end

        if not EllesmereUI.SetProfile then
            print(ns.title .. ": Your EllesmereUI cannot switch profiles. Please update EllesmereUI.")
            return false
        end
    end

    if EllesmereUI.SetProfile then EllesmereUI.SetProfile(ns.profileName) end

    -- Spec assignment is deliberately NOT done here. EllesmereUI owns that
    -- question and asks it with its own "Assign Preset to Specs" dialog, which
    -- must open with nothing pre-ticked.

    if EllesmereUI.RefreshAllAddons then EllesmereUI.RefreshAllAddons() end

    -- Write the default look once, and only on an import, after SetProfile,
    -- because the look lives in the ACTIVE profile's module data. The load path
    -- skips it: EllesmereUI profiles are account-wide, so an alt running
    -- /kitn load lands on the same profile and must not overwrite a look the
    -- user changed on their main.
    --
    -- Combat-guarded, like every other caller of the RAW apply. ns.ApplyLook
    -- carries no refusal of its own; the refusal lives in the config page's
    -- PickLook wrapper, which this path does not go through. A look is not one
    -- write - it flips dark mode across two modules and asks three refreshers to
    -- repaint - so a mid-fight apply stores values the screen never finishes
    -- painting. The wizard refuses to OPEN in combat, but combat can start while
    -- it is already open. Skipped rather than deferred: the user picks a look on
    -- the EllesmereUI step or in the config tab, and both say so.
    if import and ns.ApplyLook then
        if InCombatLockdown() then
            print(ns.title .. ": Appearance was not applied because you are in combat. Pick Dark or Colored on the EllesmereUI step when you are out.")
        else
            ns.ApplyLook("dark")
        end
    end

    -- Same import gate, same reason: without it, /kitn load on an alt would flip
    -- the bar back on for a user who had deliberately switched it off. The alt
    -- inherits tbEnabled from the shared profile anyway, so gating costs nothing.
    -- SetEnabled writes tbEnabled and calls Apply() itself.
    if import and ns.TopBar and ns.TopBar.SetEnabled then ns.TopBar.SetEnabled(true) end
    return true
end

---------------------------------------------------------------------------------
-- Plater Nameplates
---------------------------------------------------------------------------------

setupFunctions["Plater"] = function(addonKey, import)
    if import then
        if not HasData("Plater") then
            print(ns.title .. ": No Plater data found.")
            return false
        end

        local profileString = ns.data.Plater
        if not Plater or not Plater.DecompressData then
            print(ns.title .. ": Plater not loaded.")
            return false
        end

        local profileData = Plater.DecompressData(profileString, "print")
        if not profileData then
            print(ns.title .. ": Failed to decompress Plater profile.")
            return false
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

    -- Two separate refusals, because they are two different problems and the user
    -- can act on each. The profile itself lives in PlaterDB.profiles; only its
    -- activation is character-keyed, so "not installed" is the honest wording.
    if not PlaterDB or not PlaterDB.profiles or not PlaterDB.profiles[ns.profileName] then
        print(ns.title .. ": The KitnUI Plater profile is not installed.")
        return false
    end

    -- The method, not just the tables above it. Reaching SetProfile through a
    -- Plater that is not there throws, and the Load All loop has no pcall, so a
    -- throw here would also skip every step after this one.
    if not Plater or not Plater.db or not Plater.db.SetProfile then
        print(ns.title .. ": Plater is not loaded.")
        return false
    end

    PlaterDB["profileKeys"] = PlaterDB["profileKeys"] or {}
    PlaterDB["profileKeys"][UnitName("player") .. " - " .. GetRealmName()] = ns.profileName
    Plater.db:SetProfile(ns.profileName)
end

---------------------------------------------------------------------------------
-- BigWigs
--
-- Two strings, two APIs, and the order is load-bearing. `BW2:` is the profile
-- (sounds, bars, colours, layout); `BWB1:` is the per-boss settings. Neither
-- call takes the other's string: RegisterProfile rejects a boss export, and
-- ImportBossOptions rejects anything that is not one.
--
-- Boss settings are written into whatever BigWigs profile is ACTIVE, so the
-- boss import must run after the profile import has finished and swapped. That
-- is why it lives inside the RegisterProfile callback, which BigWigs fires only
-- once the user has accepted and the import has completed. Firing the two side
-- by side would drop the boss settings into whichever profile the player
-- happened to be on.
---------------------------------------------------------------------------------

-- The boss half is OPTIONAL. A profile with no boss settings is a legitimate
-- thing to ship, so a missing or empty string is skipped silently.
--
-- pcall'd because ImportBossOptions signals bad input by raising, not by
-- returning false. Unguarded, one malformed shipped string would abort the
-- enclosing callback and take CompleteSetup down with it -- the install would
-- look like it failed when the profile had already landed.
local function ImportBigWigsBosses()
    local bossString = ns.data.BigWigs_Bosses
    if type(bossString) ~= "string" or strtrim(bossString) == "" then return end

    -- Reported, for the same reason the pcall below is. A BigWigs old enough to
    -- lack ImportBossOptions still registers the profile, so CompleteSetup
    -- stamps the version and the boss half is never offered again on that
    -- version. Silence here would be indistinguishable from success.
    if not (BigWigsAPI and BigWigsAPI.ImportBossOptions) then
        print(ns.title .. ": This BigWigs version cannot import boss settings. The "
            .. "main BigWigs profile installed normally.")
        return
    end

    -- The failure is REPORTED, not swallowed. CompleteSetup stamps the addon
    -- version straight after this returns, so a silent failure would look like a
    -- clean install for the rest of that version's life and leave nothing to
    -- diagnose from.
    local ok, err = pcall(BigWigsAPI.ImportBossOptions, ns.title, bossString)
    if not ok then
        print(ns.title .. ": BigWigs boss settings could not be imported. The main "
            .. "BigWigs profile installed normally. " .. tostring(err))
    end
end

setupFunctions["BigWigs"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No BigWigs data found. Add your profile data to Data.lua.")
            return false
        end

        if not (BigWigsAPI and BigWigsAPI.RegisterProfile) then
            print(ns.title .. ": BigWigs is not loaded.")
            return false
        end

        BigWigsAPI.RegisterProfile(ns.title, ns.data[addonKey], ns.profileName, function(success)
            if success then
                -- The boss prompt is a SECOND prompt the player answers, and
                -- declining it must not un-install BigWigs: the profile is the
                -- thing being installed and it has already landed. Marking the
                -- addon complete regardless is also what keeps the installer
                -- from offering BigWigs again on every later run.
                ImportBigWigsBosses()
                CompleteSetup(addonKey)
            else
                -- Printed, not returned. RegisterProfile is asynchronous: the
                -- enclosing setup function returned long before the player
                -- answered, so this outcome cannot ride the return value, and the
                -- toast helpers are local to Installer.lua and unreachable here.
                -- A printed line is the whole of what is available, and without it
                -- declining the prompt is completely silent.
                --
                -- `else`, deliberately, rather than testing the argument against
                -- false. The `== false` convention is KitnUI's own producer
                -- contract; what BigWigs passes here is its business, and a
                -- decline delivered as nil must print too.
                print(ns.title .. ": The BigWigs profile was not imported.")
            end
        end)
        return
    end

    if not BigWigs3DB or not BigWigs3DB.profiles or not BigWigs3DB.profiles[ns.profileName] then
        print(ns.title .. ": The KitnUI BigWigs profile is not installed.")
        return false
    end

    -- Optional lookup: a missing library returns nil rather than raising. Then
    -- the object and the method, because the old one-liner dereferenced three
    -- things it had never checked.
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if not (AceDB and type(AceDB.New) == "function") then
        print(ns.title .. ": AceDB-3.0 is not available, so the BigWigs profile cannot be selected.")
        return false
    end

    local db = AceDB:New(BigWigs3DB)
    if not (db and db.SetProfile) then
        print(ns.title .. ": Could not open the BigWigs profile database.")
        return false
    end

    db:SetProfile(ns.profileName)
end

---------------------------------------------------------------------------------
-- Northern Sky Raid Tools
-- NSRT export strings are LibSerialize + LibDeflate now and land in NSRT's own
-- profile system (NSRT.Profiles / ProfileKeys / CurrentProfile), so the import
-- goes through NSRT's public NSAPI:ImportProfileString - decode, activation and
-- future format changes stay NSRT's problem. The pre-profile direct-write
-- importer this replaces (AceSerializer, per-module {enabled, data} shape) is
-- in git history; it cannot decode current exports at all.
---------------------------------------------------------------------------------

setupFunctions["NSRT"] = function(addonKey, import)
    if not IsAddOnLoaded("NorthernSkyRaidTools") then
        print(ns.title .. ": NorthernSkyRaidTools is not loaded.")
        return false
    end

    -- NSRT's internal namespace is a global too (NorthernSkyRaidTools.lua
    -- assigns it next to NSAPI); the decode preflight and profile helpers
    -- live there. An NSRT old enough to lack any of them gets a plain
    -- refusal - importing into a pre-profile NSRT is not supported. The two
    -- tables are required because the helpers iterate and write through both.
    local NSI = NorthernSkyRaidTools
    if not (NSAPI and NSAPI.ImportProfileString
        and NSI and NSI.DecodeExportData and NSI.LoadProfile
        and NSI.SaveProfile and NSI.GetProfileKey
        and type(NSRT) == "table" and type(NSRT.Profiles) == "table"
        and type(NSRT.ProfileKeys) == "table") then
        print(ns.title .. ": Your Northern Sky Raid Tools version is too old for this profile. Please update it.")
        return false
    end

    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No NSRT data found.")
            return false
        end

        -- Preflight the decode before touching any saved state: the import
        -- API rejects only a non-table decode, so a decoded table with no
        -- data field would still create and activate an EMPTY profile.
        local decoded = NSI:DecodeExportData(ns.data[addonKey])
        if type(decoded) ~= "table" or type(decoded.data) ~= "table" then
            print(ns.title .. ": NSRT import failed - the export string could not be decoded.")
            return false
        end

        -- Import WITHOUT deleting anything first. On a name collision NSRT
        -- imports under a renamed profile ("KitnUI 2") and the swap below
        -- moves it over the old name only after the import fully succeeded,
        -- so the existing profile and every character's binding stay intact
        -- on every failure path. The snapshots let a failed import be swept
        -- away; the active profile's stored copy is freshened and deep-copied
        -- because the import's own save empties and refills it, and a raise
        -- mid-copy would leave it partial.
        local priorNames = {}
        for profileName in pairs(NSRT.Profiles) do priorNames[profileName] = true end
        local priorCurrent = NSRT.CurrentProfile
        local myKey = NSI:GetProfileKey()
        local priorMyBinding = myKey and NSRT.ProfileKeys[myKey] or nil
        local priorCurrentCopy
        if priorCurrent and NSRT.Profiles[priorCurrent] then
            -- SaveProfile empties and refills the stored table, so freshen it
            -- only under protection with a pre-save copy to fall back on: a
            -- raise mid-save would leave the active profile partial, and it
            -- was this function that invoked the save.
            local preSaveCopy = CopyTable(NSRT.Profiles[priorCurrent])
            if not pcall(NSI.SaveProfile, NSI) then
                NSRT.Profiles[priorCurrent] = preSaveCopy
                print(ns.title .. ": NSRT import failed - the current profile could not be saved.")
                return false
            end
            priorCurrentCopy = CopyTable(NSRT.Profiles[priorCurrent])
        end

        -- pcall because ImportProfileString mutates several structures with
        -- no internal protection - a raised error must reach the sweep.
        local ok, imported = pcall(NSAPI.ImportProfileString, NSAPI, ns.data[addonKey], ns.profileName)
        if not ok or not imported then
            -- The preflight makes this near-impossible (the import decodes
            -- the same string); sweep whatever the aborted import created
            -- and put everything else back where it was. Only bindings that
            -- point at a name swept HERE are cleared - a binding that was
            -- already dangling before the import survives, unless it happened
            -- to point at the very name the import chose.
            local sweptNames = {}
            for profileName in pairs(NSRT.Profiles) do
                if not priorNames[profileName] then
                    NSRT.Profiles[profileName] = nil
                    sweptNames[profileName] = true
                end
            end
            for charKey, profileName in pairs(NSRT.ProfileKeys) do
                if sweptNames[profileName] then NSRT.ProfileKeys[charKey] = nil end
            end
            -- Restore the prior active profile's stored copy, put the prior
            -- name back, and ALWAYS repair the live root when possible: the
            -- import's LoadProfile writes into the live root before it
            -- changes CurrentProfile, so a partial import can sit in the
            -- root while CurrentProfile still looks untouched. skipsave
            -- skips only LoadProfile's ENTRY save; its exit save still runs
            -- and can itself raise mid-copy, so the known-good stored copy
            -- goes back in afterwards no matter how the repair went.
            if priorCurrent and priorCurrentCopy then
                NSRT.Profiles[priorCurrent] = priorCurrentCopy
            end
            NSRT.CurrentProfile = priorCurrent
            if priorCurrent and priorCurrentCopy then
                pcall(NSI.LoadProfile, NSI, priorCurrent, true)
                NSRT.Profiles[priorCurrent] = priorCurrentCopy
            end
            -- LAST, because the repair's LoadProfile rebinds this character
            -- to priorCurrent; restore the true prior binding, nil included.
            if myKey then
                NSRT.ProfileKeys[myKey] = priorMyBinding
            end
            print(ns.title .. ": NSRT import failed - the profile was not created.")
            return false
        end

        -- Collision case: the import landed under a renamed profile and is
        -- already built and active. Move it over the old KitnUI name - pure
        -- renames, the only direct SavedVariables writes in this function.
        if imported ~= ns.profileName then
            NSRT.Profiles[ns.profileName] = NSRT.Profiles[imported]
            NSRT.Profiles[imported] = nil
            for charKey, profileName in pairs(NSRT.ProfileKeys) do
                if profileName == imported then NSRT.ProfileKeys[charKey] = ns.profileName end
            end
            if NSRT.CurrentProfile == imported then NSRT.CurrentProfile = ns.profileName end
            if NSRT.MainProfile == imported then NSRT.MainProfile = ns.profileName end
        end

        CompleteSetup(addonKey)
        return true
    end

    -- Load: bind this character to the account-wide KitnUI profile. pcall
    -- for the same reason as the import path - LoadProfile's saves can
    -- raise mid-copy. (A raise in its entry save can still leave this
    -- character's active stored profile partial; accepted risk, the same
    -- unprotected path NSRT's own UI takes, and only reachable when NSRT
    -- itself is already broken.)
    --
    -- This path used to be a deliberate no-op that returned nothing, because
    -- NSRT was account-wide with no per-character profile to activate. v2.0.1
    -- rebuilt the import on NSAPI's profile support, so there IS now something
    -- to do on load and a missing profile is a real refusal. The old carve-out
    -- is retired, not overlooked.
    if not NSRT.Profiles[ns.profileName] then
        print(ns.title .. ": No NSRT profile found. Run the installer first.")
        return false
    end
    if not pcall(NSI.LoadProfile, NSI, ns.profileName) then
        print(ns.title .. ": NSRT profile load failed.")
        return false
    end
    return true
end

---------------------------------------------------------------------------------
-- NSRT nickname
--
-- The nickname is NOT profile content and is not in our export string: NSRT
-- keeps it at NSRT.Settings.MyNickName, carries it across its own profile
-- writes (Profiles.lua) and strips it from exports, and current NSRT drops the
-- payload's NickNames key on import anyway. So the field and the profile import
-- cannot overwrite each other in either order, which is why the installer can
-- offer both on one page.
--
-- All NSRT API knowledge stays in this file; Installer.lua only calls these two.
---------------------------------------------------------------------------------

-- Current nickname as a STRING, or nil when NSRT cannot be read at all. The
-- empty-string fallback is what makes nil unambiguous: NSRT leaves MyNickName
-- unset until the user touches it, so returning the raw field would report a
-- perfectly healthy NSRT as unreadable and hide the field from everyone who has
-- never set a nickname - which is exactly who it is for.
function ns.GetNSRTNickname()
    if not IsAddOnLoaded("NorthernSkyRaidTools") then return nil end
    if type(NSRT) ~= "table" or type(NSRT.Settings) ~= "table" then return nil end
    -- Type-checked like every other read in this file. MyNickName is a plain
    -- saved variable that any addon can write, and a non-string reaches the
    -- wizard's SetText and raises there rather than here. A value that is not a
    -- string reads as no nickname, which is a state the user can act on.
    local nickname = NSRT.Settings.MyNickName
    if type(nickname) ~= "string" then return "" end
    return nickname
end

-- Follows the refusal contract at the top of this file: nothing on success,
-- print + explicit false on refusal.
--
-- An EMPTY value is a write, not a no-op: NSRT treats an empty string as
-- deleting the nickname, so skipping the write would make a cleared box silently
-- keep the old name.
function ns.SetNSRTNickname(value)
    if not IsAddOnLoaded("NorthernSkyRaidTools") then
        print(ns.title .. ": NorthernSkyRaidTools is not loaded.")
        return false
    end

    -- NickNames is required as well as Settings: NickNameUpdated indexes it
    -- directly, so a missing table would raise inside NSRT rather than here.
    local NSI = NorthernSkyRaidTools
    if not (NSI and NSI.NickNameUpdated and NSI.Utf8Sub
        and type(NSRT) == "table" and type(NSRT.Settings) == "table"
        and type(NSRT.NickNames) == "table") then
        print(ns.title .. ": Your Northern Sky Raid Tools version is too old for nickname setup. Please update it.")
        return false
    end

    -- Refused in combat for the same reason NSRT marks its own nickname option
    -- nocombat: the write is followed by a raid and guild broadcast.
    if InCombatLockdown() then
        print(ns.title .. ": Nickname cannot be changed in combat.")
        return false
    end

    -- Trim first so a stray space does not become part of the name, then cut to
    -- NSRT's own 12-character limit with NSRT's own utf8-aware helper.
    local ok, trimmed = pcall(NSI.Utf8Sub, NSI, strtrim(value or ""), 1, 12)
    if not ok then
        print(ns.title .. ": Nickname could not be read.")
        return false
    end

    -- Write before broadcast, matching the order NSRT's own options page uses.
    NSRT.Settings.MyNickName = trimmed
    if not pcall(NSI.NickNameUpdated, NSI, trimmed) then
        print(ns.title .. ": Nickname was saved but could not be shared with your group.")
    end
end

---------------------------------------------------------------------------------
-- Blizzard Edit Mode
---------------------------------------------------------------------------------

-- Which of KitnUI's two Edit Mode layouts belongs to the current mode. Falls
-- back to the standard one whenever the Lulu layout has not been authored yet,
-- so a half-configured Lulu Mode still lands on a working layout.
--
-- Two runs can disagree, deliberately. A full install imports the EllesmereUI
-- profile first, and that import deletes the existing profile, clearing the
-- config tab's switch states with it. So a re-install reads Lulu as off and
-- lands the standard layout, while /kitn load on the same character reads it as
-- still on. A re-install returning to defaults is the intended outcome.
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
    if not (C_EditMode and C_EditMode.GetLayouts) then
        print(ns.title .. ": Edit Mode is not available right now. Open Edit Mode once, then try again.")
        return false
    end

    local layouts = C_EditMode.GetLayouts()
    if not (layouts and layouts.layouts) then
        print(ns.title .. ": Could not read your Edit Mode layouts.")
        return false
    end

    -- The setter and the preset count as well as the getter above. The old line
    -- reached through three things it had never checked, and a throw here would
    -- also skip every later step of Load All, which has no pcall.
    if not C_EditMode.SetActiveLayout then
        print(ns.title .. ": Edit Mode cannot switch layouts right now.")
        return false
    end

    local presetCount = Enum and Enum.EditModePresetLayoutsMeta
        and Enum.EditModePresetLayoutsMeta.NumValues
    if type(presetCount) ~= "number" then
        print(ns.title .. ": Could not read Edit Mode's preset layout count.")
        return false
    end

    local _, wantedLayout = editModeTarget()
    for i, v in ipairs(layouts.layouts) do
        if v.layoutName == wantedLayout then
            C_EditMode.SetActiveLayout(presetCount + i)
            -- Success. Returns nothing, per the contract at the top of this file.
            return
        end
    end

    -- Falling off the loop is the one a user actually hits: the layout was
    -- deleted or renamed. Name it, so they know what to look for.
    print(ns.title .. ": The Edit Mode layout \"" .. tostring(wantedLayout)
        .. "\" was not found. Re-run the installer's Edit Mode step to recreate it.")
    return false
end

---------------------------------------------------------------------------------
-- KitnEssentials
---------------------------------------------------------------------------------

setupFunctions["KitnEssentials"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No KitnEssentials data found.")
            return false
        end

        if not IsAddOnLoaded("KitnEssentials") then
            print(ns.title .. ": KitnEssentials is not loaded.")
            return false
        end

        local API = _G.KitnEssentialsAPI
        if not API or not API.DecodeProfileString then
            print(ns.title .. ": KitnEssentials API not available.")
            return false
        end

        local profileData = API:DecodeProfileString(ns.data[addonKey])
        if not profileData or not next(profileData) then
            print(ns.title .. ": KitnEssentials decode failed.")
            return false
        end

        KitnEssentialsDB = KitnEssentialsDB or {}
        KitnEssentialsDB.profiles = KitnEssentialsDB.profiles or {}
        KitnEssentialsDB.profiles[ns.profileName] = profileData

        local charKey = UnitName("player") .. " - " .. GetRealmName()
        KitnEssentialsDB.profileKeys = KitnEssentialsDB.profileKeys or {}
        KitnEssentialsDB.profileKeys[charKey] = ns.profileName

        -- The method too, not just the table holding it. This is a SKIP, not a
        -- refusal: the profile data is already written above and the profileKeys
        -- entry activates it anyway, so a missing method costs nothing here, while
        -- a throw would land between the write and CompleteSetup and leave an
        -- installed profile with no ledger entry.
        local KE_addon = _G.KitnEssentials
        if KE_addon and KE_addon.db and KE_addon.db.SetProfile then
            KE_addon.db:SetProfile(ns.profileName)
        end

        CompleteSetup(addonKey)
        return
    end

    local API = _G.KitnEssentialsAPI
    if not API or not API.SetProfile then
        print(ns.title .. ": KitnEssentials is not loaded.")
        return false
    end

    -- Checking the API is not enough. KitnEssentialsAPI:SetProfile hands straight
    -- to AceDB, which CREATES a profile that does not exist, so a user whose
    -- profile was deleted would get an empty one silently rebuilt and be told it
    -- loaded. This reads the same key the install path writes above.
    if not KitnEssentialsDB or not KitnEssentialsDB.profiles
        or not KitnEssentialsDB.profiles[ns.profileName] then
        print(ns.title .. ": The KitnUI KitnEssentials profile is not installed.")
        return false
    end

    API:SetProfile(ns.profileName)
end

---------------------------------------------------------------------------------
-- BuffReminders
---------------------------------------------------------------------------------

setupFunctions["BuffReminders"] = function(addonKey, import)
    if import then
        if not HasData(addonKey) then
            print(ns.title .. ": No BuffReminders data found.")
            return false
        end

        if not IsAddOnLoaded("BuffReminders") then
            print(ns.title .. ": BuffReminders is not loaded.")
            return false
        end

        -- SetProfile as well as Import: the success branch below calls it, and
        -- checking only the method we happen to name first is how an unguarded
        -- call gets in.
        local BR = _G.BuffReminders
        if not BR or not BR.Import or not BR.SetProfile then
            print(ns.title .. ": BuffReminders API not available.")
            return false
        end

        local success, err = BR:Import(ns.data[addonKey], ns.profileName)
        if success then
            BR:SetProfile(ns.profileName)
            CompleteSetup(addonKey)
        else
            print(ns.title .. ": BuffReminders import failed - " .. (err or "unknown error"))
            -- Inside the else, because the return below is shared with the success
            -- branch. Moving it down there would refuse every working install.
            return false
        end
        return
    end

    local BR = _G.BuffReminders
    if not BR or not BR.SetProfile then
        print(ns.title .. ": BuffReminders is not loaded.")
        return false
    end

    BR:SetProfile(ns.profileName)
end

---------------------------------------------------------------------------------
-- Baganator
-- Writes a named KitnUI profile into BAGANATOR_CONFIG.Profiles and sets it as the
-- active profile for this character. Only runs on an explicit install or load
-- action, never on PLAYER_LOGIN, so changes the user makes inside the profile
-- survive a reload.
--
-- Category groups are decoded from a JSON export string (Baganator's
-- Customise > Categories > Export) and merged into the profile. Array fields are
-- converted to the hashmap form Baganator stores internally.
---------------------------------------------------------------------------------

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
        -- Sentinels that stop Baganator from reimporting its stock defaults over
        -- our data on first boot (CategoryViews/Initialize.lua:144). 999 stays
        -- above any DefaultImportVersion Baganator will realistically ship.
        category_default_import = 999,
        -- Our data is written in the post-migration format; skip the
        -- MigrateFormat loop (CategoryViews/Initialize.lua:3-77).
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

    -- Every custom category needs a modifications entry with a priority, matching
    -- Baganator's own import behaviour.
    for source in pairs(out.custom_categories) do
        out.category_modifications[source] = out.category_modifications[source] or { priority = 0 }
        if out.category_modifications[source].priority == nil then
            out.category_modifications[source].priority = 0
        end
    end

    -- C_EncodingUtil.DeserializeJSON converts numeric-string object keys (e.g.
    -- "1") into Lua numbers. Baganator looks up sections via the string form
    -- (derived from display_order entries like "_1"), so coerce keys back to
    -- strings here.
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
            return false
        end

        local src = ns.data[addonKey]

        -- Decode BEFORE touching BAGANATOR_CONFIG, and bail on failure the same
        -- way the NSRT decode above does. Both view modes ship as "category", so
        -- a profile written without its category groups is a broken bag display
        -- -- and writing one would replace a good existing profile, activate it,
        -- and stamp the install as done.
        -- A missing or blank categoriesJSON is refused too, not skipped. HasData
        -- only proves the payload table is non-empty, so an edit that emptied
        -- this one field would otherwise sail past the decode and write exactly
        -- the profile this gate exists to prevent.
        if type(src.categoriesJSON) ~= "string" or strtrim(src.categoriesJSON) == "" then
            print(ns.title .. ": Baganator category data is missing from this build.")
            return false
        end

        local decoded, err = DecodeBaganatorCategories(src.categoriesJSON)
        if not decoded then
            print(ns.title .. ": Baganator categories decode failed - " .. (err or "unknown error"))
            return false
        end

        BAGANATOR_CONFIG = BAGANATOR_CONFIG or {}
        BAGANATOR_CONFIG.Profiles = BAGANATOR_CONFIG.Profiles or {}

        local profile = {}

        -- Copy the non-JSON fields (view modes, seen_welcome) into the profile.
        for k, v in pairs(src) do
            if k ~= "categoriesJSON" then
                profile[k] = type(v) == "table" and CopyTable(v) or v
            end
        end

        for k, v in pairs(decoded) do
            profile[k] = v
        end

        BAGANATOR_CONFIG.Profiles[ns.profileName] = profile

        -- Activate the KitnUI profile for this character (per-character SavedVar).
        BAGANATOR_CURRENT_PROFILE = ns.profileName

        CompleteSetup(addonKey)
        return
    end

    -- Load: activate the existing KitnUI profile for this character. Says so when
    -- there is nothing to activate, matching the import branch's own failure
    -- paths -- a silent no-op reads as a load that worked.
    if BAGANATOR_CONFIG and BAGANATOR_CONFIG.Profiles and BAGANATOR_CONFIG.Profiles[ns.profileName] then
        BAGANATOR_CURRENT_PROFILE = ns.profileName
        return
    end
    print(ns.title .. ": No Baganator profile to load. Install it first.")
    return false
end

---------------------------------------------------------------------------------
-- Blizzard Cooldown Manager (per-spec)
---------------------------------------------------------------------------------

-- Blizzard's Cooldown Manager redraws itself the instant a layout changes, and
-- that redraw cannot run inside an addon's call stack. It indexes a table the
-- client forbids to tainted code
-- (Blizzard_CooldownViewer/CooldownViewer.lua:946) and compares protected spell
-- data (:344), and whichever it reaches first throws. The throw landed
-- mid-RemoveLayout, which by then had cleared the user's active layout and had
-- not yet removed anything, so the import died having done only damage.
--
-- LockNotifications is Blizzard's own answer to a batch of edits; its own code
-- brackets batches the same way (CooldownViewerSettingsDataProvider.lua:186 and
-- CooldownViewerSettingsDataStoreSerialization.lua:353). Held, every layout edit
-- runs to completion and the manager merely records that one redraw is owed.
--
-- That owed redraw is then DROPPED rather than fired, because firing it would
-- throw exactly as before: releasing the lock is still our call stack. Nothing
-- is lost. The wizard reloads the UI at Finish and the viewer rebuilds from the
-- saved layouts, so a stale viewer until then costs nothing.
--
-- needsNotificationAfterUnlock is Blizzard's own flag
-- (CooldownViewerSettingsLayoutManager.lua:825). Clearing it is what makes the
-- release quiet, and it is preferred to the alternatives because of HOW it
-- fails: if a later build renames the flag the redraw fires and errors as it
-- does today, but the edits have already completed by then, so the import still
-- succeeds.
local function SilenceCDM(lm)
    if type(lm.LockNotifications) ~= "function"
        or type(lm.UnlockNotifications) ~= "function" then
        return false
    end
    lm:LockNotifications()
    return true
end

-- Every SilenceCDM needs exactly one of these, and NO `return` may sit between
-- the pair: a lock that is never released leaves the viewer frozen until the
-- next reload. That is why the brackets below wrap single runs of edits instead
-- of the import as a whole, which has four exits inside it.
local function RestoreCDM(lm, silenced)
    if not silenced then return end
    lm.needsNotificationAfterUnlock = false
    lm:UnlockNotifications()
end

setupFunctions["BlizzardCDM"] = function(_addonKey, import, specIndex)
    if import then
        local _, _, classId = UnitClass("player")
        local classData = ns.data.BlizzardCDM and ns.data.BlizzardCDM[classId]
        local specString = classData and classData[specIndex]

        if not specString or strtrim(specString) == "" then
            print(ns.title .. ": No CDM data for this spec. Add your layout string to Data.lua.")
            return false
        end

        -- Both resolved BEFORE the layout manager is touched. Importing first
        -- and finding afterwards that there is nothing to stamp would leave a
        -- replaced layout with no record of what it holds.
        local cdmKey = ns.GetCDMKey(classId, specIndex)
        local cdmFingerprint = ns.GetCDMShippedFingerprint(classId, specIndex)
        if not cdmKey or not cdmFingerprint then
            print(ns.title .. ": Could not identify this spec's CDM layout. Nothing was changed.")
            return false
        end

        if not CooldownViewerSettings or not CooldownViewerSettings.GetLayoutManager then
            print(ns.title .. ": Blizzard Cooldown Manager is not available. Enable it in Settings > Gameplay > Combat.")
            return false
        end

        local lm = CooldownViewerSettings:GetLayoutManager()
        if not lm then
            print(ns.title .. ": Could not get CDM Layout Manager.")
            return false
        end

        -- Every layout-manager method this path calls, checked BEFORE the first
        -- mutation. RemoveLayout below deletes the user's existing layout, so a
        -- throw after that point costs them the layout and reports nothing, and
        -- the Import All loop has no pcall either, so every later spec would be
        -- skipped too. AreLayoutsFullyMaxed and SetActiveLayoutByID stay checked
        -- at their own call sites, because both are genuinely optional there.
        for _, method in ipairs({ "EnumerateLayouts", "RemoveLayout",
                                  "CreateLayoutsFromSerializedData", "SaveLayouts" }) do
            if type(lm[method]) ~= "function" then
                print(ns.title .. ": Your Cooldown Manager is missing " .. method
                    .. ", so this layout cannot be imported. Nothing was changed.")
                return false
            end
        end

        -- Guarded the same way Installer.lua:407 guards the same global. It is
        -- only used for the layout's display name, so a missing one degrades to
        -- the numbered fallback rather than refusing; the throw it would
        -- otherwise raise sits in the pcall-less Import All loop.
        local specName
        if GetSpecializationInfoForClassID then
            specName = select(2, GetSpecializationInfoForClassID(classId, specIndex))
        end
        local layoutName = "KUI - " .. (specName or ("Spec" .. specIndex))
        local removedExisting = false
        local _, layouts = lm:EnumerateLayouts()
        if layouts then
            for layoutID, layout in pairs(layouts) do
                if layout and layout.layoutName == layoutName then
                    local quietRemove = SilenceCDM(lm)
                    lm:RemoveLayout(layoutID)
                    RestoreCDM(lm, quietRemove)
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

        local quietCreate = SilenceCDM(lm)
        local layoutIDs = lm:CreateLayoutsFromSerializedData(specString)
        RestoreCDM(lm, quietCreate)

        if layoutIDs and layoutIDs[1] then
            local importedID = layoutIDs[1]

            local _, postLayouts = lm:EnumerateLayouts()
            if not postLayouts or not postLayouts[importedID] then
                print(ns.title .. ": CDM layout limit reached. Delete a layout and try again.")
                return false
            end

            postLayouts[importedID].layoutName = layoutName

            local quietSave = SilenceCDM(lm)
            lm:SaveLayouts()
            RestoreCDM(lm, quietSave)

            -- Degrades rather than refuses. The layout is already created and
            -- named by this point, so a missing namespace costs only the
            -- activation, and the user can pick the layout themselves.
            local currentSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
                and C_SpecializationInfo.GetSpecialization()
            if currentSpec == specIndex then
                local quietActivate = SilenceCDM(lm)
                if lm.SetActiveLayoutByID then
                    lm:SetActiveLayoutByID(importedID)
                end
                lm:SaveLayouts()
                RestoreCDM(lm, quietActivate)

                C_Timer.After(0, function()
                    if not InCombatLockdown() and lm.SetActiveLayoutByID then
                        local quietRetry = SilenceCDM(lm)
                        lm:SetActiveLayoutByID(importedID)
                        lm:SaveLayouts()
                        RestoreCDM(lm, quietRetry)
                    end
                end)
            end

            -- CDM writes its own bookkeeping instead of calling CompleteSetup,
            -- because its profile entry is a per-spec table rather than a flag.
            -- The value is the FINGERPRINT of the string just imported, under a
            -- class-and-spec key, so the entry says which class it belongs to
            -- AND whether the data has moved on since. A string is still truthy,
            -- so anything that only asks "is this set?" keeps working. Integer
            -- keys from older builds are LEFT ALONE: they are the only evidence
            -- the account ever imported CDM, which GetCDMSpecState reads as
            -- "untracked".
            ns.db.profiles = ns.db.profiles or {}
            ns.db.profiles["BlizzardCDM"] = ns.db.profiles["BlizzardCDM"] or {}
            ns.db.profiles["BlizzardCDM"][cdmKey] = cdmFingerprint
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

-- A FRESH table every call. One member is conditional (see the nameplates
-- branch below), and ApplyEUIModuleSet appends to what this returns while the
-- same return also becomes ImportProfileSilent's disableAddons -- a shared
-- static set would let that append leak into the import's strip list.
--
-- Used in two places, and both are needed:
--   * as ImportProfileSilent's disableAddons, where EllesmereUI ALSO strips
--     those modules out of the payload and filters cross-module layout anchors
--   * directly at Finish, because disableAddons only fires on an import. An alt
--     running /kitn load never imports, and addon enable state is per character,
--     so the alt would otherwise keep the modules on.
--
-- EllesmereUICooldownManager is deliberately NOT here. It skins Blizzard's own
-- Cooldown Viewer rather than competing with it, and the Blizzard CDM step
-- supplies the spell layout for that same viewer, so the two stack. Listing it
-- strips its settings AND its spell layouts out of the import.
-- Off on every install, with no condition attached: KitnUI either replaces
-- these with a dedicated addon or leaves the job to Blizzard. Disabling Blizz
-- UI Enhanced also takes its Dragon Riding skin, which lives in the same folder.
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

-- Every EllesmereUI module folder, read from EllesmereUI's own map so a module
-- added in a later release is covered without editing a list here. hostAddon is
-- the folder that actually ships a module whose own entry is a shim.
--
-- Returns nil rather than a partial list when the map is unreadable: a guess at
-- the suite's composition would enable or disable the wrong folders, and the
-- caller treats nil as "do the half you can prove".
local function euiAllModules()
    local map = _G.EllesmereUI and EllesmereUI._ADDON_DB_MAP
    if type(map) ~= "table" or #map == 0 then return nil end

    local folders, seen = {}, {}
    for _, entry in ipairs(map) do
        local folder = type(entry) == "table" and (entry.hostAddon or entry.folder)
        if type(folder) == "string" and not seen[folder] then
            seen[folder] = true
            folders[#folders + 1] = folder
        end
    end
    if #folders == 0 then return nil end

    return folders
end

-- Every enable and disable below names the current character. Leaving the
-- argument off does NOT mean "this character": it means the whole account.
-- Blizzard's own addon list maps its "All" selection to nil and passes a player
-- GUID for every per-character operation. Without the argument, an alt running
-- /kitn load rewrites every other character's module choices.
local function AddonCharacter()
    if not UnitGUID then return nil end
    local guid = UnitGUID("player")
    if type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

-- Idempotent and safe: no-ops when C_AddOns is unavailable and skips any module
-- that isn't installed. Takes effect on the ReloadUI at the end of the flow.
function ns.ApplyEUIModuleSet()
    if not (C_AddOns and C_AddOns.DisableAddOn) then return end

    -- Nothing at all rather than something account-wide. Doing the pass without
    -- a character would reach every alt, which is the failure this argument was
    -- added to remove.
    local character = AddonCharacter()
    if not character then return end

    local set = ns.GetEUIModuleSet()

    local off = {}

    -- Lulu Mode turns EllesmereUI's action bars off. It belongs here and NOT in
    -- GetEUIModuleSet, which doubles as ImportProfileSilent's disableAddons and
    -- would strip the bar configuration this addon exists to install. Enable
    -- state is all Lulu needs, and this pass runs last, so it wins over the
    -- import's own enable sweep.
    --
    -- Handed to Lulu rather than added to the list below, because the loop takes
    -- no record and turning Lulu off later would have nothing to put back.
    -- Still marked in `off` so the enable sweep at the end leaves it alone.
    if ns.LuluEnabled and ns.LuluEnabled() then
        off["EllesmereUIActionBars"] = true
        if ns.LuluApplyActionBars then ns.LuluApplyActionBars(true) end
    end
    for _, folder in ipairs(set) do
        off[folder] = true
        if euiModuleInstalled(folder) then
            C_AddOns.DisableAddOn(folder, character)
        end
    end

    -- The other half of the composition. An install gets this free from
    -- EllesmereUI's own sweep, which enables everything disableAddons does not
    -- name. But /kitn load never imports, so without this an alt keeps whatever
    -- modules that character happened to have switched off and quietly differs
    -- from a freshly installed one forever. Running it here covers both paths,
    -- plus one the import misses either way: an install where the user unchecked
    -- the EllesmereUI step skips the import and its sweep with it.
    --
    -- This does override a module the user turned off on purpose. That is the
    -- point of "load": the character ends up matching the pack. THIS character,
    -- and no other -- the whole reason the argument is here.
    --
    -- One sweep stays outside KitnUI's reach: EllesmereUI's own import enables
    -- every module with no character of its own, so an INSTALL touches the
    -- account before this pass runs last. An alt with Lulu applied whose action
    -- bars that sweep switches back on lands in the "apply" mismatch at its next
    -- login, and Lulu's own prompt puts it right.
    if not C_AddOns.EnableAddOn then return end
    local all = euiAllModules()
    if not all then return end
    for _, folder in ipairs(all) do
        if not off[folder] and euiModuleInstalled(folder) then
            C_AddOns.EnableAddOn(folder, character)
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

    -- Chat Setup, same reasoning as the module set above: the opt-in is account
    -- wide but WoW's chat layout is per character, so an alt that only runs
    -- /kitn load has none of it and needs its own pass.
    --
    -- LOAD MODE ONLY, and that restriction is load-bearing. RunChatSetup resets
    -- the character's chat windows before rebuilding them, and this function
    -- also ends the install and update runs -- so without the gate every
    -- /kitn update would silently wipe the chat layout of anyone who had ever
    -- pressed the button.
    if ns.installerIsLoadMode and ns.db.extras and ns.db.extras.chat
        and ns.RunChatSetup then
        ns.RunChatSetup()
    end

    ReloadUI()
end
