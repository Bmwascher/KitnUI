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
