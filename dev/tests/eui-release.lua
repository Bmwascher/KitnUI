-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-release.lua                                             ║
-- ║  Purpose: Gate for what the installer lets go of: the part   ║
-- ║           list's reads when the list hides or the wizard     ║
-- ║           closes, and the plan an answered confirm held.     ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/eui-release.lua
--
-- Reachability is read off weak-keyed tables: after a full collection an
-- entry is left only while something else still reaches its key.

local failures = 0
local checks = 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
    end
end

local function eq(actual, expected, label)
    check(actual == expected, label, "got " .. tostring(actual) .. ", wanted " .. tostring(expected))
end

---------------------------------------------------------------------------------
-- Stubs
---------------------------------------------------------------------------------

local noop = function() end

-- Frames keep their scripts and their own shown flag. OnShow and OnHide run
-- only on a change, and a frame's own Hide clears the flag before OnHide
-- runs; a parent's hide is not modelled.
local Frame = {}
local frameMeta = { __index = function(_, key) return Frame[key] or noop end }
local function newFrame()
    return setmetatable({ scripts = {}, shown = true }, frameMeta)
end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown end
function Frame:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Frame:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Frame:SetShown(on)
    if on then self:Show() else self:Hide() end
end
function Frame:CreateTexture() return newFrame() end
function Frame:CreateFontString() return newFrame() end
function Frame:GetWidth() return 0 end
function Frame:GetHeight() return 0 end
function Frame:GetStringWidth() return 0 end
function Frame:GetStringHeight() return 0 end
function Frame:GetFrameLevel() return 0 end
function Frame:SetText(text) self.text = text end
function Frame:GetText() return self.text end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end

-- The last point set, so a test can read where a frame or font starts.
function Frame:SetPoint(...) self.point = { ... } end

-- Every frame and font the code builds, so a test can find one by what it holds.
local frames, fonts = {}, {}
_G.CreateFrame = function()
    local frame = newFrame()
    frames[#frames + 1] = frame
    return frame
end
_G.UIParent = newFrame()
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.C_Timer = { After = noop }
_G.InCombatLockdown = function() return false end
_G.UIFrameFadeIn = noop
_G.UIFrameFadeOut = noop
_G.PlaySound = noop
_G.SOUNDKIT = {}

-- Every options table a confirm was shown with, kept for good, as a popup
-- EllesmereUI discards on an accent change keeps its last one.
local popups = {}
_G.EllesmereUI = {
    MakeFont = function()
        local font = newFrame()
        fonts[#fonts + 1] = font
        return font
    end,
    MakeBorder = noop,
    SolidTex = noop,
    MakeStyledButton = function()
        local lbl = newFrame()
        fonts[#fonts + 1] = lbl
        return newFrame(), newFrame(), lbl
    end,
    ShowConfirmPopup = function(_, opts) popups[#popups + 1] = opts end,
}

local ns = { title = "KitnUI", version = "2.2.0", data = {} }
ns.UsesAltTheme = function() return false end
ns.DisplayVersion = function() return "2.2.0" end
ns.EUI_UPDATE_TEXT = { preparing = "Preparing..." }
ns.EUICancelDecodes = noop
ns.EUIStartDecodes = noop
ns.EUIDecodesReady = function() return true end
ns.EUIUpdateState = function() return "update" end
ns.EUIUnlockLabels = function() return {} end
ns.EUIRowDiff = function() return {} end

-- The list's inputs, a fresh table per read, known weakly.
local reads = setmetatable({}, { __mode = "k" })
local readCount = 0
ns.EUIPageInputs = function()
    readCount = readCount + 1
    local inputs = { rows = {}, N = {}, keyToFolder = {}, missing = {} }
    reads[inputs] = true
    return inputs
end
local function listHolds()
    collectgarbage("collect")
    return next(reads) ~= nil
end

local function loadChunk(path)
    local chunk, err = loadfile(path)
    if not chunk then
        print("FAIL  could not load " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", ns)
end

loadChunk("Installer/Wizard.lua")
loadChunk("Installer/Installer.lua")
loadChunk("Installer/ModuleView.lua")

---------------------------------------------------------------------------------
-- The part list lets go of what it read
---------------------------------------------------------------------------------

local W = ns.Wizard
W:Build()
local wizard = W.frame
check(wizard ~= nil, "the wizard builds against the stubs")
if not wizard then
    print(string.format("%d checks, %d failures", checks, failures))
    os.exit(1)
end

W:Show()
ns.EUIModulesPage()
eq(readCount, 1, "the list reads its inputs when it opens")
check(listHolds(), "an open list holds what it read")

-- Hidden with the whole UI, the wizard keeps its shown flag and only its
-- OnHide runs; the list restarts from what it read when the UI returns.
wizard.scripts.OnHide(wizard)
check(listHolds(), "a list hidden with the whole UI keeps what it read")

W:Hide()
check(not listHolds(), "closing the wizard lets go of what the list read")

W:Show()
ns.EUIModulesPage()
eq(readCount, 2, "an open after a close reads afresh")
check(listHolds(), "and holds what it read while it shows")

ns.EUIHideModuleList()
check(not listHolds(), "leaving the list's page lets go of what it read")

---------------------------------------------------------------------------------
-- An answered confirm lets go of its plan
---------------------------------------------------------------------------------

local plans = setmetatable({}, { __mode = "k" })
local function newPlan(mark)
    local plan = { kind = "update", mark = mark, inputs = {} }
    plans[plan] = mark
    return plan
end
local function reaches(mark)
    collectgarbage("collect")
    for _, m in pairs(plans) do
        if m == mark then return true end
    end
    return false
end

-- The acceptance. A plan carrying `fresh` asks to be confirmed again with it,
-- as one whose prediction moved while the confirm was open does.
local applied = {}
ns.EUIApplyUpdate = function(plan)
    applied[#applied + 1] = plan.mark
    local fresh = plan.fresh
    if fresh then
        plan.fresh = nil
        return "reconfirm", fresh
    end
    return true
end
ns.EUIConfirmText = function() return "confirm" end
ns.EUIUpdateToast = function() return "updated" end
ns.EUISkippedNote = noop
-- A success redraws the page the confirm came from; the Modules page counts.
local redraws = 0
W.subPage = noop
ns.EUIShowModules = function() redraws = redraws + 1 end

-- One answer with chat silenced: how many plans it applied, and the last.
local function answer(fn)
    local before = #applied
    local realPrint = _G.print
    _G.print = noop
    fn()
    _G.print = realPrint
    return #applied - before, applied[#applied]
end

ns.EUIConfirmUpdate(newPlan("confirmed"))
local shown = popups[#popups]
check(reaches("confirmed"), "a showing confirm reaches its plan")
local count, last = answer(shown.onConfirm)
eq(count, 1, "Confirm applies one plan")
eq(last, "confirmed", "the one the confirm showed")
eq(redraws, 1, "and the page redraws")
check(not reaches("confirmed"), "an answered confirm no longer reaches its plan")
count = answer(shown.onConfirm)
eq(count, 0, "a second Confirm from the same options applies nothing")

ns.EUIConfirmUpdate(newPlan("cancelled"))
shown = popups[#popups]
if shown.onCancel then shown.onCancel() end
check(not reaches("cancelled"), "a cancelled confirm no longer reaches its plan")

-- Escape and a click outside run onDismiss, or onCancel without one.
ns.EUIConfirmUpdate(newPlan("dismissed"))
shown = popups[#popups]
local dismiss = shown.onDismiss or shown.onCancel
if dismiss then dismiss() end
check(not reaches("dismissed"), "a dismissed confirm no longer reaches its plan")

local function movedPlan()
    local plan = newPlan("moved")
    plan.fresh = newPlan("fresh")
    return plan
end
ns.EUIConfirmUpdate(movedPlan())
count, last = answer(popups[#popups].onConfirm)
check(count == 1 and last == "moved", "Confirm applies a plan whose prediction moved", last)
check(not reaches("moved"), "a confirm shown again lets go of the first plan")
check(reaches("fresh"), "and the confirm now showing reaches the fresh plan")
shown = popups[#popups]
if shown.onCancel then shown.onCancel() end
check(not reaches("fresh"), "until it too is answered")

---------------------------------------------------------------------------------
-- The confirm's height fits its message once
---------------------------------------------------------------------------------

-- A message 100 tall in a popup whose base affords 44. A popup that sizes
-- itself grows by the overflow when shown; the older one keeps its base. A
-- stale first measurement reads 200, the previous message's height, until
-- the next frame.
do
    local msg = { measure = 100 }
    function msg:GetStringHeight() return self.measure end
    function msg:GetText() return self.text end
    local popup = { _baseH = 176, h = 176, _msg = msg }
    function popup:IsVisible() return true end
    function popup:GetHeight() return self.h end
    function popup:SetHeight(h) self.h = h end
    local growsItself
    local EUI, Timer = _G.EllesmereUI, _G.C_Timer
    local realShow, realAfter = EUI.ShowConfirmPopup, Timer.After
    EUI.ShowConfirmPopup = function(_, opts)
        msg.text = opts.message
        popup.h = popup._baseH + (growsItself and math.max(0, msg.measure - 44) or 0)
    end
    local deferred = {}
    Timer.After = function(_, fn) deferred[#deferred + 1] = fn end
    _G.EUIConfirmPopup = popup
    local function heightFor(selfSizing, stale)
        growsItself, deferred = selfSizing, {}
        msg.measure = stale and 200 or 100
        ns.EUIConfirmUpdate(newPlan("height"))
        msg.measure = 100
        for _, fn in ipairs(deferred) do fn() end
        return popup.h
    end
    eq(heightFor(true), 232, "a popup that grew itself for the message is not grown again")
    eq(heightFor(false), 232, "an older popup grows by the overflow")
    eq(heightFor(true, true), 232, "a popup sized from a stale measurement is corrected on the next frame")
    eq(heightFor(false, true), 232, "and so is an older popup grown from one")
    _G.EUIConfirmPopup = nil
    EUI.ShowConfirmPopup, Timer.After = realShow, realAfter
end

---------------------------------------------------------------------------------
-- The confirm's button and alignment
---------------------------------------------------------------------------------

ns.EUI_UPDATE_TEXT.resetTitle = "Reset %s?"
ns.EUIResetText = function() return "reset" end
ns.EUIConfirmUpdate({ kind = "update", noBase = true, inputs = {} })
eq(popups[#popups].confirmText, "Replace", "a confirm with no install record reads Replace")
ns.EUIConfirmUpdate({ kind = "update", noBase = false, inputs = {} })
eq(popups[#popups].confirmText, "Update", "an update reads Update")
ns.EUIConfirmUpdate({ kind = "reset", row = { label = "Unit Frames" }, inputs = {} })
eq(popups[#popups].confirmText, "Reset", "a reset reads Reset")

do
    -- The popup's message, and a show that sets its text, as EllesmereUI's
    -- does on every show, its own confirms' included.
    local msg = { justify = "CENTER" }
    function msg:SetJustifyH(j) self.justify = j end
    function msg:SetText(text) self.text = text end
    local hooks = 0
    local realHook = _G.hooksecurefunc
    _G.hooksecurefunc = function(t, name, fn)
        hooks = hooks + 1
        local orig = t[name]
        t[name] = function(...)
            orig(...)
            fn(...)
        end
    end
    local EUI = _G.EllesmereUI
    local realShow = EUI.ShowConfirmPopup
    EUI.ShowConfirmPopup = function(self, opts)
        realShow(self, opts)
        local current = _G.EUIConfirmPopup
        if current and current._msg and current._msg.SetText then current._msg:SetText(opts.message) end
    end
    local popup = { _msg = msg }
    function popup:IsVisible() return true end
    _G.EUIConfirmPopup = popup
    ns.EUIConfirmUpdate(newPlan("aligned"))
    eq(msg.justify, "LEFT", "a confirm's message is left-aligned while it shows")
    EUI:ShowConfirmPopup({ message = "theirs" })
    eq(msg.justify, "CENTER", "an EllesmereUI confirm shown over it reads centered")
    ns.EUIConfirmUpdate(newPlan("aligned again"))
    eq(msg.justify, "LEFT", "a second confirm is left-aligned too")
    eq(hooks, 1, "with the message hooked once")
    popups[#popups].onCancel()
    EUI:ShowConfirmPopup({ message = "after a close" })
    eq(msg.justify, "CENTER", "and EllesmereUI's next confirm after a close reads centered")

    -- A message that cannot be hooked could never be centered again, so it is
    -- left as EllesmereUI drew it.
    local bare = { justify = "CENTER" }
    function bare:SetJustifyH(j) self.justify = j end
    popup = { _msg = bare }
    function popup:IsVisible() return true end
    _G.EUIConfirmPopup = popup
    ns.EUIConfirmUpdate(newPlan("no SetText"))
    eq(bare.justify, "CENTER", "a message that cannot be hooked keeps its centering")
    popups[#popups].onCancel()
    popup = {}
    function popup:IsVisible() return true end
    _G.EUIConfirmPopup = popup
    local shownBare = pcall(ns.EUIConfirmUpdate, newPlan("no message"))
    check(shownBare, "a popup without its message field shows without an error")
    popups[#popups].onCancel()
    _G.EUIConfirmPopup = nil
    EUI.ShowConfirmPopup, _G.hooksecurefunc = realShow, realHook
end

---------------------------------------------------------------------------------
-- The list draws a counted update
---------------------------------------------------------------------------------

local function fontWith(text)
    for _, font in ipairs(fonts) do
        if font.text == text then return font end
    end
end

local function slotLabel(slot)
    local b = wizard["Option" .. slot]
    return b.shown and b._lbl.text or nil
end

do
    local UF = { id = "uf", label = "Unit Frames" }
    local CDM = { id = "cdm", label = "Cooldown Manager" }
    local GEN = { id = "general", label = "General", sub = "fonts, colors, scale" }
    local counts = { uf = 1, cdm = 0, general = 0 }
    local Timer = _G.C_Timer
    local realAfter, realDiff, realInputs = Timer.After, ns.EUIRowDiff, ns.EUIPageInputs
    Timer.After = function(_, fn) fn() end
    _G.debugprofilestop = function() return 0 end
    ns.EUIPageInputs = function()
        return { rows = { UF, CDM, GEN }, N = {}, O = {}, keyToFolder = {}, missing = {} }
    end
    local lastNames
    ns.EUIRowDiff = function(_, _, _, _, opts)
        lastNames = opts and opts.names
        local result = {}
        for id, n in pairs(counts) do result[id] = { count = n, groups = {} } end
        return { prepared = true, units = 0, result = result, Step = function() return true end }
    end
    ns.EUISplitLinks = function() return { { child = CDM, target = UF } } end
    ns.EUIRestorable = function() return "restore" end
    ns.EUI_UPDATE_TEXT.split = "%s is anchored to %s. You're keeping your own %s, so %s may not line up."
    ns.EUI_UPDATE_TEXT.splitMore = " (+%d more)"
    W:Show()

    local drew, drawErr = pcall(ns.EUIUpdaterPage)
    check(drew, "the list draws a counted update against the stubs", drawErr)
    check(fontWith("KitnUI 2.2.0 changes 1 part of EllesmereUI. Everything is ticked; untick a part to keep it as you have it. Hover a count to see what changes."),
        "the intro reads one part at a count of one")
    check(fontWith("MODULE") and fontWith("KITNUI 2.2.0"), "the column heads are uppercase")
    check(fontWith("Cooldown Manager is anchored to Unit Frames. You're keeping your own Unit Frames, so Cooldown Manager may not line up."),
        "the notice names the split pair, the part keeping the player's copy twice")
    check(fontWith("Tick Unit Frames too"), "and offers to tick the part keeping the player's copy")
    eq(slotLabel(1), "Update Profile", "everything ticked: the update button first")
    eq(slotLabel(2), "Restore previous", "with Restore previous beside it")
    eq(slotLabel(3), nil, "and no third button")

    -- The walk's name lookups: nil without the game's functions or with a
    -- secret answer, the name otherwise.
    check(lastNames ~= nil, "the walk is handed the name lookups")
    if lastNames then
        eq(lastNames.spec(102), nil, "names: no spec name without GetSpecializationInfoByID")
        eq(lastNames.spell(191034), nil, "names: no spell name without C_Spell")
        _G.GetSpecializationInfoByID = function() return 102, "Balance", "", 0, "DAMAGER", "DRUID", "Druid" end
        _G.C_Spell = { GetSpellName = function() return "Starfall" end }
        eq(lastNames.spec(102), "Balance Druid", "names: the spec reads <spec> <class>")
        eq(lastNames.spell(191034), "Starfall", "names: the spell reads its name")
        local asked = 0
        _G.GetSpecializationInfoByID = function() asked = asked + 1 end
        _G.C_Spell = { GetSpellName = function() asked = asked + 1 end }
        for _, id in ipairs({ 0, -5, 2147483648, 102.5 }) do
            eq(lastNames.spec(id), nil, "names: an out-of-range spec ID reads no name")
            eq(lastNames.spell(id), nil, "names: an out-of-range spell ID reads no name")
        end
        eq(asked, 0, "names: an out-of-range ID never reaches the game")
        _G.GetSpecializationInfoByID = function() return 102, "Balance", "", 0, "DAMAGER", "DRUID", "Druid" end
        _G.C_Spell = { GetSpellName = function() return "Starfall" end }
        _G.issecretvalue = function() return true end
        eq(lastNames.spec(102), nil, "names: a secret spec name is not used")
        eq(lastNames.spell(191034), nil, "names: a secret spell name is not used")
        _G.issecretvalue, _G.GetSpecializationInfoByID, _G.C_Spell = nil, nil, nil

        -- The cooldown lookup: a buff order entry's cooldown ID to its spell.
        local cooldown = lastNames.cooldown or function() return "missing" end
        eq(cooldown(42), nil, "names: no cooldown spell without C_CooldownViewer")
        local cdAsked = 0
        _G.C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id)
            cdAsked = cdAsked + 1
            if id == 42 then return { cooldownID = 42, spellID = 191034, overrideSpellID = 0 } end
            if id == 43 then return { cooldownID = 43, spellID = 191034, overrideSpellID = 194223 } end
            return nil
        end }
        eq(cooldown(42), 191034, "names: a cooldown reads its spell")
        eq(cooldown(43), 194223, "names: a cooldown reads its override spell first")
        eq(cooldown(44), nil, "names: a cooldown the game does not know reads no spell")
        cdAsked = 0
        for _, id in ipairs({ 0, -5, 2147483648, 102.5 }) do
            eq(cooldown(id), nil, "names: an out-of-range cooldown ID reads no spell")
        end
        eq(cdAsked, 0, "names: an out-of-range cooldown ID never reaches the game")
        _G.issecretvalue = function() return true end
        eq(cooldown(42), nil, "names: a secret spell ID is not used")
        _G.issecretvalue, _G.C_CooldownViewer = nil, nil
    end

    counts.cdm = 3
    drew, drawErr = pcall(ns.EUIUpdaterPage)
    check(drew, "the list draws two changed parts", drawErr)
    check(fontWith("KitnUI 2.2.0 changes 2 parts of EllesmereUI. Everything is ticked; untick a part to keep it as you have it. Hover a count to see what changes."),
        "the intro reads parts above one")
    local ufRow
    for _, frame in ipairs(frames) do
        if frame.row == UF and frame.scripts.OnClick then ufRow = frame end
    end
    check(ufRow ~= nil, "the Unit Frames row is drawn")
    -- A field the row does not carry reads as nil, not as the stubs' noop, so
    -- a row built before the redraw fails these checks instead of erroring.
    local function child(t, ...)
        for i = 1, select("#", ...) do
            if type(t) ~= "table" then return nil end
            t = rawget(t, (select(i, ...)))
        end
        return t
    end
    -- The panel starts at the list's left edge, in line with the intro, the
    -- band and the buttons: the heads, and the rows anchored to them, sit
    -- 8 px inside it. The band is the panel's 536 px; its text has that less
    -- 10 px before it, 8 px and the 80 px button after it, and 4 px at the end.
    local rowAt = child(ufRow, "point")
    local head = type(rowAt) == "table" and rowAt[2] or nil
    local headAt = type(head) == "table" and rawget(head, "point") or nil
    eq(type(headAt) == "table" and headAt[4] or nil, 8, "under the band, the heads and rows sit 8 px inside the panel")
    local bandText = fontWith("Cooldown Manager is anchored to Unit Frames. You're keeping your own Unit Frames, so Cooldown Manager may not line up.")
    eq(bandText and rawget(bandText, "width"), 434, "the band's text takes the panel's width less its padding and the button")

    -- The stubs carry no C_Texture, as a client without the atlas.
    eq(child(ufRow, "box", "fill", "shown"), true, "a ticked box is filled")
    eq(child(ufRow, "box", "mark", "shown"), false, "and without the atlas shows no mark")
    eq(child(ufRow, "kitn", "badge", "height"), 12, "a badge is 2 px shorter than a short row")
    if ufRow then ufRow.scripts.OnClick(ufRow) end
    eq(slotLabel(1), "Update ticked (1)", "a part unticked: the button counts the ticks")
    eq(slotLabel(2), "Restore previous", "Restore previous stays beside it")
    eq(slotLabel(3), "Tick all", "and Tick all follows")
    eq(wizard.Option3.width, 100, "Tick all is drawn narrow")

    -- Restore's "switch" state is 240 wide; the row still fits the content column.
    ns.EUIRestorable = function() return "switch" end
    ns.EUI_UPDATE_TEXT.notRestorable = "Switch to your KitnUI profile first"
    if ufRow then
        ufRow.scripts.OnClick(ufRow)
        ufRow.scripts.OnClick(ufRow)
    end
    eq(slotLabel(2), "Switch to your KitnUI profile first", "the switch state sits beside the update button")
    eq(slotLabel(3), "Tick all", "with Tick all after it")
    local rowW = (wizard.Option1.width or 0) + (wizard.Option2.width or 0) + (wizard.Option3.width or 0) + 20
    check(rowW <= 520, "and the three buttons fit the 520 px content column", rowW)
    ns.EUIRestorable = function() return "restore" end

    -- Every font measurement secret: the list draws on its stand-ins.
    _G.issecretvalue = function() return true end
    drew, drawErr = pcall(ns.EUIUpdaterPage)
    _G.issecretvalue = nil
    check(drew, "the list draws when every measurement is secret", drawErr)
    eq(slotLabel(1), "Update Profile", "and its buttons draw")
    local cellW = child(ufRow, "kitn", "_w")
    check(type(cellW) == "number" and cellW > 16, "the KitnUI cell carries its width", cellW)
    eq(child(ufRow, "kitn", "badge", "width"), cellW, "a secret text width gives the badge its cell's width")
    eq(child(ufRow, "kitn", "badge", "height"), 18, "a secret list height gives rows room for full-height badges")

    -- While counting: the walk's steps wait for the next frame, so the page
    -- first draws with no counts.
    local deferred = {}
    Timer.After = function(_, fn) deferred[#deferred + 1] = fn end
    drew, drawErr = pcall(ns.EUIUpdaterPage)
    check(drew, "the list draws while counting", drawErr)
    eq(child(ufRow, "kitn", "text", "text"), "...", "while counting a KitnUI cell reads ...")
    eq(slotLabel(1), "Preparing...", "and the update button reads Preparing...")
    Timer.After = function(_, fn) fn() end
    for _, fn in ipairs(deferred) do fn() end
    eq(child(ufRow, "kitn", "text", "text"), "Changes 1 Setting", "the count lands in the cell")

    -- Up to date, the read-only page: no box, plain "Up to Date", Restore
    -- previous alone in slot 1. Plain text starts 6 px into its cell, where a
    -- badge's text starts, and the KitnUI head starts on that line too.
    local realState = ns.EUIUpdateState
    ns.EUIUpdateState = function() return "current" end
    counts.uf, counts.cdm = 0, 0
    drew, drawErr = pcall(ns.EUIUpdaterPage)
    check(drew, "the up-to-date page draws", drawErr)
    eq(child(ufRow, "box", "shown"), false, "up to date: no box")
    eq(child(ufRow, "kitn", "text", "text"), "Up to Date", "up to date: the cell reads Up to Date")
    local plainAt = child(ufRow, "kitn", "text", "point")
    eq(type(plainAt) == "table" and plainAt[2] or nil, 6, "up to date: plain text starts 6 px into its cell, as a badge's text does")
    local updaterHead = fontWith("KITNUI 2.2.0")
    local updaterHeadAt = updaterHead and rawget(updaterHead, "point")
    eq(type(updaterHeadAt) == "table" and updaterHeadAt[2] or nil, 396, "Profile Update: the KitnUI head starts 6 px into its column")
    eq(child(ufRow, "kitn", "_w"), 130, "Profile Update: the KitnUI cell keeps its 130 px")
    local plainRowAt = child(ufRow, "point")
    local plainHead = type(plainRowAt) == "table" and plainRowAt[2] or nil
    local plainHeadAt = type(plainHead) == "table" and rawget(plainHead, "point") or nil
    eq(type(plainHeadAt) == "table" and plainHeadAt[4] or nil, 8, "with no band, the heads and rows sit 8 px inside the panel")
    eq(slotLabel(1), "Restore previous", "up to date: Restore previous in slot 1")
    eq(slotLabel(2), nil, "up to date: and nothing beside it")
    ns.EUIUpdateState = realState

    -- The Modules page with a four-digit count: every badge stays inside its
    -- column. Your copy (list x 208, 140 wide) ends before the KitnUI column
    -- (354), and the KitnUI badge (128 wide) before Reset (484). The heads
    -- start 6 px into their columns, on the line the cells' text starts on.
    local realStringWidth = Frame.GetStringWidth
    Frame.GetStringWidth = function() return 200 end
    Frame.GetUnboundedStringWidth = function() return 200 end
    ns.EUIReadPlayer = function()
        return { rows = { UF, CDM, GEN }, P = {}, O = {}, N = {}, keyToFolder = {}, missing = {} }
    end
    ns.EUIPlayerContext = function() return { held = {}, defaults = {}, unlock = {} } end
    counts.uf = 1228
    drew, drawErr = pcall(ns.EUIModulesPage)
    Frame.GetStringWidth, Frame.GetUnboundedStringWidth = realStringWidth, nil
    check(drew, "the Modules page draws a four-digit count", drawErr)
    eq(child(ufRow, "yours", "text", "text"), "Changed by You - 1228", "Modules: the Your copy cell reads the player's count")
    local yoursAt, kitnAt = child(ufRow, "yours", "point"), child(ufRow, "kitn", "point")
    eq(type(yoursAt) == "table" and yoursAt[4] or nil, 208, "Modules: the Your copy column starts at list x 208")
    eq(type(kitnAt) == "table" and kitnAt[4] or nil, 354, "Modules: the KitnUI column starts at list x 354")
    eq(child(ufRow, "yours", "_w"), 140, "Modules: the Your copy cell is 140 wide")
    eq(child(ufRow, "kitn", "_w"), 128, "Modules: the KitnUI cell is 128 wide, 2 px short of Reset")
    local yoursW = child(ufRow, "yours", "badge", "width")
    check(type(yoursW) == "number" and 208 + yoursW <= 354, "Modules: a long Your copy badge ends left of the KitnUI column", yoursW)
    local kitnW = child(ufRow, "kitn", "badge", "width")
    check(type(kitnW) == "number" and 354 + kitnW <= 484, "Modules: a long KitnUI badge ends before Reset", kitnW)
    local yoursHead, modulesHead = fontWith("YOUR COPY"), fontWith("KITNUI 2.2.0")
    local yoursHeadAt = yoursHead and rawget(yoursHead, "point")
    local modulesHeadAt = modulesHead and rawget(modulesHead, "point")
    eq(type(yoursHeadAt) == "table" and yoursHeadAt[2] or nil, 214, "Modules: the Your copy head starts 6 px into its column")
    eq(type(modulesHeadAt) == "table" and modulesHeadAt[2] or nil, 360, "Modules: the KitnUI head starts 6 px into its column")

    Timer.After, ns.EUIRowDiff, ns.EUIPageInputs = realAfter, realDiff, realInputs
    ns.EUIHideModuleList()
end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
