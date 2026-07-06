local _, ns = ...

------------------------------------------------------------
-- KitnUI installer wizard, skinned with EllesmereUI's public (ungated) builders:
--   EllesmereUI.SolidTex / MakeBorder / MakeFont / MakeStyledButton /
--   GetAccentColor / PanelPP.
-- Exposes a v1-PluginInstaller-compatible surface so Installer.lua page
-- functions render onto ns.Wizard.frame (SubTitle/Desc1..3/Option1..4) and
-- drive paging via Queue/SetPage/SetOption.
------------------------------------------------------------

ns.Wizard = ns.Wizard or {}
local W = ns.Wizard

local PANEL_BG = { 0.05, 0.07, 0.09 }
-- KitnUI brand accent (|cffFF008C) used for highlights instead of EllesmereUI's
-- own accent, so the installer reads as KitnUI's rather than EUI's purple.
local KITN_PINK = { 1, 0, 0.549 }

-- MakeStyledButton colour array: bg(1-4), bg-hover(5-8), border(9-12),
-- border-hover(13-16), text(17-20), text-hover(21-24). Values match EUI's own buttons.
local BTN_COLOURS = {
    0.061, 0.095, 0.120, 0.6,   0.061, 0.095, 0.120, 0.65,
    1, 1, 1, 0.3,               1, 1, 1, 0.45,
    1, 1, 1, 0.55,              1, 1, 1, 0.70,
}

local function euiReady()
    return _G.EllesmereUI and EllesmereUI.MakeBorder and EllesmereUI.MakeStyledButton
        and EllesmereUI.SolidTex and EllesmereUI.MakeFont
end

local function skin(frame, alpha)
    local bg = EllesmereUI.SolidTex(frame, "BACKGROUND", PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], alpha or 0.97)
    bg:SetAllPoints()
    EllesmereUI.MakeBorder(frame, 1, 1, 1, 0.15, EllesmereUI.PanelPP)
    return bg
end

------------------------------------------------------------
-- Build the root frame once (idempotent).
------------------------------------------------------------

function W:Build()
    if W.frame then return W.frame end
    if not euiReady() then
        print((ns.title or "KitnUI") .. ": EllesmereUI UI is not ready.")
        return nil
    end

    local f = CreateFrame("Frame", "KitnUIWizard", UIParent)
    f:SetSize(720, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f, 0.98)

    -- Title + accent underline
    f.SubTitle = EllesmereUI.MakeFont(f, 20, "", 1, 1, 1)
    f.SubTitle:SetAlpha(0.95)
    f.SubTitle:SetPoint("TOP", 0, -24)
    local underline = EllesmereUI.SolidTex(f, "ARTWORK", KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 0.95)
    underline:SetSize(220, 2)
    underline:SetPoint("TOP", f.SubTitle, "BOTTOM", 0, -6)

    -- Content text (page functions write these)
    f.Desc1 = EllesmereUI.MakeFont(f, 14, "", 1, 1, 1, 0.92)
    f.Desc1:SetPoint("TOP", 0, -84)
    f.Desc1:SetWidth(470)
    f.Desc1:SetJustifyH("CENTER")
    f.Desc2 = EllesmereUI.MakeFont(f, 13, "", 1, 1, 1, 0.82)
    f.Desc2:SetPoint("TOP", f.Desc1, "BOTTOM", 0, -14)
    f.Desc2:SetWidth(470)
    f.Desc2:SetJustifyH("CENTER")
    f.Desc3 = EllesmereUI.MakeFont(f, 12, "", 1, 1, 1, 0.7)
    f.Desc3:SetPoint("TOP", f.Desc2, "BOTTOM", 0, -10)
    f.Desc3:SetWidth(470)
    f.Desc3:SetJustifyH("CENTER")

    -- Option buttons (bottom row). Label lives in _lbl; click routes through _onClick.
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(150, 30)
        local _, _, lbl = EllesmereUI.MakeStyledButton(b, "", 13, BTN_COLOURS, function()
            if b._onClick then b._onClick() end
        end)
        b._lbl = lbl
        b:Hide()
        f["Option" .. i] = b
    end
    -- Option row sits above the Next/Back nav row so they never overlap.
    f.Option1:SetPoint("BOTTOM", f, "BOTTOM", -240, 70)
    f.Option2:SetPoint("BOTTOM", f, "BOTTOM", -80, 70)
    f.Option3:SetPoint("BOTTOM", f, "BOTTOM", 80, 70)
    f.Option4:SetPoint("BOTTOM", f, "BOTTOM", 240, 70)

    -- Step rail (left)
    f.stepRail = CreateFrame("Frame", nil, f)
    f.stepRail:SetPoint("TOPLEFT", 16, -70)
    f.stepRail:SetSize(170, 380)
    f.stepLabels = {}

    -- Next / Back
    f.Next = CreateFrame("Button", nil, f)
    f.Next:SetSize(96, 28)
    f.Next:SetPoint("BOTTOMRIGHT", -18, 26)
    EllesmereUI.MakeStyledButton(f.Next, "Next", 13, BTN_COLOURS, function() W:SetPage((W.page or 1) + 1) end)
    f.Back = CreateFrame("Button", nil, f)
    f.Back:SetSize(96, 28)
    f.Back:SetPoint("BOTTOMLEFT", 18, 26)
    EllesmereUI.MakeStyledButton(f.Back, "Back", 13, BTN_COLOURS, function() W:SetPage((W.page or 1) - 1) end)

    -- Close
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() W:Hide() end)

    f:Hide()
    W.frame = f
    return f
end

------------------------------------------------------------
-- Per-page option helpers used by Installer.lua page functions.
------------------------------------------------------------

function W:HideOptions()
    if not W.frame then return end
    for i = 1, 4 do W.frame["Option" .. i]:Hide() end
end

function W:SetOption(i, text, onClick)
    local b = W.frame and W.frame["Option" .. i]
    if not b then return end
    if b._lbl then b._lbl:SetText(text) end
    b._onClick = onClick
    b:Show()
end

-- Style an external button (e.g. the CDM "Import All Specs") with KitnUI's look.
function W:StyleButton(btn, text, fontSize, onClick)
    if not (EllesmereUI and EllesmereUI.MakeStyledButton) then return end
    return EllesmereUI.MakeStyledButton(btn, text, fontSize or 13, BTN_COLOURS, onClick)
end

------------------------------------------------------------
-- Left step rail (accent highlights the active step).
------------------------------------------------------------

local function updateRail()
    local f = W.frame
    local titles = W.stepTitles or {}
    for i = 1, math.max(#titles, #f.stepLabels) do
        local lbl = f.stepLabels[i]
        if not lbl then
            lbl = EllesmereUI.MakeFont(f.stepRail, 13, "", 1, 1, 1)
            lbl:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
            lbl:SetWidth(170)
            lbl:SetJustifyH("LEFT")
            f.stepLabels[i] = lbl
        end
        local title = titles[i]
        if title then
            lbl:SetText(title)
            if i == W.page then
                lbl:SetTextColor(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3])
                lbl:SetAlpha(1)
            else
                lbl:SetTextColor(1, 1, 1)
                lbl:SetAlpha(0.5)
            end
            lbl:Show()
        else
            lbl:Hide()
        end
    end
end

------------------------------------------------------------
-- Paging engine (Queue mirrors the v1 PluginInstaller data shape).
------------------------------------------------------------

function W:Queue(data)
    W:Build()
    if not W.frame then return end
    W.pages = data.Pages or {}
    W.stepTitles = data.StepTitles or {}
    W.frame.SubTitle:SetText(data.Name or (ns.title or "KitnUI"))
    W:SetPage(1)
    W:Show()
end

function W:SetPage(n)
    if not (W.pages and W.pages[n]) then return end
    W.page = n
    W:HideOptions()
    if W.ResetExtras then W.ResetExtras() end
    W.frame.Desc1:SetText("")
    W.frame.Desc2:SetText("")
    W.frame.Desc3:SetText("")
    W.frame.Back:SetShown(n > 1)
    W.frame.Next:SetShown(n < #W.pages)
    updateRail()
    W.pages[n]()
end

function W:Show()
    if W.frame then W.frame:Show() end
end

function W:Hide()
    if W.frame then W.frame:Hide() end
end
