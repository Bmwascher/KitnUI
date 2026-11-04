-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/PartyMarkers.lua                           ║
-- ║  Purpose: Party members' ticks and labels on the XP bar.     ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
local L = X.PartyLogic

local ceil, max = math.ceil, math.max

-- Above the fill and effects, below the art and the texts.
local HOST_LEVEL = 12
-- A label row's step and gap, as multiples of its size, as the around-texts'.
local ROW_SCALE, GAP_SCALE = 1.25, 0.2

-- Reused by every sync.
local look = {}

function X.PartyClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function NewMark(w)
    local tick = w.ptHost:CreateTexture(nil, "OVERLAY")
    tick:SetTexture(X.WHITE)
    tick:Hide()
    local label = w.ptHost:CreateFontString(nil, "OVERLAY")
    label:SetWordWrap(false)
    label:Hide()
    return { tick = tick, label = label }
end

local function SyncTick(w, mark, m, tickW, px)
    local x = L.MarkerX(m.pct, w.bw, tickW, px)
    if mark.x ~= x or mark.tickW ~= tickW or mark.tickH ~= w.bh then
        mark.x, mark.tickW, mark.tickH = x, tickW, w.bh
        mark.tick:SetSize(tickW, w.bh)
        mark.tick:ClearAllPoints()
        mark.tick:SetPoint("LEFT", w.ptHost, "LEFT", x, 0)
    end
    if mark.class ~= m.class then
        mark.class = m.class
        local r, g, b = X.PartyClassColor(m.class)
        mark.tick:SetVertexColor(r, g, b)
        mark.label:SetTextColor(r, g, b)
    end
    X.MaskEffect(w, mark.tick)
    if not mark.on then
        mark.on = true
        mark.tick:Show()
    end
end

-- Returns whether a label is drawn.
local function SyncLabel(mark, m)
    local label = mark.label
    local text = L.LabelText(m.name, m.level, look.style)
    if not text then
        if mark.text then
            mark.text = nil
            label:Hide()
        end
        return false
    end
    if mark.font ~= look.font or mark.size ~= look.size or mark.flags ~= look.flags then
        mark.font, mark.size, mark.flags = look.font, look.size, look.flags
        if not label:SetFont(look.font, look.size, look.flags) then label:SetFont(STANDARD_TEXT_FONT, look.size, look.flags) end
    end
    if mark.text ~= text then
        mark.text = text
        label:SetText(text)
        label:Show()
    end
    if mark.side ~= look.side or mark.labelX ~= look.ox or mark.labelY ~= look.y then
        mark.side, mark.labelX, mark.labelY = look.side, look.ox, look.y
        label:ClearAllPoints()
        if look.side == "below" then
            label:SetPoint("TOP", mark.tick, "BOTTOM", look.ox, look.y)
        else
            label:SetPoint("BOTTOM", mark.tick, "TOP", look.ox, look.y)
        end
    end
    return true
end

local function HideMark(mark)
    if mark.on then
        mark.on = false
        mark.tick:Hide()
    end
    if mark.text then
        mark.text = nil
        mark.label:Hide()
    end
end

-- list: { n, { name, class, level, pct }, ... }, or nil. Draws on the size of
-- the widget's last draw. A label's far edge counts in w.above or w.below, so
-- what floats above the bar and the preview's height both clear it.
function X.SyncMarkers(w, view, list)
    if not (w and w.bw and w.textAbove) then return end
    w.above, w.below = w.textAbove, w.textBelow
    local n = list and list.n or 0
    if n > 0 and not w.ptHost then
        w.ptHost = CreateFrame("Frame", nil, w.frame)
        w.ptHost:SetAllPoints(w.body)
        w.ptHost:SetFrameLevel(w.base + HOST_LEVEL)
        w.ptMarks = {}
    end
    if not w.ptHost then return end
    local size = tonumber(view("xpPartyLabelSize")) or 11
    local gap = ceil(size * GAP_SCALE)
    local below = view("xpPartyLabelSide") == "below"
    local oy = tonumber(view("xpPartyLabelOffY")) or 0
    look.style = view("xpPartyLabel")
    look.font, look.flags, look.size = X.FontPath(view("xpFont")), X.OutlineFlag(view("xpOutline")), size
    look.side, look.ox = below and "below" or "above", tonumber(view("xpPartyLabelOffX")) or 0
    -- A tick sits on the body while the around-texts are placed from the frame's
    -- edge, so the inset joins the room.
    local inset = w.insetY or 0
    look.y = below and (oy - (w.textBelow + gap + inset)) or (oy + w.textAbove + gap + inset)
    local px = X.Pixel()
    local tickW = L.MarkerWidth(tonumber(view("xpPartyMarkerWidth")) or 2, px)
    local labels = false
    for i = 1, n do
        local mark = w.ptMarks[i]
        if not mark then
            mark = NewMark(w)
            w.ptMarks[i] = mark
        end
        SyncTick(w, mark, list[i], tickW, px)
        if SyncLabel(mark, list[i]) then labels = true end
    end
    for i = n + 1, #w.ptMarks do HideMark(w.ptMarks[i]) end
    if labels then
        -- How far the label's edges reach past the body, on the side its offset
        -- put it, so what floats above the bar clears it wherever it sits.
        local rowH = ceil(size * ROW_SCALE)
        local top, bottom = look.y + rowH, -(look.y + w.bh)
        if below then top, bottom = look.y - w.bh, rowH - look.y end
        w.above, w.below = max(w.textAbove, top), max(w.textBelow, bottom)
    end
end
