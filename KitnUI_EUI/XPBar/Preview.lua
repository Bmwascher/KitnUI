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
-- Overlay levels above a bar's base, over its top layer (the texts, at 12).
local HIT_FRAME, HIT_BODY, HIT_FILL, HIT_TEXT = 20, 21, 22, 30
-- How far the frame's overlay reaches past the bar.
local RING_OUT = 4

-- nil for a secret value, the value otherwise.
local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- wrap is UNSCALED and centered on the stage; content holds the fit scale at
-- offset 0,0 inside it. An offset on a scaled frame is in its own scaled
-- space, so the centering must not live on the scaled frame.
local stage, wrap, content, picker
local widgets = {}
local hits, hitsBuilt = { xp = {}, fb = {} }, {}
local availW = 1
-- The bar the page and the preview show, kept for the session only.
local selected = "xp"

local BAR_V = { xp = "XP Bar", fb = "Faction Bar" }
local BAR_O = { "xp", "fb" }

-- Every piece visible: quest XP, rested XP, both times and a rate, even on a
-- character at max level or with no rested XP.
local sampleXP = {
    level = 59, cur = 94410, max = 209800, quest = 31470, rested = 52450,
    atMax = false, xpOff = false, levelTime = 1200, elapsed = 3600, gained = 90000,
}
local sampleFaction = { cur = 6500, min = 0, max = 10000, isMax = false }
local xpOut, fbOut = {}, {}

local function Pad()
    return (EllesmereUI and EllesmereUI.CONTENT_PAD) or 10
end

local function SampleFaction()
    if ns.IS_FOREVER then
        local label = _G.FACTION_STANDING_LABEL5
        sampleFaction.kind, sampleFaction.name = "standard", "Watched Faction"
        sampleFaction.label, sampleFaction.reaction = type(label) == "string" and label or "Friendly", 5
    else
        sampleFaction.kind, sampleFaction.name = "friendship", "Delve Companion"
        sampleFaction.label, sampleFaction.reaction = "Level 20", nil
    end
    return sampleFaction
end

function X.SelectedBar()
    return selected
end

-- The page builds only the selected bar's sections, so a pick rebuilds it,
-- and the rebuilt page mounts this header again.
function X.SelectBar(kind)
    if (kind ~= "xp" and kind ~= "fb") or kind == selected then return end
    selected = kind
    if EllesmereUI and EllesmereUI.RefreshPage then
        pcall(EllesmereUI.RefreshPage, EllesmereUI, true)
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
        local ok, btn = pcall(EllesmereUI.BuildDropdownControl, parent, PICK_W, level, BAR_V, BAR_O,
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

-- Each part of a bar leads to the row that sets it. Made once per bar, the
-- first time the host has the overlay helper and the colors it draws with.
local function BuildHits(kind)
    local EUI, w = EllesmereUI, widgets[kind]
    if hitsBuilt[kind] or not w then return end
    if not (EUI and EUI.CreatePreviewHitOverlay and EUI.ELLESMERE_GREEN and EUI.PP and EUI.PP.CreateBorder) then
        return
    end
    hitsBuilt[kind] = true
    local ring = CreateFrame("Frame", nil, w.frame)
    ring:SetPoint("TOPLEFT", w.frame, "TOPLEFT", -RING_OUT, RING_OUT)
    ring:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", RING_OUT, -RING_OUT)
    AddHit(w, "frame", ring, false, HIT_FRAME)
    AddHit(w, "body", w.body, false, HIT_BODY)
    AddHit(w, "fill", w.fill, false, HIT_FILL)
    for key, fs in pairs(w.texts) do AddHit(w, key, fs, true, HIT_TEXT) end
end

-- The fill's overlay covers the filled part only; a text's shows only with
-- its text.
local function SyncHits(kind)
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

local function Layout()
    local w = content and widgets[selected]
    if not w then return 0 end
    local other = widgets[selected == "xp" and "fb" or "xp"]
    if other then other.frame:Hide() end
    if selected == "xp" then
        X.XPView(sampleXP, X.Get, xpOut)
        X.Draw(w, X.Get, xpOut)
    else
        X.FactionView(SampleFaction(), X.Get, fbOut)
        X.Draw(w, X.Get, fbOut)
    end
    w.frame:Show()
    SyncHits(selected)
    local bw = tonumber(X.Get(selected .. "Width")) or 100
    local bh = tonumber(X.Get(selected .. "Height")) or 10
    w.frame:ClearAllPoints()
    w.frame:SetPoint("TOP", content, "TOP", 0, -(w.above or 0))
    local h = (w.above or 0) + bh + (w.below or 0)
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
    content = content or CreateFrame("Frame", nil, wrap)
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
