-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab/Core.lua                                             ║
-- ║  Purpose: Inject a KitnUI category into EllesmereUI's config ║
-- ║           panel and provide the machinery its pages share.   ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- Read-through to KitnUI's namespace. Resolution happens per read, so symbols
-- KitnUI fills late (ns.db is not populated until PLAYER_LOGIN) resolve the
-- moment they exist rather than at load. Writes stay local by design: anything
-- this addon defines is its own. The trap that implies is that assigning a name
-- KitnUI also owns would shadow it silently for this addon only.
local core = _G.KitnUI_Shared
if core then setmetatable(ns, { __index = core }) end

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
        -- General. A table with one leaf, and the LEAF carries the default: the
        -- 0a4835e failure was `accent = {}` surviving with the leaf nilled, so a
        -- default of an empty table would fix nothing.
        accent                  = { pink = false },
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

-- Both halves of KitnUI's state now live in KitnUIDB: the switch states and the
-- snapshots recording what those switches overrode. The caller nils KitnUIDB, so
-- they die together and can no longer be destroyed out of step. What still has
-- to be handled is the OTHER side: EllesmereUI is left holding whatever KitnUI
-- forced into it, and once the snapshots are gone nothing remembers the
-- originals. So the reset turns every switch off FIRST and lets each page's own
-- re-apply put the originals back while the snapshots are still there.
--
-- Two things this has to cover beyond the active profile:
--   * Lulu Mode's module disable and Edit Mode layout are not in the re-apply
--     registry, because reversing them needs a reload. Reset reloads anyway.
--   * Switch states in OTHER EllesmereUI profiles cannot be restored from here
--     without switching to each profile in turn. Nilling KitnUIDB drops them
--     with their snapshots, which leaves the forced value in place with nothing
--     claiming it and nothing left to mis-record. That is the honest trade.
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

    if ns.LuluTearDown then pcall(ns.LuluTearDown) end

    local settings = ns.EUISettings()
    for key in pairs(settings) do
        settings[key] = nil
    end

    for _, fn in ipairs(reapplyFns) do
        pcall(fn)
    end

    -- Every other profile's switch block, dropped whole. The caller nils
    -- KitnUIDB immediately after, so this is belt and braces rather than the
    -- only clearance, and it keeps EUIResetAll correct on its own terms.
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
        ok = trampoline and pcall(trampoline) or false
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

---------------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------------

-- Switch states used to live in EllesmereUIDB.profiles[name].addons.KitnUIEUI.
-- Nothing writes there any more, so without this sweep every profile keeps a
-- stale block forever and carries it into every export the user shares.
--
-- The values are moved rather than dropped. They are unreliable, which is why
-- this store was abandoned, but Lulu Mode's flag is the one that matters:
-- disabling the action bars module and swapping the Edit Mode layout both
-- outlive a reload on their own, so losing the flag would leave Lulu applied
-- with the switch reading off and no way to reverse it from the page.
--
-- Idempotent by construction: the blocks are gone after the first pass, and an
-- entry already in the new store is never overwritten because it is the newer
-- of the two.
local function MigrateLegacySettings()
    local profiles = _G.EllesmereUIDB and EllesmereUIDB.profiles
    if type(profiles) ~= "table" or not ns.db then return end

    ns.db.euiSettings = ns.db.euiSettings or {}
    for name, profile in pairs(profiles) do
        if type(profile) == "table" and type(profile.addons) == "table" then
            local old = profile.addons.KitnUIEUI
            if type(old) == "table" then
                if next(old) and ns.db.euiSettings[name] == nil then
                    ns.db.euiSettings[name] = CopyTable(old)
                end
                profile.addons.KitnUIEUI = nil
            end
        end
    end
end

-- PLAYER_LOGIN, matching every EllesmereUI options file: page builders read
-- ns.db, which Installer/Core.lua only fills at login.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not (_G.EllesmereUI and EllesmereUI.RegisterModule and EllesmereUI.Widgets) then return end

    -- Before anything reads a switch state. ns.db is filled by Installer/Core.lua,
    -- which registers its PLAYER_LOGIN handler first and so has already run.
    MigrateLegacySettings()

    InjectSidebar()

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

-- KitnUI proper calls these four: Installer/Core.lua:296 (EUIResetAll),
-- Setup.lua:134 (ApplyLook), Setup.lua:279-281 and :622 (LuluEnabled,
-- LuluLayoutName). All four call sites nil-guard, so a symbol missing here
-- fails SILENTLY. Naming them in one list is what stops that happening by
-- accident. Keep this list and the table in the spec in step.
local EXPORTS = { "EUIResetAll", "ApplyLook", "LuluEnabled", "LuluLayoutName" }

-- Its own frame, deliberately. Core's main boot handler returns early when
-- EllesmereUI is too old to have RegisterModule or Widgets, and none of these
-- four needs EllesmereUI: the reapply registry they depend on is populated at
-- file scope. Publishing behind that guard would leave /kitn reset with no
-- teardown on exactly the configuration where forced values from a previous
-- session are still held down. Gameplay.lua's tooltip hook uses its own frame
-- for the same reason and says so.
--
-- Login rather than file scope because ApplyLook, LuluEnabled and LuluLayoutName
-- live in General.lua and Lulu.lua, which EUITab.xml loads AFTER this file.
-- Copy by value is safe: none of the four is ever reassigned after definition.
local exportBoot = CreateFrame("Frame")
exportBoot:RegisterEvent("PLAYER_LOGIN")
exportBoot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if type(core) ~= "table" then return end
    for _, k in ipairs(EXPORTS) do
        core[k] = ns[k]
    end
end)
