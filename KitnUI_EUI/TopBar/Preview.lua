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

---------------------------------------------------------------------------------
-- Task 3: drag to reorder. Only launcher slots (LayoutLauncherPanel, below)
-- are wired -- the clock and fps slots never call WireDrag. Ported from the
-- house drag idiom (EUI_CooldownManager_Options.lua, EllesmereUIDataBars_
-- Options.lua:1236-1276), adapted for two side panels sharing one visual
-- row instead of one flat array: FindDragTarget below resolves a screen
-- position to a (panel, index) pair rather than a single array index, which
-- is what lets a drag cross the centre gap onto the other side.
---------------------------------------------------------------------------------

local DRAG_THRESHOLD = 3

-- Cached from the last Layout() pass so drag maths never has to re-derive the
-- row geometry mid-drag. iconSize/spacing/yOff are shared by both panels;
-- leftEndX/rightStartX are the boundary this file uses to decide which
-- panel's row a screen position belongs to -- Bar.lua's own layout has no
-- such boundary to read, because it never needs one.
local lastIconSize, lastSpacing, lastYOff
local lastLeftEndX, lastRightStartX

-- Drag state. Set by BeginDrag, read by FindDragTarget/ApplyDragFeedback/
-- FinishDrag, cleared by FinishDrag.
local dragSlot, dragId, dragPanel, dragFromIdx
local dragMode, dragTargetPanel, dragTargetIdx
local dragGhost
local insertLine

-- Visible-filtered copy of a stored order array, in the same left-to-right
-- order LayoutLauncherPanel renders it. Step 5's SpliceWithin is what folds
-- one of these back into the full stored array without losing a hidden entry.
local function VisibleIds(arr)
    local out = {}
    for _, id in ipairs(arr) do
        if Visible(id) then out[#out + 1] = id end
    end
    return out
end

-- A plain Frame on UIParent at TOOLTIP strata, one ARTWORK texture at alpha
-- 0.7, created once and reused. Must be on UIParent, not the preview: the
-- content header and the scroll frame both clip their children.
local function EnsureDragGhost()
    if dragGhost then return dragGhost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("TOOLTIP")
    g:SetAlpha(0.7)
    local tex = g:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    g._icon = tex
    g:Hide()
    dragGhost = g
    return g
end

local function EnsureInsertLine()
    if insertLine then return insertLine end
    insertLine = previewFrame:CreateTexture(nil, "OVERLAY")
    insertLine:SetWidth(2)
    insertLine:Hide()
    return insertLine
end

-- Snaps every draggable slot back to its Layout()-assigned position and
-- hides the insert line. Called before every feedback recompute and once
-- more on drop, so a cancelled or completed drag never leaves a slot sitting
-- at a slide offset.
local function ClearDragFeedback()
    if insertLine then insertLine:Hide() end
    for _, slot in pairs(slotPool) do
        if slot._baseX then
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", slot._baseX, slot._baseY)
        end
    end
end

-- Converts a cursor position into previewFrame-local units through effective
-- scales, exactly as EUI_CooldownManager_Options.lua:14306-14313 does, then
-- resolves it to a (mode, panel, index) drop target. cx, cy are already
-- divided by UIParent's own effective scale by the caller (the drag ticker,
-- below), matching that reference's own calling convention.
--
-- Unlike the reference's single flat array, this bar has two panels
-- separated by the clock, so the panel has to be chosen first: whichever
-- side of the gap's midpoint the cursor falls on (leftEndX/rightStartX,
-- cached from Layout()). Only then does the per-panel swap/insert zone scan
-- run, scoped to that one panel's own visible slots -- which is what makes a
-- drop in the middle of the clock gap resolve to "end of the nearer panel"
-- rather than the reference's own dead-zone fallback of appending past the
-- last slot in the whole row, which would be wrong here: the two panels are
-- not one contiguous row of evenly spaced slots the way a single CDM bar is.
local function FindDragTarget(cx, cy)
    if not previewFrame then return nil end
    local pfLeft, pfTop = previewFrame:GetLeft(), previewFrame:GetTop()
    if not (pfLeft and pfTop) then return nil end

    local pfES = previewFrame:GetEffectiveScale()
    local uiES = UIParent:GetEffectiveScale()
    local rawCX = cx * uiES
    local rawCY = cy * uiES
    local rawPfL = pfLeft * pfES
    local rawPfT = pfTop * pfES
    local localX = (rawCX - rawPfL) / pfES
    local localY = -((rawPfT - rawCY) / pfES)

    local size = lastIconSize
    local yOff = lastYOff
    if not (size and yOff) then return nil end
    if localY > yOff + size * 0.5 or localY < yOff - size * 1.5 then return nil end

    local leftEndX = lastLeftEndX or 0
    local rightStartX = lastRightStartX or 0
    local targetPanel = "left"
    if localX >= (leftEndX + rightStartX) / 2 then targetPanel = "right" end

    local order = ns.TopBar.Order()
    local visArr
    if targetPanel == "left" then visArr = VisibleIds(order.left) else visArr = VisibleIds(order.right) end

    if #visArr == 0 then return "insert", targetPanel, 1 end

    local spacing = lastSpacing or 0
    local swapZone = size * 0.2

    local firstSlot = slotPool[visArr[1]]
    if firstSlot and localX < firstSlot._baseX - spacing * 0.5 then
        return "insert", targetPanel, 1
    end

    for i = 1, #visArr do
        local slot = slotPool[visArr[i]]
        if slot and slot._baseX then
            local slotL, slotR = slot._baseX, slot._baseX + size
            local slotCX = slot._baseX + size / 2
            if localX >= slotL - spacing * 0.5 and localX < slotR + spacing * 0.5 then
                if visArr[i] ~= dragId and math.abs(localX - slotCX) < swapZone then
                    return "swap", targetPanel, i
                elseif localX < slotCX then
                    return "insert", targetPanel, i
                else
                    return "insert", targetPanel, i + 1
                end
            end
        end
    end

    return "insert", targetPanel, #visArr + 1
end

-- Slides the target panel's other slots aside for an insert and draws the
-- accent insert line between the two neighbours it will land between.
-- Ported from EUI_CooldownManager_Options.lua:14225-14229 (the line) and
-- :14243-14263 (the slide), scoped to one panel's row. A swap has no cited
-- visual in either reference file this task points at, so it gets none here
-- either -- ClearDragFeedback alone is its feedback.
local function ApplyDragFeedback(mode, targetPanel, targetIdx)
    ClearDragFeedback()
    if mode ~= "insert" then return end

    local order = ns.TopBar.Order()
    local visArr
    if targetPanel == "left" then visArr = VisibleIds(order.left) else visArr = VisibleIds(order.right) end

    local size = lastIconSize or 0
    local spacing = lastSpacing or 0
    local nudge = size + spacing

    for i, id in ipairs(visArr) do
        local skip = targetPanel == dragPanel and id == dragId
        if not skip then
            local slot = slotPool[id]
            if slot and slot._baseX then
                local virtualPos = i
                if targetPanel == dragPanel and i > dragFromIdx then virtualPos = i - 1 end
                local virtualInsert = targetIdx
                if targetPanel == dragPanel and targetIdx > dragFromIdx then virtualInsert = targetIdx - 1 end
                local offX = -nudge
                if virtualPos >= virtualInsert then offX = nudge end
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", slot._baseX + offX, slot._baseY)
            end
        end
    end

    EnsureInsertLine()
    local lineX
    if targetIdx <= 1 then
        local first = slotPool[visArr[1]]
        if first then lineX = first._baseX - spacing / 2 else lineX = 0 end
    elseif targetIdx > #visArr then
        local last = slotPool[visArr[#visArr]]
        if last then lineX = last._baseX + size + spacing / 2 else lineX = 0 end
    else
        local before = slotPool[visArr[targetIdx - 1]]
        local after = slotPool[visArr[targetIdx]]
        if before and after then lineX = (before._baseX + size + after._baseX) / 2 end
    end

    if lineX then
        local r, g, b = ns.TopBar.AccentRGB()
        insertLine:SetColorTexture(r, g, b, 0.9)
        insertLine:ClearAllPoints()
        insertLine:SetPoint("TOP", previewFrame, "TOPLEFT", lineX, lastYOff or 0)
        insertLine:SetPoint("BOTTOM", previewFrame, "TOPLEFT", lineX, (lastYOff or 0) - size)
        insertLine:Show()
    else
        insertLine:Hide()
    end
end

-- Step 5's algorithm, in full, verbatim per the brief. `stored` is the full
-- array (every id, hidden included); `newVisible` is the new VISIBLE
-- sequence for the same panel, a permutation of stored's own visible subset.
local function SpliceWithin(stored, newVisible)
    local out, k = {}, 0
    for i = 1, #stored do
        if Visible(stored[i]) then
            k = k + 1
            out[i] = newVisible[k] or stored[i]
        else
            out[i] = stored[i]
        end
    end
    return out
end

-- Ends the drag: restores the dragged slot's alpha, hides the ghost and any
-- slide/line feedback, and -- unless the drop is a no-op -- writes the new
-- order and redraws. Never moves preview frames directly; Layout() (via
-- PreviewRefresh) is the only thing that ever sets a slot's real position.
local function FinishDrag()
    local self = dragSlot
    if not self then return end
    self:SetAlpha(1)
    if dragGhost then dragGhost:Hide() end
    ClearDragFeedback()

    if dragMode and dragTargetPanel and dragTargetIdx then
        local isNoop
        if dragMode == "swap" then
            isNoop = dragTargetPanel == dragPanel and dragTargetIdx == dragFromIdx
        else
            local eff = dragTargetIdx
            if dragTargetPanel == dragPanel and eff > dragFromIdx then eff = eff - 1 end
            isNoop = dragTargetPanel == dragPanel and eff == dragFromIdx
        end

        if not isNoop then
            local order = ns.TopBar.Order()
            local visLeft = VisibleIds(order.left)
            local visRight = VisibleIds(order.right)
            local fromArr = visLeft
            if dragPanel == "right" then fromArr = visRight end
            local targetArr = visLeft
            if dragTargetPanel == "right" then targetArr = visRight end

            if dragMode == "swap" then
                fromArr[dragFromIdx], targetArr[dragTargetIdx] = targetArr[dragTargetIdx], fromArr[dragFromIdx]
            else
                local id = table.remove(fromArr, dragFromIdx)
                local insertAt = dragTargetIdx
                if dragTargetPanel == dragPanel and insertAt > dragFromIdx then insertAt = insertAt - 1 end
                if insertAt < 1 then insertAt = 1 end
                if insertAt > #targetArr + 1 then insertAt = #targetArr + 1 end
                table.insert(targetArr, insertAt, id)
            end

            local newLeft = SpliceWithin(order.left, visLeft)
            local newRight = SpliceWithin(order.right, visRight)
            ns.TopBar.SetOrder(newLeft, order.centre, newRight)
            ns.TopBar.Apply()
            ns.TopBar.PreviewRefresh()
        end
    end

    dragSlot, dragId, dragPanel, dragFromIdx = nil, nil, nil, nil
    dragMode, dragTargetPanel, dragTargetIdx = nil, nil, nil
end

-- The second OnUpdate (installed on previewFrame by BeginDrag). Polls for
-- release first -- the hole EllesmereUIDataBars_Options.lua:1262-1266 closes
-- on the slot's own pending-threshold OnUpdate, this closes on the
-- drag-in-progress one, so a release anywhere (including outside the
-- options window) always reaches FinishDrag.
local function DragTick()
    if not IsMouseButtonDown("LeftButton") then
        previewFrame:SetScript("OnUpdate", nil)
        FinishDrag()
        return
    end
    if not dragGhost then return end

    local cx, cy = GetCursorPosition()
    local sc = UIParent:GetEffectiveScale()
    local ucx, ucy = cx / sc, cy / sc
    local gs = dragGhost:GetScale() or 1
    dragGhost:ClearAllPoints()
    dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ucx / gs, ucy / gs)

    local mode, tPanel, tIdx = FindDragTarget(ucx, ucy)
    if mode and tPanel and tIdx then
        dragMode, dragTargetPanel, dragTargetIdx = mode, tPanel, tIdx
        ApplyDragFeedback(mode, tPanel, tIdx)
    else
        dragMode, dragTargetPanel, dragTargetIdx = nil, nil, nil
        ClearDragFeedback()
    end
end

-- Starts a drag once the slot's own pending-threshold OnUpdate (WireDrag,
-- below) crosses DRAG_THRESHOLD. Records which panel and visible index the
-- slot started at, so FinishDrag can tell a same-panel move from a
-- cross-panel one.
local function BeginDrag(self)
    local id, panel = self._id, self._panel
    if not (id and panel and self._baseX) then return end

    local order = ns.TopBar.Order()
    local visArr
    if panel == "left" then visArr = VisibleIds(order.left) else visArr = VisibleIds(order.right) end
    local idx
    for i, v in ipairs(visArr) do
        if v == id then idx = i break end
    end
    if not idx then return end

    dragSlot, dragId, dragPanel, dragFromIdx = self, id, panel, idx
    dragMode, dragTargetPanel, dragTargetIdx = nil, nil, nil

    local ghost = EnsureDragGhost()
    local fitScale = previewFrame:GetScale() or 1
    local w, h = self:GetWidth(), self:GetHeight()
    if not w then w = lastIconSize or 20 end
    if not h then h = lastIconSize or 20 end
    ghost:SetSize(w * fitScale, h * fitScale)
    if self._icon then ghost._icon:SetTexture(self._icon:GetTexture()) end
    ghost:Show()

    EnsureInsertLine()
    self:SetAlpha(0.3)

    previewFrame:SetScript("OnUpdate", DragTick)
end

-- Manual drag detection: a lightweight OnUpdate installed on the slot itself
-- at OnMouseDown, torn down either by crossing DRAG_THRESHOLD (which hands
-- off to BeginDrag) or by the button already being up on a later tick --
-- EllesmereUIDataBars_Options.lua:1262-1266's own guard, which is what stops
-- a press-and-release-elsewhere from leaking a live OnUpdate when OnMouseUp
-- never fires on this slot.
local function WireDrag(slot)
    slot:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local cx, cy = GetCursorPosition()
        self._pendX, self._pendY = cx, cy
        self:SetScript("OnUpdate", function(s)
            if not IsMouseButtonDown("LeftButton") then
                s:SetScript("OnUpdate", nil)
                s._pendX, s._pendY = nil, nil
                return
            end
            local nx, ny = GetCursorPosition()
            local dx = nx - (s._pendX or nx)
            local dy = ny - (s._pendY or ny)
            if dx * dx + dy * dy >= DRAG_THRESHOLD * DRAG_THRESHOLD then
                s:SetScript("OnUpdate", nil)
                s._pendX, s._pendY = nil, nil
                BeginDrag(s)
            end
        end)
    end)
    slot:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self._pendX then
            self:SetScript("OnUpdate", nil)
            self._pendX, self._pendY = nil, nil
        end
    end)
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
            if not slot._dragWired then
                WireDrag(slot)
                slot._dragWired = true
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

    -- Task 3: cached for FindDragTarget/ApplyDragFeedback, which run off the
    -- mouse rather than off a fresh Layout() pass and so need this frozen at
    -- the values the currently-drawn slots were placed with.
    lastIconSize = iconSize
    lastSpacing  = spacing
    lastYOff     = -(iconRowH - iconSize) / 2

    local leftW = LayoutLauncherPanel(order.left, "left", 0, iconSize, spacing, iconRowH)
    lastLeftEndX = leftW

    if clockSlot then
        PositionClock(clockSlot, leftW + spacing, -(iconRowH - clockH) / 2, clockW, clockH)
    end

    local rightStartX = leftW + spacing + clockW + spacing
    local rightW = LayoutLauncherPanel(order.right, "right",
        rightStartX, iconSize, spacing, iconRowH)
    lastRightStartX = rightStartX

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
