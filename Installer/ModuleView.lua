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

local ROW_H_MAX, ROW_H_MIN = 26, 14
-- The intro starts on the line Desc1 uses, below the header rule in the art;
-- the list ends 10 px above the action buttons.
local LIST_TOP, LIST_BOTTOM = -116, 132
local CONTENT_X, CONTENT_W = 200, 520
local YOURS_X, KITN_X_MODULES, KITN_X_UPDATER = 252, 372, 390
-- Reset, shown on hover at the row's right edge on the Modules page, keeps a
-- region of its own: there the KitnUI cell's hover area ends 4 px before it.
-- The cell's badge and text still draw at their full width.
local KITN_W, RESET_W = 120, 50
local KITN_W_MODULES = CONTENT_W - KITN_X_MODULES - RESET_W - 4
local MODULES_TITLE = "EllesmereUI Modules"
local AMBER = { 1, 0.8, 0.2 }
-- Stand-ins for a measurement that cannot be read: the list's height (the
-- wizard's 560 less both ends), a two-line intro, one line of the notice.
local LIST_H_FALLBACK, INTRO_H_FALLBACK, NOTICE_LINE_H = 312, 36, 16
local NOTICE_MIN_H, NOTICE_GAP = 28, 8
-- A badge is 18 high, or 2 px shorter than its row, so adjacent badges never touch.
local BADGE_H, BADGE_PAD = 18, 8
-- Tick all is drawn narrow. Beside Restore's 240 px "switch" state the update
-- button narrows too, so the three fit the 520 px content column.
local TICK_ALL_W, UPDATE_W_BESIDE_SWITCH = 100, 160
local BACKING_FILL = { 0.03, 0.01, 0.02, 0.80 }
-- The badges with a color of their own; "kitn" follows the accent and
-- "amber" the warning amber, both read on each draw.
local BADGES = {
    you = { fill = { 0.47, 0.67, 1, 0.20 }, text = { 0.71, 0.81, 1, 1 } },
    off = { fill = { 1, 1, 1, 0.09 }, text = { 1, 1, 1, 0.55 } },
}

local TEXT = {
    introUpdate = "KitnUI %s changes %d parts of EllesmereUI. Everything is ticked; untick a part to keep it as you have it. Hover a count to see what changes.",
    introUpdateOne = "KitnUI %s changes 1 part of EllesmereUI. Everything is ticked; untick a part to keep it as you have it. Hover a count to see what changes.",
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
    tipTitleOne = "%s - changes 1 setting",
    tipYours = "%s - %d changed by you",
    tipSkipped = "Skipped in KitnUI %s",
    updateAll = "Update Profile",
    updateAllNoBase = "Update (replaces your changes)",
    updateTicked = "Update ticked (%d)",
    replaceTicked = "Replace ticked (%d)",
    tickAll = "Tick all",
    takeSkipped = "Take skipped (%d)",
    tickToo = "Tick %s too",
    reset = "Reset",
    colModule = "MODULE",
    colYours = "YOUR COPY",
    colKitn = "KITNUI %s",
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

-- A font measurement, or the stand-in when it is secret or not a number.
local function Measure(value, fallback)
    local isv = issecretvalue
    if (isv and isv(value)) or type(value) ~= "number" then return fallback end
    return value
end

-- A name the game gave, or nil when it is missing, secret or empty.
local function UsableName(name)
    local isv = issecretvalue
    if (isv and isv(name)) or type(name) ~= "string" or name == "" then return nil end
    return name
end

-- An ID the game's lookups accept. The IDs come from saved profile data, and
-- an out-of-range one would stop the count walk with an error.
local function ValidID(id)
    return type(id) == "number" and id >= 1 and id < 2147483648 and id % 1 == 0
end

-- The count walks' name lookups (ModuleRows.lua, EUIRowDiff opts.names).
local NAMES = {
    spec = function(id)
        if not ValidID(id) or type(GetSpecializationInfoByID) ~= "function" then return nil end
        local _, name, _, _, _, _, className = GetSpecializationInfoByID(id)
        name, className = UsableName(name), UsableName(className)
        if name and className then return name .. " " .. className end
        return name
    end,
    spell = function(id)
        if not ValidID(id) or not (C_Spell and C_Spell.GetSpellName) then return nil end
        return UsableName(C_Spell.GetSpellName(id))
    end,
}

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

-- A cell's text and its kind: "kitn", "you", "amber" or "off" for a badge,
-- "plain" for grey text.
local function KitnText(row)
    if row.off then return TEXT.off, "off" end
    local e = view.kitn and view.kitn[row.id]
    if not e then return TEXT.counting, "plain" end
    if e.noBase then return TEXT.replaces, "amber" end
    if view.state == "current" then
        if e.count > 0 then return TEXT.waiting:format(e.count), "amber" end
        return TEXT.upToDate, "plain"
    end
    if e.count == 1 then return TEXT.changesOne, "kitn" end
    if e.count > 1 then return TEXT.changesMany:format(e.count), "kitn" end
    return TEXT.noChanges, "plain"
end

local function YoursText(row)
    if row.off or view.yours == false then return TEXT.refused, "plain" end
    local settle = ns.EUIPartSettle and ns.EUIPartSettle(row.id)
    if settle == "pending" or settle == "due" then return TEXT.reloadToCheck, "plain" end
    local e = view.yours and view.yours[row.id]
    if not e then return TEXT.checking, "plain" end
    if e.noBase then return e.count > 0 and TEXT.differs or TEXT.matches, "plain" end
    if e.count > 0 then return TEXT.yours:format(e.count), "you" end
    return TEXT.asInstalled, "plain"
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
    local changed = ChangedCount()
    if changed == 1 then return TEXT.introUpdateOne:format(Version()) end
    return TEXT.introUpdate:format(Version(), changed)
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
    cell:SetSize(width, ROW_H_MIN)
    cell._w = width
    cell.badge = cell:CreateTexture(nil, "BACKGROUND")
    cell.badge:SetPoint("LEFT")
    cell.badge:SetHeight(BADGE_H)
    cell.badge:Hide()
    cell.text = Font(cell, 12, 1)
    cell.text:SetPoint("LEFT")
    cell.text:SetJustifyH("LEFT")
    cell:SetScript("OnLeave", function() RowLeave(r) end)
    return cell
end

-- A cell's text in its kind: on a badge sized to the text, or plain grey.
local function PaintCell(cell, text, kind)
    local t, badge = cell.text, cell.badge
    t:SetText(text)
    t:ClearAllPoints()
    if kind == "kitn" then
        local a = ns.Wizard:Accent()
        badge:SetColorTexture(a[1], a[2], a[3], 0.26)
        t:SetTextColor(a[1] + (1 - a[1]) * 0.56, a[2] + (1 - a[2]) * 0.56, a[3] + (1 - a[3]) * 0.56, 1)
    elseif kind == "amber" then
        local f, c = ns.WARN_AMBER, ns.WARN_TEXT
        badge:SetColorTexture(f[1], f[2], f[3], 0.20)
        t:SetTextColor(c[1], c[2], c[3], 1)
    elseif BADGES[kind] then
        local b = BADGES[kind]
        badge:SetColorTexture(b.fill[1], b.fill[2], b.fill[3], b.fill[4])
        t:SetTextColor(b.text[1], b.text[2], b.text[3], b.text[4])
    else
        badge:Hide()
        t:SetTextColor(1, 1, 1, 0.62)
        t:SetPoint("LEFT")
        return
    end
    t:SetPoint("LEFT", BADGE_PAD, 0)
    badge:SetWidth(Measure(t:GetStringWidth(), cell._w - 2 * BADGE_PAD) + 2 * BADGE_PAD)
    badge:Show()
end

local function BuildRow(i)
    local r = CreateFrame("Button", nil, list)
    r.stripe = r:CreateTexture(nil, "BACKGROUND", nil, -1)
    r.stripe:SetPoint("TOPLEFT", -8, 0)
    r.stripe:SetPoint("BOTTOMRIGHT", 8, 0)
    r.stripe:SetColorTexture(1, 1, 1, 0.035)
    r.hover = r:CreateTexture(nil, "BACKGROUND")
    r.hover:SetPoint("TOPLEFT", -8, 0)
    r.hover:SetPoint("BOTTOMRIGHT", 8, 0)
    r.hover:SetColorTexture(1, 1, 1, 0.06)
    r.hover:Hide()
    -- Without the check-mark atlas the accent fill alone shows the tick.
    r.box = CreateFrame("Frame", nil, r)
    r.box:SetSize(14, 14)
    r.box:SetPoint("LEFT", 0, 0)
    r.box.fill = r.box:CreateTexture(nil, "BACKGROUND")
    r.box.fill:SetAllPoints()
    r.box.fill:Hide()
    if EllesmereUI.MakeBorder then
        r.box.border = EllesmereUI.MakeBorder(r.box, 1, 1, 1, 0.5, EllesmereUI.PanelPP)
    end
    r.box.mark = r.box:CreateTexture(nil, "OVERLAY")
    r.box.mark:SetSize(12, 12)
    r.box.mark:SetPoint("CENTER")
    r.box.markOk = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil
        and C_Texture.GetAtlasInfo("checkmark-minimal") ~= nil
    if r.box.markOk then
        r.box.mark:SetAtlas("checkmark-minimal")
        r.box.mark:SetDesaturated(true)
        r.box.mark:SetVertexColor(1, 1, 1, 1)
    end
    r.box.mark:Hide()
    r.name = Font(r, 15, 1)
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
            local title = entry.noBase and (row.label .. " - " .. TEXT.differs)
                or TEXT.tipYours:format(row.label, entry.count)
            ShowTip(cell, title, entry)
        end
    end)
    r.kitn = Cell(r, KITN_W)
    r.kitn:SetScript("OnEnter", function(cell)
        RowEnter(r)
        local row = r.row
        local entry = row and view.kitn and view.kitn[row.id]
        if not (entry and entry.count > 0) then return end
        local rec = ns.EUIRowRecord(ns.db and ns.db.euiRowAt, row.id)
        local title = entry.count == 1 and TEXT.tipTitleOne:format(row.label)
            or TEXT.tipTitle:format(row.label, entry.count)
        ShowTip(cell, title, entry, rec and rec.kitn)
    end)

    r.reset = CreateFrame("Button", nil, r)
    r.reset:SetSize(RESET_W, ROW_H_MIN)
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

    list.intro = Font(list, 14, 0.92)
    list.intro:SetPoint("TOPLEFT")
    list.intro:SetWidth(CONTENT_W)
    list.intro:SetJustifyH("LEFT")

    -- The split-link notice: an amber band under the intro, holding the button
    -- that ticks the part which keeps the player's copy.
    local warn, warnText = ns.WARN_AMBER, ns.WARN_TEXT
    list.notice = CreateFrame("Frame", nil, list)
    list.notice:SetPoint("TOPLEFT", list.intro, "BOTTOMLEFT", 0, -10)
    list.notice:SetSize(CONTENT_W, NOTICE_MIN_H)
    local noticeFill = list.notice:CreateTexture(nil, "BACKGROUND")
    noticeFill:SetAllPoints()
    noticeFill:SetColorTexture(warn[1], warn[2], warn[3], 0.12)
    if EllesmereUI.MakeBorder then
        EllesmereUI.MakeBorder(list.notice, warn[1], warn[2], warn[3], 0.45, EllesmereUI.PanelPP)
    end
    list.noticeText = Font(list.notice, 12, 1)
    list.noticeText:SetTextColor(warnText[1], warnText[2], warnText[3], 1)
    list.noticeText:SetJustifyH("LEFT")
    list.noticeText:SetWordWrap(true)
    list.noticeText:SetMaxLines(2)
    list.noticeText:SetPoint("LEFT", list.notice, "LEFT", 10, 0)
    list.splitButton = CreateFrame("Button", nil, list.notice)
    list.splitButton:SetSize(120, 20)
    ns.Wizard:StyleButton(list.splitButton, "", 12, function()
        local target = list.splitButton._target
        if target and view.ticked then
            view.ticked[target] = true
            Redraw()
        end
    end)
    list.splitButton:SetPoint("RIGHT", list.notice, "RIGHT", -4, 0)
    SetVariant(list.splitButton, "warn")
    list.notice:Hide()
    list.noticeH = 0

    -- The dark panel behind the heads and rows, so they read on the art. It
    -- sits at the list's own level, under the rows.
    list.backing = CreateFrame("Frame", nil, list)
    list.backing:SetFrameLevel(list:GetFrameLevel())
    local backingFill = list.backing:CreateTexture(nil, "BACKGROUND")
    backingFill:SetAllPoints()
    backingFill:SetColorTexture(BACKING_FILL[1], BACKING_FILL[2], BACKING_FILL[3], BACKING_FILL[4])
    if EllesmereUI.MakeBorder then
        list.backingBorder = EllesmereUI.MakeBorder(list.backing, 1, 1, 1, 0.16, EllesmereUI.PanelPP)
    end
    list.backing:Hide()

    list.head = CreateFrame("Frame", nil, list)
    list.head:SetSize(CONTENT_W, 16)
    list.colModule = Font(list.head, 10, 0.55)
    list.colModule:SetPoint("LEFT", 22, 0)
    list.colModule:SetText(TEXT.colModule)
    list.colYours = Font(list.head, 10, 0.55)
    list.colYours:SetPoint("LEFT", YOURS_X, 0)
    list.colYours:SetText(TEXT.colYours)
    list.colKitn = Font(list.head, 10, 0.55)

    -- On the heads' frame, so the panel at the list's level never covers it.
    list.sep = list.head:CreateTexture(nil, "ARTWORK")
    list.sep:SetColorTexture(1, 1, 1, 0.12)
    list.sep:SetHeight(1)
    list.sep:SetWidth(CONTENT_W)
    list:Hide()
end

---------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------

-- The band goes in before the rows: its height moves the heads and the row
-- height.
local function DrawNotice()
    local band, b = list.notice, list.splitButton
    band:Hide()
    list.noticeH = 0
    if not (view.ticked and view.inputs) or ReadOnly() then return end
    local inputs = view.inputs
    local splits = ns.EUISplitLinks(inputs.N, inputs.rows, view.ticked, inputs.keyToFolder)
    local first = splits[1]
    if not first then return end
    local T = ns.EUI_UPDATE_TEXT
    local room = CONTENT_W - 10 - 4
    if Tickable(first.target) then
        b._target = first.target.id
        local w = 80
        if type(b._lbl) == "table" then
            b._lbl:SetText(TEXT.tickToo:format(first.target.label))
            w = math.max(80, Measure(b._lbl:GetStringWidth(), 150) + 16)
        end
        b:SetWidth(w)
        b:Show()
        room = room - 8 - w
    else
        b:Hide()
    end
    -- Shown before its text is set: text set in a hidden frame can measure as
    -- the previous text until the frame lays out.
    band:Show()
    local t = list.noticeText
    t:SetWidth(room)
    t:SetText(T.split:format(first.child.label, first.target.label)
        .. (#splits > 1 and T.splitMore:format(#splits - 1) or ""))
    list.noticeH = math.max(NOTICE_MIN_H, Measure(t:GetStringHeight(), NOTICE_LINE_H) + 10)
    band:SetHeight(list.noticeH)
end

local function DrawRows()
    for _, r in ipairs(rowPool) do r:Hide() end
    list.sep:Hide()
    list.backing:Hide()
    local modules = view.mode == "modules"
    local kitnX = modules and KITN_X_MODULES or KITN_X_UPDATER
    list.colYours:SetShown(modules)
    list.colKitn:ClearAllPoints()
    list.colKitn:SetPoint("LEFT", kitnX, 0)
    list.colKitn:SetText(TEXT.colKitn:format(Version()))
    local above = 10 + Measure(list.intro:GetStringHeight(), INTRO_H_FALLBACK)
    list.head:ClearAllPoints()
    if list.noticeH > 0 then
        list.head:SetPoint("TOPLEFT", list.notice, "BOTTOMLEFT", 0, -NOTICE_GAP)
        above = above + list.noticeH + NOTICE_GAP
    else
        list.head:SetPoint("TOPLEFT", list.intro, "BOTTOMLEFT", 0, -10)
    end
    if not view.inputs then
        list.head:Hide()
        return
    end
    list.head:Show()

    local rows = view.inputs.rows
    -- Every row fits the room under the heads (18) and the General gap (6):
    -- 26 px down to 14 when there are many.
    local room = Measure(list:GetHeight(), LIST_H_FALLBACK) - above - 18 - 6
    local rowH = math.max(ROW_H_MIN, math.min(ROW_H_MAX, math.floor(room / math.max(#rows, 1))))
    local badgeH = math.min(BADGE_H, rowH - 2)
    local accent = ns.Wizard:Accent()
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
        local ticked = tickable and view.ticked[row.id] == true
        r.box:SetShown(tickable)
        if ticked then
            r.box.fill:SetColorTexture(accent[1], accent[2], accent[3], 1)
            r.box.fill:Show()
        else
            r.box.fill:Hide()
        end
        if type(r.box.border) == "table" and r.box.border.SetColor then
            if ticked then
                r.box.border:SetColor(accent[1], accent[2], accent[3], 1)
            else
                r.box.border:SetColor(1, 1, 1, 0.5)
            end
        end
        r.box.mark:SetShown(ticked and r.box.markOk)
        r.stripe:SetShown(i % 2 == 0)
        r.name:SetText(row.label)
        r.sub:SetText(row.sub or "")
        local subRoom = (modules and YOURS_X or kitnX) - 22 - Measure(r.name:GetStringWidth(), CONTENT_W) - 12
        r.sub:SetWidth(math.max(1, subRoom))
        r.sub:SetShown(row.sub ~= nil and subRoom > 20)
        r.yours:SetShown(modules)
        r.yours:SetHeight(rowH)
        r.yours.badge:SetHeight(badgeH)
        if modules then PaintCell(r.yours, YoursText(row)) end
        r.kitn:ClearAllPoints()
        r.kitn:SetPoint("LEFT", r, "LEFT", kitnX, 0)
        r.kitn:SetSize(modules and KITN_W_MODULES or KITN_W, rowH)
        r.kitn.badge:SetHeight(badgeH)
        PaintCell(r.kitn, KitnText(row))
        r.reset:SetHeight(rowH)
        r.hover:Hide()
        r.reset:Hide()
        r:Show()
    end
    list.backing:ClearAllPoints()
    list.backing:SetPoint("TOPLEFT", list.head, "TOPLEFT", -8, 6)
    list.backing:SetPoint("BOTTOMRIGHT", list.head, "BOTTOMRIGHT", 8, y - 6)
    if type(list.backingBorder) == "table" and list.backingBorder.SetColor then
        list.backingBorder:SetColor(accent[1], accent[2], accent[3], 0.16)
    end
    list.backing:Show()
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
    local width, offerTickAll = 200, false
    if view.state == "current" then
        W:SetOption(1, TEXT.takeSkipped:format(ticked), OnUpdateClick, 12)
        SetVariant(f.Option1, ticked > 0 and "primary" or "ghost")
    elseif changed == 0 or (view.mode == "updater" and ticked == changed) then
        W:SetOption(1, noBase and TEXT.updateAllNoBase or TEXT.updateAll, OnUpdateClick, 12)
        SetVariant(f.Option1, "primary")
        if noBase then width = 240 end
    else
        W:SetOption(1, (noBase and TEXT.replaceTicked or TEXT.updateTicked):format(ticked), OnUpdateClick, 12)
        SetVariant(f.Option1, "primary")
        offerTickAll = view.mode == "updater"
    end
    f.Option1:SetWidth(width)
    local slot = ns.EUIDrawRestoreSlot(2) and 3 or 2
    if offerTickAll then
        W:SetOption(slot, TEXT.tickAll, TickAll, 12)
        f["Option" .. slot]:SetWidth(TICK_ALL_W)
        SetVariant(f["Option" .. slot], "selectable")
        if ns.EUIRestorable and ns.EUIRestorable() == "switch" then f.Option1:SetWidth(UPDATE_W_BESIDE_SWITCH) end
    end
end

Redraw = function()
    if not (list and list:IsShown()) then return end
    list.intro:SetText(IntroText())
    DrawNotice()
    DrawRows()
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
            names = NAMES,
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
        names = NAMES,
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
-- again, through the restart path, which waits for decodes a hide cancelled.
-- While KitnUI's walk runs, the read it starts comes after the capture.
function ns.EUISettleLanded()
    if not (list and list:IsShown() and view.mode == "modules" and view.kitn) then return end
    view.gen = view.gen + 1
    view.yours = nil
    view.cut = true
    if list:IsVisible() then ns.EUIListRefresh() else Redraw() end
end

function ns.EUIListShowing()
    return list ~= nil and list:IsShown()
end

-- Only the Modules page reads snapshots, so only its decodes take them in.
-- Every path that starts them for it shows the list first.
function ns.EUIListReadsSettled()
    return list ~= nil and list:IsShown() and view.mode == "modules"
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
