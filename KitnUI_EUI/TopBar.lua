-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab/TopBar.lua                                           ║
-- ║  Purpose: Reserved page. The top bar itself is a separate    ║
-- ║           project; this holds its slot in the tab.           ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

ns.EUIPages["Top Bar"] = function(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "TOP BAR", y);                                 y = y - h

    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(parent:GetWidth() - 40, 90)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)

    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(box)
    bg:SetColorTexture(0, 0, 0, 0.25)

    -- Both guarded: an older EllesmereUI may not carry either helper, and a
    -- missing border or font must cost decoration, not the page.
    local PP = EllesmereUI.PanelPP
    if PP and PP.CreateBorder then
        pcall(PP.CreateBorder, box, 1, 0, 0.55, 0.55, 1, "OVERLAY", 7)
    end

    local text = box:CreateFontString(nil, "OVERLAY")
    -- pcall's second return is the error message when the call fails, so the ok
    -- flag has to be read separately or a failure reaches SetFont as a font path.
    local font
    if EllesmereUI.GetFontPath then
        local ok, path = pcall(EllesmereUI.GetFontPath)
        if ok then font = path end
    end
    text:SetFont(type(font) == "string" and font or STANDARD_TEXT_FONT, 14)
    text:SetPoint("CENTER", box, "CENTER", 0, 0)
    text:SetText("Coming soon.")

    y = y - 110

    return math.abs(y)
end
