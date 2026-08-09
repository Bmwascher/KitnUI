-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/Core.lua                                         ║
-- ║  Purpose: Inject a KitnUI category into EllesmereUI's config ║
-- ║           panel and provide the machinery its pages share.   ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- Read-through to KitnUI's namespace. Resolution happens per read, so symbols
-- KitnUI fills late (ns.db is not populated until PLAYER_LOGIN) resolve the
-- moment they exist rather than at load. Writes stay local by design: anything
-- this addon defines is its own. The trap that implies is that assigning a name
-- KitnUI also owns would shadow it silently for this addon only.
-- Without it this addon has no ns.title, no ns.db and no ns.data, and every file
-- after this one uses all three at load. Say so once and load nothing: a KitnUI
-- old enough to satisfy the folder dependency but too old to publish the bridge
-- is a version mismatch the user can fix, and a stack of Lua errors at every
-- login would not tell them that. EUI_INERT is set before the return because the
-- files after this one read it to stop as well; the print prefix is spelled out
-- because ns.title is one of the things that is missing.
local core = _G.KitnUI_Shared
if not core then
    ns.EUI_INERT = true
    print("|cffFF008CKitn|r|cffffffffUI:|r The KitnUI_EUI addon needs a newer KitnUI. Update KitnUI, or switch the KitnUI_EUI addon off.")
    return
end
setmetatable(ns, { __index = core })

-- Used as the sidebar row key, the info-table key, and RegisterModule's folder
-- argument. It does not have to match KitnUI's real addon folder: alwaysLoaded
-- short-circuits the IsAddonLoaded check the sidebar would otherwise run. It
-- does have to be identical at all four sites.
ns.EUI_MODULE_KEY = "KitnUI"

-- Page files register themselves here rather than Core listing them, so adding
-- a page never edits this file. Order is separate because the router is keyed.
ns.EUIPages = ns.EUIPages or {}
-- Top Bar goes last because it is a placeholder, and a page that says "Coming
-- soon" should not sit between two working pages.
ns.EUIPageOrder = { "General", "Gameplay", "Nameplates", "Top Bar" }

---------------------------------------------------------------------------------
-- EllesmereUI database access
---------------------------------------------------------------------------------

-- Cache the db OBJECT, never db.profile: a profile switch re-points .profile in
-- place, so a cached profile table silently becomes the old profile's data.
local dbCache = {}

-- EllesmereUI.Lite.GetAddon(folder, true).db is nil for EllesmereUIUnitFrames
-- and EllesmereUIMythicTimer, which keep their db file-local, and GetAddon
-- returns nil outright for EllesmereUIDamageMeters and EllesmereUIQuestTracker,
-- which never register an addon object at all. The registry scan is therefore
-- required, not a fallback of last resort.
function ns.EUIProfile(folder)
    local L = _G.EllesmereUI and EllesmereUI.Lite
    if not (L and folder) then return nil end

    local cached = dbCache[folder]
    if cached and cached.profile then return cached.profile end

    if L.GetAddon then
        local ok, addon = pcall(L.GetAddon, folder, true)
        if ok and addon and addon.db and addon.db.profile then
            dbCache[folder] = addon.db
            return addon.db.profile
        end
    end

    local reg = L._dbRegistry
    if type(reg) == "table" then
        for i = 1, #reg do
            local entry = reg[i]
            if entry and entry.folder == folder and entry.profile then
                dbCache[folder] = entry
                return entry.profile
            end
        end
    end

    return nil
end

-- ns.EUIProfile reaches a module's PROFILE, through GetAddon or the registry
-- scan. This reaches the addon OBJECT, which is where modules hang their public
-- helpers: EllesmereUIActionBars keeps its visibility compat layer there, and
-- writing barVisibility without it desyncs five companion fields.
--
-- No registry fallback, deliberately: _dbRegistry stores dbs, not addons, so
-- there is nothing there to fall back to.
function ns.EUIAddon(folder)
    local L = _G.EllesmereUI and EllesmereUI.Lite
    if not (L and L.GetAddon and folder) then return nil end
    local ok, addon = pcall(L.GetAddon, folder, true)
    if ok and type(addon) == "table" then return addon end
    return nil
end

-- Keyed by profile because a value from one profile says nothing about another.
local function ActiveProfileName()
    if _G.EllesmereUI and EllesmereUI.GetActiveProfileName then
        local ok, name = pcall(EllesmereUI.GetActiveProfileName)
        if ok and type(name) == "string" then return name end
    end
    return (_G.EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
end

-- The same table ns.EUIProfile returns, read straight out of EllesmereUI's saved
-- variables instead of out of its live registry. A module that is switched off is
-- in neither, but its settings are still filed under the active profile and are
-- still what it will read the next time it loads: NewDB does not create them, it
-- finds them (References/EllesmereUI-v8.7.5/EllesmereUI/EllesmereUI_Lite.lua:265-273).
--
-- This exists for one job, undoing a value KitnUI forced into a module that has
-- since been switched off. Nothing else should prefer it: while the module is
-- loaded ns.EUIProfile returns the very same table AND the module's own helpers
-- are reachable, and only that route can apply a change without a reload.
function ns.EUIStoredProfile(folder)
    if not folder then return nil end
    local profiles = _G.EllesmereUIDB and EllesmereUIDB.profiles
    if type(profiles) ~= "table" then return nil end
    local profile = profiles[ActiveProfileName()]
    if type(profile) ~= "table" or type(profile.addons) ~= "table" then return nil end
    local stored = profile.addons[folder]
    if type(stored) ~= "table" then return nil end
    return stored
end

---------------------------------------------------------------------------------
-- Settings store
---------------------------------------------------------------------------------

-- Switch states live in EllesmereUI's own per-profile store, which is what puts
-- KitnUI in its Export Profile list: the export resolves each listed addon
-- through Lite._dbRegistry, so an addon outside the registry can appear in the
-- list and still export nothing.
--
-- Commit 0a4835e moved these OUT of that store because EllesmereUI's spec
-- override engine was nilling them on every reload. That diagnosis was right and
-- the conclusion was too broad: a removal marker self-heals against a REGISTERED
-- DEFAULT (HasRegisteredDefault walks db._profileDefaults), and the only reason a
-- third party has none is that it passed none. NaowhUI passes { profile = {} },
-- which is why it needs a hand-maintained sync pass. We pass real defaults
-- instead, and the engine leaves us alone.
--
-- EVERY switch key must appear here. A key missing from this table is a key the
-- override engine is free to delete on the next reload, which is exactly the bug
-- that drove these settings out of the store in the first place. The values are
-- the OFF state: a default of true would make a switch read on for someone who
-- never touched it.
local DEFAULTS = {
    profile = {
        -- Lulu
        lulu                    = false,
        -- Gameplay
        beginner                = false,
        hideAllTooltipsInCombat = false,
        hideCdmTooltipsInCombat = false,
        -- General. A plain on/off value. It was `accent = { pink = false }` until
        -- 2026-08-09, and the switch wrote into that sub-table in place.
        --
        -- WHAT IS PROVEN, measured in Kitn's client on EllesmereUI 8.7.7: the
        -- value was live in the store at the instant of a reload, absent from the
        -- saved file immediately after, and every scalar switch in the same block
        -- survived that same save. Making this one key a scalar fixed it.
        --
        -- WHAT IS NOT PROVEN is the mechanism, and an earlier version of this
        -- comment claimed one. Reading Lite 8.7.5 under References/ says it
        -- cannot happen: DeepMergeDefaults builds a FRESH sub-table, so writing
        -- in place should never reach the registered default that the logout
        -- strip compares against. The installed 8.7.7 copy has a byte-identical
        -- StripDefaults and logout handler, so the difference is somewhere
        -- neither the cross-vendor reviewer nor I have read. Do not trust the
        -- withdrawn "shared table" story.
        --
        -- What survives that uncertainty is the rule: a scalar cannot be reached
        -- this way at all, because assigning one writes a key on the settings
        -- table and never touches the defaults table. The arrow colour below
        -- stays a table safely for the same reason — its setter REPLACES the
        -- table instead of writing into it. Both of those shapes are verified in
        -- game. An in-place write into a table-valued default is the one shape
        -- that is not, so nothing here uses it.
        accentPink              = false,
        -- Nameplates. Keep npArrowColor in step with ns.KITN_PINK in
        -- Installer/Wizard.lua: that one is POSITIONAL and this one is KEYED,
        -- and a registered default has to be a literal.
        npArrows                = false,
        npArrowColor            = { r = 1, g = 0, b = 0.549 },
        npArrowW                = 24,
        npArrowH                = 27,
        npArrowGap              = 3,
        npArrowY                = 0,
        npArrowGlow             = true,
        npArrowCastNudge        = true,
        npArrowCastKick         = 8,
    },
}

ns.EUI_DEFAULTS = DEFAULTS.profile

local settingsFallback
local settingsDB

-- The svName minus its trailing "DB" is the folder EllesmereUI files us under,
-- so "KitnUI_EUIDB" lands us in profiles[name].addons.KitnUI_EUI. NewDB also
-- wipes _G[svName]; KitnUI_EUIDB is declared by nothing, so that wipe hits a
-- throwaway. This is the entire reason the tab is a separate addon: from inside
-- a folder called KitnUI the svName would have to be KitnUIDB, our real file.
function ns.EUISettingsDB()
    if settingsDB and type(settingsDB.profile) == "table" then return settingsDB end
    local L = _G.EllesmereUI and EllesmereUI.Lite
    if not (L and L.NewDB) then return nil end
    local ok, db = pcall(L.NewDB, "KitnUI_EUIDB", DEFAULTS)
    if ok and type(db) == "table" and type(db.profile) == "table" then
        settingsDB = db
        return settingsDB
    end
    return nil
end

-- Latched fallback for a session where EllesmereUI is absent or too old: the
-- pages still have to render, and session-only storage beats erroring. Latched
-- because swapping the real store in mid-session would orphan every switch
-- flipped before it.
function ns.EUISettings()
    if settingsFallback then return settingsFallback end
    local db = ns.EUISettingsDB()
    if db then return db.profile end
    settingsFallback = {}
    return settingsFallback
end

---------------------------------------------------------------------------------
-- Snapshot store
---------------------------------------------------------------------------------

-- A key that did not exist is not the same as a key set to nil: absent means
-- "use the module's own default", and that state has to be restorable. nil
-- cannot be stored in a table to mean it, so a sentinel carries it.
ns.EUI_ABSENT = "__kitnui_absent__"

-- Snapshots live in KitnUI's own SavedVariable, never in the EllesmereUI
-- profile. A snapshot describes what THIS machine had before KitnUI touched it,
-- which is meaningless inside an exported look.
local function SnapRoot()
    if not ns.db then return nil end
    ns.db.euiSnap = ns.db.euiSnap or {}
    return ns.db.euiSnap
end

-- Snapshots key by profile off the same helper the switch states use, so the
-- two halves can never disagree about which profile a record belongs to.
--
-- Use this on the ON path only. It builds tables on the way down.
function ns.EUISnap(section, key)
    local root = SnapRoot()
    if not root then return nil end
    local profile = ActiveProfileName()
    root[section] = root[section] or {}
    root[section][profile] = root[section][profile] or {}
    root[section][profile][key] = root[section][profile][key] or {}
    return root[section][profile][key]
end

-- Use this on the OFF path. Asking "did we override this?" with EUISnap would
-- seed an empty record in every profile a user merely visits, which bloats the
-- saved variables of someone who never turned the switch on.
function ns.EUIPeekSnap(section, key)
    local root = SnapRoot()
    if not root then return nil end
    local sect = root[section]
    local profile = sect and sect[ActiveProfileName()]
    return profile and profile[key] or nil
end

-- Record once, then write. The record-once guard matters on re-apply: without
-- it, re-applying after a profile switch would snapshot KitnUI's own forced
-- value over the user's original and make the switch unrestorable.
--
-- STANDING RULE for every page built on this store, including the ones a later
-- plan adds: no two controls may hold down the same EllesmereUI key. The second
-- one to record would capture the first one's forced value as the original, and
-- whichever is switched off last would restore the wrong thing. If two controls
-- genuinely need the same key, they have to become one control.
function ns.EUIOverride(tbl, saved, key, value)
    if not (tbl and saved and key) then return end
    if saved.prev == nil then
        local current = tbl[key]
        if current == nil then current = ns.EUI_ABSENT end
        saved.prev = current
    end
    tbl[key] = value
end

-- Some EllesmereUI values live on the EllesmereUIDB ROOT rather than inside a
-- profile, so they are account-wide. Profile-keying their snapshots would misfile
-- one global under whichever profile happened to be active, and the record would
-- then be invisible from every other profile: the off path would find nothing to
-- restore, and turning the switch on again would snapshot KitnUI's own forced
-- value as if it were the user's. These two helpers are the same store without
-- the profile dimension.
local function SnapGlobalRoot()
    if not ns.db then return nil end
    ns.db.euiSnapGlobal = ns.db.euiSnapGlobal or {}
    return ns.db.euiSnapGlobal
end

function ns.EUISnapGlobal(key)
    local root = SnapGlobalRoot()
    if not root then return nil end
    root[key] = root[key] or {}
    return root[key]
end

function ns.EUIPeekSnapGlobal(key)
    local root = ns.db and ns.db.euiSnapGlobal
    return root and root[key] or nil
end

-- Clearing saved.prev is what marks the value as no longer held down. The
-- snapshot's existence IS the "currently forcing this" flag, so nothing is
-- tracked twice.
function ns.EUIRestore(tbl, saved, key)
    if not (tbl and saved and key) then return end
    if saved.prev == nil then return end
    if saved.prev == ns.EUI_ABSENT then
        tbl[key] = nil
    else
        tbl[key] = saved.prev
    end
    saved.prev = nil
end

---------------------------------------------------------------------------------
-- Profile lifecycle
---------------------------------------------------------------------------------

local reapplyFns = {}

-- Each page file registers exactly one function that re-asserts everything that
-- page forces into EllesmereUI.
function ns.EUIRegisterReapply(fn)
    if type(fn) == "function" then
        reapplyFns[#reapplyFns + 1] = fn
    end
end

local reapplyPending = false

-- Debounced by design, not for tidiness. EllesmereUI.RefreshAllAddons runs off
-- the back of a profile switch and would overwrite anything written
-- synchronously, so the re-apply has to land after it.
function ns.EUIQueueReapply()
    if reapplyPending then return end
    reapplyPending = true
    C_Timer.After(0.1, function()
        reapplyPending = false
        -- pcall'd per member: one failing module must not strand the rest.
        for _, fn in ipairs(reapplyFns) do
            pcall(fn)
        end
        if ns.LuluReconcile then pcall(ns.LuluReconcile) end
    end)
end

-- The SNAPSHOT is keyed by profile name and lives in KitnUIDB, so a rename
-- orphans it and whatever KitnUI forced into that profile becomes unrestorable.
-- The switch states need no help: they live inside the profile table itself, and
-- EllesmereUI.RenameProfile moves that table wholesale.
local function MoveProfileRecords(oldName, newName)
    local snap = ns.db and ns.db.euiSnap
    if snap then
        for _, section in pairs(snap) do
            -- Never clobber: an existing newName record is real data.
            if section[oldName] and not section[newName] then
                section[newName] = section[oldName]
            end
            section[oldName] = nil
        end
    end
end

-- EllesmereUI's RenameProfile moves the profile order entry, the spec
-- assignments, the sync group membership and the CDM spell store to the new
-- name, but not EllesmereUIDB.colorsPullFrom: the name of the profile supplying
-- the shared custom colour palette. Renaming that profile leaves the pointer
-- dangling, GetCustomColorsDB finds no source and returns the bare root table,
-- and every custom colour silently falls back to an EllesmereUI default. The
-- visible symptom is the class resource bar jumping to the stock colour for the
-- spec's resource.
--
-- KitnUI is the reason this bites. Importing our profile sets colorsPullFrom to
-- our own profile name, so the profile a user is most likely to rename is
-- exactly the one holding the palette. Repaired here rather than reported and
-- left alone, because the user loses their colours in the meantime.
--
-- The palette is cached, so moving the pointer repaints nothing on its own.
-- Invalidate and repaint through the same two calls EllesmereUI uses after a
-- colour edit of its own.
local function RepairColorsPullFrom(oldName, newName)
    if not (_G.EllesmereUIDB and EllesmereUIDB.colorsPullFrom == oldName) then return end
    EllesmereUIDB.colorsPullFrom = newName

    local EUI = _G.EllesmereUI
    if not EUI then return end
    if EUI.InvalidateColorCache then pcall(EUI.InvalidateColorCache) end
    if EUI.ApplyColorsToOUF then pcall(EUI.ApplyColorsToOUF) end
end

local function OnProfileRenamed(oldName, newName)
    if type(oldName) ~= "string" or type(newName) ~= "string" then return end
    MoveProfileRecords(oldName, newName)
    RepairColorsPullFrom(oldName, newName)
end

-- Without this, a new profile that reuses a deleted profile's name inherits the
-- old one's SNAPSHOTS and restores values it never had. The switch states go
-- with the profile table that EllesmereUI.DeleteProfile drops.
local function OnProfileDeleted(name)
    if type(name) ~= "string" then return end

    local snap = ns.db and ns.db.euiSnap
    if snap then
        for _, section in pairs(snap) do
            section[name] = nil
        end
    end

    -- Deleting the ACTIVE profile repoints every db to Default without going
    -- through SwitchProfile, ApplyProfileData or OnSpecSwitchComplete, so this
    -- handler is the only place that learns about it. Safe to queue before the
    -- repoint happens: EUIQueueReapply defers by 0.1 seconds. Queued even when
    -- there was nothing to clear, because the repoint still happened.
    ns.EUIQueueReapply()
end

-- The switch states now live in EllesmereUIDB, one block per profile; only the
-- snapshots recording what those switches overrode still live in KitnUIDB. The
-- caller nils KitnUIDB, so the snapshots die when it does. What still has
-- to be handled is the OTHER side: EllesmereUI is left holding whatever KitnUI
-- forced into it, and once the snapshots are gone nothing remembers the
-- originals. So the reset turns every switch off FIRST and lets each page's own
-- re-apply put the originals back while the snapshots are still there.
--
-- Two things this has to cover beyond the active profile:
--   * Lulu Mode's module disable and Edit Mode layout are not in the re-apply
--     registry, because reversing them needs a reload. Reset reloads anyway.
--   * Every profile's switch block is cleared, not just the active one's. The
--     active profile goes through db:ResetProfile so the live db.profile
--     reference stays valid; every other profile's block is deleted outright,
--     safe because nothing holds a reference to it until a profile switch, at
--     which point RepointAllDBs re-points and re-merges the defaults. The
--     snapshots stay a separate store in KitnUIDB; the caller nilling that
--     file is what clears those.
--
-- And one thing it deliberately does NOT cover, stated here because losing the
-- statement would make it look like an oversight. A value forced into a
-- NON-active EllesmereUI profile stays forced. The re-apply registry only ever
-- reaches the live profile, and that profile's snapshots die with KitnUIDB, so
-- nothing is left that knows the original. Reaching further would mean walking
-- every profile through every page's restore with the db object pointed
-- somewhere it is not, which is a larger and riskier job than the case is worth.
--
-- Everything runs synchronously, because the caller nils KitnUIDB straight after
-- and a debounced pass would fire into the wreckage.
--
-- Returns false and does nothing in combat. The Lulu teardown reverses an Edit
-- Mode layout, and ApplyPresetEditMode refuses in combat, so a reset typed
-- mid-fight would reload with the Lulu layout still active and the switch
-- already cleared.
function ns.EUIResetAll()
    if InCombatLockdown() then
        print(ns.title .. ": Cannot reset during combat. Try again after this fight.")
        return false
    end

    -- Refused, not degraded. On an EllesmereUI too old for Lite.NewDB the store
    -- is the session-only fallback, which starts empty and knows none of the real
    -- switch states: Lulu could be recorded ON in EllesmereUIDB while the fallback
    -- reads OFF, so the teardown below would skip and leave the action bars off
    -- and the Lulu layout active. The caller nils KitnUIDB straight afterwards,
    -- taking every snapshot with it, and the loop further down would delete the
    -- persistent switch blocks too. Nothing would be left that knows what to put
    -- back. EllesmereUIDB is a saved variable and survives a downgrade, so this
    -- state is reachable and the settings it is holding down are real.
    local db = ns.EUISettingsDB()
    if not db then
        print(ns.title .. ": Cannot reset with this version of EllesmereUI, because it cannot read the settings KitnUI is holding down and resetting would strand them. Update EllesmereUI, then try again.")
        return false
    end

    if ns.LuluTearDown then pcall(ns.LuluTearDown) end

    -- The ACTIVE profile is cleared through the db object so the live
    -- db.profile reference stays valid: ResetProfile wipes in place and
    -- re-merges the registered defaults.
    if db.ResetProfile then
        pcall(function() db:ResetProfile() end)
    else
        local settings = ns.EUISettings()
        for key in pairs(settings) do
            settings[key] = nil
        end
    end

    for _, fn in ipairs(reapplyFns) do
        pcall(fn)
    end

    -- Every OTHER profile's block, dropped whole. Until 2026-08-07 the caller
    -- nilling KitnUIDB did this for free; now those blocks live in
    -- EllesmereUIDB and would survive a reset, leaving their switches reading ON
    -- with no snapshots anywhere.
    --
    -- The active profile is identified by table IDENTITY rather than by name.
    -- Both EllesmereUIDB.activeProfile and db._profileName track the active
    -- profile and RepointAllDBs keeps them in step, but comparing against the
    -- live db.profile pointer is what the loop actually needs to know: skip the
    -- one table the db object is currently holding, whatever it is called. That
    -- cannot go stale, so no name source has to be trusted.
    --
    -- Safe to delete rather than clear: nothing holds a reference to a
    -- non-active profile's block until a profile switch, and RepointAllDBs
    -- re-points and re-merges the defaults at that point.
    local live = db.profile
    local profiles = _G.EllesmereUIDB and EllesmereUIDB.profiles
    if type(profiles) == "table" then
        for _, profile in pairs(profiles) do
            if type(profile) == "table" and type(profile.addons) == "table" then
                if profile.addons.KitnUI_EUI ~= live then
                    profile.addons.KitnUI_EUI = nil
                end

                -- The pre-0a4835e key, swept unconditionally. It is never the live
                -- store, so no identity test applies, and the migration cannot be
                -- relied on to have removed it: EllesmereUI passes unknown addon
                -- keys straight through an import
                -- (References/EllesmereUI-v8.7.5/EllesmereUI/EllesmereUI_Profiles.lua:128-136,
                -- copied at :3029-3031), so importing an old profile reintroduces
                -- one long after the migration has stamped. Left here it would
                -- outlive this reset, which also nils KitnUIDB and the stamp with
                -- it, and the next login would migrate those stale switches back
                -- into the profile the user just reset.
                profile.addons.KitnUIEUI = nil
            end
        end
    end

    if ns.db then ns.db.euiSettings = {} end
end

---------------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------------

-- EllesmereUI:RegisterModule whitelists its callers: it reads debugstack, pulls
-- the "AddOns/<folder>/" segment out of the caller's path, and drops the call
-- unless that folder is one of its own twenty. The guard reads
-- `if callerFolder and not ALLOWED[callerFolder]`, so it fails OPEN when no
-- folder can be extracted. A loadstring chunk has no file path, so the call
-- lands. This is a deliberate bypass of a deliberate gate. EllesmereUI can close
-- it in one line, which is why every step is guarded and why losing the tab must
-- never break the installer.
local function RegisterModule(config)
    if not (_G.EllesmereUI and EllesmereUI.RegisterModule) then return end

    local ok = false
    if type(loadstring) == "function" then
        _G.__KitnUI_pendingReg = { key = ns.EUI_MODULE_KEY, config = config }
        local trampoline = loadstring([[
            local r = _G.__KitnUI_pendingReg
            if r and EllesmereUI and EllesmereUI.RegisterModule then
                EllesmereUI:RegisterModule(r.key, r.config)
            end
        ]], "KitnUI-register")
        if trampoline then ok = pcall(trampoline) end
        _G.__KitnUI_pendingReg = nil
    end

    -- Without loadstring the direct call still runs. The whitelist rejects it
    -- silently, which costs the tab and nothing else.
    if not ok then
        pcall(function() EllesmereUI:RegisterModule(ns.EUI_MODULE_KEY, config) end)
    end
end

-- Registering supplies page CONTENT. The sidebar ROW comes from two private
-- tables EllesmereUI builds from its own hardcoded roster, so the row has to be
-- inserted separately. The panel is built lazily on first open, so login is
-- early enough.
local function InjectSidebar()
    local EUI = _G.EllesmereUI
    if not EUI then return end

    -- alwaysLoaded hides the per-addon power toggle and marks the row enabled.
    -- KitnUI is not an EllesmereUI module the user can switch off from here.
    EUI._addonInfoByFolder = EUI._addonInfoByFolder or {}
    EUI._addonInfoByFolder[ns.EUI_MODULE_KEY] = EUI._addonInfoByFolder[ns.EUI_MODULE_KEY] or {
        folder       = ns.EUI_MODULE_KEY,
        display      = "KitnUI",
        search_name  = "KitnUI Kitn",
        alwaysLoaded = true,
    }

    -- No cross-module profile sync icon: KitnUI has nothing to sync.
    EUI._syncExempt = EUI._syncExempt or {}
    EUI._syncExempt[ns.EUI_MODULE_KEY] = true

    -- Guard against double insertion on /reload.
    EUI.ADDON_GROUPS = EUI.ADDON_GROUPS or {}
    for _, group in ipairs(EUI.ADDON_GROUPS) do
        if group.key == "kitnui" then return end
    end
    table.insert(EUI.ADDON_GROUPS, 1, {
        key     = "kitnui",
        label   = "KitnUI",
        members = { ns.EUI_MODULE_KEY },
    })
end

-- Export and import walk EllesmereUI's own _ADDON_DB_MAP rather than the db
-- registry, so a companion addon is invisible to them without this. The UI reads
-- the map live, so a login-time insert is picked up.
--
-- Only folder and display are read off a map entry. `canon` is derived by the
-- map's own file-scope loop for shipped entries and an injected one simply has
-- none, which AddonsToCanon handles by passing unknown keys through unchanged.
-- The loaded check falls back to the folder name, and KitnUI_EUI is a real
-- loaded addon, which is why the folder had to match the addon folder.
local function InjectProfileAddon()
    local EUI = _G.EllesmereUI
    local map = EUI and EUI._ADDON_DB_MAP
    if type(map) ~= "table" then return end
    for _, e in ipairs(map) do
        if e.folder == "KitnUI_EUI" then return end   -- a reload must not re-insert
    end
    map[#map + 1] = { folder = "KitnUI_EUI", display = "KitnUI" }
end

---------------------------------------------------------------------------------
-- Migration
---------------------------------------------------------------------------------

-- Switch states used to live in KitnUIDB.euiSettings, keyed by EllesmereUI
-- profile name (commit 0a4835e). They now live in the profile itself. This moves
-- them once.
--
-- Guarded on a version stamp rather than on the destination being empty: with
-- registered defaults the destination is NEVER empty, so emptiness cannot be the
-- condition.
--
-- KitnUIDB.euiSettings is left in place rather than deleted. If this migration is
-- wrong we want the evidence, and a stale table in our own saved variables costs
-- a few bytes. A later release drops it.
--
-- The pre-0a4835e block is NOT left in place, because it is not ours. It sits in
-- EllesmereUI's profile, so it rides every exported profile forever, and worse:
-- /kitn reset nils KitnUIDB and takes the version stamp below with it, so the
-- next login re-runs this migration and re-imports those stale switch states
-- over the reset the user just asked for.
-- 2 since 2026-08-09: the accent switch stopped being a nested table, so its old
-- value has to fold forward and the dead key has to go. Re-running version 1's
-- work is harmless — every write it makes is guarded on the destination key being
-- absent.
local MIGRATION_VERSION = 2

local function MigrateSettingsForward()
    if not ns.db then return end
    if (ns.db.euiMigration or 0) >= MIGRATION_VERSION then return end

    local profiles = _G.EllesmereUIDB and EllesmereUIDB.profiles
    if type(profiles) ~= "table" then return end

    local old = ns.db.euiSettings
    -- The pre-0a4835e key had no underscore, so it is a different key from the
    -- one we write now and would otherwise be stranded. Swept here too.
    -- type-checked, not just truthy: a malformed profile whose addons field is
    -- not a table would otherwise error on the index and abort the whole
    -- migration at whichever profile pairs() reached first.
    local function LegacyBlock(profile)
        local addons = profile.addons
        local b = type(addons) == "table" and addons.KitnUIEUI
        return type(b) == "table" and next(b) and b or nil
    end

    for name, profile in pairs(profiles) do
        if type(profile) == "table" then
            local source = (type(old) == "table" and type(old[name]) == "table" and old[name])
                            or LegacyBlock(profile)
            if source then
                if type(profile.addons) ~= "table" then profile.addons = {} end
                -- An absent block, or an absent key inside one, counts as still
                -- at its default and is created. NewDB only builds the ACTIVE
                -- profile's block at login; the rest appear on first switch via
                -- RepointAllDBs, so filling only existing blocks would silently
                -- skip every other profile.
                local dest = profile.addons.KitnUI_EUI
                if type(dest) ~= "table" then
                    dest = {}
                    profile.addons.KitnUI_EUI = dest
                end
                for key, default in pairs(ns.EUI_DEFAULTS) do
                    local incoming = source[key]
                    if incoming ~= nil and dest[key] == nil then
                        if type(default) == "table" and type(incoming) == "table" then
                            dest[key] = CopyTable(incoming)
                        else
                            dest[key] = incoming
                        end
                    end
                end

                -- Handled apart from the loop above, because that loop is driven
                -- by the CURRENT defaults and accent is no longer among them. The
                -- old stores still hold it in its retired nested shape, and
                -- KitnUIDB.euiSettings is our own saved variable, so unlike the
                -- profile copy it really does persist. Without this a user coming
                -- straight from that store loses the setting.
                local oldAccent = source.accent
                if type(oldAccent) == "table" and oldAccent.pink ~= nil
                    and dest.accentPink == nil then
                    dest.accentPink = oldAccent.pink and true or false
                end
            end

            -- Cleared whether or not it was the source. When euiSettings supplied
            -- the values it is the newer of the two stores and wins outright, so
            -- what is left here is older data that has already been superseded.
            if type(profile.addons) == "table" then profile.addons.KitnUIEUI = nil end

        end
    end

    ns.db.euiMigration = MIGRATION_VERSION
end

-- The accent switch's retired nested shape, folded forward and then DELETED.
--
-- Deliberately NOT part of the version-stamped migration above, and not a
-- once-per-login pass either. A profile imported at any point afterwards brings
-- the old key with it — EllesmereUI copies an addon block through an import
-- unchanged — and by then a one-time pass has long since stamped itself done.
-- Registered with the re-apply registry instead, which fires on a profile
-- switch, a spec switch and a profile apply, plus once at login — that last one
-- only on an EllesmereUI complete enough to build the tab, which is the only
-- state where anything reads the switch anyway. Registered from THIS file, so it
-- runs before General.lua's accent apply: the registry runs in registration
-- order and Core.lua loads first.
--
-- The retired value WINS, rather than yielding to an accentPink already sitting
-- in the block. That looks reckless and is not: no released version ever wrote
-- both keys, so the two together can only mean EllesmereUI merged the registered
-- default in, which it does on import (ApplyProfileData) and at login
-- (EUISettingsDB) before this ever runs. Yielding to it would read a defaulted
-- false as a deliberate choice and throw the real setting away.
--
-- Deleting rather than ignoring is the point. EllesmereUI's logout pass only
-- touches keys it has a registered default for, so a key it does not know is
-- kept forever and rides every exported profile out into the world.
local function FoldRetiredAccentKey()
    local profiles = _G.EllesmereUIDB and EllesmereUIDB.profiles
    if type(profiles) ~= "table" then return end

    for _, profile in pairs(profiles) do
        local addons = type(profile) == "table" and profile.addons
        local block = type(addons) == "table" and addons.KitnUI_EUI
        local dead = type(block) == "table" and block.accent
        if type(dead) == "table" then
            if dead.pink ~= nil then
                block.accentPink = dead.pink and true or false
            end
            block.accent = nil
        end
    end
end

ns.EUIRegisterReapply(FoldRetiredAccentKey)

---------------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------------

-- PLAYER_LOGIN, matching every EllesmereUI options file: page builders read
-- ns.db, which Installer/Core.lua only fills at login.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- ABOVE the capability guard, deliberately. Migration depends on none of the
    -- things that guard protects: it needs ns.db and EllesmereUIDB.profiles and
    -- nothing else. Below the guard it would be skipped on an EllesmereUI that has
    -- Lite.NewDB but no config panel, and the legacy block would then sit
    -- unconsumed while /kitn reset still works, because the export frame publishes
    -- EUIResetAll whether or not this handler returned early. Reset would open the
    -- new store, read a defaulted lulu = false, skip the teardown, and then delete
    -- the one record that said Lulu was on, stranding its action bars and layout
    -- with nothing left to restore them.
    --
    -- Ordered before the db is registered either way, so the defaults merge sees
    -- migrated values rather than bare defaults. ns.db is filled by
    -- Installer/Core.lua, whose PLAYER_LOGIN handler is registered first (its frame
    -- is created at KitnUI load time, before this addon loads) and has already run.
    MigrateSettingsForward()

    if not (_G.EllesmereUI and EllesmereUI.RegisterModule and EllesmereUI.Widgets) then return end

    InjectSidebar()

    -- Registration first, injection second. GetAddonProfile resolves a map entry
    -- through Lite._dbRegistry, so a map entry with no registered db reads
    -- "Ready" in the export list and exports nothing.
    ns.EUISettingsDB()
    InjectProfileAddon()

    -- Each guarded on the exact function it hooks: EllesmereUI dropping any one
    -- of these must cost that behaviour, not the tab.
    local EUI = _G.EllesmereUI
    if EUI.SwitchProfile        then hooksecurefunc(EUI, "SwitchProfile",        ns.EUIQueueReapply) end
    if EUI.OnSpecSwitchComplete then hooksecurefunc(EUI, "OnSpecSwitchComplete", ns.EUIQueueReapply) end
    if EUI.ApplyProfileData     then hooksecurefunc(EUI, "ApplyProfileData",     ns.EUIQueueReapply) end
    if EUI.OnProfileRenamed     then hooksecurefunc(EUI, "OnProfileRenamed",     OnProfileRenamed)   end
    if EUI.OnProfileDeleted     then hooksecurefunc(EUI, "OnProfileDeleted",     OnProfileDeleted)   end

    -- One re-apply at login. Without it the only repair triggers are a profile
    -- switch, a spec switch and a profile apply, so a player who re-enables an
    -- EllesmereUI module that a switch was holding down would wait indefinitely
    -- with the forced value stuck and the switch reading off. The record-once
    -- guard makes this idempotent, and the debounce sequences it after
    -- EllesmereUI's own login work.
    ns.EUIQueueReapply()

    RegisterModule({
        title       = "KitnUI",
        description = "Profile installer for the EllesmereUI suite.",
        pages       = ns.EUIPageOrder,
        -- pcall'd: a page that errors must cost that page, not the whole panel.
        buildPage   = function(pageName, parent, yOffset)
            local builder = ns.EUIPages[pageName]
            if not builder then return math.abs(yOffset) end
            local ok, height = pcall(builder, parent, yOffset)
            if not ok or type(height) ~= "number" then return math.abs(yOffset) end
            return height
        end,
    })
end)

---------------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------------

KitnCommands = KitnCommands or {}
KitnCommands["options"] = function()
    if _G.EllesmereUI and EllesmereUI.ShowModule then
        EllesmereUI:ShowModule(ns.EUI_MODULE_KEY)
    else
        print(ns.title .. ": EllesmereUI's config panel is unavailable.")
    end
end
KitnCommands["config"] = KitnCommands["options"]

---------------------------------------------------------------------------------
-- Reverse bridge
---------------------------------------------------------------------------------

-- KitnUI proper calls these five: EUIResetAll from Installer/Core.lua's reset,
-- ApplyLook and LuluLayoutName from Setup.lua's profile writes, LuluEnabled and
-- LuluApplyActionBars from Setup.lua's EllesmereUI module pass. Every call site
-- nil-guards, so a symbol missing here fails SILENTLY — which is exactly what
-- happened to LuluApplyActionBars when it was added to Lulu.lua and not to this
-- list, and the installer's action bars step quietly did nothing for a commit.
-- Naming them in one list is what is supposed to stop that. Keep this list and
-- the table in the spec in step.
--
-- The read-through metatable above is one-way: KitnUI_EUI reads KitnUI's
-- namespace, but anything this addon defines stays in this addon's table until
-- it is copied back here.
local EXPORTS = { "EUIResetAll", "ApplyLook", "LuluEnabled", "LuluLayoutName", "LuluApplyActionBars" }

-- Its own frame, deliberately. Core's main boot handler returns early when
-- EllesmereUI is too old to have RegisterModule or Widgets, and none of these
-- needs EllesmereUI: the reapply registry they depend on is populated at
-- file scope. Publishing behind that guard would leave /kitn reset with no
-- teardown on exactly the configuration where forced values from a previous
-- session are still held down. Gameplay.lua's tooltip hook uses its own frame
-- for the same reason and says so.
--
-- Login rather than file scope because all but EUIResetAll live in General.lua
-- and Lulu.lua, which EUITab.xml loads AFTER this file. Copy by value is safe:
-- none of them is ever reassigned after definition.
local exportBoot = CreateFrame("Frame")
exportBoot:RegisterEvent("PLAYER_LOGIN")
exportBoot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if type(core) ~= "table" then return end
    for _, k in ipairs(EXPORTS) do
        core[k] = ns[k]
    end
end)
