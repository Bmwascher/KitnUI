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

local format, floor, ceil, abs, min, max = string.format, math.floor, math.ceil, math.abs, math.min, math.max

local UNLOCK_KEY = "KitnUI_XPTicker"
local ARROW = "Interface\\AddOns\\KitnUI_EUI\\Media\\XPBar\\arrow"
-- The current level, ten completed levels, the footer, its legend and Pace.
local MAX_ROWS = 14
-- The rows that can carry a gap bar: the current level and ten completed ones.
local BAR_ROWS = 11
-- Seconds to level below which Ding takes the accent color.
local DING_URGENT = 600
-- Lines in the Pace tooltip.
local TIP_ROWS = 8
-- Sizes, as multiples of the font size.
local TOP_SCALE, PAD_SCALE, ARROW_GAP, BUTTON_W = 1.35, 0.5, 0.3, 4
local LINE_SCALE, LINE_GAP = 0.25, 0.4
local CELL_SCALE, GAP_COL, COL_GAP, BAR_SCALE, GAP_FONT = 5, 4.2, 0.5, 0.5, 0.92
local DIV_ABOVE, DIV_BELOW, VALUE_GAP = 0.2, 0.25, 0.25
-- Pixels a tick reaches past its bar, above and below.
local TICK_OVER = 2
-- The current level's projected finish is drawn faint.
local PROJECTED_ALPHA = 0.45
-- Faster and up are teal, slower and down amber; labels and even gaps are dim.
local FAST_R, FAST_G, FAST_B = 0.3, 0.85, 0.75
local SLOW_R, SLOW_G, SLOW_B = 1, 0.71, 0.33
local DIM = 0.66
local BACKGROUNDS = { card = { 0.05, 0.05, 0.05, 0.85 }, soft = { 0, 0, 0, 0.35 } }
X.CARD_BACKGROUNDS = BACKGROUNDS
-- The Card backdrop over a white sky: the worst case accent text must read on.
local CARD_BACK = BACKGROUNDS.card[1] * BACKGROUNDS.card[4] + (1 - BACKGROUNDS.card[4])
-- Marks a gap measured against the source the footer does not name.
local STAR = "|cffa8a8a8*|r"
local PCT, PCT_STAR = "%d%%", "%d%%" .. STAR
-- Where a card sits until it is moved, clear of the bars' default spots.
local FIRST_X, FIRST_Y = 40, 120

local live, timer, liveRaw
local cardData, trendState = {}, {}
local hist = {
    n = 0, levels = {}, texts = {}, secs = {}, acct = {}, ref = {}, src = {}, share = {}, gap = {}, star = {},
    gapText = {},
}
local histGen, histLevel, histRows, histBars, histCur
-- Other characters' times, one list per row and the current level's last, and
-- the sort space: kept between rebuilds.
local buckets, bucketN, scratch = {}, {}, {}
-- Other characters with a played time at both ends of this level, in parallel
-- arrays: filled once per level, read on every tick.
local peerKey, peerAt, peerNext = {}, {}, {}
local peerCount, peersLevel = 0, nil

---------------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------------

local function SetRow(out, n, kind, key, left, right, extra, extraKey, share, cls)
    out.kind[n], out.keys[n], out.left[n], out.right[n] = kind, key, left, right
    out.extra[n], out.extraKey[n], out.share[n], out.cls[n] = extra, extraKey, share, cls
end

local function GapClass(share)
    if type(share) ~= "number" then return nil end
    if share == 0 then return "even" end
    return share < 0 and "fast" or "slow"
end

-- Builds the card's texts from a raw record, the live one or the preview's.
-- r: level, cur, max, quest, rested, levelTime, elapsed, gained, paused, trend,
-- played, pace, hist. Each row has a kind, a setting key, three texts, the key
-- its extra text leads to, a bar share and a text color.
function X.TickerView(r, view, out)
    out.left, out.right, out.extra, out.keys = out.left or {}, out.right or {}, out.extra or {}, out.keys or {}
    out.extraKey, out.kind, out.share, out.cls = out.extraKey or {}, out.kind or {}, out.share or {}, out.cls or {}
    local perHour, eta = M.Rate(r.gained, r.elapsed, (r.max or 0) - (r.cur or 0))
    local due = type(eta) == "number" and eta > 0
    out.rate = perHour and M.RateText(perHour) or "no XP yet"
    out.rateDim = not perHour
    out.arrow = (perHour and not r.paused) and r.trend or nil
    out.ding = r.paused and "Paused" or ("Ding " .. M.TimeText(eta))
    out.urgent = not r.paused and due and eta < DING_URGENT
    out.dingTone = out.urgent and "urgent" or ((r.paused or not due) and "dim" or nil)
    out.pauseText = r.paused and "Start" or "Pause"
    out.line = view("xpTickerShowLine") == true
    out.xpEnd, out.questEnd, out.restedEnd = M.Stack(r.cur, r.max, r.quest, r.rested, view("xpShowQuest") == true)
    local grid = view("xpTickerGapBars") == true
    out.grid = grid
    local h = r.hist
    local n = 0
    if view("xpTickerShowCurrent") == true then
        n = n + 1
        local pct = (r.max or 0) > 0 and floor((r.cur or 0) * 100 / r.max) or 0
        local label = format("Level %d", r.level or 0)
        if grid then
            local share
            if h and due and not r.paused and type(r.levelTime) == "number" then
                share = M.SplitGap(r.levelTime + eta, h.curRef)
            end
            SetRow(out, n, "current", "tkCurrent", label, M.ClockText(r.levelTime),
                format(h and h.curStar and PCT_STAR or PCT, pct), "tkCurrent", share, nil)
        else
            SetRow(out, n, "current", "tkCurrent", label, format("%s  %d%%", M.ClockText(r.levelTime), pct))
        end
    end
    if h then
        for i = 1, min(h.n, tonumber(view("xpTickerHistoryRows")) or 0) do
            n = n + 1
            local label = format("Level %d", h.levels[i])
            if grid then
                SetRow(out, n, "history", "tkHistory", label, h.texts[i], h.gapText[i], "tkGapBars", h.share[i],
                    GapClass(h.share[i]))
            else
                SetRow(out, n, "history", "tkHistory", label, h.texts[i])
            end
        end
    end
    out.levelRows = n
    local played = view("xpTickerShowPlayed") == true
    local foot = grid and h and h.footText or nil
    if played or foot then
        n = n + 1
        SetRow(out, n, "footer", played and "tkPlayed" or "tkGapBars", played and "Played" or "",
            played and M.TimeText(r.played) or "", foot, foot and "tkGapBars" or nil)
    end
    local legend = grid and h and h.legendText or nil
    if legend then
        n = n + 1
        SetRow(out, n, "legend", "tkGapBars", "", "", legend, "tkGapBars")
    end
    if view("xpTickerShowPace") == true and type(r.pace) == "number" then
        n = n + 1
        SetRow(out, n, "pace", "tkPace", "Pace", M.PaceText(r.pace), nil, nil, nil, r.pace >= 0 and "fast" or "slow")
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

local function NewTexture(card, sub)
    local t = card:CreateTexture(nil, "ARTWORK", nil, sub)
    t:Hide()
    return t
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
    card.left, card.right, card.extra = {}, {}, {}
    for i = 1, MAX_ROWS do
        card.left[i], card.right[i], card.extra[i] = NewText(card), NewText(card), NewText(card)
        card.left[i]:Hide()
        card.right[i]:Hide()
        card.extra[i]:Hide()
    end
    card.tick, card.bar, card.barEdge = {}, {}, {}
    for i = 1, BAR_ROWS do
        card.barEdge[i], card.bar[i], card.tick[i] = NewTexture(card, 1), NewTexture(card, 2), NewTexture(card, 3)
    end
    card.lineEdge, card.lineTrack = NewTexture(card, 0), NewTexture(card, 1)
    card.lineRest, card.lineQuest, card.lineFill = NewTexture(card, 2), NewTexture(card, 2), NewTexture(card, 2)
    card.divider = NewTexture(card, 1)
    card.pauseBtn, card.resetBtn = NewButton(card), NewButton(card)
    card.paceHover = CreateFrame("Frame", nil, card)
    card.paceHover:Hide()
    card.dirty = true
    return card
end

local SetFont = X.SetFont

local function Num(v)
    return tonumber(v) or 1
end

-- Only when a setting changed: every size is a multiple of the font size. The
-- rows are placed by the draw, which knows which of them show.
local function StyleCard(card, view)
    card.dirty = false
    local size = tonumber(view("xpTickerFontSize")) or 12
    local topSize = ceil(size * TOP_SCALE)
    local font, flags = X.FontPath(view("xpTickerFont")), X.OutlineFlag(view("xpTickerOutline"))
    local pad, rowH, topH = ceil(size * PAD_SCALE), M.RowHeight(size), M.RowHeight(topSize)
    local px = X.Pixel and X.Pixel() or 1
    card.pad, card.rowH, card.topH, card.kuiW, card.px = pad, rowH, topH, M.TickerWidth(size), px
    card.font, card.flags, card.size, card.gapSize = font, flags, size, floor(size * GAP_FONT + 0.5)
    card.innerW = card.kuiW - 2 * pad
    card.lineH, card.lineGap = max(2, floor(size * LINE_SCALE + 0.5)), ceil(size * LINE_GAP)
    card.cellW, card.gapW, card.colGap = ceil(size * CELL_SCALE), ceil(size * GAP_COL), ceil(size * COL_GAP)
    card.barH = max(2, floor(size * BAR_SCALE + 0.5))
    card.divAbove, card.divBelow, card.valueGap = ceil(size * DIV_ABOVE), ceil(size * DIV_BELOW), ceil(size * VALUE_GAP)
    card:SetWidth(card.kuiW)
    SetFont(card.top, font, topSize, flags)
    SetFont(card.topR, font, topSize, flags)
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
        SetFont(card.left[i], font, size, flags)
        SetFont(card.right[i], font, size, flags)
        SetFont(card.extra[i], font, size, flags)
        card.left[i].kuiR, card.right[i].kuiR, card.extra[i].kuiR = nil, nil, nil
    end
    local ar, ag, ab
    if X.AccentColor then ar, ag, ab = X.AccentColor() end
    if not (ar and ag and ab) then ar, ag, ab = 1, 1, 1 end
    local tr, tg, tb = M.AccentText(ar, ag, ab, CARD_BACK)
    card.tintR, card.tintG, card.tintB = tr or 1, tg or 1, tb or 1
    local track = card.lineTrack
    track:ClearAllPoints()
    track:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -(pad + topH))
    track:SetSize(card.innerW, card.lineH)
    track:SetColorTexture(1, 1, 1, 0.12)
    card.lineEdge:ClearAllPoints()
    card.lineEdge:SetPoint("TOPLEFT", track, "TOPLEFT", -px, px)
    card.lineEdge:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", px, -px)
    card.lineEdge:SetColorTexture(0, 0, 0, 1)
    card.lineFill:SetColorTexture(ar, ag, ab, 1)
    card.lineQuest:SetColorTexture(Num(view("xpQuestR")), Num(view("xpQuestG")), Num(view("xpQuestB")), Num(view("xpQuestA")))
    card.lineRest:SetColorTexture(Num(view("xpRestedR")), Num(view("xpRestedG")), Num(view("xpRestedB")), Num(view("xpRestedA")))
    for i = 1, BAR_ROWS do
        local edge, bar = card.barEdge[i], card.bar[i]
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -px, px)
        edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", px, -px)
        edge:SetColorTexture(0, 0, 0, 0.6)
        card.tick[i]:SetColorTexture(1, 1, 1, 0.5)
    end
    card.divider:SetColorTexture(1, 1, 1, 0.14)
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
    card.layN, card.dingTone, card.rateDim = nil, nil, nil
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
        card.arrow:SetVertexColor(FAST_R, FAST_G, FAST_B, 1)
    elseif dir == "down" then
        card.arrow:SetTexCoord(0, 1, 1, 0)
        card.arrow:SetVertexColor(SLOW_R, SLOW_G, SLOW_B, 1)
    end
    card.arrow:SetShown(dir ~= nil)
end

local function Tint(fs, r, g, b)
    if fs.kuiR ~= r or fs.kuiG ~= g or fs.kuiB ~= b then
        fs.kuiR, fs.kuiG, fs.kuiB = r, g, b
        fs:SetTextColor(r, g, b, 1)
    end
end

local function TintClass(fs, cls)
    if cls == "fast" then
        Tint(fs, FAST_R, FAST_G, FAST_B)
    elseif cls == "slow" then
        Tint(fs, SLOW_R, SLOW_G, SLOW_B)
    elseif cls == "even" then
        Tint(fs, DIM, DIM, DIM)
    else
        Tint(fs, 1, 1, 1)
    end
end

-- One piece of the XP line, from and to in percent of the track.
local function SyncSegment(card, tex, from, to)
    local x = floor(from * card.innerW / 100 + 0.5)
    local w = floor(to * card.innerW / 100 + 0.5) - x
    if tex.kuiX == x and tex.kuiW == w then return end
    tex.kuiX, tex.kuiW = x, w
    if w < 1 then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", card.lineTrack, "TOPLEFT", x, 0)
    tex:SetSize(w, card.lineH)
    tex:Show()
end

-- One row's tick and bar: neither without a reference, the tick alone when even
-- or under a pixel, else a bar left of the tick for faster, right for slower.
local function SyncBar(card, i, share, alpha)
    local bar = card.bar[i]
    local w, side = -1, nil
    if type(share) == "number" then
        w = floor(abs(share) * card.cellW / 2 + 0.5)
        side = share < 0 and "fast" or "slow"
    end
    if bar.kuiPlaced and bar.kuiW == w and bar.kuiSide == side and bar.kuiAlpha == alpha then return end
    bar.kuiPlaced, bar.kuiW, bar.kuiSide, bar.kuiAlpha = true, w, side, alpha
    local edge = card.barEdge[i]
    card.tick[i]:SetShown(w >= 0)
    if w < 1 then
        bar:Hide()
        edge:Hide()
        return
    end
    bar:ClearAllPoints()
    if side == "fast" then
        bar:SetPoint("TOPRIGHT", card, "TOPLEFT", card.cx, bar.kuiTop)
        bar:SetColorTexture(FAST_R, FAST_G, FAST_B, alpha)
    else
        bar:SetPoint("TOPLEFT", card, "TOPLEFT", card.cx, bar.kuiTop)
        bar:SetColorTexture(SLOW_R, SLOW_G, SLOW_B, alpha)
    end
    bar:SetSize(w, card.barH)
    edge:SetAlpha(alpha)
    bar:Show()
    edge:Show()
end

-- Places every row, the ticks, the divider and the line for this set of rows,
-- and sizes the card. Runs only when the set changes.
local function LayoutRows(card, data)
    local pad, rowH, px = card.pad, card.rowH, card.px
    local n, levels = data.n, data.levelRows
    local top = pad + card.topH + (data.line and (card.lineH + card.lineGap) or 0)
    local split = levels > 0 and n > levels
    local below = top + levels * rowH + (split and (card.divAbove + px + card.divBelow) or 0)
    local clockX = -(pad + card.gapW + card.colGap + card.cellW + card.colGap)
    card.cx = card.kuiW - pad - card.gapW - card.colGap - card.cellW / 2
    for i = 1, MAX_ROWS do
        local on = i <= n
        local left, right, extra = card.left[i], card.right[i], card.extra[i]
        left:SetShown(on)
        right:SetShown(on)
        extra:SetShown(on)
        if on then
            local kind = data.kind[i]
            local level = kind == "current" or kind == "history"
            local y = level and (top + (i - 1) * rowH) or (below + (i - levels - 1) * rowH)
            left:ClearAllPoints()
            left:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -y)
            right:ClearAllPoints()
            if kind == "footer" then
                right:SetPoint("TOPLEFT", left, "TOPRIGHT", card.valueGap, 0)
            elseif level and data.grid then
                right:SetPoint("TOPRIGHT", card, "TOPRIGHT", clockX, -y)
            else
                right:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, -y)
            end
            extra:ClearAllPoints()
            extra:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, -y)
            SetFont(extra, card.font, kind == "history" and card.gapSize or card.size, card.flags)
            if i <= BAR_ROWS then
                local bar, tick = card.bar[i], card.tick[i]
                bar.kuiTop = -(y + (rowH - card.barH) / 2)
                tick:ClearAllPoints()
                tick:SetPoint("TOP", card, "TOPLEFT", card.cx, bar.kuiTop + TICK_OVER)
                tick:SetSize(px, card.barH + 2 * TICK_OVER)
            end
        end
        if i <= BAR_ROWS then card.bar[i].kuiPlaced = nil end
    end
    card.divider:ClearAllPoints()
    if split then
        card.divider:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -(top + levels * rowH + card.divAbove))
        card.divider:SetSize(card.innerW, px)
    end
    card.divider:SetShown(split)
    card.lineTrack:SetShown(data.line)
    card.lineEdge:SetShown(data.line)
    if not data.line then
        card.lineFill:Hide()
        card.lineQuest:Hide()
        card.lineRest:Hide()
    end
    card.lineFill.kuiX, card.lineQuest.kuiX, card.lineRest.kuiX = nil, nil, nil
    card.kuiH = below + (n - levels) * rowH + pad
    card:SetHeight(card.kuiH)
end

function X.DrawCard(card, view, data)
    if card.dirty then StyleCard(card, view) end
    SetKept(card.top, data.rate)
    SetKept(card.topR, data.ding)
    SetKept(card.pauseBtn.text, data.pauseText)
    SyncArrow(card, data.arrow)
    if card.rateDim ~= data.rateDim then
        card.rateDim = data.rateDim
        local c = data.rateDim and DIM or 1
        card.top:SetTextColor(c, c, c, 1)
    end
    local tone = data.dingTone or "plain"
    if card.dingTone ~= tone then
        card.dingTone = tone
        if tone == "urgent" then
            card.topR:SetTextColor(card.tintR, card.tintG, card.tintB, 1)
        elseif tone == "dim" then
            card.topR:SetTextColor(DIM, DIM, DIM, 1)
        else
            card.topR:SetTextColor(1, 1, 1, 1)
        end
    end
    local footer = data.n > data.levelRows and data.kind[data.levelRows + 1] == "footer"
    if card.layN ~= data.n or card.layLevels ~= data.levelRows or card.layLine ~= data.line
        or card.layGrid ~= data.grid or card.layFooter ~= footer then
        card.layN, card.layLevels, card.layLine, card.layGrid, card.layFooter = data.n, data.levelRows, data.line, data.grid, footer
        LayoutRows(card, data)
    end
    for i = 1, data.n do
        local kind, left, right, extra = data.kind[i], card.left[i], card.right[i], card.extra[i]
        SetKept(left, data.left[i])
        SetKept(right, data.right[i])
        SetKept(extra, data.extra[i] or "")
        if kind == "current" then
            Tint(left, card.tintR, card.tintG, card.tintB)
            Tint(right, 1, 1, 1)
            Tint(extra, 1, 1, 1)
        elseif kind == "history" then
            Tint(left, DIM, DIM, DIM)
            Tint(right, 1, 1, 1)
            TintClass(extra, data.cls[i])
        elseif kind == "pace" then
            Tint(left, DIM, DIM, DIM)
            TintClass(right, data.cls[i])
        else
            Tint(left, DIM, DIM, DIM)
            Tint(right, 1, 1, 1)
            Tint(extra, DIM, DIM, DIM)
        end
    end
    for i = 1, BAR_ROWS do
        local kind = i <= data.n and data.kind[i] or nil
        local level = data.grid and (kind == "current" or kind == "history")
        SyncBar(card, i, level and data.share[i] or nil, kind == "current" and PROJECTED_ALPHA or 1)
    end
    if data.line then
        local xpEnd, questEnd, restedEnd = data.xpEnd or 0, data.questEnd or 0, data.restedEnd or 0
        SyncSegment(card, card.lineFill, 0, xpEnd)
        SyncSegment(card, card.lineQuest, xpEnd, questEnd)
        SyncSegment(card, card.lineRest, questEnd, restedEnd)
    end
    -- Pace is the last row while it shows.
    local paceRow = data.kind[data.n] == "pace" and data.n or nil
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

-- The gaps, stars, footer and legend of a card's finished levels, made once per
-- history change. current: the card shows its current level. The live card and
-- the preview share it.
function X.SummarizeHistory(h, current)
    M.SplitSummary(h, scratch, current)
    for i = 1, h.n do
        local text = M.GapText(h.share[i], h.gap[i])
        h.gapText[i] = (text and h.star[i]) and (text .. STAR) or text
    end
    local clock = h.median and M.ClockText(h.median)
    if h.main == "account" then
        h.footText = "vs account"
    elseif h.main == "median" then
        h.footText = "median " .. clock
    else
        h.footText = nil
    end
    if not h.mixed then
        h.legendText = nil
    elseif h.main == "account" then
        h.legendText = "* recent median " .. clock
    else
        h.legendText = "* account"
    end
end

-- Every other character's time for each level on the card, in one walk of the
-- saves. The player's own entry is skipped, so without a character key nothing
-- is taken.
local function FillAccount(level, n)
    for i = 1, n + 1 do bucketN[i] = 0 end
    local chars = ns.db and ns.db.perChar
    local me = ns.GetCharKey and ns.GetCharKey()
    if type(chars) == "table" and me then
        for key, char in pairs(chars) do
            local h = key ~= me and type(char) == "table" and char.xpHistory
            local splits = type(h) == "table" and h.splits
            if type(splits) == "table" then
                for i = 1, n + 1 do
                    local secs = splits[i <= n and hist.levels[i] or level]
                    if type(secs) == "number" and secs >= 0 then
                        local list = buckets[i]
                        if not list then
                            list = {}
                            buckets[i] = list
                        end
                        local count = bucketN[i] + 1
                        bucketN[i], list[count] = count, secs
                    end
                end
            end
        end
    end
    for i = 1, n + 1 do
        local med = buckets[i] and M.Median(buckets[i], bucketN[i], scratch) or nil
        if med and med <= 0 then med = nil end
        if i <= n then hist.acct[i] = med else hist.curAcct = med end
    end
end

-- Showing or hiding the current level changes only the summary, so it walks
-- no save.
local function SyncHistory(level, rows, bars, current)
    local gen = X.HistoryGen()
    local same = gen == histGen and level == histLevel and rows == histRows and bars == histBars
    if same and current == histCur then return end
    histCur = current
    if not same then
        histGen, histLevel, histRows, histBars = gen, level, rows, bars
        local h = X.History(false)
        local splits = h and h.splits
        local n = 0
        if type(splits) == "table" and type(level) == "number" then
            for lv = level - 1, 1, -1 do
                if n >= rows then break end
                local secs = splits[lv]
                if type(secs) == "number" then
                    n = n + 1
                    hist.levels[n], hist.texts[n], hist.secs[n] = lv, M.ClockText(secs), secs
                end
            end
        end
        hist.n = n
        if bars then
            if type(level) == "number" then
                FillAccount(level, n)
            else
                hist.curAcct = nil
            end
        end
    end
    if bars then X.SummarizeHistory(hist, current) end
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

-- Reads no game API beyond the clock and no save unless the history moved.
-- Past the first account walk it makes no table.
local function FillRecord(r)
    r.played = X.PlayedTotal()
    SyncHistory(r.level, tonumber(Get("xpTickerHistoryRows")) or 0, Get("xpTickerGapBars") == true,
        Get("xpTickerShowCurrent") == true)
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

-- The tint, the urgent Ding and the line's fill come from the accent, so a new
-- one restyles the card.
function X.TickerAccent()
    if not live then return end
    live.dirty = true
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
