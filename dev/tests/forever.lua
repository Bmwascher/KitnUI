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

local FOREVER_MANIFEST_LINE = "Data\\Data-Forever.xml [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic]"
local retailManifestAt, foreverManifestAt
for i, line in ipairs(tocLines) do
    if line == "Data\\Data.xml" then retailManifestAt = i end
    if line == FOREVER_MANIFEST_LINE then foreverManifestAt = i end
end
check(foreverManifestAt ~= nil, "toc: the Forever manifest is tagged to load on Forever only")
check(retailManifestAt ~= nil and foreverManifestAt ~= nil and foreverManifestAt > retailManifestAt,
    "toc: it loads after the retail manifest, so its payloads replace the retail ones")

-- Every Forever payload file ships with its step's Forever version line, and
-- every Forever version line belongs to a step a Forever file ships. A file
-- belongs to the versioned keys it assigns; its other keys (BigWigs_Bosses,
-- Blizzard_EditMode_Lulu) share that step's version. Blizzard CDM fingerprints
-- its strings and has no line. Every read goes through the shipped lookup, so
-- an empty line counts as none here exactly as it does in game, and any
-- non-empty value is a valid version.
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
local tocForever = loadCore(16001)

local function versioned(key) return tocRetail.GetAddonDataVersion(key) ~= nil end

-- A player who imported the retail string on Forever holds the retail version,
-- and the update offer needs a different one, so a Forever line that repeats
-- its retail line counts as none.
local function hasForeverLine(key)
    local retailVersion = tocRetail.GetAddonDataVersion(key)
    return retailVersion ~= nil and tocForever.GetAddonDataVersion(key) ~= retailVersion
end

local shippedOnForever = {}
for _, payloadFile in ipairs(foreverFiles) do
    local owners = 0
    for key in pairs(payloadFile.data) do
        if versioned(key) then
            owners = owners + 1
            shippedOnForever[key] = true
            check(hasForeverLine(key),
                "pairing: " .. payloadFile.path .. " ships " .. key .. " with a Forever version line that differs from its retail line")
        end
    end
    check(owners > 0 or payloadFile.data.BlizzardCDM ~= nil,
        "pairing: " .. payloadFile.path .. " assigns a versioned step or Blizzard CDM")
end

local stepKeys = {}
for _, files in ipairs({ retailFiles, foreverFiles }) do
    for _, payloadFile in ipairs(files) do
        for key in pairs(payloadFile.data) do stepKeys[key] = true end
    end
end
local linesRead = 0
for key in pairs(stepKeys) do
    if hasForeverLine(key) then
        linesRead = linesRead + 1
        check(shippedOnForever[key], "pairing: the Forever version line for " .. key .. " has a Forever payload")
    end
end
eq(linesRead, foreverLineCount,
    "pairing: every non-empty Forever version line names a step and differs from its retail line")

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
