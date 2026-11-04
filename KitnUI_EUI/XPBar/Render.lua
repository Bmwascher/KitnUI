-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Render.lua                                 ║
-- ║  Purpose: One bar drawn from settings and data: fills,       ║
-- ║           texts, frame styles, dividers and the profession   ║
-- ║           flipbook. Shared by the live bars and the preview. ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
local M = X.Math

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local Plain = ns.EUIPlain

local WHITE = "Interface\\Buttons\\WHITE8X8"
X.WHITE = WHITE
local STRIPES = "Interface\\AddOns\\KitnUI_EUI\\Media\\XPBar\\stripes"
local PROF_FRAME = "Professions-skillbar-frame"
local BLIZZ_BG, BLIZZ_MASK = "UI-HUD-CoolDownManager-Bar-BG", "UI-HUD-CoolDownManager-Bar"
local FLIP_PREFIX = "Skillbar_Fill_Flipbook_"
local GAP_SEGMENTS = 20
local FLIP_MAX_TILES = 24
-- One flipbook frame's height in its atlas; the row count follows from it.
local FLIP_FRAME_H = 34
-- The profession frame's reach past the bar, and the share of the art its
-- end caps take.
local PROF_FIT = { capFrac = 0.2, offX = -2, offY = -2, top = 0, bot = -3 }
local PROF_PIECES = { "TL", "TM", "TR", "BL", "BM", "BR" }
-- Dashed and dotted marks: on, then off, in physical pixels.
local DASH = { dashed = { 4, 3 }, dotted = { 2, 2 } }

X.PROFESSIONS = {
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Inscription",
    "Jewelcrafting", "Leatherworking", "Mining", "Skinning", "Tailoring", "Cooking", "Fishing",
}

local XP_TEXTS = { "level", "center", "right", "levelTime", "sessionTime", "rate", "compRested" }
local FB_TEXTS = { "left", "right" }

-- The client returns a new table on every lookup and Draw runs on every XP
-- event, so each atlas's info is read once and kept; false marks one this
-- client lacks.
local atlasInfo = {}

local function Atlas(name)
    local T = _G.C_Texture
    if not (T and T.GetAtlasInfo and name) then return nil end
    local info = atlasInfo[name]
    if info == nil then
        local ok, got = pcall(T.GetAtlasInfo, name)
        info = ok and type(got) == "table" and got or false
        atlasInfo[name] = info
    end
    return info or nil
end

X.Atlas = Atlas

function X.StyleAvailable(style)
    local EUI = _G.EllesmereUI
    if style == "eui" then return true end
    if style == "prof" then return Atlas(PROF_FRAME) ~= nil end
    if style == "classic" then
        local CF = EUI and EUI.ClassicFrame
        return type(CF) == "table" and type(CF.Create) == "function" and type(CF.Seat) == "function"
            and type(CF.SetShown) == "function" and type(CF.ScaleK) == "function"
    end
    if style == "forever" then
        return ns.IS_FOREVER == true and EUI ~= nil and type(EUI.ForeverBorder) == "function"
            and type(EUI.ForeverBorderSeat) == "function" and type(EUI.ForeverBorderShown) == "function"
    end
    if style == "blizzard" then return Atlas(BLIZZ_BG) ~= nil and Atlas(BLIZZ_MASK) ~= nil end
    return false
end

-- "" is the client's own default; a style whose art is missing draws as the
-- EUI border.
function X.ResolveStyle(stored)
    if stored == nil or stored == "" then stored = ns.IS_FOREVER and "forever" or "eui" end
    if X.StyleAvailable(stored) then return stored end
    return "eui"
end

function X.ProfessionAvailable(name)
    return type(name) == "string" and Atlas(FLIP_PREFIX .. name) ~= nil
end

local function Media()
    local stub = _G.LibStub
    if not stub then return nil end
    local ok, lib = pcall(stub, "LibSharedMedia-3.0", true)
    return ok and lib or nil
end

local function Fetch(kind, name)
    local lib = Media()
    if not (lib and lib.Fetch) then return nil end
    local ok, path = pcall(lib.Fetch, lib, kind, name, true)
    return ok and type(path) == "string" and path or nil
end

-- The names LibSharedMedia lists for a kind, or nil.
function X.LSMList(kind)
    local lib = Media()
    if not (lib and lib.List) then return nil end
    local ok, list = pcall(lib.List, lib, kind)
    return ok and type(list) == "table" and list or nil
end

local function FontPath(name)
    if name and name ~= "" then
        local path = Fetch("font", name)
        if path then return path end
    end
    local EUI = _G.EllesmereUI
    if EUI and EUI.GetFontPath then
        local ok, path = pcall(EUI.GetFontPath, nil)
        if ok and type(path) == "string" then return path end
    end
    return STANDARD_TEXT_FONT
end

local function Outline(flag)
    if flag == "NONE" then return "" end
    if flag and flag ~= "" then return flag end
    local EUI = _G.EllesmereUI
    if EUI and EUI.GetFontOutlineFlag then
        local ok, value = pcall(EUI.GetFontOutlineFlag, nil)
        if ok and type(value) == "string" then return value end
    end
    return "OUTLINE"
end

X.FontPath, X.OutlineFlag = FontPath, Outline

local function BarTexture(name)
    if name and name ~= "" then return Fetch("statusbar", name) or WHITE end
    return WHITE
end

X.BarTexture = BarTexture

-- One physical pixel: the width of every border and divider line.
local function Pixel()
    local EUI = _G.EllesmereUI
    local m = EUI and EUI.PP and tonumber(EUI.PP.mult)
    return (m and m > 0) and m or 1
end

X.Pixel = Pixel

---------------------------------------------------------------------------------
-- The widget
---------------------------------------------------------------------------------

local function NewBar(parent, level)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetAllPoints(parent)
    bar:SetFrameLevel(level)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    return bar
end

-- One bar: a background, the rested, quest and fill bars (0-100) stacked by
-- frame level, then the dividers, the art and the texts above them. No event
-- and no script: the caller adds what a live bar needs.
function X.NewWidget(parent, kind)
    local frame = CreateFrame("Frame", nil, parent or UIParent)
    local base = Plain(frame:GetFrameLevel()) or 0
    local w = { kind = kind, frame = frame, texts = {}, bars = {}, base = base }
    w.body = CreateFrame("Frame", nil, frame)
    w.body:SetFrameLevel(base + 1)
    w.bg = w.body:CreateTexture(nil, "BACKGROUND")
    w.bg:SetAllPoints(w.body)
    if kind == "xp" then
        w.rested = NewBar(w.body, base + 2)
        w.quest = NewBar(w.body, base + 3)
        w.bars[1], w.bars[2] = w.rested, w.quest
    end
    w.fill = NewBar(w.body, base + 4)
    w.bars[#w.bars + 1] = w.fill
    w.dividers = CreateFrame("Frame", nil, frame)
    w.dividers:SetAllPoints(frame)
    w.dividers:SetFrameLevel(base + 10)
    w.border = CreateFrame("Frame", nil, frame)
    w.border:SetAllPoints(frame)
    w.border:SetFrameLevel(base + 13)
    w.textHost = CreateFrame("Frame", nil, frame)
    w.textHost:SetAllPoints(frame)
    w.textHost:SetFrameLevel(base + 14)
    for _, key in ipairs(kind == "xp" and XP_TEXTS or FB_TEXTS) do
        local fs = w.textHost:CreateFontString(nil, "OVERLAY")
        fs:SetWordWrap(false)
        fs:SetTextColor(1, 1, 1, 1)
        fs:Hide()
        w.texts[key] = fs
    end
    w.colorA, w.colorB = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
    w.above, w.below = 0, 0
    -- Reused by every draw: the rows each edge has filled, and the texts
    -- inside the bar.
    w.rows = { above = { n = 0, l = 0, r = 0, c = false }, below = { n = 0, l = 0, r = 0, c = false } }
    w.inside = {}
    return w
end

local function SetBarTexture(bar, tex)
    if bar.kuiTex ~= tex then
        bar:SetStatusBarTexture(tex)
        bar.kuiTex = tex
    end
    return bar:GetStatusBarTexture()
end

function X.AccentColor()
    local EUI = _G.EllesmereUI
    if EUI and EUI.GetAccentColor then
        local ok, r, g, b = pcall(EUI.GetAccentColor)
        if ok and type(r) == "number" then return r, g, b end
    end
    local pink = ns.KITN_PINK
    if type(pink) == "table" then return pink[1], pink[2], pink[3] end
    return nil
end

-- The fill's gradient ends and direction. The faction bar and the solid
-- styles draw one color; Profession falls back to the solid color wherever
-- the flipbook is not drawn.
local function FillColors(view, p, data)
    if p == "fb" then
        local r, g, b = data.r or 1, data.g or 1, data.b or 1
        return "HORIZONTAL", r, g, b, r, g, b
    end
    local style = view("xpFillStyle")
    if style == "gradient" then
        return view("xpGradDir") == "VERTICAL" and "VERTICAL" or "HORIZONTAL",
            view("xpGradStartR"), view("xpGradStartG"), view("xpGradStartB"),
            view("xpGradEndR"), view("xpGradEndG"), view("xpGradEndB")
    end
    local r, g, b
    if style == "class" then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then r, g, b = c.r, c.g, c.b end
    elseif style == "accent" then
        r, g, b = X.AccentColor()
    end
    if not r then r, g, b = view("xpSolidR"), view("xpSolidG"), view("xpSolidB") end
    return "HORIZONTAL", r, g, b, r, g, b
end

function X.FillEndColor(view, p, data)
    local _, _, _, _, r, g, b = FillColors(view, p, data)
    return r, g, b
end

-- One repeating texture over the rested segment, in this set's own bar, so
-- the gaps cut it as they cut the fill. Made only when first shown.
local function PaintStripes(w, set, view, data)
    local from, to = data.questEnd or 0, data.restedEnd or 0
    if view("xpRestedStripes") ~= true or to <= from then
        if set.stripes then set.stripes:Hide() end
        return
    end
    local t = set.stripes
    if not t then
        t = set.rested:CreateTexture(nil, "OVERLAY")
        t:SetTexture(STRIPES, "REPEAT", "REPEAT")
        set.stripes = t
    end
    local size = max(1, tonumber(view("xpStripeSize")) or 1)
    local left, right = from * w.bw / 100, to * w.bw / 100
    local u1, u2 = M.StripeCoords(left, right, size)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", set.rested, "TOPLEFT", left, 0)
    t:SetPoint("BOTTOMRIGHT", set.rested, "BOTTOMLEFT", right, 0)
    t:SetTexCoord(u1, u2, 0, w.bh / size)
    t:Show()
end

-- Paints one set of background and bars: the widget's own, or a gap
-- segment's copy.
local function PaintSet(w, set, view, p, data, tex, hideFill)
    set.bg:SetColorTexture(view(p .. "BgR"), view(p .. "BgG"), view(p .. "BgB"), view(p .. "BgA"))
    if set.rested then
        SetBarTexture(set.rested, tex)
        set.rested:SetStatusBarColor(view("xpRestedR"), view("xpRestedG"), view("xpRestedB"), view("xpRestedA"))
        set.rested:SetValue(data.restedEnd or 0)
        SetBarTexture(set.quest, tex)
        set.quest:SetStatusBarColor(view("xpQuestR"), view("xpQuestG"), view("xpQuestB"), view("xpQuestA"))
        set.quest:SetValue(data.questEnd or 0)
        PaintStripes(w, set, view, data)
    end
    local ftex = SetBarTexture(set.fill, tex)
    set.fill:SetStatusBarColor(1, 1, 1, 1)
    local dir, r1, g1, b1, r2, g2, b2 = FillColors(view, p, data)
    w.colorA:SetRGBA(r1, g1, b1, 1)
    w.colorB:SetRGBA(r2, g2, b2, 1)
    if ftex then
        if ftex.SetGradient then ftex:SetGradient(dir, w.colorA, w.colorB) end
        ftex:SetAlpha(hideFill and 0 or 1)
    end
    set.fill:SetValue(data.fill or 0)
end

local function SetInset(w, x, y)
    w.body:ClearAllPoints()
    w.body:SetPoint("TOPLEFT", w.frame, "TOPLEFT", x, -y)
    w.body:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", -x, y)
end

---------------------------------------------------------------------------------
-- Frame styles
---------------------------------------------------------------------------------

-- The profession frame. An atlas with slice data keeps its own margins; a
-- flat one gets fixed caps, a stretched middle, and a bottom rail mirrored
-- from the top so both edges match.
local function ProfFrame(w, height)
    local info = Atlas(PROF_FRAME)
    if not info then return end
    local fit = PROF_FIT
    local ov = w.profArt
    if not ov then
        ov = CreateFrame("Frame", nil, w.border)
        ov.tex = ov:CreateTexture(nil, "OVERLAY")
        w.profArt = ov
    end
    ov:ClearAllPoints()
    ov:SetPoint("TOPLEFT", w.frame, "TOPLEFT", -2 + fit.offX, 2 + fit.offY + fit.top)
    ov:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", 2 + fit.offX, -2 + fit.offY - fit.bot)
    ov:Show()
    local sd = info.sliceData
    if sd then
        if ov.flat then for _, t in pairs(ov.flat) do t:Hide() end end
        ov.tex:ClearAllPoints()
        ov.tex:SetAllPoints(ov)
        ov.tex:SetAtlas(PROF_FRAME)
        ov.tex:SetTextureSliceMargins(sd.marginLeft or 0, sd.marginTop or 0, sd.marginRight or 0, sd.marginBottom or 0)
        ov.tex:SetTextureSliceMode(sd.sliceMode or 0)
        ov.tex:Show()
        return
    end
    ov.tex:Hide()
    local s = ov.flat
    if not s then
        s = {}
        for _, key in ipairs(PROF_PIECES) do s[key] = ov:CreateTexture(nil, "OVERLAY") end
        ov.flat = s
    end
    local lc, rc = info.leftTexCoord or 0, info.rightTexCoord or 1
    local tc, bc = info.topTexCoord or 0, info.bottomTexCoord or 1
    local du = rc - lc
    local lMid, rMid = lc + du * fit.capFrac, rc - du * fit.capFrac
    local midU, band = (lc + rc) / 2, du * 0.004
    local vMid = (tc + bc) / 2
    local oh = height + 4 + fit.top + fit.bot
    local scale = (info.height and info.height > 0) and (oh / info.height) or 1
    local capW = fit.capFrac * (info.width or 0) * scale
    if capW <= 0 then capW = oh end
    local file = info.file or info.filename
    for _, t in pairs(s) do
        t:SetTexture(file)
        t:ClearAllPoints()
        t:Show()
    end
    s.TL:SetTexCoord(lc, lMid, tc, vMid)
    s.TL:SetPoint("TOPLEFT", ov, "TOPLEFT")
    s.TL:SetPoint("BOTTOMLEFT", ov, "LEFT")
    s.TL:SetWidth(capW)
    s.BL:SetTexCoord(lc, lMid, vMid, tc)
    s.BL:SetPoint("TOPLEFT", ov, "LEFT")
    s.BL:SetPoint("BOTTOMLEFT", ov, "BOTTOMLEFT")
    s.BL:SetWidth(capW)
    s.TR:SetTexCoord(rMid, rc, tc, vMid)
    s.TR:SetPoint("TOPRIGHT", ov, "TOPRIGHT")
    s.TR:SetPoint("BOTTOMRIGHT", ov, "RIGHT")
    s.TR:SetWidth(capW)
    s.BR:SetTexCoord(rMid, rc, vMid, tc)
    s.BR:SetPoint("TOPRIGHT", ov, "RIGHT")
    s.BR:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT")
    s.BR:SetWidth(capW)
    s.TM:SetTexCoord(midU - band, midU + band, tc, vMid)
    s.TM:SetPoint("TOPLEFT", s.TL, "TOPRIGHT")
    s.TM:SetPoint("BOTTOMRIGHT", s.TR, "BOTTOMLEFT")
    s.BM:SetTexCoord(midU - band, midU + band, vMid, tc)
    s.BM:SetPoint("TOPLEFT", s.BL, "TOPRIGHT")
    s.BM:SetPoint("BOTTOMRIGHT", s.BR, "BOTTOMLEFT")
end

local function ShowArt(w, style)
    local EUI = _G.EllesmereUI
    if w.euiBorder then w.euiBorder:SetShown(style == "eui") end
    if w.profArt then w.profArt:SetShown(style == "prof") end
    if w.classic and EUI and EUI.ClassicFrame then EUI.ClassicFrame.SetShown(w.classic, style == "classic") end
    if w.ring and EUI and EUI.ForeverBorderShown then EUI.ForeverBorderShown(w.ring, style == "forever") end
    if w.blizzBg then w.blizzBg:SetShown(style == "blizzard") end
end

-- Draws the style's art and returns the body's horizontal and vertical inset.
local function ApplyStyle(w, view, p, style, height)
    local EUI = _G.EllesmereUI
    ShowArt(w, style)
    if style == "eui" then
        if not w.euiBorder then
            w.euiBorder = CreateFrame("Frame", nil, w.border)
            w.euiBorder:SetAllPoints(w.frame)
        end
        w.euiBorder:Show()
        local size = tonumber(view(p .. "BorderSize")) or 0
        if EUI and EUI.ApplyBorderStyle then
            pcall(EUI.ApplyBorderStyle, w.euiBorder, size, view(p .. "BorderR"), view(p .. "BorderG"),
                view(p .. "BorderB"), view(p .. "BorderA"), view(p .. "BorderTexture"))
        end
        local inset = size * Pixel()
        return inset, inset
    elseif style == "prof" then
        ProfFrame(w, height)
        return 0, 2
    elseif style == "classic" then
        local CF = EUI.ClassicFrame
        if not w.classic then w.classic = CF.Create(w.border, "ARTWORK", 2) end
        CF.SetShown(w.classic, true)
        return 0, 0
    elseif style == "forever" then
        if not w.ring then w.ring = EUI.ForeverBorder(w.border, "ARTWORK", 2) end
        if w.ring then
            EUI.ForeverBorderSeat(w.ring, w.frame)
            EUI.ForeverBorderShown(w.ring, true)
        end
        local e = EUI.FOREVER_BORDER and tonumber(EUI.FOREVER_BORDER.fill) or 0
        return e, e
    elseif style == "blizzard" then
        if not w.blizzBg then w.blizzBg = w.frame:CreateTexture(nil, "BACKGROUND", nil, -2) end
        w.blizzBg:SetAtlas(BLIZZ_BG)
        w.blizzBg:ClearAllPoints()
        w.blizzBg:SetPoint("TOPLEFT", w.frame, "TOPLEFT", -2, 3)
        w.blizzBg:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", 6, -7)
        w.blizzBg:Show()
        return 0, 0
    end
    return 0, 0
end

local function MaskOne(w, tex, on)
    if not tex then return end
    if on and not tex.kuiBlizz then
        tex:AddMaskTexture(w.blizzMask)
        tex.kuiBlizz = true
    elseif not on and tex.kuiBlizz then
        tex:RemoveMaskTexture(w.blizzMask)
        tex.kuiBlizz = nil
    end
end

local function MaskBar(w, bar, on)
    if not bar then return end
    local tex = bar:GetStatusBarTexture()
    if bar.kuiMasked and bar.kuiMasked ~= tex then MaskOne(w, bar.kuiMasked, false) end
    MaskOne(w, tex, on)
    bar.kuiMasked = on and tex or nil
end

-- For a region made between draws, which no SyncMasks run would reach until
-- the next draw.
function X.MaskEffect(w, region)
    MaskOne(w, region, w.masksOn == true)
end

-- The Blizzard style's silhouette on every texture that can paint inside the
-- bar; the backgrounds are hidden instead, since the style's frame art is the
-- background. Undone when the style changes. Runs after the gaps, tiles and
-- lines are made, so textures made in this draw are covered.
local function SyncMasks(w, on)
    w.masksOn = on and true or false
    if not (on or w.blizzMask) then return end
    if on and not w.blizzMask then
        w.blizzMask = w.body:CreateMaskTexture()
        w.blizzMask:SetAtlas(BLIZZ_MASK)
        w.blizzMask:SetAllPoints(w.body)
    end
    for i = 1, #w.bars do MaskBar(w, w.bars[i], on) end
    MaskOne(w, w.stripes, on)
    local segs = w.segments
    if segs then
        for i = 1, #segs do
            local copy = segs[i].copy
            copy.bg:SetShown(not on)
            MaskBar(w, copy.rested, on)
            MaskBar(w, copy.quest, on)
            MaskBar(w, copy.fill, on)
            MaskOne(w, copy.stripes, on)
        end
    end
    local marks = w.marks
    if marks then
        for i = 1, #marks do MaskOne(w, marks[i], on) end
    end
    local tiles = w.tiles
    if tiles then
        for i = 1, #tiles do
            MaskOne(w, tiles[i].idle, on)
            MaskOne(w, tiles[i].flip, on)
        end
    end
    local strips = w.gapStrips
    if strips then
        for i = 1, #strips do MaskOne(w, strips[i], on) end
    end
    local fx = w.fxRegions
    if fx then
        for i = 1, #fx do MaskOne(w, fx[i], on) end
    end
end

---------------------------------------------------------------------------------
-- Profession flipbook
---------------------------------------------------------------------------------

-- A tile: the idle first frame behind, and the animated layer in front with
-- its own group. Both are masked to the fill's edge.
local function NewTile(w)
    local t = {}
    t.idle = w.fill:CreateTexture(nil, "OVERLAY", nil, 0)
    t.flip = w.fill:CreateTexture(nil, "OVERLAY", nil, 1)
    t.idle:AddMaskTexture(w.flipMask)
    t.flip:AddMaskTexture(w.flipMask)
    t.group = w.fill:CreateAnimationGroup()
    t.anim = t.group:CreateAnimation("FlipBook")
    t.anim:SetTarget(t.flip)
    t.anim:SetDuration(2)
    t.anim:SetFlipBookColumns(2)
    t.anim:SetFlipBookFrameWidth(0)
    t.anim:SetFlipBookFrameHeight(0)
    t.group:SetScript("OnFinished", function() t.flip:Hide() end)
    t.flip:Hide()
    return t
end

local function StopTile(t)
    t.group:Stop()
    t.flip:Hide()
    t.idle:Hide()
end

local function HideTiles(w)
    local tiles = w.tiles
    if not tiles then return end
    for i = 1, #tiles do StopTile(tiles[i]) end
    w.flipOn, w.flipCount, w.flipAtlas, w.flipPlay = nil, nil, nil, nil
end

local function PlaceTile(tex, anchor, x, tw)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, 0)
    tex:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", x, 0)
    tex:SetWidth(tw)
end

-- Tiles copies of the art at its own proportions across the bar, revealed
-- up to the fill's edge, or one copy across the whole bar with Stretch on.
local function Flip(w, view, bw, bh)
    local atlas = FLIP_PREFIX .. tostring(view("xpProfFill"))
    local info = Atlas(atlas)
    if not info then
        HideTiles(w)
        return
    end
    if not w.flipMask then
        w.flipMask = w.fill:CreateMaskTexture()
        w.flipMask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        w.tiles = {}
    end
    local ftex = w.fill:GetStatusBarTexture()
    w.flipMask:ClearAllPoints()
    if ftex then w.flipMask:SetPoint("RIGHT", ftex, "RIGHT") end
    w.flipMask:SetSize(max(1, bw), max(1, bh))
    local artH = info.height or FLIP_FRAME_H
    local rows = max(1, floor(artH / FLIP_FRAME_H + 0.5))
    local n, tw = 1, bw
    if not view("xpProfStretch") and bh > 0 and (info.width or 0) > 0 then
        tw = max(1, bh * (info.width / 2) / (artH / rows))
        n = max(1, ceil(bw / tw))
        if n > FLIP_MAX_TILES then
            n = FLIP_MAX_TILES
            tw = bw / n
        end
    end
    local tiles = w.tiles
    for i = #tiles + 1, n do tiles[i] = NewTile(w) end
    for i = n + 1, #tiles do StopTile(tiles[i]) end
    local play = view("xpProfPlay")
    local resync = n ~= w.flipCount or atlas ~= w.flipAtlas or play ~= w.flipPlay
    local file = info.file or info.filename
    local l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
    local tp, b = info.topTexCoord or 0, info.bottomTexCoord or 1
    for i = 1, n do
        local t = tiles[i]
        if resync then
            t.group:Stop()
            t.flip:Hide()
        end
        if t.atlas ~= atlas then
            t.anim:SetFlipBookRows(rows)
            t.anim:SetFlipBookFrames(rows * 2)
            t.flip:SetAtlas(atlas)
            t.idle:SetTexture(file)
            t.idle:SetTexCoord(l, l + (r - l) / 2, tp, tp + (b - tp) / rows)
            t.atlas = atlas
        end
        local x = (i - 1) * tw
        PlaceTile(t.idle, w.fill, x, tw)
        PlaceTile(t.flip, w.fill, x, tw)
        t.idle:Show()
        if play == "loop" then
            if not t.group:IsPlaying() then
                t.group:SetLooping("REPEAT")
                t.flip:Show()
                t.group:Play()
            end
        elseif not t.group:IsPlaying() then
            t.group:SetLooping("NONE")
            t.flip:Hide()
        end
    end
    w.flipOn, w.flipCount, w.flipAtlas, w.flipPlay = true, n, atlas, play
end

-- One pass on every tile together; a gain during a pass lets it finish.
function X.PlayGain(w)
    if not (w and w.flipOn and w.flipPlay == "gain" and w.tiles) then return end
    for i = 1, w.flipCount or 0 do
        local t = w.tiles[i]
        if t and not t.group:IsPlaying() then
            t.flip:Show()
            t.group:Play()
        end
    end
end

---------------------------------------------------------------------------------
-- Dividers
---------------------------------------------------------------------------------

-- A gap segment clips a full-size copy of the bar, so every segment shows
-- its own slice of one continuous fill and gradient.
local function NewSegment(w)
    local s = CreateFrame("Frame", nil, w.frame)
    s:SetClipsChildren(true)
    s:SetFrameLevel(w.base + 5)
    local copy = CreateFrame("Frame", nil, s)
    copy:SetFrameLevel(w.base + 5)
    copy.bg = copy:CreateTexture(nil, "BACKGROUND")
    copy.bg:SetAllPoints(copy)
    if w.kind == "xp" then
        copy.rested = NewBar(copy, w.base + 6)
        copy.quest = NewBar(copy, w.base + 7)
    end
    copy.fill = NewBar(copy, w.base + 8)
    s.copy = copy
    return s
end

-- The gap actually drawn: the setting, shrunk where twenty segments of at
-- least a pixel each would not fit, so the segments always span exactly the
-- bar.
local function GapWidth(view, p, bw)
    local gap = max(0, tonumber(view(p .. "GapSize")) or 0)
    return min(gap, max(0, (bw - GAP_SEGMENTS) / (GAP_SEGMENTS - 1)))
end

-- Clipped copies for every fill but the profession art: each copy would need
-- its own animated tiles, twenty times over. With the profession art the bar
-- stays whole and the gaps are drawn over it in the background color.
local function Gaps(w, view, p, data, tex, bw, bh, on, prof)
    local segs, strips = w.segments, w.gapStrips
    local gap = on and GapWidth(view, p, bw) or 0
    local segW = (bw - gap * (GAP_SEGMENTS - 1)) / GAP_SEGMENTS
    local cut = on and not prof
    local over = on and prof and gap > 0
    if segs and not cut then for i = 1, #segs do segs[i]:Hide() end end
    if strips and not over then for i = 1, #strips do strips[i]:Hide() end end
    w.body:SetAlpha(cut and 0 or 1)
    if cut then
        if not segs then
            segs = {}
            w.segments = segs
        end
        for i = 1, GAP_SEGMENTS do
            local s = segs[i] or NewSegment(w)
            segs[i] = s
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", w.body, "TOPLEFT", (i - 1) * (segW + gap), 0)
            s:SetSize(segW, bh)
            s:Show()
            s.copy:ClearAllPoints()
            s.copy:SetPoint("TOPLEFT", w.body, "TOPLEFT", 0, 0)
            s.copy:SetSize(bw, bh)
            PaintSet(w, s.copy, view, p, data, tex, false)
        end
    elseif over then
        if not strips then
            strips = {}
            w.gapStrips = strips
        end
        local r, g, b = view(p .. "BgR"), view(p .. "BgG"), view(p .. "BgB")
        for i = 1, GAP_SEGMENTS - 1 do
            local t = strips[i]
            if not t then
                t = w.dividers:CreateTexture(nil, "ARTWORK")
                t:SetTexture(WHITE)
                strips[i] = t
            end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", w.body, "TOPLEFT", i * segW + (i - 1) * gap, 0)
            t:SetSize(gap, bh)
            t:SetVertexColor(r, g, b, 1)
            t:Show()
        end
    end
end

local function MarkTexture(w, i)
    local pool = w.marks
    if not pool then
        pool = {}
        w.marks = pool
    end
    local t = pool[i]
    if not t then
        t = w.dividers:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        pool[i] = t
    end
    return t
end

local function MarkLabel(w, i)
    local pool = w.markLabels
    if not pool then
        pool = {}
        w.markLabels = pool
    end
    local fs = pool[i]
    if not fs then
        fs = w.dividers:CreateFontString(nil, "OVERLAY")
        fs:SetWordWrap(false)
        pool[i] = fs
    end
    return fs
end

local function HidePool(pool, from)
    if not pool then return end
    for i = from, #pool do pool[i]:Hide() end
end

-- 5% marks in the chosen style, solid 10% marks, optional 10% labels, and
-- Smart Ticks hiding the marks the fill has passed.
local function Lines(w, view, p, data, bw, bh, on, font, flags)
    local used, labels = 0, 0
    if on then
        local px = Pixel()
        local style5 = view(p .. "Tick5Style")
        local smart = view(p .. "SmartTicks") == true
        local showLabels = view(p .. "TickLabels") == true
        local fill = data.fill or 0
        for i = 1, 19 do
            local pct = i * 5
            local is10 = i % 2 == 0
            local style = is10 and "solid" or style5
            local x = floor(bw * pct / 100 / px + 0.5) * px
            if style ~= "none" and not (smart and pct <= fill) then
                local stem = p .. (is10 and "Tick10" or "Tick5")
                local r, g, b, a = view(stem .. "R"), view(stem .. "G"), view(stem .. "B"), view(stem .. "A")
                local dash = DASH[style]
                if dash then
                    local dashOn, dashOff = dash[1] * px, dash[2] * px
                    local y = 0
                    while y < bh do
                        used = used + 1
                        local t = MarkTexture(w, used)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", w.body, "TOPLEFT", x, -y)
                        t:SetSize(px, min(dashOn, bh - y))
                        t:SetVertexColor(r, g, b, a)
                        t:Show()
                        y = y + dashOn + dashOff
                    end
                else
                    used = used + 1
                    local t = MarkTexture(w, used)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", w.body, "TOPLEFT", x, 0)
                    t:SetSize(px, bh)
                    t:SetVertexColor(r, g, b, a)
                    t:Show()
                end
            end
            if is10 and showLabels then
                labels = labels + 1
                local fs = MarkLabel(w, labels)
                local size = tonumber(view(p .. "TickLabelSize")) or 8
                if not fs:SetFont(font, size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
                fs:SetTextColor(view(p .. "TickLabelR"), view(p .. "TickLabelG"), view(p .. "TickLabelB"), 1)
                fs:SetText(tostring(pct))
                fs:ClearAllPoints()
                -- Labels sit inside the bar with the texts; the offsets let a
                -- player move them clear.
                local ox = tonumber(view(p .. "TickLabelOffX")) or 0
                local oy = tonumber(view(p .. "TickLabelOffY")) or 0
                fs:SetPoint("LEFT", w.body, "LEFT", x + 2 * px + ox, oy)
                fs:Show()
            end
        end
    end
    HidePool(w.marks, used + 1)
    HidePool(w.markLabels, labels + 1)
end

---------------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------------

local function SetText(fs, text, font, size, flags)
    if not text then
        fs:Hide()
        return false
    end
    if not fs:SetFont(font, size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
    -- Width 0 is the automatic width: it lifts the cap an earlier draw set.
    fs:SetWidth(0)
    fs:SetText(text)
    fs:Show()
    return true
end

local function TextWidth(fs)
    if not (fs and Plain(fs:IsShown()) == true) then return 0 end
    local width = Plain(fs:GetStringWidth())
    return type(width) == "number" and width or 0
end

local function PlaceAround(fs, w, edge, side, row, step, gap, pad, ox, oy)
    local h = side == "left" and "LEFT" or side == "right" and "RIGHT" or ""
    local x = (side == "left" and pad or side == "right" and -pad or 0) + ox
    fs:ClearAllPoints()
    if edge == "above" then
        fs:SetPoint("BOTTOM" .. h, w.frame, "TOP" .. h, x, gap + row * step + oy)
    else
        fs:SetPoint("TOP" .. h, w.frame, "BOTTOM" .. h, x, -(gap + row * step) + oy)
    end
end

-- One text on an edge's rows, in call order. A left and a right text share a
-- row only when both fit across the bar beside each other, measured; a
-- centered text takes a row of its own. So no two texts on an edge overlap,
-- at any font size or bar width, until an offset moves one.
local function PlaceRow(fs, w, edge, side, rowW, step, gap, pad, ox, oy)
    local e = w.rows[edge]
    local width = TextWidth(fs)
    local fits = e.n > 0 and not e.c and side ~= "center"
    if fits and side == "left" then fits = e.l == 0 and width + e.r + 3 * pad <= rowW end
    if fits and side == "right" then fits = e.r == 0 and width + e.l + 3 * pad <= rowW end
    if not fits then e.n, e.l, e.r, e.c = e.n + 1, 0, 0, false end
    if side == "left" then e.l = width elseif side == "right" then e.r = width else e.c = true end
    PlaceAround(fs, w, edge, side, e.n - 1, step, gap, pad, ox, oy)
end

-- One text inside the bar, or on the next row of its edge, then moved by its
-- own offsets ox, oy.
local function Place(fs, w, text, pos, side, font, size, flags, rowW, step, gap, pad, ox, oy)
    if not SetText(fs, text, font, size, flags) then return end
    if pos == "above" or pos == "below" then
        PlaceRow(fs, w, pos, side, rowW, step, gap, pad, ox, oy)
        return
    end
    local point = side == "left" and "LEFT" or side == "right" and "RIGHT" or "CENTER"
    fs:ClearAllPoints()
    fs:SetPoint(point, w.body, point, (side == "left" and pad or side == "right" and -pad or 0) + ox, oy)
    w.inside[side] = fs
end

-- A capped text ends in an ellipsis; one with no room at all hides.
local function Fit(fs, cap)
    if not (fs and cap) then return end
    if cap < 1 then fs:Hide() else fs:SetWidth(cap) end
end

-- The texts inside the bar share one row (Math.InsideCaps has the rule).
local function FitInside(w, bw, pad)
    local s = w.inside
    local capL, capC, capR = M.InsideCaps(bw - 2 * pad, pad,
        s.left and TextWidth(s.left), s.center and TextWidth(s.center), s.right and TextWidth(s.right))
    Fit(s.left, capL)
    Fit(s.center, capC)
    Fit(s.right, capR)
end

local function EdgeRoom(e, step, gap)
    return e.n > 0 and (gap + e.n * step) or 0
end

-- A text's saved X and Y offsets, from the stem of its keys.
local function Offsets(view, stem)
    return tonumber(view(stem .. "OffX")) or 0, tonumber(view(stem .. "OffY")) or 0
end

-- The stacking step and the padding follow the font size, so no spacing is
-- a fixed pixel count.
local function LayoutTexts(w, view, p, data, font, flags, width, bw)
    local T, rows, inside = w.texts, w.rows, w.inside
    rows.above.n, rows.below.n = 0, 0
    inside.left, inside.center, inside.right = nil, nil, nil
    local size = tonumber(view(p .. "FontSize")) or 12
    local pad = ceil(size * 0.4)
    local step, gap
    if p == "fb" then
        step, gap = ceil(size * 1.25), ceil(size * 0.2)
        Place(T.left, w, data.left, view("fbNamePos"), "left", font, size, flags, width, step, gap, pad, Offsets(view, "fbName"))
        Place(T.right, w, data.right, view("fbAmountPos"), "right", font, size, flags, width, step, gap, pad, Offsets(view, "fbAmount"))
    else
        local around = max(6, size - 1)
        step, gap = ceil(around * 1.25), ceil(around * 0.2)
        Place(T.level, w, data.level, "inside", "left", font, size, flags, width, step, gap, pad, 0, 0)
        Place(T.right, w, data.right, "inside", "right", font, size, flags, width, step, gap, pad, 0, 0)
        Place(T.levelTime, w, data.levelTime, view("xpLevelTimePos"), "left", font, around, flags, width, step, gap, pad, Offsets(view, "xpLevelTime"))
        Place(T.sessionTime, w, data.sessionTime, view("xpSessionTimePos"), "right", font, around, flags, width, step, gap, pad, Offsets(view, "xpSessionTime"))
        Place(T.rate, w, data.rate, view("xpRatePos"), "left", font, around, flags, width, step, gap, pad, Offsets(view, "xpRate"))
        Place(T.compRested, w, data.compRested, view("xpCompRestedPos"), "right", font, around, flags, width, step, gap, pad, Offsets(view, "xpCompRested"))
        local pos = view("xpAmountPos")
        Place(T.center, w, data.center, pos, "center", font, pos == "inside" and size or around, flags, width, step, gap, pad, Offsets(view, "xpAmount"))
    end
    FitInside(w, bw, pad)
    w.above, w.below = EdgeRoom(rows.above, step, gap), EdgeRoom(rows.below, step, gap)
end

---------------------------------------------------------------------------------
-- Draw
---------------------------------------------------------------------------------

-- view(key) reads a setting: the live store, for the real bars and the
-- preview alike. data is what XPView or FactionView built.
function X.Draw(w, view, data)
    if not (w and view and data) then return end
    local p = w.kind == "xp" and "xp" or "fb"
    local width, height = tonumber(view(p .. "Width")) or 100, tonumber(view(p .. "Height")) or 10
    w.frame:SetSize(width, height)
    local style = X.ResolveStyle(view(p .. "FrameStyle"))
    local ix, iy = ApplyStyle(w, view, p, style, height)
    SetInset(w, ix, iy)
    if style == "classic" then
        local CF = _G.EllesmereUI.ClassicFrame
        CF.Seat(w.classic, w.body, CF.ScaleK(), false)
    end
    local bw, bh = max(1, width - 2 * ix), max(1, height - 2 * iy)
    w.bw, w.bh = bw, bh
    local tex = BarTexture(view(p .. "Texture"))
    local divider = view(p .. "Divider")
    local prof = p == "xp" and view("xpFillStyle") == "profession" and X.ProfessionAvailable(view("xpProfFill"))
    PaintSet(w, w, view, p, data, tex, prof)
    w.bg:SetShown(style ~= "blizzard")
    if prof then Flip(w, view, bw, bh) else HideTiles(w) end
    Gaps(w, view, p, data, tex, bw, bh, divider == "gaps", prof)
    local font, flags = FontPath(view(p .. "Font")), Outline(view(p .. "Outline"))
    Lines(w, view, p, data, bw, bh, divider == "lines", font, flags)
    SyncMasks(w, style == "blizzard")
    X.SyncReady(w, view, data, bw, bh)
    LayoutTexts(w, view, p, data, font, flags, width, bw)
    w.textAbove, w.textBelow, w.insetY = w.above, w.below, iy
    if p == "xp" and X.SyncMarkers then X.SyncMarkers(w, view, data.markers) end
end
