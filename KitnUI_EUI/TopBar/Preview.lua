-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/TopBar/Preview.lua                                ║
-- ║  Purpose: The live arrangement preview pinned above the Top   ║
-- ║           Bar options page, and its drag-to-arrange.          ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

local previewWrap        -- UNSCALED. Centred on the stage (below); the
                          -- CONTENT_PAD inset now lives in availW alone, not
                          -- in this frame's offset. See below.
local previewFrame       -- module-local. NEVER EllesmereUI._contentHeaderPreview.
local previewStage       -- UNSCALED. The backdrop the bar centres on, parented
                          -- to the HEADER frame -- never previewWrap or
                          -- previewFrame -- so it never inherits the fit scale.
                          -- Built once in BuildPreviewHeader, exactly as
                          -- hintText already is.
local hintText            -- parented to the HEADER frame, never previewFrame or
                          -- previewWrap. Built once in BuildPreviewHeader.
local dividerL, dividerR  -- UNSCALED. The two zone dividers, parented to
                          -- previewWrap. See LayoutDividers.
local availW              -- usable width, cached from the last BuildPreviewHeader
                          -- call so a settings-driven PreviewRefresh (which gets
                          -- no width argument) can still fit against it.

-- The builder is handed rightW (1005), unpadded. Inset by CONTENT_PAD on each
-- side so the stage -- and the preview centred on it -- lines up with the
-- padded content below it, exactly as the CDM insets its own preview wrapper
-- (EUI_CooldownManager_Options.lua:13952-13965). The `or 10` fallback is the
-- CDM's own idiom, not a guess. previewWrap no longer carries the inset as an
-- offset; availW alone bounds the stage's own width, so the preview can never
-- exceed the padded area.
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
-- So: previewWrap owns the centring and is never scaled; previewFrame owns the
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
-- Widest plausible readout, used to MEASURE the fps slot. Must keep the same
-- case as the real string Readouts.lua:158 builds, or the measurement is of a
-- string the bar never draws.
local FPS_STRING       = "999 FPS  999 MS"

-- Vertical gap between the icon row and the FPS text under the clock, and
-- between the preview and the hint line below it. Not part of any width/scale
-- arithmetic, so any reasonable constant is fine here.
local READOUT_GAP = 2
local HINT_GAP    = 6
local STAGE_PAD_Y = 6      -- breathing room above and below the bar

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
-- Task 3: drag to reorder WITHIN a panel. Only launcher slots
-- (LayoutLauncherPanel, below) are wired -- the clock and fps slots never
-- call WireDrag. Ported from the house drag idiom
-- (EUI_CooldownManager_Options.lua, EllesmereUIDataBars_Options.lua:1236-
-- 1276).
--
-- Task 4: widened to also allow a drop in the OTHER launcher panel, ported
-- from EllesmereUIBags.lua's ComputeDropZone (:3154-3205) -- a cursor now
-- resolves to a (mode, index, panel) triple instead of just (mode, index).
-- The centre panel (the clock's own domain) and anything outside both
-- launcher panels still refuse: FindDragTarget returns nil for both, which
-- FinishDrag treats as a no-op, same as an in-panel cancel.
---------------------------------------------------------------------------------

local DRAG_THRESHOLD = 3

-- Cached from the last Layout() pass so drag maths never has to re-derive
-- the row geometry mid-drag. Shared by both panels -- Layout() lays out both
-- with the same iconSize/spacing/yOff. lastLeftW/lastClockStartX/lastClockW/
-- lastRightStartX/lastRightW (Task 4) are each panel's own content span in
-- previewFrame-local x, so FindDragTarget can resolve a panel zone even when
-- that panel is currently empty and has no slot to read a _baseX from.
local lastIconSize, lastSpacing, lastYOff
local lastLeftW, lastClockStartX, lastClockW, lastRightStartX, lastRightW

-- Drag state. Set by BeginDrag, read by FindDragTarget/ApplyDragFeedback/
-- FinishDrag, cleared by FinishDrag and by CancelDragOnHide.
--
-- dragPanel is fixed for the whole drag: it is the panel the drag STARTED
-- in, and dragVisArr is a snapshot of that panel's own visible ids (dragged
-- id included), taken once in BeginDrag. dragOtherVisArr (Task 4) is the
-- same kind of snapshot for the OTHER panel, which never contains the
-- dragged id -- so a "swap" target is only ever resolved within dragVisArr,
-- never dragOtherVisArr (FindDragTarget gates that explicitly). Neither
-- array is re-derived from ns.TopBar.Order() mid-drag: nothing else can
-- touch tbOrder while a drag is in progress, so re-deriving either every
-- tick would be pure waste -- three CopyTables and a fresh table build,
-- every frame, for a value that cannot have changed mid-drag.
local dragSlot, dragId, dragPanel, dragFromIdx, dragVisArr, dragOtherVisArr
local dragMode, dragTargetIdx, dragTargetPanel
local dragGhost
local insertLine

-- The slot currently armed by WireDrag's OnMouseDown -- pressed, but not yet
-- past DRAG_THRESHOLD, so BeginDrag has not run and dragSlot is still nil.
-- Fix round 2: that slot's own pending OnUpdate cannot tick while
-- previewFrame is hidden, so CancelDragOnHide has to reach it separately
-- from dragSlot -- an armed-but-not-dragging press is exactly the case
-- dragSlot is nil for.
local pendingSlot

-- The (mode, index, panel) DragTick last actually applied. Skips
-- ApplyDragFeedback/ClearDragFeedback when the target has not moved since
-- the previous tick -- EUI_CooldownManager_Options.lua:14443's own
-- early-out. Cleared by BeginDrag, FinishDrag and CancelDragOnHide so a new
-- drag never early-outs against a stale value left by the last one.
local lastFeedbackMode, lastFeedbackIdx, lastFeedbackPanel

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
-- resolves it to a (mode, index, panel) drop target. cx, cy are already
-- divided by UIParent's own effective scale by the caller (the drag ticker,
-- below), matching that reference's own calling convention.
--
-- Task 4: ported from EllesmereUIBags.lua's ComputeDropZone (:3154-3205),
-- mirrored over three horizontal panels instead of N vertical bag rows. The
-- x axis is split into left/centre/right zones at the MIDPOINTS of the gaps
-- between lastLeftW/lastClockStartX+lastClockW/lastRightStartX (Layout()'s
-- own cached spans, Task 4), not off any one slot's _baseX -- that keeps a
-- zone resolvable even when its panel is currently empty. The centre zone
-- (the clock's own domain) and anything past the outer edge of either
-- launcher panel both return nil -- the Bags refusal path at :3282-3300 --
-- which the caller treats as a cancelled drag, same as an in-panel no-op.
--
-- "swap" is only ever returned for the panel the drag STARTED in (dragPanel):
-- a swap trades the dragged id for another WITHOUT changing either stored
-- array's length, which only makes sense within one array. The other panel's
-- own visible array (dragOtherVisArr) never contains the dragged id, so
-- without this gate the same distance-from-centre test would spuriously
-- return "swap" there too -- a mode Step 3's move helpers cannot commit.
local function FindDragTarget(cx, cy)
    if not (previewFrame and dragPanel and dragVisArr) then return nil end
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

    local spacing = lastSpacing or 0
    local leftW = lastLeftW or 0
    local clockStartX = lastClockStartX or leftW
    local clockW = lastClockW or 0
    local rightStartX = lastRightStartX or leftW
    local rightW = lastRightW or 0

    local boundaryLC = leftW + spacing * 0.5
    local boundaryCR = clockStartX + clockW + spacing * 0.5
    local leftOuter = -spacing * 0.5
    local rightOuter = rightStartX + rightW + spacing * 0.5

    -- Fix round 3, Fix 2: an empty panel draws nothing, so its drop zone is
    -- only `spacing` wide -- 14 preview-local units at the default
    -- tbSpacing, 4 at the slider minimum, half of it outside previewFrame's
    -- own left edge -- and there is no reset-order control anywhere in the
    -- UI to escape the state Task 4 made legitimate and persistent. Extend
    -- the panel's own OUTER boundary, and ONLY the outer one (never
    -- boundaryLC/boundaryCR, which stay exactly as they were), by one
    -- button footprint -- `size` already includes BTN_PAD -- so an empty
    -- side offers a target the size of the icon it is missing. A non-empty
    -- panel's boundaries are untouched: this only fires when the cached span
    -- for that side is zero.
    if leftW == 0 then leftOuter = leftOuter - size end
    if rightW == 0 then rightOuter = rightOuter + size end

    local targetPanel
    if localX < boundaryLC then
        if localX < leftOuter then return nil end
        targetPanel = "left"
    elseif localX < boundaryCR then
        return nil -- centre: the clock's own domain, never a drop target
    elseif localX <= rightOuter then
        targetPanel = "right"
    else
        return nil -- past the right panel's own outer edge
    end

    local visArr
    if targetPanel == dragPanel then visArr = dragVisArr else visArr = dragOtherVisArr end
    if not visArr then return nil end
    if #visArr == 0 then return "insert", 1, targetPanel end

    local first = slotPool[visArr[1]]
    local last = slotPool[visArr[#visArr]]
    if not (first and first._baseX and last and last._baseX) then return nil end

    local swapZone = size * 0.2

    for i = 1, #visArr do
        local slot = slotPool[visArr[i]]
        if slot and slot._baseX then
            local slotL, slotR = slot._baseX, slot._baseX + size
            local slotCX = slot._baseX + size / 2
            if localX >= slotL - spacing * 0.5 and localX < slotR + spacing * 0.5 then
                if targetPanel == dragPanel and visArr[i] ~= dragId and math.abs(localX - slotCX) < swapZone then
                    return "swap", i, targetPanel
                elseif localX < slotCX then
                    return "insert", i, targetPanel
                else
                    return "insert", i + 1, targetPanel
                end
            end
        end
    end

    return "insert", #visArr + 1, targetPanel
end

-- Slides dragPanel's other slots aside for an in-panel insert and draws the
-- accent insert line between the two neighbours it will land between. Ported
-- from EUI_CooldownManager_Options.lua:14225-14229 (the line), :14243-14263
-- (the slide) and :14451 (the nudge distance -- fix round 1: this used to be
-- size+spacing, about 6.7x the reference's own value, which shoved the
-- default 12-icon right panel's leading edge onto the clock). A swap has no
-- cited visual in either reference file this task points at, so it gets
-- none here either -- ClearDragFeedback alone is its feedback.
--
-- Task 4: targetPanel picks which snapshot to read (dragVisArr for
-- dragPanel itself, dragOtherVisArr for the panel across the gap). The
-- slide-aside only ever runs for dragPanel: dragOtherVisArr's ids are not
-- being reordered relative to each other, only gaining one new neighbour on
-- commit, so there is nothing there for the slide's virtualPos/virtualInsert
-- maths (both anchored on dragFromIdx, a position that only means something
-- within dragPanel's own array) to apply to.
local function ApplyDragFeedback(mode, targetIdx, targetPanel)
    ClearDragFeedback()
    if mode ~= "insert" then return end
    if not targetPanel then return end
    local visArr
    if targetPanel == dragPanel then visArr = dragVisArr else visArr = dragOtherVisArr end
    if not visArr then return end

    local size = lastIconSize or 0
    local spacing = lastSpacing or 0

    if targetPanel == dragPanel then
        local nudge = math.floor((size + spacing) * 0.15)
        for i, id in ipairs(visArr) do
            if id ~= dragId then
                local slot = slotPool[id]
                if slot and slot._baseX then
                    local virtualPos = i
                    if i > dragFromIdx then virtualPos = i - 1 end
                    local virtualInsert = targetIdx
                    if targetIdx > dragFromIdx then virtualInsert = targetIdx - 1 end
                    local offX = -nudge
                    if virtualPos >= virtualInsert then offX = nudge end
                    slot:ClearAllPoints()
                    slot:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", slot._baseX + offX, slot._baseY)
                end
            end
        end
    end

    EnsureInsertLine()
    local panelStartX = 0
    if targetPanel == "right" then panelStartX = lastRightStartX or 0 end
    local lineX
    if #visArr == 0 then
        lineX = panelStartX
    elseif targetIdx <= 1 then
        local first = slotPool[visArr[1]]
        if first and first._baseX then lineX = first._baseX - spacing / 2 else lineX = panelStartX end
    elseif targetIdx > #visArr then
        local last = slotPool[visArr[#visArr]]
        if last and last._baseX then lineX = last._baseX + size + spacing / 2 else lineX = panelStartX end
    else
        local before = slotPool[visArr[targetIdx - 1]]
        local after = slotPool[visArr[targetIdx]]
        if before and before._baseX and after and after._baseX then
            lineX = (before._baseX + size + after._baseX) / 2
        end
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
    -- ENFORCE the precondition, do not assume it. `Visible` depends on the live
    -- `el.requires()` predicate, so the visible count at drop time can differ
    -- from the count when the drag began and cached its array. On a mismatch the
    -- loop below silently duplicates one id and deletes another through its own
    -- fallback, and SetOrder writes that to SavedVariables. Refusing is always
    -- safe: the worst case is a drag that does nothing. This guard would also
    -- have caught the cross-panel corruption Task 3's review found.
    local nVis = 0
    for i = 1, #stored do
        if Visible(stored[i]) then nVis = nVis + 1 end
    end
    if nVis ~= #newVisible then return stored end

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

-- Task 4, verbatim per the brief. Operate on the STORED arrays directly and
-- must NEVER be routed through SpliceWithin: a cross-panel move changes
-- both arrays' visible lengths, and SpliceWithin's length guard above
-- returns `stored` unchanged on exactly that mismatch, so a cross-panel
-- drop routed through it would silently do nothing. RemoveId only ever
-- shortens the SOURCE array by one -- any hidden id after the removed slot
-- closes up by one index, unavoidable since the array is genuinely
-- shorter, but harmless since their relative order is untouched. A hidden
-- id never changes panel: only the dragged id moves, and it is visible by
-- definition.
local function RemoveId(arr, id)
    local out = {}
    for i = 1, #arr do
        if arr[i] ~= id then out[#out + 1] = arr[i] end
    end
    return out
end

-- Insert id into `arr` so it becomes the k-th VISIBLE entry. k is 1-based and
-- comes from the drop position among the target panel's visible slots; a k past
-- the last visible entry appends.
local function InsertAtVisible(arr, id, k)
    local out, seen, placed = {}, 0, false
    for i = 1, #arr do
        if Visible(arr[i]) then
            seen = seen + 1
            if seen == k and not placed then
                out[#out + 1] = id
                placed = true
            end
        end
        out[#out + 1] = arr[i]
    end
    if not placed then out[#out + 1] = id end
    return out
end

-- Ends the drag: restores the dragged slot's alpha, hides the ghost and any
-- slide/line feedback, and -- unless the drop is a no-op -- writes the new
-- order and redraws. Never moves preview frames directly; Layout() (via
-- PreviewRefresh) is the only thing that ever sets a slot's real position.
--
-- Task 4: branches on dragTargetPanel == dragPanel. Same-panel keeps Task
-- 3's own swap/insert-within-visArr logic and SpliceWithin, byte for byte.
-- Cross-panel (dragMode is always "insert" there -- FindDragTarget never
-- returns "swap" for the other panel) goes through RemoveId/InsertAtVisible
-- on the two STORED arrays instead, per the brief's Step 3 -- it is never a
-- no-op, because landing in a different panel is always a real change.
local function FinishDrag()
    local self = dragSlot
    if not self then return end
    self:SetAlpha(1)
    if dragGhost then dragGhost:Hide() end
    ClearDragFeedback()

    if dragMode and dragTargetIdx and dragTargetPanel then
        if dragTargetPanel == dragPanel then
            local isNoop
            if dragMode == "swap" then
                isNoop = dragTargetIdx == dragFromIdx
            else
                local eff = dragTargetIdx
                if eff > dragFromIdx then eff = eff - 1 end
                isNoop = eff == dragFromIdx
            end

            if not isNoop then
                local visArr = dragVisArr

                if dragMode == "swap" then
                    visArr[dragFromIdx], visArr[dragTargetIdx] = visArr[dragTargetIdx], visArr[dragFromIdx]
                else
                    local id = table.remove(visArr, dragFromIdx)
                    local insertAt = dragTargetIdx
                    if insertAt > dragFromIdx then insertAt = insertAt - 1 end
                    if insertAt < 1 then insertAt = 1 end
                    if insertAt > #visArr + 1 then insertAt = #visArr + 1 end
                    table.insert(visArr, insertAt, id)
                end

                -- Fresh, full (hidden-inclusive) arrays for SpliceWithin --
                -- this is a one-time read at drop, not a per-tick one. The
                -- panel dragPanel did NOT touch is passed straight through
                -- unchanged.
                local order = ns.TopBar.Order()
                local newLeft, newRight
                if dragPanel == "left" then
                    newLeft = SpliceWithin(order.left, visArr)
                    newRight = order.right
                else
                    newLeft = order.left
                    newRight = SpliceWithin(order.right, visArr)
                end
                ns.TopBar.SetOrder(newLeft, order.centre, newRight)
                ns.TopBar.Apply()
                ns.TopBar.PreviewRefresh()
            end
        elseif dragMode == "insert" then
            local order = ns.TopBar.Order()
            local sourceStored, destStored
            if dragPanel == "left" then
                sourceStored, destStored = order.left, order.right
            else
                sourceStored, destStored = order.right, order.left
            end

            sourceStored = RemoveId(sourceStored, dragId)
            destStored = InsertAtVisible(destStored, dragId, dragTargetIdx)

            local newLeft, newRight
            if dragPanel == "left" then
                newLeft, newRight = sourceStored, destStored
            else
                newLeft, newRight = destStored, sourceStored
            end
            ns.TopBar.SetOrder(newLeft, order.centre, newRight)
            ns.TopBar.Apply()
            ns.TopBar.PreviewRefresh()
        end
    end

    dragSlot, dragId, dragPanel, dragFromIdx, dragVisArr, dragOtherVisArr = nil, nil, nil, nil, nil, nil
    dragMode, dragTargetIdx, dragTargetPanel = nil, nil, nil
    lastFeedbackMode, lastFeedbackIdx, lastFeedbackPanel = nil, nil, nil
    -- Fix round 2, Fix 2: pendingSlot is normally already nil here (the
    -- threshold handoff clears it before BeginDrag ever runs), but clearing
    -- it again costs nothing and keeps this function's own end state
    -- self-contained rather than relying on that ordering elsewhere.
    pendingSlot = nil
end

-- The second OnUpdate (installed on previewFrame by BeginDrag). Polls for
-- release first -- the hole EllesmereUIDataBars_Options.lua:1262-1266 closes
-- on the slot's own pending-threshold OnUpdate, this closes on the
-- drag-in-progress one, so a release anywhere (including outside the
-- options window) always reaches FinishDrag.
--
-- Fix round 1: FindDragTarget is cheap now (dragVisArr is a snapshot, not a
-- fresh Order() call), so it still runs every tick, but ApplyDragFeedback/
-- ClearDragFeedback -- the ~40 SetPoint calls -- only run when the target
-- actually changed since the last tick (lastFeedbackMode/lastFeedbackIdx),
-- matching EUI_CooldownManager_Options.lua:14443's own early-out.
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

    local mode, tIdx, tPanel = FindDragTarget(ucx, ucy)
    if mode == lastFeedbackMode and tIdx == lastFeedbackIdx and tPanel == lastFeedbackPanel then return end
    lastFeedbackMode, lastFeedbackIdx, lastFeedbackPanel = mode, tIdx, tPanel

    dragMode, dragTargetIdx, dragTargetPanel = mode, tIdx, tPanel
    if mode and tIdx and tPanel then
        ApplyDragFeedback(mode, tIdx, tPanel)
    else
        ClearDragFeedback()
    end
end

-- Starts a drag once the slot's own pending-threshold OnUpdate (WireDrag,
-- below) crosses DRAG_THRESHOLD. Records the panel and visible index the
-- slot started at, and snapshots BOTH panels' own visible ids once (Task
-- 4) -- the only read of ns.TopBar.Order() for the rest of the drag;
-- FindDragTarget and ApplyDragFeedback both reuse dragVisArr/dragOtherVisArr
-- instead of re-deriving either every tick.
local function BeginDrag(self)
    local id, panel = self._id, self._panel
    if not (id and panel and self._baseX) then return end

    local order = ns.TopBar.Order()
    local visArr, otherVisArr
    if panel == "left" then
        visArr = VisibleIds(order.left)
        otherVisArr = VisibleIds(order.right)
    else
        visArr = VisibleIds(order.right)
        otherVisArr = VisibleIds(order.left)
    end
    local idx
    for i, v in ipairs(visArr) do
        if v == id then idx = i break end
    end
    if not idx then return end

    dragSlot, dragId, dragPanel, dragFromIdx, dragVisArr = self, id, panel, idx, visArr
    dragOtherVisArr = otherVisArr
    dragMode, dragTargetIdx, dragTargetPanel = nil, nil, nil
    lastFeedbackMode, lastFeedbackIdx, lastFeedbackPanel = nil, nil, nil

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

-- Tears an in-progress drag down WITHOUT writing anything -- called from
-- previewFrame's OnHide (fix round 1). The host reparents every content-
-- header child when the user leaves this page or closes the panel
-- (EllesmereUI.lua:9202-9224, :9313-9322), which can Hide() previewFrame
-- with the mouse button still down. WoW does not run OnUpdate on a hidden
-- frame, so an in-progress drag would otherwise freeze mid-air: the ghost
-- stranded on UIParent at TOOLTIP strata, the dragged slot stuck at alpha
-- 0.3, and -- on the next visit, when previewFrame shows again and DragTick
-- fires once more, sees the button already up -- FinishDrag would write a
-- stale reorder to SavedVariables minutes after the user actually let go.
-- This reaches the same end state FinishDrag's no-op path does, but never
-- calls FinishDrag and so never reaches SetOrder.
--
-- Fix round 2: two more cases folded in, in order.
--
-- Fix 2 -- a slot can be ARMED (pressed, short of DRAG_THRESHOLD) with no
-- drag in progress at all: dragSlot is still nil at that point. That slot's
-- own pending OnUpdate cannot tick while previewFrame is hidden, so it has
-- to be torn down here too, before the dragSlot check below -- otherwise it
-- resumes on the next Show against a stale cursor delta from the PREVIOUS
-- visit, and if the button happens to be down again by then, can cross the
-- threshold immediately and start a drag the user never began this time.
--
-- Fix 3 -- everything past that point (the OnUpdate teardown, the ghost, the
-- alpha restore, ClearDragFeedback's own loop over every entry in slotPool)
-- has nothing to undo when no drag is in progress, which is the common case
-- of simply leaving the page. Return early once the pending tracker is
-- handled, rather than doing that work on every hide.
local function CancelDragOnHide()
    if pendingSlot then
        pendingSlot:SetScript("OnUpdate", nil)
        pendingSlot._pendX, pendingSlot._pendY = nil, nil
        pendingSlot = nil
    end

    if not dragSlot then return end

    if previewFrame then previewFrame:SetScript("OnUpdate", nil) end
    if dragGhost then dragGhost:Hide() end
    dragSlot:SetAlpha(1)
    ClearDragFeedback()
    dragSlot, dragId, dragPanel, dragFromIdx, dragVisArr, dragOtherVisArr = nil, nil, nil, nil, nil, nil
    dragMode, dragTargetIdx, dragTargetPanel = nil, nil, nil
    lastFeedbackMode, lastFeedbackIdx, lastFeedbackPanel = nil, nil, nil
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
        -- Second-drag guard (fix round 1), matching
        -- EllesmereUIDataBars_Options.lua:1258: a press on another slot
        -- while one is already dragging must not arm a second pending
        -- watch on top of it.
        if dragSlot then return end
        local cx, cy = GetCursorPosition()
        pendingSlot = self
        self._pendX, self._pendY = cx, cy
        self:SetScript("OnUpdate", function(s)
            if not IsMouseButtonDown("LeftButton") then
                s:SetScript("OnUpdate", nil)
                s._pendX, s._pendY = nil, nil
                pendingSlot = nil
                return
            end
            local nx, ny = GetCursorPosition()
            local dx = nx - (s._pendX or nx)
            local dy = ny - (s._pendY or ny)
            if dx * dx + dy * dy >= DRAG_THRESHOLD * DRAG_THRESHOLD then
                s:SetScript("OnUpdate", nil)
                s._pendX, s._pendY = nil, nil
                -- Threshold handoff (fix round 2, Fix 2): BeginDrag is about
                -- to set dragSlot, so this slot is no longer merely "armed".
                pendingSlot = nil
                BeginDrag(s)
            end
        end)
    end)
    slot:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self._pendX then
            self:SetScript("OnUpdate", nil)
            self._pendX, self._pendY = nil, nil
            pendingSlot = nil
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

-- The two zone dividers: one between the left launcher panel and the clock,
-- one between the clock and the right panel. They show the user where the
-- three drag zones actually are, which is why they are placed on
-- FindDragTarget's OWN boundaries (boundaryLC/boundaryCR, :267-268) rather
-- than merely near them -- a divider drawn anywhere else would be a picture
-- of a rule the drop test does not follow.
--
-- Parented to previewWrap, which is UNSCALED, and given the boundary
-- positions converted into wrap space. A one-unit line on previewFrame would
-- be the same line in CONTENT space and would soften to two thirds of a pixel
-- at the worst-case fit; this one stays a crisp single pixel at any scale.
--
-- Hidden entirely when the clock is not drawn: with no centre occupant there
-- is no centre zone to divide, and FindDragTarget's own boundaries collapse
-- onto each other.
local function LayoutDividers(boundaryLC, boundaryCR, rowH, scale, hasClock)
    if not previewWrap then return end
    if not dividerL then
        dividerL = previewWrap:CreateTexture(nil, "ARTWORK")
        dividerR = previewWrap:CreateTexture(nil, "ARTWORK")
    end
    if not (dividerL and dividerR) then return end

    if not hasClock then
        dividerL:Hide()
        dividerR:Hide()
        return
    end

    local h = math.max(1, rowH * scale)
    for _, tex in ipairs({ dividerL, dividerR }) do
        tex:SetColorTexture(1, 1, 1, 0.10)
        tex:SetSize(1, h)
        tex:ClearAllPoints()
    end
    dividerL:SetPoint("TOPLEFT", previewWrap, "TOPLEFT", boundaryLC * scale, 0)
    dividerR:SetPoint("TOPLEFT", previewWrap, "TOPLEFT", boundaryCR * scale, 0)
    dividerL:Show()
    dividerR:Show()
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

    if clockSlot then
        PositionClock(clockSlot, leftW + spacing, -(iconRowH - clockH) / 2, clockW, clockH)
    end

    local rightStartX = leftW + spacing + clockW + spacing
    local rightW = LayoutLauncherPanel(order.right, "right",
        rightStartX, iconSize, spacing, iconRowH)

    -- Task 4: each panel's own content span, cached the same way lastIconSize
    -- etc. are above -- FindDragTarget's zone boundaries read these instead
    -- of a slot's own _baseX, so a zone stays resolvable even when its panel
    -- is currently empty (leftW/rightW == 0).
    lastLeftW        = leftW
    lastClockStartX  = leftW + spacing
    lastClockW       = clockW
    lastRightStartX  = rightStartX
    lastRightW       = rightW

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
    -- The SCALED CONTENT width, not the full availW: centring previewWrap
    -- (on the stage) only centres the bar if the wrapper is sized to it.
    previewWrap:SetSize(math.max(1, contentW * scale), unscaledH * scale)
    previewStage:SetSize(math.max(1, availW), unscaledH * scale + STAGE_PAD_Y * 2)

    -- After previewWrap is sized, because the dividers anchor to it. The two
    -- expressions are FindDragTarget's boundaryLC/boundaryCR verbatim
    -- (:267-268), read off the same cached spans it reads.
    LayoutDividers(leftW + spacing * 0.5,
        lastClockStartX + clockW + spacing * 0.5,
        iconRowH, scale, clockSlot and true or false)

    -- Step 5: the scaled preview's own contribution, the stage's own vertical
    -- padding, plus the hint line's own height and gap, both UNSCALED -- the
    -- hint is parented to the header frame (Step 4) and never scaled.
    local hintH = 0
    if hintText then hintH = hintText:GetStringHeight() or 0 end
    return unscaledH * scale + STAGE_PAD_Y * 2 + HINT_GAP + hintH
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

    -- previewWrap is centred on the stage below and is NEVER scaled.
    previewWrap = previewWrap or CreateFrame("Frame", nil, parent)
    previewWrap:SetParent(parent)

    -- The stage: represents the SCREEN the bar sits centred on. Parented
    -- directly to `parent` -- never into the previewWrap/previewFrame chain
    -- -- so it never inherits the fit scale. Created once, cached, reused on
    -- rebuild, exactly as hintText already is.
    if not previewStage then
        previewStage = CreateFrame("Frame", nil, parent)
        if EllesmereUI and EllesmereUI.SolidTex then
            previewStage._fill = EllesmereUI.SolidTex(previewStage, "BACKGROUND", 0, 0, 0, 0.22)
            if previewStage._fill then previewStage._fill:SetAllPoints() end
        end
        -- Independently guarded from the fill above: a missing border must
        -- not cost the backdrop.
        if EllesmereUI and EllesmereUI.MakeBorder and EllesmereUI.BORDER_R and EllesmereUI.BORDER_G
           and EllesmereUI.BORDER_B and EllesmereUI.PanelPP then
            EllesmereUI.MakeBorder(previewStage, EllesmereUI.BORDER_R, EllesmereUI.BORDER_G,
                EllesmereUI.BORDER_B, 0.35, EllesmereUI.PanelPP)
        end
    end
    previewStage:SetParent(parent)
    -- Lower than previewWrap's, so the stage always draws behind the preview
    -- regardless of creation order.
    previewStage:SetFrameLevel(previewWrap:GetFrameLevel() - 1)
    previewStage:ClearAllPoints()
    previewStage:SetPoint("TOP", parent, "TOP", 0, 0)
    previewStage:Show()

    previewWrap:ClearAllPoints()
    previewWrap:SetPoint("TOP", previewStage, "TOP", 0, -STAGE_PAD_Y)
    previewWrap:Show()

    -- previewFrame is the scaled child. Its offset inside the wrapper is 0,0,
    -- and zero is the one offset a scale cannot distort.
    previewFrame = previewFrame or CreateFrame("Frame", nil, previewWrap)
    previewFrame:SetParent(previewWrap)
    previewFrame:ClearAllPoints()
    previewFrame:SetPoint("TOPLEFT", previewWrap, "TOPLEFT", 0, 0)
    previewFrame:Show()
    -- Fix round 1: cancels an in-progress drag cleanly if the host hides
    -- this frame mid-drag (leaving the page, closing the panel) instead of
    -- letting DragTick freeze and later write a stale reorder.
    previewFrame:SetScript("OnHide", CancelDragOnHide)

    -- Step 4: the hint line, parented to the HEADER frame -- not previewFrame,
    -- not previewWrap -- so it never shrinks with the fit scale and has no
    -- business inside the frame Task 3's drag maths converts cursor
    -- coordinates against. The hint's own TOP is anchored to the STAGE's
    -- BOTTOM (never scaled), centred to match the centred preview above it,
    -- so the hint hangs BELOW the stage and the gap stays a constant pixel
    -- count regardless of the fit scale.
    if not hintText then
        hintText = parent:CreateFontString(nil, "OVERLAY")
        hintText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        hintText:SetJustifyH("CENTER")
        hintText:SetTextColor(0.6, 0.6, 0.6, 1)
        -- Short on purpose. The two zone dividers (LayoutDividers) now show
        -- the sides and the centre, so the sentence no longer has to explain
        -- them.
        hintText:SetText("Drag an icon to arrange the bar however you like.")
    end
    hintText:SetParent(parent)
    hintText:ClearAllPoints()
    hintText:SetPoint("TOP", previewStage, "BOTTOM", 0, -HINT_GAP)
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
    -- Fix round 3, Fix 1: previewFrame survives leaving the page (its parent
    -- previewWrap is stashed and hidden by SaveContentHeaderToCache, not
    -- destroyed -- EllesmereUI.lua:9213), so the nil check above stays true
    -- for the rest of the session after one visit to the Top Bar page. 23 of
    -- the 24 callers only fire while the Top Bar page is on screen, but the
    -- RegAccent callback (Options.lua, registered at file scope) is
    -- session-scoped and reaches this on every profile apply and every
    -- spec-driven profile swap -- with the Top Bar page not the mounted one,
    -- this would resize and re-layout whatever OTHER module's header frame
    -- currently owns the shared contentHeaderFrame. IsVisible(), not
    -- IsShown(): it accounts for the whole parent chain, and it is
    -- previewWrap that SaveContentHeaderToCache hides, not previewFrame's
    -- own Show flag. False in both bad cases; true in all three legitimate
    -- ones -- widget setters, FinishDrag, and PreviewRestore, which only
    -- fires after RestoreContentHeaderFromCache has already shown
    -- previewWrap again (:9239-9241).
    if not previewFrame:IsVisible() then return end
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
