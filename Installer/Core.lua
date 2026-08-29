-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Core.lua                                                    ║
-- ║  Purpose: Addon bootstrap: SavedVariables + defaults, media/ ║
-- ║           LSM registration, colour helpers, /kitn slash      ║
-- ║           commands, and the login boot flow.                 ║
-- ╚══════════════════════════════════════════════════════════════╝

local addonName, ns = ... ---@type string, KitnUINS

-- The forward half of the bridge to KitnUI_EUI, which is a separate addon with
-- its own namespace table and reads this one through an __index fallthrough.
-- Must be the SAME table, not a copy: ns.db is not filled until PLAYER_LOGIN,
-- and a copy would freeze it empty.
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
-- The ONE definition. Every profile this installer writes -- EllesmereUI and
-- every companion -- derives its name from here, and the Lulu Edit Mode layout
-- derives from it too, so this string is the only place the shipped profile name
-- is decided. It carried a test value through v2 development; if it is ever set
-- back to one, set it back BEFORE tagging, not after.
ns.profileName = "KitnUI"
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version")
ns.data = ns.data or {}
ns.db = nil

-- The version as it should be SHOWN. ns.version is the raw .toc value and is not
-- printable as-is: the packager substitutes the git tag, which carries a leading
-- "v" that reads as a second "version" next to the word, and an unpackaged
-- checkout leaves the @project-version@ token in place. "dev" stands in for the
-- token rather than a hand-written number, which goes stale the first release
-- nobody remembers to edit it.
--
-- Display sites only. Anything COMPARING versions -- the update prompt's
-- stored-against-current test below -- must keep using ns.version raw, because
-- that is the form the stored value was written in.
--
-- `value` lets a caller pass a stored version through the same treatment.
function ns.DisplayVersion(value)
    local ver = value or ns.version
    if type(ver) ~= "string" or ver:find("project") then return "dev" end
    return (ver:gsub("^[vV]", ""))
end

-- EllesmereUI readiness guard (checked before touching the EUI API / wizard).
function ns.EUIReady()
    return _G.EllesmereUI and EllesmereUI.ImportProfile and true or false
end

-- Why EUIReady() is false, for the boot prompt and OpenInstaller's refusal:
-- "missing" (not installed), "disabled" (installed but switched off for this
-- character), "loaderror" (enabled yet failed to load -- an interface,
-- dependency or Lua error), "tooold" (loaded without the import API). nil
-- when EllesmereUI is ready. The addon loads without EllesmereUI now that
-- the dependency is optional, so every consumer of the answer exists to
-- point the user at the right fix. Enabled-but-unloaded is deliberately NOT
-- called disabled: an Enable and Reload button against a load error would
-- walk the user through a reload that fixes nothing.
function ns.EUIMissingReason()
    if ns.EUIReady() then return nil end
    if not C_AddOns.DoesAddOnExist("EllesmereUI") then return "missing" end
    if IsAddOnLoaded("EllesmereUI") then return "tooold" end
    local state = C_AddOns.GetAddOnEnableState
        and C_AddOns.GetAddOnEnableState("EllesmereUI", UnitGUID("player"))
    -- Enum.AddOnEnableState.None is 0. A state we cannot read fails CLOSED,
    -- to loaderror: that popup has no button, so being wrong there costs one
    -- inaccurate sentence, while calling it disabled would offer an Enable
    -- and Reload button that reloads without fixing anything -- and the same
    -- popup would greet the user again on the far side, forever.
    if state == 0 then return "disabled" end
    return "loaderror"
end

-- Tell EllesmereUI that KitnUI owns the first-run experience, so EUI's own
-- first-install picker stays silent while our wizard runs. This is runtime
-- state on the EllesmereUI table, not a SavedVariable, so it has to be set
-- every session. File scope is early enough on both counts: EllesmereUI is
-- in OptionalDeps, so when it is present it loads before this file runs, and
-- EUI does not check the flag until PLAYER_LOGIN plus half a second. Guarded,
-- so a missing or older EllesmereUI simply keeps its own picker.
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
-- BLIZZARD CDM IS DELIBERATELY ABSENT, and it has no TOC header. One version
-- string cannot say WHICH spec changed, so a single edited layout would prompt a
-- three-spec player to reimport all three, and a hand-maintained header lies in
-- both directions once it drifts from the data. CDM answers "is this stale?" by
-- fingerprinting the string it ships -- see the block below.

function ns.GetAddonDataVersion(addonKey)
    local header = addonVersionHeaders[addonKey]
    if not header then return nil end
    return C_AddOns.GetAddOnMetadata(addonName, header)
end

---------------------------------------------------------------------------------
-- Blizzard CDM: content fingerprints instead of a version header
---------------------------------------------------------------------------------

-- A short token derived from the layout string KitnUI ships for one spec. Only
-- ever compared against another token this function produced, so it never has to
-- be cryptographic and never leaves SavedVariables.
--
-- Multiply-and-modulo, not FNV-1a: FNV needs bit.bxor and bitops are forbidden
-- family-wide. The largest intermediate is (2^32-1)*33+255, about 1.42e11 --
-- far below 2^53, so a double holds it exactly and the result cannot drift.
--
-- THE EMISSION SPLITS h RATHER THAN FORMATTING IT WHOLE. How %d or %x renders a
-- double outside the signed 32-bit range is host-dependent. Two halves below
-- 2^16 are well defined everywhere, and the split is lossless
-- (hi * 65536 + lo == h), so it costs no hash bits. Length is a third field:
-- two strings that collide on the hash almost certainly differ in length.
local function Fingerprint(str)
    if type(str) ~= "string" or str == "" then return nil end

    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 4294967296
    end
    return format("%d-%d-%d", math.floor(h / 65536), h % 65536, #str)
end

-- The storage key. A STRING, so it can never collide with the plain integer spec
-- indices older builds wrote -- which is what makes the migration in
-- GetCDMSpecState safe with no argument about numeric ranges.
--
-- Both halves are validated because ns.SetupAddon forwards its variadic argument
-- straight through, so a caller can reach here with a nil or non-numeric spec.
function ns.GetCDMKey(classId, specIndex)
    if type(classId) ~= "number" or type(specIndex) ~= "number" then return nil end
    if classId < 1 or specIndex < 1 then return nil end
    if math.floor(classId) ~= classId or math.floor(specIndex) ~= specIndex then return nil end
    return format("%d:%d", classId, specIndex)
end

-- The two names the Cooldown Manager import works with, and the label both the
-- import and the prompt show the user. One source, because a second copy would
-- drift the first time either name changed and the drift would be silent: a
-- reader that simply never finds a match.
--
-- The legacy name is the one shipped before the rename, matched so an upgrade
-- REPLACES the old layout rather than leaving it holding one of the five slots.
--
-- Both arguments must already be numbers. Every caller validates them first,
-- through ns.GetCDMKey on the import side and through its own identity read on
-- the watcher side.
function ns.CDMLayoutName(classId, specIndex)
    local specName
    if GetSpecializationInfoForClassID then
        specName = select(2, GetSpecializationInfoForClassID(classId, specIndex))
    end
    local specLabel = specName or ("Spec" .. specIndex)
    return "KitnUI - " .. specLabel, "KUI - " .. specLabel, specLabel
end

-- Memoized because ns.IsAddonImported feeds every sidebar repaint, which would
-- otherwise re-hash the class's whole payload each time. The cache cannot go
-- stale: ns.data.BlizzardCDM is a load-time table literal and nothing writes to
-- it, so a shipped string is constant for the session.
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
    -- An `if`, not `and`/`or`: the value on the right can be nil.
    local held
    if type(store) == "table" and key then held = store[key] end

    if type(held) == "string" then
        return held == shipped and "current" or "stale"
    end
    return HasLegacyCDMKeys() and "untracked" or "missing"
end

-- THE SINGLE OWNER of every specialization API call on the status surfaces, so
-- there is one set of guards rather than one per surface. Returns the class id
-- (or nil) and the rows. The import path keeps its own calls; it is not status.
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
-- implementation serves both call sites and the test harness.
--
-- `snapshot` is the FROZEN pre-session copy of profiles.BlizzardCDM. A nil
-- specIndex asks "any spec of this class", which is what Import All needs.
--
-- Legacy keys warn even though they name no class, so this over-warns across
-- classes on purpose: the import deletes a matching layout before recreating it,
-- and over-warning costs a click while under-warning destroys work.
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

    -- CDM rides the same list so every consumer downstream is unchanged. Only
    -- the RULE differs: fingerprints, not a header. isNew is true only when
    -- nothing of this class is tracked and no legacy key survives, so a player
    -- coming back from an older build is offered an update, not announced as new.
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
        -- popup returns on every login. Checked on BOTH branches -- a dormant
        -- addon with an older stored version reaches the other one.
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
            -- a build that did not record a version. Both report as new because
            -- there is no old version to name. Reporting it once is enough: the
            -- reimport records a version and this stops firing.
            outdated[#outdated + 1] = {
                key = addonKey,
                newVersion = current,
                isNew = true,
            }
        end
    end
    return outdated
end

-- Blizzard's cap is five layouts PER TYPE, not five in total, so a character can
-- hold five Account and five Character layouts. Counting the whole list would
-- refuse a write that would have succeeded.
--
-- Only Account layouts are counted, because EllesmereUI's importer forces every
-- layout it writes to Enum.EditModeLayoutType.Account.
--
-- The name match is type-scoped for the same reason: ApplyPresetEditMode de-dupes
-- by NAME across both types, so a CHARACTER layout sharing our name frees a
-- Character slot, not the Account slot we are about to fill. Treating it as a
-- replacement would let a sixth Account layout through.
--
-- Returns true when the write is safe. An unreadable layout list, or a missing
-- Enum, also returns true, so a missing API costs the guard and not the feature
-- -- ApplyPresetEditMode reports its own failure in that case.
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

-- Which layout is active now, in a form that survives the list being reordered.
--
-- C_EditMode.GetLayouts returns SAVED layouts only, while its activeLayout field
-- indexes the presets-first COMBINED list, so the two need reconciling.
--
-- A preset is recorded as its INDEX: presets come first and their count is fixed,
-- so those indices cannot shift. A saved layout is recorded as its NAME, because
-- ApplyPresetEditMode inserts ahead of existing layouts and shifts every index
-- after it, so a saved index goes stale the moment Lulu Mode runs.
function ns.ActiveEditModeLayout()
    if not (C_EditMode and C_EditMode.GetLayouts) then return nil end

    local ok, info = pcall(C_EditMode.GetLayouts)
    if not (ok and type(info) == "table" and type(info.layouts) == "table") then return nil end
    if type(info.activeLayout) ~= "number" then return nil end

    local presets = Enum and Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues
    if type(presets) ~= "number" then return nil end

    if info.activeLayout <= presets then return info.activeLayout end

    local entry = info.layouts[info.activeLayout - presets]
    if type(entry) ~= "table" or type(entry.layoutName) ~= "string" then return nil end

    -- Override layouts (Plunderstorm and its kin) need no handling. Blizzard keeps
    -- the active override in a separate field from the saved list this reads, so
    -- an override never reaches this line and what is recorded is the ordinary
    -- layout underneath it -- the one worth going back to anyway.
    return entry.layoutName
end

---------------------------------------------------------------------------------
-- Saved variable defaults
---------------------------------------------------------------------------------

local defaults = {
    profiles = {},          -- [addonKey] = true when imported
    addonVersions = {},     -- [addonKey] = X-header version at time of import
    extras = {},            -- [extraKey] = true once the user opted in; account-wide so /kitn load repeats it on an alt
    installedVersion = nil, -- addon version at last install
    perChar = {},           -- [charName-realm] = { loaded = true/false, editModeApplied = true, layoutWatchOff = { [specIndex] = true } }
    pendingMessages = {},   -- lines to print after the next reload (see ns.QueueMessage)
    cdmLimitPending = {},   -- [charName-realm] = spec names the CDM layout cap blocked, reminded about at that character's next login
    euiSettings = {},       -- [profileName] = { accent = {...}, lulu = true } config tab switches
    euiSnap = {},           -- [section][profileName][key] = { prev = <old value> }
    bflSnap = {},           -- what BetterFriendlist's appearance keys held before KitnUI took them (see ApplyBetterFriendlistAppearance)
    euiSnapGlobal = {},     -- [key] = { prev = <old value> } for anything outside a profile: EllesmereUIDB root keys, plus Lulu's two per-character debts (keys prefixed "lulu")
    devMode = false,        -- toggle dev-mode update popup (/kitn dev)
}

-- The key every per-character record in KitnUIDB is stored under. Nil rather
-- than a throw when either half cannot be read, and nil rather than a half key:
-- a key missing its realm would read and write another character's record.
-- Every caller treats nil as "no answer this pass" and writes nothing.
function ns.GetCharKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. "-" .. realm
end

-- The characters a real profile import gives the alternate options theme to.
-- Everyone else gets the default one. The active theme is account-wide, so this
-- is a choice made once at import; nothing reasserts it at login and the
-- dropdown stays free afterward.
local EUI_ALT_THEME_CHARACTERS = {
    "Cznfik-Area 52",
    "Rescuelol-Mal'Ganis",
    "Zenfiki-Area 52",
    "Cznp-Area 52",
    "Bite-Area 52",
    "Cheeklord-Area 52",
    "Cheekgripper-Area 52",
    "Glizzygordo-Area 52",
    "Frankcole-Area 52",
}

-- Spaces, apostrophes and case are dropped from both sides before comparing.
-- The realm half arrives from GetRealmName as a display name, and a single
-- punctuation difference between that and the list above would silently hand the
-- character the default theme with nothing to show for it.
local function CanonicalCharKey(key)
    if type(key) ~= "string" then return nil end
    local canonical = key:gsub("[%s']", "")
    return canonical:lower()
end

local altThemeCharacters = {}
for _, key in ipairs(EUI_ALT_THEME_CHARACTERS) do
    altThemeCharacters[CanonicalCharKey(key)] = true
end

--- Whether this character is named on the roster. Only the by-name half of the
--- look question; ns.UsesAltTheme is the whole of it.
function ns.OnAltThemeRoster()
    local key = CanonicalCharKey(ns.GetCharKey())
    return (key ~= nil and altThemeCharacters[key] == true)
end

-- One character in this many, among those the roster does not name, is given the
-- alternate look as well.
local ALT_THEME_SHARE = 4

-- Derived from the character key, never drawn: an import must be able to run
-- twice and reach the same theme. Multiply-and-add over the bytes, kept inside
-- the range a double holds exactly.
local function KeyHash(key)
    local hash = 5381
    for i = 1, #key do
        hash = (hash * 33 + key:byte(i)) % 4294967296
    end
    return hash
end

--- Whether this character gets the alternate look: the artwork on the options
--- panel, the installer background, and the amber chrome. True for everyone the
--- roster names, and for a share of everyone it does not. Nil rather than a key
--- means no answer can be derived, and the default look is the safe one.
---
--- Answered here rather than through the theme bridge, which is absent when the
--- companion addon is disabled and the wizard still has art to pick.
---
--- The low bits of the hash follow the key's last byte too closely to decide a
--- share this small, so the value is folded before the split.
function ns.UsesAltTheme()
    if ns.OnAltThemeRoster() then return true end

    local key = CanonicalCharKey(ns.GetCharKey())
    if key == nil then return false end
    return math.floor(KeyHash(key) / 65536) % ALT_THEME_SHARE == 0
end

--- Which options theme this character should be given by an import. Named rather
--- than a boolean so the theme side owns its own names.
function ns.EUIThemeForCharacter()
    local names = ns.EUIThemeNames
    if type(names) ~= "table" then return nil end

    if ns.UsesAltTheme() then return names.alt end
    return names.default
end

---------------------------------------------------------------------------------
-- Color helpers (also used by Setup.lua / Installer.lua via ns)
---------------------------------------------------------------------------------

-- Say something to the user across a reload. A print on the line before
-- ReloadUI goes into a chat frame the client tears down microseconds later, so
-- queue instead of printing anywhere a reload follows; the boot handler prints
-- it on the far side.
function ns.QueueMessage(text)
    if type(text) ~= "string" or not ns.db then return end
    ns.db.pendingMessages = ns.db.pendingMessages or {}
    ns.db.pendingMessages[#ns.db.pendingMessages + 1] = text
end

function ns.Color(text)
    return string.format("|cffFF008C%s|r", text)
end

-- Truthiness is not enough here: a channel holding a string passes an `and` chain
-- and then raises on the multiply, and one outside 0-1 formats to more than two
-- hex digits, which produces an escape the game renders as literal text. Both
-- have to be rejected before any arithmetic runs.
local function AccentByte(v)
    if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then return nil end
    return math.floor(v * 255 + 0.5)
end

-- The same highlight for text drawn INSIDE the installer window, and for the
-- success toast, which is drawn over it while the installer runs. Everything read
-- somewhere else keeps ns.Color: chat lines, printed status, and the host's
-- confirm popups, where the window's colour has nothing around it to agree with.
-- The failure and warning toasts keep their own fixed red and amber, which carry
-- a meaning the accent would erase.
--
-- Reads the two constants the chrome paints from, so a colour cannot drift
-- between a page's words and the page they sit on. Falls back to the brand rather
-- than erroring, because this runs while a page is being built and a failure here
-- would leave the wizard half drawn.
function ns.WizardColor(text)
    local c = ns.UsesAltTheme and ns.UsesAltTheme() and ns.RASTA_AMBER or ns.KITN_PINK
    if type(c) ~= "table" then return ns.Color(text) end
    local r, g, b = AccentByte(c[1]), AccentByte(c[2]), AccentByte(c[3])
    if not (r and g and b) then return ns.Color(text) end
    return string.format("|cff%02X%02X%02X%s|r", r, g, b, text)
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
    local key = ns.GetCharKey()
    if not key then return false end
    return self.db.perChar[key] and self.db.perChar[key].loaded
end

function ns:SetCharLoaded()
    local key = ns.GetCharKey()
    if not key then return end
    self.db.perChar[key] = self.db.perChar[key] or {}
    self.db.perChar[key].loaded = true
end

-- Whether KitnUI's Edit Mode layout has genuinely been applied on THIS
-- character. The profile flag beside it is account-wide and the layout it names
-- is account-wide too, so on an alt that has never been touched every test but
-- this one passes.
function ns:HasEditModeApplied()
    local key = ns.GetCharKey()
    if not key then return false end
    local rec = self.db and self.db.perChar and self.db.perChar[key]
    return (rec and rec.editModeApplied) == true
end

-- Written key by key into whatever record is already there. A fresh table would
-- erase the per-spec opt-outs stored beside it.
--
-- Reports whether it wrote, because one caller has to answer differently when it
-- did not. A writer that returns nothing forces that caller to assume success.
function ns:MarkEditModeApplied()
    local key = ns.GetCharKey()
    if not key or not self.db then return false end
    self.db.perChar = self.db.perChar or {}
    local rec = self.db.perChar[key]
    if not rec then
        rec = {}
        self.db.perChar[key] = rec
    end
    rec.editModeApplied = true
    return true
end

---------------------------------------------------------------------------------
-- Confirmation popup for /kitn install when already installed
---------------------------------------------------------------------------------

local function ConfirmOverwriteInstall(fn)
    -- Refused rather than degraded. Reading a nil key as "no record" would skip
    -- the confirmation below and overwrite the user's profiles unasked.
    local key = ns.GetCharKey()
    if not key then
        print(ns.title .. ": Could not identify this character, so nothing was started. Try again in a moment.")
        return
    end

    if ns.db and ns.db.perChar[key] then
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
    -- Put back everything the config tab is holding down BEFORE the snapshots
    -- go, or the two die out of step. The teardown refuses in combat, and a
    -- refusal must abort the whole reset rather than wipe the saved variables
    -- the restore still needs.
    --
    -- Its absence aborts for the same reason. KitnUI_EUI can be disabled on its
    -- own, and with it goes the only code that can reverse Lulu's action bars
    -- and Edit Mode layout. Refusing out loud beats a reset that looks like it
    -- worked.
    if not ns.EUIResetAll then
        print(ns.title .. ": cannot reset while the KitnUI_EUI addon is disabled, because the settings it is holding down could not be put back. Enable it, reload, then try again.")
        return
    end
    if ns.EUIResetAll() == false then return end

    -- BetterFriendlist's appearance keys live in ITS saved variables, so the wipe
    -- below cannot reach them -- only the snapshot it is about to delete knows
    -- what they held. Put them back first. After the EllesmereUI teardown on
    -- purpose: that one can still refuse, and a refusal must leave everything as
    -- it was.
    --
    -- A false answer means the addon is not loaded to take its settings back, so
    -- the snapshot rides across the wipe with the other debts below. Dropping it
    -- would strand KitnUI's values in BetterFriendlist forever: nothing else
    -- remembers what the player had.
    local bflOwed
    if ns.RestoreBetterFriendlistAppearance then
        if ns.RestoreBetterFriendlistAppearance() == false then
            bflOwed = ns.db.bflSnap
            -- Said out loud, because a reset that quietly leaves another addon
            -- on KitnUI's settings looks like a reset that worked. The line is
            -- queued rather than printed: the reload below tears the chat frame
            -- down.
            ns.QueueMessage(ns.title .. ": BetterFriendlist is not loaded, so its appearance could not be put back. KitnUI kept the record -- enable BetterFriendlist and run " .. ns.Color("/kitn reset") .. " again to finish it.")
        elseif ns.db.bflSnap and ns.db.bflSnap.verify then
            -- Put back, but that addon's own picker can roll its keys off again
            -- during the reload below, exactly as it can undo an install. So the
            -- record rides across the wipe for ONE check at the next login;
            -- RecheckBetterFriendlistAppearance settles it and drops it.
            bflOwed = ns.db.bflSnap
        end
    end

    -- That teardown queues a line for anything it could NOT put back, and the
    -- queue lives in the very table this function is about to delete. Printing
    -- here instead does not work: the reload two lines down destroys the chat
    -- frame. So the queue rides across the wipe, and InitDB rebuilds every other
    -- key at the next login.
    local carried = ns.db and ns.db.pendingMessages

    -- Lulu's records are debts, not settings: each one is what a character needs
    -- to switch its action bars back on or put its Edit Mode layout back. The
    -- teardown above settles only THIS character's. The wipe below would take an
    -- alt's with it, leaving that character with the module off, Lulu's layout
    -- active, and nothing left that knows either -- the reset clears every
    -- profile's switch block too, so the alt does not even come back reading
    -- Lulu ON. So they ride across the wipe.
    --
    -- Only records still OWED travel; the teardown clears what it settles.
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
    if (carried and #carried > 0) or owed or bflOwed then
        fresh = {}
        if carried and #carried > 0 then fresh.pendingMessages = carried end
        if owed then fresh.euiSnapGlobal = owed end
        if bflOwed then fresh.bflSnap = bflOwed end
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
    print(string.format("|cffffffffKitnUI version %s|r", ns.DisplayVersion()))

    -- Plater is omitted while it is dormant: printing a data version for a
    -- profile the installer no longer offers advertises something the user
    -- cannot get.
    local order = { "EllesmereUI", "BigWigs", "NSRT", "KitnEssentials", "BuffReminders", "Baganator", "Blizzard_EditMode", "BlizzardCDM" }
    local names = {
        EllesmereUI = "EllesmereUI", Plater = "Plater", BigWigs = "BigWigs",
        NSRT = "Northern Sky Raid Tools", Blizzard_EditMode = "Edit Mode",
        KitnEssentials = "KitnEssentials", BuffReminders = "BuffReminders",
        Baganator = "Baganator", BlizzardCDM = "Blizzard CDM",
    }
    for _, key in ipairs(order) do
        -- CDM has no version to print. With no header, `current` is nil forever
        -- and the Outdated branch below is unreachable, so the generic path
        -- would report a stale layout as "Imported".
        if key == "BlizzardCDM" then
            local _, rows = ns.GetCDMSpecRows()
            local summary = ns.SummarizeCDMRows(rows)
            -- The colour follows the WORST row, not "has this class imported
            -- anything". ns.HasCDMForCurrentClass answers the import question
            -- and counts a stale layout as imported, so it would paint an
            -- outdated class green -- the one state this line exists to flag.
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
        print(ns.title .. " " .. ns.DisplayVersion())
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
-- KitnUI_Lite conflict: reclaim the /kitn commands
---------------------------------------------------------------------------------

-- KitnUI_Lite is the standalone installer this addon replaces. It assigns the
-- same KitnCommands keys and the same SlashCmdList["KITN"] dispatcher at ITS
-- file scope, and it loads after this addon, so left alone it owns every
-- shared command: /kitn install opens Lite's installer and /kitn reset wipes
-- Lite's saved variables. The snapshot below is put back the moment Lite
-- finishes loading -- ADDON_LOADED fires after an addon's file scope runs --
-- so this addon wins whatever the load order, at login or later. Lite's own
-- extra entries (diag, slash) and other addons' entries (KitnEssentials'
-- shortcuts, KitnUI_EUI's options) are left alone: only the keys named here
-- are taken back, and a new /kitn command added above must be added here too.
local OWNED_KEYS = { "install", "load", "cdm", "dev", "reset", "update", "version", "ver", "v" }
local ownedCommands = {}
for _, key in ipairs(OWNED_KEYS) do ownedCommands[key] = KitnCommands[key] end
local ownedDispatcher = SlashCmdList["KITN"]

local reclaim = CreateFrame("Frame")
reclaim:RegisterEvent("ADDON_LOADED")
reclaim:SetScript("OnEvent", function(_, _, loadedName)
    if loadedName ~= "KitnUI_Lite" then return end
    for key, fn in pairs(ownedCommands) do
        KitnCommands[key] = fn
    end
    SLASH_KITN1, SLASH_KITN2, SLASH_KITN3 = "/kitn", "/kitnui", "/kui"
    SlashCmdList["KITN"] = ownedDispatcher
end)

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
    ns.db.cdmLimitPending = ns.db.cdmLimitPending or {}
    -- Vestigial after the 2026-08-07 migration: switch states live in
    -- EllesmereUI's profile now, and this table is only read by
    -- MigrateSettingsForward. Delete this line and the migration together, one
    -- release after they ship.
    ns.db.euiSettings = ns.db.euiSettings or {}
    ns.db.euiSnap = ns.db.euiSnap or {}
    ns.db.euiSnapGlobal = ns.db.euiSnapGlobal or {}
    ns.db.bflSnap = ns.db.bflSnap or {}
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    InitDB()

    -- Drained before the EllesmereUI check below, so a message survives a session
    -- where the installer itself is unavailable. The delay matches the login
    -- notification further down: printed immediately, it lands under the client's
    -- own startup output.
    if ns.db.pendingMessages and #ns.db.pendingMessages > 0 then
        -- Cleared INSIDE the timer. Clearing first lets a reload inside the
        -- two-second delay consume the lines without ever showing them.
        C_Timer.After(2, function()
            local queued = ns.db and ns.db.pendingMessages
            if not queued or #queued == 0 then return end
            ns.db.pendingMessages = {}
            -- Blank lines so the block reads as an answer to something the user
            -- did, not as one more line of the client's startup output.
            print("")
            for _, line in ipairs(queued) do print(line) end
            print("")
        end)
    end

    -- The layout cap the import ran into, asked about here rather than there:
    -- the wizard's own reload follows the failure within seconds, and the
    -- layouts it needs deleted are only reachable once that reload is done.
    -- Cleared once it HAS been raised, so one blocked import asks once and a
    -- refused one still asks later: StaticPopup_Show answers nil when a show
    -- condition rejects the dialog and when every dialog frame is already
    -- taken, and this login raises several popups of its own.
    -- One key, read and validated once. The timer below reads the pending list
    -- and then clears it, and a second read could answer differently between
    -- them.
    local charKey = ns.GetCharKey()
    local cdmBlocked = charKey and ns.db.cdmLimitPending and ns.db.cdmLimitPending[charKey]
    if cdmBlocked and #cdmBlocked > 0 then
        C_Timer.After(2, function()
            local pending = ns.db and ns.db.cdmLimitPending
            local blocked = pending and pending[charKey]
            if not blocked or #blocked == 0 then return end
            -- Icons are resolved HERE rather than carried across the reload.
            -- The store holds the spec's plain name, which is also the key the
            -- record and its clear match on, and writing a texture escape into
            -- it would make that key drift the first time the lookup answered
            -- differently. The record is per character, so the class the icons
            -- come from is always the class that owns the blocked specs.
            local specIcons = {}
            local iconClassId, iconRows = ns.GetCDMSpecRows()
            if iconClassId and GetSpecializationInfoForClassID then
                for _, row in ipairs(iconRows) do
                    local icon = select(4, GetSpecializationInfoForClassID(iconClassId, row.specIndex))
                    if icon then
                        if row.specName then specIcons[row.specName] = icon end
                        -- Keyed by the numbered label as well. A record written
                        -- in a session where the spec-name lookup was missing
                        -- holds "Spec<n>", and only this second key lets it find
                        -- an icon on a login where the lookup works again.
                        specIcons["Spec" .. row.specIndex] = icon
                    end
                end
            end

            -- Each name carries its own icon and colour so the separators stay
            -- plain. The accent rather than the class colour: these are the
            -- player's own specs, and a priest's white would not stand out at
            -- all against the popup's own text.
            local names = {}
            for i, spec in ipairs(blocked) do
                local icon = specIcons[spec]
                names[i] = (icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. ns.Color(spec)
            end

            StaticPopupDialogs["KITNUI_CDM_FULL"] = {
                text = ns.title .. ": Cooldown Manager layouts could not be imported for "
                    .. table.concat(names, ", ")
                    .. ".\n\nBlizzard allows five layouts per character and this one is full. Delete the layouts you do not use in the Cooldown Manager, then run " .. ns.Color("/kitn cdm") .. " to import the rest.",
                button1 = "Okay",
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            -- Printed whether or not the popup goes up, and before the attempt:
            -- a refused popup leaves this line as the only word the user gets
            -- this login, and a shown one leaves something to scroll back to
            -- after they click Okay.
            print(ns.title .. ": " .. ns.Red("Cooldown Manager layouts not imported") .. " - "
                .. table.concat(names, ", ") .. ". Delete layouts you do not use, then run "
                .. ns.Color("/kitn cdm") .. ".")

            if StaticPopup_Show("KITNUI_CDM_FULL") then
                pending[charKey] = nil
            end
        end)
    end

    -- KitnUI_Lite conflict, second half: the reclaim frame above has already
    -- taken the /kitn commands back by now, so this is the human half -- say
    -- why two installers are fighting and offer to end it. Before the
    -- EllesmereUI check on purpose: a Lite user without EllesmereUI needs
    -- this prompt too.
    if IsAddOnLoaded("KitnUI_Lite") then
        StaticPopupDialogs["KITNUI_LITE_CONFLICT"] = {
            text = ns.title .. ": KitnUI and KitnUI Lite are both enabled. The full KitnUI replaces Lite, and running both causes duplicate login prompts and conflicting /kitn commands.\n\nDisable KitnUI Lite now? After that, remove it in your addon manager.",
            button1 = "Disable and Reload",
            button2 = "Later",
            OnAccept = function()
                if C_AddOns.DisableAddOn then
                    -- No character argument on purpose: disabled for the whole
                    -- account, because the conflict exists on every character.
                    C_AddOns.DisableAddOn("KitnUI_Lite")
                    ReloadUI()
                end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("KITNUI_LITE_CONFLICT")
    end

    if not ns.EUIReady() then
        -- Spam rule: a user who has completed an install gets one chat line,
        -- never a popup -- their profiles already exist and nagging them to
        -- install would be wrong. Only a user the first-run auto-open below
        -- would have caught gets the popup treatment.
        local completed = (ns.db.profiles and next(ns.db.profiles) ~= nil)
            or ns.db.installedVersion
        local reason = ns.EUIMissingReason()
        if completed then
            local words = {
                missing   = "not installed",
                disabled  = "disabled for this character",
                loaderror = "failing to load",
                tooold    = "too old for this KitnUI",
            }
            print(ns.title .. ": EllesmereUI is " .. (words[reason] or "unavailable")
                .. ", so the installer and profile loading are unavailable until it is back.")
        else
            local text, button1, button2, accept
            if reason == "disabled" then
                text = ns.title .. ": Welcome! KitnUI installs profiles for EllesmereUI, which is installed but disabled. Enable it and reload to start the installer?"
                button1 = "Enable and Reload"
                button2 = "Later"
                accept = function()
                    if C_AddOns.EnableAddOn then
                        -- This character only: no argument means the whole
                        -- account (see AddonCharacter in Setup.lua).
                        C_AddOns.EnableAddOn("EllesmereUI", UnitGUID("player"))
                        ReloadUI()
                    end
                end
            elseif reason == "loaderror" then
                -- Blizzard's own reason token, humanized by its ADDON_*
                -- globalstring when one exists (ADDON_INTERFACE_VERSION is
                -- "Out of date", and so on).
                local why
                if C_AddOns.GetAddOnInfo then
                    why = select(5, C_AddOns.GetAddOnInfo("EllesmereUI"))
                end
                if type(why) == "string" and why ~= "" then
                    why = " (" .. (_G["ADDON_" .. why] or why) .. ")"
                else
                    why = ""
                end
                text = ns.title .. ": Welcome! KitnUI needs EllesmereUI, which is enabled but could not load" .. why .. ". Update EllesmereUI, then log back in to start the installer."
                button1 = "Okay"
            elseif reason == "tooold" then
                text = ns.title .. ": Welcome! KitnUI needs a newer EllesmereUI than this one. Update EllesmereUI, then log back in to start the installer."
                button1 = "Okay"
            else
                text = ns.title .. ": Welcome! KitnUI installs profiles for EllesmereUI, which is not installed. Install EllesmereUI from CurseForge or Wago, then log back in to start the installer."
                button1 = "Okay"
            end
            StaticPopupDialogs["KITNUI_NEEDS_EUI"] = {
                text = text,
                button1 = button1,
                button2 = button2,
                OnAccept = accept,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("KITNUI_NEEDS_EUI")
        end
        return
    end

    local hasProfiles = ns.db.profiles and next(ns.db.profiles)

    -- First run: launch the installer a moment AFTER login rather than during
    -- it. The wizard is a UISpecialFrames member (Wizard.lua), and a
    -- window shown while login is still finishing is swept closed with the rest
    -- of them: an in-game probe on 2026-08-22 found the frame built, paged to
    -- step 1 and at full alpha, yet hidden, with nothing printed and no error.
    -- The delay matches the login notification at the bottom of this handler.
    if not hasProfiles and not ns.db.installedVersion then
        -- Every reason to stand down is re-tested at fire time, because two
        -- seconds is long enough for the user to act first. Returns false only
        -- when combat is the one thing in the way, which the retry below waits
        -- out; every other answer is final for this session.
        local function OpenFirstRun()
            if not ns.db or ns.db.installedVersion then return true end
            if ns.db.profiles and next(ns.db.profiles) then return true end
            -- /kitn install during the wait opens this same wizard, and
            -- re-queueing it would throw the user back to page 1.
            if ns.Wizard and ns.Wizard.frame and ns.Wizard.frame:IsShown() then return true end
            if InCombatLockdown() then return false end
            if ns.OpenInstaller then ns.OpenInstaller() end
            return true
        end

        C_Timer.After(2, function()
            if OpenFirstRun() then return end
            -- Logging in mid-combat would otherwise spend the only automatic
            -- open on a refusal -- OpenInstaller declines in combat -- and
            -- leave a first-run player with no wizard for the whole session.
            local retry = CreateFrame("Frame")
            retry:RegisterEvent("PLAYER_REGEN_ENABLED")
            retry:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                OpenFirstRun()
            end)
        end)

    -- Version update: prompt to re-install (overall version or per-addon versions).
    -- Dev-mode: always show popup when version is unresolved (@project-version@).
    elseif hasProfiles and ns.db.installedVersion and ns.version
        and (ns.db.installedVersion ~= ns.version or ns.db.devMode)
        and ns.db.dismissedVersion ~= ns.version then
        local outdated = ns.GetOutdatedAddons()
        -- Both sides go through DisplayVersion: the test above compares the RAW
        -- stored value, but the sentence the user reads must not carry the
        -- packager's "v" on either side of the arrow.
        local updateText = ns.title .. " has been updated ("
            .. ns.DisplayVersion(ns.db.installedVersion) .. " -> " .. ns.DisplayVersion() .. ")."
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
        -- In the same delayed block because it can print: BetterFriendlist may
        -- have undone the installer's appearance write, or a /kitn reset's
        -- restore, during the reload that was meant to apply it (Setup.lua).
        -- Bounded on both sides -- three logins for the write, one for the
        -- reset -- and silent unless it actually had to write again.
        if ns.RecheckBetterFriendlistAppearance then ns.RecheckBetterFriendlistAppearance() end

        local outdated = ns.GetOutdatedAddons()
        if #outdated > 0 then
            local updated, new = {}, {}
            for _, info in ipairs(outdated) do
                if info.isNew then
                    new[#new + 1] = ns.Green(info.key)
                elseif info.oldVersion and info.newVersion then
                    updated[#updated + 1] = ns.Color(info.key) .. " (v" .. info.oldVersion .. " -> v" .. info.newVersion .. ")"
                else
                    -- No versions to name -- CDM's entry carries specs instead,
                    -- so name the key alone rather than concatenating a nil.
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
