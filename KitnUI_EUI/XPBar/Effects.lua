-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Effects.lua                                ║
-- ║  Purpose: The bars' effects: native animations on a bar      ║
-- ║           widget, made on first use. Shared by the live bars ║
-- ║           and the preview.                                   ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
local M = X.Math

local Plain = ns.EUIPlain

-- Whether a moving effect keeps its motion under the Blizzard frame style's
-- mask. False makes those effects alpha-only, with no other change.
X.FX_MASKED_MOTION = true

local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0.25
local GLOW_FADE = "Interface\\AddOns\\KitnUI_EUI\\Media\\XPBar\\glowfade"
local GLOW_CORNER = "Interface\\AddOns\\KitnUI_EUI\\Media\\XPBar\\glowcorner"
local SURGE_RIBBON, SURGE_PIP = "ui-castingbar-full-glow-standard", "ui-castingbar-pip"
local SURGE_GLOW, SURGE_FLARE = "cast_standard_pipglow", "cast-empowered-pipflare"

-- Sizes, as multiples of the bar's height or the text's size.
local SPAN_MIN, SPARK_W, TRAIL_W, SURGE_PART, BAND_W = 0.25, 0.6, 4, 1.5, 3
local AMOUNT_RISE, AMOUNT_MARGIN, AMOUNT_GAP = 1.5, 2, 0.2

-- Timings, in seconds.
local PULSE_ALPHA, PULSE_TIME = 0.9, 0.8
local WAVE_TIME, WAVE_IN, WAVE_OUT = 0.45, 0.12, 0.2
local SURGE_TIME, SURGE_IN, SURGE_OUT, SURGE_SCALE = 0.3, 0.08, 0.15, 0.1
local FLASH_ALPHA, FLASH_IN, FLASH_OUT, FLASH_SCALE = 0.75, 0.15, 0.7, 0.01
local SWEEP_TIME = 0.4
-- The band's and the glow's four alpha steps: from, to, length, start.
local SWEEP_STEPS = {
    { 0, 1, 0.15, 0 }, { 1, 0.6, 0.25, 0.15 }, { 0.6, 0.9, 0.25, 0.4 }, { 0.9, 0, 0.5, 0.65 },
}
local AMOUNT_HOLD, AMOUNT_FADE = 0.5, 0.75
local READY_FROM, READY_TO, READY_TIME = 0.1, 0.5, 0.9

---------------------------------------------------------------------------------
-- Regions and groups
---------------------------------------------------------------------------------

-- A clipped frame on the body, so an effect stays inside the bar on every
-- style. It is not a child of the body, whose alpha is 0 while gaps are cut.
local function Host(w)
    if w.fxClip then return end
    w.fxClip = CreateFrame("Frame", nil, w.frame)
    w.fxClip:SetAllPoints(w.body)
    w.fxClip:SetFrameLevel(w.base + 11)
    w.fxClip:SetClipsChildren(true)
    w.fx = CreateFrame("Frame", nil, w.fxClip)
    w.fx:SetAllPoints(w.fxClip)
    w.fx:SetFrameLevel(w.base + 11)
    w.fxRegions, w.fxSets = {}, {}
end

local function Glow(w)
    if w.fxGlow then return end
    w.fxGlow = CreateFrame("Frame", nil, w.frame)
    w.fxGlow:SetAllPoints(w.frame)
    w.fxGlow:SetFrameLevel(w.base + 11)
end

local function ShowRegions(set)
    for i = 1, #set.regions do set.regions[i]:Show() end
end

local function HideRegions(set)
    for i = 1, #set.regions do set.regions[i]:Hide() end
end

local function StopSet(set)
    set.group:Stop()
    HideRegions(set)
end

-- Plays the gains that merged, or merges them again while something still blocks.
-- A fill that fell while turn-ins waited crossed a level, so only that fill is left.
local function PlayPending(w)
    local from = w.fxPendFrom
    if from == nil then return end
    local to, amount, quest, fillAt = w.fxPendTo, w.fxPendAmount, w.fxPendQuest, w.fxPendFill
    w.fxPendFrom, w.fxPendTo, w.fxPendAmount, w.fxPendQuest, w.fxPendFill = nil, nil, nil, nil, nil
    local fill = tonumber(w.fxData.fill)
    if fill and fillAt and fill < fillAt then from, to = 0, fill end
    X.PlayGainEffect(w, w.fxView, w.fxData, from, to, amount, quest)
end

local function Finished(w, set)
    HideRegions(set)
    if set == w.fxQuest then w.fxQuest = nil else w.fxBusy = nil end
    PlayPending(w)
end

local function NewSet(w, name)
    Host(w)
    local set = { group = w.fx:CreateAnimationGroup(), regions = {} }
    set.group:SetScript("OnFinished", function() Finished(w, set) end)
    w.fxSets[name] = set
    return set
end

local function InBar(w, set)
    local t = w.fx:CreateTexture(nil, "ARTWORK")
    t:SetTexture(X.WHITE)
    t:SetBlendMode("ADD")
    t:Hide()
    w.fxRegions[#w.fxRegions + 1] = t
    set.regions[#set.regions + 1] = t
    X.MaskEffect(w, t)
    return t
end

local function Step(group, target, from, to, duration, delay, order)
    local a = group:CreateAnimation("Alpha")
    a:SetTarget(target)
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(duration)
    if delay then a:SetStartDelay(delay) end
    if order then a:SetOrder(order) end
end

local function Move(group, target, duration)
    local a = group:CreateAnimation("Translation")
    a:SetTarget(target)
    a:SetDuration(duration)
    return a
end

local function Span(w, t, left, width)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", w.fx, "TOPLEFT", left, 0)
    t:SetPoint("BOTTOMLEFT", w.fx, "BOTTOMLEFT", left, 0)
    t:SetWidth(width)
end

local function Moves(w)
    return X.FX_MASKED_MOTION or not w.masksOn
end

---------------------------------------------------------------------------------
-- Gain effects
---------------------------------------------------------------------------------

local function PlayPulse(w, r, g, b, fromPct, toPct)
    local set = w.fxSets and w.fxSets.pulse
    if not set then
        set = NewSet(w, "pulse")
        set.tex = InBar(w, set)
        Step(set.group, set.tex, PULSE_ALPHA, 0, PULSE_TIME)
    end
    Span(w, set.tex, M.EffectSpan(fromPct, toPct, w.bw, w.bh * SPAN_MIN))
    set.tex:SetVertexColor(r, g, b, 1)
    return set
end

-- A part of Energy Wave's streak: the drawn fade's stretch from alpha a1 to a2,
-- left to right. Along the fade's depth, the texture coordinate is its alpha.
local function WavePart(w, set, a1, a2)
    local t = InBar(w, set)
    t:SetTexture(GLOW_FADE)
    t:SetTexCoord(0, a1, 1, a1, 0, a2, 1, a2)
    return t
end

local function PlayWave(w, r, g, b, fromPct, toPct)
    local set = w.fxSets and w.fxSets.wave
    if not set then
        set = NewSet(w, "wave")
        set.spark, set.trail, set.light = WavePart(w, set, 0.5, 1), WavePart(w, set, 0, 0.5), InBar(w, set)
        set.moveSpark, set.moveTrail = Move(set.group, set.spark, WAVE_TIME), Move(set.group, set.trail, WAVE_TIME)
        for i = 1, #set.regions do
            Step(set.group, set.regions[i], 0, 1, WAVE_IN)
            Step(set.group, set.regions[i], 1, 0, WAVE_OUT, WAVE_TIME - WAVE_OUT)
        end
    end
    local left, width = M.EffectSpan(fromPct, toPct, w.bw, w.bh * SPAN_MIN)
    local toX, moves = left + width, Moves(w)
    local startX = moves and 0 or toX
    local sparkW, trailW = w.bh * SPARK_W, w.bh * TRAIL_W
    Span(w, set.spark, startX - sparkW, sparkW)
    Span(w, set.trail, startX - sparkW - trailW, trailW)
    Span(w, set.light, left, width)
    set.spark:SetVertexColor(r, g, b, 1)
    set.trail:SetVertexColor(r, g, b, 1)
    set.light:SetVertexColor(r, g, b, 0.5)
    local offset = moves and toX or 0
    set.moveSpark:SetOffset(offset, 0)
    set.moveTrail:SetOffset(offset, 0)
    return set
end

local function SurgePart(w, set, atlas)
    local t = InBar(w, set)
    t:SetAtlas(atlas)
    t:SetDesaturated(true)
    return t
end

local function PlaySurge(w, r, g, b, fromPct, toPct)
    local set = w.fxSets and w.fxSets.surge
    if not set then
        set = NewSet(w, "surge")
        set.ribbon = SurgePart(w, set, SURGE_RIBBON)
        set.parts = { SurgePart(w, set, SURGE_PIP), SurgePart(w, set, SURGE_GLOW), SurgePart(w, set, SURGE_FLARE) }
        set.moves = {}
        for i = 1, #set.parts do set.moves[i] = Move(set.group, set.parts[i], SURGE_TIME) end
        set.scale = set.group:CreateAnimation("Scale")
        set.scale:SetTarget(set.ribbon)
        set.scale:SetOrigin("LEFT", 0, 0)
        set.scale:SetDuration(SURGE_TIME)
        for i = 1, #set.regions do
            Step(set.group, set.regions[i], 0, 1, SURGE_IN)
            Step(set.group, set.regions[i], 1, 0, SURGE_OUT, SURGE_TIME - SURGE_OUT)
        end
    end
    local left, width = M.EffectSpan(fromPct, toPct, w.bw, w.bh * SPAN_MIN)
    local moves = Moves(w)
    local partW = w.bh * SURGE_PART
    local startX = (moves and left or left + width) - partW / 2
    Span(w, set.ribbon, left, width)
    set.ribbon:SetVertexColor(r, g, b, 1)
    for i = 1, #set.parts do
        Span(w, set.parts[i], startX, partW)
        set.parts[i]:SetVertexColor(r, g, b, 1)
        set.moves[i]:SetOffset(moves and width or 0, 0)
    end
    set.scale:SetScaleFrom(moves and SURGE_SCALE or 1, 1)
    set.scale:SetScaleTo(1, 1)
    return set
end

local GAIN_PLAYS = { pulse = PlayPulse, wave = PlayWave, surge = PlaySurge }

---------------------------------------------------------------------------------
-- Level-up and rank-up effects
---------------------------------------------------------------------------------

local function PlayFlash(w)
    local set = w.fxSets and w.fxSets.flash
    if not set then
        set = NewSet(w, "flash")
        set.tex = InBar(w, set)
        set.tex:SetAllPoints(w.fx)
        set.tex:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)
        Step(set.group, set.tex, 0, FLASH_ALPHA, FLASH_IN, nil, 1)
        Step(set.group, set.tex, FLASH_ALPHA, 0, FLASH_OUT, nil, 2)
        set.scale = set.group:CreateAnimation("Scale")
        set.scale:SetTarget(set.tex)
        set.scale:SetOrigin("RIGHT", 0, 0)
        set.scale:SetDuration(FLASH_OUT)
        set.scale:SetOrder(2)
    end
    set.scale:SetScaleFrom(1, 1)
    set.scale:SetScaleTo(Moves(w) and FLASH_SCALE or 1, 1)
    return set
end

-- A piece of the Sweep's glow, outside the frame. The texture coordinates (...)
-- turn its opaque edge or corner to the frame.
local function GlowPiece(w, set, file, ...)
    local t = w.fxGlow:CreateTexture(nil, "ARTWORK")
    t:SetTexture(file)
    t:SetTexCoord(...)
    t:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)
    t:SetBlendMode("ADD")
    t:Hide()
    set.regions[#set.regions + 1] = t
    return t
end

-- A strip along one frame edge. The fade is drawn, because SetGradient painted
-- these strips plain white.
local function GlowStrip(w, set, p1, rel1, p2, rel2, ...)
    local t = GlowPiece(w, set, GLOW_FADE, ...)
    t:SetPoint(p1, w.frame, rel1)
    t:SetPoint(p2, w.frame, rel2)
    return t
end

-- The square beyond one frame corner. Its fade is round, and equals each strip's
-- along the edge they share.
local function GlowCorner(w, set, point, rel, ...)
    local t = GlowPiece(w, set, GLOW_CORNER, ...)
    t:SetPoint(point, w.frame, rel)
    return t
end

local function PlaySweep(w, view, p)
    local set = w.fxSets and w.fxSets.sweep
    if not set then
        set = NewSet(w, "sweep")
        Glow(w)
        set.band = InBar(w, set)
        set.band:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)
        set.move = Move(set.group, set.band, SWEEP_TIME)
        set.top = GlowStrip(w, set, "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", 0, 1, 0, 1)
        set.bottom = GlowStrip(w, set, "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", 0, 1, 1, 0)
        set.leftSide = GlowStrip(w, set, "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", 0, 0, 1, 0, 0, 1, 1, 1)
        set.rightSide = GlowStrip(w, set, "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1, 1, 1, 0, 0, 1, 0)
        set.corners = {
            GlowCorner(w, set, "BOTTOMRIGHT", "TOPLEFT", 1, 0, 0, 1),
            GlowCorner(w, set, "BOTTOMLEFT", "TOPRIGHT", 0, 1, 0, 1),
            GlowCorner(w, set, "TOPRIGHT", "BOTTOMLEFT", 1, 0, 1, 0),
            GlowCorner(w, set, "TOPLEFT", "BOTTOMRIGHT", 0, 1, 1, 0),
        }
        for i = 1, #set.regions do
            for j = 1, #SWEEP_STEPS do
                local s = SWEEP_STEPS[j]
                Step(set.group, set.regions[i], s[1], s[2], s[3], s[4])
            end
        end
    end
    local moves = Moves(w)
    local bandW = moves and w.bh * BAND_W or w.bw
    Span(w, set.band, moves and -bandW or 0, bandW)
    set.move:SetOffset(moves and (w.bw + bandW) or 0, 0)
    local size = tonumber(view(p .. "GlowSize")) or 1
    set.top:SetHeight(size)
    set.bottom:SetHeight(size)
    set.leftSide:SetWidth(size)
    set.rightSide:SetWidth(size)
    for i = 1, #set.corners do
        set.corners[i]:SetWidth(size)
        set.corners[i]:SetHeight(size)
    end
    return set
end

local LEVEL_PLAYS = { flash = PlayFlash, sweep = PlaySweep }

---------------------------------------------------------------------------------
-- The floating amount
---------------------------------------------------------------------------------

local function ShowAmount(w, view, p, toPct, amount, r, g, b)
    local fs = w.fxAmount
    if not fs then
        fs = w.textHost:CreateFontString(nil, "OVERLAY")
        fs:SetWordWrap(false)
        fs:Hide()
        local group = w.textHost:CreateAnimationGroup()
        Step(group, fs, 1, 0, AMOUNT_FADE, AMOUNT_HOLD)
        w.fxAmountMove = Move(group, fs, AMOUNT_FADE)
        w.fxAmountMove:SetStartDelay(AMOUNT_HOLD)
        group:SetScript("OnFinished", function() fs:Hide() end)
        w.fxAmount, w.fxAmountGroup = fs, group
    end
    w.fxAmountGroup:Stop()
    local size = tonumber(view(p .. "GainTextSize")) or 13
    local font, flags = X.FontPath(view(p .. "Font")), X.OutlineFlag(view(p .. "Outline"))
    X.SetFont(fs, font, size, flags)
    fs:SetTextColor(r, g, b, 1)
    local text = p == "xp" and M.Number(amount, view("xpNumberStyle"), _G.BreakUpLargeNumbers) or M.Short(amount)
    fs:SetText("+" .. text)
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOM", w.body, "TOPLEFT", M.AmountX(toPct, w.bw, size * AMOUNT_MARGIN), (w.above or 0) + size * AMOUNT_GAP)
    w.fxAmountMove:SetOffset(0, size * AMOUNT_RISE)
    fs:Show()
    w.fxAmountGroup:Play()
end

local function StopAmount(w)
    if not w.fxAmount then return end
    w.fxAmountGroup:Stop()
    w.fxAmount:Hide()
end

---------------------------------------------------------------------------------
-- Calls
---------------------------------------------------------------------------------

function X.EffectAvailable(name)
    if name == "pulse" or name == "wave" then return true end
    if name ~= "surge" then return false end
    return X.Atlas(SURGE_RIBBON) ~= nil and X.Atlas(SURGE_PIP) ~= nil
        and X.Atlas(SURGE_GLOW) ~= nil and X.Atlas(SURGE_FLARE) ~= nil
end

function X.ResolveGainEffect(stored)
    if stored == "off" then return "off" end
    if GAIN_PLAYS[stored] and X.EffectAvailable(stored) then return stored end
    return "pulse"
end

-- A secret visibility counts as hidden.
local function Playable(w)
    return w and w.bw and X.UnlockActive ~= true and Plain(w.frame:IsVisible()) == true
end

local function Start(w, set)
    w.fxBusy = set
    ShowRegions(set)
    set.group:Play()
end

-- A gain during another gain merges: the span they cover, whatever order they
-- came in, with the amounts summed, replayed once when it ends. A turn-in's gain
-- (quest) runs beside a level effect; any other gain waits for that effect too.
-- A turn-in's span from 0 is past a level-up, so it replaces the old level's.
function X.PlayGainEffect(w, view, data, fromPct, toPct, amount, quest)
    if not Playable(w) then return end
    local p = w.kind == "xp" and "xp" or "fb"
    local style = X.ResolveGainEffect(view(p .. "GainEffect"))
    if style == "off" then return end
    w.fxView, w.fxData = view, data
    local busy = w.fxBusy
    if w.fxQuest or (busy and not (quest and busy.isLevel)) then
        local from, to = tonumber(fromPct) or 0, tonumber(toPct) or 0
        if quest and from == 0 then
            w.fxPendFrom, w.fxPendTo = 0, to
        else
            w.fxPendFrom = math.min(w.fxPendFrom or from, from)
            w.fxPendTo = math.max(w.fxPendTo or to, to)
        end
        w.fxPendAmount = (w.fxPendAmount or 0) + (amount or 0)
        w.fxPendQuest = w.fxPendQuest or quest
        if quest then w.fxPendFill = w.fxPendFill or tonumber(data.fill) end
        return
    end
    local r, g, b
    if view(p .. "GainMatchBar") == true then
        r, g, b = X.FillEndColor(view, p, data)
    else
        r, g, b = view(p .. "GainColorR"), view(p .. "GainColorG"), view(p .. "GainColorB")
    end
    local set = GAIN_PLAYS[style](w, r, g, b, fromPct, toPct)
    if quest then
        w.fxQuest = set
        ShowRegions(set)
        set.group:Play()
    else
        Start(w, set)
    end
    if view(p .. "GainShowAmount") == true and (amount or 0) > 0 then
        ShowAmount(w, view, p, toPct, amount, r, g, b)
        w.fxAmountQuest = quest
    end
end

-- A level-up or rank-up takes over from a reading's gain. A turn-in's gain and
-- its amount stay, and one that was waiting on the stopped gain starts now.
function X.PlayLevelEffect(w, view)
    if not Playable(w) then return end
    local p = w.kind == "xp" and "xp" or "fb"
    local play = LEVEL_PLAYS[view(p .. "LevelEffect")]
    if not play then return end
    if w.fxBusy then StopSet(w.fxBusy) end
    if not w.fxPendQuest then w.fxPendFrom, w.fxPendTo, w.fxPendAmount = nil, nil, nil end
    if not w.fxAmountQuest then StopAmount(w) end
    local set = play(w, view, p)
    set.isLevel = true
    Start(w, set)
    if w.fxPendQuest then PlayPending(w) end
end

local function StopReady(set)
    set.on = false
    StopSet(set)
end

local function MakeReady(w)
    Host(w)
    local set = { group = w.fx:CreateAnimationGroup(), regions = {} }
    set.tex = InBar(w, set)
    set.group:SetLooping("BOUNCE")
    Step(set.group, set.tex, READY_FROM, READY_TO, READY_TIME)
    w.fxReady = set
    return set
end

-- Constant time when nothing changed. Makes nothing until data.readyEnd is
-- first set; the loop runs only while it shows.
function X.SyncReady(w, view, data, bw, bh)
    local set = w.fxReady
    if not (data.readyEnd and Playable(w)) then
        if set and set.on then StopReady(set) end
        return
    end
    set = set or MakeReady(w)
    Span(w, set.tex, M.EffectSpan(data.fill or 0, data.readyEnd, bw, bh * SPAN_MIN))
    set.tex:SetVertexColor(M.Lift(view("xpQuestR")), M.Lift(view("xpQuestG")), M.Lift(view("xpQuestB")), 1)
    if not set.on then
        set.on = true
        ShowRegions(set)
        set.group:Play()
    end
end

function X.StopEffects(w)
    if not w then return end
    w.fxBusy, w.fxQuest, w.fxAmountQuest = nil, nil, nil
    w.fxPendFrom, w.fxPendTo, w.fxPendAmount, w.fxPendQuest, w.fxPendFill = nil, nil, nil, nil, nil
    if w.fxSets then
        for _, set in pairs(w.fxSets) do StopSet(set) end
    end
    StopAmount(w)
    if w.fxReady and w.fxReady.on then StopReady(w.fxReady) end
end
