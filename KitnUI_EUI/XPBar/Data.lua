-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Data.lua                                   ║
-- ║  Purpose: What the bars read from the game: XP, quest XP,    ║
-- ║           factions and kill messages.                        ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
local M = X.Math

local min = math.min

-- The highest standing a plain reputation has.
local MAX_REACTION = 8
-- A ceiling on the reputation list walk, so a list that keeps growing while
-- headers open cannot loop forever.
local CATALOG_GUARD = 500

local Plain = ns.EUIPlain

local function Num(v)
    v = Plain(v)
    return type(v) == "number" and v or nil
end

-- A call that may be missing or may raise: its results, or nil.
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d
end

local xp = {}

-- One reused table: { level, cur, max, rested, resting, applies, atMax, xpOff }.
-- Blizzard's own rule decides max level and whether the bar applies; the
-- level compare is the fallback.
function X.ReadXP()
    local level = Num(Call(UnitLevel, "player")) or 0
    local cap = min(Num(Call(GetMaxLevelForPlayerExpansion)) or math.huge, Num(Call(GetMaxPlayerLevel)) or math.huge)
    xp.level = level
    xp.cur = Num(Call(UnitXP, "player")) or 0
    xp.max = Num(Call(UnitXPMax, "player")) or 0
    xp.rested = Num(Call(GetXPExhaustion)) or 0
    xp.resting = Plain(Call(IsResting)) == true
    xp.xpOff = Plain(Call(IsXPUserDisabled)) == true
    local rules = _G.GameRulesUtil
    local atMax = rules and Plain(Call(rules.IsPlayerAtEffectiveMaxLevel))
    if type(atMax) ~= "boolean" then atMax = level >= cap end
    local applies = rules and Plain(Call(rules.CanShowExperienceBar))
    if type(applies) ~= "boolean" then applies = level < cap and not xp.xpOff end
    xp.atMax, xp.applies = atMax, applies
    return xp
end

-- The level the client counts as max, for a member's level as for the player's.
function X.LevelCap()
    local rules = _G.GameRulesUtil
    local cap = rules and Num(Call(rules.GetEffectiveMaxLevelForPlayer))
    if cap then return cap end
    local a, b = Num(Call(GetMaxLevelForPlayerExpansion)), Num(Call(GetMaxPlayerLevel))
    if a and b then return min(a, b) end
    return a or b
end

-- A read of a call that may be missing, raise or answer a secret: the first
-- two results, each nil when it cannot be used.
function X.ReadPlain(fn, ...)
    local a, b = Call(fn, ...)
    return Plain(a), Plain(b)
end

-- Completed and in-progress quest XP. Read-only: it never selects a quest.
-- Bonus objectives and world quests are tasks and are skipped.
function X.ScanQuestXP()
    local log, reward = _G.C_QuestLog, _G.GetQuestLogRewardXP
    if not (log and log.GetNumQuestLogEntries and log.GetInfo and type(reward) == "function") then return 0, 0 end
    local done, open = 0, 0
    for i = 1, Num(Call(log.GetNumQuestLogEntries)) or 0 do
        local info = Call(log.GetInfo, i)
        if type(info) == "table" and not info.isHeader and not info.isHidden and not info.isTask then
            local id = Num(info.questID)
            local gain = id and Num(Call(reward, id)) or 0
            if gain > 0 then
                if Plain(Call(log.IsComplete, id)) == true or Plain(Call(log.ReadyForTurnIn, id)) == true then
                    done = done + gain
                else
                    open = open + gain
                end
            end
        end
    end
    return done, open
end

local record = {}
local paragon = {}

local function StandingLabel(reaction)
    local label = reaction and _G["FACTION_STANDING_LABEL" .. reaction]
    return type(label) == "string" and label or ""
end

-- The companion's faction, only inside a delve; retail only.
local function CompanionFaction()
    if ns.IS_FOREVER then return nil end
    local delves, major, party = _G.C_DelvesUI, _G.C_MajorFactions, _G.C_PartyInfo
    if not (delves and major and party) then return nil end
    if Plain(Call(party.IsDelveInProgress)) ~= true then return nil end
    local season = Num(Call(delves.GetDelvesFactionForSeason))
    local data = season and Call(major.GetMajorFactionData, season)
    local companion = type(data) == "table" and Num(data.playerCompanionID) or nil
    return companion and Num(Call(delves.GetFactionForCompanion, companion)) or nil
end

local function WatchedFaction()
    local rep = _G.C_Reputation
    local data = rep and Call(rep.GetWatchedFactionData)
    return type(data) == "table" and Num(data.factionID) or nil
end

-- Friendship, paragon and renown are retail's, read in that order; Forever
-- reads plain standing only.
local function Fill(rec, id, data, rep)
    rec.paragon, rec.reaction = nil, nil
    rec.rank, rec.total = nil, nil
    if not ns.IS_FOREVER then
        local gossip = _G.C_GossipInfo
        local friend = gossip and Call(gossip.GetFriendshipReputation, id)
        if type(friend) == "table" and (Num(friend.friendshipFactionID) or 0) > 0 then
            local ranks = Call(gossip.GetFriendshipReputationRanks, id)
            local level = type(ranks) == "table" and Num(ranks.currentLevel) or nil
            local nextAt = Num(friend.nextThreshold)
            rec.kind = "friendship"
            rec.label = level and ("Level " .. level) or (Plain(friend.reaction) or "")
            rec.min = Num(friend.reactionThreshold) or 0
            rec.cur = Num(friend.standing) or 0
            rec.max = nextAt or rec.cur
            rec.isMax = nextAt == nil
            rec.rank, rec.total = level or rec.min, rec.cur
            return rec
        end
        if Plain(Call(rep.IsFactionParagonForCurrentPlayer or rep.IsFactionParagon, id)) == true then
            local value, threshold, _, pending = Call(rep.GetFactionParagonInfo, id)
            value, threshold = Num(value), Num(threshold)
            if value and threshold and threshold > 0 then
                rec.kind, rec.label = "paragon", "Paragon"
                rec.min, rec.cur, rec.max, rec.isMax = 0, value % threshold, threshold, false
                paragon.pending = Plain(pending) == true
                rec.paragon = paragon
                rec.rank, rec.total = math.floor(value / threshold), value
                return rec
            end
        end
        local major = _G.C_MajorFactions
        if major and Plain(Call(rep.IsMajorFaction, id)) == true then
            local md = Call(major.GetMajorFactionData, id)
            if type(md) == "table" then
                rec.kind = "renown"
                rec.label = "Renown " .. (Num(md.renownLevel) or 0)
                rec.min, rec.cur, rec.max = 0, Num(md.renownReputationEarned) or 0, Num(md.renownLevelThreshold) or 0
                rec.isMax = Plain(Call(major.HasMaximumRenown, id)) == true
                rec.rank, rec.total = Num(md.renownLevel) or 0, rec.cur
                return rec
            end
        end
    end
    local lo, hi = Num(data.currentReactionThreshold) or 0, Num(data.nextReactionThreshold) or 0
    rec.kind = "standard"
    rec.reaction = Num(data.reaction)
    rec.label = StandingLabel(rec.reaction)
    rec.min, rec.cur, rec.max = lo, Num(data.currentStanding) or 0, hi
    rec.isMax = (rec.reaction or 0) >= MAX_REACTION or hi <= lo
    rec.rank, rec.total = rec.reaction, rec.cur
    return rec
end

-- The progress record for the chosen source, or nil when there is no
-- faction to show. One reused table. The companion source falls back to the
-- watched faction outside a delve.
function X.ResolveFaction(source, pinnedID)
    local rep = _G.C_Reputation
    if not (rep and rep.GetFactionDataByID) then return nil end
    local id
    if source == "pinned" then
        id = Num(pinnedID)
        if id and id <= 0 then id = nil end
    else
        if source == "companion" then id = CompanionFaction() end
        id = id or WatchedFaction()
    end
    if not id then return nil end
    local data = Call(rep.GetFactionDataByID, id)
    local name = type(data) == "table" and Plain(data.name) or nil
    if type(name) ~= "string" or name == "" then return nil end
    record.id, record.name = id, name
    return Fill(record, id, data, rep)
end

function X.FactionName(id)
    local rep = _G.C_Reputation
    id = Num(id)
    local data = rep and id and Call(rep.GetFactionDataByID, id)
    local name = type(data) == "table" and Plain(data.name) or nil
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- Every known faction as dropdown values and order, or nil in combat or a
-- protected instance. Opening collapsed headers is the only way to list what
-- they hold; only the headers opened here are closed again, so the
-- reputation pane looks as it did.
function X.FactionCatalog()
    local rep = _G.C_Reputation
    if not (rep and rep.GetNumFactions and rep.GetFactionDataByIndex) then return nil end
    if InCombatLockdown() then return nil end
    local EUI = _G.EllesmereUI
    if EUI and EUI.InProtectedInstance and Plain(Call(EUI.InProtectedInstance)) == true then return nil end
    local opened = {}
    local i = 1
    while i <= (Num(Call(rep.GetNumFactions)) or 0) and i <= CATALOG_GUARD do
        local d = Call(rep.GetFactionDataByIndex, i)
        if type(d) == "table" and d.isHeader and d.isCollapsed and rep.ExpandFactionHeader then
            local key = Plain(d.name)
            if type(key) == "string" then opened[key] = true end
            Call(rep.ExpandFactionHeader, i)
        end
        i = i + 1
    end
    local values, order = {}, {}
    local n = min(Num(Call(rep.GetNumFactions)) or 0, CATALOG_GUARD)
    for j = 1, n do
        local d = Call(rep.GetFactionDataByIndex, j)
        local id = type(d) == "table" and Num(d.factionID) or nil
        local name = type(d) == "table" and Plain(d.name) or nil
        if id and id > 0 and type(name) == "string" and name ~= "" and (not d.isHeader or d.isHeaderWithRep)
            and not values[id] then
            values[id] = name
            order[#order + 1] = id
        end
    end
    if rep.CollapseFactionHeader then
        for j = n, 1, -1 do
            local d = Call(rep.GetFactionDataByIndex, j)
            local key = type(d) == "table" and d.isHeader and not d.isCollapsed and Plain(d.name) or nil
            if type(key) == "string" and opened[key] then Call(rep.CollapseFactionHeader, j) end
        end
    end
    return values, order
end

-- Retail only: Forever estimates kills from the level instead.
function X.ParseKillXP(text)
    if ns.IS_FOREVER then return nil end
    return M.ParseKill(text, _G.COMBATLOG_XPGAIN_FIRSTPERSON, issecretvalue)
end
