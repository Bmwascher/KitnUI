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
-- EllesmereUI builds its XP bar a moment after login: the first spot is read
-- again every SEED_RETRY seconds until it exists, at most SEED_TRIES times.
local SEED_RETRY = 1
local SEED_TRIES = 10
local DEFAULT_Y = { xp = -100, fb = -160 }
local LABEL_R, LABEL_G, LABEL_B = 1, 0.82, 0

local XP_EVENTS = {
    "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
    "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "PLAYER_MAX_LEVEL_UPDATE", "MAX_EXPANSION_LEVEL_UPDATED",
    "PLAYER_LOGOUT", "TIME_PLAYED_MSG",
}
local ALL_EVENTS = {}
for i = 1, #XP_EVENTS do ALL_EVENTS[i] = XP_EVENTS[i] end
for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "CHAT_MSG_COMBAT_XP_GAIN",
    "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
    ALL_EVENTS[#ALL_EVENTS + 1] = e
end

local ev
local active = false
local unlockDone, accentDone, sessionQueued, questFresh = false, false, false, false
local xpWasOn = false
local widgets = {}
local registered, wanted, wantOpts = {}, {}, {}
local questTimer, clock, seedTimer
local seedTries = 0
local questDone, questOpen = 0, 0
-- Defined with the event handlers; ReconcileEvents arms it.
local ArmQuestScan
local raw, xpData, fbData = {}, {}, {}
local factionRec
local xpShown, fbShown = true, false
local visCfg = { visibility = "always" }

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------

-- Fills `out` with the events the enabled bars need. opts: quest (a quest
-- overlay, completed line or tooltip needs quest XP), kills (retail tooltip
-- below max level), companion (faction source follows the delve).
function X.WantedEvents(out, xpOn, fbOn, opts)
    for i = 1, #ALL_EVENTS do out[ALL_EVENTS[i]] = nil end
    if xpOn then
        for i = 1, #XP_EVENTS do out[XP_EVENTS[i]] = true end
        if opts.quest then
            out.QUEST_LOG_UPDATE = true
            out.UNIT_QUEST_LOG_CHANGED = true
        end
        if opts.kills then out.CHAT_MSG_COMBAT_XP_GAIN = true end
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
        and (Get("xpShowQuest") == true or Get("xpShowCompRested") == true or Get("xpTooltip") == true)
    wantOpts.kills = leveling and not ns.IS_FOREVER and Get("xpTooltip") == true
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
    out.sessionTime = view("xpShowSessionTime") and ("Time this session: " .. M.TimeText(r.elapsed)) or nil
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
    raw.quest = questDone
    raw.levelTime, raw.elapsed, raw.gained = X.LevelTime(), X.SessionElapsed(), X.SessionGained()
    X.XPView(raw, Get, xpData)
    X.Draw(w, Get, xpData)
    xpShown = t.applies or Get("xpShowAtMax") == true
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

-- An Unlock Mode anchor link is an anchored bar's only placing authority, as
-- it is for EUI's own frames: the bar is put back on its link, never on its
-- saved spot. An unanchored bar sits on its own saved spot.
local function Place(kind)
    local w = widgets[kind]
    if not w then return end
    local frame = w.frame
    local EUI = _G.EllesmereUI
    if EUI and EUI.IsAnchored and EUI.IsAnchored(UNLOCK_KEY[kind]) then
        if EUI.ReapplyOwnAnchor then EUI.ReapplyOwnAnchor(UNLOCK_KEY[kind]) end
        return
    end
    local pos = Get(kind == "xp" and "xpPos" or "fbPos")
    local fallbackY = DEFAULT_Y[kind]
    frame:ClearAllPoints()
    if type(pos) == "table" then
        local point = pos.point or "TOP"
        frame:SetPoint(point, UIParent, pos.relPoint or point, tonumber(pos.x) or 0, tonumber(pos.y) or 0)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, fallbackY)
    end
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
    local need = active and w and w.frame:IsShown() and X.XPEnabled()
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
        Place("xp")
    end
    if widgets.fb then
        Show("fb", X.FactionEnabled() and fbShown and Eval(Get("fbVisibility")))
        Place("fb")
    end
    X.UpdateClock()
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
        if questDone > 0 then
            TipLine("Completed quests", questDone >= left and "Enough to level"
                or format("%s (%.1f%%)", M.Number(questDone, style, breakUp), questDone * 100 / mx))
        end
        if questOpen > 0 then TipLine("Quests in progress", M.Number(questOpen, style, breakUp)) end
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
        if GameTooltip:IsOwned(w.frame) and not (w.frame:IsShown() and TipAllowed(kind)) then
            GameTooltip:Hide()
        end
    end
end

-- Hover only: clicks pass through to whatever is under the bar. Applied on
-- every show too, because the hover service enables the whole mouse when it
-- reveals a frame.
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

local function OnWidgetHide()
    X.UpdateClock()
end

local function MakeWidget(kind)
    local w = X.NewWidget(UIParent, kind)
    local frame = w.frame
    frame.kuiPrefix = kind
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
    elseif event == "PLAYER_XP_UPDATE" then
        X.OnXP()
        RefreshXP()
        if widgets.xp then X.PlayGain(widgets.xp) end
    elseif event == "PLAYER_LEVEL_UP" then
        X.OnLevelUp((...))
        RefreshXP()
        ReconcileEvents()
    elseif event == "TIME_PLAYED_MSG" then
        X.OnPlayed(...)
        RefreshXP()
    elseif event == "UPDATE_FACTION" or event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED"
        or event == "ZONE_CHANGED_NEW_AREA" then
        RefreshFaction()
    else
        -- The cap, rested and XP-gain events can carry a mixed level-up
        -- reading too; Track takes each one.
        X.OnXP()
        RefreshXP()
        ReconcileEvents()
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
        clearPos = function() Set(posKey, nil) end,
        applyPos = function() Place(kind) end,
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

-- Registered once and never unregistered: unregistering an element deletes
-- every anchor link the player made to it.
local function RegisterUnlock()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterUnlockElements and EUI.MakeUnlockElement) then return end
    EUI:RegisterUnlockElements({
        UnlockElement(EUI, "xp", UNLOCK_KEY.xp, "KitnUI XP Bar", 3, "xpPos", "xpWidth", "xpHeight", X.XPEnabled),
        UnlockElement(EUI, "fb", UNLOCK_KEY.fb, "KitnUI Faction Bar", 4, "fbPos", "fbWidth", "fbHeight", X.FactionEnabled),
    }, "KitnUI_EUI")
end

local function RegisterAccent()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegAccent) then return end
    EUI.RegAccent({ type = "callback", fn = function()
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

local function OnLoginKnown(kind)
    X.SessionStart(kind)
    if active then ReconcileEvents() end
    if active and X.XPEnabled() then
        RefreshXP()
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
    if not unlockDone then
        unlockDone = true
        RegisterUnlock()
    end
    if not accentDone then
        accentDone = true
        RegisterAccent()
    end
    local EUI = _G.EllesmereUI
    if EUI and EUI.RegisterVisibilityUpdater then EUI.RegisterVisibilityUpdater(VisUpdater) end
    if not sessionQueued then
        sessionQueued = true
        if ns.EUIWhenLoginKnown then ns.EUIWhenLoginKnown(OnLoginKnown) else OnLoginKnown("login") end
    end
end

local SeedRetry

-- Bounded per load: past SEED_TRIES, only a later apply reads the spot again.
local function ArmSeedRetry()
    if seedTimer or seedTries >= SEED_TRIES or not (C_Timer and C_Timer.NewTimer) then return end
    seedTries = seedTries + 1
    seedTimer = C_Timer.NewTimer(SEED_RETRY, SeedRetry)
end

function SeedRetry()
    seedTimer = nil
    if not (active and X.XPEnabled()) then return end
    if X.SeedPosition() then
        Place("xp")
    else
        ArmSeedRetry()
    end
end

-- Saves the session, then cancels every timer, unregisters every event,
-- leaves the visibility service and hides both bars.
local function Stop()
    if not active then return end
    X.SessionListen(false)
    X.SessionSave()
    X.SessionStop()
    xpWasOn = false
    if questTimer then
        questTimer:Cancel()
        questTimer = nil
    end
    if seedTimer then
        seedTimer:Cancel()
        seedTimer = nil
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
    active = false
    questFresh = false
    for _, w in pairs(widgets) do
        if w.mouseover and EUI and EUI.UnregisterMouseoverTarget then EUI.UnregisterMouseoverTarget(w.frame) end
        w.mouseover = false
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
        return
    end
    Ensure()
    if xpOn and not widgets.xp then MakeWidget("xp") end
    if fbOn and not widgets.fb then MakeWidget("fb") end
    for _, w in pairs(widgets) do SetMouse(w.frame) end
    -- The XP bar going off while the faction bar stays: Stop does not run,
    -- so the session stops listening and is saved here.
    if xpWasOn and not xpOn then
        X.SessionListen(false)
        X.SessionSave()
    end
    xpWasOn = xpOn
    ReconcileEvents()
    if xpOn then
        X.SessionListen(true)
        if not X.SeedPosition() then ArmSeedRetry() end
        -- XP earned while the bar was off joins the session, which kept
        -- counting time: time and XP cover the same span.
        X.OnXP()
        RefreshXP()
        X.RequestPlayed()
    end
    if fbOn then RefreshFaction() end
    X.ApplyVisibility()
    DropTooltips()
    X.SyncExisting(claim)
end

-- For the reset: everything off, and every hidden bar given back whatever the
-- switches say.
function X.Teardown()
    Stop()
    X.SyncExisting(nil, true)
end

ns.EUIRegisterReapply(function()
    X.Apply()
end)
