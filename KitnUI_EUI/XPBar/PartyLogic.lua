-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/PartyLogic.lua                             ║
-- ║  Purpose: Party XP's decisions: the message format, names,   ║
-- ║           the gate, row text and the member merge. Pure: it  ║
-- ║           calls nothing in the game.                         ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
X.PartyLogic = X.PartyLogic or {}
local L = X.PartyLogic

local floor, max, min = math.floor, math.max, math.min
local format, match = string.format, string.match

L.PREFIX = "KitnUIXP"
L.SLOT = 2
L.VERSION = 1
L.ASK = "R"

-- Longer than any report, so a parse never reads an oversized string.
local MESSAGE_MAX = 40
local LEVEL_MAX, XP_MAX = 1000, 2147483647

local PREFIX_OK, PREFIX_DUPLICATE = 0, 1

---------------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------------

local function Whole(v)
    return type(v) == "number" and v == floor(v)
end

local function Sane(level, cur, total)
    return Whole(level) and Whole(cur) and Whole(total)
        and level >= 1 and level <= LEVEL_MAX
        and total >= 1 and total <= XP_MAX
        and cur >= 0 and cur <= total
end

function L.EncodeReport(level, cur, total)
    if not Sane(level, cur, total) then return nil end
    return format("%d %d %d %d", L.VERSION, level, cur, total)
end

-- "ask", or "report" with its three numbers, or nil.
function L.ParseMessage(text)
    if type(text) ~= "string" or #text > MESSAGE_MAX then return nil end
    if text == L.ASK then return "ask" end
    local version, level, cur, total = match(text, "^(%d+) (%d+) (%d+) (%d+)$")
    if not version or tonumber(version) ~= L.VERSION then return nil end
    level, cur, total = tonumber(level), tonumber(cur), tonumber(total)
    if not Sane(level, cur, total) then return nil end
    return "report", level, cur, total
end

function L.PrefixHeld(result)
    return result == PREFIX_OK or result == PREFIX_DUPLICATE
end

---------------------------------------------------------------------------------
-- Channels and names
---------------------------------------------------------------------------------

local ACCEPTED = { PARTY = true, INSTANCE_CHAT = true }

function L.AcceptChannel(channel)
    return channel ~= nil and ACCEPTED[channel] == true
end

function L.Channel(inInstanceGroup, inHomeGroup)
    if inInstanceGroup then return "INSTANCE_CHAT" end
    if inHomeGroup then return "PARTY" end
    return nil
end

-- One key for one player, whichever way the game spelled it. sep is set where
-- names are regional: the unit API's second return is a surname, and a sender
-- is the joined name with no realm.
function L.MemberKey(name, realm, myRealm, sep)
    if type(name) ~= "string" or name == "" then return nil end
    if sep then
        if type(realm) ~= "string" or realm == "" then return name end
        local tail = sep .. realm
        if name:sub(-#tail) == tail then return name end
        return name .. tail
    end
    if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm end
    if type(myRealm) == "string" and myRealm ~= "" then return name .. "-" .. myRealm end
    return nil
end

function L.SenderKey(sender, myRealm, sep)
    if type(sender) ~= "string" or sender == "" then return nil end
    if sep or sender:find("-", 1, true) then return sender end
    return L.MemberKey(sender, nil, myRealm)
end

---------------------------------------------------------------------------------
-- The gate
---------------------------------------------------------------------------------

function L.DisplayOn(card, markers, lines, xpBar, showTooltip)
    return card == true or (xpBar == true and (markers == true or (lines == true and showTooltip == true)))
end

function L.Gate(share, atMax, xpOff, inParty, memberBelowMax, displayOn)
    if not displayOn and (not share or atMax) then return "off" end
    if not inParty then return "watch" end
    if share and not atMax and not xpOff then return "share" end
    if displayOn and memberBelowMax then return "listen" end
    return "roster"
end

local OWN_XP = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN" }

L.UNIT_EVENTS = { UNIT_LEVEL = true, UNIT_CONNECTION = true, UNIT_NAME_UPDATE = true }
L.ALL_EVENTS = { "GROUP_ROSTER_UPDATE", "UNIT_LEVEL", "UNIT_CONNECTION", "UNIT_NAME_UPDATE", "CHAT_MSG_ADDON" }
for i = 1, #OWN_XP do L.ALL_EVENTS[#L.ALL_EVENTS + 1] = OWN_XP[i] end

-- ownXP: in a party below max level, for the report, the player's own row and
-- noticing XP gain change.
function L.WantedEvents(out, mode, ownXP)
    for i = 1, #L.ALL_EVENTS do out[L.ALL_EVENTS[i]] = nil end
    if mode == "off" then return out end
    out.GROUP_ROSTER_UPDATE = true
    if mode == "watch" then return out end
    for e in pairs(L.UNIT_EVENTS) do out[e] = true end
    if mode ~= "roster" then out.CHAT_MSG_ADDON = true end
    if ownXP then
        for i = 1, #OWN_XP do out[OWN_XP[i]] = true end
    end
    return out
end

---------------------------------------------------------------------------------
-- Displays
---------------------------------------------------------------------------------

function L.CardShown(cardOn, inParty, anyBelowMax, rowCount)
    return cardOn == true and inParty == true and anyBelowMax == true and rowCount > 0
end

-- Fills out.kind, out.pct and out.text. A heard pair holds only at the game's
-- level, or inside a chat lock, where nothing newer can come.
function L.RowView(out, m, heard, cap, locked)
    out.pct = 0
    if not m.online then
        out.kind, out.text = "offline", "offline"
    elseif cap and m.level >= cap then
        out.kind, out.pct, out.text = "max", 100, format("Lv %d  Max", m.level)
    elseif heard and (heard.level == m.level or locked) then
        out.kind, out.pct, out.text = "data", heard.pct, format("Lv %d  %.1f%%", heard.level, heard.pct)
    else
        out.kind, out.text = "nodata", format("Lv %d  no data", m.level)
    end
    return out
end

function L.TooltipStatus(row)
    return (row.text:gsub("  ", " "))
end

function L.LabelText(name, level, style)
    if style == "off" then return nil end
    if style == "name" then return name end
    return format("%s Lv %d", name, level)
end

-- The tick's left edge in pixels, inside the bar.
function L.MarkerX(pct, barW, tickW, px)
    local most = floor((barW - tickW) / px) * px
    return max(0, min(floor((pct / 100 * barW - tickW / 2) / px + 0.5) * px, most))
end

-- A tick's width in whole physical pixels, px being the size of one.
function L.MarkerWidth(tickW, px)
    return max(px, floor(tickW / px + 0.5) * px)
end

---------------------------------------------------------------------------------
-- The member merge
---------------------------------------------------------------------------------

-- prev: the row this unit already has, or nil. A name, class or level that
-- does not read leaves a shown row as it is and adds none.
function L.MergeMember(prev, exists, isFollower, name, class, level)
    if not exists or isFollower then return "drop" end
    if name == nil or class == nil or type(level) ~= "number" or level <= 0 then
        return prev and "keep" or "none"
    end
    return "set"
end

---------------------------------------------------------------------------------
-- The refusal state machine
---------------------------------------------------------------------------------

local RESULT_OK, RESULT_THROTTLE, RESULT_CHANNEL_THROTTLE, RESULT_LOCKDOWN = 0, 3, 8, 11
L.RESULT_NOT_IN_GROUP = 5

-- s: sharing, askDue, reportDue, force, gated, what is being sent and the last
-- values sent. Holding is no state of its own: what a lock or a refusal leaves
-- due stays due with no slot armed, and the next trigger arms one.

function L.Reset(s)
    for k in pairs(s) do s[k] = nil end
end

function L.SetSharing(s, on)
    s.sharing = on
    if not on then s.reportDue, s.force = false, false end
end

function L.Due(s)
    return s.askDue == true or s.reportDue == true
end

-- Returns true when a slot should be armed. A roster event sends only what it
-- released, so a bare one is no trigger for a held send. Being gated dropped the
-- ask with the rest, so the release asks again, a non-sharer included.
function L.Trigger(s, kind)
    if kind == "roster" then
        if not s.gated then return false end
        s.gated = false
        s.askDue = true
        if s.sharing then s.reportDue, s.force = true, true end
        return true
    end
    if s.gated then return false end
    if kind == "xp" then
        if s.sharing then s.reportDue = true end
    elseif kind == "join" or kind == "asked" then
        if s.sharing then s.reportDue, s.force = true, true end
    elseif kind == "enter" then
        s.askDue = true
        if s.sharing then s.reportDue, s.force = true, true end
    end
    return L.Due(s)
end

-- The text to send now, or nil. An ask goes first, and a locked flush changes
-- nothing. An unchanged report with nothing forcing it is spent here: that is
-- "only while XP changes".
function L.NextSend(s, locked, level, cur, total)
    s.sending = nil
    if locked then return nil end
    if s.askDue then
        s.sending = "ask"
        return L.ASK
    end
    if not s.reportDue then return nil end
    local text = L.EncodeReport(level, cur, total)
    local unchanged = not s.force and s.sentLevel == level and s.sentCur == cur and s.sentTotal == total
    if not text or unchanged then
        s.reportDue, s.force = false, false
        return nil
    end
    s.sending, s.tryLevel, s.tryCur, s.tryTotal = "report", level, cur, total
    return text
end

local function Spend(s, sending)
    if sending == "ask" then
        s.askDue = false
    elseif sending == "report" then
        s.reportDue, s.force = false, false
    end
end

-- Returns true when another slot should be armed.
function L.OnResult(s, ok, result)
    local sending = s.sending
    s.sending = nil
    if ok and result == RESULT_LOCKDOWN then return false end
    if ok and (result == RESULT_THROTTLE or result == RESULT_CHANNEL_THROTTLE) then return true end
    if ok and result == L.RESULT_NOT_IN_GROUP then
        s.askDue, s.reportDue, s.force = false, false, false
        s.gated = true
        return false
    end
    Spend(s, sending)
    if ok and result == RESULT_OK and sending == "report" then
        s.sentLevel, s.sentCur, s.sentTotal = s.tryLevel, s.tryCur, s.tryTotal
    end
    return L.Due(s)
end

