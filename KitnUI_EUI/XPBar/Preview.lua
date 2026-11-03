-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Preview.lua                                ║
-- ║  Purpose: The live preview of both bars pinned above the XP  ║
-- ║           Bar options page, drawn with sample values.        ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar

local STAGE_PAD_Y = 14
local BAR_GAP = 18

-- nil for a secret value, the value otherwise.
local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- wrap is UNSCALED and centered on the stage; content holds the fit scale at
-- offset 0,0 inside it. An offset on a scaled frame is in its own scaled
-- space, so the centering must not live on the scaled frame.
local stage, wrap, content
local xpWidget, fbWidget
local availW = 1

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

local function Layout()
    if not (content and xpWidget and fbWidget) then return 0 end
    X.XPView(sampleXP, X.Get, xpOut)
    X.Draw(xpWidget, X.Get, xpOut)
    X.FactionView(SampleFaction(), X.Get, fbOut)
    X.Draw(fbWidget, X.Get, fbOut)
    local xh = tonumber(X.Get("xpHeight")) or 24
    local fh = tonumber(X.Get("fbHeight")) or 20
    local cw = math.max(tonumber(X.Get("xpWidth")) or 600, tonumber(X.Get("fbWidth")) or 400)
    local yPos = -(xpWidget.above or 0)
    xpWidget.frame:ClearAllPoints()
    xpWidget.frame:SetPoint("TOP", content, "TOP", 0, yPos)
    yPos = yPos - xh - (xpWidget.below or 0) - BAR_GAP - (fbWidget.above or 0)
    fbWidget.frame:ClearAllPoints()
    fbWidget.frame:SetPoint("TOP", content, "TOP", 0, yPos)
    local h = -yPos + fh + (fbWidget.below or 0)
    local scale = (cw > availW) and (availW / cw) or 1
    content:SetScale(scale)
    content:SetSize(math.max(1, cw), math.max(1, h))
    wrap:SetSize(math.max(1, cw * scale), math.max(1, h * scale))
    stage:SetSize(math.max(1, availW), h * scale + STAGE_PAD_Y * 2)
    return h * scale + STAGE_PAD_Y * 2
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
    stage:ClearAllPoints()
    stage:SetPoint("TOP", parent, "TOP", 0, 0)
    stage:Show()
    wrap:ClearAllPoints()
    wrap:SetPoint("TOP", stage, "TOP", 0, -STAGE_PAD_Y)
    wrap:Show()
    content = content or CreateFrame("Frame", nil, wrap)
    content:SetParent(wrap)
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
    content:Show()
    xpWidget = xpWidget or X.NewWidget(content, "xp")
    fbWidget = fbWidget or X.NewWidget(content, "fb")
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
