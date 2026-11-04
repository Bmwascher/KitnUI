-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Math.lua                                   ║
-- ║  Purpose: Pure arithmetic and text for the XP and faction    ║
-- ║           bars. No WoW call, so the headless tests load it.  ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}

local M = {}
ns.XPBar.Math = M

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local format = string.format

-- How many kill messages the retail average keeps.
M.KILL_SAMPLES = 10
-- A save older than this, in seconds, belongs to an earlier session, so a
-- /reload after it starts fresh.
M.SESSION_RELOAD_WINDOW = 300
-- The card's arrow: the share two windows' rates must differ by, how long a
-- window is in seconds, and the share of a window it may close late and still
-- count. A later close means the card missed its end.
M.TREND_SHARE = 0.05
M.TREND_WINDOW = 180
M.TREND_LATE_SHARE = 0.25

local function Round1(n) return floor(n * 10 + 0.5) / 10 end

-- The fill, and where the completed-quest and rested segments end, in
-- percent. Each segment starts where the one before it ends and is capped so
-- the stack never passes 100.
function M.Stack(cur, maxXP, quest, rested, showQuest)
    if type(maxXP) ~= "number" or maxXP <= 0 then return 0, 0, 0 end
    local xp = min(100, max(0, (cur or 0) * 100 / maxXP))
    local q = showQuest and min(max(0, (quest or 0) * 100 / maxXP), 100 - xp) or 0
    local r = min(max(0, (rested or 0) * 100 / maxXP), 100 - xp - q)
    return xp, xp + q, xp + q + r
end

function M.PercentText(xpPct, projected)
    local earned = Round1(xpPct or 0)
    local total = Round1(min(projected or 0, 100))
    if total > earned then return format("%.1f%% (%.1f%%)", earned, total) end
    return format("%.1f%%", earned)
end

local function Commas(n)
    local s = tostring(floor(n))
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. grouped
end

function M.Short(n)
    n = tonumber(n) or 0
    if n >= 1e6 then return format("%.1fM", n / 1e6) end
    if n >= 1e3 then return format("%.1fK", n / 1e3) end
    return tostring(floor(n))
end

-- style: "full" (separators, from breakUp when given), "plain" or "short".
function M.Number(n, style, breakUp)
    n = tonumber(n) or 0
    if style == "short" then return M.Short(n) end
    if style == "plain" then return tostring(floor(n)) end
    if type(breakUp) == "function" then
        local ok, s = pcall(breakUp, floor(n))
        if ok and type(s) == "string" then return s end
    end
    return Commas(n)
end

function M.AmountText(cur, maxXP, style, showRemaining, breakUp)
    local text = M.Number(cur, style, breakUp) .. " / " .. M.Number(maxXP, style, breakUp)
    if showRemaining then
        text = text .. " (" .. M.Number(max(0, (maxXP or 0) - (cur or 0)), style, breakUp) .. ")"
    end
    return text
end

function M.TimeText(sec)
    sec = tonumber(sec)
    if not sec or sec <= 0 then return "--" end
    if sec < 60 then return "< 1m" end
    local d = floor(sec / 86400)
    local h = floor((sec % 86400) / 3600)
    local m = floor((sec % 3600) / 60)
    if d > 0 then return format("%dd %dh %dm", d, h, m) end
    if h > 0 then return format("%dh %dm", h, m) end
    return format("%dm", m)
end

-- XP per hour and seconds to level, or nil before anything is gained. The
-- elapsed time counts as at least a minute, so one early kill does not read
-- as an enormous rate.
function M.Rate(gained, elapsed, remaining)
    if type(gained) ~= "number" or gained <= 0 then return nil end
    local secs = max(60, tonumber(elapsed) or 0)
    local perHour = gained * 3600 / secs
    local eta = 0
    if type(remaining) == "number" and remaining > 0 then eta = ceil(remaining * 3600 / perHour) end
    return perHour, eta
end

-- Width caps for the texts inside a bar, left, center and right; nil means
-- no cap, and a nil width means there is no such text. avail is the bar's
-- width less a pad at each end. The center text stays centered, so each side
-- text gets only its own half of the room beside it, whatever the other side
-- leaves free. Without a center text the two side texts share the bar.
function M.InsideCaps(avail, pad, lw, cw, rw)
    if cw then
        local capC = cw > avail and max(1, avail) or nil
        local side = (avail - min(cw, avail)) / 2 - pad
        return (lw and lw > side) and side or nil, capC, (rw and rw > side) and side or nil
    end
    if not (lw and rw) then
        return (lw and lw > avail) and avail or nil, nil, (rw and rw > avail) and avail or nil
    end
    if lw + rw + pad <= avail then return nil, nil, nil end
    local capL = max((avail - pad) / 2, avail - pad - rw)
    local capR = avail - pad - min(lw, capL)
    return (lw > capL) and capL or nil, nil, (rw > capR) and capR or nil
end

-- One reading per call; returns the XP gained since the last one, and the
-- level counted to when this reading counted a level-up. Within a level the
-- XP sums signed, reading to reading, so a mixed reading still adds up. A
-- level-up arrives as two signals, the total changing and the level rising,
-- in either order: the first counts the level once (the rest of the old
-- level plus the XP read now), the second counts nothing. Equal totals are
-- told apart by the level number; several levels in one step count as one.
-- s: x, m, level (the last reading, at the counted level), wait ("total"
-- while the counted level's new total is still due).
function M.Track(s, cur, total, level)
    if type(cur) ~= "number" or type(total) ~= "number" or type(level) ~= "number" then return 0 end
    if s.x == nil then
        s.x, s.m, s.level, s.wait = cur, total, level, nil
        return 0
    end
    local moved, rose = total ~= s.m, level > s.level
    local gain, upTo = cur - s.x, nil
    if rose or (moved and s.wait ~= "total") then
        gain = (s.m - s.x) + cur
        upTo = rose and level or s.level + 1
        s.level, s.wait = upTo, (rose and not moved) and "total" or nil
    elseif moved then
        s.wait = nil
    end
    s.x, s.m = cur, total
    return gain, upTo
end

-- Kills to level when each kill gives perKill and rested XP doubles a kill
-- until it runs out. Retail passes rested = 0: its perKill is an average of
-- whole kill messages, which already include any rested bonus.
function M.KillsToLevel(left, rested, perKill)
    if type(perKill) ~= "number" or perKill <= 0 then return nil end
    left = max(0, tonumber(left) or 0)
    rested = max(0, tonumber(rested) or 0)
    local boosted = min(ceil(left / (2 * perKill)), floor(rested / perKill))
    return boosted + max(0, ceil((left - boosted * 2 * perKill) / perKill))
end

function M.ForeverKillXP(level)
    return 45 + 5 * (tonumber(level) or 0)
end

function M.PushKill(list, xp)
    list[#list + 1] = xp
    while #list > M.KILL_SAMPLES do table.remove(list, 1) end
end

function M.KillAverage(list)
    local n = type(list) == "table" and #list or 0
    if n == 0 then return nil end
    local sum = 0
    for i = 1, n do sum = sum + list[i] end
    return sum / n
end

function M.CompRestedText(compPct, restPct)
    return format("Completed: |cFFFF9700%.1f%%|r - Rested: |cFF4F90FF%.1f%%|r", compPct or 0, restPct or 0)
end

-- rec: { kind, name, label, cur, min, max, isMax, paragon }. Returns the
-- percent, the progress and span within the current rank, and the left and
-- right texts.
function M.FactionProgress(rec)
    if type(rec) ~= "table" then return nil end
    local lo, hi, cur = tonumber(rec.min) or 0, tonumber(rec.max) or 0, tonumber(rec.cur) or 0
    local span, inSpan = hi - lo, cur - lo
    local pct
    if rec.isMax then
        pct, inSpan = 100, span
    elseif span > 0 then
        pct = min(100, max(0, inSpan * 100 / span))
    else
        pct = 0
    end
    local left = format("%s - %s - %.1f%%", tostring(rec.name or ""), tostring(rec.label or ""), pct)
    local right = span > 0 and format("(%s / %s)", M.Short(inSpan), M.Short(span)) or ""
    return pct, inSpan, span, left, right
end

-- A saved session continues only after a /reload, with the reset switch off,
-- from a save made within the window.
function M.ShouldContinue(kind, resetOnReload, savedAt, now, window)
    if kind ~= "reload" or resetOnReload then return false end
    if type(savedAt) ~= "number" or type(now) ~= "number" then return false end
    local gap = now - savedAt
    return gap >= 0 and gap <= (window or M.SESSION_RELOAD_WINDOW)
end

local killFormat, killPattern

-- A client format string ("%s dies, you gain %d experience.") as a Lua
-- pattern. Only the start is anchored: a rested kill appends its bonus.
local function KillPattern(fmt)
    if fmt ~= killFormat then
        local p = fmt:gsub("%%%d%$", "%%")
        p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
        p = p:gsub("%%s", "(.-)")
        p = p:gsub("%%d", "(%%d+)")
        killFormat, killPattern = fmt, "^" .. p
    end
    return killPattern
end

-- The XP a kill message names, whole, or nil for secret or other text.
function M.ParseKill(text, fmt, isSecret)
    if isSecret and isSecret(text) then return nil end
    if type(text) ~= "string" or type(fmt) ~= "string" then return nil end
    local a, b = text:match(KillPattern(fmt))
    local n = tonumber(b) or tonumber(a)
    if not n or n <= 0 then return nil end
    return floor(n)
end

-- One XP reading against the effects' own kept one, compared only within one
-- level and one total. Returns the gain and its span in percent, or nil. XP only
-- falls at a level-up. s: x, m, level, and for M.QuestSpan the last rise or
-- level-up reading (gainAt, gainBase, gainFrom, gainTo).
function M.XPGainStep(s, cur, total, level, now)
    if type(cur) ~= "number" or type(total) ~= "number" or type(level) ~= "number" then return nil end
    local x, m, l = s.x, s.m, s.level
    s.x, s.m, s.level = cur, total, level
    if x == nil then return nil end
    if m ~= total or l ~= level or cur < x then
        local fill = total > 0 and min(100, cur * 100 / total) or 0
        s.gainAt, s.gainBase, s.gainFrom, s.gainTo = now, 0, 0, fill
        return nil
    end
    if total <= 0 or cur == x then return nil end
    local from, to = min(100, x * 100 / total), min(100, cur * 100 / total)
    s.gainAt, s.gainBase, s.gainFrom, s.gainTo = now, x, from, to
    return cur - x, from, to
end

-- Where a turn-in's gain sits on the bar, in percent, read against the kept
-- reading since the game can report the event and the XP in either order. Past
-- a level-up it draws only what is on the bar after it. It only places the gain:
-- every turn-in has a place.
function M.QuestSpan(s, cur, total, level, reward, now, window)
    if type(cur) ~= "number" or type(total) ~= "number" or type(reward) ~= "number" or total <= 0 then return nil end
    local x = s.x
    local fill = min(100, cur * 100 / total)
    if x == nil or s.level ~= level or s.m ~= total or cur < x then return 0, fill end
    if cur > x then return min(100, x * 100 / total), fill end
    if s.gainAt and now - s.gainAt <= window and s.gainBase + reward < total then
        return s.gainFrom, s.gainTo
    end
    local after = cur + reward
    if after >= total then return 0, min(100, (after - total) * 100 / total) end
    return fill, after * 100 / total
end

-- One reputation reading against the kept one: "rank", or "gain" with the
-- amount and the percent it began at, or nil. A nil id, a new id or a change
-- of kind only seeds, but a track turning into paragon has just finished its
-- last rank. s: id, kind, rank, total, pct.
function M.FactionStep(s, id, kind, rank, total, pct, isMax)
    local lastID, lastKind, lastRank, lastTotal, lastPct = s.id, s.kind, s.rank, s.total, s.pct
    s.id, s.kind, s.rank, s.total, s.pct = id, kind, rank, total, pct
    if id == nil or id ~= lastID then return nil end
    if kind ~= lastKind then return kind == "paragon" and "rank" or nil end
    if type(rank) == "number" and type(lastRank) == "number" then
        if rank > lastRank then return "rank" end
        if rank < lastRank then return nil end
    elseif rank ~= lastRank then
        return nil
    end
    if not isMax and type(total) == "number" and type(lastTotal) == "number" and total > lastTotal then
        return "gain", total - lastTotal, lastPct or 0
    end
    return nil
end

-- A span's left and width in pixels: at least minW, inside the bar, growing
-- left from its end when too short.
function M.EffectSpan(fromPct, toPct, barW, minW)
    local left = max(0, min(100, tonumber(fromPct) or 0)) * barW / 100
    local right = max(0, min(100, tonumber(toPct) or 0)) * barW / 100
    if right < left then left, right = right, left end
    local width = right - left
    local least = min(minW or 0, barW)
    if width < least then
        width = least
        left = max(0, min(barW - width, right - width))
    end
    return left, width
end

function M.AmountX(pct, barW, margin)
    if barW < 2 * margin then return barW / 2 end
    return max(margin, min(barW - margin, (tonumber(pct) or 0) * barW / 100))
end

-- From absolute x, so a repeating tile stays still as its segment grows and
-- every gap's copy of the segment lines up.
function M.StripeCoords(leftPx, rightPx, tile)
    local size = max(1, tonumber(tile) or 1)
    return leftPx / size, rightPx / size
end

function M.ReadyToLevel(cur, total, quest)
    if type(cur) ~= "number" or type(total) ~= "number" or type(quest) ~= "number" then return false end
    return total > 0 and quest > 0 and quest >= total - cur
end

function M.Lift(c)
    return min(1, (tonumber(c) or 0) * 1.6)
end

function M.RateText(perHour)
    return M.Short(perHour) .. " xp/hr"
end

function M.ClockText(sec)
    sec = tonumber(sec)
    if not sec or sec < 0 then return "--" end
    sec = floor(sec)
    local h, m, s = floor(sec / 3600), floor((sec % 3600) / 60), sec % 60
    if h > 0 then return format("%d:%02d:%02d", h, m, s) end
    return format("%d:%02d", m, s)
end

-- Compares each window's rate with the one before it, not with the running
-- session rate, which flattens late in a long session. Elapsed comes from the
-- session, so a pause freezes it. A nil at, falling numbers or a window closing
-- too late starts it over. s: at, gained, rate, dir.
function M.Trend(s, gained, elapsed, window)
    if type(gained) ~= "number" or type(elapsed) ~= "number" then return s.dir end
    if s.at == nil or elapsed < s.at or gained < s.gained
        or elapsed - s.at > window * (1 + M.TREND_LATE_SHARE) then
        s.at, s.gained, s.rate, s.dir = elapsed, gained, nil, nil
        return nil
    end
    local span = elapsed - s.at
    if span < window then return s.dir end
    local rate = (gained - s.gained) / span
    local prev = s.rate
    s.at, s.gained, s.rate, s.dir = elapsed, gained, rate, nil
    if prev and prev > 0 then
        if rate > prev * (1 + M.TREND_SHARE) then
            s.dir = "up"
        elseif rate < prev * (1 - M.TREND_SHARE) then
            s.dir = "down"
        end
    end
    return s.dir
end

function M.TickerWidth(fontSize)
    return floor((tonumber(fontSize) or 12) * 22 + 0.5)
end

function M.RowHeight(fontSize)
    return ceil((tonumber(fontSize) or 12) * 1.4)
end

-- The whole seconds spent in newLevel - 1, from the running clock, else the
-- clock a reading-first level-up held; nil when neither is that level's.
function M.LevelSplit(newLevel, levelOf, levelStart, heldOf, heldStart, now)
    if type(newLevel) ~= "number" or type(now) ~= "number" then return nil end
    local done = newLevel - 1
    local start = (levelStart and levelOf == done) and levelStart or (heldStart and heldOf == done) and heldStart or nil
    if not start then return nil end
    return max(0, floor(now - start + 0.5))
end

-- How far ahead of a character the player is at this point in the level: at
-- and nextAt are that character's total played on reaching this level and the
-- next, and share is how far through the level the player is.
function M.PaceGap(myTotal, share, at, nextAt)
    if type(myTotal) ~= "number" or type(share) ~= "number" or type(at) ~= "number" or type(nextAt) ~= "number" then
        return nil
    end
    if nextAt < at then return nil end
    return at + share * (nextAt - at) - myTotal
end

function M.PaceText(gap)
    if type(gap) ~= "number" then return "--" end
    return M.TimeText(max(1, math.abs(gap))) .. (gap >= 0 and " ahead" or " behind")
end
