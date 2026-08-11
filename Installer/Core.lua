-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Core.lua                                                    ║
-- ║  Purpose: Addon bootstrap: SavedVariables + defaults, media/ ║
-- ║           LSM registration, colour helpers, /kitn slash      ║
-- ║           commands, and the login boot flow.                 ║
-- ╚══════════════════════════════════════════════════════════════╝

local addonName, ns = ... ---@type string, KitnUINS

-- The forward half of the bridge to KitnUI_EUI, which is a separate addon and so
-- gets a separate namespace table. It reads eight symbols from here (db, data,
-- profileName, title, Red, QueueMessage, EditModeSlotFree, KITN_PINK) through an
-- __index fallthrough, so this must be the SAME table, not a copy: ns.db is not
-- filled until PLAYER_LOGIN and a copy would freeze it empty.
_G.KitnUI_Shared = ns

local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

---------------------------------------------------------------------------------
-- Media paths + LibSharedMedia registration
---------------------------------------------------------------------------------

local FONT_PATH = "Interface\\AddOns\\KitnUI\\Media\\Fonts\\Expressway.TTF"
local BAR_TEXTURE_PATH = "Interface\\AddOns\\KitnUI\\Media\\Statusbars\\KitnUI_Bar"
ns.FONT = FONT_PATH

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM then
    LSM:Register("font", "Expressway", FONT_PATH)
    LSM:Register("statusbar", "KitnUI", BAR_TEXTURE_PATH)
end

---------------------------------------------------------------------------------
-- Shared namespace references
---------------------------------------------------------------------------------

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

-- Tell EllesmereUI that KitnUI owns the first-run experience, so EUI's own
-- first-install picker stays silent while our wizard runs. This is runtime
-- state on the EllesmereUI table, not a SavedVariable, so it has to be set
-- every session. File scope is early enough on both counts: RequiredDeps
-- guarantees EllesmereUI is loaded before this file runs, and EUI does not
-- check the flag until PLAYER_LOGIN plus half a second. Guarded, so an older
-- EllesmereUI simply keeps its own picker.
if _G.EllesmereUI and EllesmereUI.RegisterExternalInstaller then
    EllesmereUI.RegisterExternalInstaller("KitnUI")
end

---------------------------------------------------------------------------------
-- Per-addon version tracking (X-headers in TOC)
---------------------------------------------------------------------------------

local addonVersionHeaders = {
    EllesmereUI       = "X-EllesmereUI-Version",
    Plater            = "X-Plater-Version",
    BigWigs           = "X-BigWigs-Version",
    NSRT              = "X-NSRT-Version",
    Blizzard_EditMode = "X-EditMode-Version",
    KitnEssentials    = "X-KitnEssentials-Version",
    BuffReminders     = "X-BuffReminders-Version",
    Baganator         = "X-Baganator-Version",
}
-- BLIZZARD CDM IS DELIBERATELY ABSENT, and its TOC header is gone with it. A
-- single version string cannot describe per-class, per-spec data: it cannot say
-- WHICH spec changed, so one edited layout prompts a three-spec player to
-- reimport all three, and it is maintained by hand beside the data, so it lies
-- in both directions when the two drift. CDM answers "is this stale?" by
-- fingerprinting the string it ships instead -- see the block below.

function ns.GetAddonDataVersion(addonKey)
    local header = addonVersionHeaders[addonKey]
    if not header then return nil end
    return C_AddOns.GetAddOnMetadata(addonName, header)
end

---------------------------------------------------------------------------------
-- Blizzard CDM: content fingerprints instead of a version header
---------------------------------------------------------------------------------

-- A short token derived from the layout string KitnUI ships for one spec. It is
-- only ever compared against another token this function produced, so it never
-- has to be cryptographic and never leaves SavedVariables.
--
-- Multiply-and-modulo rather than the FNV-1a the reference addon uses: FNV needs
-- bit.bxor, and bitops are forbidden family-wide (../AGENTS.md). Every step here
-- is plain arithmetic. The largest intermediate is (2^32-1)*33+255, about 1.42e11
-- -- far below 2^53, so a double holds it exactly and the result cannot drift.
--
-- THE EMISSION SPLITS h RATHER THAN FORMATTING IT WHOLE. Printing a whole 32-bit
-- value with %x or %d depends on how the host formatter converts a double
-- outside the signed 32-bit range, and nothing available here settles what WoW's
-- Lua does there. Two halves below 2^16 are inside the well-defined range on
-- every runtime, and the split is lossless (hi * 65536 + lo == h), so this costs
-- no hash bits. Length is a third field: two strings that collide on the hash
-- almost certainly differ in length.
local function Fingerprint(str)
    if type(str) ~= "string" or str == "" then return nil end

    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 4294967296
    end
    return format("%d-%d-%d", math.floor(h / 65536), h % 65536, #str)
end

-- The storage key. A STRING, so it can never be confused with the plain integer
-- spec indices every earlier build wrote -- which is what makes the migration in
-- GetCDMSpecState safe without any argument about numeric ranges.
--
-- Both halves are validated because ns.SetupAddon forwards its variadic argument
-- straight through, so a caller can reach here with a nil or non-numeric spec.
function ns.GetCDMKey(classId, specIndex)
    if type(classId) ~= "number" or type(specIndex) ~= "number" then return nil end
    if classId < 1 or specIndex < 1 then return nil end
    if math.floor(classId) ~= classId or math.floor(specIndex) ~= specIndex then return nil end
    return format("%d:%d", classId, specIndex)
end

-- Memoized because ns.IsAddonImported feeds every sidebar repaint, and without
-- this the class's whole payload would be re-hashed on each one. The cache
-- cannot go stale: ns.data.BlizzardCDM is a table literal built at load time and
-- nothing writes to it, so a shipped string is constant for the session.
local shippedFingerprints = {}

function ns.GetCDMShippedFingerprint(classId, specIndex)
    local key = ns.GetCDMKey(classId, specIndex)
    if not key then return nil end
    if shippedFingerprints[key] ~= nil then
        local cached = shippedFingerprints[key]
        if cached == false then return nil end
        return cached
    end

    local classData = ns.data.BlizzardCDM and ns.data.BlizzardCDM[classId]
    local fp = Fingerprint(classData and classData[specIndex])
    -- false, not nil: a nil would look like "not cached yet" and re-hash forever.
    shippedFingerprints[key] = fp or false
    return fp
end

-- Does the CDM table still hold keys from a build that stored plain spec
-- indices? Those prove the account imported SOMETHING and say nothing about
-- which class, which is exactly the "untracked" state below.
local function HasLegacyCDMKeys()
    local store = ns.db and ns.db.profiles and ns.db.profiles.BlizzardCDM
    if type(store) ~= "table" then return false end
    for k in pairs(store) do
        if type(k) == "number" then return true end
    end
    return false
end

-- One of five states, and never a guess:
--   nodata    nothing shipped, or a shipped string that will not fingerprint
--   current   a stored fingerprint equal to what we ship now
--   stale     a stored fingerprint different from what we ship now
--   untracked no entry for this spec, but legacy keys exist, so what this
--             character holds is genuinely unknown
--   missing   no entry and no legacy keys
function ns.GetCDMSpecState(classId, specIndex)
    local shipped = ns.GetCDMShippedFingerprint(classId, specIndex)
    if not shipped then return "nodata" end

    local key = ns.GetCDMKey(classId, specIndex)
    local store = ns.db and ns.db.profiles and ns.db.profiles.BlizzardCDM
    -- An `if`, not `and`/`or`: the value on the right can be nil, which is the
    -- one shape the project rule forbids collapsing.
    local held
    if type(store) == "table" and key then held = store[key] end

    if type(held) == "string" then
        return held == shipped and "current" or "stale"
    end
    return HasLegacyCDMKeys() and "untracked" or "missing"
end

-- THE SINGLE OWNER of every specialization API call on the status surfaces.
-- The CDM page used to resolve the class and the spec count itself, which meant
-- two places guarding the same APIs two different ways. Returns the class id (or
-- nil) and the rows; the import path keeps its own calls, which are not status.
function ns.GetCDMSpecRows()
    local rows = {}
    local _, _, classId = UnitClass("player")
    if type(classId) ~= "number" then return nil, rows end
    if not (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID) then
        return classId, rows
    end

    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId)
    if type(numSpecs) ~= "number" then return classId, rows end

    for i = 1, numSpecs do
        local specName
        if GetSpecializationInfoForClassID then
            specName = select(2, GetSpecializationInfoForClassID(classId, i))
        end
        rows[#rows + 1] = {
            specIndex = i,
            specName = specName or ("Spec " .. i),
            state = ns.GetCDMSpecState(classId, i),
        }
    end
    return classId, rows
end

function ns.HasCDMForCurrentClass()
    local _, rows = ns.GetCDMSpecRows()
    for _, row in ipairs(rows) do
        if row.state == "current" or row.state == "stale" then return true end
    end
    return false
end

-- Specs worth offering: a "nodata" spec is skipped, because a spec we cannot
-- ship cannot be fixed by importing, and offering it would build a prompt
-- nothing can clear.
function ns.GetOutdatedCDMSpecs()
    local out = {}
    local _, rows = ns.GetCDMSpecRows()
    for _, row in ipairs(rows) do
        if row.state == "stale" or row.state == "untracked" or row.state == "missing" then
            out[#out + 1] = row
        end
    end
    return out
end

-- One summary, two callers (/kitn version and the CDM page), so the two cannot
-- describe the same database differently. "update available" means STALE and
-- nothing else -- a spec that was never imported has no update to take.
function ns.SummarizeCDMRows(rows)
    local counts = { current = 0, stale = 0, untracked = 0, missing = 0, nodata = 0 }
    for _, row in ipairs(rows or {}) do
        counts[row.state] = (counts[row.state] or 0) + 1
    end
    local parts = {}
    if counts.current > 0 then parts[#parts + 1] = counts.current .. " up to date" end
    if counts.stale > 0 then parts[#parts + 1] = counts.stale .. " update available" end
    if counts.untracked > 0 then parts[#parts + 1] = counts.untracked .. " untracked" end
    if counts.missing > 0 then parts[#parts + 1] = counts.missing .. " not imported" end
    if #parts == 0 then return "no layouts available for this class" end
    return table.concat(parts, ", ")
end

-- Should the wizard ask before importing? Pure over its arguments so the same
-- implementation serves both call sites AND the test harness -- a copy of this
-- decision living in a test could pass while the shipped one drifted.
--
-- `snapshot` is the FROZEN pre-session copy of profiles.BlizzardCDM. A nil
-- specIndex asks "any spec of this class", which is what Import All needs.
--
-- Legacy keys warn even though they name no class. That over-warns across
-- classes on purpose: the import deletes a matching layout before recreating it,
-- a legacy user may have edited theirs, and over-warning costs a click while
-- under-warning destroys work.
function ns.CDMNeedsOverwriteConfirm(snapshot, classId, specIndex)
    if type(snapshot) ~= "table" then return false end

    for k in pairs(snapshot) do
        if type(k) == "number" then return true end
    end

    if specIndex then
        local key = ns.GetCDMKey(classId, specIndex)
        return (key and snapshot[key]) and true or false
    end

    if type(classId) ~= "number" then return false end
    local prefix = classId .. ":"
    for k in pairs(snapshot) do
        if type(k) == "string" and k:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- Which addons have updated data since last install, or new data never imported.
function ns.GetOutdatedAddons()
    local outdated = {}
    if not ns.db then return outdated end

    -- CDM rides the same list so every consumer downstream is unchanged -- the
    -- login notification, the update popup, /kitn update's keys and the update
    -- wizard's page selection all read this one function. Only the RULE differs:
    -- fingerprints, not a header. isNew is true only when nothing of this class
    -- is tracked and no legacy key survives, so a player coming back from an
    -- older build is offered an update rather than announced as new.
    local cdmSpecs = ns.GetOutdatedCDMSpecs()
    if #cdmSpecs > 0 then
        local everImported = ns.HasCDMForCurrentClass() or HasLegacyCDMKeys()
        outdated[#outdated + 1] = {
            key = "BlizzardCDM",
            isNew = not everImported,
            specs = cdmSpecs,
        }
    end

    for addonKey, header in pairs(addonVersionHeaders) do
        local installed = ns.db.addonVersions and ns.db.addonVersions[addonKey]
        local current = C_AddOns.GetAddOnMetadata(addonName, header)
        local hasProfile = ns.db.profiles and ns.db.profiles[addonKey]

        -- An addon whose payload is empty can never be imported, so reporting it
        -- outdated creates a prompt nothing can clear: the wizard skips a dormant
        -- step when building its pages, the version is never re-stamped, and the
        -- popup returns on every login. Checked on BOTH branches -- it used to
        -- guard only the never-imported one, which left a dormant addon with an
        -- older stored version stuck in exactly that loop.
        local payload = ns.data[addonKey]
        local emptyPayload = payload == nil
            or (type(payload) == "string" and strtrim(payload) == "")
            or (type(payload) == "table" and not next(payload))

        if emptyPayload or not current then -- luacheck: ignore 542
            -- nothing to offer; fall through to the next addon
        elseif installed and installed ~= current then
            outdated[#outdated + 1] = {
                key = addonKey,
                oldVersion = installed,
                newVersion = current,
                isNew = false,
            }
        elseif not hasProfile or not installed then
            -- Covers two cases with one branch: never imported, and imported by
            -- a build that did not record a version (the Blizzard CDM path did
            -- not stamp one before 2026.08.11). Both are reported as new because
            -- there is no old version to name, and the login notification's
            -- non-new branch concatenates oldVersion with no nil guard.
            -- Reporting it once is enough: the reimport records a version and
            -- this stops firing.
            outdated[#outdated + 1] = {
                key = addonKey,
                newVersion = current,
                isNew = true,
            }
        end
    end
    return outdated
end

-- Blizzard's cap is five layouts PER TYPE, not five in total:
-- EditModeMaxLayoutsPerType is 5, and AreLayoutsOfTypeMaxed compares it against
-- numLayouts[layoutType], so a character at five Account layouts and five
-- Character layouts holds ten. Counting the whole list would refuse a write that
-- would have succeeded and tell the user to delete a layout they do not need to.
--
-- Every layout KitnUI writes is Account type, because EllesmereUI's importer
-- forces imported.layoutType to Enum.EditModeLayoutType.Account. So only Account
-- layouts are counted here.
--
-- The name match is type-scoped for the same reason. ApplyPresetEditMode de-dupes
-- by NAME across both types, so a CHARACTER layout sharing our name would free a
-- Character slot, not the Account slot we are about to fill. Treating it as a
-- replacement would let a sixth Account layout through.
--
-- A layout under KitnUI's OTHER name does not help either: importing the Lulu
-- layout while only the standard one exists still needs a free Account slot.
--
-- Returns true when the write is safe. An unreadable layout list, or an Enum this
-- client does not carry, returns true so a missing API costs the guard and not
-- the feature: ApplyPresetEditMode reports its own failure in that case.
function ns.EditModeSlotFree(layoutName)
    local layouts = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
    if not (layouts and layouts.layouts) then return true end

    local accountType = Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account
    if accountType == nil then return true end

    local used = 0
    for _, layout in ipairs(layouts.layouts) do
        if layout.layoutType == accountType then
            if layout.layoutName == layoutName then return true end
            used = used + 1
        end
    end

    return used < 5
end

---------------------------------------------------------------------------------
-- Saved variable defaults
---------------------------------------------------------------------------------

local defaults = {
    profiles = {},          -- [addonKey] = true when imported
    addonVersions = {},     -- [addonKey] = X-header version at time of import
    extras = {},            -- [extraKey] = true once the user opted in; account-wide so /kitn load repeats it on an alt
    installedVersion = nil, -- addon version at last install
    perChar = {},           -- [charName-realm] = { loaded = true/false }
    pendingMessages = {},   -- lines to print after the next reload (see ns.QueueMessage)
    euiSettings = {},       -- [profileName] = { accent = {...}, lulu = true } config tab switches
    euiSnap = {},           -- [section][profileName][key] = { prev = <old value> }
    euiSnapGlobal = {},     -- [key] = { prev = <old value> } for anything outside a profile: EllesmereUIDB root keys, plus Lulu's two per-character debts (keys prefixed "lulu")
    devMode = false,        -- toggle dev-mode update popup (/kitn dev)
}

local function GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

---------------------------------------------------------------------------------
-- Color helpers (also used by Setup.lua / Installer.lua via ns)
---------------------------------------------------------------------------------

-- Say something to the user across a reload.
--
-- Lulu Mode and the installer both call ReloadUI on the line after they report
-- what they could not do, so those messages were written into a chat frame the
-- client tore down microseconds later. The user flipped a switch, saw the screen
-- reload, and was told nothing. Queue instead of print anywhere a reload follows,
-- and the boot handler prints it on the far side.
function ns.QueueMessage(text)
    if type(text) ~= "string" or not ns.db then return end
    ns.db.pendingMessages = ns.db.pendingMessages or {}
    ns.db.pendingMessages[#ns.db.pendingMessages + 1] = text
end

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

---------------------------------------------------------------------------------
-- Utility + per-character load state
---------------------------------------------------------------------------------

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

---------------------------------------------------------------------------------
-- Confirmation popup for /kitn install when already installed
---------------------------------------------------------------------------------

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

---------------------------------------------------------------------------------
-- Slash commands (ns.OpenInstaller is assigned by Installer.lua)
---------------------------------------------------------------------------------

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
    -- Put back everything the config tab is holding down before the snapshots
    -- go, otherwise they and the switch states die out of step. It refuses in
    -- combat, and a refusal must abort the whole reset rather than proceeding to
    -- wipe the saved variables the restore still needs.
    -- Absence aborts for the same reason a refusal does. KitnUI_EUI is a separate
    -- addon and can be disabled on its own, and with it goes the only code that
    -- can put back what its switches are holding down. Wiping the snapshots then
    -- would strand Lulu's action bars and Edit Mode layout with nothing left to
    -- reverse them. Refusing out loud beats a reset that looks like it worked.
    if not ns.EUIResetAll then
        print(ns.title .. ": cannot reset while the KitnUI_EUI addon is disabled, because the settings it is holding down could not be put back. Enable it, reload, then try again.")
        return
    end
    if ns.EUIResetAll() == false then return end

    -- That teardown queues a line for anything it could NOT put back, and the
    -- queue lives in the very table this function is about to delete. Printing
    -- here instead does not work either: the reload on the next line destroys
    -- the chat frame, which is the whole reason QueueMessage exists. So the
    -- queue is the one thing carried across the wipe, and InitDB rebuilds every
    -- other key at the next login. Without this a reset that could not restore
    -- the Edit Mode layout was completely silent, which is the exact failure
    -- QueueMessage was written to remove.
    local carried = ns.db and ns.db.pendingMessages

    -- Lulu's records are debts, not settings. Each one is what a character needs
    -- to switch its action bars back on or put its Edit Mode layout back, and the
    -- teardown above can only settle THIS character's: it reads the current
    -- player's records and nothing else. The wipe below would take an alt's with
    -- it, leaving that character with the module off, Lulu's layout active, and
    -- nothing left that knows either — the reset also clears every profile's
    -- switch block, so the alt does not even come back reading Lulu ON. They ride
    -- across the wipe for the same reason the queued messages do.
    --
    -- Only records still OWED travel. The teardown clears what it settles, so the
    -- current character's are already gone unless something refused to apply.
    local owed
    local snaps = ns.db and ns.db.euiSnapGlobal
    if type(snaps) == "table" then
        for key, saved in pairs(snaps) do
            if type(key) == "string" and key:sub(1, 4) == "lulu"
                and type(saved) == "table" and saved.prev ~= nil then
                owed = owed or {}
                owed[key] = { prev = saved.prev }
            end
        end
    end

    local fresh
    if (carried and #carried > 0) or owed then
        fresh = {}
        if carried and #carried > 0 then fresh.pendingMessages = carried end
        if owed then fresh.euiSnapGlobal = owed end
    end
    KitnUIDB = fresh
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

    -- Plater is omitted while it is dormant (see the addon step list in
    -- Installer.lua): printing a data version for a profile the installer no
    -- longer offers would advertise something the user cannot get.
    local order = { "EllesmereUI", "BigWigs", "NSRT", "KitnEssentials", "BuffReminders", "Baganator", "Blizzard_EditMode", "BlizzardCDM" }
    local names = {
        EllesmereUI = "EllesmereUI", Plater = "Plater", BigWigs = "BigWigs",
        NSRT = "Northern Sky Raid Tools", Blizzard_EditMode = "Edit Mode",
        KitnEssentials = "KitnEssentials", BuffReminders = "BuffReminders",
        Baganator = "Baganator", BlizzardCDM = "Blizzard CDM",
    }
    for _, key in ipairs(order) do
        -- CDM has no version to print. Reading addonVersions for it here was the
        -- fifth status surface the header removal had to cover: with no header,
        -- `current` is nil forever and the Outdated branch below becomes
        -- unreachable, so a stale layout would have read "Imported".
        if key == "BlizzardCDM" then
            local _, rows = ns.GetCDMSpecRows()
            local summary = ns.SummarizeCDMRows(rows)
            -- The colour follows the WORST row, not "has this class imported
            -- anything". ns.HasCDMForCurrentClass answers the import question
            -- and counts a stale layout as imported, so reading it here painted
            -- an outdated class green -- the one state this line exists to
            -- flag -- and painted "1 up to date, 2 not imported" green too.
            local worst = "none"
            for _, row in ipairs(rows) do
                if row.state == "stale" then
                    worst = "stale"
                    break
                elseif row.state == "untracked" or row.state == "missing" then
                    worst = "partial"
                elseif row.state == "current" and worst == "none" then
                    worst = "current"
                end
            end
            local color = "|cff9d9d9d"
            if worst == "stale" then
                color = "|cffFF0000"
            elseif worst == "partial" then
                color = "|cffFFAA00"
            elseif worst == "current" then
                color = "|cff00FF00"
            end
            print("  " .. names[key] .. ": " .. color .. summary .. "|r |cff9d9d9d(this class)|r")
        else
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
        -- Registered by KitnUI_EUI, which can be disabled on its own now that it is a
        -- separate addon. Advertising a command that answers "Unknown command" is
        -- worse than saying nothing.
        if KitnCommands and KitnCommands["options"] then
            print("  /kitn options  - Open the KitnUI tab in EllesmereUI's config panel")
        end
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

---------------------------------------------------------------------------------
-- SavedVariables init + boot (PLAYER_LOGIN)
---------------------------------------------------------------------------------

local function InitDB()
    if not KitnUIDB then KitnUIDB = CopyTable(defaults) end
    ns.db = KitnUIDB
    ns.db.profiles = ns.db.profiles or {}
    ns.db.addonVersions = ns.db.addonVersions or {}
    ns.db.extras = ns.db.extras or {}
    ns.db.perChar = ns.db.perChar or {}
    -- Vestigial after the 2026-08-07 migration: switch states live in
    -- EllesmereUI's profile now, and this table is only read by
    -- MigrateSettingsForward. Delete this line and the migration together, one
    -- release after they ship.
    ns.db.euiSettings = ns.db.euiSettings or {}
    ns.db.euiSnap = ns.db.euiSnap or {}
    ns.db.euiSnapGlobal = ns.db.euiSnapGlobal or {}
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    InitDB()

    -- Drained before the EllesmereUI check below, so a message survives even a
    -- session where the installer itself is unavailable. Consumed only when it is
    -- shown, so an interrupted login carries it to the next one. The delay matches
    -- the login notification further down: printed immediately it lands under the
    -- client's own startup spam, which is the problem this exists to solve.
    if ns.db.pendingMessages and #ns.db.pendingMessages > 0 then
        -- Cleared INSIDE the timer, not before it. Clearing first meant a reload
        -- inside the two-second delay consumed the lines without ever showing
        -- them, which is the failure the queue exists to prevent.
        C_Timer.After(2, function()
            local queued = ns.db and ns.db.pendingMessages
            if not queued or #queued == 0 then return end
            ns.db.pendingMessages = {}
            -- Blank lines around the block. It lands two seconds into a login,
            -- packed against the client's own startup output, and without the
            -- gap it reads as one more line of that rather than as the answer to
            -- something the user did.
            print("")
            for _, line in ipairs(queued) do print(line) end
            print("")
        end)
    end

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
                elseif info.oldVersion and info.newVersion then
                    updated[#updated + 1] = ns.Color(info.key) .. " (v" .. info.oldVersion .. " -> v" .. info.newVersion .. ")"
                else
                    -- No versions to name. CDM is the case that exists today: it
                    -- left the header scheme, so its entry carries specs instead.
                    -- Naming the key alone beats the nil concatenation this
                    -- branch used to raise.
                    updated[#updated + 1] = ns.Color(info.key)
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
