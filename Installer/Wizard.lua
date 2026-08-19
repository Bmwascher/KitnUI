-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Wizard.lua                                                  ║
-- ║  Purpose: Installer wizard shell: the EllesmereUI-skinned    ║
-- ║           frame, sidebar step rail, progress bar, buttons,   ║
-- ║           and the paging engine.                             ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

---------------------------------------------------------------------------------
-- Skinned with EllesmereUI's public builders: SolidTex, MakeBorder, MakeFont,
-- MakeStyledButton, GetAccentColor, PanelPP. Installer.lua's page functions
-- render onto ns.Wizard.frame (SubTitle / Desc1..3 / Option1..4) and drive
-- paging through Queue / SetPage / SetOption.
---------------------------------------------------------------------------------

ns.Wizard = ns.Wizard or {}
local W = ns.Wizard

local PANEL_BG   = { 0.04, 0.02, 0.04 }        -- near-black base (matches the KitnUI art)
local PANEL_GRAD = { 0.12, 0.01, 0.06 }        -- faint pink glow for the top of the gradient
local BORDER_COL = { 0.69, 0.55, 1.0, 0.20 }   -- faint purple-white 1px border
-- KitnUI brand accent (|cffFF008C) used for highlights instead of EllesmereUI's
-- own accent, so the installer reads as KitnUI's rather than EUI's purple.
local KITN_PINK = { 1, 0, 0.549 }

-- Exported because the Nameplates page defaults its target arrow colour to the
-- same brand accent, and two copies of a brand colour drift. POSITIONAL, because
-- SetColorTexture takes three arguments; anything reading it into a keyed colour
-- table has to convert.
ns.KITN_PINK = KITN_PINK

-- Baked installer background art: a ~1.36:1 pink panel inside a black margin,
-- shipped as an uncompressed TGA. ART_CROP drops the margin so the panel fills
-- the frame with no stretch, and PANEL_W/PANEL_H match that aspect. Retune both
-- together if the art changes.
local ART_PATH = "Interface\\AddOns\\KitnUI\\Media\\Background\\KitnUI-EUI-Background.tga"
local ART_CROP = { 0.065, 0.940, 0.099, 0.916 }  -- left, right, top, bottom (0..1)
local PANEL_W, PANEL_H = 760, 560                 -- 1.357:1, matches the cropped panel
local TITLE_ICON = "Interface\\AddOns\\KitnUI\\Media\\Textures\\KitnUI.tga"  -- KitnUI cat logo (512x512)

-- Layout: the baked art already draws the sidebar column, logo, header band and
-- close box, so overlays are positioned INTO those regions rather than redrawn.
local SIDEBAR_W = 176                   -- baked sidebar width (art divider @ x~178)
local CONTENT_X = SIDEBAR_W + 24        -- left edge of the content column
local STEP_DONE = { 0.43, 0.75, 0.61 }  -- green check for completed steps
local OPTION_W  = 165                   -- default action-button width (CDM shrinks to fit)
local STEP_MAXW = 148                   -- max step-label width before the baked divider

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

local function skin(frame)
    -- base fill (BACKGROUND -2)
    local base = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    base:SetColorTexture(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 0.98)
    base:SetAllPoints()
    -- subtle top->bottom purple gradient (BACKGROUND -1)
    local grad = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    grad:SetColorTexture(1, 1, 1, 1)
    grad:SetAllPoints()
    if grad.SetGradient and CreateColor then
        grad:SetGradient("VERTICAL",
            CreateColor(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 0.0),
            CreateColor(PANEL_GRAD[1], PANEL_GRAD[2], PANEL_GRAD[3], 0.85))
    else
        grad:Hide()
    end
    -- KitnUI installer background art (baked pink panel + cat), BACKGROUND 0 so it
    -- sits over the fallback fill/gradient. Texcoords crop the source's outer black
    -- margin; the frame aspect matches the cropped panel so nothing stretches.
    frame.artLayer = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    frame.artLayer:SetAllPoints()
    frame.artLayer:SetTexture(ART_PATH)
    if frame.artLayer:GetTexture() then
        frame.artLayer:SetTexCoord(ART_CROP[1], ART_CROP[2], ART_CROP[3], ART_CROP[4])
    else
        frame.artLayer:Hide()  -- art failed to load; fall back to the drawn fill/gradient
    end
    -- border
    if EllesmereUI.MakeBorder then
        EllesmereUI.MakeBorder(frame, BORDER_COL[1], BORDER_COL[2], BORDER_COL[3], BORDER_COL[4], EllesmereUI.PanelPP)
    end
    return base
end

---------------------------------------------------------------------------------
-- Build the root frame once (idempotent).
---------------------------------------------------------------------------------

function W:Build()
    if W.frame then return W.frame end
    if not euiReady() then
        print((ns.title or "KitnUI") .. ": EllesmereUI UI is not ready.")
        return nil
    end

    local f = CreateFrame("Frame", "KitnUIWizard", UIParent)
    f:SetSize(PANEL_W, PANEL_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f)

    -- Esc closes the wizard (standard modal behavior); named frame required.
    tinsert(UISpecialFrames, "KitnUIWizard")

    -- Title: left-aligned in the content column, inside the baked header band.
    f.SubTitle = EllesmereUI.MakeFont(f, 24, "", 1, 1, 1)
    f.SubTitle:SetAlpha(0.98)
    f.SubTitle:SetPoint("TOPLEFT", CONTENT_X, -30)
    f.SubTitle:SetJustifyH("LEFT")

    -- Optional brand icon in the header band, left of the title. Hidden unless a
    -- page opts in via W:SetTitleIcon (KitnUI/Welcome/Finish pages).
    f.titleIcon = f:CreateTexture(nil, "ARTWORK")
    f.titleIcon:SetSize(34, 34)
    f.titleIcon:SetPoint("TOPLEFT", CONTENT_X, -25)
    f.titleIcon:Hide()

    -- Content text (page functions write these), left-aligned in the content column.
    local contentW = PANEL_W - CONTENT_X - 40
    f.Desc1 = EllesmereUI.MakeFont(f, 16, "", 1, 1, 1, 0.92)
    f.Desc1:SetPoint("TOPLEFT", CONTENT_X, -116)  -- clears the faint baked rule @ frameY_top~103
    f.Desc1:SetWidth(contentW)
    f.Desc1:SetJustifyH("LEFT")
    f.Desc1:SetSpacing(3)
    f.Desc2 = EllesmereUI.MakeFont(f, 16, "", 1, 1, 1, 0.85)
    f.Desc2:SetPoint("TOPLEFT", f.Desc1, "BOTTOMLEFT", 0, -14)
    f.Desc2:SetWidth(contentW)
    f.Desc2:SetJustifyH("LEFT")
    f.Desc2:SetSpacing(3)
    f.Desc3 = EllesmereUI.MakeFont(f, 15, "", 1, 1, 1, 0.8)
    f.Desc3:SetPoint("TOPLEFT", f.Desc2, "BOTTOMLEFT", 0, -10)
    f.Desc3:SetWidth(contentW)
    f.Desc3:SetJustifyH("LEFT")
    f.Desc3:SetSpacing(3)

    -- "Profile status" separator: a thin rule + small caption that addon pages show
    -- above the Status/Version block (via W:ShowStatusHeader) to set it apart from the
    -- description. Hidden by default; other pages leave it off (W:HideStatusHeader).
    f.detailRule = f:CreateTexture(nil, "ARTWORK")
    f.detailRule:SetColorTexture(1, 1, 1, 0.12)
    f.detailRule:SetHeight(1)
    f.detailRule:Hide()
    f.detailHeader = EllesmereUI.MakeFont(f, 11, "", 1, 1, 1, 0.5)  -- muted caption (pink read too hot here)
    f.detailHeader:SetJustifyH("LEFT")
    f.detailHeader:Hide()

    -- Option/action buttons. Label lives in _lbl; bg/border in _bg/_brd (for
    -- SetButtonVariant); click routes through _onClick.
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(OPTION_W, 34)
        local bg, brd, lbl = EllesmereUI.MakeStyledButton(b, "", 13, BTN_COLOURS, function()
            if b._onClick then b._onClick() end
        end)
        b._bg, b._brd, b._lbl = bg, brd, lbl
        b:Hide()
        f["Option" .. i] = b
    end
    -- Action row: left-aligned in the content column, above the progress + nav rows.
    f.Option1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CONTENT_X, 88)
    f.Option2:SetPoint("LEFT", f.Option1, "RIGHT", 10, 0)
    f.Option3:SetPoint("LEFT", f.Option2, "RIGHT", 10, 0)
    f.Option4:SetPoint("LEFT", f.Option3, "RIGHT", 10, 0)

    -- Small hint above the action row for pages presenting a mutually-exclusive
    -- choice (e.g. EllesmereUI color mode); hidden unless a page sets it.
    f.optionHint = EllesmereUI.MakeFont(f, 12, "", 1, 1, 1, 0.5)
    f.optionHint:SetJustifyH("LEFT")
    f.optionHint:Hide()

    -- Step rail overlaid on the baked sidebar column (below the baked logo block).
    f.stepRail = CreateFrame("Frame", nil, f)
    f.stepRail:SetPoint("TOPLEFT", 6, -76)
    f.stepRail:SetSize(SIDEBAR_W - 10, 400)
    f.stepLabels = {}

    -- Version, in the baked sidebar footer. Two corrections to what
    -- GetAddOnMetadata hands back, because the label below supplies the word
    -- "Version" itself.
    --
    -- Packaged: the packager substitutes the git TAG, which carries a leading
    -- "v", so the line would otherwise read "Version v2.0.1".
    --
    -- Unpackaged checkout: the .toc still holds the literal @project-version@
    -- token. The stand-in used to be a hand-written number, which went stale the
    -- first release nobody remembered to edit it (it read 2.0 through all of
    -- 2.0.1). "dev" cannot go stale, and it also says plainly that this is not a
    -- shipped build.
    local ver = ns.version
    if not ver or ver:find("project") then
        ver = "dev"
    else
        ver = ver:gsub("^[vV]", "")
    end
    f.versionText = EllesmereUI.MakeFont(f, 13, "", 0.498, 0.839, 0.878, 0.95)  -- soft cyan
    f.versionText:SetPoint("BOTTOM", f, "BOTTOMLEFT", SIDEBAR_W / 2, 14)
    f.versionText:SetJustifyH("CENTER")
    f.versionText:SetText("Version " .. ver)
    -- faint divider above the version, across the sidebar footer
    local vdiv = f:CreateTexture(nil, "ARTWORK")
    vdiv:SetColorTexture(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 0.16)
    vdiv:SetHeight(1)
    vdiv:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 34)
    vdiv:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", SIDEBAR_W - 20, 34)

    -- Next / Back nav buttons (quiet "ghost" by default; Next goes primary after a
    -- successful page action via the installer's handoff).
    f.Next = CreateFrame("Button", nil, f)
    f.Next:SetSize(140, 30)
    f.Next:SetPoint("BOTTOMRIGHT", -20, 4)  -- nudged so its visual (bordered) edge lines up with the bar
    f.Next._bg, f.Next._brd, f.Next._lbl =
        EllesmereUI.MakeStyledButton(f.Next, "Next", 14, BTN_COLOURS, function() W:SetPage((W.page or 1) + 1) end)
    f.Back = CreateFrame("Button", nil, f)
    f.Back:SetSize(140, 30)
    f.Back:SetPoint("BOTTOMLEFT", CONTENT_X, 4)  -- footer, below the baked divider (y38)
    f.Back._bg, f.Back._brd, f.Back._lbl =
        EllesmereUI.MakeStyledButton(f.Back, "Back", 14, BTN_COLOURS, function() W:SetPage((W.page or 1) - 1) end)
    W:SetButtonVariant(f.Next, "ghost")
    W:SetButtonVariant(f.Back, "ghost")

    -- Close: invisible hitbox over the baked X box (the art draws the glyph, which
    -- avoids the Expressway font's missing "x" glyph); a faint pink wash on hover.
    local close = CreateFrame("Button", nil, f)
    close:SetSize(26, 24)
    close:SetPoint("CENTER", f, "TOPRIGHT", -14, -14)  -- over the baked X box
    close:SetFrameLevel(f:GetFrameLevel() + 10)
    local hover = close:CreateTexture(nil, "ARTWORK")
    hover:SetColorTexture(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 0.22)
    hover:SetAllPoints()
    hover:Hide()
    close:SetScript("OnEnter", function() hover:Show() end)
    close:SetScript("OnLeave", function() hover:Hide() end)
    close:SetScript("OnClick", function() W:Hide() end)
    f.CloseButton = close

    -- Progress bar (track + pink fill) in the content column, above the nav row.
    local progTrack = CreateFrame("Frame", nil, f)
    progTrack:SetHeight(6)
    progTrack:SetPoint("BOTTOMLEFT", CONTENT_X, 50)   -- just above the baked divider
    progTrack:SetPoint("BOTTOMRIGHT", -22, 50)        -- 22px each side = centered in content area
    local trackBg = progTrack:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(1, 1, 1, 0.10)
    trackBg:SetAllPoints()
    f.progFill = progTrack:CreateTexture(nil, "ARTWORK")
    f.progFill:SetColorTexture(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 1)
    f.progFill:SetPoint("TOPLEFT", 0, 0)
    f.progFill:SetPoint("BOTTOMLEFT", 0, 0)
    f.progFill:SetWidth(1)
    f.progTrack = progTrack
    f.progLabel = EllesmereUI.MakeFont(f, 15, "", 1, 1, 1, 0.6)
    f.progLabel:SetPoint("BOTTOMRIGHT", progTrack, "TOPRIGHT", 0, 6)
    f.progLabel:SetJustifyH("RIGHT")

    f:Hide()
    W.frame = f
    return f
end

---------------------------------------------------------------------------------
-- Per-page option helpers used by Installer.lua page functions.
---------------------------------------------------------------------------------

function W:HideOptions()
    if not W.frame then return end
    for i = 1, 4 do
        local b = W.frame["Option" .. i]
        b:SetWidth(OPTION_W)  -- reset any per-page fit (e.g. CDM) back to default
        b:Hide()
    end
    -- reset the row's left anchor (a centered single-button page may have moved it)
    W.frame.Option1:ClearAllPoints()
    W.frame.Option1:SetPoint("BOTTOMLEFT", W.frame, "BOTTOMLEFT", CONTENT_X, 88)
    W.frame.optionHint:Hide()
end

-- KitnUI brand icon in the header band, left of the title. show = display it and
-- shift the title right to make room; false/nil = hide + restore the default anchor.
function W:SetTitleIcon(show)
    if not W.frame then return end
    local f = W.frame
    if show then
        f.titleIcon:SetTexture(TITLE_ICON)
        if f.titleIcon:GetTexture() then
            f.titleIcon:Show()
            f.SubTitle:ClearAllPoints()
            f.SubTitle:SetPoint("TOPLEFT", CONTENT_X + 42, -30)
            return
        end
    end
    f.titleIcon:Hide()
    f.SubTitle:ClearAllPoints()
    f.SubTitle:SetPoint("TOPLEFT", CONTENT_X, -30)
end

-- Small muted hint just above the action row (e.g. "Choose a color mode").
-- Cleared each page by HideOptions.
function W:SetOptionHint(text)
    if not W.frame then return end
    local h = W.frame.optionHint
    h:ClearAllPoints()
    h:SetPoint("BOTTOMLEFT", W.frame.Option1, "TOPLEFT", 0, 8)
    h:SetText(text)
    h:Show()
end

---------------------------------------------------------------------------------
-- Single-line text input, for a page that collects one value (the NSRT
-- nickname). Built once and reused, like the CDM page's persistent button: a
-- per-page frame would leak one EditBox per visit. SetPage hides it through
-- ResetExtras, so it can never bleed onto the next page.
--
-- opts: label, text, maxLetters, onCommit(value)
---------------------------------------------------------------------------------

function W:ShowInput(opts)
    if not W.frame then return end
    local f = W.frame
    opts = opts or {}

    if not f.inputBox then
        -- Same muted treatment as detailHeader, so the caption reads as part of
        -- the status block rather than as a second heading.
        f.inputCaption = EllesmereUI.MakeFont(f, 11, "", 1, 1, 1, 0.5)
        f.inputCaption:SetJustifyH("LEFT")

        local eb = CreateFrame("EditBox", nil, f)
        eb:SetSize(180, 26)
        eb:SetAutoFocus(false)
        eb:SetFont(ns.FONT or "Fonts\\FRIZQT__.TTF", 13, "")
        eb:SetTextInsets(8, 8, 0, 0)
        eb:SetTextColor(1, 1, 1, 0.95)
        local bg = eb:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(0, 0, 0, 0.40)  -- the "selectable" button fill, so the kit matches
        bg:SetAllPoints()
        if EllesmereUI.MakeBorder then
            EllesmereUI.MakeBorder(eb, 1, 1, 1, 0.14, EllesmereUI.PanelPP)
        end

        -- Enter commits by dropping focus, so there is exactly ONE commit path.
        eb:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
        -- Escape must not reach the frame: KitnUIWizard is in UISpecialFrames, so
        -- without this the whole wizard closes on a half-typed value. It also
        -- cancels, which is what an Escape means everywhere else.
        eb:SetScript("OnEscapePressed", function(box)
            box._cancelled = true
            box:ClearFocus()
        end)
        eb:SetScript("OnEditFocusLost", function(box)
            if box._cancelled then
                box._cancelled = nil
                box:SetText(box._committed or "")
                box:SetCursorPosition(0)
                return
            end
            -- An unchanged value is NOT committed. Focus is lost by clicking
            -- anywhere, including Next, so without this test merely visiting the
            -- page and clicking away would write - and for the nickname that
            -- turns "never set" into "deliberately cleared", which NSRT then
            -- broadcasts to the group.
            local value = box:GetText()
            if value == box._committed then return end
            if box._onCommit then box._onCommit(value) end
        end)
        f.inputBox = eb
    end

    local eb = f.inputBox
    eb._onCommit = opts.onCommit
    eb._cancelled = nil
    eb:SetMaxLetters(opts.maxLetters or 12)
    W:SetInputText(opts.text)

    -- Anchored off Desc3 rather than a fixed y, the same way ShowStatusHeader
    -- hangs off Desc1: the status block above it is a different height per page.
    f.inputCaption:ClearAllPoints()
    f.inputCaption:SetPoint("TOPLEFT", f.Desc3, "BOTTOMLEFT", 0, -18)
    f.inputCaption:SetText(opts.label or "")
    f.inputCaption:Show()
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", f.inputCaption, "BOTTOMLEFT", 0, -4)
    eb:Show()
end

-- Put a value back in the box. Pages call this after a commit with whatever the
-- target addon actually KEPT, so a truncated or refused value is visible rather
-- than assumed.
function W:SetInputText(text)
    local eb = W.frame and W.frame.inputBox
    if not eb then return end
    eb._committed = text or ""
    eb:SetText(eb._committed)
    eb:SetCursorPosition(0)
end

function W:HideInput()
    local f = W.frame
    if not (f and f.inputBox) then return end
    -- ClearFocus first, so leaving the page commits what was typed instead of
    -- discarding it. It is a no-op when the box was not focused.
    f.inputBox:ClearFocus()
    f.inputBox:Hide()
    f.inputCaption:Hide()
end

-- Show the "profile status" separator (thin rule + caption) above the status/
-- version block and re-anchor Desc2 below it. Addon pages call this; every page
-- starts with it hidden (SetPage resets via HideStatusHeader). Safe to call twice.
function W:ShowStatusHeader(text)
    if not W.frame then return end
    local f = W.frame
    f.detailRule:ClearAllPoints()
    f.detailRule:SetPoint("TOPLEFT", f.Desc1, "BOTTOMLEFT", 0, -16)
    f.detailRule:SetPoint("TOPRIGHT", f.Desc1, "BOTTOMRIGHT", 0, -16)
    f.detailRule:Show()
    f.detailHeader:ClearAllPoints()
    f.detailHeader:SetPoint("TOPLEFT", f.detailRule, "BOTTOMLEFT", 0, -9)
    f.detailHeader:SetText(text or "PROFILE STATUS")
    f.detailHeader:Show()
    f.Desc2:ClearAllPoints()
    f.Desc2:SetPoint("TOPLEFT", f.detailHeader, "BOTTOMLEFT", 0, -7)
end

-- Hide the separator and restore Desc2's default anchor (directly under Desc1).
function W:HideStatusHeader()
    if not W.frame then return end
    local f = W.frame
    f.detailRule:Hide()
    f.detailHeader:Hide()
    f.Desc2:ClearAllPoints()
    f.Desc2:SetPoint("TOPLEFT", f.Desc1, "BOTTOMLEFT", 0, -14)
end

-- Center the single action button in the content column (used by the Finish pages).
function W:CenterOption1()
    if not W.frame then return end
    local b = W.frame.Option1
    b:ClearAllPoints()
    b:SetPoint("BOTTOM", W.frame, "BOTTOMLEFT", CONTENT_X + (PANEL_W - CONTENT_X - 40) / 2, 88)
end

-- Size the first `count` action buttons so they fit one row in the content column;
-- returns the width used (so a caller can center something over the row).
function W:FitOptions(count)
    count = math.max(count, 1)
    local contentW = PANEL_W - CONTENT_X - 40
    local w = math.min(OPTION_W, math.floor((contentW - (count - 1) * 10) / count))
    for i = 1, count do
        if W.frame["Option" .. i] then W.frame["Option" .. i]:SetWidth(w) end
    end
    return w
end

function W:SetOption(i, text, onClick)
    local b = W.frame and W.frame["Option" .. i]
    if not b then return end
    if b._lbl then b._lbl:SetText(text) end
    b._onClick = onClick
    b:Show()
end

-- Style an external button (e.g. the CDM "Import All Specs") with KitnUI's look,
-- capturing its bg/border/label so SetButtonVariant can retint it.
function W:StyleButton(btn, text, fontSize, onClick)
    if not (EllesmereUI and EllesmereUI.MakeStyledButton) then return end
    local bg, brd, lbl = EllesmereUI.MakeStyledButton(btn, text, fontSize or 13, BTN_COLOURS, onClick)
    btn._bg, btn._brd, btn._lbl = bg, brd, lbl
    return bg, brd, lbl
end

-- Retint a styled button to one of four emphases (primary / selectable / done /
-- ghost). Operates on the textures MakeStyledButton created; safe to call twice.
function W:SetButtonVariant(btn, variant)
    if not (btn and btn._bg) then return end
    btn._variant = variant
    local P = KITN_PINK
    -- MakeStyledButton's 2nd return is a border OBJECT ({_frame, edges}), not a
    -- texture, so only recolor it when it exposes SetColorTexture; the bg fill +
    -- label color carry the emphasis regardless.
    local function setBrd(r, g, b, a)
        if btn._brd and btn._brd.SetColorTexture then btn._brd:SetColorTexture(r, g, b, a) end
    end
    if variant == "primary" then
        btn._bg:SetColorTexture(P[1], P[2], P[3], 1)
        setBrd(P[1], P[2], P[3], 1)
        if btn._lbl then btn._lbl:SetTextColor(0.06, 0.02, 0.04, 1) end
    elseif variant == "selectable" then
        btn._bg:SetColorTexture(0, 0, 0, 0.40)  -- dark fill so class colors stay legible
        setBrd(P[1], P[2], P[3], 0.55)
        if btn._lbl then btn._lbl:SetTextColor(1, 1, 1, 0.95) end
    elseif variant == "selected" then
        btn._bg:SetColorTexture(P[1], P[2], P[3], 0.22)  -- pink wash marks the active choice
        setBrd(P[1], P[2], P[3], 1)                       -- full pink border
        if btn._lbl then btn._lbl:SetTextColor(1, 1, 1, 1) end
    elseif variant == "done" then
        btn._bg:SetColorTexture(1, 1, 1, 0.04)
        setBrd(STEP_DONE[1], STEP_DONE[2], STEP_DONE[3], 0.5)
        if btn._lbl then btn._lbl:SetTextColor(STEP_DONE[1], STEP_DONE[2], STEP_DONE[3], 1) end
    else -- ghost
        btn._bg:SetColorTexture(1, 1, 1, 0.04)
        setBrd(1, 1, 1, 0.14)
        if btn._lbl then btn._lbl:SetTextColor(1, 1, 1, 0.82) end
    end
end

---------------------------------------------------------------------------------
-- Left step rail (accent highlights the active step).
---------------------------------------------------------------------------------

local function updateRail()
    local f = W.frame
    local titles = W.stepTitles or {}
    for i = 1, math.max(#titles, #f.stepLabels) do
        local row = f.stepLabels[i]
        if not row then
            -- Button so the step is clickable: jump straight to its page (handy for
            -- reinstalling a single profile). Row i always maps to page i.
            row = CreateFrame("Button", nil, f.stepRail)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 29)
            row:SetPoint("TOPRIGHT", 0, -(i - 1) * 29)
            row:SetHeight(27)
            -- pink row wash marks the current step (background, under everything)
            row.activeBg = row:CreateTexture(nil, "BACKGROUND")
            row.activeBg:SetColorTexture(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 0.10)
            row.activeBg:SetAllPoints()
            row.activeBg:Hide()
            -- faint white wash on hover (only when not the current step)
            row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
            row.hover:SetColorTexture(1, 1, 1, 0.06)
            row.hover:SetAllPoints()
            row.hover:Hide()
            -- pink left bar marks the current step
            row.bar = row:CreateTexture(nil, "ARTWORK")
            row.bar:SetColorTexture(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 1)
            row.bar:SetWidth(3)
            row.bar:SetPoint("TOPLEFT", 0, -2)
            row.bar:SetPoint("BOTTOMLEFT", 0, 2)
            -- green check marks completed steps (shares the gutter with the bar)
            row.chk = row:CreateTexture(nil, "ARTWORK")
            row.chk:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            row.chk:SetSize(12, 12)
            row.chk:SetPoint("LEFT", 3, 0)
            row.label = EllesmereUI.MakeFont(row, 13, "", 1, 1, 1)
            row.label:SetPoint("LEFT", 18, 0)
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self) if not self._isCurrent then self.hover:Show() end end)
            row:SetScript("OnLeave", function(self) self.hover:Hide() end)
            row:SetScript("OnClick", function() W:SetPage(i) end)
            f.stepLabels[i] = row
        end
        local title = titles[i]
        if title then
            row.label:SetText(title)
            -- keep the label left of the baked sidebar divider; only the longest
            -- step names need the smaller size.
            local fp, _, fl = row.label:GetFont()
            if fp then
                row.label:SetFont(fp, 13, fl)
                if row.label:GetStringWidth() > STEP_MAXW then
                    row.label:SetFont(fp, 11.5, fl)
                end
            end
            local isCurrent = (i == W.page)
            -- Completed check = an actually-imported addon (real profile lookup);
            -- non-addon steps (Welcome/Extras/Finish) complete once stepped past.
            local key = W.stepKeys and W.stepKeys[i]
            local isDone
            if isCurrent then
                isDone = false
            elseif key then
                isDone = ns.IsAddonImported and ns.IsAddonImported(key) or false
            else
                isDone = (i < (W.page or 1))
            end
            row._isCurrent = isCurrent
            row.bar:SetShown(isCurrent)
            row.activeBg:SetShown(isCurrent)
            row.chk:SetShown(isDone)
            if isCurrent then
                row.hover:Hide()  -- current row never shows the hover wash
                row.label:SetTextColor(1, 1, 1, 1)      -- bright white; the pink bar marks "current"
            elseif isDone then
                row.label:SetTextColor(1, 1, 1, 0.75)
            else
                row.label:SetTextColor(1, 1, 1, 0.38)
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------------
-- Paging engine.
---------------------------------------------------------------------------------

function W:Queue(data)
    W:Build()
    if not W.frame then return end
    W.pages = data.Pages or {}
    W.stepTitles = data.StepTitles or {}
    W.stepKeys = data.StepKeys or {}
    W.frame.SubTitle:SetText(data.Name or (ns.title or "KitnUI"))
    W:SetPage(1)
    W:Show()
end

function W:SetPage(n)
    if not (W.pages and W.pages[n]) then return end
    W.page = n
    W:HideOptions()
    if W.ResetExtras then W.ResetExtras() end
    W:HideStatusHeader()
    W:SetTitleIcon(false)
    W.frame.Desc1:SetText("")
    W.frame.Desc2:SetText("")
    W.frame.Desc3:SetText("")
    W.frame.Back:SetShown(n > 1)
    W.frame.Next:SetShown(n < #W.pages)
    updateRail()
    -- Progress bar + step counter.
    local total = #W.pages
    local frac = total > 0 and (n / total) or 0
    local tw = W.frame.progTrack and W.frame.progTrack:GetWidth() or 0
    if tw > 0 then W.frame.progFill:SetWidth(math.max(1, tw * frac)) end
    W.frame.progLabel:SetText(("Step %d of %d"):format(n, total))
    W.pages[n]()
end

function W:Show()
    if W.frame then W.frame:Show() end
end

function W:Hide()
    if W.frame then W.frame:Hide() end
end
