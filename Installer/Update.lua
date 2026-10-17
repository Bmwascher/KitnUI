-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Update.lua                                                  ║
-- ║  Purpose: The EllesmereUI profile update: page state, the    ║
-- ║           two async decodes, the capture-merge-confirm       ║
-- ║           click, the apply with its two rollbacks, and       ║
-- ║           Restore previous. Everything that talks to         ║
-- ║           EllesmereUI lives here; the merge itself does not. ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

local NAME = ns.profileName
local BACKUP = ns.EUIBackupName
local RESOURCE_BARS = "EllesmereUIResourceBars"

local function isTable(v) return type(v) == "table" end
local function E() return _G.EllesmereUI end
local function DB() return _G.EllesmereUIDB end

-- Every sentence the flow shows. The design's sentences are reproduced
-- verbatim; the rest are this file's.
ns.EUI_UPDATE_TEXT = {
    promise = "Your changes are kept and KitnUI's come in. Where you both changed the same thing, ",
    promiseKey = "KitnUI's version is used",
    replacedTail = " of your changes are replaced because KitnUI changed the same things.",
    replacedTailOne = " of your changes is replaced because KitnUI changed the same things.",
    replacedNone = "None of your changes are replaced.",
    noBase = "KitnUI has no record of the profile you installed, so the parts you tick ",
    noBaseKey = "replace yours",
    backupReplaced = "Your previous backup will be replaced.",
    overridesKept = "Your Spec Overrides are kept.",
    overridesTaken = "KitnUI's Spec Overrides replace yours. KitnUI's saved layouts may also replace bar and element positions, sizes and links you changed.",
    links = "Links from updated bars to modules KitnUI disables, to modules with no Unlock Mode checkbox, or that EllesmereUI cannot identify will be removed. These are not included in the count.",
    health = "Your custom health bar color will be reset to the class color. This is not included in the count.",
    moved = "Your profile keybind and sync-group membership move to the backup. Restore previous brings them back.",
    combat = "Cannot update in combat",
    notActive = "Switch to your KitnUI profile to update it.",
    unlock = "Save or exit Unlock Mode before updating.",
    unlockRestore = "Save or exit Unlock Mode before restoring.",
    establish = "Try again in a moment.",
    readFail = "Could not read your current profile.",
    preparing = "Preparing...",
    importFail = "EllesmereUI import failed",
    switchFail = "Could not switch to the backup.",
    switchFailUpdate = "Could not switch to the updated profile.",
    reloadScale = "Type " .. ns.Color("/reload") .. " to put your UI scale back.",
    tailRestore = "Restore previous puts your previous profile back.",
    renameFail = "Could not back up your profile.",
    sync = "Your active profile and the backup share a sync group. Remove one of them from the group first.",
    notRestorable = "Switch to your KitnUI profile first",
    needsNewer = "Update needs a newer EllesmereUI.",
    updated = "Profile updated.",
    updatedReplaced = "Profile updated. %d of your changes were replaced.",
    updatedReplacedOne = "Profile updated. 1 of your changes was replaced.",
}
local T = ns.EUI_UPDATE_TEXT

-- The per-part view's sentences.
T.noneTicked = "Tick at least one part first."
T.rowReplaced = "%d of yours replaced"
T.rowNone = "none of yours"
T.rowReplaces = "replaces yours"
T.skipped = "Skipped: %s -- take them any time from " .. ns.Color("/kitn install") .. ", EllesmereUI > Modules."
T.movedScratch = "Your profile keybind and sync-group membership are removed; set them again in EllesmereUI."
T.scratchFail = "Could not move your profile aside for the update. Nothing was imported."
T.resetTitle = "Reset %s?"
T.resetBody = "%s goes back to KitnUI's version."
T.resetYours = "Your %d changes to %s will be replaced."
T.resetYoursOne = "Your 1 change to %s will be replaced."
T.resetNone = "You have no changes to %s."
T.resetOthers = "Your other parts are not touched."
T.resetCaptured = "Your Spec Overrides also hold settings for %s; they apply again when you change spec."
-- Formatted with the child, the target, the target and the child: T.split for
-- a pair with an anchor link, T.splitSize for one linked only by a size match.
T.split = "%s is anchored to %s. You're keeping your own %s, so %s may not line up."
T.splitSize = "%s is sized to match %s. You're keeping your own %s, so %s may not line up."
T.splitMore = " (+%d more)"
T.restoreNow = "Restore previous puts back your profile as it is now."
T.restoreEarlier = "Restore previous puts back the backup taken earlier in this visit, undoing every change since then."
T.resetDone = "%s reset to KitnUI's version."

---------------------------------------------------------------------------------
-- Base seeding and page state
---------------------------------------------------------------------------------

-- An account that installed the string shipping now has its base for free.
function ns.EUISeedBase()
    if not ns.db or ns.db.euiBase ~= nil then return end
    local stamp = ns.db.addonVersions and ns.db.addonVersions.EllesmereUI
    local shipped = ns.GetAddonDataVersion("EllesmereUI")
    if stamp and shipped and stamp == shipped and type(ns.data.EllesmereUI) == "string" then
        ns.db.euiBase = ns.data.EllesmereUI
    end
end

local REQUIRED = {
    "DecodeImportStringAsync", "DecodeImportString", "ExportProfile", "RenameProfile",
    "DeleteProfile", "ImportProfile", "BuildImportKeyToFolder", "FilterLayoutToFolders",
    "SetProfile",
}

-- EllesmereUI has no setter for a spec's profile, so write its table. Looked up
-- each time: EllesmereUI's options replace the table whole.
local function assignSpec(spec)
    local d = DB()
    if not isTable(d) then return end
    if not isTable(d.specProfiles) then d.specProfiles = {} end
    d.specProfiles[spec] = NAME
end

local function hasRequired(e)
    if not e or not isTable(e._ADDON_DB_MAP) then return false end
    for _, fn in ipairs(REQUIRED) do
        if type(e[fn]) ~= "function" then return false end
    end
    return true
end

-- "none" | "current" | "update" | "stale", plus the one line saying why a
-- stale profile cannot be updated.
function ns.EUIUpdateState()
    if not (ns.db and ns.db.profiles and ns.db.profiles.EllesmereUI) then return "none" end
    local stamp = ns.db.addonVersions and ns.db.addonVersions.EllesmereUI
    local shipped = ns.GetAddonDataVersion("EllesmereUI")
    if not (stamp and shipped and stamp ~= shipped) then return "current" end
    local e, d = E(), DB()
    local profiles = isTable(d) and d.profiles
    if not (isTable(profiles) and profiles[NAME]) then
        return "stale", "Your KitnUI profile is gone. Reset installs it again."
    end
    if d.activeProfile ~= NAME then return "stale", T.notActive end
    if not hasRequired(e) then return "stale", T.needsNewer end
    return "update"
end

-- Whether the part list can be drawn: the functions and the map its inputs
-- need. EUIUpdateState answers "current" before it checks them, and the
-- standard page it serves needs none of them, so the list asks here instead.
function ns.EUIListReady()
    return hasRequired(E())
end

-- "restore" when the backup can be put back from here, "switch" when the
-- player must be on their KitnUI profile first, nil when there is no backup.
function ns.EUIRestorable()
    local d = DB()
    local profiles = isTable(d) and d.profiles
    if not (isTable(profiles) and profiles[BACKUP] and ns.db and isTable(ns.db.euiBackup)) then return nil end
    if profiles[NAME] == nil or d.activeProfile == NAME then return "restore" end
    return "switch"
end

---------------------------------------------------------------------------------
-- The two decodes
---------------------------------------------------------------------------------

local cache = { gen = 0, byVersion = {}, bySettled = {} }
ns.EUIDecodeCache = cache

function ns.EUICancelDecodes()
    cache.gen = cache.gen + 1
    for _, slot in ipairs({ "handleO", "handleV", "handleN" }) do
        local handle = cache[slot]
        if handle and handle.Cancel then handle:Cancel() end
        cache[slot] = nil
    end
    -- The decoder keeps the callback of a run it no longer drives; emptied,
    -- its box reaches nothing of the chain.
    if cache.box then cache.box.land = nil end
    cache.box = nil
    cache.O, cache.N = nil, nil
    cache.byVersion, cache.bySettled = {}, {}
    cache.failedO, cache.failedN = false, false
    cache.running = false
end

local function decoded(payload)
    return isTable(payload) and isTable(payload.data) and payload or nil
end

-- The stamp's base, then each older base a part stands at, then the shipped
-- string, one after another into this cache. A string already decoded is
-- reused rather than decoded again; a stale generation drops its result.
-- onReady runs once, at the end. EllesmereUI's decoder keeps its last callback
-- after the run ends, so the callback reaches the chain only through a box
-- that its landing and a cancel empty.
function ns.EUIStartDecodes(onReady)
    ns.EUICancelDecodes()
    local e = E()
    if not (e and e.DecodeImportStringAsync) then return false end
    local gen = cache.gen
    cache.running = true

    local steps = {}
    local base = ns.db and ns.db.euiBase
    if type(base) == "string" then
        steps[#steps + 1] = { s = base, slot = "handleO", take = function(p)
            cache.O = p
            cache.failedO = p == nil
        end }
    else
        cache.failedO = true
    end
    local bases = ns.db and ns.db.euiBases
    if isTable(bases) then
        -- Saved data can hold any key, and a number beside the version strings
        -- would make the sort raise on every page draw.
        local versions = {}
        for v, s in pairs(bases) do
            if type(v) == "string" and type(s) == "string" then versions[#versions + 1] = v end
        end
        table.sort(versions)
        for _, v in ipairs(versions) do
            steps[#steps + 1] = { s = bases[v], slot = "handleV", take = function(p) cache.byVersion[v] = p end }
        end
    end
    local settled = ns.EUIListReadsSettled and ns.EUIListReadsSettled() and ns.db and ns.db.euiSettled
    if isTable(settled) then
        local ids = {}
        for id, entry in pairs(settled) do
            if type(id) == "number" and isTable(entry) and type(entry.s) == "string" then ids[#ids + 1] = id end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            steps[#steps + 1] = { s = settled[id].s, slot = "handleV", take = function(p) cache.bySettled[id] = p or false end }
        end
    end
    steps[#steps + 1] = { s = ns.data.EllesmereUI, slot = "handleN", take = function(p)
        cache.N = p
        cache.failedN = p == nil
    end }

    local results, i = {}, 0
    local function nextStep()
        while true do
            i = i + 1
            local step = steps[i]
            if not step then
                cache.running = false
                if onReady then onReady() end
                return
            end
            if type(step.s) ~= "string" then
                step.take(nil)
            elseif results[step.s] ~= nil then
                step.take(results[step.s] or nil)
            else
                local box = { land = function(payload)
                    local p = decoded(payload)
                    results[step.s] = p or false
                    cache[step.slot] = nil
                    step.take(p)
                    nextStep()
                end }
                cache.box = box
                local handle = e.DecodeImportStringAsync(step.s, function(payload)
                    local land = box.land
                    if cache.gen ~= gen or not land then return end
                    box.land = nil
                    land(payload)
                end)
                if handle and cache.gen == gen and results[step.s] == nil then cache[step.slot] = handle end
                return
            end
        end
    end
    nextStep()
    return true
end

function ns.EUIDecodesReady()
    return not cache.running and (cache.N ~= nil or cache.failedN)
end

---------------------------------------------------------------------------------
-- The click: capture, merge, describe
---------------------------------------------------------------------------------

function ns.EUICurrentSpecID()
    local info = C_SpecializationInfo
    local index = info and info.GetSpecialization and info.GetSpecialization()
    if type(index) ~= "number" or index <= 0 or not info.GetSpecializationInfo then return nil end
    return info.GetSpecializationInfo(index)
end

local function assignedSpecs()
    local d = DB()
    local out = {}
    if isTable(d) and isTable(d.specProfiles) then
        for specID, name in pairs(d.specProfiles) do
            if name == NAME then out[#out + 1] = specID end
        end
        table.sort(out)
    end
    return out
end


local function healthResets(lock)
    local e = E()
    return not lock and e and e.IsModuleAddonLoaded and e.IsModuleAddonLoaded(RESOURCE_BARS) == true
end

-- The three refusals every click and every acceptance repeats.
local function refusal()
    if InCombatLockdown() then return T.combat end
    local d = DB()
    if not (isTable(d) and d.activeProfile == NAME) then return T.notActive end
    local e = E()
    if e and e._unlockModeActive then return T.unlock end
    return nil
end

-- Harvest and export the player's profile. The export's side effect, the
-- stored profile freshened from live, is what makes the later rename carry a
-- complete backup; the string is what the caller decodes, or discards.
function ns.EUIBankCurrent()
    local e = E()
    if not e then return nil, T.readFail end
    if e.Conditions_EstablishPending and e.Conditions_EstablishPending() then return nil, T.establish end
    if e.SpecOverrides_HarvestCurrent then e.SpecOverrides_HarvestCurrent() end
    local s = e.ExportProfile(NAME)
    if type(s) ~= "string" then return nil, T.readFail end
    return s
end

function ns.EUICaptureP()
    local s, err = ns.EUIBankCurrent()
    if not s then return nil, err end
    local payload = decoded(E().DecodeImportString(s))
    if not payload then return nil, T.readFail end
    return payload
end

---------------------------------------------------------------------------------
-- The settled snapshot
---------------------------------------------------------------------------------

-- Seconds after the loading screen before the profile counts as settled.
-- EllesmereUI's own settle passes end within about two seconds of it.
local EUI_SETTLE_DELAY = 10
ns.EUI_SETTLE_DELAY = EUI_SETTLE_DELAY

local function settleBefore()
    local db = ns.db or {}
    return { settled = db.euiSettled, at = db.euiSettledAt, pending = db.euiSettlePending, due = ns.euiSettleDue }
end

local function writeSettle(settled, at, pending, due)
    ns.db.euiSettled, ns.db.euiSettledAt, ns.db.euiSettlePending = settled, at, pending
    ns.euiSettleDue = due
end

-- True while a change from an earlier session waits for its snapshot.
local function settleDue()
    return isTable(ns.euiSettleDue) and next(ns.euiSettleDue) ~= nil
end

-- The click's refusals, and a profile EllesmereUI is still establishing,
-- whose export would not be the settled one.
local function settleRefusal()
    local why = refusal()
    if why then return why end
    local e, d = E(), DB()
    if e and e.Conditions_EstablishPending and e.Conditions_EstablishPending() then return T.establish end
    local stored = isTable(d.profiles) and d.profiles[NAME]
    if isTable(stored) and stored._importEstablishPending then return T.establish end
    return nil
end

-- Records `s`, an export of the KitnUI profile, as the snapshot of every part
-- due one, with what KitnUI's switches hold now.
local function recordSettled(s)
    local id = 1
    for k in pairs(isTable(ns.db.euiSettled) and ns.db.euiSettled or {}) do
        if type(k) == "number" and k >= id then id = math.floor(k) + 1 end
    end
    local held = ns.EUIHeldPaths and ns.EUIHeldPaths({ NAME, BACKUP }) or {}
    writeSettle(ns.EUISettleRecord("capture", settleBefore(), { id = id, entry = { s = s, held = held } }))
end

-- The only writer of a snapshot: a read or a click never records one, as it
-- would take in every edit up to that moment. Returns true when nothing is
-- left due, or false and the refusal.
function ns.EUISettleCapture()
    if not (ns.db and settleDue()) then return true end
    local e = E()
    if not hasRequired(e) then return false, T.needsNewer end
    local why = settleRefusal()
    if why then return false, why end
    -- The export's harvest would end a Spec Overrides edit the player has
    -- open, so the options panel waits like any refusal that is not combat.
    local panel = e._mainFrame
    if (isTable(panel) and panel.IsShown and panel:IsShown())
        or (e.SpecOverrides_EditSessionActive and e.SpecOverrides_EditSessionActive()) then
        return false, T.establish
    end
    local t0 = ns.db.devMode and debugprofilestop()
    local s, err = ns.EUIBankCurrent()
    if not s then return false, err end
    recordSettled(s)
    if t0 then
        print(ns.title .. (" settled snapshot: %.1f ms"):format(debugprofilestop() - t0))
    end
    if ns.EUISettleLanded then ns.EUISettleLanded() end
    return true
end

-- A part's state for the list: "settled", "due", "pending" or nil.
function ns.EUIPartSettle(part)
    local before = settleBefore()
    return ns.EUISettleState(before, before.due, part)
end

local settleFrame
local settleGen = 0
local settleLoading = false

-- A refusal waits for the next loading screen or end of combat, which the
-- frame listens for until the capture lands.
local function trySettle()
    ns.euiSettleOpen = true
    if ns.EUISettleCapture() then
        settleGen = settleGen + 1
        settleFrame:UnregisterAllEvents()
    end
end

-- The end of each loading screen, and each end of combat outside one, starts
-- the delay again, and only the latest timer runs: the profile's own work after
-- either has settled by the time it fires.
local function startDelay()
    settleGen = settleGen + 1
    local gen = settleGen
    C_Timer.After(EUI_SETTLE_DELAY, function()
        if gen == settleGen then trySettle() end
    end)
end

-- The start of a loading screen cancels a running delay, and nothing starts one
-- until its end: a timer from an end of combat during it could run out before
-- the screen does, and the screen's end starts a whole delay anyway.
local function onSettleEvent(_, event)
    if event == "LOADING_SCREEN_ENABLED" then
        settleLoading = true
        settleGen = settleGen + 1
    elseif event == "PLAYER_ENTERING_WORLD" then
        settleLoading = false
        startDelay()
    elseif not settleLoading then
        startDelay()
    end
end

-- The boot's call at PLAYER_LOGIN. What is pending now changed in an earlier
-- session, so it is due; with nothing due, nothing is created.
function ns.EUIArmSettle()
    ns.euiSettleOpen = false
    settleLoading = false
    local due = {}
    local pending = ns.db and ns.db.euiSettlePending
    for part, v in pairs(isTable(pending) and pending or {}) do
        if type(part) == "string" and v == true then due[part] = true end
    end
    ns.euiSettleDue = due
    if next(due) == nil then return end
    settleFrame = CreateFrame("Frame")
    settleFrame:SetScript("OnEvent", onSettleEvent)
    settleFrame:RegisterEvent("LOADING_SCREEN_ENABLED")
    settleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    settleFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end


local function movesToBackup()
    local d = DB()
    if not isTable(d) then return false end
    if isTable(d.profileKeybinds) and d.profileKeybinds[NAME] then return true end
    if isTable(d.syncedModules) then
        for _, targets in pairs(d.syncedModules) do
            if isTable(targets) and targets[NAME] then return true end
        end
    end
    return false
end

-- Every change after the visit's first keeps the visit's backup and swaps
-- through a scratch profile instead (see EUIApplyUpdate).
local function scratchPath()
    local d = DB()
    local profiles = isTable(d) and d.profiles
    return ns.euiVisitBacked == true and isTable(profiles) and profiles[BACKUP] ~= nil
        and ns.db ~= nil and isTable(ns.db.euiBackup)
end

-- The importer's activation gate as it will see the assignments. The first
-- change deletes the old backup, clearing its assignments; the scratch path
-- keeps it.
local function predictLock(scratch)
    local d = DB()
    local profiles = isTable(d) and d.profiles
    local backupGoes = not scratch and isTable(profiles) and profiles[BACKUP] ~= nil
    return ns.EUIWillLock(ns.EUICurrentSpecID(), isTable(d) and d.specProfiles, backupGoes)
end

-- What the list and the merge share: KitnUI's string and every recorded base,
-- folder-stripped, the rows, the composite base and the key resolver. Pd, the
-- player's capture when there is one, is stripped in place. With `settled`,
-- the Modules read's alone, comes the settled composite S. Nil until the
-- decodes land.
local function sideInputs(Pd, settled)
    local e = E()
    if not (hasRequired(e) and cache.N and isTable(cache.N.data)) then return nil end
    local keep, strip, stripCDM = ns.EUIStripSets(e._ADDON_DB_MAP, ns.GetEUIModuleSet())
    -- An unreadable map entry partitions nothing, and the final filter drops
    -- every link of a folder the keep set lacks. When any entry fails, or none
    -- names a folder, the payload's unnamed folders are partitioned here; the
    -- Top Bar's folder stays out, as it is out of every map.
    local partial = next(keep) == nil and next(strip) == nil
    for _, entry in ipairs(isTable(e._ADDON_DB_MAP) and e._ADDON_DB_MAP or {}) do
        if not (isTable(entry) and type(entry.folder) == "string") then partial = true end
    end
    if partial then
        local disabled = {}
        for _, folder in ipairs(ns.GetEUIModuleSet() or {}) do disabled[folder] = true end
        for folder in pairs(isTable(cache.N.data.addons) and cache.N.data.addons or {}) do
            if type(folder) == "string" and not (keep[folder] or strip[folder]) and folder ~= "KitnUI_EUI" then
                if disabled[folder] then strip[folder] = true else keep[folder] = true end
            end
        end
    end
    local Nd = ns.EUIDeepCopy(cache.N.data)
    ns.EUIStripFolders(Nd, strip, stripCDM)
    if Pd then ns.EUIStripFolders(Pd, strip, stripCDM) end

    local stamp = ns.db.addonVersions and ns.db.addonVersions.EllesmereUI
    local bases = {}
    local function addBase(version, payload)
        if version and isTable(payload) and isTable(payload.data) then
            local data = ns.EUIDeepCopy(payload.data)
            ns.EUIStripFolders(data, strip, stripCDM)
            bases[version] = data
        end
    end
    addBase(stamp, cache.O)
    for version, payload in pairs(cache.byVersion) do addBase(version, payload) end
    -- Each snapshot is stripped as the bases are. One the timed capture took
    -- after the decodes started is decoded here, and a failure is not retried.
    local settledData = {}
    if Pd and settled then
        for id, entry in pairs(isTable(ns.db.euiSettled) and ns.db.euiSettled or {}) do
            if type(id) == "number" and cache.bySettled[id] == nil and isTable(entry) and type(entry.s) == "string" then
                cache.bySettled[id] = decoded(e.DecodeImportString(entry.s)) or false
            end
        end
        for id, payload in pairs(cache.bySettled) do
            if isTable(payload) and isTable(payload.data) then
                local data = ns.EUIDeepCopy(payload.data)
                ns.EUIStripFolders(data, strip, stripCDM)
                settledData[id] = data
            end
        end
    end

    local metaK2F = ns.EUIOverlayMeta(cache.N.data.unlockLayoutMeta, Pd and Pd.unlockLayoutMeta)
    local sides = { Nd }
    if Pd then
        sides[#sides + 1] = Pd
        sides[#sides + 1] = ns.EUIOverrideElementSide(Pd)
    end
    for _, data in pairs(bases) do sides[#sides + 1] = data end
    for _, data in pairs(settledData) do sides[#sides + 1] = data end
    local keyToFolder = ns.EUILayoutKeyToFolder(sides, metaK2F, e.BuildImportKeyToFolder)
    local rows = ns.EUIRows(e._ADDON_DB_MAP, e.ADDON_ROSTER, cache.N.data.addons, ns.GetEUIModuleSet())
    local O, missing = ns.EUIComposeBase(rows, ns.db.euiRowAt, bases, stamp, keyToFolder)
    local S
    if Pd and settled then S = ns.EUIComposeSettled(O, rows, settleBefore(), settledData, keyToFolder, missing) end
    return {
        N = Nd, O = O, P = Pd, missing = missing, rows = rows, keep = keep,
        metaK2F = metaK2F, keyToFolder = keyToFolder, stamp = stamp, S = S,
    }
end

-- The player's profile captured now, supplemented, with the shared inputs.
-- Returns the inputs and the stored profile, or nil and a line. The Modules
-- read passes `settled`: while a change from an earlier session is due its
-- snapshot, it waits for the settle timer before exporting.
local function captureSide(settled)
    if settled and settleDue() and not ns.euiSettleOpen then return nil, T.establish end
    local P, err = ns.EUICaptureP()
    if not P then return nil, err end
    local stored = DB().profiles[NAME]
    ns.EUISupplementP(P.data, isTable(stored) and stored.addons)
    local side = sideInputs(P.data, settled)
    if not side then return nil, T.importFail end
    return side, stored
end

-- The list's counts: KitnUI's string against the composite base.
function ns.EUIPageInputs()
    return sideInputs(nil)
end

-- The "Your copy" read, under the same refusals as an update, measured from
-- each part's settled snapshot.
function ns.EUIReadPlayer()
    local why = refusal()
    if why then return nil, why end
    if not ns.EUIDecodesReady() then return nil, T.preparing end
    return captureSide(true)
end

-- The click's inputs, plus what the warnings read. Held on the plan so a
-- recount uses the profile the confirm described.
local function gatherInputs()
    local inputs, stored = captureSide()
    if not inputs then return nil, stored end
    local storedLayout = isTable(stored) and stored.unlockLayout or nil
    inputs.storedLayout = storedLayout
    inputs.storedK2F = E().BuildImportKeyToFolder(isTable(storedLayout) and storedLayout or {}, inputs.metaK2F) or {}
    return inputs
end

function ns.EUIUnlockLabels()
    local out = {}
    local e = E()
    local elems = e and e._unlockRegisteredElements
    if isTable(elems) then
        for key, elem in pairs(elems) do
            if isTable(elem) and type(elem.label) == "string" then out[key] = elem.label end
        end
    end
    return out
end

-- What the player's walk needs besides the inputs: the defaults EllesmereUI
-- registered per loaded module, the settings KitnUI's own switches hold, and
-- the Unlock Mode labels.
function ns.EUIPlayerContext()
    local e = E()
    local defaults = {}
    local reg = e and e.Lite and e.Lite._dbRegistry
    if isTable(reg) then
        for i = 1, #reg do
            local entry = reg[i]
            if isTable(entry) and type(entry.folder) == "string" and isTable(entry._profileDefaults) then
                defaults[entry.folder] = entry._profileDefaults
            end
        end
    end
    if ns.db and ns.db.devMode then
        local n = 0
        for _ in pairs(defaults) do n = n + 1 end
        print(ns.title .. " folders with defaults: " .. n)
    end
    local held = ns.EUIHeldPaths and ns.EUIHeldPaths({ NAME, BACKUP }) or {}
    return { defaults = defaults, held = held, unlock = ns.EUIUnlockLabels() }
end

-- The held set for "Your copy": `held` joined with what a switch held when
-- each snapshot was taken, KitnUI's in that snapshot. A Reset's context keeps
-- only what is held now.
function ns.EUISettledHeld(held)
    local out = {}
    for path in pairs(held or {}) do out[path] = true end
    for _, entry in pairs(isTable(ns.db and ns.db.euiSettled) and ns.db.euiSettled or {}) do
        for path in pairs(isTable(entry) and isTable(entry.held) and entry.held or {}) do
            if type(path) == "string" then out[path] = true end
        end
    end
    return out
end

-- The rows the update changes, counted the way the list counts them. Walked
-- whole: the click already merges the whole payload in the same frame.
local function changedRows(inputs)
    local walker = ns.EUIRowDiff(inputs.O, inputs.N, inputs.rows, inputs.keyToFolder, { missing = inputs.missing })
    walker:Step(math.huge)
    local changed = {}
    for _, row in ipairs(inputs.rows) do
        local entry = walker.result[row.id]
        if not row.off and entry and (entry.noBase or entry.count > 0) then changed[row.id] = true end
    end
    return changed
end

local function withWarnings(plan, removed)
    local inputs = plan.inputs
    local Pd = inputs.P
    local rb = Pd.addons and Pd.addons[RESOURCE_BARS]
    plan.warnLinks = ns.EUILinkWarning(plan.merged, inputs.storedLayout, Pd.unlockLayout, removed, inputs.storedK2F)
    plan.warnHealth = isTable(rb) and isTable(rb.health) and rb.health.customColored == true
        and healthResets(plan.willLock) or false
    plan.warnMoved = movesToBackup()
    plan.backupExists = DB().profiles[BACKUP] ~= nil
    return plan
end

-- The merge over one set of inputs under one activation prediction, with every
-- row outside `ticked` put back to the player's copy.
local function buildPlan(inputs, lock, ticked, scratch, kind, changed)
    local merged, report = ns.EUIThreeWayMerge(inputs.O, inputs.N, inputs.P, {
        keyToFolder = inputs.keyToFolder,
        healthReset = healthResets(lock),
    })
    ns.EUIKeepSlices(merged, report, inputs.P, inputs.rows, ticked, inputs.keyToFolder)
    local removed = ns.EUIFinalLayoutFilter(merged, report, inputs.metaK2F, inputs.keep, E())
    if not removed then return nil, T.readFail end
    if ns.db and ns.db.devMode then
        for _, path in ipairs(report.conflicts) do print(ns.title .. " conflict: " .. path) end
        for key in pairs(removed) do print(ns.title .. " removed: " .. key) end
    end
    return withWarnings({
        kind = kind,
        inputs = inputs,
        merged = merged,
        report = report,
        ticked = ticked,
        changed = changed,
        byRow = ns.EUIByRow(report.conflicts, ticked, inputs.keyToFolder),
        willLock = lock,
        scratch = scratch,
        noBase = report.noBase,
        build = function(l, s) return buildPlan(inputs, l, ticked, s, kind, changed) end,
    }, removed)
end

-- One row back to KitnUI's version, everything else as the player has it.
local function buildResetPlan(inputs, lock, row, context, scratch)
    local P = inputs.P
    -- The player's profile merged against itself: the same sanitising an update
    -- applies (transport keys, the layout's shape, the scale rule), with nothing
    -- of KitnUI's in it until the row is taken.
    local merged, report = ns.EUIThreeWayMerge(P, P, P, {
        keyToFolder = inputs.keyToFolder,
        healthReset = healthResets(lock),
    })
    ns.EUITakeSlice(merged, inputs.N, row, inputs.keyToFolder)
    if row.id == "overrides" then
        report.overrideSet = next(ns.EUIMaskedOverrideSet(inputs.N)) and "kitn" or "none"
    end
    local removed = ns.EUIFinalLayoutFilter(merged, report, inputs.metaK2F, inputs.keep, E())
    if not removed then return nil, T.readFail end

    local base = (inputs.O == nil or inputs.missing[row.id]) and inputs.N or inputs.O
    -- The player's changes to the row that the reset alters: one already equal
    -- to KitnUI's value stays as it is, so it is not "replaced".
    local walker = ns.EUIRowDiff(base, P, { row }, inputs.keyToFolder, {
        player = true, held = context.held, defaults = context.defaults, unlock = context.unlock,
        against = inputs.N,
    })
    walker:Step(math.huge)
    local entry = walker.result[row.id]
    return withWarnings({
        kind = "reset",
        row = row,
        inputs = inputs,
        merged = merged,
        report = report,
        ticked = { [row.id] = true },
        changed = { [row.id] = true },
        byRow = {},
        yours = entry and entry.count or 0,
        captured = ns.EUIOverridesCapture(P, row.id, inputs.keyToFolder),
        splits = ns.EUISplitLinks(inputs.N, inputs.rows, { [row.id] = true }, inputs.keyToFolder),
        willLock = lock,
        scratch = scratch,
        noBase = false,
        build = function(l, s) return buildResetPlan(inputs, l, row, context, s) end,
    }, removed)
end

-- The click. ticked: the rows to take, or nil for every row with a change.
-- Returns a plan the confirm describes and the acceptance applies, or nil and
-- a line.
function ns.EUIPrepareUpdate(ticked)
    local why = refusal()
    if why then return nil, why end
    -- A take cannot stamp what it installs without a shipped version, and its
    -- part would then read waiting again; an update always has one.
    if ns.GetAddonDataVersion("EllesmereUI") == nil then return nil, T.importFail end
    if ticked ~= nil and next(ticked) == nil then return nil, T.noneTicked end
    if not ns.EUIDecodesReady() then return nil, T.preparing end
    if cache.failedN then return nil, T.importFail end
    local inputs, err = gatherInputs()
    if not inputs then return nil, err end
    local changed = changedRows(inputs)
    local take = {}
    for id in pairs(changed) do
        if ticked == nil or ticked[id] then take[id] = true end
    end
    if ticked ~= nil and next(take) == nil then return nil, T.noneTicked end
    local kind = ns.EUIUpdateState() == "current" and "take" or "update"
    local scratch = scratchPath()
    return buildPlan(inputs, predictLock(scratch), take, scratch, kind, changed)
end

-- A Reset click. context: ns.EUIPlayerContext()'s result, reused from the page
-- when it has one.
function ns.EUIPrepareReset(rowId, context)
    local why = refusal()
    if why then return nil, why end
    -- The reset part is recorded at the shipped version; without one the list
    -- still shows (state "current"), but nothing may import.
    if ns.GetAddonDataVersion("EllesmereUI") == nil then return nil, T.importFail end
    if not ns.EUIDecodesReady() then return nil, T.preparing end
    if cache.failedN then return nil, T.importFail end
    local inputs, err = gatherInputs()
    if not inputs then return nil, err end
    local row
    for _, r in ipairs(inputs.rows) do
        if r.id == rowId and not r.off then row = r end
    end
    if not row then return nil, T.readFail end
    local scratch = scratchPath()
    return buildResetPlan(inputs, predictLock(scratch), row, context or ns.EUIPlayerContext(), scratch)
end

-- The confirms' colors, as WoW color codes. Every run of text carries its
-- own code and none nests, because a run's |r ends whatever color is open.
local C_BASE, C_PART, C_COUNT, C_QUIET = "cccccc", "ffffff", "E6B24C", "8c8c8c"

local function paint(color, text)
    return "|cff" .. color .. text .. "|r"
end

-- One string from groups of lines, a blank line between groups; an empty
-- group adds nothing.
local function joinGroups(groups)
    local out = {}
    for _, lines in ipairs(groups) do
        if #lines > 0 then out[#out + 1] = table.concat(lines, "\n") end
    end
    return table.concat(out, "\n\n")
end

-- The confirm's message: the lead, a line per ticked part, the total, then
-- the notes, warnings in amber.
function ns.EUIConfirmText(plan)
    local lead
    if plan.noBase then
        lead = paint(C_BASE, T.noBase) .. paint(C_PART, T.noBaseKey) .. paint(C_BASE, ".")
    else
        lead = paint(C_BASE, T.promise) .. paint(C_PART, T.promiseKey) .. paint(C_BASE, ".")
    end
    -- A part with no base of its own has no count of the player's changes:
    -- each setting KitnUI's string holds there replaces theirs, as the part's
    -- list cell says.
    local parts = {}
    local missing = plan.inputs.missing or {}
    for _, row in ipairs(plan.inputs.rows) do
        if plan.ticked[row.id] then
            local k = plan.byRow[row.id] or 0
            local tail
            if plan.noBase or missing[row.id] then
                tail = paint(C_COUNT, T.rowReplaces)
            elseif k > 0 then
                tail = paint(C_COUNT, T.rowReplaced:format(k))
            else
                tail = paint(C_QUIET, T.rowNone)
            end
            parts[#parts + 1] = paint(C_PART, row.label) .. paint(C_BASE, ": ") .. tail
        end
    end
    local total = {}
    if not plan.noBase then
        local n = #plan.report.conflicts
        if n == 0 then
            total[1] = paint(C_BASE, T.replacedNone)
        else
            total[1] = paint(C_COUNT, tostring(n)) .. paint(C_BASE, n == 1 and T.replacedTailOne or T.replacedTail)
        end
    end
    local notes = {}
    if plan.backupExists and not plan.scratch then notes[#notes + 1] = paint(C_COUNT, T.backupReplaced) end
    if plan.report.overrideSet == "kitn" then
        notes[#notes + 1] = paint(C_COUNT, T.overridesTaken)
    elseif plan.report.overrideSet == "player" then
        notes[#notes + 1] = paint(C_QUIET, T.overridesKept)
    end
    if plan.warnLinks then notes[#notes + 1] = paint(C_COUNT, T.links) end
    if plan.warnHealth then notes[#notes + 1] = paint(C_COUNT, T.health) end
    if plan.warnMoved then notes[#notes + 1] = paint(C_COUNT, plan.scratch and T.movedScratch or T.moved) end
    -- What Restore will put back, by the rule a reset follows below.
    notes[#notes + 1] = paint(C_QUIET, plan.scratch and T.restoreEarlier or T.restoreNow)
    return joinGroups({ { lead }, parts, total, notes })
end

function ns.EUIResetText(plan)
    local label = plan.row.label
    local yours
    if plan.yours == 1 then
        yours = paint(C_COUNT, T.resetYoursOne:format(label))
    elseif plan.yours > 1 then
        yours = paint(C_COUNT, T.resetYours:format(plan.yours, label))
    else
        yours = paint(C_BASE, T.resetNone:format(label))
    end
    local lead = paint(C_BASE, T.resetBody:format(label) .. " ") .. yours .. paint(C_BASE, " " .. T.resetOthers)
    local notes = {}
    if plan.captured then notes[#notes + 1] = paint(C_QUIET, T.resetCaptured:format(label)) end
    local first = plan.splits[1]
    if first then
        notes[#notes + 1] = paint(C_COUNT, (first.anchored and T.split or T.splitSize):format(first.child.label,
            first.target.label, first.target.label, first.child.label)
            .. (#plan.splits > 1 and T.splitMore:format(#plan.splits - 1) or ""))
    end
    if plan.row.id == "overrides" then notes[#notes + 1] = paint(C_COUNT, T.overridesTaken) end
    -- A reset imports the whole profile, so the final layout filter can remove
    -- a link in a part the reset leaves alone.
    if plan.warnLinks then notes[#notes + 1] = paint(C_COUNT, T.links) end
    if plan.warnHealth then notes[#notes + 1] = paint(C_COUNT, T.health) end
    if plan.backupExists and not plan.scratch then notes[#notes + 1] = paint(C_COUNT, T.backupReplaced) end
    if plan.warnMoved then notes[#notes + 1] = paint(C_COUNT, plan.scratch and T.movedScratch or T.moved) end
    -- What Restore will put back: the backup this reset takes, or the one an
    -- earlier change took. A full reset takes none, so a promise of the
    -- profile from before the visit would be false after one began it.
    notes[#notes + 1] = paint(C_QUIET, plan.scratch and T.restoreEarlier or T.restoreNow)
    return joinGroups({ { lead }, notes })
end

-- The rows an update leaves waiting: changed and not taken.
function ns.EUISkippedLabels(plan)
    local out = {}
    for _, row in ipairs(plan.inputs.rows) do
        if plan.changed[row.id] and not plan.ticked[row.id] then out[#out + 1] = row.label end
    end
    return out
end

-- The chat line after an update that left rows waiting, or nil.
function ns.EUISkippedNote(plan)
    if plan.kind ~= "update" then return nil end
    local labels = ns.EUISkippedLabels(plan)
    if #labels == 0 then return nil end
    return T.skipped:format(table.concat(labels, ", "))
end

---------------------------------------------------------------------------------
-- The acceptance: backup, import, rollbacks
---------------------------------------------------------------------------------

-- EllesmereUI's profile calls run every module's repoint and keybind hooks, so
-- one can raise partway through. Each runs protected and its error is reported
-- without stopping the sequence; the profile table, read after the call, says
-- what happened and which rollback applies. Returns the error text or nil.
local function try(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return nil end
    geterrorhandler()(err)
    return tostring(err)
end

local function refreshAll()
    local e = E()
    if e and e.RefreshAllAddons then try(e.RefreshAllAddons) end
end

-- True when the import had changed the scale. EllesmereUI applies the scale
-- only at startup, so the one the import put on screen stays until a reload.
local function restoreScale(rec)
    local d = DB()
    if not (isTable(d) and isTable(rec) and rec.scaleTaken) then return false end
    local changed = d.ppUIScale ~= rec.ppUIScale or d.ppUIScaleAuto ~= rec.ppUIScaleAuto
    d.ppUIScale = rec.ppUIScale
    d.ppUIScaleAuto = rec.ppUIScaleAuto
    return changed
end

-- `from` is the name the player's profile was moved to: the backup, or the
-- scratch name on a later change of the visit.
local function rolledBack(err, ok, detail, scaled, from)
    local line = err .. (ok and " Your previous profile was put back." or (" Your previous profile is named " .. (from or BACKUP) .. "."))
    if scaled then line = line .. " " .. T.reloadScale end
    return false, line, detail
end

-- Nothing stored: the rename alone moves everything back. `rec` holds the
-- scale to put back; only the visit's own backup record is cleared.
local function rollbackA(err, detail, from, rec)
    local e, d = E(), DB()
    try(e.RenameProfile, from, NAME)
    local ok = d.activeProfile == NAME and d.profiles[NAME] ~= nil
    local scaled = restoreScale(rec)
    if from == BACKUP then ns.db.euiBackup = nil end
    refreshAll()
    return rolledBack(err, ok, detail, scaled, from)
end

-- Stored without activating and the switch failed: remove the stored profile,
-- put the moved one back under its name and its assignments back on it.
local function rollbackB(err, detail, from, rec)
    local e, d = E(), DB()
    try(e.DeleteProfile, NAME)
    try(e.RenameProfile, from, NAME)
    local ok = d.activeProfile == NAME and d.profiles[NAME] ~= nil
    for _, spec in ipairs(isTable(rec) and rec.assignedSpecs or {}) do
        assignSpec(spec)
    end
    local scaled = restoreScale(rec)
    if from == BACKUP then ns.db.euiBackup = nil end
    refreshAll()
    return rolledBack(err, ok, detail, scaled, from)
end

-- What Restore previous puts back beside the backup profile.
local function backupRecord(assigned, scaleTaken)
    local d = DB()
    return {
        version = ns.db.addonVersions and ns.db.addonVersions.EllesmereUI,
        base = ns.db.euiBase,
        euiRowAt = ns.EUIDeepCopy(ns.db.euiRowAt),
        euiBases = ns.EUIDeepCopy(ns.db.euiBases),
        euiSettled = ns.EUIDeepCopy(ns.db.euiSettled),
        euiSettledAt = ns.EUIDeepCopy(ns.db.euiSettledAt),
        euiSettlePending = ns.EUIDeepCopy(ns.db.euiSettlePending),
        assignedSpecs = assigned,
        colorsPullFrom = d.colorsPullFrom or false,
        colorsSectionPullFrom = ns.EUIDeepCopy(d.colorsSectionPullFrom) or false,
        ppUIScale = d.ppUIScale,
        ppUIScaleAuto = d.ppUIScaleAuto,
        scaleTaken = scaleTaken,
    }
end

-- The scratch name, or a numbered one when a profile already holds it: an
-- existing profile of that name may be the player's own, so it is never
-- deleted to make room.
local function freeScratchName()
    local profiles = DB().profiles
    local name, i = ns.EUIScratchName, 1
    while profiles[name] ~= nil do
        i = i + 1
        name = ns.EUIScratchName .. " " .. i
    end
    return name
end

-- The scratch profile goes once the import has landed. Its delete drops every
-- note filed under it, so the notes move to the new profile first; a color
-- source still naming it would be cleared by the delete, so it moves too.
local function finishScratch(scratchName)
    local e, d = E(), DB()
    if ns.EUIMoveProfileRecords then ns.EUIMoveProfileRecords(scratchName, NAME) end
    if e.ColorSourcesProfileRenamed then
        try(e.ColorSourcesProfileRenamed, scratchName, NAME)
    elseif d.colorsPullFrom == scratchName then
        d.colorsPullFrom = NAME
    end
    if d.profiles[scratchName] then try(e.DeleteProfile, scratchName) end
end

-- The rename into the backup took the notes, but the new profile carries the
-- same switches and forced values. Copied, not moved: Restore previous brings
-- the backup's own set back under this name.
local function finishBackup()
    if ns.EUIMoveProfileRecords then ns.EUIMoveProfileRecords(BACKUP, NAME, true) end
end

local function finishApply(plan, before)
    if plan.kind == "update" then ns.CompleteSetup("EllesmereUI") end
    ns.db.euiRowAt, ns.db.euiBases = ns.EUIRecordRows(plan.kind, before, {
        rows = plan.inputs.rows,
        ticked = plan.ticked,
        changed = plan.changed,
        row = plan.row and plan.row.id,
        prior = { version = before.stamp, base = before.base },
        shipped = { version = ns.GetAddonDataVersion("EllesmereUI"), base = ns.data.EllesmereUI },
        kitn = ns.DisplayVersion and ns.DisplayVersion() or ns.version,
    })
    -- Written after an update's CompleteSetup, whose full-install transition
    -- this replaces: only the parts this change installed wait to settle. A
    -- reset plan's ticked set is its one part.
    writeSettle(ns.EUISettleRecord(plan.kind, before.settle, {
        parts = plan.ticked, rows = plan.inputs and plan.inputs.rows,
    }))
    if plan.kind ~= "reset" then
        ns.db.euiUpdateReport = {
            conflicts = plan.report.conflicts,
            kept = plan.report.kept,
            applied = plan.report.applied,
            noBase = plan.report.noBase,
            overrideSet = plan.report.overrideSet,
            byRow = plan.byRow,
            skipped = ns.EUISkippedLabels(plan),
        }
        ns.euiUpdatedThisSession = ns.db.euiUpdateReport
    end
    refreshAll()
    ns.ApplyEUIModuleSet()
end

-- A visit runs from opening the wizard to closing it. Its first change takes
-- the backup; every later one keeps it.
function ns.EUIBeginVisit()
    ns.euiVisitBacked = false
end

-- Applies a confirmed plan. Returns true on success; false and a line on a
-- refusal or a failure, plus the importer's own error text when it raised one;
-- "reconfirm" and a new plan when the activation prediction or the path changed
-- while the dialog was open.
function ns.EUIApplyUpdate(plan)
    local why = refusal()
    if why then return false, why end
    local e, d = E(), DB()
    local banked, err = ns.EUIBankCurrent()
    if not banked then return false, err end

    -- A prediction that moved while the dialog was open changes which leaves
    -- count; the recount runs over the inputs the confirm described, so edits
    -- made during the dialog stay out of the update and in the backup.
    local scratch = scratchPath()
    local lock = predictLock(scratch)
    if lock ~= plan.willLock or scratch ~= plan.scratch then
        local fresh, reason = plan.build(lock, scratch)
        if not fresh then return false, reason end
        return "reconfirm", fresh
    end
    local assigned = assignedSpecs()
    plan.merged.assignedSpecs = assigned
    local before = {
        rowAt = ns.db.euiRowAt,
        bases = ns.db.euiBases,
        base = ns.db.euiBase,
        stamp = ns.db.addonVersions and ns.db.addonVersions.EllesmereUI,
        settle = settleBefore(),
    }
    local scaleTaken = plan.merged.uiScale ~= nil

    local from, rec
    if scratch then
        -- A second import under the active profile's own name keeps the live
        -- layout over the merged one, so the live profile moves aside first.
        from = freeScratchName()
        rec = { assignedSpecs = assigned, ppUIScale = d.ppUIScale, ppUIScaleAuto = d.ppUIScaleAuto, scaleTaken = scaleTaken }
        err = try(e.RenameProfile, NAME, from)
        if not (d.profiles[from] and d.activeProfile == from) then
            -- A rename that raised after moving the table left the active
            -- name pointing at nothing.
            if d.profiles[NAME] == nil then return rollbackA(T.scratchFail, err, from, rec) end
            return false, T.scratchFail, err
        end
    else
        from = BACKUP
        if d.profiles[BACKUP] then
            err = try(e.DeleteProfile, BACKUP)
            if d.profiles[BACKUP] then return false, T.renameFail, err end
        end
        ns.db.euiBackup = backupRecord(assigned, scaleTaken)
        err = try(e.RenameProfile, NAME, BACKUP)
        if not (d.profiles[BACKUP] and d.activeProfile == BACKUP) then
            if d.profiles[NAME] == nil then return rollbackA(T.renameFail, err, BACKUP, ns.db.euiBackup) end
            ns.db.euiBackup = nil
            return false, T.renameFail, err
        end
        rec = ns.db.euiBackup
    end

    local ok, result, importErr, status = pcall(e.ImportProfile, { version = 3, type = "full", data = plan.merged }, NAME)
    local failed, detail = not ok or not result, nil
    if not ok then
        detail = tostring(result)
    elseif not result then
        detail = importErr
    end
    if failed then
        local line = T.importFail .. "."
        if d.profiles[NAME] == nil then
            return rollbackA(line, detail, from, rec)
        elseif d.activeProfile ~= NAME then
            return rollbackB(line, detail, from, rec)
        end
        -- The activation tail threw after the account writes: the merged
        -- profile is active and the visit's backup is intact, so Restore is
        -- offered.
        if scratch then finishScratch(from) else finishBackup() end
        if scaleTaken then ns.db.euiBackup.scaleTaken = true end
        ns.euiVisitBacked = true
        refreshAll()
        return false, line .. " " .. T.tailRestore, detail
    end

    if status == "spec_locked" then
        err = try(e.SetProfile, NAME)
        if d.activeProfile ~= NAME then return rollbackB(T.switchFailUpdate, err, from, rec) end
        if plan.merged.customColors then
            if e.PointColorSectionsAt then
                try(e.PointColorSectionsAt, NAME)
            elseif d.colorsApplyToAllProfiles ~= false then
                d.colorsPullFrom = NAME
            end
        end
    end

    if scratch then finishScratch(from) else finishBackup() end
    if scaleTaken then ns.db.euiBackup.scaleTaken = true end
    ns.euiVisitBacked = true
    finishApply(plan, before)
    return true
end

function ns.EUIUpdateToast(plan)
    if plan.kind == "reset" then return T.resetDone:format(plan.row.label) end
    local n = #plan.report.conflicts
    if n == 1 then return T.updatedReplacedOne end
    if n > 0 then return T.updatedReplaced:format(n) end
    return T.updated
end

---------------------------------------------------------------------------------
-- Restore previous
---------------------------------------------------------------------------------

function ns.EUIRestorePrevious()
    if InCombatLockdown() then return false, "Cannot restore in combat" end
    local e, d = E(), DB()
    if not (hasRequired(e) and isTable(d) and isTable(d.profiles)) then return false, T.needsNewer end
    if e._unlockModeActive then return false, T.unlockRestore end
    if ns.EUIRestorable() ~= "restore" then return false, T.notRestorable end
    local rec = ns.db.euiBackup
    local active = d.activeProfile or "Default"
    if active ~= BACKUP and ns.EUISharesSyncGroup(d.syncedModules, active, BACKUP) then
        return false, T.sync
    end
    -- A record from before the section sources existed holds none, so the
    -- current ones are kept through the delete, which would clear a source
    -- naming the profile it removes; one naming the backup follows the rename.
    local sections = rec.colorsSectionPullFrom
    if sections == nil and isTable(d.colorsSectionPullFrom) then
        sections = {}
        for s, n in pairs(d.colorsSectionPullFrom) do sections[s] = n == BACKUP and NAME or n end
    end
    try(e.SetProfile, BACKUP)
    if d.activeProfile ~= BACKUP then return false, T.switchFail end
    if d.profiles[NAME] then try(e.DeleteProfile, NAME) end
    try(e.RenameProfile, BACKUP, NAME)
    if not (d.profiles[NAME] and d.activeProfile == NAME) then
        -- Moved back under the backup's name, the profile is the active one
        -- again and Restore stays on offer.
        if d.profiles[BACKUP] == nil and d.profiles[NAME] then try(e.RenameProfile, NAME, BACKUP) end
        return false, "Could not restore the backup."
    end
    for _, spec in ipairs(isTable(rec.assignedSpecs) and rec.assignedSpecs or {}) do
        assignSpec(spec)
    end
    d.colorsPullFrom = rec.colorsPullFrom or nil
    if sections ~= nil then d.colorsSectionPullFrom = sections or nil end
    if e.ApplyColorsToOUF then try(e.ApplyColorsToOUF) end
    local scaled = restoreScale(rec)
    ns.db.euiBase = rec.base
    ns.db.addonVersions = ns.db.addonVersions or {}
    ns.db.addonVersions.EllesmereUI = rec.version
    ns.db.euiRowAt = rec.euiRowAt
    ns.db.euiBases = rec.euiBases
    ns.db.euiSettled = rec.euiSettled
    ns.db.euiSettledAt = rec.euiSettledAt
    ns.db.euiSettlePending = rec.euiSettlePending
    -- A part the restored record has pending is captured at the next login.
    ns.euiSettleDue = {}
    ns.euiVisitBacked = false
    ns.db.euiUpdateReport = nil
    ns.db.euiBackup = nil
    refreshAll()
    ns.ApplyEUIModuleSet()
    return true, scaled and T.reloadScale or nil
end
