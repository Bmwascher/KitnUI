-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Party.lua                                  ║
-- ║  Purpose: Party XP's live path: the gate's readings, the one ║
-- ║           party frame, the roster, heard values, the send    ║
-- ║           path and the feeds to the displays.                ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
local L = X.PartyLogic

local Plain = ns.EUIPlain
local Get = X.Get
local Read = X.ReadPlain

local UNITS = { "party1", "party2", "party3", "party4" }

local frame, timer, loginQueued, lastChannel
local mode = "off"
local prefixHeld = false
local registered, wanted = {}, {}
-- The refusal state machine's table.
local s = {}
local inParty, memberBelowMax, anyBelowMax = false, false, false
local memberCount, lastCount = 0, 0

local members = {}
for i = 1, #UNITS do members[i] = { present = false, view = {} } end
local me = { online = true, view = {} }
local myHeard = {}
local byKey, heard = {}, {}
local rows, marks = {}, { n = 0 }
local rowCount = 0

local OnEvent, Flush

---------------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------------

-- A reading that cannot be trusted counts as locked: a wrong "unlocked" is a
-- blocked call, and a wrong "locked" only waits.
local function ChatLocked()
    local info = _G.C_ChatInfo
    if not (info and info.InChatMessagingLockdown) then return false end
    local ok, locked = pcall(info.InChatMessagingLockdown)
    return not ok or Plain(locked) ~= false
end

local function InPartyGroup()
    if Read(IsInRaid) == true then return false end
    return Read(IsInGroup) == true
end

local function CurrentChannel()
    return L.Channel(Read(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) == true, Read(IsInGroup, LE_PARTY_CATEGORY_HOME) == true)
end

local function Hearing()
    return mode == "listen" or mode == "share"
end

---------------------------------------------------------------------------------
-- The roster
---------------------------------------------------------------------------------

local function Clear(t)
    for k in pairs(t) do t[k] = nil end
end

local function ClearRoster()
    for i = 1, #members do
        members[i].present, members[i].key = false, nil
    end
    Clear(byKey)
    Clear(heard)
    inParty, memberBelowMax, anyBelowMax = false, false, false
    memberCount = 0
end

local function ApplyVerdict(m, verdict, name, realm, class, level, online, myRealm)
    if verdict == "drop" or verdict == "none" then
        m.present, m.key = false, nil
    elseif verdict == "keep" then
        if type(level) == "number" and level > 0 then m.level = level end
        m.online = online
    else
        m.present, m.name, m.class, m.level, m.online = true, name, class, level, online
        m.key = L.MemberKey(name, realm, myRealm)
    end
end

local function RosterPass()
    local cap = X.LevelCap()
    local myRealm = Read(GetNormalizedRealmName)
    local humans, below, unreadable = 0, false, false
    Clear(byKey)
    for i = 1, #UNITS do
        local unit, m = UNITS[i], members[i]
        local exists = Read(UnitExists, unit) == true
        local follower = exists and (Read(UnitInPartyIsAI, unit) == true or Read(UnitIsPlayer, unit) == false)
        local name, realm, class, level, online
        if exists and not follower then
            humans = humans + 1
            name, realm = Read(UnitFullName, unit)
            local _, file = Read(UnitClass, unit)
            class = file
            level = Read(UnitLevel, unit)
            online = Read(UnitIsConnected, unit) ~= false
            if not (cap and type(level) == "number" and level >= cap) then below = true end
        end
        local verdict = L.MergeMember(m.present and m or nil, exists, follower, name, class, level)
        if verdict == "keep" or verdict == "none" then unreadable = true end
        ApplyVerdict(m, verdict, name, realm, class, level, online, myRealm)
        if m.present and m.key then byKey[m.key] = m end
    end
    -- With a member unreadable the roster cannot be known, so nothing is pruned.
    if not unreadable then
        for key in pairs(heard) do
            if not byKey[key] then heard[key] = nil end
        end
    end
    memberCount, memberBelowMax, inParty = humans, below, humans > 0
end

---------------------------------------------------------------------------------
-- The displays' feed
---------------------------------------------------------------------------------

local function ViewSelf(cap)
    local t = X.ReadXP()
    local name = Read(UnitFullName, "player")
    local _, class = Read(UnitClass, "player")
    me.name, me.class = name or me.name, class or me.class
    me.level = t.level
    myHeard.level = t.level
    myHeard.pct = t.max > 0 and t.cur * 100 / t.max or 0
    L.RowView(me.view, me, myHeard, cap, false)
    return not t.atMax
end

local function ViewMember(m, cap, locked)
    L.RowView(m.view, m, m.key and heard[m.key], cap, locked)
end

local function BuildMarks()
    local n = 0
    for i = 1, #members do
        local m = members[i]
        local h = m.key and heard[m.key]
        if m.present and h and m.view.kind == "data" then
            n = n + 1
            local e = marks[n]
            if not e then
                e = {}
                marks[n] = e
            end
            e.name, e.class, e.level, e.pct = m.name, m.class, h.level, h.pct
        end
    end
    marks.n = n
end

local function BuildRows()
    rowCount = 0
    if inParty then
        if me.name and Get("xpPartyShowSelf") == true then
            rowCount = 1
            rows[rowCount] = me
        end
        for i = 1, #members do
            if members[i].present then
                rowCount = rowCount + 1
                rows[rowCount] = members[i]
            end
        end
    end
    BuildMarks()
end

local function Publish()
    X.PartyCardRefresh(rows, rowCount, L.CardShown(Get("xpPartyCard") == true, inParty, anyBelowMax, rowCount))
    local w = X.LiveXPWidget()
    if w and X.XPEnabled() then X.SyncMarkers(w, Get, X.PartyMarkerList()) end
end

local function RedrawAll()
    if inParty then
        local cap, locked = X.LevelCap(), ChatLocked()
        anyBelowMax = ViewSelf(cap) or memberBelowMax
        for i = 1, #members do
            if members[i].present then ViewMember(members[i], cap, locked) end
        end
    end
    BuildRows()
    Publish()
end

---------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------

local function CancelTimer()
    if timer then
        timer:Cancel()
        timer = nil
    end
end

local function Arm()
    if timer or not (C_Timer and C_Timer.NewTimer) then return end
    timer = C_Timer.NewTimer(L.SLOT, Flush)
end

local function Fire(kind)
    if prefixHeld and Hearing() and L.Trigger(s, kind) then Arm() end
end

local function RegisterPrefix()
    if prefixHeld then return end
    local info = _G.C_ChatInfo
    if not (info and info.RegisterAddonMessagePrefix) then return end
    local ok, result = pcall(info.RegisterAddonMessagePrefix, L.PREFIX)
    prefixHeld = ok and L.PrefixHeld(Plain(result))
end

---------------------------------------------------------------------------------
-- The gate
---------------------------------------------------------------------------------

local function SetMode(newMode, ownXP)
    if newMode ~= "off" and not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
    end
    L.WantedEvents(wanted, newMode, ownXP)
    if frame then
        for i = 1, #L.ALL_EVENTS do
            local e = L.ALL_EVENTS[i]
            if wanted[e] and not registered[e] then
                if L.UNIT_EVENTS[e] then
                    frame:RegisterUnitEvent(e, UNITS[1], UNITS[2], UNITS[3], UNITS[4])
                else
                    frame:RegisterEvent(e)
                end
                registered[e] = true
            elseif not wanted[e] and registered[e] then
                frame:UnregisterEvent(e)
                registered[e] = nil
            end
        end
    end
    mode = newMode
end

-- Works out the state from the settings and the game, and moves to it. A roster
-- read too early at login is read again through the login-known queue.
local function Reconcile(rosterEvent)
    local share = Get("xpPartyShare") == true
    local display = L.DisplayOn(Get("xpPartyCard") == true, Get("xpPartyMarkers") == true,
        Get("xpPartyTooltip") == true, Get("xpEnabled") == true, Get("xpTooltip") == true)
    local atMax, xpOff = false, false
    if share or display then
        local t = X.ReadXP()
        atMax, xpOff = t.atMax == true, t.xpOff == true
    end
    if (display or (share and not atMax)) and InPartyGroup() then
        RosterPass()
    else
        ClearRoster()
    end
    local was = mode
    local newMode = L.Gate(share, atMax, xpOff, inParty, memberBelowMax, display)
    SetMode(newMode, inParty and (share or display) and not atMax)
    L.SetSharing(s, newMode == "share")
    if Hearing() then
        local held = prefixHeld
        RegisterPrefix()
        local channel = CurrentChannel()
        if rosterEvent then Fire("roster") end
        if was ~= newMode or channel ~= lastChannel or prefixHeld ~= held then
            Fire("enter")
        elseif memberCount > lastCount then
            Fire("join")
        end
        lastChannel = channel
    else
        CancelTimer()
        L.Reset(s)
        lastChannel = nil
    end
    lastCount = memberCount
    RedrawAll()
end

-- Reconciles first: an event can read a level before the game reports it, and
-- the 2 seconds settle that. What the reconcile finds goes out in this slot, so a
-- timer it armed would retry past a refusal with no new trigger.
function Flush()
    timer = nil
    Reconcile()
    CancelTimer()
    if not (prefixHeld and Hearing()) then return end
    local level, cur, total = Read(UnitLevel, "player"), Read(UnitXP, "player"), (Read(UnitXPMax, "player"))
    local text = L.NextSend(s, ChatLocked(), level, cur, total)
    if not text then return end
    local channel = CurrentChannel()
    if not channel then
        L.OnResult(s, true, L.RESULT_NOT_IN_GROUP)
        return
    end
    local info = _G.C_ChatInfo
    local ok, result = false, nil
    if info and info.SendAddonMessage then ok, result = pcall(info.SendAddonMessage, L.PREFIX, text, channel) end
    if L.OnResult(s, ok, Plain(result)) then Arm() end
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------

local function OnMessage(prefix, text, channel, sender)
    if Plain(prefix) ~= L.PREFIX then return end
    channel, sender = Plain(channel), Plain(sender)
    if not L.AcceptChannel(channel) then return end
    local key = L.SenderKey(sender, (Read(GetNormalizedRealmName)))
    local m = key and byKey[key]
    if not m then return end
    local kind, level, cur, total = L.ParseMessage(Plain(text))
    if kind == "ask" then
        Fire("asked")
        return
    end
    if kind ~= "report" then return end
    local h = heard[key]
    if h and h.level == level and h.cur == cur and h.total == total then return end
    if not h then
        h = {}
        heard[key] = h
    end
    h.level, h.cur, h.total, h.pct = level, cur, total, cur * 100 / total
    ViewMember(m, X.LevelCap(), ChatLocked())
    BuildMarks()
    Publish()
end

function OnEvent(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        OnMessage(...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- A raid's roster traffic stops here.
        if mode == "watch" and not InPartyGroup() then return end
        Reconcile(true)
    elseif event == "PLAYER_XP_UPDATE" then
        anyBelowMax = ViewSelf(X.LevelCap()) or memberBelowMax
        Publish()
        Fire("xp")
    elseif event == "PLAYER_LEVEL_UP" then
        Reconcile()
        Fire("xp")
        if mode ~= "off" then Arm() end
    else
        Reconcile()
    end
end

---------------------------------------------------------------------------------
-- The funnel
---------------------------------------------------------------------------------

-- Nil with Party Markers off; the reused list otherwise.
function X.PartyMarkerList()
    if Get("xpPartyMarkers") ~= true then return nil end
    return marks
end

function X.PartyTooltipLines(tip)
    if not (tip and inParty) or Get("xpPartyTooltip") ~= true then return end
    local header = false
    for i = 1, #members do
        local m = members[i]
        if m.present then
            if not header then
                header = true
                tip:AddLine("Party", 1, 0.82, 0)
            end
            tip:AddLine(L.TooltipText(m.name, m.view), 1, 1, 1)
        end
    end
end

function X.PartyApply()
    Reconcile()
    X.PartyCardApply()
    if not loginQueued then
        loginQueued = true
        if ns.EUIWhenLoginKnown then ns.EUIWhenLoginKnown(X.PartyApply) end
    end
end

function X.PartyStop()
    CancelTimer()
    ClearRoster()
    L.Reset(s)
    lastChannel, lastCount = nil, 0
    SetMode("off", false)
    BuildRows()
    X.PartyCardRefresh(rows, 0, false)
    X.PartyCardStop()
    local w = X.LiveXPWidget()
    if w then X.SyncMarkers(w, Get, nil) end
end
