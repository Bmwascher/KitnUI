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

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
