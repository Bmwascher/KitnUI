-- ╔══════════════════════════════════════════════════════════════╗
-- ║  xpbar-math.lua                                              ║
-- ║  Purpose: Gate for the XP bars' pure arithmetic and text.    ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/xpbar-math.lua

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

local ns = {}
local chunk, err = loadfile("KitnUI_EUI/XPBar/Math.lua")
if not chunk then
    print("FAIL  could not load KitnUI_EUI/XPBar/Math.lua: " .. tostring(err))
    os.exit(1)
end
chunk("KitnUI_EUI", ns)
local M = ns.XPBar and ns.XPBar.Math
if not M then
    print("FAIL  Math.lua did not publish ns.XPBar.Math")
    os.exit(1)
end

-- Stack
local a, b, c = M.Stack(45000, 100000, 15000, 25000, true)
eq(a, 45, "stack: the fill")
eq(b, 60, "stack: quest XP ends after the fill")
eq(c, 85, "stack: rested ends after the quest XP")
b, c = select(2, M.Stack(45000, 100000, 15000, 25000, false))
eq(b, 45, "stack: with the overlay off there is no quest segment")
eq(c, 70, "stack: and rested follows the fill")
a, b, c = M.Stack(90, 100, 20, 30, true)
eq(a, 90, "stack: overflow keeps the fill")
eq(b, 100, "stack: the quest segment stops at 100")
eq(c, 100, "stack: and so does rested")
a = M.Stack(10, 0, 0, 0, true)
eq(a, 0, "stack: no XP max draws nothing")

-- PercentText
eq(M.PercentText(45, 85), "45.0% (85.0%)", "percent: with a projection")
eq(M.PercentText(45, 45), "45.0%", "percent: without one")
eq(M.PercentText(45, 44), "45.0%", "percent: a smaller projection is left out")
eq(M.PercentText(90, 130), "90.0% (100.0%)", "percent: the projection caps at 100")

-- Numbers
eq(M.Number(45000, "full"), "45,000", "number: full with separators")
eq(M.Number(1234567, "full"), "1,234,567", "number: full with two separators")
eq(M.Number(45000, "full", function(n) return "B" .. n end), "B45000", "number: full uses the client's formatter when given")
eq(M.Number(45000, "plain"), "45000", "number: plain")
eq(M.Number(45000, "short"), "45.0K", "number: short")
eq(M.AmountText(45000, 100000, "full", true), "45,000 / 100,000 (55,000)", "amount: full with remaining")
eq(M.AmountText(45000, 100000, "plain", false), "45000 / 100000", "amount: plain without remaining")
eq(M.AmountText(45000, 100000, "short", true), "45.0K / 100.0K (55.0K)", "amount: short")
eq(M.Short(6500), "6.5K", "short: 6500")
eq(M.Short(10000), "10.0K", "short: 10000")
eq(M.Short(90000), "90.0K", "short: 90000")
eq(M.Short(1200000), "1.2M", "short: 1.2M")
eq(M.Short(950), "950", "short: under a thousand")

-- TimeText
eq(M.TimeText(0), "--", "time: nothing")
eq(M.TimeText(59), "< 1m", "time: under a minute")
eq(M.TimeText(2160), "36m", "time: minutes")
eq(M.TimeText(3600), "1h 0m", "time: an hour")
eq(M.TimeText(93780), "1d 2h 3m", "time: days")

-- Rate
eq(M.Rate(0, 100, 10), nil, "rate: nothing gained gives no rate")
local perHour, eta = M.Rate(1500, 30, 1000)
eq(perHour, 90000, "rate: the elapsed time counts as at least a minute")
eq(eta, 40, "rate: seconds to level")

-- Inside texts: no two may cross
local capL, capC, capR = M.InsideCaps(500, 6, 70, 250, 150)
eq(capL, nil, "inside: a short left text keeps its width")
eq(capC, nil, "inside: the center text fits")
eq(capR, 119, "inside: the right text is held to its own half beside the center")
capL, capC, capR = M.InsideCaps(500, 6, 100, 200, 100)
check(capL == nil and capC == nil and capR == nil, "inside: texts that fit are left alone")
capL, capC = M.InsideCaps(100, 6, 40, 300, 40)
eq(capC, 100, "inside: a center text wider than the bar is capped to it")
eq(capL, -6, "inside: and the side texts have no room left")
capL, capC, capR = M.InsideCaps(200, 6, 150, nil, 150)
eq(capL, 97, "inside: without a center, two long side texts share the bar")
eq(capC, nil, "inside: with no center cap")
eq(capR, 97, "inside: each taking half")
capL, capC, capR = M.InsideCaps(200, 6, 40, nil, 180)
eq(capL, nil, "inside: a short side text keeps its width")
eq(capC, nil, "inside: no center text, no center cap")
eq(capR, 154, "inside: and the long one takes the rest")
capL = M.InsideCaps(200, 6, 250, nil, nil)
eq(capL, 200, "inside: a lone text wider than the bar is capped to it")

-- Track: one reading per event. A level-up changes the XP, the level's total
-- and the level, and the client may report them in any order, with every
-- mixed reading in between. Each order must add up to the true gain, 200
-- (100 to finish level 10, then 100 into level 11), and leave the tracker
-- right for the next level. Each order also runs with one of its two mixed
-- readings unseen, and with both, so the level-up arrives as one reading.
local OLD, NEW = { 900, 1000, 10 }, { 100, 1200, 11 }
local function mixed(xpNew, maxNew, levelNew)
    return { xpNew and NEW[1] or OLD[1], maxNew and NEW[2] or OLD[2], levelNew and NEW[3] or OLD[3] }
end
local ORDERS = {
    { "xp, total, level", { mixed(true, false, false), mixed(true, true, false) } },
    { "xp, level, total", { mixed(true, false, false), mixed(true, false, true) } },
    { "total, xp, level", { mixed(false, true, false), mixed(true, true, false) } },
    { "total, level, xp", { mixed(false, true, false), mixed(false, true, true) } },
    { "level, xp, total", { mixed(false, false, true), mixed(true, false, true) } },
    { "level, total, xp", { mixed(false, false, true), mixed(false, true, true) } },
}
local function run(steps)
    local s, total = {}, 0
    M.Track(s, OLD[1], OLD[2], OLD[3])
    for _, r in ipairs(steps) do total = total + M.Track(s, r[1], r[2], r[3]) end
    total = total + M.Track(s, NEW[1], NEW[2], NEW[3])
    total = total + M.Track(s, NEW[1], NEW[2], NEW[3])
    local after = M.Track(s, 150, 1200, 11)
    local next1 = M.Track(s, 1150, 1200, 11)
    local next2 = M.Track(s, 10, 1500, 12)
    return total, after, next1 + next2
end
for _, order in ipairs(ORDERS) do
    local name, steps = order[1], order[2]
    for skip = 0, 3 do
        local used = {}
        for i, r in ipairs(steps) do
            if skip == 0 or (skip ~= i and skip ~= 3) then used[#used + 1] = r end
        end
        local label = "track " .. name .. ((skip == 3 and ", both unseen")
            or (skip > 0 and (", reading " .. skip .. " unseen")) or "")
        local total, after, nextLevel = run(used)
        eq(total, 200, label .. ": the level counts once")
        eq(after, 50, label .. ": later XP counts")
        eq(nextLevel, 1060, label .. ": the next level uses the new total")
    end
end

-- Mixed-reading sequences, as { readings, the true gain }. The first
-- reading is the baseline.
local function sum(readings)
    local s, total = {}, 0
    for _, r in ipairs(readings) do total = total + M.Track(s, r[1], r[2], r[3]) end
    return total
end
eq(sum({ { 100, 1000, 10 }, { 200, 1000, 10 }, { 200, 1200, 10 }, { 200, 1200, 11 } }), 1100,
    "track: XP gained, then the total, then the level")
eq(sum({ { 100, 1000, 10 }, { 200, 1000, 10 }, { 200, 1000, 11 }, { 200, 1200, 11 } }), 1100,
    "track: XP gained, then the level, then the total")
eq(sum({ { 900, 1000, 10 }, { 100, 1000, 10 }, { 100, 1200, 10 }, { 100, 1200, 11 } }), 200,
    "track: the XP drops before the total changes")
eq(sum({ { 900, 1000, 10 }, { 900, 1200, 11 }, { 100, 1200, 11 } }), 200,
    "track: the total and level together, the XP after")
eq(sum({ { 900, 1000, 10 }, { 100, 1000, 11 }, { 950, 1000, 11 }, { 50, 1000, 12 } }), 1150,
    "track: two levels with equal totals are counted by the level number")

local s = {}
eq(M.Track(s, 900, 1000, 10), 0, "track: the first reading is the baseline")
eq(select(2, M.Track(s, 900, 1200, 10)), 11, "track: the first signal counts the level it names")
eq(select(2, M.Track(s, 900, 1200, 11)), nil, "track: the second signal counts no level")
eq(M.Track(s, 900, 1200, 10), 0, "track: a stale old level changes nothing")
s = {}
M.Track(s, 900, 1000, 10)
eq(select(2, M.Track(s, 900, 1000, 11)), 11, "track: a level rising first counts the level")
eq(select(2, M.Track(s, 100, 1200, 11)), nil, "track: and its total then counts no level")
s = {}
M.Track(s, 100, 1000, 10)
eq(M.Track(s, 100, 1000, 10), 0, "track: a repeated reading adds nothing")
eq(M.Track(s, 300, 1000, 10), 200, "track: within a level")
eq(M.Track(s, nil, 1000, 10), 0, "track: a missing reading adds nothing")

-- Kills
eq(M.KillsToLevel(1000, 0, 100), 10, "kills: no rested XP")
eq(M.KillsToLevel(1000, 300, 100), 7, "kills: partial rested XP")
eq(M.KillsToLevel(1000, 5000, 100), 5, "kills: rested XP covers everything")
eq(M.KillsToLevel(1000, 0, 300), 4, "kills: the retail form rounds up")
eq(M.KillsToLevel(1000, 0, 0), nil, "kills: no XP per kill gives no estimate")
eq(M.ForeverKillXP(60), 345, "kills: the Forever formula")
local list = {}
for i = 1, 12 do M.PushKill(list, i) end
eq(#list, 10, "kills: the ring keeps ten")
eq(list[1], 3, "kills: the oldest go first")
eq(M.KillAverage(list), 7.5, "kills: the average")
eq(M.KillAverage({}), nil, "kills: no kills give no average")

-- Kill messages
local FMT = "%s dies, you gain %d experience."
eq(M.ParseKill("Meandering Shalehorn dies, you gain 922 experience.", FMT), 922, "kill text: the probed message")
eq(M.ParseKill("Alert Shalehorn dies, you gain 1383 experience. (+461 exp Rested bonus)", FMT), 1383,
    "kill text: a rested kill counts whole")
eq(M.ParseKill("You receive loot.", FMT), nil, "kill text: other text")
eq(M.ParseKill("Meandering Shalehorn dies, you gain 922 experience.", FMT, function() return true end), nil,
    "kill text: secret text")
eq(M.ParseKill("Meandering Shalehorn dies, you gain 922 experience.", nil), nil, "kill text: no format")

-- Faction progress
local pct, inSpan, span, left, right = M.FactionProgress({ kind = "standard", name = "Stormwind", label = "Honored",
    cur = 9500, min = 9000, max = 21000 })
eq(inSpan, 500, "faction standard: progress in the rank")
eq(span, 12000, "faction standard: the rank's span")
eq(left, "Stormwind - Honored - 4.2%", "faction standard: left text")
eq(right, "(500 / 12.0K)", "faction standard: right text")
check(pct > 4.16 and pct < 4.17, "faction standard: percent", pct)
left, right = select(4, M.FactionProgress({ kind = "friendship", name = "Delve Companion", label = "Level 20",
    cur = 6500, min = 0, max = 10000 }))
eq(left, "Delve Companion - Level 20 - 65.0%", "faction friendship: left text")
eq(right, "(6.5K / 10.0K)", "faction friendship: right text")
local fp = { M.FactionProgress({ kind = "renown", name = "Council", label = "Renown 7", cur = 1500, min = 0, max = 2500 }) }
eq(fp[1], 60, "faction renown: percent")
eq(fp[4], "Council - Renown 7 - 60.0%", "faction renown: left text")
fp = { M.FactionProgress({ kind = "paragon", name = "Council", label = "Paragon", cur = 4000, min = 0,
    max = 10000, paragon = { pending = true } }) }
eq(fp[1], 40, "faction paragon: percent")
eq(fp[5], "(4.0K / 10.0K)", "faction paragon: right text")
fp = { M.FactionProgress({ kind = "standard", name = "Old", label = "Exalted", cur = 42000, min = 42000,
    max = 42000, isMax = true }) }
eq(fp[1], 100, "faction max: full")
eq(fp[5], "", "faction max: no amount")
eq(M.FactionProgress(nil), nil, "faction: no record")

-- Completed and rested line
local line = M.CompRestedText(15, 25)
check(line:find("15.0%", 1, true) and line:find("25.0%", 1, true), "completed and rested: both percents", line)
check(line:find(" - ", 1, true) ~= nil, "completed and rested: an ASCII hyphen between them", line)
local ascii = true
for i = 1, #line do if line:byte(i) > 127 then ascii = false end end
check(ascii, "completed and rested: ASCII only")

-- Session continuation
eq(M.ShouldContinue("reload", false, 4800, 5000, 300), true, "session: a reload within the window continues")
eq(M.ShouldContinue("login", false, 4800, 5000, 300), false, "session: a login starts fresh")
eq(M.ShouldContinue("reload", true, 4800, 5000, 300), false, "session: reset on reload starts fresh")
eq(M.ShouldContinue("reload", false, 4000, 5000, 300), false, "session: an old save starts fresh")
eq(M.ShouldContinue("reload", false, nil, 5000, 300), false, "session: no save starts fresh")

-- One reading against the effects' own kept one
do
    local kept = {}
    eq(M.XPGainStep(kept, 100, 1000, 10), nil, "gain step: a first reading seeds")
    local gain, from, to = M.XPGainStep(kept, 150, 1000, 10)
    eq(gain, 50, "gain step: a rise returns the gain")
    eq(from, 10, "gain step: and where it began, in percent")
    eq(to, 15, "gain step: and where it ended")
    eq(M.XPGainStep(kept, 150, 1000, 10), nil, "gain step: a repeated reading returns nil")
    eq(M.XPGainStep(kept, 120, 1000, 10), nil, "gain step: a fall returns nil")
    eq(M.XPGainStep(kept, 130, 1200, 10), nil, "gain step: a new total returns nil")
    eq(M.XPGainStep(kept, 140, 1200, 11), nil, "gain step: a new level returns nil")
    eq(M.XPGainStep(kept, 150, 1200, 11), 10, "gain step: the next rise counts from the last reading")
    eq(M.XPGainStep(kept, nil, 1200, 11), nil, "gain step: a missing reading returns nil")

    -- A level-up's three signals, one reading each, in all six orders, and the
    -- rise after them. XP that lands above the old XP reads as a kill in each.
    local function gainsIn(order, newXP)
        local st = {}
        M.XPGainStep(st, 900, 1000, 10)
        local x, m, level = 900, 1000, 10
        local gains = 0
        for i = 1, 3 do
            local signal = order:sub(i, i)
            if signal == "x" then x = newXP elseif signal == "m" then m = 1200 else level = 11 end
            if M.XPGainStep(st, x, m, level) then gains = gains + 1 end
        end
        return gains, M.XPGainStep(st, newXP + 10, 1200, 11) ~= nil
    end
    local function orderIs(order, newXP, wantGains)
        local gains, nextPlays = gainsIn(order, newXP)
        eq(gains, wantGains, "gain step: a level-up in order " .. order .. " to " .. newXP)
        eq(nextPlays, true, "gain step: the rise after order " .. order .. " to " .. newXP)
    end
    for _, order in ipairs({ "xml", "xlm", "mxl", "lxm", "mlx", "lmx" }) do
        orderIs(order, 100, 0)
        orderIs(order, 950, 1)
    end
end

-- Where a turn-in's gain sits on the bar, on a window of 0.5 seconds
do
    local function seeded(cur)
        local kept = {}
        M.XPGainStep(kept, cur, 1000, 10, 0)
        return kept
    end
    local function spanIs(label, wantFrom, wantTo, ...)
        local from, to = M.QuestSpan(...)
        eq(from, wantFrom, "quest span: " .. label)
        eq(to, wantTo, "quest span: " .. label .. ", its end")
    end

    local st = seeded(100)
    spanIs("the XP still to come runs ahead of the fill", 10, 15, st, 100, 1000, 10, 50, 10, 0.5)
    spanIs("the XP already there, not yet reported", 10, 15, st, 150, 1000, 10, 50, 10, 0.5)
    eq(M.XPGainStep(st, 150, 1000, 10, 10), 50, "quest span: the reading arrives")
    spanIs("the XP reported just before takes that reading's span", 10, 15, st, 150, 1000, 10, 50, 10.2, 0.5)
    spanIs("a reading outside the window does not", 15, 20, st, 150, 1000, 10, 50, 11, 0.5)

    st = seeded(700)
    M.XPGainStep(st, 900, 1000, 10, 10)
    spanIs("a quest's own reading near the top still lends its span", 70, 90, st, 900, 1000, 10, 200, 10.2, 0.5)

    -- A quest that crosses a level draws only what is on the bar after it, in
    -- each order of its signals.
    st = seeded(990)
    spanIs("XP to come past the top draws what is left over", 0, 4, st, 990, 1000, 10, 50, 10, 0.5)
    st = seeded(890)
    M.XPGainStep(st, 900, 1000, 10, 10)
    spanIs("a kill's reading does not hide a reward past the top", 0, 10, st, 900, 1000, 10, 200, 10.2, 0.5)
    st = seeded(900)
    spanIs("a new level not yet reported draws the new fill", 0, 5, st, 60, 1200, 11, 150, 10, 0.5)
    spanIs("a new total not yet reported", 0, 5, st, 60, 1200, 10, 150, 10, 0.5)
    spanIs("a fall not yet reported", 0, 10, st, 100, 1000, 10, 150, 10, 0.5)
    st = seeded(900)
    M.XPGainStep(st, 60, 1200, 11, 10)
    spanIs("a level-up reading just before draws the new fill", 0, 5, st, 60, 1200, 11, 150, 10.2, 0.5)
    spanIs("for the next quest inside the window too", 0, 5, st, 60, 1200, 11, 60, 10.3, 0.5)
    spanIs("and a quest well after it runs ahead of the fill", 5, 17.5, st, 60, 1200, 11, 150, 11, 0.5)
    st = seeded(900)
    M.XPGainStep(st, 100, 1000, 10, 10)
    spanIs("a fall just before counts as a level-up", 0, 10, st, 100, 1000, 10, 50, 10.2, 0.5)

    spanIs("no kept reading draws the fill", 0, 10, {}, 100, 1000, 10, 50, 10, 0.5)
    spanIs("a missing reading", nil, nil, seeded(100), nil, 1000, 10, 50, 10, 0.5)
    spanIs("no total", nil, nil, seeded(100), 100, 0, 10, 50, 10, 0.5)
    spanIs("no reward", nil, nil, seeded(100), 100, 1000, 10, nil, 10, 0.5)
end

-- One reputation reading
do
    local kept = {}
    eq(M.FactionStep(kept, 5, "standard", 6, 4000, 40, false), nil, "faction step: a first reading plays nothing")
    local moment, amount, from = M.FactionStep(kept, 5, "standard", 6, 4100, 41, false)
    eq(moment, "gain", "faction step: a rise is a gain")
    eq(amount, 100, "faction step: with its amount")
    eq(from, 40, "faction step: and where it began")
    eq(M.FactionStep(kept, 5, "standard", 6, 4050, 40.5, false), nil, "faction step: a loss plays nothing")
    eq(M.FactionStep(kept, 5, "standard", 7, 9000, 1, false), "rank", "faction step: a higher standing is a rank")
    eq(M.FactionStep(kept, 5, "standard", 6, 3000, 90, false), nil, "faction step: a lower rank plays nothing")
    eq(M.FactionStep(kept, 9, "standard", 2, 100, 5, false), nil, "faction step: a new id plays nothing")
    eq(M.FactionStep(kept, nil), nil, "faction step: a nil reading plays nothing")
    eq(M.FactionStep(kept, 9, "standard", 3, 200, 5, false), nil, "faction step: nor the reading after it")
    eq(M.FactionStep(kept, 9, "standard", 3, 300, 100, true), nil, "faction step: no gain at max")

    kept = {}
    M.FactionStep(kept, 7, "friendship", 2, 500, 10, false)
    eq(M.FactionStep(kept, 7, "friendship", 3, 900, 1, false), "rank", "faction step: a higher friendship rank is a rank")
    kept = {}
    M.FactionStep(kept, 7, "renown", 4, 2400, 96, false)
    eq(M.FactionStep(kept, 7, "renown", 5, 10, 1, false), "rank", "faction step: a higher renown level is a rank")
    kept = {}
    M.FactionStep(kept, 7, "paragon", 2, 29000, 90, false)
    eq(M.FactionStep(kept, 7, "paragon", 3, 30100, 1, false), "rank", "faction step: a paragon reward is a rank")
    kept = {}
    M.FactionStep(kept, 7, "renown", 25, 2500, 100, true)
    eq(M.FactionStep(kept, 7, "paragon", 0, 10, 1, false), "rank", "faction step: a change to paragon on one id is a rank")
    kept = {}
    M.FactionStep(kept, 7, "standard", 6, 4000, 40, false)
    eq(M.FactionStep(kept, 7, "renown", 1, 100, 4, false), nil, "faction step: another change of kind plays nothing")
end

-- Effect geometry
do
    local spanX, width = M.EffectSpan(10, 15, 200, 4)
    eq(spanX, 20, "effect span: the left in pixels")
    eq(width, 10, "effect span: the width in pixels")
    spanX, width = M.EffectSpan(10, 10.5, 200, 4)
    eq(spanX, 17, "effect span: a short span grows left from its end")
    eq(width, 4, "effect span: to the least width")
    spanX, width = M.EffectSpan(0, 0.1, 200, 4)
    eq(spanX, 0, "effect span: stays inside at the left")
    eq(width, 4, "effect span: at the least width")
    spanX, width = M.EffectSpan(99.9, 100, 200, 4)
    eq(spanX, 196, "effect span: stays inside at the right")
    eq(width, 4, "effect span: there too at the least width")
    spanX, width = M.EffectSpan(0, 100, 2, 4)
    eq(spanX, 0, "effect span: on a bar below the least width, from the left")
    eq(width, 2, "effect span: at the bar's width")

    eq(M.AmountX(50, 200, 10), 100, "amount x: follows the percent")
    eq(M.AmountX(1, 200, 10), 10, "amount x: clamped at the left")
    eq(M.AmountX(99, 200, 10), 190, "amount x: clamped at the right")
    eq(M.AmountX(50, 10, 10), 5, "amount x: centered on a bar too narrow to clamp")

    local u1, u2 = M.StripeCoords(0, 50, 10)
    eq(u1, 0, "stripe coords: from absolute x")
    eq(u2, 5, "stripe coords: to absolute x")
    local u3 = M.StripeCoords(50, 80, 10)
    eq(u3, u2, "stripe coords: two spans sharing a pixel agree there")
    eq(select(2, M.StripeCoords(0, 8, 0)), 8, "stripe coords: a tile of 0 counts as 1")

    eq(M.ReadyToLevel(900, 1000, 0), false, "ready: no quest XP")
    eq(M.ReadyToLevel(900, 1000, 100), true, "ready: exact cover")
    eq(M.ReadyToLevel(900, 1000, 150), true, "ready: over")
    eq(M.ReadyToLevel(900, 1000, 99), false, "ready: under")
    eq(M.ReadyToLevel(nil, 1000, 99), false, "ready: a missing reading")

    eq(M.Lift(0.5), 0.8, "lift: raises a channel")
    eq(M.Lift(0.9), 1, "lift: capped at 1")
    eq(M.Lift(nil), 0, "lift: a missing channel")
end

-- The card's texts
eq(M.RateText(90000), "90.0K xp/hr", "rate text: short, with its suffix")
eq(M.ClockText(0), "0:00", "clock text: zero")
eq(M.ClockText(59), "0:59", "clock text: seconds")
eq(M.ClockText(1200), "20:00", "clock text: minutes")
eq(M.ClockText(3600), "1:00:00", "clock text: hours")
eq(M.ClockText(nil), "--", "clock text: unknown")
eq(M.ClockText(-1), "--", "clock text: a negative counts as unknown")

-- Trend, on a window of 100 seconds
do
    local function two(firstGain, secondGain)
        local st = {}
        M.Trend(st, 0, 0, 100)
        M.Trend(st, firstGain, 100, 100)
        return M.Trend(st, firstGain + secondGain, 200, 100), st
    end
    local st = {}
    eq(M.Trend(st, 0, 0, 100), nil, "trend: a first reading seeds")
    eq(M.Trend(st, 50, 50, 100), nil, "trend: mid window")
    eq(M.Trend(st, 100, 100, 100), nil, "trend: no direction in the first window")
    eq((two(100, 105)), nil, "trend: 5% up exactly is no direction")
    eq((two(100, 106)), "up", "trend: just over 5% is up")
    eq((two(100, 95)), nil, "trend: 5% down exactly is no direction")
    eq((two(100, 94)), "down", "trend: just over 5% down is down")
    eq((two(100, 0)), "down", "trend: a window with no XP after one with XP")
    eq((two(0, 100)), nil, "trend: a previous rate of 0 sets none")
    local dir, kept = two(100, 106)
    eq(M.Trend(kept, 206, 200, 100), dir, "trend: a frozen elapsed time changes nothing")
    eq(M.Trend(kept, 999, 200, 100), dir, "trend: however the XP reads")
    eq(M.Trend(kept, 0, 0, 100), nil, "trend: a reset reseeds")
    eq(M.Trend(kept, 100, 100, 100), nil, "trend: and the first window after it sets none")
    local cleared = select(2, two(100, 106))
    cleared.at = nil
    eq(M.Trend(cleared, 999, 999, 100), nil, "trend: a cleared start reseeds at any numbers")
    eq(M.Trend(cleared, 1099, 1099, 100), nil, "trend: and the first window after it sets none")

    local onTime = select(2, two(100, 106))
    eq(M.Trend(onTime, 456, 325, 100), "up", "trend: a window that closes a little late counts")
    local late = select(2, two(100, 106))
    eq(M.Trend(late, 1000, 326, 100), nil, "trend: a window that closes too late is dropped")
    eq(late.rate, nil, "trend: with the rate before it")
    eq(M.Trend(late, 1100, 426, 100), nil, "trend: and the first window after it sets none")
    eq(M.Trend(late, 1300, 526, 100), "up", "trend: the next compares those two")
end

-- The seconds spent in the level just finished
eq(M.LevelSplit(11, 10, 900, nil, nil, 1000), 100, "level split: the running clock")
eq(M.LevelSplit(11, nil, nil, 10, 900, 1000), 100, "level split: the held clock")
eq(M.LevelSplit(11, 9, 900, nil, nil, 1000), nil, "level split: a running clock of another level")
eq(M.LevelSplit(11, nil, nil, 9, 900, 1000), nil, "level split: a held clock of another level")
eq(M.LevelSplit(12, 10, 900, nil, nil, 1000), nil, "level split: two levels at once")
eq(M.LevelSplit(11, 10, 900.4, nil, nil, 1000), 100, "level split: whole seconds")
eq(M.LevelSplit(nil, 10, 900, nil, nil, 1000), nil, "level split: no level")

-- Pace
eq(M.PaceGap(1000, 0.5, 800, 1600), 200, "pace gap: positive is ahead")
eq(M.PaceGap(1400, 0.5, 800, 1600), -200, "pace gap: negative is behind")
eq(M.PaceGap(1000, 0, 800, 1600), -200, "pace gap: at the level's start")
eq(M.PaceGap(1000, 1, 800, 1600), 600, "pace gap: at the level's end")
eq(M.PaceGap(nil, 0.5, 800, 1600), nil, "pace gap: a missing input")
eq(M.PaceGap(1000, 0.5, 1600, 800), nil, "pace gap: an end before its start")
eq(M.PaceText(3600), "1h 0m ahead", "pace text: ahead")
eq(M.PaceText(-120), "2m behind", "pace text: behind")
eq(M.PaceText(0), "< 1m ahead", "pace text: level")
eq(M.PaceText(nil), "--", "pace text: unknown")

-- Sizes follow the font size
eq(M.TickerWidth(24), 2 * M.TickerWidth(12), "ticker width: scales with the font size")
check(M.RowHeight(24) > M.RowHeight(12), "row height: scales with the font size")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
