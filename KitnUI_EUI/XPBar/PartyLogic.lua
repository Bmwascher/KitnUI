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

-- One "Name-Realm" for one player, whichever way the game spelled it.
function L.MemberKey(name, realm, myRealm)
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm end
    if type(myRealm) == "string" and myRealm ~= "" then return name .. "-" .. myRealm end
    return nil
end

function L.SenderKey(sender, myRealm)
    if type(sender) ~= "string" or sender == "" then return nil end
    if sender:find("-", 1, true) then return sender end
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

function L.TooltipText(name, row)
    return name .. ": " .. (row.text:gsub("  ", " "))
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
