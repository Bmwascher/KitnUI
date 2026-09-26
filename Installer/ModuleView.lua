-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ModuleView.lua                                              ║
-- ║  Purpose: The EllesmereUI part list: the Profile Update      ║
-- ║           wizard's EllesmereUI step and the install          ║
-- ║           wizard's Modules sub-page, with their counts,      ║
-- ║           ticks, tooltips and per-part Reset.                ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- The count walk is the one every-frame path here: while a count is pending,
-- one C_Timer.After(0) step per frame, the first included, does at most
-- EUI_DIFF_STEPS units, a unit being one key read (ModuleRows.lua, tick),
-- aiming at 2 ms a frame. Leaving the page or closing the wizard stops it;
-- nothing runs while no list is showing.
local EUI_DIFF_STEPS = 900

local ROW_H, ROW_H_MIN = 20, 14
-- The list ends above the split line, which sits on the action row.
local LIST_TOP, LIST_BOTTOM = -70, 150
local CONTENT_X, CONTENT_W = 200, 520
local YOURS_X, KITN_X_MODULES, KITN_X_UPDATER = 230, 350, 260
local MODULES_TITLE = "EllesmereUI Modules"
local AMBER = { 1, 0.8, 0.2 }

local TEXT = {
    introUpdate = "KitnUI %s changes %d parts of EllesmereUI. Everything is ticked; untick a part to keep it as you have it. Hover a count to see what changes.",
    introCurrent = "Each part of EllesmereUI on its own.",
    introModulesUpdate = "Each part of EllesmereUI on its own. Tick what you want to take from KitnUI; the rest stays as you have it.",
    introModulesCurrent = "Each part of EllesmereUI on its own. Tick a skipped part to take its update. Hover a row to reset it to KitnUI's version.",
    changesOne = "changes 1 setting",
    changesMany = "changes %d settings",
    noChanges = "no changes",
    replaces = "replaces yours",
    off = "off - Plater chosen",
    waiting = "skipped - %d waiting",
    upToDate = "up to date",
    counting = "...",
    checking = "checking...",
    yours = "changed by you - %d",
    asInstalled = "as installed",
    differs = "differs",
    matches = "matches",
    reloadToCheck = "reload to check",
    refused = "-",
    tipTitle = "%s - changes %d settings",
    tipSkipped = "Skipped in KitnUI %s",
    updateAll = "Update Profile",
    updateAllNoBase = "Update (replaces your changes)",
    updateTicked = "Update ticked (%d)",
    replaceTicked = "Replace ticked (%d)",
    tickAll = "Tick all",
    takeSkipped = "Take skipped (%d)",
    tickToo = "Tick %s too",
    reset = "Reset",
    colModule = "Module",
    colYours = "Your copy",
    colKitn = "KitnUI %s",
}

local list
local rowPool = {}
local view = { gen = 0 }
local Redraw, Resume

local function WF() return ns.Wizard.frame end

local function Font(parent, size, alpha)
    return EllesmereUI.MakeFont(parent, size, "", 1, 1, 1, alpha or 1)
end

local function SetVariant(btn, variant)
    if btn and ns.Wizard.SetButtonVariant then ns.Wizard:SetButtonVariant(btn, variant) end
end

local function Version()
    return ns.DisplayVersion and ns.DisplayVersion() or tostring(ns.version)
end

---------------------------------------------------------------------------------
-- What a row says
---------------------------------------------------------------------------------

local function Changed(row)
    local e = view.kitn and view.kitn[row.id]
    return e ~= nil and not row.off and (e.noBase == true or e.count > 0)
end

-- The read-only list is the Profile Update wizard's step once nothing waits.
local function ReadOnly()
    return view.mode == "updater" and view.state == "current"
end

local function Tickable(row)
    if not view.ticked or ReadOnly() then return false end
    -- In state "current" a tick takes a skipped update, so a part needs its
    -- waiting record as well as a change: without one (the stamp's base gone)
    -- a take would replace the part and record nothing.
    if view.state == "current" and not ns.EUIRowRecord(ns.db and ns.db.euiRowAt, row.id) then return false end
    return Changed(row)
end

local function KitnText(row)
    if row.off then return TEXT.off end
    local e = view.kitn and view.kitn[row.id]
    if not e then return TEXT.counting end
    if e.noBase then return TEXT.replaces end
    if view.state == "current" then
        return e.count > 0 and TEXT.waiting:format(e.count) or TEXT.upToDate
    end
    if e.count == 1 then return TEXT.changesOne end
    if e.count > 1 then return TEXT.changesMany:format(e.count) end
    return TEXT.noChanges
end

local function YoursText(row)
    if row.off or view.yours == false then return TEXT.refused end
    local settle = ns.EUIPartSettle and ns.EUIPartSettle(row.id)
    if settle == "pending" or settle == "due" then return TEXT.reloadToCheck end
    local e = view.yours and view.yours[row.id]
    if not e then return TEXT.checking end
    if e.noBase then return e.count > 0 and TEXT.differs or TEXT.matches end
    if e.count > 0 then return TEXT.yours:format(e.count) end
    return TEXT.asInstalled
end

local function ChangedCount()
    local n = 0
    for _, row in ipairs(view.inputs.rows) do
        if Changed(row) then n = n + 1 end
    end
    return n
end

local function IntroText()
    local T = ns.EUI_UPDATE_TEXT
    if not view.inputs then
        if ns.EUIDecodesReady() and ns.EUIDecodeCache.failedN then return T.importFail end
        return T.preparing
    end
    if view.mode == "modules" then
        return view.state == "current" and TEXT.introModulesCurrent or TEXT.introModulesUpdate
    end
    if view.state == "current" then return TEXT.introCurrent end
    if not view.kitn then return T.preparing end
    return TEXT.introUpdate:format(Version(), ChangedCount())
end

---------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------

-- A decode another EllesmereUI decode cancelled never reports, so a click that
-- finds none ready starts them again, as the standard page's button does.
local function RefuseAndRecover(why)
    if why == ns.EUI_UPDATE_TEXT.preparing and not ns.EUIDecodesReady() then
        ns.EUIStartDecodes(ns.EUIOnDecodesReady)
    end
    ns.EUIToast("warn", why)
end

local function OnUpdateClick()
    local T = ns.EUI_UPDATE_TEXT
    if not view.ticked then
        if ns.EUIDecodesReady() and ns.EUIDecodeCache.failedN then
            ns.EUIToast("warn", T.importFail)
        else
            RefuseAndRecover(T.preparing)
        end
        return
    end
    -- An update with no part left to change (each one reset, or a version
    -- that changes nothing counted) still moves the stamp, so it runs whole.
    local ticked = view.ticked
    if view.state == "update" and ChangedCount() == 0 then
        ticked = nil
    elseif next(ticked) == nil then
        ns.EUIToast("warn", T.noneTicked)
        return
    end
    local plan, why = ns.EUIPrepareUpdate(ticked)
    if not plan then
        RefuseAndRecover(why)
        return
    end
    ns.EUIConfirmUpdate(plan)
end

local function OnResetClick(row)
    local plan, why = ns.EUIPrepareReset(row.id, view.context)
    if not plan then
        RefuseAndRecover(why)
        return
    end
    ns.EUIConfirmUpdate(plan)
end

local function TickAll()
    for _, row in ipairs(view.inputs.rows) do
        if Tickable(row) then view.ticked[row.id] = true end
    end
    Redraw()
end

---------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------

local function ShowTip(cell, title, entry, skippedIn)
    if not (GameTooltip and entry and entry.groups and #entry.groups > 0) then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    if skippedIn then GameTooltip:AddLine(TEXT.tipSkipped:format(skippedIn), AMBER[1], AMBER[2], AMBER[3]) end
    for _, line in ipairs(ns.EUITooltipLines(entry)) do
        if line.header then
            GameTooltip:AddLine(line.text, 1, 1, 1)
        else
            GameTooltip:AddLine("  " .. line.text, 0.75, 0.75, 0.75)
        end
    end
    GameTooltip:Show()
end

local function RowEnter(r)
    r.hover:Show()
    if view.mode == "modules" and view.inputs and r.row and not r.row.off then r.reset:Show() end
end

-- Entering a cell leaves the row, so the row's own hover state is read off the
-- cursor rather than the event.
local function RowLeave(r)
    if GameTooltip then GameTooltip:Hide() end
    if r:IsMouseOver() then return end
    r.hover:Hide()
    r.reset:Hide()
end

local function Cell(r, width)
    local cell = CreateFrame("Button", nil, r)
    cell:SetSize(width, ROW_H)
    cell.text = Font(cell, 12, 0.85)
    cell.text:SetPoint("LEFT")
    cell.text:SetJustifyH("LEFT")
    cell:SetScript("OnLeave", function() RowLeave(r) end)
    return cell
end

local function BuildRow(i)
    local r = CreateFrame("Button", nil, list)
    r.hover = r:CreateTexture(nil, "BACKGROUND")
    r.hover:SetAllPoints()
    r.hover:SetColorTexture(1, 1, 1, 0.05)
    r.hover:Hide()
    r.box = r:CreateTexture(nil, "ARTWORK")
    r.box:SetSize(14, 14)
    r.box:SetPoint("LEFT", 0, 0)
    r.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(14, 14)
    r.check:SetPoint("CENTER", r.box)
    r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.name = Font(r, 13, 1)
    r.name:SetPoint("LEFT", 22, 0)
    r.sub = Font(r, 11, 0.45)
    r.sub:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)

    r.yours = Cell(r, 115)
    r.yours:SetPoint("LEFT", r, "LEFT", YOURS_X, 0)
    r.yours:SetScript("OnEnter", function(cell)
        RowEnter(r)
        local row = r.row
        local entry = row and view.yours and view.yours[row.id]
        if entry and entry.count > 0 and YoursText(row) ~= TEXT.reloadToCheck then
            ShowTip(cell, row.label .. " - " .. YoursText(row), entry)
        end
    end)
    r.kitn = Cell(r, 120)
    r.kitn:SetScript("OnEnter", function(cell)
        RowEnter(r)
        local row = r.row
        local entry = row and view.kitn and view.kitn[row.id]
        if not (entry and entry.count > 0) then return end
        local rec = ns.EUIRowRecord(ns.db and ns.db.euiRowAt, row.id)
        ShowTip(cell, TEXT.tipTitle:format(row.label, entry.count), entry, rec and rec.kitn)
    end)

    r.reset = CreateFrame("Button", nil, r)
    r.reset:SetSize(50, ROW_H)
    r.reset:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.reset.text = Font(r.reset, 12, 0.9)
    r.reset.text:SetPoint("RIGHT")
    r.reset.text:SetText(TEXT.reset)
    r.reset:SetScript("OnEnter", function() RowEnter(r) end)
    r.reset:SetScript("OnLeave", function() RowLeave(r) end)
    r.reset:SetScript("OnClick", function()
        if r.row then OnResetClick(r.row) end
    end)
    r.reset:Hide()

    r:SetScript("OnEnter", function() RowEnter(r) end)
    r:SetScript("OnLeave", function() RowLeave(r) end)
    r:SetScript("OnClick", function()
        if not (r._tickable and r.row) then return end
        local id = r.row.id
        view.ticked[id] = not view.ticked[id] or nil
        Redraw()
    end)
    rowPool[i] = r
    return r
end

local function BuildList()
    if list then return end
    local f = WF()
    list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", f, "TOPLEFT", CONTENT_X, LIST_TOP)
    list:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", CONTENT_X + CONTENT_W, LIST_BOTTOM)
    -- Hidden with the wizard or the whole UI, as well as by a page change: the
    -- new generation stops the walk and drops a deferred player read before it
    -- can toast, and the mark tells the next show to restart what was cut short.
    list:SetScript("OnHide", function()
        view.gen = view.gen + 1
        view.cut = true
        if GameTooltip then GameTooltip:Hide() end
    end)
    list:SetScript("OnShow", function() Resume() end)

    list.intro = Font(list, 13, 0.9)
    list.intro:SetPoint("TOPLEFT")
    list.intro:SetWidth(CONTENT_W)
    list.intro:SetJustifyH("LEFT")

    list.head = CreateFrame("Frame", nil, list)
    list.head:SetSize(CONTENT_W, 16)
    list.head:SetPoint("TOPLEFT", list.intro, "BOTTOMLEFT", 0, -10)
    list.colModule = Font(list.head, 11, 0.5)
    list.colModule:SetPoint("LEFT", 22, 0)
    list.colModule:SetText(TEXT.colModule)
    list.colYours = Font(list.head, 11, 0.5)
    list.colYours:SetPoint("LEFT", YOURS_X, 0)
    list.colYours:SetText(TEXT.colYours)
    list.colKitn = Font(list.head, 11, 0.5)

    list.sep = list:CreateTexture(nil, "ARTWORK")
    list.sep:SetColorTexture(1, 1, 1, 0.12)
    list.sep:SetHeight(1)
    list.sep:SetWidth(CONTENT_W)

    list.split = Font(list, 12, 1)
    list.split:SetTextColor(AMBER[1], AMBER[2], AMBER[3])
    list.split:SetJustifyH("LEFT")
    list.split:SetPoint("BOTTOMLEFT", f.Option1, "TOPLEFT", 0, 10)
    list.splitButton = CreateFrame("Button", nil, list)
    list.splitButton:SetSize(120, 20)
    ns.Wizard:StyleButton(list.splitButton, "", 12, function()
        local target = list.splitButton._target
        if target and view.ticked then
            view.ticked[target] = true
            Redraw()
        end
    end)
    list.splitButton:SetPoint("LEFT", list.split, "RIGHT", 8, 0)
    SetVariant(list.splitButton, "selectable")
    list:Hide()
end

---------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------

local function DrawRows()
    for _, r in ipairs(rowPool) do r:Hide() end
    list.sep:Hide()
    local modules = view.mode == "modules"
    local kitnX = modules and KITN_X_MODULES or KITN_X_UPDATER
    list.colYours:SetShown(modules)
    list.colKitn:ClearAllPoints()
    list.colKitn:SetPoint("LEFT", kitnX, 0)
    list.colKitn:SetText(TEXT.colKitn:format(Version()))
    if not view.inputs then
        list.head:Hide()
        return
    end
    list.head:Show()

    local rows = view.inputs.rows
    -- Every row fits the content height: 20 px down to 14 when there are many.
    local room = list:GetHeight() - list.intro:GetStringHeight() - 10 - list.head:GetHeight() - 8
    local rowH = math.max(ROW_H_MIN, math.min(ROW_H, math.floor(room / math.max(#rows, 1))))
    local y = -2
    for i, row in ipairs(rows) do
        local r = rowPool[i] or BuildRow(i)
        if row.id == "general" then
            y = y - 6
            list.sep:ClearAllPoints()
            list.sep:SetPoint("TOPLEFT", list.head, "BOTTOMLEFT", 0, y + 3)
            list.sep:Show()
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", list.head, "BOTTOMLEFT", 0, y)
        r:SetSize(CONTENT_W, rowH)
        y = y - rowH
        r.row = row

        local tickable = Tickable(row)
        r._tickable = tickable
        r.box:SetShown(tickable)
        r.check:SetShown(tickable and view.ticked[row.id] == true)
        r.name:SetText(row.label)
        r.sub:SetText(row.sub or "")
        local subRoom = (modules and YOURS_X or kitnX) - 22 - r.name:GetStringWidth() - 12
        r.sub:SetWidth(math.max(1, subRoom))
        r.sub:SetShown(row.sub ~= nil and subRoom > 20)
        r.yours:SetShown(modules)
        r.yours.text:SetText(modules and YoursText(row) or "")
        r.kitn:ClearAllPoints()
        r.kitn:SetPoint("LEFT", r, "LEFT", kitnX, 0)
        r.kitn.text:SetText(KitnText(row))
        r.hover:Hide()
        r.reset:Hide()
        local faint = row.off or (modules and view.state == "current" and view.ticked ~= nil and not tickable)
        r:SetAlpha(faint and 0.45 or 1)
        r:Show()
    end
end

local function DrawSplit()
    list.split:Hide()
    list.splitButton:Hide()
    if not (view.ticked and view.inputs) or ReadOnly() then return end
    local inputs = view.inputs
    local splits = ns.EUISplitLinks(inputs.N, inputs.rows, view.ticked, inputs.keyToFolder)
    local first = splits[1]
    if not first then return end
    local T = ns.EUI_UPDATE_TEXT
    list.split:SetText(T.split:format(first.child.label, first.target.label)
        .. (#splits > 1 and T.splitMore:format(#splits - 1) or ""))
    list.split:Show()
    if Tickable(first.target) then
        local b = list.splitButton
        b._target = first.target.id
        if b._lbl then
            b._lbl:SetText(TEXT.tickToo:format(first.target.label))
            b:SetWidth(math.max(80, b._lbl:GetStringWidth() + 16))
        end
        b:Show()
    end
end

local function DrawButtons()
    local W, f = ns.Wizard, WF()
    W:HideOptions()
    if ReadOnly() then
        ns.EUIDrawRestoreSlot(1)
        SetVariant(f.Next, "primary")
        return
    end
    if not view.ticked then
        W:SetOption(1, ns.EUI_UPDATE_TEXT.preparing, OnUpdateClick)
        SetVariant(f.Option1, "primary")
        ns.EUIDrawRestoreSlot(2)
        return
    end
    local ticked, changed = 0, ChangedCount()
    for _, row in ipairs(view.inputs.rows) do
        if view.ticked[row.id] then ticked = ticked + 1 end
    end
    local noBase = view.inputs.O == nil
    local slot = 2
    if view.state == "current" then
        W:SetOption(1, TEXT.takeSkipped:format(ticked), OnUpdateClick, 12)
        SetVariant(f.Option1, ticked > 0 and "primary" or "ghost")
    elseif changed == 0 or (view.mode == "updater" and ticked == changed) then
        W:SetOption(1, noBase and TEXT.updateAllNoBase or TEXT.updateAll, OnUpdateClick, 12)
        SetVariant(f.Option1, "primary")
    else
        W:SetOption(1, (noBase and TEXT.replaceTicked or TEXT.updateTicked):format(ticked), OnUpdateClick, 12)
        SetVariant(f.Option1, "primary")
        if view.mode == "updater" then
            W:SetOption(2, TEXT.tickAll, TickAll, 12)
            SetVariant(f.Option2, "selectable")
            slot = 3
        end
    end
    f.Option1:SetWidth(200)
    ns.EUIDrawRestoreSlot(slot)
end

Redraw = function()
    if not (list and list:IsShown()) then return end
    list.intro:SetText(IntroText())
    DrawRows()
    DrawSplit()
    DrawButtons()
end

---------------------------------------------------------------------------------
-- Counting off the frame budget
---------------------------------------------------------------------------------

-- The first step runs on the frame after the caller's, never inside a page
-- draw. Dev mode prints the worst frame and the setup's cost ("prep"): the
-- time of every step that began before the walk's seeding had finished.
local function Pump(walker, gen, onDone)
    local worst, prep, steps, total, worstUnits, worstKB = 0, 0, 0, 0, 0, 0
    local function step()
        local f = WF()
        if view.gen ~= gen or not (f and f:IsVisible()) then return end
        local preparing = not walker.prepared
        local kb = collectgarbage("count")
        local t0 = debugprofilestop()
        local done = walker:Step(EUI_DIFF_STEPS)
        local spent = debugprofilestop() - t0
        steps, total = steps + 1, total + spent
        if spent > worst then
            worst, worstUnits, worstKB = spent, walker.units, collectgarbage("count") - kb
        end
        if preparing then prep = prep + spent end
        if not done then
            C_Timer.After(0, step)
            return
        end
        if ns.db and ns.db.devMode then
            print(ns.title .. (" count walk: worst frame %.2f ms (%d units, %+.0f KB), prep %.2f ms, %d steps, mean %.2f ms")
                :format(worst, worstUnits, worstKB, prep, steps, total / steps))
        end
        onDone(walker.result)
    end
    C_Timer.After(0, step)
end

-- "Your copy": the player's profile read a frame after the page draws, then
-- walked against the settled composite, which is the composite base wherever a
-- part has no snapshot, KitnUI's own held settings left out, then and now.
local function StartPlayerRead()
    local gen = view.gen
    C_Timer.After(0, function()
        if view.gen ~= gen then return end
        local t0 = ns.db and ns.db.devMode and debugprofilestop()
        local side, why = ns.EUIReadPlayer()
        if not side then
            view.yours = false
            Redraw()
            ns.EUIToast("warn", why)
            return
        end
        view.context = ns.EUIPlayerContext()
        local held = view.context.held
        if ns.EUISettledHeld then held = ns.EUISettledHeld(held) end
        local walker = ns.EUIRowDiff(side.S or side.O or side.N, side.P, side.rows, side.keyToFolder, {
            player = true,
            noBase = side.O == nil,
            missing = side.missing,
            fallback = side.N,
            held = held,
            defaults = view.context.defaults,
            unlock = view.context.unlock,
        })
        if t0 then
            print(ns.title .. (" player read: %.1f ms"):format(debugprofilestop() - t0))
        end
        Pump(walker, gen, function(result)
            view.yours = result
            Redraw()
        end)
    end)
end

local function StartKitnWalk()
    local inputs = view.inputs
    local walker = ns.EUIRowDiff(inputs.O, inputs.N, inputs.rows, inputs.keyToFolder, {
        missing = inputs.missing,
        unlock = ns.EUIUnlockLabels(),
    })
    Pump(walker, view.gen, function(result)
        view.kitn = result
        view.ticked = {}
        if view.state == "update" then
            for _, row in ipairs(inputs.rows) do
                if Changed(row) then view.ticked[row.id] = true end
            end
        end
        Redraw()
        if view.mode == "modules" then StartPlayerRead() end
    end)
end

-- Shown again after a hide, without a page draw. Hiding the wizard cancels the
-- decodes the player read needs, so they start again and the restart waits
-- for them in ns.EUIListRefresh.
Resume = function()
    if not view.cut then return end
    if ns.EUIDecodesReady() then
        ns.EUIListRefresh()
    else
        ns.EUIStartDecodes(ns.EUIOnDecodesReady)
    end
end

---------------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------------

-- Draws the list from the decode cache as it stands; the decode callback calls
-- it again when they land. A count or read a hide cut short starts over under
-- a new generation, so a step still queued from before cannot run beside it.
-- The mark is spent first, so a second call restarts nothing.
function ns.EUIListRefresh()
    if not (list and list:IsShown()) then return end
    if ns.EUIDecodesReady() then
        local cut = view.cut
        view.cut = nil
        if not view.inputs then
            view.inputs = ns.EUIPageInputs()
            if view.inputs then StartKitnWalk() end
        elseif cut and not view.kitn then
            view.gen = view.gen + 1
            StartKitnWalk()
        elseif cut and view.mode == "modules" and view.yours == nil then
            view.gen = view.gen + 1
            StartPlayerRead()
        end
    end
    Redraw()
end

-- A snapshot landed: a "Your copy" read or refusal from before it is read
-- again. While KitnUI's walk runs, the read it starts comes after the capture.
function ns.EUISettleLanded()
    if not (list and list:IsShown() and view.mode == "modules" and view.kitn) then return end
    view.gen = view.gen + 1
    view.yours = nil
    Redraw()
    if list:IsVisible() then StartPlayerRead() else view.cut = true end
end

function ns.EUIListShowing()
    return list ~= nil and list:IsShown()
end

-- The new generation stops any walk still running. What the list read,
-- decoded copies of whole profiles, is dropped rather than kept for the next
-- open, which reads everything afresh.
function ns.EUIHideModuleList()
    view.gen = view.gen + 1
    view.inputs, view.kitn, view.yours, view.ticked, view.context = nil, nil, nil, nil, nil
    for _, r in ipairs(rowPool) do r.row = nil end
    if list then list:Hide() end
end

local function Open(mode)
    BuildList()
    view.gen = view.gen + 1
    view.mode = mode
    view.state = ns.EUIUpdateState()
    view.inputs, view.kitn, view.yours, view.ticked, view.context = nil, nil, nil, nil, nil
    -- The decodes start below, so the show must not start them as well.
    view.cut = nil
    list:Show()
    ns.EUIStartDecodes(ns.EUIOnDecodesReady)
    ns.EUIListRefresh()
end

-- The Profile Update wizard's EllesmereUI step, in states "update" and "current".
function ns.EUIUpdaterPage()
    WF().SubTitle:SetText("EllesmereUI")
    Open("updater")
end

-- The install wizard's hidden page, drawn by W:ShowSubPage.
function ns.EUIModulesPage()
    Open("modules")
end

function ns.EUIShowModules()
    ns.Wizard:ShowSubPage(MODULES_TITLE, ns.EUIModulesPage)
end
