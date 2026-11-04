-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/PartyCard.lua                              ║
-- ║  Purpose: The Party Card: one row per party member, its      ║
-- ║           samples, its visibility and its Unlock Mode        ║
-- ║           element. It takes its rows as arguments.           ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar
local L = X.PartyLogic

local Plain = ns.EUIPlain
local Get = X.Get
local ClassColor = X.PartyClassColor

local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min

local UNLOCK_KEY = "KitnUI_PartyXP"
local TICKER_KEY = "KitnUI_XPTicker"
-- How far a chain of Unlock Mode links is followed before it counts as never ending.
local LINK_DEPTH = 20
-- Sizes, as multiples of the font size. The pad is the ticker's, so at one font
-- size their text lines up when stacked.
local ROW_SCALE, NAME_SCALE, PAD_SCALE, INSET_SCALE = 1.5, 7.5, 0.5, 0.1
-- The most of a row the name column may take: Width and Font Size are set apart,
-- and at a large font on a narrow card its multiple would leave the bar no room.
local NAME_SHARE = 0.5
local MAX_GRAY, OFFLINE_GRAY = 0.45, 0.5
local ROW_BACK_A = 0.5
-- Where a card with no ticker to stack under sits until it is moved, clear of
-- the bars' and the ticker's first spots.
local FIRST_X, FIRST_Y = 40, -40
-- Both cards' backgrounds meet, so the two read as one box.
local STACK_GAP = 0
X.PARTY_STACK_GAP = STACK_GAP
-- The samples' own cap, on every client.
local SAMPLE_CAP = 60

local live, liveRows
local liveN, liveWanted, unlockOn, watching, accentDone = 0, false, false, false, false
-- Placed for this Unlock Mode session. A drag or an arrow key lives only on the
-- frame until Save & Exit reads it back from there, so only a save or a cleared
-- spot reaches a held card.
local held = false
local element

---------------------------------------------------------------------------------
-- The widget
---------------------------------------------------------------------------------

-- Registers nothing: the live path adds what a card on screen needs.
function X.NewPartyCard(parent)
    local card = CreateFrame("Frame", nil, parent or UIParent)
    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetAllPoints(card)
    card.edge = CreateFrame("Frame", nil, card)
    card.edge:SetAllPoints(card)
    card.rows, card.look = {}, {}
    card.gen = 0
    card.dirty = true
    return card
end

-- The row at i, made on first need.
function X.PartyCardRow(card, i)
    local row = card.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, card)
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetWordWrap(false)
    row.name:SetJustifyH("LEFT")
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetMinMaxValues(0, 100)
    row.bar:SetValue(0)
    row.back = row.bar:CreateTexture(nil, "BACKGROUND")
    row.back:SetAllPoints(row.bar)
    row.back:SetColorTexture(0, 0, 0, ROW_BACK_A)
    row.text = row.bar:CreateFontString(nil, "OVERLAY")
    row.text:SetWordWrap(false)
    row.text:SetPoint("CENTER", row.bar, "CENTER", 0, 0)
    card.rows[i] = row
    return row
end

local function SetFont(fs, font, size, flags)
    if not fs:SetFont(font, size, flags) then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
end

-- Only when a setting changed: every size is a multiple of the font size.
local function StyleCard(card, view)
    card.dirty = false
    card.gen = card.gen + 1
    local look = card.look
    look.size = tonumber(view("xpPartyFontSize")) or 12
    look.width = X.Math.PartyWidth(view("xpPartyWidth"), view("xpTickerFontSize"))
    look.rowH = ceil(look.size * ROW_SCALE)
    look.pad = ceil(look.size * PAD_SCALE)
    local inner = max(1, look.width - 2 * look.pad)
    look.nameW = min(ceil(look.size * NAME_SCALE), floor(inner * NAME_SHARE))
    look.barW = inner - look.nameW
    look.inset = ceil(look.size * INSET_SCALE)
    look.font, look.flags = X.FontPath(view("xpPartyFont")), X.OutlineFlag(view("xpPartyOutline"))
    look.tex = X.BarTexture(view("xpPartyTexture"))
    local mode = view("xpPartyBackground")
    local backs = X.CARD_BACKGROUNDS
    local bg = backs and backs[mode]
    if bg then
        card.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
        card.bg:Show()
    else
        card.bg:Hide()
    end
    card.edge:SetShown(mode == "card")
    local EUI = _G.EllesmereUI
    if mode == "card" and EUI and EUI.ApplyBorderStyle then
        pcall(EUI.ApplyBorderStyle, card.edge, 1, 0, 0, 0, 1, "solid")
    end
end

local function StyleRow(card, row, i)
    local look = card.look
    row.gen = card.gen
    local y = -(look.pad + (i - 1) * look.rowH)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", card, "TOPLEFT", look.pad, y)
    row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -look.pad, y)
    row:SetHeight(look.rowH)
    SetFont(row.name, look.font, look.size, look.flags)
    SetFont(row.text, look.font, look.size, look.flags)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetWidth(max(1, look.nameW - look.pad))
    row.bar:ClearAllPoints()
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", look.nameW, -look.inset)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, look.inset)
    row.bar:SetStatusBarTexture(look.tex)
    row.text:SetWidth(look.barW)
    row.kFillR, row.kFillG, row.kFillB = nil, nil, nil
end

local function FillColor(view, e)
    if e.view.kind == "max" then return MAX_GRAY, MAX_GRAY, MAX_GRAY end
    local mode = view("xpPartyFill")
    if mode == "class" then return ClassColor(e.class) end
    if mode == "accent" then
        local r, g, b = X.AccentColor()
        if r then return r, g, b end
    end
    return view("xpPartyFillColorR"), view("xpPartyFillColorG"), view("xpPartyFillColorB")
end

-- An unchanged row is not redrawn.
local function PaintRow(row, e, view)
    local v = e.view
    if row.kName ~= e.name then
        row.kName = e.name
        row.name:SetText(e.name)
    end
    local r, g, b = ClassColor(e.class)
    if v.kind == "offline" then r, g, b = OFFLINE_GRAY, OFFLINE_GRAY, OFFLINE_GRAY end
    if row.kNameR ~= r or row.kNameG ~= g or row.kNameB ~= b then
        row.kNameR, row.kNameG, row.kNameB = r, g, b
        row.name:SetTextColor(r, g, b)
    end
    if row.kText ~= v.text then
        row.kText = v.text
        row.text:SetText(v.text)
    end
    if row.kPct ~= v.pct then
        row.kPct = v.pct
        row.bar:SetValue(v.pct)
    end
    local fr, fg, fb = FillColor(view, e)
    if row.kFillR ~= fr or row.kFillG ~= fg or row.kFillB ~= fb then
        row.kFillR, row.kFillG, row.kFillB = fr, fg, fb
        row.bar:SetStatusBarColor(fr, fg, fb)
    end
end

-- rows: n entries of { name, class, view = { kind, pct, text } }.
function X.DrawPartyCard(card, view, rows, n)
    if card.dirty then StyleCard(card, view) end
    local look = card.look
    for i = 1, n do
        local row = X.PartyCardRow(card, i)
        if row.gen ~= card.gen then StyleRow(card, row, i) end
        PaintRow(row, rows[i], view)
        row:Show()
    end
    for i = n + 1, #card.rows do card.rows[i]:Hide() end
    local height = n * look.rowH + 2 * look.pad
    if card.kuiW ~= look.width or card.kuiH ~= height then
        card.kuiW, card.kuiH = look.width, height
        card:SetSize(look.width, height)
    end
end

---------------------------------------------------------------------------------
-- The samples
---------------------------------------------------------------------------------

local sampleSelf = { name = "You", class = "MAGE", level = 59, online = true, view = {} }
local sampleData = { name = "Milkers", class = "MAGE", level = 58, online = true, view = {} }
local sampleNone = { name = "Snorlock", class = "WARLOCK", level = 57, online = true, view = {} }
local sampleMax = { name = "Bite", class = "HUNTER", level = SAMPLE_CAP, online = true, view = {} }
local SELF_PCT, DATA_PCT = 45, 91.2
local sampleRows = {}
local sampleMarks = { n = 1, { name = sampleData.name, class = sampleData.class, level = sampleData.level, pct = DATA_PCT } }
local selfHeard = { level = sampleSelf.level, pct = SELF_PCT }
local dataHeard = { level = sampleData.level, pct = DATA_PCT }

function X.PartySampleRows(view)
    local name = X.ReadPlain(_G.UnitFullName, "player")
    local _, class = X.ReadPlain(_G.UnitClass, "player")
    sampleSelf.name = name or sampleSelf.name
    sampleSelf.class = class or sampleSelf.class
    L.RowView(sampleSelf.view, sampleSelf, selfHeard, SAMPLE_CAP, false)
    L.RowView(sampleData.view, sampleData, dataHeard, SAMPLE_CAP, false)
    L.RowView(sampleNone.view, sampleNone, nil, SAMPLE_CAP, false)
    L.RowView(sampleMax.view, sampleMax, nil, SAMPLE_CAP, false)
    local n = 0
    if view("xpPartyShowSelf") == true then
        n = 1
        sampleRows[n] = sampleSelf
    end
    sampleRows[n + 1], sampleRows[n + 2], sampleRows[n + 3] = sampleData, sampleNone, sampleMax
    return sampleRows, n + 3
end

function X.PartySampleMarks()
    return sampleMarks
end

---------------------------------------------------------------------------------
-- The live card
---------------------------------------------------------------------------------

local function Redraw()
    if not (live and watching) then return end
    if unlockOn then
        local rows, n = X.PartySampleRows(Get)
        X.DrawPartyCard(live, Get, rows, n)
    elseif liveN > 0 then
        X.DrawPartyCard(live, Get, liveRows, liveN)
    end
end

local function Wanted()
    if unlockOn then return true end
    if not liveWanted then return false end
    return X.EvalVisibility(Get("xpPartyVisibility"))
end

local function WantsMouseover()
    return Wanted() == "mouseover"
end

-- Whether the ticker's Unlock Mode links lead back to this card: each would then
-- be placed from the other.
local function TickerLeadsHere()
    local db = _G.EllesmereUIDB
    local links = type(db) == "table" and db.unlockAnchors
    if type(links) ~= "table" then return false end
    local key = TICKER_KEY
    for _ = 1, LINK_DEPTH do
        local info = links[key]
        local target = type(info) == "table" and info.target
        if not target then return false end
        if target == UNLOCK_KEY then return true end
        key = target
    end
    return true
end

-- The ticker's frame, while the card has no spot or link of its own to follow.
local function StackUnder()
    if type(Get("xpPartyPos")) == "table" then return nil end
    local EUI = _G.EllesmereUI
    if EUI and EUI.IsAnchored and EUI.IsAnchored(UNLOCK_KEY) then return nil end
    if TickerLeadsHere() then return nil end
    return X.TickerFrame()
end

-- A frame anchor follows the ticker's moves and height with no event. Unlock
-- Mode's arrow keys write a frame's offsets back onto UIParent, and its drag
-- starts from where the mover last saw the frame, so while it is open a stacked
-- card sits on UIParent at the same spot and is left there.
local function PlaceCard()
    if not live then return end
    local ticker = StackUnder()
    if not ticker then
        X.PlaceFrame(live, UNLOCK_KEY, Get("xpPartyPos"), "LEFT", FIRST_X, FIRST_Y)
        held = unlockOn
        return
    end
    if held then return end
    live:ClearAllPoints()
    live:SetPoint("TOPLEFT", ticker, "BOTTOMLEFT", 0, -STACK_GAP)
    if not unlockOn then return end
    local left, top = Plain(live:GetLeft()), Plain(live:GetTop())
    if not (left and top) then return end
    live:ClearAllPoints()
    live:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    held = true
end

local function PlaceUnheld()
    if not held then PlaceCard() end
end

function X.PartyCardVisibility()
    if not (live and watching) then return end
    local v = Wanted()
    local EUI = _G.EllesmereUI
    local canHover = EUI and EUI.RegisterMouseoverTarget and EUI.UnregisterMouseoverTarget
    if v == "mouseover" and canHover then
        if not live.mouseover then
            EUI.RegisterMouseoverTarget(live, WantsMouseover)
            live.mouseover = true
        end
    else
        if live.mouseover and canHover then EUI.UnregisterMouseoverTarget(live) end
        live.mouseover = false
        live:SetAlpha(1)
        live:SetShown(v and true or false)
    end
    PlaceUnheld()
end

-- While noInitHook is up, Unlock Mode's position pass, which runs on every zone
-- change, skips the element, and its resize path calls only applyPos, which holds.
local function OnUnlock(active)
    unlockOn = Plain(active) == true
    held = false
    if element then element.noInitHook = unlockOn end
    Redraw()
    X.PartyCardVisibility()
end

-- Clicks and hover pass through to the world, through the hover service's
-- reveal too.
local function SetMouse(frame)
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(false) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
end

local function MakeLive()
    live = X.NewPartyCard(UIParent)
    live:Hide()
    live:SetFrameStrata("LOW")
    live:SetClampedToScreen(true)
    hooksecurefunc(live, "EnableMouse", SetMouse)
    SetMouse(live)
end

local function Watch(on)
    if watching == on then return end
    watching = on
    local EUI = _G.EllesmereUI
    if not EUI then return end
    if on then
        if EUI.RegisterVisibilityUpdater then EUI.RegisterVisibilityUpdater(X.PartyCardVisibility) end
        if EUI.RegisterUnlockModeListener then EUI:RegisterUnlockModeListener(UNLOCK_KEY, OnUnlock) end
    else
        if EUI.UnregisterVisibilityUpdater then EUI.UnregisterVisibilityUpdater(X.PartyCardVisibility) end
        if EUI.UnregisterUnlockModeListener then EUI:UnregisterUnlockModeListener(UNLOCK_KEY) end
    end
end

local function RegisterAccent()
    if accentDone then return end
    accentDone = true
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegAccent) then return end
    EUI.RegAccent({ type = "callback", fn = function()
        if Get("xpPartyFill") ~= "accent" then return end
        Redraw()
        if X.PreviewRefresh then X.PreviewRefresh() end
    end })
end

function X.PartyCardApply()
    if Get("xpPartyCard") ~= true then
        X.PartyCardStop()
        return
    end
    if not live then MakeLive() end
    X.EnsureUnlock()
    RegisterAccent()
    Watch(true)
    live.dirty = true
    Redraw()
    X.PartyCardVisibility()
end

-- What the party path last worked out, kept for the combat edges and Unlock Mode.
function X.PartyCardRefresh(rows, n, wanted)
    liveRows, liveN, liveWanted = rows, n, wanted
    if not live or not watching then return end
    Redraw()
    X.PartyCardVisibility()
end

function X.PartyCardStop()
    Watch(false)
    unlockOn = false
    held = false
    if element then element.noInitHook = false end
    if not live then return end
    local EUI = _G.EllesmereUI
    if live.mouseover and EUI and EUI.UnregisterMouseoverTarget then EUI.UnregisterMouseoverTarget(live) end
    live.mouseover = false
    live:Hide()
end

-- Width is on the page and height follows the font size, so the mover has no
-- resize controls.
function X.PartyElement(EUI)
    element = EUI.MakeUnlockElement({
        key = UNLOCK_KEY, label = "KitnUI Party XP", group = "KitnUI", order = 6, noResize = true,
        isHidden = function() return Get("xpPartyCard") ~= true end,
        -- Never creates: Unlock Mode asks whether or not the card is on.
        getFrame = function() return live end,
        getSize = function()
            return X.Math.PartyWidth(Get("xpPartyWidth"), Get("xpTickerFontSize")), live and live.kuiH or Get("xpPartyFontSize")
        end,
        savePos = function(_, point, relPoint, x, y)
            X.Set("xpPartyPos", { point = point, relPoint = relPoint, x = x, y = y })
            PlaceCard()
        end,
        -- A copy: Unlock Mode is free to keep or change what it is given.
        loadPos = function()
            local p = Get("xpPartyPos")
            if type(p) ~= "table" then return nil end
            return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
        end,
        -- Spec layouts read these instead of loadPos and savePos. A layout's spot
        -- replaces whatever the session held.
        loadRawPos = function() return X.Math.RawSpot(Get("xpPartyPos")) end,
        saveRawPos = function(_, banked)
            X.Set("xpPartyPos", X.Math.StoredSpot(banked))
            held = false
            PlaceCard()
        end,
        clearPos = function()
            X.Set("xpPartyPos", nil)
            held = false
        end,
        applyPos = PlaceUnheld,
    })
    return element
end
