-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Preview.lua                                ║
-- ║  Purpose: The live preview pinned above the XP Bar options   ║
-- ║           page: the selected bar, drawn with sample values.  ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar

local STAGE_PAD_Y = 14
-- The bar picker above the stage: its gap from the top, width, height, and
-- the gap below it.
local PICK_TOP, PICK_W, PICK_H, PICK_GAP = 14, 260, 30, 12
-- Overlay levels above a bar's base, over its top layer (the texts, at 14).
local HIT_FRAME, HIT_BODY, HIT_FILL, HIT_TEXT = 20, 21, 22, 30
-- How far the frame's overlay reaches past the bar.
local RING_OUT = 4

local Plain = ns.EUIPlain

-- wrap is UNSCALED and centered on the stage; content holds the fit scale at
-- offset 0,0 inside it. An offset on a scaled frame is in its own scaled
-- space, so the centering must not live on the scaled frame.
local stage, wrap, content, picker
local widgets = {}
local hits, hitsBuilt = { xp = {}, fb = {}, tk = {}, px = {} }, {}
local availW = 1
-- The bar the page and the preview show, kept for the session only.
local selected = "xp"

-- Every piece visible: quest XP, rested XP, both times and a rate, even on a
-- character at max level or with no rested XP.
local sampleXP = {
    level = 59, cur = 94410, max = 209800, quest = 31470, rested = 52450,
    atMax = false, xpOff = false, levelTime = 1200, elapsed = 3600, gained = 90000,
    -- The card's rows; the bars read none of these.
    trend = "up", played = 1468800, pace = 1500,
    hist = {
        n = 3, levels = { 58, 57, 56 }, texts = { "1:12:05", "58:40", "49:12" }, secs = { 4325, 3520, 2952 },
        -- Other characters' times for two levels and the current one, so the sample
        -- shows bars both ways, a starred row and the legend.
        acct = { 3900, 3900 }, curAcct = 4800,
        ref = {}, src = {}, share = {}, gap = {}, star = {}, gapText = {},
    },
}
-- Argent Dawn at Revered: 13,020 of the 21,000 that reach Exalted.
local REVERED = 7
local sampleFaction = {
    kind = "standard", name = "Argent Dawn", reaction = REVERED, cur = 13020, min = 0, max = 21000, isMax = false,
}
local xpOut, fbOut, cardOut = {}, {}, {}
-- The sample's completed levels, of which the page's slider shows the newest.
local SAMPLE_LEVELS = sampleXP.hist.n
-- What Play Gain draws on the sample: a span in percent, and the amounts.
local SAMPLE_SPAN, SAMPLE_XP, SAMPLE_REP = 10, 20980, 2100
-- The party card's most rows, and the gap beside the cards and above the sample bar.
local PARTY_ROWS, PARTY_GAP = 4, 12
local partyShown = 0

local function Pad()
    return (EllesmereUI and EllesmereUI.CONTENT_PAD) or 10
end

local function SampleFaction()
    local label = _G.FACTION_STANDING_LABEL7
    sampleFaction.label = type(label) == "string" and label or "Revered"
    return sampleFaction
end

function X.SelectedBar()
    return selected
end

-- The page builds only the selected bar's sections, so a pick rebuilds it,
-- and the rebuilt page mounts this header again. The rebuild keeps the old
-- scroll, so the page then goes to its top: the player lands on the selected
-- bar's first section.
function X.SelectBar(kind)
    if (kind ~= "xp" and kind ~= "fb" and kind ~= "tk") or kind == selected then return end
    selected = kind
    if EllesmereUI and EllesmereUI.RefreshPage then
        pcall(EllesmereUI.RefreshPage, EllesmereUI, true)
        if EllesmereUI.ScrollToTop then pcall(EllesmereUI.ScrollToTop, EllesmereUI) end
    else
        X.PreviewRefresh()
    end
end

-- Without the picker the page carries its own.
function X.SelectorShown()
    return picker ~= nil
end

local function PickerRoom()
    return picker and (PICK_TOP + PICK_H + PICK_GAP) or 0
end

-- Made once and moved to each header it is mounted in, as the stage is.
local function MountPicker(parent)
    local level = (Plain(parent:GetFrameLevel()) or 0) + 5
    if not picker and EllesmereUI and EllesmereUI.BuildDropdownControl then
        local ok, btn = pcall(EllesmereUI.BuildDropdownControl, parent, PICK_W, level, X.BAR_V, X.BAR_O,
            X.SelectedBar, X.SelectBar)
        if ok and btn then picker = btn end
    end
    if not picker then return end
    picker:SetParent(parent)
    picker:SetFrameLevel(level)
    picker:ClearAllPoints()
    picker:SetPoint("TOP", parent, "TOP", 0, -PICK_TOP)
    picker:SetHeight(PICK_H)
    picker:Show()
    if picker._refreshLabel then pcall(picker._refreshLabel) end
end

local function Navigate(key)
    if X.NavigateToSetting then X.NavigateToSetting(key) end
end

local function AddHit(w, key, element, isText, level)
    local ok, btn = pcall(EllesmereUI.CreatePreviewHitOverlay, element, Navigate, key, isText, w.base + level,
        { parent = w.frame })
    if ok and btn then hits[w.kind][key] = btn end
end

local function AddCardHit(w, key, element, isText, go)
    local ok, btn = pcall(EllesmereUI.CreatePreviewHitOverlay, element, go, key, isText, w.base + HIT_TEXT,
        { parent = w.frame })
    if ok and btn then hits.tk[key] = btn end
end

local function GoToTop() Navigate("tkTop") end

-- An overlay fits one text, so each part of the top line and both columns of a
-- row has its own. A row's overlays lead to whatever that row shows now, so
-- which rows are on never strands a press.
local function BuildCardHits(w)
    local card = w.frame
    AddHit(w, "tkBack", card, false, HIT_FRAME)
    AddCardHit(w, "tkTop", card.top, true, GoToTop)
    AddCardHit(w, "tkDing", card.topR, true, GoToTop)
    AddCardHit(w, "tkArrow", card.arrow, false, GoToTop)
    for i = 1, #card.left do
        local function GoToRow() Navigate(cardOut.keys and cardOut.keys[i]) end
        AddCardHit(w, "tkRow" .. i, card.left[i], true, GoToRow)
        AddCardHit(w, "tkValue" .. i, card.right[i], true, GoToRow)
    end
end

local function AddPartyHit(w, key, element, isText, level, go)
    local ok, btn = pcall(EllesmereUI.CreatePreviewHitOverlay, element, go, key, isText, w.base + level,
        { parent = w.frame })
    if ok and btn then hits.px[key] = btn end
end

local function GoToFont() Navigate("pxFont") end
local function GoToFill() Navigate("pxFill") end
local function GoToSize() Navigate("pxSize") end

-- Every row the sample can show, so turning Show Self on later has its overlays.
local function BuildPartyHits(w)
    local card = w.frame
    AddHit(w, "pxBack", card, false, HIT_FRAME)
    for i = 1, PARTY_ROWS do
        local row = X.PartyCardRow(card, i)
        AddPartyHit(w, "pxName" .. i, row.name, true, HIT_TEXT, GoToFont)
        AddPartyHit(w, "pxBar" .. i, row.bar, false, HIT_FILL, GoToFill)
        AddPartyHit(w, "pxText" .. i, row.text, true, HIT_TEXT, GoToSize)
    end
end

-- Each part of a bar leads to the row that sets it. Made once per bar, the
-- first time the host has the overlay helper and the colors it draws with.
local function BuildHits(kind)
    local EUI, w = EllesmereUI, widgets[kind]
    if hitsBuilt[kind] or not w then return end
    if not (EUI and EUI.CreatePreviewHitOverlay and EUI.ELLESMERE_GREEN and EUI.PP and EUI.PP.CreateBorder) then
        return
    end
    hitsBuilt[kind] = true
    if kind == "tk" then
        BuildCardHits(w)
        return
    end
    if kind == "px" then
        BuildPartyHits(w)
        return
    end
    local ring = CreateFrame("Frame", nil, w.frame)
    ring:SetPoint("TOPLEFT", w.frame, "TOPLEFT", -RING_OUT, RING_OUT)
    ring:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", RING_OUT, -RING_OUT)
    AddHit(w, "frame", ring, false, HIT_FRAME)
    AddHit(w, "body", w.body, false, HIT_BODY)
    AddHit(w, "fill", w.fill, false, HIT_FILL)
    for key, fs in pairs(w.texts) do AddHit(w, key, fs, true, HIT_TEXT) end
end

local function SyncCardHit(btn, on)
    if not btn then return end
    btn:SetShown(on)
    if on and btn._resizeToText then pcall(btn._resizeToText) end
end

local function SyncPartyHits()
    local list = hits.px
    for i = 1, PARTY_ROWS do
        local on = i <= partyShown
        SyncCardHit(list["pxName" .. i], on)
        SyncCardHit(list["pxBar" .. i], on)
        SyncCardHit(list["pxText" .. i], on)
    end
end

local function SyncCardHits()
    local list = hits.tk
    SyncCardHit(list.tkTop, true)
    SyncCardHit(list.tkDing, true)
    SyncCardHit(list.tkArrow, cardOut.arrow ~= nil)
    for i = 1, #widgets.tk.frame.left do
        local on = i <= (cardOut.n or 0)
        SyncCardHit(list["tkRow" .. i], on)
        SyncCardHit(list["tkValue" .. i], on)
    end
end

-- The fill's overlay covers the filled part only; a text's shows only with
-- its text.
local function SyncHits(kind)
    if kind == "tk" then
        SyncCardHits()
        return
    end
    if kind == "px" then
        SyncPartyHits()
        return
    end
    local w, list = widgets[kind], hits[kind]
    local tex = list.fill and w.fill:GetStatusBarTexture()
    if tex then
        list.fill:ClearAllPoints()
        list.fill:SetAllPoints(tex)
    end
    for key, fs in pairs(w.texts) do
        local btn = list[key]
        if btn then
            local on = Plain(fs:IsShown()) == true
            btn:SetShown(on)
            if on and btn._resizeToText then pcall(btn._resizeToText) end
        end
    end
end

-- With Party Markers on, the party card sits beside the ticker's sample, tops
-- aligned, with a sample XP bar below both. With it off, the card sits under the
-- ticker's sample, as on screen. Returns the width and height of the whole. w is
-- the ticker's sample, bw its width and h its height.
local function LayoutStack(w, bw, h)
    local party = widgets.px
    if not party then
        local card = X.NewPartyCard(content)
        party = { kind = "px", frame = card, base = Plain(card:GetFrameLevel()) or 0, above = 0, below = 0 }
        widgets.px = party
        BuildHits("px")
    end
    local rows, n = X.PartySampleRows(X.Get)
    partyShown = n
    party.frame.dirty = true
    X.DrawPartyCard(party.frame, X.Get, rows, n)
    party.frame:Show()
    SyncHits("px")
    local bar = widgets.xp
    local withBar = bar and X.Get("xpPartyMarkers") == true
    local pairW
    if withBar then
        pairW = bw + PARTY_GAP + party.frame.kuiW
        h = math.max(h, party.frame.kuiH)
    else
        pairW = math.max(bw, party.frame.kuiW)
        h = h + X.PARTY_STACK_GAP + party.frame.kuiH
    end
    local totalW = pairW
    if withBar then
        X.XPView(sampleXP, X.Get, xpOut)
        xpOut.readyEnd = nil
        xpOut.markers = X.PartySampleMarks()
        X.Draw(bar, X.Get, xpOut)
        xpOut.markers = nil
        bar.frame:Show()
        SyncHits("xp")
        local barW = tonumber(X.Get("xpWidth")) or 100
        local barH = tonumber(X.Get("xpHeight")) or 10
        local top = h + PARTY_GAP + (bar.above or 0)
        bar.frame:ClearAllPoints()
        bar.frame:SetPoint("TOP", content, "TOP", 0, -top)
        h = top + barH + (bar.below or 0)
        totalW = math.max(totalW, barW)
    end
    w.frame:ClearAllPoints()
    w.frame:SetPoint("TOPLEFT", content, "TOPLEFT", (totalW - pairW) / 2, 0)
    party.frame:ClearAllPoints()
    if withBar then
        party.frame:SetPoint("TOPLEFT", w.frame, "TOPRIGHT", PARTY_GAP, 0)
    else
        party.frame:SetPoint("TOPLEFT", w.frame, "BOTTOMLEFT", 0, -X.PARTY_STACK_GAP)
    end
    return totalW, h
end

local function Layout()
    if selected == "tk" and content and not widgets.tk then
        local card = X.NewCard(content)
        widgets.tk = { kind = "tk", frame = card, base = Plain(card:GetFrameLevel()) or 0, above = 0, below = 0 }
        BuildHits("tk")
    end
    local w = content and widgets[selected]
    if not w then return 0 end
    for kind, other in pairs(widgets) do
        if kind ~= selected then
            X.StopEffects(other)
            other.frame:Hide()
        end
    end
    if selected == "tk" then
        -- The summary covers only the rows the page shows, as the live card's does.
        local sample = sampleXP.hist
        sample.n = math.min(SAMPLE_LEVELS, tonumber(X.Get("xpTickerHistoryRows")) or 0)
        X.SummarizeHistory(sample, X.Get("xpTickerShowCurrent") == true)
        X.TickerView(sampleXP, X.Get, cardOut)
        w.frame.dirty = true
        X.DrawCard(w.frame, X.Get, cardOut)
    elseif selected == "xp" then
        X.XPView(sampleXP, X.Get, xpOut)
        -- The sample shows Ready Glow while its switch is on, ready or not.
        xpOut.readyEnd = X.Get("xpReadyGlow") == true and xpOut.questEnd or nil
        X.Draw(w, X.Get, xpOut)
    else
        X.FactionView(SampleFaction(), X.Get, fbOut)
        X.Draw(w, X.Get, fbOut)
    end
    w.frame:Show()
    -- The draw above ran while the bar could be hidden.
    if selected == "xp" then X.SyncReady(w, X.Get, xpOut, w.bw, w.bh) end
    SyncHits(selected)
    local bw, bh = w.frame.kuiW, w.frame.kuiH
    if selected ~= "tk" then
        bw = tonumber(X.Get(selected .. "Width")) or 100
        bh = tonumber(X.Get(selected .. "Height")) or 10
    end
    w.frame:ClearAllPoints()
    w.frame:SetPoint("TOP", content, "TOP", 0, -(w.above or 0))
    local h = (w.above or 0) + bh + (w.below or 0)
    if selected == "tk" then bw, h = LayoutStack(w, bw, h) end
    local scale = (bw > availW) and (availW / bw) or 1
    content:SetScale(scale)
    content:SetSize(math.max(1, bw), math.max(1, h))
    wrap:SetSize(math.max(1, bw * scale), math.max(1, h * scale))
    stage:SetSize(math.max(1, availW), h * scale + STAGE_PAD_Y * 2)
    return PickerRoom() + h * scale + STAGE_PAD_Y * 2
end

function X.BuildPreviewHeader(parent, width)
    if not parent then return 0 end
    availW = math.max(1, (width or 1) - Pad() * 2)
    wrap = wrap or CreateFrame("Frame", nil, parent)
    wrap:SetParent(parent)
    if not stage then
        stage = CreateFrame("Frame", nil, parent)
        if EllesmereUI and EllesmereUI.SolidTex then
            stage.fillTex = EllesmereUI.SolidTex(stage, "BACKGROUND", 0, 0, 0, 0.22)
            if stage.fillTex then stage.fillTex:SetAllPoints() end
        end
        if EllesmereUI and EllesmereUI.MakeBorder and EllesmereUI.BORDER_R and EllesmereUI.BORDER_G
            and EllesmereUI.BORDER_B and EllesmereUI.PanelPP then
            EllesmereUI.MakeBorder(stage, EllesmereUI.BORDER_R, EllesmereUI.BORDER_G, EllesmereUI.BORDER_B, 0.35,
                EllesmereUI.PanelPP)
        end
    end
    stage:SetParent(parent)
    stage:SetFrameLevel(math.max(0, (Plain(wrap:GetFrameLevel()) or 1) - 1))
    MountPicker(parent)
    stage:ClearAllPoints()
    stage:SetPoint("TOP", parent, "TOP", 0, -PickerRoom())
    stage:Show()
    wrap:ClearAllPoints()
    wrap:SetPoint("TOP", stage, "TOP", 0, -STAGE_PAD_Y)
    wrap:Show()
    if not content then
        content = CreateFrame("Frame", nil, wrap)
        content:SetScript("OnHide", function()
            for _, w in pairs(widgets) do X.StopEffects(w) end
        end)
    end
    content:SetParent(wrap)
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
    content:Show()
    widgets.xp = widgets.xp or X.NewWidget(content, "xp")
    widgets.fb = widgets.fb or X.NewWidget(content, "fb")
    BuildHits("xp")
    BuildHits("fb")
    return Layout()
end

-- Redraws from current settings. Returns at once unless the preview is on
-- screen: the accent callback reaches here from any page, and the shared
-- header area may belong to another page.
function X.PreviewRefresh()
    if not content or Plain(content:IsVisible()) ~= true then return end
    local h = Layout()
    if EllesmereUI and EllesmereUI.UpdateContentHeaderHeight then
        EllesmereUI:UpdateContentHeaderHeight(h)
    end
end

-- A cached revisit only redraws; it never rebuilds the widgets.
function X.PreviewRestore()
    X.PreviewRefresh()
end

-- Plays a moment on the selected bar's sample. Play Gain also runs the
-- profession fill's own pass.
function X.PreviewPlay(moment)
    local w = content and widgets[selected]
    if not w or selected == "tk" or Plain(content:IsVisible()) ~= true then return end
    if moment == "level" then
        X.PlayLevelEffect(w, X.Get)
        return
    end
    local data = selected == "xp" and xpOut or fbOut
    local to = data.fill or 0
    X.PlayGainEffect(w, X.Get, data, math.max(0, to - SAMPLE_SPAN), to, selected == "xp" and SAMPLE_XP or SAMPLE_REP)
    X.PlayGain(w)
end
