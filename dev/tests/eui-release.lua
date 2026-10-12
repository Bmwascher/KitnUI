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

_G.CreateFrame = function() return newFrame() end
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
    MakeFont = function() return newFrame() end,
    MakeBorder = noop,
    SolidTex = noop,
    MakeStyledButton = function() return newFrame(), newFrame(), newFrame() end,
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

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
