-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/TopBar/Preview.lua                                ║
-- ║  Purpose: The live arrangement preview pinned above the Top   ║
-- ║           Bar options page, and its drag-to-arrange.          ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

local previewWrap        -- UNSCALED. Carries the CONTENT_PAD inset. See below.
local previewFrame       -- module-local. NEVER EllesmereUI._contentHeaderPreview.
local hintText            -- parented to the HEADER frame, never previewFrame or
                          -- previewWrap. Built once in BuildPreviewHeader.
local availW              -- usable width, cached from the last BuildPreviewHeader
                          -- call so a settings-driven PreviewRefresh (which gets
                          -- no width argument) can still fit against it.

-- The builder is handed rightW (1005), unpadded. Inset by CONTENT_PAD on each
-- side so the preview lines up with the padded content below it, exactly as the
-- CDM insets its own preview wrapper (EUI_CooldownManager_Options.lua:13952-13965).
-- The `or 10` fallback is the CDM's own idiom, not a guess.
--
-- TWO FRAMES, and the split is load-bearing. A SetPoint offset is expressed in
-- the anchored frame's OWN scaled space, so an inset of 45 on a frame later
-- scaled to 0.65 renders at about 29 px and the preview drifts 16 px left of the
-- controls below it -- silently, because nothing clips. The CDM solves it the
-- same way: an unscaled `wrapper` anchored at PAD holding a separately scaled
-- `pf` (EUI_CooldownManager_Options.lua:13962-13975 -- read to the END of that
-- range: pf is created parented to `parent` at :13968 and only becomes the
-- wrapper's content at :13975 via sf:SetScrollChild(pf). KitnUI parents
-- previewFrame to previewWrap directly instead; it needs no scroll frame).
-- The same semantics are why
-- both ghost followers in the suite divide their offsets by their own scale
-- (:15049-15051; EllesmereUIBags.lua:3257-3261).
--
-- So: previewWrap owns the inset and is never scaled; previewFrame owns the
-- content and the fit scale, anchored at 0,0 inside the wrapper. NEVER call
-- SetScale on previewWrap, and NEVER give previewFrame a non-zero offset.
local function Pad()
    return (EllesmereUI and EllesmereUI.CONTENT_PAD) or 10
end

---------------------------------------------------------------------------------
-- Slot construction. Mirrors Bar.lua's spacing arithmetic; never calls it --
-- Bar.lua's own frames, EnsureCreated, CreateElementButton, LayoutSide and
-- LayoutPanels are off limits. Every slot is a plain, non-secure Button: the
-- preview lives inside an options window and must never own a secure frame.
---------------------------------------------------------------------------------

-- The same predicate LayoutSide uses (Bar.lua:456), so the preview and the
-- real bar can never disagree about what is shown.
local function Visible(id)
    local el = ns.TopBar.ById[id]
    if not el then return false end
    if ns.TopBar.IsOff(id) then return false end
    if el.requires and not el.requires() then return false end
    return true
end

-- Duplicates Bar.lua:99 rather than reading it: that local is off limits, and
-- Readouts.lua already duplicates AccentRGB the same way for the same reason.
local BTN_PAD = 8

-- Duplicates Readouts.lua:71 (SizeClockButton's own CLOCK_PAD) the same way
-- BTN_PAD above duplicates Bar.lua:99 -- that local is off limits too.
local CLOCK_PAD = 6

-- Widest-case strings for the two readout slots (Step 2). The 12-hour form is
-- wider than the 24-hour one; the FPS string is the real readout's own layout
-- (Readouts.lua:158) with the colour escapes stripped -- they contribute no
-- width.
local CLOCK_STRING_24H = "23:59"
local CLOCK_STRING_12H = "12:59 PM"
local FPS_STRING       = "999 fps  999 ms"

-- Vertical gap between the icon row and the FPS text under the clock, and
-- between the preview and the hint line below it. Not part of any width/scale
-- arithmetic, so any reasonable constant is fine here.
local READOUT_GAP = 2
local HINT_GAP    = 6

-- Reused across every PreviewRefresh, keyed by element id, so Task 3's drag
-- scripts (attached to the Button itself) survive a settings-driven redraw.
-- This must never destroy and recreate the frame an id already owns.
local slotPool = {}

local function GetSlot(id)
    local slot = slotPool[id]
    if not slot then
        slot = CreateFrame("Button", nil, previewFrame)
        slotPool[id] = slot
    end
    slot:SetParent(previewFrame)
    return slot
end

-- Lays out one side panel's launcher slots left to right from `startX`,
-- mirroring LayoutSide's own arithmetic (Bar.lua:451-473) without calling it.
-- Returns the panel's own content width (0 when nothing in it is visible).
-- rowH is the icon row's shared height (Fix 4): every slot in the row
-- anchors so its own vertical centre sits on the row's centreline, matching
-- Bar.lua's LayoutSide/LayoutPanels, which hang every button and every
-- side panel off a shared y (:459, :489-493).
local function LayoutLauncherPanel(order, panel, startX, size, spacing, rowH)
    local x = 0
    local yOff = -(rowH - size) / 2
    for _, id in ipairs(order) do
        if Visible(id) then
            local el = ns.TopBar.ById[id]
            local slot = GetSlot(id)
            if not slot._icon then
                local icon = slot:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("CENTER")
                slot._icon = icon
            end
            if el.icon then slot._icon:SetTexture(el.icon) end
            slot:SetSize(size, size)
            -- The real bar sizes the button to size+BTN_PAD but the icon
            -- texture to size alone (Bar.lua:409-410); `size` here already
            -- includes BTN_PAD (Layout() passes iconSize), so the icon
            -- texture is inset by BTN_PAD inside the slot, matching it.
            local iconDim = size - BTN_PAD
            if iconDim < 0 then iconDim = 0 end
            slot._icon:SetSize(iconDim, iconDim)
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", startX + x, yOff)
            -- Preview-frame-local coordinates. Task 3's hit testing reads
            -- these, exactly as EUI_CooldownManager_Options.lua:14315-14349 does.
            slot._baseX, slot._baseY = startX + x, yOff
            slot._id, slot._panel = id, panel
            slot:Show()
            x = x + size + spacing
        end
    end
    if x > 0 then x = x - spacing end
    return x
end

-- The centre column: just the clock, sized from its own measured text so the
-- preview never has to read the real bar's clock button (Step 2) -- that
-- button lives on UIParent, may not exist yet, and may be hidden.
--
-- Split into measure/position (Fix 4): the icon row's shared vertical
-- centreline needs the clock's height known BEFORE any slot in the row is
-- anchored, so this only creates the FontString, sets its font/text, and
-- measures it -- no positioning here.
local function MeasureClock(clockSize)
    local slot = GetSlot("clock")
    if not slot._text then
        local text = slot:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER")
        slot._text = text
    end
    slot._text:SetFont(STANDARD_TEXT_FONT, clockSize, "OUTLINE")
    local sample = CLOCK_STRING_24H
    if not ns.TopBar.Get("tbUse24h", true) then sample = CLOCK_STRING_12H end
    slot._text:SetText(sample)

    local w = slot._text:GetStringWidth() or 0
    local h = slot._text:GetStringHeight() or 0
    if w <= 0 then w = clockSize end
    if h <= 0 then h = clockSize end
    return slot, w, h
end

-- Sizes and anchors the clock slot from its already-measured text metrics
-- (w, h are the PADDED slot dimensions -- CLOCK_PAD already applied by the
-- caller, matching SizeClockButton, Readouts.lua:88-89: CLOCK_PAD on both
-- sides horizontally, half that vertically).
local function PositionClock(slot, startX, yOff, w, h)
    slot:SetSize(w, h)
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", startX, yOff)
    -- Never draggable, so no _baseX/_baseY -- Step 1 scopes those to
    -- draggable slots only.
    slot._id, slot._panel = "clock", "centre"
    slot:Show()
end

-- The FPS readout: text under the clock, no drag scripts, and read from the
-- registry by id rather than from any order array -- it has no panel field
-- and is never in tbOrder (Elements.lua:1057-1060).
local function LayoutFps(centerX, topY, sysSize)
    local slot = GetSlot("fps")
    if not slot._text then
        local text = slot:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER")
        slot._text = text
    end
    slot._text:SetFont(STANDARD_TEXT_FONT, sysSize, "OUTLINE")
    slot._text:SetText(FPS_STRING)

    local w = slot._text:GetStringWidth() or 0
    local h = slot._text:GetStringHeight() or 0
    if w <= 0 then w = sysSize end
    if h <= 0 then h = sysSize end

    slot:SetSize(w, h)
    slot:ClearAllPoints()
    slot:SetPoint("TOP", previewFrame, "TOPLEFT", centerX, -topY)
    slot._id = "fps"
    slot:Show()
    return h
end

-- The whole layout pass: slot rows, the fit scale, and the hint line. Returns
-- the total header height in the PARENT's coordinate space (Step 5). Shared
-- by BuildPreviewHeader (the cold mount) and PreviewRefresh (every later
-- settings-driven redraw) so there is exactly one place that computes it.
local function Layout()
    for _, slot in pairs(slotPool) do slot:Hide() end

    local iconSize  = ns.TopBar.Get("tbIconSize", 20) + BTN_PAD
    local spacing   = ns.TopBar.Get("tbSpacing", 14)
    local clockSize = ns.TopBar.Get("tbClockSize", 24)
    local sysSize   = ns.TopBar.Get("tbSysSize", 11)
    local order     = ns.TopBar.Order()

    -- Fix 4: the clock is measured -- never positioned -- before either
    -- launcher panel, because the row's shared vertical centreline (rowH,
    -- below) needs every slot's height known before any slot is anchored.
    local clockSlot, clockW, clockH = nil, 0, 0
    if Visible("clock") then
        local textW, textH
        clockSlot, textW, textH = MeasureClock(clockSize)
        clockW, clockH = textW + CLOCK_PAD * 2, textH + CLOCK_PAD
    end

    local iconRowH = math.max(iconSize, clockH)

    local leftW = LayoutLauncherPanel(order.left, "left", 0, iconSize, spacing, iconRowH)

    if clockSlot then
        PositionClock(clockSlot, leftW + spacing, -(iconRowH - clockH) / 2, clockW, clockH)
    end

    local rightW = LayoutLauncherPanel(order.right, "right",
        leftW + spacing + clockW + spacing, iconSize, spacing, iconRowH)

    local fpsH = 0
    if Visible("fps") then
        fpsH = LayoutFps(leftW + spacing + clockW / 2, iconRowH + READOUT_GAP, sysSize)
    end

    local unscaledH = iconRowH
    if fpsH > 0 then unscaledH = unscaledH + READOUT_GAP + fpsH end

    -- Step 3: fit to width when it overflows, with no floor. contentW is the
    -- laid-out width from above. Default it BEFORE any use: the division
    -- below is guarded by its own `if`, but SetSize is not, and
    -- SetSize(nil, h) is a hard Lua error rather than a no-op.
    local laidOutWidth = leftW + spacing + clockW + spacing + rightW
    local contentW = laidOutWidth or 0
    local scale = 1
    if contentW > 0 and contentW > availW then
        scale = availW / contentW
    end
    previewFrame:SetScale(scale)                        -- the CONTENT frame only
    previewFrame:SetSize(math.max(1, contentW), unscaledH)
    previewWrap:SetSize(availW, unscaledH * scale)

    -- Step 5: the scaled preview's own contribution, plus the hint line's own
    -- height and gap, both UNSCALED -- the hint is parented to the header
    -- frame (Step 4) and never scaled.
    local hintH = 0
    if hintText then hintH = hintText:GetStringHeight() or 0 end
    return unscaledH * scale + HINT_GAP + hintH
end

-- No _prebuilding guard here, deliberately. EllesmereUI's hidden pre-build pass
-- stubs every content-header method to a no-op for the duration of each call
-- (EllesmereUI_GlobalSearch.lua:328-332, :584-592) and calls buildPage directly
-- rather than SelectPage (:544), so this function is unreachable during the
-- pass. A guard would be dead code.
function ns.TopBar.BuildPreviewHeader(parent, width)
    if not parent then return 0 end
    local pad = Pad()
    availW = math.max(1, (width or 1) - pad * 2)

    -- previewWrap carries the inset and is NEVER scaled.
    previewWrap = previewWrap or CreateFrame("Frame", nil, parent)
    previewWrap:SetParent(parent)
    previewWrap:ClearAllPoints()
    previewWrap:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, 0)
    previewWrap:Show()

    -- previewFrame is the scaled child. Its offset inside the wrapper is 0,0,
    -- and zero is the one offset a scale cannot distort.
    previewFrame = previewFrame or CreateFrame("Frame", nil, previewWrap)
    previewFrame:SetParent(previewWrap)
    previewFrame:ClearAllPoints()
    previewFrame:SetPoint("TOPLEFT", previewWrap, "TOPLEFT", 0, 0)
    previewFrame:Show()

    -- Step 4: the hint line, parented to the HEADER frame -- not previewFrame,
    -- not previewWrap -- so it never shrinks with the fit scale and has no
    -- business inside the frame Task 3's drag maths converts cursor
    -- coordinates against. Anchored off previewWrap's own BOTTOMLEFT (never
    -- scaled) so the gap below the preview stays a constant pixel count
    -- regardless of the fit scale, and x-anchored at 0 relative to it, which
    -- is already Pad() relative to `parent`.
    if not hintText then
        hintText = parent:CreateFontString(nil, "OVERLAY")
        hintText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        hintText:SetJustifyH("LEFT")
        hintText:SetTextColor(0.6, 0.6, 0.6, 1)
        hintText:SetText("Drag an icon to move it. Drag it across the gap to send it to the other side.")
    end
    hintText:SetParent(parent)
    hintText:ClearAllPoints()
    hintText:SetPoint("TOPLEFT", previewWrap, "BOTTOMLEFT", 0, -HINT_GAP)
    hintText:Show()

    return Layout()
end

-- Rebuilds the slot rows from current settings. Options.lua's slider and
-- toggle setters call this directly after Apply() (Step 6); Tasks 3 and 4
-- call it after every drop. Must return immediately when previewFrame is
-- nil: a host without EllesmereUI.SetContentHeader builds the page and fires
-- its setters while the header never mounted, so this function exists and
-- the frame does not.
function ns.TopBar.PreviewRefresh()
    if not previewFrame then return end
    local h = Layout()
    if EllesmereUI and EllesmereUI.UpdateContentHeaderHeight then
        EllesmereUI:UpdateContentHeaderHeight(h)
    end
end

-- Revisiting a page does NOT rebuild it: SelectPage takes a fast path
-- (EllesmereUI.lua:10714-10743) that only re-runs refreshList closures and then
-- calls this. Task 3's drag scripts live on frames that survive the cache, so
-- this only has to redraw; it must not rebuild the slots.
function ns.TopBar.PreviewRestore()
    ns.TopBar.PreviewRefresh()
end
