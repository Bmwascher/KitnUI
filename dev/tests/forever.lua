-- ╔══════════════════════════════════════════════════════════════╗
-- ║  forever.lua                                                 ║
-- ║  Purpose: Gate for KitnUI on WoW Forever: the client flag,   ║
-- ║           the version each client reads, the Forever         ║
-- ║           manifest, the Forever Essentials switches and      ║
-- ║           the Top Bar on Forever.                            ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/forever.lua

local failures = 0
local checks = 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
    end
end

local function eq(actual, expected, label)
    check(actual == expected, label, "got " .. tostring(actual) .. ", wanted " .. tostring(expected))
end

---------------------------------------------------------------------------------
-- Stubs: what Installer/Core.lua touches while it loads
---------------------------------------------------------------------------------

-- The TOC lines KitnUI ships, by header. Each case sets the ones it needs.
local metadata = { Version = "test" }

-- Every frame any loaded file creates, with the events it registered.
local frames = {}

_G.format = string.format
_G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert = table.insert
_G.C_AddOns = {
    GetAddOnMetadata = function(_, header) return metadata[header] end,
    IsAddOnLoaded = function() return false end,
}
_G.InCombatLockdown = function() return false end
_G.C_Timer = { After = function() end }
_G.CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = frame
    return setmetatable(frame, { __index = function() return function() end end })
end
_G.hooksecurefunc = function() end
_G.SlashCmdList = {}
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
_G.C_SpecializationInfo = {
    GetNumSpecializationsForClassID = function() return 3 end,
    GetSpecialization = function() return 1 end,
}
_G.GetSpecializationInfoForClassID = function(_, i) return 70 + i, "Spec" .. i, "", 12345 end
_G.UnitName = function() return "Tester" end
_G.GetRealmName = function() return "Realm" end
_G.ReloadUI = function() end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function() end

-- A fresh namespace per load, on the client the case names. nil leaves
-- GetBuildInfo undefined, as the other suites do.
local function loadCore(interface)
    if interface == nil then
        _G.GetBuildInfo = nil
    else
        _G.GetBuildInfo = function() return "12.0.5", "1", "Nov 1 2026", interface end
    end
    local coreNS = { data = {} }
    local chunk, err = loadfile("Installer/Core.lua")
    if not chunk then
        print("FAIL  could not load Installer/Core.lua: " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", coreNS)
    return coreNS
end

---------------------------------------------------------------------------------
-- The client flag
---------------------------------------------------------------------------------

eq(loadCore(120105).IS_FOREVER, false, "flag: retail is not Forever")
eq(loadCore(16001).IS_FOREVER, true, "flag: 16001 is Forever")
eq(loadCore(15999).IS_FOREVER, false, "flag: below 16000 is not Forever")
eq(loadCore(20000).IS_FOREVER, false, "flag: 20000 is not Forever")
eq(loadCore("16001").IS_FOREVER, false, "flag: an interface that is not a number is not Forever")
eq(loadCore(nil).IS_FOREVER, false, "flag: no GetBuildInfo is not Forever")

---------------------------------------------------------------------------------
-- The version each client reads
---------------------------------------------------------------------------------

metadata["X-BigWigs-Version"] = "R1"
metadata["X-BigWigs-Forever-Version"] = "F1"
metadata["X-EditMode-Version"] = "R2"
metadata["X-EditMode-Forever-Version"] = "F2"
metadata["X-NSRT-Version"] = "R3"
metadata["X-Baganator-Version"] = "R4"
metadata["X-Baganator-Forever-Version"] = ""

local retail = loadCore(120105)
local forever = loadCore(16001)

eq(retail.GetAddonDataVersion("BigWigs"), "R1", "versions: retail reads the retail line")
eq(retail.GetAddonDataVersion("Blizzard_EditMode"), "R2", "versions: retail reads the retail Edit Mode line")
eq(forever.GetAddonDataVersion("BigWigs"), "F1", "versions: Forever reads its own line")
eq(forever.GetAddonDataVersion("Blizzard_EditMode"), "F2", "versions: Forever reads its own Edit Mode line")
eq(forever.GetAddonDataVersion("NSRT"), "R3", "versions: with no Forever line, Forever reads the retail line")
eq(forever.GetAddonDataVersion("Baganator"), "R4", "versions: an empty Forever line counts as none")
eq(forever.GetAddonDataVersion("BlizzardCDM"), nil, "versions: Blizzard CDM has no version line on Forever either")

-- The outdated list reads the same answer as every other version reader.
local function outdatedVersion(client, key)
    for _, entry in ipairs(client.GetOutdatedAddons()) do
        if entry.key == key then return entry.newVersion end
    end
    return nil
end

for _, client in ipairs({ retail, forever }) do
    client.db = { profiles = { BigWigs = true, NSRT = true }, addonVersions = { BigWigs = "R1", NSRT = "R3" } }
    client.data.BigWigs = "payload"
    client.data.NSRT = "payload"
end
eq(outdatedVersion(retail, "BigWigs"), nil, "outdated: retail at the retail version is current")
eq(outdatedVersion(forever, "BigWigs"), "F1", "outdated: Forever offers its own version over a retail import")
eq(outdatedVersion(forever, "NSRT"), nil, "outdated: a reused retail string at the retail version is current on Forever")

---------------------------------------------------------------------------------
-- The TOC lines and the Forever manifest
---------------------------------------------------------------------------------

local function readLines(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local lines = {}
    for line in handle:lines() do lines[#lines + 1] = (line:gsub("\r$", "")) end
    handle:close()
    return lines
end

local function hasLine(lines, wanted)
    for _, line in ipairs(lines) do
        if line == wanted then return true end
    end
    return false
end

local tocLines = readLines("KitnUI.toc") or {}
local euiTocLines = readLines("KitnUI_EUI/KitnUI_EUI.toc") or {}

check(hasLine(tocLines, "## Interface: 120105, 16001"), "toc: KitnUI lists retail and Forever")
check(hasLine(euiTocLines, "## Interface: 120105, 16001"), "toc: KitnUI_EUI lists retail and Forever")

check(hasLine(tocLines, "Data\\Data.xml [AllowLoadGameType standard]"),
    "toc: the retail manifest is tagged to load on retail only")
check(hasLine(tocLines, "Data\\Data-Forever.xml [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic]"),
    "toc: the Forever manifest is tagged to load on Forever only")
check(not hasLine(tocLines, "Data\\Data.xml"), "toc: no untagged manifest loads on both clients")

local function payloadFiles(manifestPath)
    local files = {}
    for _, line in ipairs(readLines(manifestPath) or {}) do
        local scriptFile = line:match('<Script%s+file="([^"]+)"')
        if scriptFile then
            local path = "Data/" .. (scriptFile:gsub("\\", "/"))
            local payloadChunk, payloadErr = loadfile(path)
            check(payloadChunk ~= nil, "manifest: " .. path .. " loads", payloadErr)
            if payloadChunk then
                local payloadNS = { data = {} }
                payloadChunk("KitnUI", payloadNS)
                files[#files + 1] = { path = path, data = payloadNS.data }
            end
        end
    end
    return files
end

check(readLines("Data/Data-Forever.xml") ~= nil, "manifest: Data/Data-Forever.xml exists")
local retailFiles = payloadFiles("Data/Data.xml")
local foreverFiles = payloadFiles("Data/Data-Forever.xml")
check(#retailFiles > 0, "manifest: the retail manifest lists its payloads")

-- The shipped TOC's own lines, values as written.
for header in pairs(metadata) do metadata[header] = nil end
metadata.Version = "test"
local foreverLineCount = 0
for _, line in ipairs(tocLines) do
    local header, value = line:match("^## (X%-[^:]+):%s*(.-)%s*$")
    if header then
        metadata[header] = value
        if header:match("%-Forever%-Version$") and value ~= "" then
            foreverLineCount = foreverLineCount + 1
        end
    end
end
local tocRetail = loadCore(120105)

-- Each client loads only its own manifest, so every retail payload has a
-- Forever file at the same path under Data/Forever/ assigning the same keys.
-- Their strings may differ: a Forever export replaces its copy.
local function keyList(data)
    local keys = {}
    for key in pairs(data) do keys[#keys + 1] = key end
    table.sort(keys)
    return table.concat(keys, ",")
end

local foreverByPath = {}
for _, payloadFile in ipairs(foreverFiles) do foreverByPath[payloadFile.path] = payloadFile end
for _, payloadFile in ipairs(retailFiles) do
    local foreverPath = (payloadFile.path:gsub("^Data/", "Data/Forever/"))
    local foreverFile = foreverByPath[foreverPath]
    check(foreverFile ~= nil, "pairing: " .. payloadFile.path .. " has a Forever file at " .. foreverPath)
    if foreverFile then
        eq(keyList(foreverFile.data), keyList(payloadFile.data),
            "pairing: " .. foreverPath .. " assigns the same keys as its retail file")
    end
end
eq(#foreverFiles, #retailFiles, "pairing: the Forever manifest lists one file per retail payload")

-- Forever has nine classes, each with one spec.
local FOREVER_CLASSES = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }
local foreverCDMFile = foreverByPath["Data/Forever/Classes/BlizzardCDM.lua"]
local foreverCDM = foreverCDMFile and foreverCDMFile.data.BlizzardCDM or {}
local cdmClasses = 0
for _ in pairs(foreverCDM) do cdmClasses = cdmClasses + 1 end
eq(cdmClasses, #FOREVER_CLASSES, "cdm: Forever's layouts cover nine classes")
for _, classId in ipairs(FOREVER_CLASSES) do
    local specs = foreverCDM[classId]
    local specCount = 0
    if type(specs) == "table" then
        for _ in pairs(specs) do specCount = specCount + 1 end
    end
    check(specCount == 1 and type(specs[1]) == "string", "cdm: Forever class " .. classId .. " has one spec")
end

-- Only a non-empty layout string makes a class importable.
local cdmCore = loadCore(120105)
eq(cdmCore.CDMClassHasLayouts(nil), false, "cdm: no class table has no layouts")
eq(cdmCore.CDMClassHasLayouts({}), false, "cdm: an empty class table has no layouts")
eq(cdmCore.CDMClassHasLayouts({ [1] = "" }), false, "cdm: an empty spec string is no layout")
eq(cdmCore.CDMClassHasLayouts({ [1] = "  " }), false, "cdm: a blank spec string is no layout")
eq(cdmCore.CDMClassHasLayouts({ [1] = "", [2] = "1|x" }), true, "cdm: one filled spec makes the class importable")

-- A retail version bump must never offer Forever an update its own string did
-- not get, so every versioned step has its own Forever line. Read with the
-- retail lines removed, so the shipped fallback cannot answer for a missing
-- one. Keys that share a step's version (BigWigs_Bosses,
-- Blizzard_EditMode_Lulu) and Blizzard CDM, which fingerprints its strings,
-- have no line.
local versionedKeys = {}
for _, payloadFile in ipairs(retailFiles) do
    for key in pairs(payloadFile.data) do
        if tocRetail.GetAddonDataVersion(key) ~= nil then versionedKeys[#versionedKeys + 1] = key end
    end
end

local retailLines = {}
for header, value in pairs(metadata) do
    if header:match("^X%-.-%-Version$") and not header:match("%-Forever%-Version$") then
        retailLines[header] = value
    end
end
local foreverOnly = loadCore(16001)
for header in pairs(retailLines) do metadata[header] = nil end

for _, key in ipairs(versionedKeys) do
    check(foreverOnly.GetAddonDataVersion(key) ~= nil, "versions: " .. key .. " has a Forever version line")
end
for header, value in pairs(retailLines) do metadata[header] = value end
eq(#versionedKeys, foreverLineCount, "versions: every non-empty Forever version line names a versioned step")

---------------------------------------------------------------------------------
-- The Forever Essentials switches
---------------------------------------------------------------------------------

local ESSENTIALS_ON = { "spellUprank", "junkList", "activeForm", "gatherSkill", "worldMapReveal",
    "mapTravel", "questRewards", "zoneLevels", "petSummon", "macroManager" }
local ESSENTIALS_OFF = { "classicSpellbook", "classicTalents", "simplifiedStats", "worldMapFade",
    "threatMeter", "lootFeed" }

local imports = 0
local importAccepted = true
_G.EllesmereUI = {
    ImportProfileSilent = function()
        imports = imports + 1
        return importAccepted, "refused"
    end,
    SetProfile = function() end,
    RefreshAllAddons = function() end,
}

local setupNS = {
    title = "KitnUI",
    profileName = "KitnUI",
    version = "test",
    data = { EllesmereUI = "shipped-string" },
    EUIReady = function() return true end,
    GetAddonDataVersion = function() return "test" end,
    DecideAccountTheme = function() end,
}
local setupChunk, setupErr = loadfile("Installer/Setup.lua")
if not setupChunk then
    print("FAIL  could not load Installer/Setup.lua: " .. tostring(setupErr))
    os.exit(1)
end
setupChunk("KitnUI", setupNS)
check(type(setupNS.ApplyForeverEssentials) == "function", "essentials: ns.ApplyForeverEssentials is defined")
local applyEssentials = setupNS.ApplyForeverEssentials or function() end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function snapshot(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. snapshot(value[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Retail writes nothing and creates nothing.
setupNS.IS_FOREVER = false
_G.EllesmereUIDB = { lootFeed = { pos = { x = 1 } } }
applyEssentials()
eq(countKeys(_G.EllesmereUIDB), 1, "essentials: retail creates no table")
eq(_G.EllesmereUIDB.lootFeed.enabled, nil, "essentials: retail writes no switch")

-- Forever writes the listed fields and nothing else.
setupNS.IS_FOREVER = true
_G.EllesmereUIDB = {
    junkList = { freeSlotThreshold = 8 },
    lootFeed = { enabled = true, pos = { x = 1 } },
    flightTimer = { enabled = true, x = 2 },
    fishing = { reel = true },
    petSummon = 5,
    profiles = { KitnUI = {} },
}
applyEssentials()
local edb = _G.EllesmereUIDB

-- nil unless the feature's table exists, so a missing table never reads as off.
local function switchOf(key)
    local settings = edb[key]
    if type(settings) ~= "table" then return nil end
    return settings.enabled
end

for _, key in ipairs(ESSENTIALS_ON) do
    if key ~= "petSummon" then
        eq(switchOf(key), true, "essentials: " .. key .. " is on")
    end
end
for _, key in ipairs(ESSENTIALS_OFF) do
    eq(switchOf(key), false, "essentials: " .. key .. " is off")
end
eq(edb.junkList.onlyLowBagSpace, true, "essentials: Junk Items waits for nearly full bags")
eq(edb.junkList.freeSlotThreshold, 8, "essentials: the player's free-slot threshold is kept")
eq(edb.lootFeed.pos.x, 1, "essentials: a feature's other settings are kept")
eq(edb.flightTimer.enabled, true, "essentials: Flight Timer's switch is not touched")
eq(edb.flightTimer.x, 2, "essentials: nor its settings")
eq(edb.fishing.enabled, nil, "essentials: Fishing gets no switch")
eq(edb.petSummon, 5, "essentials: a key holding something other than a table is left alone")
eq(countKeys(edb), 19, "essentials: only the listed features gain a table")

local before = snapshot(edb)
applyEssentials()
eq(snapshot(edb), before, "essentials: a second run changes nothing")

_G.EllesmereUIDB = nil
check(pcall(applyEssentials), "essentials: no EllesmereUIDB raises nothing")

-- The EllesmereUI import writes them on Forever; a refused import and a load
-- do not.
local function quietly(fn)
    local realPrint = _G.print
    _G.print = function() end
    local result = fn()
    _G.print = realPrint
    return result
end

setupNS.db = { profiles = {}, addonVersions = {}, perChar = {} }
_G.EllesmereUIDB = { profiles = {} }
check(setupNS.SetupAddon("EllesmereUI", true) ~= false, "import: the EllesmereUI import succeeds")
eq(_G.EllesmereUIDB.spellUprank and _G.EllesmereUIDB.spellUprank.enabled, true, "import: the import sets the switches")

importAccepted = false
setupNS.db = { profiles = {}, addonVersions = {}, perChar = {} }
_G.EllesmereUIDB = { profiles = {} }
eq(quietly(function() return setupNS.SetupAddon("EllesmereUI", true) end), false, "import: a refused import fails")
eq(_G.EllesmereUIDB.spellUprank, nil, "import: a refused import sets no switch")
importAccepted = true

_G.EllesmereUIDB = { profiles = { KitnUI = {} } }
check(setupNS.SetupAddon("EllesmereUI", false) ~= false, "import: the load succeeds")
eq(_G.EllesmereUIDB.spellUprank, nil, "import: a load sets no switch")
eq(imports, 2, "import: the load imports nothing")
setupNS.IS_FOREVER = false

---------------------------------------------------------------------------------
-- The Top Bar on each client
---------------------------------------------------------------------------------

-- A fresh registry per client, with the frames that load created.
local function loadElements(isForever)
    local first = #frames + 1
    local elementsNS = {
        EUI_INERT = false,
        EUI_TB_DEFAULT_ORDER = {},
        IS_FOREVER = isForever,
        TopBar = { Apply = function() end },
    }
    local chunk, err = loadfile("KitnUI_EUI/TopBar/Elements.lua")
    if not chunk then
        print("FAIL  could not load KitnUI_EUI/TopBar/Elements.lua: " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI_EUI", elementsNS)
    local made = {}
    for i = first, #frames do made[#made + 1] = frames[i] end
    return elementsNS.TopBar.ById, made
end

local function macroText(el)
    local button = { attributes = {} }
    function button:SetAttribute(name, value) self.attributes[name] = value end
    el.attrs(button)
    return button.attributes.macrotext1
end

local function housingEvents(made)
    for _, frame in ipairs(made) do
        if frame.events.PLAYER_HOUSE_LIST_UPDATED then return frame.events end
    end
    return nil
end

local function onBar(el)
    if not el.requires then return true end
    return el.requires() and true or false
end

local HIDDEN_ON_FOREVER = { "portals", "vault", "home", "journal" }
local HOUSING_EVENTS = { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_HOUSE_LIST_UPDATED",
    "HOUSE_PLOT_ENTERED", "HOUSE_PLOT_EXITED" }

-- A host season list, so portals has a list to show on retail even in a
-- season where KitnUI's own table is emptied to defer to the host's.
_G.EllesmereUI.SEASON_PORTALS = { { spellID = 1, short = "T", mapID = 1, names = { "test" } } }
_G.LEGACY_BUTTON = "Legacy"

local retailBar, retailFrames = loadElements(nil)
eq(macroText(retailBar.achievements), "/click AchievementMicroButton", "topbar: retail achievements is unchanged")
eq(retailBar.achievements.label, "Achievements", "topbar: retail keeps the Achievements name")
eq(macroText(retailBar.talents), "/click PlayerSpellsMicroButton", "topbar: retail talents is unchanged")
for _, id in ipairs(HIDDEN_ON_FOREVER) do
    eq(onBar(retailBar[id]), true, "topbar: retail shows " .. id)
end
local retailEvents = housingEvents(retailFrames)
check(retailEvents ~= nil, "topbar: retail registers the housing watcher")
for _, event in ipairs(HOUSING_EVENTS) do
    eq(retailEvents and retailEvents[event], true, "topbar: the retail watcher has " .. event)
end

local foreverBar, foreverFrames = loadElements(true)
eq(macroText(foreverBar.achievements), "/click LegacyMicroButton", "topbar: Forever achievements opens Progress Legacy")
eq(foreverBar.achievements.label, "Legacy", "topbar: Forever names it as its own button does")
eq(macroText(foreverBar.talents), "/click TalentMicroButton", "topbar: Forever talents clicks its talent button")
for _, id in ipairs(HIDDEN_ON_FOREVER) do
    eq(onBar(foreverBar[id]), false, "topbar: Forever hides " .. id)
end
eq(housingEvents(foreverFrames), nil, "topbar: Forever registers no housing events")
for _, id in ipairs({ "friends", "guild", "groupfinder", "toybox", "character", "spellbook",
    "professions", "volume", "euiconfig", "gamemenu" }) do
    eq(foreverBar[id] and onBar(foreverBar[id]), true, "topbar: Forever still shows " .. id)
end

_G.LEGACY_BUTTON = nil
local unnamedBar = loadElements(true)
eq(unnamedBar.achievements.label, "Achievements", "topbar: with no Forever name the button keeps Achievements")

---------------------------------------------------------------------------------
-- A step in the retail table alone still reads on Forever
---------------------------------------------------------------------------------

-- The shipped Core.lua with one step added to its retail header table only, as
-- an edit that forgets the Forever side would leave it. The version API stub
-- raises on a nil header, as the game's does.
local coreFile = io.open("Installer/Core.lua", "r")
local coreSource = coreFile and coreFile:read("*a") or ""
if coreFile then coreFile:close() end
local injectedSource, injections = coreSource:gsub(
    'Baganator         = "X%-Baganator%-Version",',
    'Baganator         = "X-Baganator-Version",\n    TestStep          = "X-TestStep-Version",', 1)
eq(injections, 1, "derived: the retail header table is found")

local realMetadataRead = _G.C_AddOns.GetAddOnMetadata
_G.C_AddOns.GetAddOnMetadata = function(_, header)
    if header == nil then error("GetAddOnMetadata: header is nil") end
    return metadata[header]
end
_G.GetBuildInfo = function() return "12.0.5", "1", "Nov 1 2026", 16001 end
metadata["X-TestStep-Version"] = "T1"

local derivedNS = { data = {} }
local derivedChunk, derivedErr = loadstring(injectedSource, "@Installer/Core.lua")
check(derivedChunk ~= nil, "derived: the edited Core.lua loads", derivedErr)
if derivedChunk then derivedChunk("KitnUI", derivedNS) end
local derivedRead = derivedNS.GetAddonDataVersion or function() end

local readOk, readVersion = pcall(derivedRead, "TestStep")
check(readOk, "derived: a step only in the retail table reads on Forever without an error", readVersion)
eq(readOk and readVersion, "T1", "derived: with no Forever line it reads the retail line")
metadata["X-TestStep-Forever-Version"] = "F9"
readOk, readVersion = pcall(derivedRead, "TestStep")
eq(readOk and readVersion, "F9", "derived: its Forever line is the retail name with -Forever before -Version")

_G.C_AddOns.GetAddOnMetadata = realMetadataRead
metadata["X-TestStep-Version"], metadata["X-TestStep-Forever-Version"] = nil, nil

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
