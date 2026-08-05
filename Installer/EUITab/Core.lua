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
ns.EUIPageOrder = { "General", "Top Bar" }

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

-- KitnUI's own switch states live inside the EllesmereUI profile, so they
-- export, import and switch along with it for free.
--
-- The saved-variable name must NOT be "KitnUIDB". NewDB wipes _G[svName] in
-- place, and KitnUIDB is the installer's real SavedVariable declared in the
-- TOC, so passing it would destroy the installer's state. "KitnUIEUIDB" yields
-- the folder key "KitnUIEUI", which does not match KitnUI's addon folder. That
-- is harmless: the key is only ever a table key, and the sidebar keys off
-- ns.EUI_MODULE_KEY instead.
local settingsDB
local settingsFallback

function ns.EUISettings()
    if settingsDB and settingsDB.profile then return settingsDB.profile end

    local L = _G.EllesmereUI and EllesmereUI.Lite
    if L and L.NewDB and not settingsFallback then
        local ok, db = pcall(L.NewDB, "KitnUIEUIDB", { profile = {} })
        if ok and db and db.profile then
            settingsDB = db
            return db.profile
        end
    end

    -- A tab that cannot store settings must still render. In-memory means the
    -- switches work for the session and forget on logout, which beats erroring.
    settingsFallback = settingsFallback or {}
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

-- Keyed by profile because a value from one profile says nothing about another.
local function ActiveProfileName()
    if _G.EllesmereUI and EllesmereUI.GetActiveProfileName then
        local ok, name = pcall(EllesmereUI.GetActiveProfileName)
        if ok and type(name) == "string" then return name end
    end
    return (_G.EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
end

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

-- PLAYER_LOGIN, matching every EllesmereUI options file: page builders read
-- ns.db, which Installer/Core.lua only fills at login.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not (_G.EllesmereUI and EllesmereUI.RegisterModule and EllesmereUI.Widgets) then return end

    InjectSidebar()

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
