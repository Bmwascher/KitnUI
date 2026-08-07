-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab/Core.lua                                             ║
-- ║  Purpose: Inject a KitnUI category into EllesmereUI's config ║
-- ║           panel and provide the machinery its pages share.   ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

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

-- KitnUI's switch states live in KitnUI's own SavedVariable, filed under the
-- EllesmereUI profile they belong to.
--
-- They used to ride the EllesmereUI profile itself, through Lite.NewDB, which
-- landed them in EllesmereUIDB.profiles[name].addons.KitnUIEUI and made them
-- export, import and switch along with it for free. That store is not safe for
-- anyone but EllesmereUI. Its Spec Overrides engine snapshots and diffs EVERY
-- database in the Lite registry, ours included, banks each difference as a
-- per-spec override, and writes it back over the live table at login and on
-- every spec change. EllesmereUI's own modules survive that because a removal
-- marker self-heals against their registered defaults; a third party registers
-- none, so the marker stands and the switch reads off after every reload.
--
-- NaowhUI stores its settings there and pays the price: a hand-maintained list
-- of every key it holds down, a sync pass into EllesmereUI's override maps at
-- login, at each spec change and at logout, and a cleanup routine for the rows
-- left behind. That is a fair trade for a whole UI suite. It is not one for two
-- switches, and the hand-maintained list rots the moment a page is added.
--
-- What this costs: switch states no longer ride an exported profile. For a
-- profile installer that is close to free, because the installer runs again on
-- the other end. What it buys, beyond surviving a reload: the switch state and
-- the snapshot recording what that switch overrode now live in the same file,
-- so the two halves can no longer go out of step.
local settingsFallback

function ns.EUISettings()
    local root = ns.db
    -- ns.db is filled by Installer/Core.lua at PLAYER_LOGIN, which registers its
    -- handler first and so runs first. Anything reaching here earlier still has
    -- to render: session-only storage beats erroring. Latched, because swapping
    -- the real store in mid-session would orphan every switch flipped before it.
    if not root or settingsFallback then
        settingsFallback = settingsFallback or {}
        return settingsFallback
    end

    root.euiSettings = root.euiSettings or {}
    local profile = ActiveProfileName()
    root.euiSettings[profile] = root.euiSettings[profile] or {}
    return root.euiSettings[profile]
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

-- Both halves are keyed by profile name, so a rename orphans them and whatever
-- KitnUI forced into that profile becomes unrestorable. They move together or
-- not at all: a switch state without its snapshot cannot put the original back,
-- and a snapshot without its switch state is a value nothing admits to holding.
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

    local settings = ns.db and ns.db.euiSettings
    if settings then
        if settings[oldName] and not settings[newName] then
            settings[newName] = settings[oldName]
        end
        settings[oldName] = nil
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
-- old one's records and restores values it never had.
local function OnProfileDeleted(name)
    if type(name) ~= "string" then return end

    local snap = ns.db and ns.db.euiSnap
    if snap then
        for _, section in pairs(snap) do
            section[name] = nil
        end
    end

    local settings = ns.db and ns.db.euiSettings
    if settings then settings[name] = nil end

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
