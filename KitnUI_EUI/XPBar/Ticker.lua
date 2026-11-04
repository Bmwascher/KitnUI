-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Ticker.lua                                 ║
-- ║  Purpose: The XP ticker card: XP per hour, time to level,    ║
-- ║           the level's clock, completed levels, total played  ║
-- ║           and the pace against other characters.             ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
local M = X.Math

local Plain = ns.EUIPlain
local Get = X.Get

local format, floor, ceil, abs, min = string.format, math.floor, math.ceil, math.abs, math.min

local UNLOCK_KEY = "KitnUI_XPTicker"
local ARROW = "Interface\\AddOns\\KitnUI_EUI\\Media\\XPBar\\arrow"
-- The current level, ten completed levels, Played and Pace.
local MAX_ROWS = 13
-- Seconds to level below which Ding takes the accent color.
local DING_URGENT = 600
-- Lines in the Pace tooltip.
local TIP_ROWS = 8
-- Sizes, as multiples of the font size.
local TOP_SCALE, PAD_SCALE, ARROW_GAP, BUTTON_W = 1.35, 0.5, 0.3, 4
local UP_R, UP_G, UP_B = 0.3, 0.9, 0.3
local DOWN_R, DOWN_G, DOWN_B = 0.95, 0.3, 0.3
local BACKGROUNDS = { card = { 0.05, 0.05, 0.05, 0.85 }, soft = { 0, 0, 0, 0.35 } }
X.CARD_BACKGROUNDS = BACKGROUNDS
-- Where a card sits until it is moved, clear of the bars' default spots.
local FIRST_X, FIRST_Y = 40, 120

local live, timer, liveRaw
local cardData, trendState = {}, {}
local hist = { n = 0, levels = {}, texts = {} }
local histGen, histLevel, histRows
-- Other characters with a played time at both ends of this level, in parallel
-- arrays: filled once per level, read on every tick.
local peerKey, peerAt, peerNext = {}, {}, {}
local peerCount, peersLevel = 0, nil

---------------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------------

-- Builds the card's texts from a raw record, the live one or the preview's.
-- r: level, cur, max, levelTime, elapsed, gained, paused, trend, played, pace,
-- hist.
function X.TickerView(r, view, out)
    out.left, out.right, out.keys = out.left or {}, out.right or {}, out.keys or {}
    local perHour, eta = M.Rate(r.gained, r.elapsed, (r.max or 0) - (r.cur or 0))
    out.rate = perHour and M.RateText(perHour) or "no XP yet"
    out.arrow = (perHour and not r.paused) and r.trend or nil
    out.ding = r.paused and "paused" or ("Ding " .. M.TimeText(eta))
    out.urgent = not r.paused and type(eta) == "number" and eta > 0 and eta < DING_URGENT
    out.pauseText = r.paused and "Start" or "Pause"
    local n = 0
    if view("xpTickerShowCurrent") == true then
        n = n + 1
        local pct = (r.max or 0) > 0 and floor((r.cur or 0) * 100 / r.max) or 0
        out.left[n], out.right[n], out.keys[n] = format("Level %d", r.level or 0),
            format("%s  %d%%", M.ClockText(r.levelTime), pct), "tkCurrent"
    end
    local h = r.hist
    if h then
        for i = 1, min(h.n, tonumber(view("xpTickerHistoryRows")) or 0) do
            n = n + 1
            out.left[n], out.right[n], out.keys[n] = format("Level %d", h.levels[i]), h.texts[i], "tkHistory"
        end
    end
    if view("xpTickerShowPlayed") == true then
        n = n + 1
        out.left[n], out.right[n], out.keys[n] = "Played", M.TimeText(r.played), "tkPlayed"
    end
    if view("xpTickerShowPace") == true then
        n = n + 1
        out.left[n], out.right[n], out.keys[n] = "Pace", M.PaceText(r.pace), "tkPace"
    end
    out.n = n
    return out
end

---------------------------------------------------------------------------------
-- The widget
---------------------------------------------------------------------------------

local function NewText(card)
    local fs = card:CreateFontString(nil, "OVERLAY")
    fs:SetWordWrap(false)
    fs:SetTextColor(1, 1, 1, 1)
    return fs
end

local function NewButton(card)
    local b = CreateFrame("Button", nil, card)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetAllPoints(b)
    b.text:SetWordWrap(false)
    b.text:SetTextColor(1, 1, 1, 1)
    b:Hide()
    return b
end

-- Registers nothing: the live path adds what a card on screen needs.
function X.NewCard(parent)
    local card = CreateFrame("Frame", nil, parent or UIParent)
    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetAllPoints(card)
    card.edge = CreateFrame("Frame", nil, card)
    card.edge:SetAllPoints(card)
    card.top, card.topR = NewText(card), NewText(card)
    card.arrow = card:CreateTexture(nil, "ARTWORK")
    card.arrow:SetTexture(ARROW)
    card.arrow:Hide()
    card.left, card.right = {}, {}
    for i = 1, MAX_ROWS do
        card.left[i], card.right[i] = NewText(card), NewText(card)
        card.left[i]:Hide()
        card.right[i]:Hide()
    end
    card.pauseBtn, card.resetBtn = NewButton(card), NewButton(card)
    card.paceHover = CreateFrame("Frame", nil, card)
    card.paceHover:Hide()
    card.dirty = true
    return card
end

local function SetFont(fs, font, size, flags)
    if not fs:SetFont(font, size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
end

-- Only when a setting changed: every size is a multiple of the font size.
local function StyleCard(card, view)
    card.dirty = false
    local size = tonumber(view("xpTickerFontSize")) or 12
    local topSize = ceil(size * TOP_SCALE)
    local font, flags = X.FontPath(view("xpTickerFont")), X.OutlineFlag(view("xpTickerOutline"))
    local pad, rowH, topH = ceil(size * PAD_SCALE), M.RowHeight(size), M.RowHeight(topSize)
    card.pad, card.rowH, card.topH, card.kuiW = pad, rowH, topH, M.TickerWidth(size)
    card:SetWidth(card.kuiW)
    SetFont(card.top, font, topSize, flags)
    SetFont(card.topR, font, size, flags)
    SetFont(card.pauseBtn.text, font, size, flags)
    SetFont(card.resetBtn.text, font, size, flags)
    card.resetBtn.text:SetText("Reset")
    card.top:ClearAllPoints()
    card.top:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -pad)
    card.topR:ClearAllPoints()
    card.topR:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, -pad)
    card.arrow:SetSize(size, size)
    card.arrow:ClearAllPoints()
    card.arrow:SetPoint("LEFT", card.top, "RIGHT", ceil(size * ARROW_GAP), 0)
    card.resetBtn:SetSize(size * BUTTON_W, rowH)
    card.resetBtn:ClearAllPoints()
    card.resetBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, -pad)
    card.pauseBtn:SetSize(size * BUTTON_W, rowH)
    card.pauseBtn:ClearAllPoints()
    card.pauseBtn:SetPoint("RIGHT", card.resetBtn, "LEFT", -pad, 0)
    for i = 1, MAX_ROWS do
        local y = -(pad + topH + (i - 1) * rowH)
        SetFont(card.left[i], font, size, flags)
        SetFont(card.right[i], font, size, flags)
        card.left[i]:ClearAllPoints()
        card.left[i]:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
        card.right[i]:ClearAllPoints()
        card.right[i]:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, y)
    end
    local mode = view("xpTickerBackground")
    local bg = BACKGROUNDS[mode]
    if bg then
        card.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
        card.bg:Show()
    else
        card.bg:Hide()
    end
    card.edge:SetShown(mode == "card")
    local EUI = _G.EllesmereUI
    if mode == "card" and EUI and EUI.ApplyBorderStyle then
        pcall(EUI.ApplyBorderStyle, card.edge, 1, 0, 0, 0, 1, "solid")
    end
    card.rowsShown = nil
end

-- An unchanged text is not redrawn: the tick compares every row.
local function SetKept(fs, text)
    if fs.kuiText ~= text then
        fs.kuiText = text
        fs:SetText(text)
    end
end

local function SyncArrow(card, dir)
    if card.arrowDir == dir then return end
    card.arrowDir = dir
    if dir == "up" then
        card.arrow:SetTexCoord(0, 1, 0, 1)
        card.arrow:SetVertexColor(UP_R, UP_G, UP_B, 1)
    elseif dir == "down" then
        card.arrow:SetTexCoord(0, 1, 1, 0)
        card.arrow:SetVertexColor(DOWN_R, DOWN_G, DOWN_B, 1)
    end
    card.arrow:SetShown(dir ~= nil)
end

function X.DrawCard(card, view, data)
    if card.dirty then StyleCard(card, view) end
    SetKept(card.top, data.rate)
    SetKept(card.topR, data.ding)
    SetKept(card.pauseBtn.text, data.pauseText)
    SyncArrow(card, data.arrow)
    if card.urgent ~= data.urgent then
        card.urgent = data.urgent
        local r, g, b = 1, 1, 1
        if data.urgent then
            local ar, ag, ab = X.AccentColor()
            if ar then r, g, b = ar, ag, ab end
        end
        card.topR:SetTextColor(r, g, b, 1)
    end
    if data.n ~= card.rowsShown then
        card.rowsShown = data.n
        for i = 1, MAX_ROWS do
            local on = i <= data.n
            card.left[i]:SetShown(on)
            card.right[i]:SetShown(on)
        end
        card.kuiH = card.pad * 2 + card.topH + data.n * card.rowH
        card:SetHeight(card.kuiH)
    end
    for i = 1, data.n do
        SetKept(card.left[i], data.left[i])
        SetKept(card.right[i], data.right[i])
    end
    -- Pace is the last row while it is on.
    local paceRow = data.keys[data.n] == "tkPace" and data.n or nil
    if card.isLive and paceRow ~= card.paceRow then
        card.paceRow = paceRow
        card.paceHover:ClearAllPoints()
        if paceRow then
            card.paceHover:SetPoint("TOPLEFT", card.left[paceRow], "TOPLEFT")
            card.paceHover:SetPoint("BOTTOMRIGHT", card.right[paceRow], "BOTTOMRIGHT")
        end
        card.paceHover:SetShown(paceRow ~= nil)
    end
end

---------------------------------------------------------------------------------
-- History and peers
---------------------------------------------------------------------------------

local function SyncHistory(level, rows)
    local gen = X.HistoryGen()
    if gen == histGen and level == histLevel and rows == histRows then return end
    histGen, histLevel, histRows = gen, level, rows
    local h = X.History(false)
    local splits = h and h.splits
    local n = 0
    if type(splits) == "table" and type(level) == "number" then
        for lv = level - 1, 1, -1 do
            if n >= rows then break end
            local secs = splits[lv]
            if type(secs) == "number" then
                n = n + 1
                hist.levels[n], hist.texts[n] = lv, M.ClockText(secs)
            end
        end
    end
    hist.n = n
end

-- The saves of other characters cannot change during this session, so one
-- walk per level is enough.
local function FillPeers(level)
    peersLevel, peerCount = level, 0
    local chars = ns.db and ns.db.perChar
    if type(chars) ~= "table" or type(level) ~= "number" then return end
    local me = ns.GetCharKey and ns.GetCharKey()
    for key, char in pairs(chars) do
        local h = key ~= me and type(char) == "table" and char.xpHistory
        local reached = type(h) == "table" and h.reached
        if type(reached) == "table" then
            local at, nextAt = reached[level], reached[level + 1]
            if type(at) == "number" and type(nextAt) == "number" and nextAt >= at then
                peerCount = peerCount + 1
                peerKey[peerCount], peerAt[peerCount], peerNext[peerCount] = key, at, nextAt
            end
        end
    end
end

local function LevelShare(r)
    return (r.max or 0) > 0 and (r.cur or 0) / r.max or 0
end

local function ClosestGap(r)
    local share, best = LevelShare(r), nil
    for i = 1, peerCount do
        local gap = M.PaceGap(r.played, share, peerAt[i], peerNext[i])
        if gap and (not best or abs(gap) < abs(best)) then best = gap end
    end
    return best
end

---------------------------------------------------------------------------------
-- The live card
---------------------------------------------------------------------------------

-- Reads no game API beyond the clock, no save unless the history moved, and
-- makes no table.
local function FillRecord(r)
    r.played = X.PlayedTotal()
    SyncHistory(r.level, tonumber(Get("xpTickerHistoryRows")) or 0)
    r.hist = hist
    r.pace = nil
    if Get("xpTickerShowPace") == true then
        if r.level ~= peersLevel then FillPeers(r.level) end
        r.pace = ClosestGap(r)
    end
end

local function Redraw()
    local r = liveRaw
    FillRecord(r)
    -- From the session: the kept record can be stale on a show, and a window
    -- must start at the show.
    r.trend = M.Trend(trendState, X.SessionGained(), X.SessionElapsed(), M.TREND_WINDOW)
    X.TickerView(r, Get, cardData)
    X.DrawCard(live, Get, cardData)
end

-- The hover service reads a hidden card's rect to reveal it, and the mover its
-- frame, so a hidden card takes its size after every apply. It sets no trend: a
-- window must start at a show.
local function DrawHidden()
    local r = liveRaw
    if not (r and live.dirty) or Plain(live:IsShown()) == true then return end
    FillRecord(r)
    r.trend = nil
    X.TickerView(r, Get, cardData)
    X.DrawCard(live, Get, cardData)
end

local function OnTick()
    local r = liveRaw
    if not (live and r) then return end
    r.levelTime, r.elapsed, r.gained = X.LevelTime(), X.SessionElapsed(), X.SessionGained()
    r.paused = X.SessionPaused()
    Redraw()
end

local function StopTimer()
    if timer then
        timer:Cancel()
        timer = nil
    end
end

-- Motion on and clicks off, so clicks pass through to the world. Applied on
-- every show and after every EnableMouse: the hover service enables the whole
-- mouse when it reveals a frame.
local function SetMouse(frame)
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
end

local function ButtonsShown(on)
    live.pauseBtn:SetShown(on)
    live.resetBtn:SetShown(on)
    live.topR:SetShown(not on)
end

local function ShowButtons() ButtonsShown(true) end

-- Moving from the card onto one of its buttons leaves the card but not its
-- bounds. A secret answer counts as not hovered.
local function HideButtons()
    if Plain(live:IsMouseOver()) ~= true then ButtonsShown(false) end
end

local function OnCardShow(self)
    SetMouse(self)
    -- A card shown after a hide reads the session as it is now.
    OnTick()
    if not timer and C_Timer and C_Timer.NewTicker then timer = C_Timer.NewTicker(1, OnTick) end
end

local function OnCardHide()
    StopTimer()
    ButtonsShown(false)
    -- A window with a hide in it was not measured: the trend starts over.
    trendState.at = nil
end

local function CloserFirst(a, b) return abs(a.gap) < abs(b.gap) end

-- A gap is the player's lead, so the fastest character has the lowest. A tie
-- reads ahead, so it sits above the player's own line.
local function FastestFirst(a, b)
    if a.gap ~= b.gap then return a.gap < b.gap end
    return b.own == true and a.own ~= true
end

-- Built on hover only: the closest characters, fastest on top, with the player's
-- own place among them.
local function ShowPaceTip(self)
    ShowButtons()
    local r = liveRaw
    if not (r and GameTooltip) then return end
    local share = LevelShare(r)
    local list = {}
    for i = 1, peerCount do
        local gap = M.PaceGap(r.played, share, peerAt[i], peerNext[i])
        if gap then list[#list + 1] = { key = peerKey[i], gap = gap } end
    end
    table.sort(list, CloserFirst)
    for i = #list, TIP_ROWS, -1 do list[i] = nil end
    local me = ns.GetCharKey and ns.GetCharKey()
    if me then list[#list + 1] = { key = me, gap = 0, own = true } end
    table.sort(list, FastestFirst)
    local chars = ns.db and ns.db.perChar
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for i = 1, #list do
        local entry = list[i]
        local char = type(chars) == "table" and chars[entry.key]
        local h = type(char) == "table" and char.xpHistory
        local class = type(h) == "table" and h.class
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        local name = tostring(entry.key):match("^[^-]+") or ""
        -- Each line reads from that character's view; the Pace row, the player's.
        GameTooltip:AddDoubleLine(name, entry.own and "you" or M.PaceText(-entry.gap),
            c and c.r or 1, c and c.g or 1, c and c.b or 1, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function HidePaceTip(self)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    HideButtons()
end

local function MakeLive()
    live = X.NewCard(UIParent)
    live.isLive = true
    live:Hide()
    live:SetFrameStrata("LOW")
    live:SetClampedToScreen(true)
    hooksecurefunc(live, "EnableMouse", SetMouse)
    SetMouse(live)
    live:SetScript("OnEnter", ShowButtons)
    live:SetScript("OnLeave", HideButtons)
    live:SetScript("OnShow", OnCardShow)
    live:SetScript("OnHide", OnCardHide)
    live.pauseBtn:SetScript("OnEnter", ShowButtons)
    live.pauseBtn:SetScript("OnLeave", HideButtons)
    live.pauseBtn:SetScript("OnClick", function()
        X.SessionPause(not X.SessionPaused())
        X.Apply()
    end)
    live.resetBtn:SetScript("OnEnter", ShowButtons)
    live.resetBtn:SetScript("OnLeave", HideButtons)
    live.resetBtn:SetScript("OnClick", function()
        X.ResetSession()
        X.Apply()
    end)
    SetMouse(live.paceHover)
    live.paceHover:SetScript("OnEnter", ShowPaceTip)
    live.paceHover:SetScript("OnLeave", HidePaceTip)
end

local function Wanted()
    if not X.XPEnabled() or Get("xpTickerEnabled") ~= true then return false end
    local t = X.ReadXP()
    if t.atMax or t.xpOff or (t.resting and Get("xpTickerHideResting") == true) then return false end
    return X.EvalVisibility(Get("xpTickerVisibility"))
end

local function WantsMouseover()
    return Wanted() == "mouseover"
end

local function PlaceCard()
    if not live then return end
    live.kuiPlaced = true
    X.PlaceFrame(live, UNLOCK_KEY, Get("xpTickerPos"), "LEFT", FIRST_X, FIRST_Y)
end

-- A drag lives only on the frame until Unlock Mode's save reads it back.
local function PlaceUnheld()
    if not (X.UnlockActive and live and live.kuiPlaced) then PlaceCard() end
end

-- With the card off or the XP bar off, no frame is created and none is drawn.
-- With both on the frame exists even while hidden: Unlock Mode moves it and the
-- hover service reads its rect.
function X.TickerVisibility()
    local v = Wanted()
    local on = X.XPEnabled() and Get("xpTickerEnabled") == true
    if not live then
        if not on then return end
        MakeLive()
    end
    local EUI = _G.EllesmereUI
    local canHover = EUI and EUI.RegisterMouseoverTarget and EUI.UnregisterMouseoverTarget
    if v == "mouseover" and canHover then
        if not live.mouseover then
            EUI.RegisterMouseoverTarget(live, WantsMouseover)
            live.mouseover = true
        end
    else
        if live.mouseover and canHover then EUI.UnregisterMouseoverTarget(live) end
        live.mouseover = false
        live:SetAlpha(1)
        live:SetShown(v and true or false)
    end
    PlaceUnheld()
    if on then DrawHidden() end
end

-- Runs on every apply. A pause ends by itself when its Start button can no
-- longer exist: here for the switch and Never, in the session for max level. The
-- XP bar going off keeps it, since the card returns with it.
function X.TickerApply()
    if live then live.dirty = true end
    if X.XPEnabled() and (Get("xpTickerEnabled") ~= true or Get("xpTickerVisibility") == "never") then
        X.SessionPause(false)
    end
end

function X.TickerRefresh(raw)
    liveRaw = raw
    if live and Plain(live:IsShown()) == true then Redraw() end
end

-- Ding keeps its color while its urgency holds, so a new accent forgets the kept
-- answer.
function X.TickerAccent()
    if not live then return end
    live.urgent = nil
    if liveRaw and Plain(live:IsShown()) == true then Redraw() end
end

function X.TickerStop()
    StopTimer()
    if not live then return end
    local EUI = _G.EllesmereUI
    if live.mouseover and EUI and EUI.UnregisterMouseoverTarget then EUI.UnregisterMouseoverTarget(live) end
    live.mouseover = false
    live:Hide()
end

-- What the party card stacks under: nil while the ticker is off.
function X.TickerFrame()
    if X.XPEnabled() and Get("xpTickerEnabled") == true then return live end
    return nil
end

-- The size follows the font size, so the mover has no resize controls.
function X.TickerElement(EUI)
    return EUI.MakeUnlockElement({
        key = UNLOCK_KEY, label = "KitnUI XP Ticker", group = "KitnUI", order = 5, noResize = true,
        isHidden = function() return not (X.XPEnabled() and Get("xpTickerEnabled") == true) end,
        -- Never creates: Unlock Mode asks whether or not the card is on.
        getFrame = function() return live end,
        getSize = function()
            local size = Get("xpTickerFontSize")
            return live and live.kuiW or M.TickerWidth(size), live and live.kuiH or M.RowHeight(size)
        end,
        savePos = function(_, point, relPoint, x, y)
            X.Set("xpTickerPos", { point = point, relPoint = relPoint, x = x, y = y })
            PlaceCard()
        end,
        -- A copy: Unlock Mode is free to keep or change what it is given.
        loadPos = function()
            local p = Get("xpTickerPos")
            if type(p) ~= "table" then return nil end
            return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
        end,
        -- Spec layouts read these instead of loadPos and savePos.
        loadRawPos = function() return M.RawSpot(Get("xpTickerPos")) end,
        saveRawPos = function(_, banked)
            X.Set("xpTickerPos", M.StoredSpot(banked))
            PlaceCard()
        end,
        clearPos = function() X.Set("xpTickerPos", nil) end,
        applyPos = PlaceUnheld,
    })
end
