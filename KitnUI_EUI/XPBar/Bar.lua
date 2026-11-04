-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Bar.lua                                    ║
-- ║  Purpose: The live XP and faction bars: settings access, the ║
-- ║           Apply() funnel, events, clock, visibility,         ║
-- ║           tooltips and Unlock Mode.                          ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
local M = X.Math

local format, floor, max, min = string.format, math.floor, math.max, math.min

local Plain = ns.EUIPlain

---------------------------------------------------------------------------------
-- Storage helpers: the only functions that touch an xp* or fb* key.
---------------------------------------------------------------------------------

local function S() return ns.EUISettings() end

function X.Get(key, fallback)
    local s = S()
    local v = s and s[key]
    if v == nil and ns.EUI_DEFAULTS then v = ns.EUI_DEFAULTS[key] end
    if v == nil then return fallback end
    return v
end

function X.Set(key, v)
    local s = S()
    if s then s[key] = v end
end

local Get, Set = X.Get, X.Set

function X.XPEnabled() return Get("xpEnabled") == true end
function X.FactionEnabled() return Get("fbEnabled") == true end

-- These three are the switches that may claim EllesmereUI's bar, so they
-- pass their kind through.
function X.SetXPEnabled(v)
    Set("xpEnabled", v and true or false)
    X.Apply("xp")
end

function X.SetFactionEnabled(v)
    Set("fbEnabled", v and true or false)
    X.Apply("rep")
end

function X.SetHideExisting(kind, v)
    Set(kind == "rep" and "fbHideExisting" or "xpHideExisting", v and true or false)
    X.Apply(kind)
end

-- The size ranges, for the sliders and Unlock Mode's resize.
X.RANGES = {
    xpWidth = { 200, 1600 }, xpHeight = { 8, 80 },
    fbWidth = { 100, 1200 }, fbHeight = { 8, 60 },
}

-- One coalesced quest-log scan per burst of quest events, in seconds.
local QUEST_SCAN_DELAY = 0.3
local DEFAULT_Y = { xp = -100, fb = -160 }
local LABEL_R, LABEL_G, LABEL_B = 1, 0.82, 0
-- How close an XP reading must be to QUEST_TURNED_IN to lend that turn-in its
-- place on the bar, in seconds. It never decides whether a turn-in plays.
local QUEST_GAIN_WINDOW = 0.5

local XP_EVENTS = {
    "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
    "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "PLAYER_MAX_LEVEL_UPDATE", "MAX_EXPANSION_LEVEL_UPDATED",
    "PLAYER_LOGOUT", "TIME_PLAYED_MSG",
}
local ALL_EVENTS = {}
for i = 1, #XP_EVENTS do ALL_EVENTS[i] = XP_EVENTS[i] end
for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "CHAT_MSG_COMBAT_XP_GAIN",
    "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "ZONE_CHANGED_NEW_AREA", "QUEST_TURNED_IN" }) do
    ALL_EVENTS[#ALL_EVENTS + 1] = e
end

local ev
local active = false
local unlockDone, accentDone, sessionQueued, questFresh = false, false, false, false
local xpWasOn = false
local widgets = {}
local registered, wanted, wantOpts = {}, {}, {}
local questTimer, clock
local questDone, questOpen = 0, 0
-- Defined with the event handlers; ReconcileEvents arms it.
local ArmQuestScan
local raw, xpData, fbData = {}, {}, {}
local factionRec
local xpShown, fbShown = true, false
local visCfg = { visibility = "always" }
-- The effects' own last readings, so a gain is told from what the session
-- counted on other events.
local xpStep, fbStep = {}, {}
-- The game can report the quest that reaches max level after the level-up, so
-- listening runs on there until a turn-in is heard for that level (turnInLevel).
-- levelUpTo names the level for a turn-in whose level reading is still old.
local levelUpTo, turnInLevel

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------

-- Fills `out` with the events the enabled bars need. opts: quest (a quest
-- overlay, completed line or tooltip needs quest XP), kills (retail tooltip
-- below max level), companion (faction source follows the delve), questGain
-- (Quest Turn-Ins Only with a gain effect on, while leveling and for one turn-in
-- after a level-up that reaches max level).
function X.WantedEvents(out, xpOn, fbOn, opts)
    for i = 1, #ALL_EVENTS do out[ALL_EVENTS[i]] = nil end
    if xpOn then
        for i = 1, #XP_EVENTS do out[XP_EVENTS[i]] = true end
        if opts.quest then
            out.QUEST_LOG_UPDATE = true
            out.UNIT_QUEST_LOG_CHANGED = true
        end
        if opts.kills then out.CHAT_MSG_COMBAT_XP_GAIN = true end
        if opts.questGain then out.QUEST_TURNED_IN = true end
    end
    if fbOn then
        out.UPDATE_FACTION = true
        out.MAJOR_FACTION_RENOWN_LEVEL_CHANGED = true
        if opts.companion then out.ZONE_CHANGED_NEW_AREA = true end
        -- The XP session outlives its bar for the rest of the login, so its
        -- save at logout and /reload must too while this runtime is up.
        if opts.session then out.PLAYER_LOGOUT = true end
    end
    return out
end

local function ReconcileEvents()
    if not ev then return end
    local t = X.ReadXP()
    -- Quest XP and kills only matter while XP can be earned. A level-up and
    -- the cap and XP-gain events re-run this, so the set follows the level.
    local leveling = not t.atMax and not t.xpOff
    wantOpts.quest = leveling
        and (Get("xpShowQuest") == true or Get("xpShowCompRested") == true or Get("xpTooltip") == true or Get("xpReadyGlow") == true)
    wantOpts.kills = leveling and not ns.IS_FOREVER and Get("xpTooltip") == true
    wantOpts.questGain = not t.xpOff and (not t.atMax or (registered.QUEST_TURNED_IN and turnInLevel ~= t.level))
        and Get("xpGainEffect") ~= "off" and Get("xpGainQuestsOnly") == true
    wantOpts.companion = Get("fbSource") == "companion"
    wantOpts.session = X.SessionStarted()
    X.WantedEvents(wanted, X.XPEnabled(), X.FactionEnabled(), wantOpts)
    for i = 1, #ALL_EVENTS do
        local e = ALL_EVENTS[i]
        if wanted[e] and not registered[e] then
            if e == "UNIT_QUEST_LOG_CHANGED" then ev:RegisterUnitEvent(e, "player") else ev:RegisterEvent(e) end
            registered[e] = true
        elseif not wanted[e] and registered[e] then
            ev:UnregisterEvent(e)
            registered[e] = nil
        end
    end
    -- The quest totals are current only while their events are heard. A gap
    -- (the XP bar off, every quest consumer off, max level, XP gain off)
    -- drops them, and the first reconcile that wants them again scans.
    if not wanted.QUEST_LOG_UPDATE then
        questFresh, questDone, questOpen = false, 0, 0
        if questTimer then
            questTimer:Cancel()
            questTimer = nil
        end
    elseif not questFresh then
        questFresh = true
        ArmQuestScan()
    end
end

---------------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------------

-- raw: { level, cur, max, quest, rested, atMax, xpOff, levelTime, elapsed,
-- gained }. Fills `out` with the fill, the segment ends and every text; a
-- text left nil is hidden.
function X.XPView(r, view, out)
    local style, breakUp = view("xpNumberStyle"), _G.BreakUpLargeNumbers
    local mx = r.max or 0
    out.level = format("Level %d", r.level or 0)
    out.right, out.levelTime, out.rate, out.compRested = nil, nil, nil, nil
    out.readyEnd = nil
    -- A frozen time otherwise reads as a defect.
    out.sessionTime = view("xpShowSessionTime")
        and ("Time this session: " .. M.TimeText(r.elapsed) .. (r.paused and " (paused)" or "")) or nil
    if r.atMax or mx <= 0 then
        out.fill, out.questEnd, out.restedEnd = 100, 0, 0
        out.center = "Max Level"
        return out
    end
    if r.xpOff then
        out.fill, out.questEnd, out.restedEnd = M.Stack(r.cur, mx, 0, 0, false)
        out.center = "Experience disabled"
        return out
    end
    local xpPct, qEnd, rEnd = M.Stack(r.cur, mx, r.quest, r.rested, view("xpShowQuest") == true)
    out.fill, out.questEnd, out.restedEnd = xpPct, qEnd, rEnd
    out.center = view("xpAmountPos") ~= "hidden" and M.AmountText(r.cur, mx, style, view("xpShowRemaining"), breakUp) or nil
    out.right = M.PercentText(xpPct, rEnd)
    if view("xpReadyGlow") == true and M.ReadyToLevel(r.cur, mx, r.quest) then out.readyEnd = 100 end
    if view("xpShowLevelTime") then out.levelTime = "Time this level: " .. M.TimeText(r.levelTime) end
    if view("xpShowRate") then
        local perHour, eta = M.Rate(r.gained, r.elapsed, mx - (r.cur or 0))
        out.rate = perHour and format("Leveling in: %s (%s XP/Hour)", M.TimeText(eta), M.Short(perHour))
            or "Leveling in: --"
    end
    if view("xpShowCompRested") then
        out.compRested = M.CompRestedText((r.quest or 0) * 100 / mx, (r.rested or 0) * 100 / mx)
    end
    return out
end

function X.FactionView(rec, view, out)
    local pct, _, _, left, right = M.FactionProgress(rec)
    out.fill = pct or 0
    out.left = view("fbNamePos") ~= "hidden" and left or nil
    out.right = view("fbAmountPos") ~= "hidden" and right ~= "" and right or nil
    local colors = _G.FACTION_BAR_COLORS
    local c = view("fbFillMode") == "standing" and rec and rec.reaction and colors and colors[rec.reaction]
    if c then
        out.r, out.g, out.b = c.r, c.g, c.b
    else
        out.r, out.g, out.b = view("fbR"), view("fbG"), view("fbB")
    end
    return out
end

local function RefreshXP()
    local w = widgets.xp
    if not w then return end
    local t = X.ReadXP()
    raw.level, raw.cur, raw.max, raw.rested = t.level, t.cur, t.max, t.rested
    raw.atMax, raw.xpOff = t.atMax, t.xpOff
    raw.paused = X.SessionPaused()
    raw.quest = questDone
    raw.levelTime, raw.elapsed, raw.gained = X.LevelTime(), X.SessionElapsed(), X.SessionGained()
    X.XPView(raw, Get, xpData)
    xpData.markers = X.PartyMarkerList()
    X.Draw(w, Get, xpData)
    xpShown = t.applies or Get("xpShowAtMax") == true
    X.TickerRefresh(raw)
end

function X.LiveXPWidget()
    return widgets.xp
end

local function RefreshFaction()
    local w = widgets.fb
    if not w then return end
    factionRec = X.ResolveFaction(Get("fbSource"), Get("fbFactionID"))
    fbShown = factionRec ~= nil and (not factionRec.isMax or factionRec.kind == "paragon" or Get("fbShowAtMax") == true)
    X.FactionView(factionRec, Get, fbData)
    X.Draw(w, Get, fbData)
end

---------------------------------------------------------------------------------
-- Visibility and position
---------------------------------------------------------------------------------

-- EllesmereUI's own evaluator, so the eight modes behave as on its frames;
-- the fallback covers an EllesmereUI without it.
local function Eval(mode)
    local EUI = _G.EllesmereUI
    if EUI and EUI.EvalVisibility then
        visCfg.visibility = mode
        local ok, v = pcall(EUI.EvalVisibility, visCfg)
        if ok then return v end
    end
    if mode == "never" then return false end
    if mode == "mouseover" then return "mouseover" end
    if mode == "in_combat" then return InCombatLockdown() end
    if mode == "out_of_combat" then return not InCombatLockdown() end
    local inGroup = IsInGroup and IsInGroup() or false
    local inRaid = IsInRaid and IsInRaid() or false
    if mode == "in_raid" then return inRaid end
    if mode == "in_party" then return inGroup and not inRaid end
    if mode == "solo" then return not inGroup end
    return true
end

X.EvalVisibility = Eval

local function XPWantsMouseover()
    return active and X.XPEnabled() and xpShown and Get("xpVisibility") == "mouseover"
end

local function FactionWantsMouseover()
    return active and X.FactionEnabled() and fbShown and Get("fbVisibility") == "mouseover"
end

local function Show(kind, v)
    local w = widgets[kind]
    if not w then return end
    local EUI = _G.EllesmereUI
    local canHover = EUI and EUI.RegisterMouseoverTarget and EUI.UnregisterMouseoverTarget
    if v == "mouseover" and canHover then
        if not w.mouseover then
            EUI.RegisterMouseoverTarget(w.frame, kind == "xp" and XPWantsMouseover or FactionWantsMouseover)
            w.mouseover = true
        end
        return
    end
    if w.mouseover and canHover then EUI.UnregisterMouseoverTarget(w.frame) end
    w.mouseover = false
    w.frame:SetAlpha(1)
    w.frame:SetShown(v and true or false)
end

local UNLOCK_KEY = { xp = "KitnUI_XPBar", fb = "KitnUI_FactionBar" }

-- An Unlock Mode anchor link is an anchored frame's only placing authority, as
-- it is for EUI's own frames: the frame is put back on its link, never on its
-- saved spot. An unanchored frame sits on its own saved spot.
function X.PlaceFrame(frame, unlockKey, pos, defaultPoint, x, y)
    local EUI = _G.EllesmereUI
    if EUI and EUI.IsAnchored and EUI.IsAnchored(unlockKey) then
        if EUI.ReapplyOwnAnchor then EUI.ReapplyOwnAnchor(unlockKey) end
        return
    end
    frame:ClearAllPoints()
    if type(pos) == "table" then
        local point = pos.point or defaultPoint
        frame:SetPoint(point, UIParent, pos.relPoint or point, tonumber(pos.x) or 0, tonumber(pos.y) or 0)
    else
        frame:SetPoint(defaultPoint, UIParent, defaultPoint, x, y)
    end
end

local function Place(kind)
    local w = widgets[kind]
    if not w then return end
    w.kuiPlaced = true
    X.PlaceFrame(w.frame, UNLOCK_KEY[kind], Get(kind == "xp" and "xpPos" or "fbPos"), "TOP", 0, DEFAULT_Y[kind])
end

-- A session's drag or arrow key lives only on the frame until Save & Exit reads it
-- back from there, so while Unlock Mode is open only a save moves a placed frame.
local function PlaceOutsideSession(kind)
    local w = widgets[kind]
    if w and not (X.UnlockActive and w.kuiPlaced) then Place(kind) end
end

local function Tick()
    clock = nil
    if not active then return end
    RefreshXP()
    X.ApplyVisibility()
end

-- One timer aimed at the next whole minute of the session, only while the
-- XP bar draws a time or rate text. The drawn texts decide, not the
-- switches: at max level only the session time is drawn.
function X.UpdateClock()
    local w = widgets.xp
    local need = active and w and Plain(w.frame:IsShown()) == true and X.XPEnabled()
        and (xpData.levelTime or xpData.sessionTime or xpData.rate) ~= nil
    if not need then
        if clock then
            clock:Cancel()
            clock = nil
        end
        return
    end
    if clock or not (C_Timer and C_Timer.NewTimer) then return end
    local delay = 60 - (X.SessionElapsed() % 60)
    if delay < 1 then delay = delay + 60 end
    clock = C_Timer.NewTimer(delay, Tick)
end

function X.ApplyVisibility()
    if not active then return end
    if widgets.xp then
        Show("xp", X.XPEnabled() and xpShown and Eval(Get("xpVisibility")))
        PlaceOutsideSession("xp")
    end
    if widgets.fb then
        Show("fb", X.FactionEnabled() and fbShown and Eval(Get("fbVisibility")))
        PlaceOutsideSession("fb")
    end
    X.UpdateClock()
    X.TickerVisibility()
end

---------------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------------

local function TipAllowed(p)
    if Get(p .. "Tooltip") ~= true or not GameTooltip then return false end
    return not (Get(p .. "TooltipCombat") == true and InCombatLockdown())
end

local function TipLine(label, value)
    GameTooltip:AddDoubleLine(label, value, LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
end

local function ShowXPTooltip(self)
    if not TipAllowed("xp") then return end
    local t = X.ReadXP()
    local style, breakUp = Get("xpNumberStyle"), _G.BreakUpLargeNumbers
    local mx = t.max
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if t.atMax or mx <= 0 then
        GameTooltip:AddLine(format("Level %d", t.level), 1, 1, 1)
        GameTooltip:AddLine("Max Level", 1, 1, 1)
    else
        local left = max(0, mx - t.cur)
        TipLine(format("Level %d", t.level), format("%.1f%%", t.cur * 100 / mx))
        TipLine("Experience", M.Number(t.cur, style, breakUp) .. " / " .. M.Number(mx, style, breakUp))
        TipLine("Remaining", M.Number(left, style, breakUp))
        if t.rested > 0 or t.resting then
            local rested = format("%s (%.1f%%)", M.Number(t.rested, style, breakUp), t.rested * 100 / mx)
            TipLine("Rested", t.resting and (rested .. ", Resting") or rested)
        end
        if questDone > 0 or questOpen > 0 then GameTooltip:AddLine(" ") end
        if questDone > 0 then
            TipLine("Completed quests", questDone >= left and "Enough to level"
                or format("%s (%.1f%%)", M.Number(questDone, style, breakUp), questDone * 100 / mx))
        end
        if questOpen > 0 then TipLine("Quests in progress", M.Number(questOpen, style, breakUp)) end
        GameTooltip:AddLine(" ")
        local gained = X.SessionGained()
        local perHour, eta = M.Rate(gained, X.SessionElapsed(), left)
        TipLine("This session", M.Number(gained, style, breakUp))
        if perHour then
            TipLine("XP per hour", M.Number(floor(perHour), style, breakUp))
            TipLine("Time to level", M.TimeText(eta))
        end
        local kills
        if ns.IS_FOREVER then
            kills = M.KillsToLevel(left, t.rested, M.ForeverKillXP(t.level))
        else
            local average = M.KillAverage(X.Kills())
            kills = average and M.KillsToLevel(left, 0, average)
        end
        if kills then TipLine("Kills to level", kills == 1 and "About 1 kill" or format("About %d kills", kills)) end
    end
    X.PartyTooltipLines(GameTooltip)
    GameTooltip:Show()
end

local function ShowFactionTooltip(self)
    if not TipAllowed("fb") or not factionRec then return end
    local rec = factionRec
    local style, breakUp = Get("xpNumberStyle"), _G.BreakUpLargeNumbers
    local pct, inSpan, span = M.FactionProgress(rec)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(rec.name or "", 1, 1, 1)
    TipLine(rec.label or "", format("%.1f%%", pct or 0))
    if (span or 0) > 0 then
        TipLine("Progress", M.Number(inSpan, style, breakUp) .. " / " .. M.Number(span, style, breakUp))
    end
    if rec.paragon and rec.paragon.pending then GameTooltip:AddLine("Reward ready", 0.2, 1, 0.2) end
    GameTooltip:Show()
end

local function HideTooltip(self)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- A bar's open tooltip comes down once it is no longer allowed: on entering
-- combat with Hide Tooltip in Combat on, with its switch turned off, or with
-- the bar itself hidden. The visibility service calls in on every combat
-- edge, and every apply does.
local function DropTooltips()
    if not (GameTooltip and GameTooltip.IsOwned) then return end
    for kind, w in pairs(widgets) do
        if GameTooltip:IsOwned(w.frame) and not (Plain(w.frame:IsShown()) == true and TipAllowed(kind)) then
            GameTooltip:Hide()
        end
    end
end

-- Hover only: clicks pass through to whatever is under the bar. Applied on
-- every show and after every EnableMouse: the hover service enables the
-- whole mouse when it reveals a frame, and on a bar already shown that
-- reveal runs no OnShow.
local function SetMouse(frame)
    local tip = Get(frame.kuiPrefix .. "Tooltip") == true
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(tip) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
end

local function OnWidgetShow(self)
    SetMouse(self)
    if self.kuiPrefix == "xp" then RefreshXP() end
    X.UpdateClock()
end

local function OnWidgetHide(self)
    X.StopEffects(widgets[self.kuiPrefix])
    X.UpdateClock()
end

local function MakeWidget(kind)
    local w = X.NewWidget(UIParent, kind)
    local frame = w.frame
    frame.kuiPrefix = kind
    hooksecurefunc(frame, "EnableMouse", SetMouse)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:Hide()
    frame:SetScript("OnEnter", kind == "xp" and ShowXPTooltip or ShowFactionTooltip)
    frame:SetScript("OnLeave", HideTooltip)
    frame:SetScript("OnShow", OnWidgetShow)
    frame:SetScript("OnHide", OnWidgetHide)
    widgets[kind] = w
    return w
end

---------------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------------

-- Fills the totals only while they are observed: a scan that outlived its
-- events, however it got past the cancel, leaves them cleared.
local function QuestScan()
    questTimer = nil
    if not questFresh then return end
    questDone, questOpen = X.ScanQuestXP()
    RefreshXP()
    X.ApplyVisibility()
end

function ArmQuestScan()
    if questTimer or not (C_Timer and C_Timer.NewTimer) then return end
    questTimer = C_Timer.NewTimer(QUEST_SCAN_DELAY, QuestScan)
end

-- With the XP reading RefreshXP just kept. The profession fill's pass is not
-- gated here: it has its own Play on XP Gain.
local function XPGainMoment()
    local w = widgets.xp
    if not w or Get("xpGainEffect") == "off" then return end
    local gain, from, to = M.XPGainStep(xpStep, raw.cur, raw.max, raw.level, GetTime())
    if gain and Get("xpGainQuestsOnly") ~= true then X.PlayGainEffect(w, Get, xpData, from, to, gain) end
end

-- Plays from the event, not from a reading: a reading cannot say what caused it,
-- so pairing them would let a kill stand in for a quest or lose a quest's gain.
local function QuestMoment(reward)
    local w = widgets.xp
    if not w or Get("xpGainEffect") == "off" or Get("xpGainQuestsOnly") ~= true then return end
    local t = X.ReadXP()
    if t.xpOff then return end
    local atMax, spent = t.atMax, turnInLevel == t.level
    turnInLevel = type(levelUpTo) == "number" and levelUpTo > t.level and levelUpTo or t.level
    if atMax then ReconcileEvents() end
    if (atMax and spent) or type(reward) ~= "number" or reward <= 0 then return end
    local from, to = 0, 100
    if not atMax then
        from, to = M.QuestSpan(xpStep, t.cur, t.max, t.level, reward, GetTime(), QUEST_GAIN_WINDOW)
    end
    if from then X.PlayGainEffect(w, Get, xpData, from, to, reward, true) end
end

local function FactionReading()
    local rec = factionRec
    if not rec then return M.FactionStep(fbStep, nil) end
    return M.FactionStep(fbStep, rec.id, rec.kind, rec.rank, rec.total, fbData.fill, rec.isMax)
end

local function FactionMoment()
    local w = widgets.fb
    if not w then return end
    local moment, amount, from = FactionReading()
    if moment == "rank" then
        X.PlayLevelEffect(w, Get)
    elseif moment == "gain" then
        X.PlayGainEffect(w, Get, fbData, from, fbData.fill, amount)
    end
end

-- The first reading after an apply plays nothing: a login, a /reload, a bar
-- turned on and a setting changed all land here.
local function SeedEffects(xpOn, fbOn)
    xpStep.x, xpStep.gainAt = nil, nil
    if xpOn then
        local t = X.ReadXP()
        M.XPGainStep(xpStep, t.cur, t.max, t.level)
    end
    fbStep.id = nil
    if fbOn then FactionReading() end
end

local function OnEvent(_, event, ...)
    if event == "PLAYER_LOGOUT" then
        X.SessionSave()
        return
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local gain = X.ParseKillXP((...))
        if gain then X.OnKill(gain) end
        return
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
        ArmQuestScan()
        return
    elseif event == "QUEST_TURNED_IN" then
        QuestMoment(Plain((select(2, ...))))
        return
    elseif event == "PLAYER_XP_UPDATE" then
        X.OnXP()
        RefreshXP()
        XPGainMoment()
        if widgets.xp then X.PlayGain(widgets.xp) end
    elseif event == "PLAYER_LEVEL_UP" then
        X.OnLevelUp((...))
        RefreshXP()
        levelUpTo = Plain((...))
        X.PlayLevelEffect(widgets.xp, Get)
        ReconcileEvents()
    elseif event == "TIME_PLAYED_MSG" then
        X.OnPlayed(...)
        RefreshXP()
    elseif event == "UPDATE_FACTION" or event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED"
        or event == "ZONE_CHANGED_NEW_AREA" then
        RefreshFaction()
        FactionMoment()
    else
        -- The cap, rested and XP-gain events can carry a mixed level-up
        -- reading too; Track takes each one.
        X.OnXP()
        RefreshXP()
        ReconcileEvents()
        -- At max level the party path has no event of its own to hear a new cap.
        if event == "PLAYER_MAX_LEVEL_UPDATE" or event == "MAX_EXPANSION_LEVEL_UPDATED" then X.PartyApply() end
    end
    X.ApplyVisibility()
end

---------------------------------------------------------------------------------
-- Unlock Mode
---------------------------------------------------------------------------------

local function ClampSize(key, v)
    local range = X.RANGES[key]
    v = tonumber(v) or Get(key)
    return floor(max(range[1], min(range[2], v)) + 0.5)
end

local function UnlockElement(EUI, kind, key, label, order, posKey, widthKey, heightKey, enabled)
    return EUI.MakeUnlockElement({
        key = key, label = label, group = "KitnUI", order = order,
        isHidden = function() return not enabled() end,
        -- Never creates: Unlock Mode asks at login and on every zone change,
        -- whether or not the bar is on. Apply() owns creation.
        getFrame = function() return widgets[kind] and widgets[kind].frame end,
        getSize = function() return Get(widthKey), Get(heightKey) end,
        savePos = function(_, point, relPoint, x, y)
            Set(posKey, { point = point, relPoint = relPoint, x = x, y = y })
            Place(kind)
        end,
        -- A copy: Unlock Mode is free to keep or change what it is given.
        loadPos = function()
            local p = Get(posKey)
            if type(p) ~= "table" then return nil end
            return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
        end,
        -- Spec layouts read these instead of loadPos and savePos.
        loadRawPos = function() return M.RawSpot(Get(posKey)) end,
        saveRawPos = function(_, banked)
            Set(posKey, M.StoredSpot(banked))
            Place(kind)
        end,
        clearPos = function() Set(posKey, nil) end,
        applyPos = function() PlaceOutsideSession(kind) end,
        setWidth = function(_, v)
            Set(widthKey, ClampSize(widthKey, v))
            X.Apply()
            if X.PreviewRefresh then X.PreviewRefresh() end
        end,
        setHeight = function(_, v)
            Set(heightKey, ClampSize(heightKey, v))
            X.Apply()
            if X.PreviewRefresh then X.PreviewRefresh() end
        end,
    })
end

-- The bars' and the ticker's elements. The Party Card keeps its own, for its own
-- listener, since it works with both bars off.
local barElements = {}

-- While noInitHook is up, Unlock Mode's position pass, which runs on every zone
-- change, skips the element, and its resize path calls only applyPos, which holds.
local function FlagElements(on)
    for i = 1, #barElements do barElements[i].noInitHook = on end
end

-- Registered once and never unregistered: unregistering an element deletes
-- every anchor link the player made to it.
function X.EnsureUnlock()
    if unlockDone then return end
    unlockDone = true
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterUnlockElements and EUI.MakeUnlockElement) then return end
    barElements = {
        UnlockElement(EUI, "xp", UNLOCK_KEY.xp, "KitnUI XP Bar", 3, "xpPos", "xpWidth", "xpHeight", X.XPEnabled),
        UnlockElement(EUI, "fb", UNLOCK_KEY.fb, "KitnUI Reputation Bar", 4, "fbPos", "fbWidth", "fbHeight", X.FactionEnabled),
        X.TickerElement(EUI),
    }
    EUI:RegisterUnlockElements({
        barElements[1], barElements[2], barElements[3], X.PartyElement(EUI),
    }, "KitnUI_EUI")
end

local function RegisterAccent()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegAccent) then return end
    EUI.RegAccent({ type = "callback", fn = function()
        X.TickerAccent()
        if Get("xpFillStyle") ~= "accent" then return end
        if active and X.XPEnabled() then RefreshXP() end
        if X.PreviewRefresh then X.PreviewRefresh() end
    end })
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

local function VisUpdater()
    if not active then return end
    X.ApplyVisibility()
    DropTooltips()
end

local function OnUnlockMode(on)
    X.UnlockActive = on == true
    FlagElements(X.UnlockActive)
    for _, w in pairs(widgets) do X.StopEffects(w) end
    if not X.UnlockActive and active then
        RefreshXP()
        RefreshFaction()
        X.ApplyVisibility()
    end
end

local function OnLoginKnown(kind)
    X.SessionStart(kind)
    if active then ReconcileEvents() end
    if active and X.XPEnabled() then
        X.TickerApply()
        RefreshXP()
        SeedEffects(true, X.FactionEnabled())
        X.RequestPlayed()
        X.ApplyVisibility()
    end
end

-- Everything a bar needs, made on the first apply that finds one enabled.
local function Ensure()
    if active then return end
    active = true
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", OnEvent)
    end
    X.EnsureUnlock()
    if not accentDone then
        accentDone = true
        RegisterAccent()
    end
    local EUI = _G.EllesmereUI
    if EUI and EUI.RegisterVisibilityUpdater then EUI.RegisterVisibilityUpdater(VisUpdater) end
    if EUI and EUI.RegisterUnlockModeListener then EUI:RegisterUnlockModeListener(X, OnUnlockMode) end
    if not sessionQueued then
        sessionQueued = true
        if ns.EUIWhenLoginKnown then ns.EUIWhenLoginKnown(OnLoginKnown) else OnLoginKnown("login") end
    end
end

-- Saves the session, then cancels every timer, unregisters every event,
-- leaves the visibility service and hides both bars.
local function Stop()
    if not active then return end
    X.SessionListen(false)
    X.SessionSave()
    X.SessionStop()
    X.TickerStop()
    xpWasOn = false
    if questTimer then
        questTimer:Cancel()
        questTimer = nil
    end
    if clock then
        clock:Cancel()
        clock = nil
    end
    if ev then
        for e in pairs(registered) do
            ev:UnregisterEvent(e)
            registered[e] = nil
        end
    end
    local EUI = _G.EllesmereUI
    if EUI and EUI.UnregisterVisibilityUpdater then EUI.UnregisterVisibilityUpdater(VisUpdater) end
    if EUI and EUI.UnregisterUnlockModeListener then EUI:UnregisterUnlockModeListener(X) end
    X.UnlockActive = false
    FlagElements(false)
    active = false
    questFresh = false
    for _, w in pairs(widgets) do
        if w.mouseover and EUI and EUI.UnregisterMouseoverTarget then EUI.UnregisterMouseoverTarget(w.frame) end
        w.mouseover = false
        X.StopEffects(w)
        w.frame:Hide()
    end
    DropTooltips()
end

-- The one reconcile path: the re-apply registry, every option setter, Unlock
-- Mode and the switches all land here. claim is "xp" or "rep" only from a
-- click on that bar's Enable or Hide Existing switch.
function X.Apply(claim)
    local xpOn, fbOn = X.XPEnabled(), X.FactionEnabled()
    if not (xpOn or fbOn) then
        Stop()
        X.SyncExisting(claim)
        X.PartyApply()
        return
    end
    Ensure()
    if xpOn and not widgets.xp then MakeWidget("xp") end
    if fbOn and not widgets.fb then MakeWidget("fb") end
    for _, w in pairs(widgets) do
        X.StopEffects(w)
        SetMouse(w.frame)
    end
    -- The XP bar going off while the faction bar stays: Stop does not run,
    -- so the session stops listening and is saved here.
    if xpWasOn and not xpOn then
        X.SessionListen(false)
        X.SessionSave()
    end
    xpWasOn = xpOn
    ReconcileEvents()
    X.TickerApply()
    if xpOn then
        X.SessionListen(true)
        X.SeedPosition()
        -- XP earned while the bar was off joins the session, which kept
        -- counting time: time and XP cover the same span.
        X.OnXP()
        RefreshXP()
        X.RequestPlayed()
    end
    if fbOn then RefreshFaction() end
    SeedEffects(xpOn, fbOn)
    X.ApplyVisibility()
    DropTooltips()
    X.SyncExisting(claim)
    X.PartyApply()
end

-- For the reset: everything off, and every hidden bar given back whatever the
-- switches say.
function X.Teardown()
    Stop()
    X.SyncExisting(nil, true)
    X.PartyStop()
end

ns.EUIRegisterReapply(function()
    X.Apply()
end)
