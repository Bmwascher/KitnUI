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

    eq(L.MemberKey("Dunni", "Rat", "Area52", " "), "Dunni Rat", "a regional member joins the surname")
    eq(L.MemberKey("Dunni Rat", "Rat", "Area52", " "), "Dunni Rat", "a joined name is kept")
    eq(L.MemberKey("Dunni", nil, "Area52", " "), "Dunni", "no surname read takes no realm")
    eq(L.SenderKey("Dunni Rat", "Area52", " "), L.MemberKey("Dunni", "Rat", "Area52", " "), "a regional sender matches its member")
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
    eq(L.TooltipStatus(out), "Lv 59 45.0%", "a tooltip status holds the level and percent, with single spaces")
    L.RowView(out, atCap, nil, 90, false)
    eq(L.TooltipStatus(out), "Lv 90 Max", "at the cap, Max")
    L.RowView(out, m, nil, 90, false)
    eq(L.TooltipStatus(out), "Lv 59 no data", "with nothing heard, no data")
    L.RowView(out, away, nil, 90, false)
    eq(L.TooltipStatus(out), "offline", "an offline member reads offline")

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

---------------------------------------------------------------------------------
-- The refusal state machine
---------------------------------------------------------------------------------

-- A slot stands for the 2-second timer: armed by a trigger or a result, spent
-- by one flush.
local function newDriver(sharing)
    local d = { s = {}, armed = false, sent = {}, locked = false, level = 10, cur = 100, total = 1000, result = 0, raised = false }
    L.SetSharing(d.s, sharing)
    function d.trigger(kind)
        if L.Trigger(d.s, kind) then d.armed = true end
    end
    function d.slot()
        d.armed = false
        local text = L.NextSend(d.s, d.locked, d.level, d.cur, d.total)
        if not text then return end
        d.sent[#d.sent + 1] = text
        if L.OnResult(d.s, not d.raised, d.result) then d.armed = true end
    end
    function d.drain()
        local guard = 0
        while d.armed and guard < 20 do
            guard = guard + 1
            d.slot()
        end
        check(guard < 20, "a drain ends")
    end
    return d
end

do
    -- Merging, and one message a slot
    local d = newDriver(true)
    d.trigger("xp")
    d.cur = 150
    d.trigger("xp")
    d.cur = 200
    eq(d.armed, true, "a trigger arms a slot")
    d.drain()
    eq(#d.sent, 1, "two triggers merge into one send")
    eq(select(2, L.ParseMessage(d.sent[1])), 10, "the report parses")
    eq(select(3, L.ParseMessage(d.sent[1])), 200, "with the newest values")
    eq(L.Due(d.s), false, "and nothing is left due")

    d = newDriver(true)
    d.trigger("enter")
    d.slot()
    eq(d.sent[1], L.ASK, "an enter asks first")
    eq(d.armed, true, "and the report takes the next slot")
    eq(#d.sent, 1, "one message a slot")
    d.slot()
    eq(L.ParseMessage(d.sent[2]), "report", "then the report")
    eq(d.armed, false, "then nothing")

    -- Only while XP changes
    d = newDriver(true)
    d.trigger("xp")
    d.drain()
    d.trigger("xp")
    d.drain()
    eq(#d.sent, 1, "an unchanged reading sends nothing")
    eq(L.Due(d.s), false, "and is not left due")
    d.trigger("join")
    d.drain()
    eq(#d.sent, 2, "a join sends the same values")
    d.trigger("asked")
    d.drain()
    eq(#d.sent, 3, "and so does a report request")

    -- A lock, read before the send or refused by it
    d = newDriver(true)
    d.locked = true
    d.trigger("xp")
    eq(d.armed, true, "a trigger inside a lock arms one slot")
    d.slot()
    eq(#d.sent, 0, "whose flush sends nothing")
    eq(d.armed, false, "and arms no retry")
    eq(L.Due(d.s), true, "what was due stays due")
    d.locked = false
    eq(d.armed, false, "a lock lifting alone arms nothing")
    d.cur = 300
    d.trigger("xp")
    d.drain()
    eq(#d.sent, 1, "the next trigger sends once")
    eq(select(3, L.ParseMessage(d.sent[1])), 300, "with the newest values")

    d = newDriver(true)
    d.result = 11
    d.trigger("join")
    d.slot()
    eq(#d.sent, 1, "a refused send was tried")
    eq(d.armed, false, "11 arms no retry")
    eq(L.Due(d.s), true, "and keeps what is due")
    d.trigger("roster")
    eq(d.armed, false, "a bare roster event does not send what is held")
    d.result = 0
    d.trigger("xp")
    d.drain()
    eq(#d.sent, 2, "the next trigger sends it")
    eq(L.Due(d.s), false, "once")

    -- A non-sharer holds only its ask
    d = newDriver(false)
    d.trigger("xp")
    eq(d.armed, false, "a non-sharer's XP is no report")
    d.trigger("asked")
    eq(d.armed, false, "nor is a report request")
    d.trigger("join")
    eq(d.armed, false, "nor a join")
    d.result = 11
    d.trigger("enter")
    d.slot()
    eq(d.sent[1], L.ASK, "a non-sharer asks")
    eq(L.Due(d.s), true, "and a refused ask is held")
    d.result = 0
    d.trigger("join")
    eq(d.armed, true, "a join sends the held ask")
    d.drain()
    eq(d.sent[2], L.ASK, "which is only the ask")
    eq(#d.sent, 2, "with no report")

    -- Throttles and a group that is gone
    for _, code in ipairs({ 3, 8 }) do
        d = newDriver(true)
        d.result = code
        d.trigger("xp")
        d.slot()
        eq(d.armed, true, code .. " tries the next slot")
        eq(L.Due(d.s), true, code .. " keeps what is due")
        d.result = 0
        d.drain()
        eq(L.Due(d.s), false, code .. " then clears it")
    end

    d = newDriver(true)
    d.result = 5
    d.trigger("enter")
    d.slot()
    eq(d.armed, false, "5 arms nothing")
    eq(L.Due(d.s), false, "and drops what is due")
    d.result = 0
    d.trigger("xp")
    d.trigger("asked")
    d.trigger("join")
    d.trigger("enter")
    eq(d.armed, false, "every trigger sets nothing until the roster changes")
    local beforeRelease = #d.sent
    d.trigger("roster")
    eq(d.armed, true, "a roster event clears it")
    d.drain()
    eq(d.sent[beforeRelease + 1], L.ASK, "and asks again, since 5 dropped the ask")
    eq(L.ParseMessage(d.sent[#d.sent]), "report", "then reports")

    d = newDriver(false)
    d.result = 5
    d.trigger("enter")
    d.slot()
    eq(L.Due(d.s), false, "a non-sharer's 5 drops its ask")
    d.result = 0
    d.trigger("join")
    eq(d.armed, false, "and nothing but the roster restores it")
    d.trigger("roster")
    eq(d.armed, true, "a roster event does")
    d.drain()
    eq(#d.sent, 2, "with one more message")
    eq(d.sent[2], L.ASK, "which is the ask")
    eq(L.Due(d.s), false, "and nothing is left due")

    -- Anything else is dropped
    for _, code in ipairs({ 1, 2, 4, 6, 7, 9, 10, 12 }) do
        d = newDriver(true)
        d.result = code
        d.trigger("xp")
        d.slot()
        eq(d.armed, false, code .. " is dropped")
        eq(L.Due(d.s), false, code .. " leaves nothing due")
    end
    d = newDriver(true)
    d.result = nil
    d.trigger("xp")
    d.slot()
    eq(L.Due(d.s), false, "a result that cannot be read is dropped")
    d = newDriver(true)
    d.raised = true
    d.trigger("enter")
    d.slot()
    eq(d.armed, true, "a raised error drops the ask and the report still has a slot")
    d.raised = false
    d.drain()
    eq(L.Due(d.s), false, "and it goes")

    -- A report that cannot encode never reaches a send
    d = newDriver(true)
    d.total = 0
    d.trigger("join")
    d.drain()
    eq(#d.sent, 0, "a report that encodes to nil is not sent")
    eq(L.Due(d.s), false, "and is not kept")
    d = newDriver(true)
    d.cur = nil
    d.trigger("xp")
    d.drain()
    eq(#d.sent, 0, "nor one with a reading missing")

    -- Sharing going off and a reset
    d = newDriver(true)
    d.trigger("join")
    L.SetSharing(d.s, false)
    eq(L.Due(d.s), false, "sharing going off drops a due report")
    d.trigger("enter")
    L.Reset(d.s)
    eq(L.Due(d.s), false, "a reset clears everything")
end

-- Every order of the triggers and a lock, under each result: nothing is lost,
-- nothing is sent past the newest values, and the machine always ends quiet.
do
    local OPS = { "xp", "join", "asked", "enter", "lockOn", "lockOff" }
    local RESULTS = { 0, 3, 8, 11, 5, 2 }
    local runs = 0
    local function run(order, code)
        runs = runs + 1
        local d = newDriver(true)
        d.result = code
        for i, op in ipairs(order) do
            d.cur = 100 + i
            if op == "lockOn" then
                d.locked = true
            elseif op == "lockOff" then
                d.locked = false
            else
                d.trigger(op)
            end
            if d.armed then d.slot() end
        end
        d.locked = false
        d.result = 0
        d.cur = 500
        d.trigger("roster")
        d.trigger("xp")
        d.drain()
        eq(L.Due(d.s), false, "any order: nothing is left due")
        eq(d.armed, false, "any order: no slot is left armed")
        local last = d.sent[#d.sent]
        eq(select(3, L.ParseMessage(last)), 500, "any order: the last report is the newest")
        for _, text in ipairs(d.sent) do
            check(L.ParseMessage(text) ~= nil, "any order: every message parses", text)
        end
    end
    local function permute(list, n, code)
        if n == 0 then
            run(list, code)
            return
        end
        for i = 1, n do
            list[i], list[n] = list[n], list[i]
            permute(list, n - 1, code)
            list[i], list[n] = list[n], list[i]
        end
    end
    for _, code in ipairs(RESULTS) do permute(OPS, #OPS, code) end
    eq(runs, 720 * #RESULTS, "every order ran under each result")
end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
