-- ╔══════════════════════════════════════════════════════════════╗
-- ║  xpbar-party-logic.lua                                       ║
-- ║  Purpose: Gate for party XP's pure decisions: the message    ║
-- ║           format, names, the gate, the row text, the member  ║
-- ║           merge and the refusal state machine. No stubs: the ║
-- ║           file calls nothing in the game.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/xpbar-party-logic.lua

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
local chunk, err = loadfile("KitnUI_EUI/XPBar/PartyLogic.lua")
if not chunk then
    print("FAIL  could not load KitnUI_EUI/XPBar/PartyLogic.lua: " .. tostring(err))
    os.exit(1)
end
chunk("KitnUI_EUI", ns)
local L = ns.XPBar.PartyLogic

---------------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------------

do
    local text = L.EncodeReport(59, 94410, 209800)
    check(type(text) == "string", "a report encodes")
    local kind, level, cur, total = L.ParseMessage(text)
    eq(kind, "report", "a report parses as a report")
    eq(level, 59, "with its level")
    eq(cur, 94410, "its XP")
    eq(total, 209800, "and its total")
    eq(L.EncodeReport(level, cur, total), text, "what a parse accepts encodes the same")
    eq(L.ParseMessage(L.ASK), "ask", "the ask parses as an ask")
    eq(L.ParseMessage(L.EncodeReport(1, 0, 1)), "report", "the lowest sane report parses")
    eq(L.ParseMessage(L.EncodeReport(5, 400, 400)), "report", "XP equal to the total parses")

    local bad = {
        "garbage", "", "1 59 100", "1 59 100 200 300", "1 59 300 200", "1 59 0 0", "1 0 0 200",
        (L.VERSION + 1) .. " 59 100 200", "1 59 -1 200", "1 59.5 1 200", string.rep("1", 60), 42,
    }
    for i, text2 in ipairs(bad) do
        eq(L.ParseMessage(text2), nil, "a bad message is refused, case " .. i)
    end
    eq(L.ParseMessage(nil), nil, "no message is refused")

    local refused = {
        { 59.5, 1, 2 }, { 59, 1.5, 2 }, { 59, 1, 2.5 }, { 59, 1, 0 }, { 59, 3, 2 }, { 0, 1, 2 }, { 59, -1, 2 },
        { "59", 1, 2 }, { 59, 1, math.huge }, { 59, 1, 2 ^ 40 }, { 5000, 1, 2 },
    }
    for i, r in ipairs(refused) do
        eq(L.EncodeReport(r[1], r[2], r[3]), nil, "a bad report does not encode, case " .. i)
    end
    eq(L.EncodeReport(nil, 1, 2), nil, "a missing level does not encode")
    eq(L.EncodeReport(59, nil, 2), nil, "a missing XP does not encode")
    eq(L.EncodeReport(59, 1, nil), nil, "a missing total does not encode")

    check(#L.PREFIX > 0 and #L.PREFIX <= 16, "the prefix fits the game's limit")
    check(#L.EncodeReport(999, 2147483647, 2147483647) <= 255, "the longest report fits one message")
    eq(L.PrefixHeld(0), true, "a registered prefix is held")
    eq(L.PrefixHeld(1), true, "and a prefix already registered")
    eq(L.PrefixHeld(2), false, "an invalid prefix is not")
    eq(L.PrefixHeld(3), false, "nor one past the limit")
    eq(L.PrefixHeld(nil), false, "nor no answer")
end

---------------------------------------------------------------------------------
-- Channels and names
---------------------------------------------------------------------------------

do
    eq(L.Channel(true, false), "INSTANCE_CHAT", "an instance group sends on INSTANCE_CHAT")
    eq(L.Channel(true, true), "INSTANCE_CHAT", "and with a home party inside it")
    eq(L.Channel(false, true), "PARTY", "a home party sends on PARTY")
    eq(L.Channel(false, false), nil, "no group sends nothing")
    eq(L.AcceptChannel("PARTY"), true, "PARTY is heard")
    eq(L.AcceptChannel("INSTANCE_CHAT"), true, "INSTANCE_CHAT is heard")
    for _, channel in ipairs({ "RAID", "GUILD", "WHISPER", "" }) do
        eq(L.AcceptChannel(channel), false, "a channel is refused: " .. channel)
    end
    eq(L.AcceptChannel(nil), false, "no channel is refused")

    eq(L.MemberKey("Mirelle", nil, "Area52"), "Mirelle-Area52", "a same-realm member, no realm")
    eq(L.MemberKey("Mirelle", "", "Area52"), "Mirelle-Area52", "a same-realm member, a blank realm")
    eq(L.MemberKey("Mirelle", "Illidan", "Area52"), "Mirelle-Illidan", "a cross-realm member")
    eq(L.MemberKey("Mirelle", nil, nil), nil, "no realm known")
    eq(L.MemberKey("", "Illidan", "Area52"), nil, "an empty name")
    eq(L.MemberKey(42, "Illidan", "Area52"), nil, "a name that is not a string")
    eq(L.SenderKey("Mirelle-Area52", "Illidan"), "Mirelle-Area52", "a sender with a realm keeps it")
    eq(L.SenderKey("Mirelle", "Area52"), "Mirelle-Area52", "a sender with no realm takes this one")
    eq(L.SenderKey("Mirelle", nil), nil, "and none is known")
    eq(L.SenderKey(nil, "Area52"), nil, "no sender")
    eq(L.SenderKey("", "Area52"), nil, "an empty sender")
    eq(L.SenderKey("Mirelle-Area52", "X"), L.MemberKey("Mirelle", nil, "Area52"), "one player keys one way")
end

---------------------------------------------------------------------------------
-- The gate
---------------------------------------------------------------------------------

do
    local BOOLS = { true, false }
    local function digit(b) return b and "1" or "0" end

    -- The combinations with no display, as card, markers, lines, XP bar and Show
    -- Tooltip digits. Every other combination has one.
    local NO_DISPLAY = {
        ["00000"] = true, ["00001"] = true, ["00100"] = true, ["00101"] = true,
        ["01000"] = true, ["01001"] = true, ["01100"] = true, ["01101"] = true,
        ["00010"] = true, ["00011"] = true, ["00110"] = true,
    }
    local displayCases = 0
    for _, card in ipairs(BOOLS) do
        for _, markers in ipairs(BOOLS) do
            for _, lines in ipairs(BOOLS) do
                for _, xpBar in ipairs(BOOLS) do
                    for _, tip in ipairs(BOOLS) do
                        displayCases = displayCases + 1
                        local key = digit(card) .. digit(markers) .. digit(lines) .. digit(xpBar) .. digit(tip)
                        eq(L.DisplayOn(card, markers, lines, xpBar, tip), not NO_DISPLAY[key], "a display's state: " .. key)
                    end
                end
            end
        end
    end
    eq(displayCases, 32, "a display's state: every combination ran")
    eq(L.DisplayOn(false, true, true, false, true), false, "markers and lines need the XP bar")
    eq(L.DisplayOn(true, false, false, false, false), true, "the card does not")
    eq(L.DisplayOn(false, false, true, true, false), false, "lines need Show Tooltip")

    -- The modes, from the spec's table. A row is share, at max and XP gain off;
    -- its columns run in party, member below max and display: 000, 001, 010, 011,
    -- 100, 101, 110, 111.
    local NOT_SHARING = { "off", "watch", "off", "watch", "off", "roster", "off", "listen" }
    local MODES = {
        ["100"] = { "watch", "watch", "watch", "watch", "share", "share", "share", "share" },
        ["101"] = { "watch", "watch", "watch", "watch", "roster", "roster", "roster", "listen" },
        ["110"] = NOT_SHARING, ["111"] = NOT_SHARING,
        ["000"] = NOT_SHARING, ["001"] = NOT_SHARING, ["010"] = NOT_SHARING, ["011"] = NOT_SHARING,
    }
    local count = 0
    for _, share in ipairs(BOOLS) do
        for _, atMax in ipairs(BOOLS) do
            for _, xpOff in ipairs(BOOLS) do
                for _, inParty in ipairs(BOOLS) do
                    for _, below in ipairs(BOOLS) do
                        for _, display in ipairs(BOOLS) do
                            count = count + 1
                            local row = digit(share) .. digit(atMax) .. digit(xpOff)
                            local column = (inParty and 4 or 0) + (below and 2 or 0) + (display and 1 or 0) + 1
                            eq(L.Gate(share, atMax, xpOff, inParty, below, display), MODES[row][column],
                                "the gate: " .. row .. " column " .. column)
                        end
                    end
                end
            end
        end
    end
    eq(count, 64, "the gate: every combination ran")
    eq(L.Gate(true, true, false, true, true, false), "off", "at max with displays off: nothing")
    eq(L.Gate(true, false, false, false, false, false), "watch", "below max, solo: one watcher")
    eq(L.Gate(true, false, false, true, false, false), "share", "below max in a party: shares")
    eq(L.Gate(true, false, true, false, false, false), "watch", "XP gain off, solo: keeps the watcher")
    eq(L.Gate(true, false, true, true, false, false), "roster", "XP gain off in a party: does not share")
    eq(L.Gate(false, false, false, true, true, false), "off", "Share off, no display: nothing")
    eq(L.Gate(false, false, false, true, true, true), "listen", "Share off, a display on: hears")
    eq(L.Gate(true, true, false, true, false, true), "roster", "at max, a display on, an all-max party: hears nothing")
    eq(L.Gate(true, true, false, true, true, true), "listen", "and with a member below max: hears")

    local function names(out)
        local list = {}
        for e in pairs(out) do list[#list + 1] = e end
        table.sort(list)
        return table.concat(list, ",")
    end
    local out = { CHAT_MSG_ADDON = true }
    eq(next(L.WantedEvents(out, "off", false)), nil, "off wants nothing, and clears what was kept")
    eq(names(L.WantedEvents(out, "watch", true)), "GROUP_ROSTER_UPDATE", "watch wants one event")
    local rosterSet = "GROUP_ROSTER_UPDATE,UNIT_CONNECTION,UNIT_LEVEL,UNIT_NAME_UPDATE"
    eq(names(L.WantedEvents(out, "roster", false)), rosterSet, "roster wants the roster set")
    eq(names(L.WantedEvents(out, "listen", false)), "CHAT_MSG_ADDON," .. rosterSet, "listen adds the messages")
    eq(names(L.WantedEvents(out, "share", false)), "CHAT_MSG_ADDON," .. rosterSet, "share is the listen set")
    L.WantedEvents(out, "share", true)
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN" }) do
        eq(out[e], true, "ownXP adds " .. e)
    end
    for _, mode in ipairs({ "off", "watch", "roster", "listen", "share" }) do
        L.WantedEvents(out, mode, true)
        eq(out.ADDON_RESTRICTION_STATE_CHANGED, nil, "no restriction event in " .. mode)
        for e in pairs(out) do
            local listed = false
            for _, known in ipairs(L.ALL_EVENTS) do
                if known == e then listed = true end
            end
            check(listed, "every wanted event is listed: " .. e)
        end
    end
    eq(L.UNIT_EVENTS.UNIT_LEVEL, true, "the unit events are marked")
    eq(L.UNIT_EVENTS.GROUP_ROSTER_UPDATE, nil, "and no other")
end

---------------------------------------------------------------------------------
-- Displays
---------------------------------------------------------------------------------

do
    eq(L.CardShown(true, true, true, 2), true, "the card shows with all four")
    eq(L.CardShown(false, true, true, 2), false, "not with its switch off")
    eq(L.CardShown(true, false, true, 2), false, "not out of a party")
    eq(L.CardShown(true, true, false, 2), false, "not with nobody below max")
    eq(L.CardShown(true, true, true, 0), false, "not with no row")

    local m = { level = 59, online = true }
    local heard = { level = 59, pct = 45 }
    local out = {}
    eq(L.RowView(out, m, heard, 90, false), out, "a row view fills what it is given")
    eq(out.kind, "data", "a heard value is a data row")
    eq(out.pct, 45, "at its percent")
    check(out.text:find("59", 1, true) and out.text:find("45.0", 1, true), "reading the level and percent", out.text)

    L.RowView(out, m, nil, 90, false)
    eq(out.kind, "nodata", "nothing heard is a no-data row")
    eq(out.pct, 0, "with an empty bar")
    check(out.text:find("59", 1, true), "reading the level", out.text)

    local atCap = { level = 90, online = true }
    L.RowView(out, atCap, nil, 90, false)
    eq(out.kind, "max", "at the cap is a max row, with no message")
    eq(out.pct, 100, "with a full bar")
    L.RowView(out, atCap, { level = 89, pct = 12 }, 90, false)
    eq(out.kind, "max", "max comes before a heard value")
    L.RowView(out, atCap, nil, nil, false)
    eq(out.kind, "nodata", "no known cap counts nobody as max")

    local away = { level = 90, online = false }
    L.RowView(out, away, { level = 90, pct = 12 }, 90, false)
    eq(out.kind, "offline", "offline comes before max and a heard value")
    eq(out.pct, 0, "with an empty bar")

    local leveled = { level = 60, online = true }
    local old = { level = 59, pct = 99.5 }
    L.RowView(out, leveled, old, 90, false)
    eq(out.kind, "nodata", "a level-up drops the old pair")
    check(out.text:find("60", 1, true), "and reads the new level", out.text)
    L.RowView(out, leveled, old, 90, true)
    eq(out.kind, "data", "inside a lock the pair is kept")
    eq(out.pct, 99.5, "at its percent")
    check(out.text:find("59", 1, true), "with its own level", out.text)
    L.RowView(out, m, { level = 59, pct = 0 }, 90, false)
    eq(out.pct, 0, "0 percent is a percent")
    L.RowView(out, m, { level = 59, pct = 100 }, 90, false)
    eq(out.pct, 100, "and so is 100")

    L.RowView(out, m, heard, 90, false)
    local line = L.TooltipText("Mirelle", out)
    check(line:find("Mirelle", 1, true) and line:find("45.0", 1, true), "a tooltip line holds the name and percent", line)
    check(not line:find("  ", 1, true), "with single spaces", line)
    L.RowView(out, away, nil, 90, false)
    check(L.TooltipText("Bram", out):find("Bram", 1, true) ~= nil, "an offline member has a line")

    eq(L.LabelText("Mirelle", 58, "off"), nil, "a label off is no text")
    eq(L.LabelText("Mirelle", 58, "name"), "Mirelle", "a name label")
    local full = L.LabelText("Mirelle", 58, "namelevel")
    check(full:find("Mirelle", 1, true) and full:find("58", 1, true), "a name and level label", full)

    eq(L.MarkerX(0, 100, 2, 1), 0, "a tick at 0 stays inside")
    eq(L.MarkerX(100, 100, 2, 1), 98, "a tick at 100 stays inside")
    eq(L.MarkerX(50, 100, 2, 1), 49, "a tick centers on its percent")
    eq(L.MarkerX(50, 10, 20, 1), 0, "a tick wider than the bar sits at its start")
    eq(L.MarkerX(33.3, 100, 2, 0.5), 32.5, "a tick snaps to a physical pixel")
    eq(L.MarkerX(33.3, 100, 2, 1), 32, "at whatever size one is")
    eq(L.MarkerX(100, 101, 3, 0.5), 98, "and stays inside the bar after the snap")
    eq(L.MarkerWidth(2, 1), 2, "a tick's width in whole pixels")
    eq(L.MarkerWidth(1, 0.75), 0.75, "snaps to the nearest")
    eq(L.MarkerWidth(2, 0.75), 2.25, "above as well")
    eq(L.MarkerWidth(1, 4), 4, "and is never under one pixel")
end

---------------------------------------------------------------------------------
-- The member merge
---------------------------------------------------------------------------------

do
    local prev = {}
    local BOOLS = { true, false }
    local function digit(b) return b and "1" or "0" end
    -- A player who exists, by readable name, class and level, and a row already
    -- kept. A unit gone or a follower is "drop" whatever else it reads.
    local PLAYER = {
        ["1111"] = "set", ["1110"] = "set",
        ["1101"] = "keep", ["1100"] = "none", ["1011"] = "keep", ["1010"] = "none",
        ["1001"] = "keep", ["1000"] = "none", ["0111"] = "keep", ["0110"] = "none",
        ["0101"] = "keep", ["0100"] = "none", ["0011"] = "keep", ["0010"] = "none",
        ["0001"] = "keep", ["0000"] = "none",
    }
    local count = 0
    for _, exists in ipairs(BOOLS) do
        for _, follower in ipairs(BOOLS) do
            for _, hasName in ipairs(BOOLS) do
                for _, hasClass in ipairs(BOOLS) do
                    for _, hasLevel in ipairs(BOOLS) do
                        for _, hasPrev in ipairs(BOOLS) do
                            count = count + 1
                            local key = digit(hasName) .. digit(hasClass) .. digit(hasLevel) .. digit(hasPrev)
                            local wanted = (exists and not follower) and PLAYER[key] or "drop"
                            eq(L.MergeMember(hasPrev and prev or nil, exists, follower, hasName and "A" or nil,
                                hasClass and "MAGE" or nil, hasLevel and 10 or nil), wanted, "the merge, case " .. count)
                        end
                    end
                end
            end
        end
    end
    eq(count, 64, "the merge: every combination ran")
    eq(L.MergeMember(prev, true, false, "A", "MAGE", 0), "keep", "a level of 0 does not read")
    eq(L.MergeMember(nil, true, false, "A", "MAGE", -1), "none", "and neither does a negative one")
end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
