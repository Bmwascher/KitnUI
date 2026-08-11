-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/TopBar/Bar.lua                                   ║
-- ║  Purpose: The bar frame, its three panels, element buttons,  ║
-- ║           layout and the Apply() funnel that reconciles      ║
-- ║           everything against settings.                       ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.TopBar = ns.TopBar or {}

---------------------------------------------------------------------------------
-- Storage helpers. These are the only functions permitted to touch the
-- settings table for a tb* key. No other file calls ns.EUISettings() for one.
---------------------------------------------------------------------------------

local function S() return ns.EUISettings() end

function ns.TopBar.Get(key, fallback)
    local s = S()
    if not s then return fallback end
    local v = s[key]
    if v == nil then return fallback end
    return v
end

function ns.TopBar.Set(key, v)
    local s = S()
    if s then s[key] = v end
end

-- File-local aliases, so the rest of this file reads cleanly.
local Get, Set = ns.TopBar.Get, ns.TopBar.Set

-- Returns three arrays, always populated. A MISSING stored panel entry means
-- the user has never arranged anything, so the registry default stands. An
-- EMPTY stored panel entry is a deliberate layout -- a drag can empty a side --
-- and must stand as empty, not fall back to the default.
function ns.TopBar.Order()
    local s = S()
    local stored = s and s.tbOrder
    local out = {}
    for _, panel in ipairs({ "left", "centre", "right" }) do
        local a = type(stored) == "table" and stored[panel]
        if type(a) == "table" then
            out[panel] = CopyTable(a)
        else
            out[panel] = CopyTable(ns.TopBar.DEFAULT_ORDER[panel])
        end
    end
    return out
end

-- REPLACES the whole table. Writing into a registered table default is what
-- deleted the accent switch at logout; tbOrder gets the same wholesale rule.
function ns.TopBar.SetOrder(left, centre, right)
    local s = S()
    if not s then return end
    s.tbOrder = { left = CopyTable(left), centre = CopyTable(centre), right = CopyTable(right) }
end

function ns.TopBar.IsOff(id)
    local s = S()
    local off = s and s.tbOff
    return type(off) == "table" and off[id] and true or false
end

-- Also replaces wholesale, same reason.
function ns.TopBar.SetOff(id, v)
    local s = S()
    if not s then return end
    local next_ = {}
    if type(s.tbOff) == "table" then
        for k, on in pairs(s.tbOff) do if on then next_[k] = true end end
    end
    if v then next_[id] = true else next_[id] = nil end
    s.tbOff = next_
end

---------------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------------

-- File-scope locals, declared ABOVE Apply() so it can test `if not bar`. Every
-- one of these is local: a bare assignment would publish a global, and
-- .luacheckrc would fail the file rather than the addon failing quietly.
local bar, leftPanel, centrePanel, rightPanel
local fitPending = false
local buttons = {}

-- Mouseover fade: the AnimationGroup/Animation pair, built once in
-- EnsureCreated so PlayFade only ever has to Play() it.
local fadeGroup, fadeAnim

-- Outer edge cushion for the bar's own bounding box, kept separate from
-- tbSpacing's user-configurable inter-element gap.
local PAD = 8
-- Button footprint around the icon texture, on top of tbIconSize.
local BTN_PAD = 8

-- Icon rest tint and the hover tween. TWEEN_TIME is fixed by the design and
-- deliberately not exposed as a setting.
local REST_R, REST_G, REST_B = 1, 1, 1
local TWEEN_TIME = 0.2

-- Alpha the bar rests at when Fade Until Moused Over is on and the pointer
-- is elsewhere. Low, not zero, so the bar reads as "there but dim" rather
-- than vanishing outright.
local FADE_REST_ALPHA = 0.15

-- The three accent scalars resolve the same way for the panel accent lines
-- and the icon hover tween, so both read through this one helper.
local function AccentRGB()
    local r, g, b
    if Get("tbAccentOverride", ns.EUI_DEFAULTS.tbAccentOverride) then
        r = Get("tbAccentR", ns.EUI_DEFAULTS.tbAccentR)
        g = Get("tbAccentG", ns.EUI_DEFAULTS.tbAccentG)
        b = Get("tbAccentB", ns.EUI_DEFAULTS.tbAccentB)
    elseif EllesmereUI and EllesmereUI.GetAccentColor then
        r, g, b = EllesmereUI.GetAccentColor()
    end
    if not (r and g and b) then
        r, g, b = ns.EUI_DEFAULTS.tbAccentR, ns.EUI_DEFAULTS.tbAccentG, ns.EUI_DEFAULTS.tbAccentB
    end
    return r, g, b
end
ns.TopBar.AccentRGB = AccentRGB

-- One texture, vertex colour interpolated: the icon art is a single texture,
-- not two cross-faded layers, so this cannot be an AnimationGroup.
--
-- This OnUpdate is an ANIMATION, not polling: it has a fixed 0.2s duration
-- and unhooks itself on the final frame. The project's no-OnUpdate rule
-- targets indefinite per-frame work, which this is not.
local function TintTo(btn, tr, tg, tb)
    if not btn._icon then return end
    local sr, sg, sb = btn._icon:GetVertexColor()
    if sr == tr and sg == tg and sb == tb then
        btn:SetScript("OnUpdate", nil)
        return
    end
    btn._tweenT = 0
    btn:SetScript("OnUpdate", function(self, elapsed)
        self._tweenT = self._tweenT + elapsed
        local t = self._tweenT / TWEEN_TIME
        if t >= 1 then
            self._icon:SetVertexColor(tr, tg, tb)
            self:SetScript("OnUpdate", nil)
            return
        end
        self._icon:SetVertexColor(sr + (tr - sr) * t, sg + (tg - sg) * t, sb + (tb - sb) * t)
    end)
end

-- An AnimationGroup rather than an OnUpdate. FROM is always the bar's live
-- alpha, so a fade interrupted mid-tween by the opposite hover restarts from
-- where it visually is rather than snapping.
local function PlayFade(toAlpha)
    if not (bar and fadeGroup and fadeAnim) then return end
    fadeGroup:Stop()
    fadeAnim:SetFromAlpha(bar:GetAlpha())
    fadeAnim:SetToAlpha(toAlpha)
    fadeAnim:SetDuration(Get("tbFadeTime", ns.EUI_DEFAULTS.tbFadeTime))
    fadeGroup:Play()
end

-- Shared hover handlers: the bar AND every launcher button hook these, so
-- the bar reads as one hover region rather than fading out the instant the
-- pointer crosses from the bar's own background onto a button on top of it.
local function FadeReveal()
    if Get("tbFade", ns.EUI_DEFAULTS.tbFade) then PlayFade(1) end
end

-- bar:IsMouseOver() alone has a gap: FitBarWidth sizes the bar from PAD (8)
-- plus twice the wider side panel, but LayoutPanels hangs each side panel
-- off the centre by tbSpacing (default 14), so the wider side overhangs the
-- bar's own rectangle by about 10px (and a taller side panel overhangs it
-- vertically too). The panels bound their buttons exactly, so check them as
-- well to close that gap. Shared by FadeConceal and ApplyFade so there is
-- one place to be right, not two that can drift apart.
local function Hovered()
    if not bar then return false end
    return bar:IsMouseOver()
        or (leftPanel and leftPanel:IsMouseOver())
        or (centrePanel and centrePanel:IsMouseOver())
        or (rightPanel and rightPanel:IsMouseOver())
        or false
end

-- Deferred one frame: moving the pointer from the bar straight onto one of
-- its own buttons fires this OnLeave before the button's OnEnter, so an
-- immediate fade-out would dim the bar out from under the button the
-- pointer just landed on. Waiting one frame lets that OnEnter land first;
-- checking Hovered() then is the actual decision, not the delay itself.
local function FadeConceal()
    if not Get("tbFade", ns.EUI_DEFAULTS.tbFade) then return end
    C_Timer.After(0, function()
        if not Hovered() then
            PlayFade(FADE_REST_ALPHA)
        end
    end)
end

-- Each panel is a plain frame: a BACKGROUND fill (hidden when tbBackdrop is
-- off) and a one-pixel OVERLAY accent line along the bottom edge. Both anchor
-- to the panel rather than take an explicit size, so they track it whenever
-- LayoutPanels resizes the panel and ApplyPanelColors never has to.
local function CreatePanel(suffix)
    local p = CreateFrame("Frame", "KitnUITopBar" .. suffix, bar)

    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(0.03, 0.03, 0.04, 0.85)
    p._bg = bg

    local accent = p:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT")
    accent:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT")
    accent:SetHeight(1)
    accent:SetColorTexture(1, 0, 0.549, 1)
    p._accent = accent

    return p
end

-- Parented straight into its final panel. Once a secure button has a parent,
-- SetParent on it is protected, so there is no later point where re-parenting
-- would be safe.
local function CreateElementButton(el)
    local panel = leftPanel
    if el.panel == "right" then panel = rightPanel
    elseif el.panel == "centre" then panel = centrePanel end

    local template = el.secure and "SecureActionButtonTemplate" or nil
    local btn = CreateFrame("Button", "KitnUITopBar_" .. el.id, panel, template)
    btn:RegisterForClicks("AnyUp")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetTexture(el.icon)
    btn._icon = icon

    -- Non-secure elements (gamemenu) get their click handler once, here:
    -- ordinary Lua, so there is no combat gate and no reason to redo it on
    -- every Apply. Secure elements get theirs from WireSecureAttributes.
    if not el.secure and el.onClick then
        btn:SetScript("OnClick", el.onClick)
    end

    -- The tooltip contract, owned here so no element repeats it. An element's
    -- own tooltip function only adds lines. The one exception is the portals
    -- flyout's own buttons, which show their own tooltip -- they are not laid
    -- out by this file and never reach this OnEnter.
    btn:SetScript("OnEnter", function(self)
        TintTo(self, AccentRGB())
        if not Get("tbTooltips", ns.EUI_DEFAULTS.tbTooltips) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if el.tooltip then el.tooltip(GameTooltip) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        TintTo(self, REST_R, REST_G, REST_B)
        GameTooltip:Hide()
    end)

    -- HookScript, not SetScript: the tooltip handlers just above own OnEnter/
    -- OnLeave for this button, and a second SetScript would silently replace
    -- them. This just adds the fade reveal/conceal alongside.
    btn:HookScript("OnEnter", FadeReveal)
    btn:HookScript("OnLeave", FadeConceal)

    buttons[el.id] = btn
    return btn
end

local function EnsureCreated()
    if bar then return end
    -- Strata MEDIUM, deliberately not exposed as a setting.
    bar = CreateFrame("Frame", "KitnUITopBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    -- Without the clamp, a saved pixel position can be stranded off-screen by a
    -- UI scale change, past where Unlock Mode can reach it.
    bar:SetClampedToScreen(true)

    -- The fade pair, built once here so PlayFade only ever has to Play() it.
    -- Gated on tbFade inside the handlers, not here, matching how the icon
    -- handlers check tbTooltips rather than skip wiring altogether.
    bar:EnableMouse(true)
    fadeGroup = bar:CreateAnimationGroup()
    fadeAnim  = fadeGroup:CreateAnimation("Alpha")
    -- Without this an AnimationGroup snaps back to its pre-play alpha when it
    -- finishes, so a fade-in would reach 1 and then immediately revert to the
    -- rest alpha instead of holding.
    fadeGroup:SetToFinalAlpha(true)
    bar:SetScript("OnEnter", FadeReveal)
    bar:SetScript("OnLeave", FadeConceal)

    leftPanel   = CreatePanel("Left")
    centrePanel = CreatePanel("Centre")
    rightPanel  = CreatePanel("Right")

    for _, el in ipairs(ns.TopBar.Elements) do
        -- An element with no panel is not laid out by the bar and anchors itself.
        -- `fps` is the only one: it lives on its own UIParent frame under the clock.
        -- Building a button for it would silently parent it into the left panel,
        -- because the panel resolver above defaults there.
        if el.panel then CreateElementButton(el) end
    end
end

---------------------------------------------------------------------------------
-- Layout and width fit
---------------------------------------------------------------------------------

-- Symmetric auto width: padding plus the centre plus TWICE the wider side, so
-- the clock stays optically screen-centred even when the two sides hold
-- different numbers of icons.
local function FitBarWidth()
    if InCombatLockdown() then
        fitPending = true
        return
    end
    fitPending = false
    local wide = math.max(leftPanel:GetWidth(), rightPanel:GetWidth())
    bar:SetWidth(PAD + centrePanel:GetWidth() + 2 * wide)
    -- The bar has one anchor point, which derives no height, so without this
    -- GetHeight() is 0 and Unlock Mode's drag region is zero pixels tall. Take
    -- the tallest panel: the centre one is taller than the sides whenever the
    -- clock is larger than an icon.
    bar:SetHeight(math.max(leftPanel:GetHeight(),
                           centrePanel:GetHeight(),
                           rightPanel:GetHeight()))
end

-- Called from the ticker in Readouts.lua. The flag itself stays private.
function ns.TopBar.RetryFit()
    if fitPending then FitBarWidth() end
end

---------------------------------------------------------------------------------
-- Apply helpers
---------------------------------------------------------------------------------

local function ApplyPanelColors()
    if not (leftPanel and centrePanel and rightPanel) then return end

    local opacity  = Get("tbOpacity", ns.EUI_DEFAULTS.tbOpacity) / 100
    local backdrop = Get("tbBackdrop", ns.EUI_DEFAULTS.tbBackdrop) and true or false
    local r, g, b = AccentRGB()

    for _, panel in ipairs({ leftPanel, centrePanel, rightPanel }) do
        if panel._bg then
            panel._bg:SetColorTexture(0.03, 0.03, 0.04, opacity)
            if backdrop then panel._bg:Show() else panel._bg:Hide() end
        end
        if panel._accent then panel._accent:SetColorTexture(r, g, b, 1) end
    end
end

-- Nil-guarded: Readouts.lua produces this, and it owns both the clock
-- FontString and the FPS/MS readout's font, sized from tbClockSize/tbSysSize.
local function ApplyFonts()
    if ns.TopBar.ApplyReadoutFonts then ns.TopBar.ApplyReadoutFonts() end
end

-- Respects an in-progress hover: without this, changing the accent (or any
-- other Apply-triggering setting) while hovering an icon would snap it to
-- white and leave it there until the pointer moves.
local function ApplyIconColors()
    for _, btn in pairs(buttons) do
        if btn._icon then
            btn:SetScript("OnUpdate", nil)
            if btn:IsMouseOver() then
                btn._icon:SetVertexColor(AccentRGB())
            else
                btn._icon:SetVertexColor(REST_R, REST_G, REST_B)
            end
        end
    end
end

-- Rest-state reconciliation for the mouseover fade: runs on every Apply so
-- switching tbFade off, or changing it while the pointer is elsewhere, snaps
-- the bar back to visible instead of waiting for a hover.
local function ApplyFade()
    if not bar then return end
    if fadeGroup then fadeGroup:Stop() end
    if not Get("tbFade", ns.EUI_DEFAULTS.tbFade) then
        bar:SetAlpha(1)
    elseif Hovered() then
        bar:SetAlpha(1)
    else
        bar:SetAlpha(FADE_REST_ALPHA)
    end
end

local function ApplySize()
    if not bar then return end
    local size = Get("tbIconSize", ns.EUI_DEFAULTS.tbIconSize)
    for _, btn in pairs(buttons) do
        btn:SetSize(size + BTN_PAD, size + BTN_PAD)
        if btn._icon then btn._icon:SetSize(size, size) end
    end
    -- The clock button just got sized from tbIconSize above like every other
    -- button, which is wrong for it: its content is text at tbClockSize, not
    -- an icon. Readouts.lua owns the real measurement; this must run after
    -- the generic pass above or that pass would overwrite it right back.
    if ns.TopBar.SizeClockButton then ns.TopBar.SizeClockButton() end
end

local function ApplyPosition()
    if not bar then return end
    bar:ClearAllPoints()
    local pos = Get("tbPos")
    if type(pos) == "table" then
        bar:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or 0)
    else
        -- The default position, used when tbPos has never been written and by
        -- ResetPositions. Flush to the top edge.
        bar:SetPoint("TOP", UIParent, "TOP", 0, 0)
    end
end

-- Secure attribute assignment only. Non-secure click handlers are wired once
-- at creation in CreateElementButton, because they need no combat gate.
local function WireSecureAttributes()
    for id, btn in pairs(buttons) do
        local el = ns.TopBar.ById[id]
        if el and el.secure then
            -- Without this the ActionButtonUseKeyDown CVar fires on key-down
            -- and the AnyUp click never arrives.
            btn:SetAttribute("useOnKeyDown", false)
            if el.attrs then el.attrs(btn) end
        end
    end
end

-- Positions the visible buttons of one panel left-to-right from its own LEFT
-- edge, skipping any id with no matching definition, any id switched off via
-- tbOff, and any element whose `requires` says no (kitnessentials is absent,
-- not greyed out, when it is not loaded).
local function LayoutSide(panel, order, size, spacing)
    local x, tallest = 0, size
    for _, id in ipairs(order) do
        local el  = ns.TopBar.ById[id]
        local btn = buttons[id]
        if el and btn and not ns.TopBar.IsOff(id) and (not el.requires or el.requires()) then
            btn:Show()
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", panel, "LEFT", x, 0)
            -- Real width and height, not the uniform icon size. The clock
            -- button is sized from its own rendered text by SizeClockButton
            -- and is wider and taller than any launcher.
            local w, h = btn:GetWidth(), btn:GetHeight()
            x = x + w + spacing
            if h > tallest then tallest = h end
        elseif btn then
            btn:Hide()
        end
    end
    local width = x
    if width > 0 then width = width - spacing end
    panel:SetSize(math.max(1, width), tallest)
end

local function LayoutPanels()
    if not (bar and leftPanel and centrePanel and rightPanel) then return end
    local size    = Get("tbIconSize", ns.EUI_DEFAULTS.tbIconSize) + BTN_PAD
    local spacing = Get("tbSpacing", ns.EUI_DEFAULTS.tbSpacing)
    local order   = ns.TopBar.Order()

    LayoutSide(leftPanel, order.left, size, spacing)
    LayoutSide(centrePanel, order.centre, size, spacing)
    LayoutSide(rightPanel, order.right, size, spacing)

    -- Centre anchors to the bar's own centre, which SetPoint("TOP", UIParent,
    -- "TOP", ...) already keeps screen-centred regardless of the width of
    -- either side. Left and right hang off it by a fixed spacing gap.
    centrePanel:ClearAllPoints()
    centrePanel:SetPoint("TOP", bar, "TOP", 0, 0)
    leftPanel:ClearAllPoints()
    leftPanel:SetPoint("RIGHT", centrePanel, "LEFT", -spacing, 0)
    rightPanel:ClearAllPoints()
    rightPanel:SetPoint("LEFT", centrePanel, "RIGHT", spacing, 0)
end

-- Protected: the bar parents secure buttons, so Hide() on it is protected too.
-- Only ever reached from Apply()'s protected half, already gated there.
local function HideBar()
    if not bar then return end
    -- Unregister first (combat-safe -- see ApplyVisibility below): a resident
    -- "visibility" driver gets re-evaluated by Blizzard's own 0.2s tick
    -- regardless of why the bar is hidden, and a plain "show" conditional
    -- would call bar:Show() right back on the next tick otherwise.
    UnregisterStateDriver(bar, "visibility")
    bar:Hide()
    -- bar:Hide() above already drives the readout down through the OnHide hook
    -- Readouts.lua installs. This is belt and braces for the case where that
    -- hook has not been installed yet, and it is a plain Hide on an unprotected
    -- frame, so it costs nothing.
    local sys = _G.KitnUITopBarSys
    if sys then sys:Hide() end
end

---------------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------------

-- Own frame and own pending flag, deliberately separate from deferFrame/
-- pendingApply below: registering a state driver (or re-Show()ing after an
-- unregister) performs a Show()/Hide() on `bar` synchronously and on the
-- caller's own taint, so it must queue its own retry rather than share
-- Apply()'s.
local visibilityPending = false
local visibilityEvents = CreateFrame("Frame")
visibilityEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
visibilityEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visibilityEvents:RegisterEvent("CHALLENGE_MODE_START")
visibilityEvents:RegisterEvent("CHALLENGE_MODE_COMPLETED")
visibilityEvents:RegisterEvent("CHALLENGE_MODE_RESET")

local function DeferVisibility()
    if visibilityPending then return end
    visibilityPending = true
    visibilityEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Serious content: keystone, raid, or RATED PvP. None of those are reachable
-- from a macro conditional, so this is Lua, not conditional text, and it
-- selects WHICH conditional BuildConditional registers rather than being
-- part of the conditional string itself. Declared ahead of BuildConditional,
-- which calls it, because Lua 5.1 cannot see a local declared later.
local function SeriousContent()
    if not Get("tbHideSerious", false) then return false end

    local _, kind = IsInInstance()
    if kind == "raid" then return true end

    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then return true end

    -- RATED, not "any arena", and two mistakes are avoided here. Branching on
    -- the "arena" instance type would catch skirmishes; less obviously, so does
    -- IsRatedArena() ALONE. Blizzard's own match code reads
    -- `IsRatedArena() and not IsArenaSkirmish()`, so the skirmish exclusion is
    -- the actual semantics, not belt and braces.
    --
    -- IsArenaSkirmish is a GLOBAL, not a C_PvP member. Reaching for
    -- C_PvP.IsArenaSkirmish yields nil and the exclusion silently never fires.
    local P = _G.C_PvP
    if P then
        local skirmish = _G.IsArenaSkirmish and _G.IsArenaSkirmish()
        if not skirmish then
            if P.IsRatedArena and P.IsRatedArena() then return true end
        end
        if P.IsRatedBattleground and P.IsRatedBattleground() then return true end
        if P.IsRatedMap and P.IsRatedMap() then return true end
    end

    return false
end

-- Built from the switches, never typed by the user.
local function BuildConditional()
    local hide = {}
    if Get("tbHideCombat", false)    then hide[#hide + 1] = "combat"    end
    if Get("tbHidePetBattle", true)  then hide[#hide + 1] = "petbattle" end
    if Get("tbHideVehicle", false)   then hide[#hide + 1] = "vehicleui" end
    if SeriousContent() then return "hide" end
    if #hide == 0 then return "show" end
    return "[" .. table.concat(hide, "][") .. "] hide; show"
end

-- Called from Apply(), behind Apply()'s own combat check, and directly by the
-- event frame below, which CAN fire mid-combat -- a keystone completing during a
-- fight is the normal case, not the edge case.
--
-- NONE of RegisterStateDriver, UnregisterStateDriver or bar:Show() are
-- combat-safe from here, so all three sit behind the gate. UnregisterStateDriver
-- looks safe and is not: UnregisterAttributeDriver sets "setframe" first, and
-- that branch calls Show() on Blizzard's own SecureStateDriverManager -- a
-- protected frame -- on OUR taint, because we are the one calling SetAttribute.
function ns.TopBar.ApplyVisibility()
    if not bar then return end
    -- A disabled bar keeps its frame alive for the rest of the session --
    -- HideBar() only unregisters the driver and hides it, it does not clear
    -- the `bar` upvalue -- so without this guard a zone change, a hearth, or
    -- an instance entry after the user disables the bar would resolve
    -- BuildConditional() and call bar:Show() (or register a "show" driver)
    -- right back, resurrecting a disabled bar on the next loading screen.
    -- HideBar() already owns the disabled end state; Apply() re-enters this
    -- function when the user re-enables, so nothing else has to change.
    if not ns.TopBar.Enabled() then return end
    ApplyFade()

    -- THE FPS/MS READOUT IS DELIBERATELY NOT DRIVEN. It follows the bar through
    -- Readouts.lua's OnShow/OnHide hooks on this frame instead, because a second
    -- state driver looks tidier and is not.
    --
    -- A registered driver is re-resolved by Blizzard's 0.2s tick, and a `show`
    -- result calls frame:Show() unconditionally with no change test. Releasing a
    -- driver is protected. So: the user switches the readout off during combat,
    -- Apply()'s first half hides it, Apply bails at the combat gate before the
    -- driver can be released, and the next tick shows the readout straight back
    -- for the rest of the fight. The off switch has to outrank every visibility
    -- rule, and a driver cannot be taken away when it needs to be.
    --
    -- Following the bar's shown state has none of that: showing and hiding an
    -- unprotected frame is safe in combat, so the decision lands when it is made,
    -- and it reads the outcome of this rule rather than being a second one.
    local cond = BuildConditional()
    if cond == "show" then
        -- No driver needed for a plain "show": Blizzard's own 0.2s tick
        -- would just keep re-resolving a no-op. Unregistering also means a
        -- bar the driver had hidden needs an explicit Show() to come back.
        if InCombatLockdown() then DeferVisibility() return end
        UnregisterStateDriver(bar, "visibility")
        bar:Show()
        return
    end

    if InCombatLockdown() then DeferVisibility() return end
    RegisterStateDriver(bar, "visibility", cond)
end

-- Re-evaluates on its own trigger events rather than waiting for the next
-- Apply(). CHALLENGE_MODE_COMPLETED and CHALLENGE_MODE_RESET matter most:
-- without them the "hide" driver registered at keystone start survives the
-- key ending and persists until some unrelated zone event happens to fire.
-- PLAYER_REGEN_ENABLED is only ever registered by DeferVisibility above,
-- and unregisters itself here once the deferred change lands, matching
-- deferFrame's own clear-before-retry pattern below.
visibilityEvents:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        visibilityPending = false
    end
    ns.TopBar.ApplyVisibility()
end)

---------------------------------------------------------------------------------
-- Apply funnel
---------------------------------------------------------------------------------

local pendingApply = false

-- One frame at file scope. Apply() is the only thing that arms it.
local deferFrame = CreateFrame("Frame")
deferFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    -- Cleared HERE, before the retry, and nowhere else. Clearing it on only one
    -- of Apply's exits is how the queue wedges: a deferred apply that finds the
    -- feature disabled would leave the flag set and swallow every later Defer().
    pendingApply = false
    ns.TopBar.Apply()
end)

local function Defer()
    if pendingApply then return end
    pendingApply = true
    deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function ns.TopBar.Apply()
    -- Ticker reconciliation FIRST, ahead of every gate. Starting and stopping a
    -- timer is not protected, and the design classifies it as combat-safe. Behind
    -- the gate, switching the bar off mid-fight would leave its ticker running
    -- until combat ended.
    --
    -- Running it here means it can be reached BEFORE the bar exists, on the
    -- enabled-in-combat path. UpdateTicker must therefore cancel unconditionally
    -- when disabled but start only once the readout exists.
    if ns.TopBar.UpdateTicker then ns.TopBar.UpdateTicker() end

    -- CREATION IS PROTECTED, so it cannot happen before the gate. Once the bar
    -- parents secure buttons, creating more of them in combat is unsafe, and so
    -- is hiding the bar.
    if not bar then
        -- Enabled check first: a disabled bar that does not exist has nothing to
        -- defer, and deferring it would arm the queue for no reason.
        if not ns.TopBar.Enabled() then return end
        if InCombatLockdown() then Defer() return end
        EnsureCreated()
        -- AGAIN, and this one is load-bearing. The call at the top of Apply ran
        -- while the readout did not exist yet and correctly refused to start
        -- anything. Without this second call the deferred retry that finally
        -- builds the bar leaves the ticker off until some unrelated later Apply.
        if ns.TopBar.UpdateTicker then ns.TopBar.UpdateTicker() end
    end

    if not ns.TopBar.Enabled() then
        -- Also protected: a frame parenting secure buttons cannot be hidden the
        -- ordinary way in combat. The state driver handles combat hiding; this
        -- path is the user switching the feature off, which can wait.
        if InCombatLockdown() then Defer() return end
        HideBar()
        return
    end

    -- Half one: nothing here is protected, so it lands even mid-fight.
    ApplyPanelColors()
    ApplyFonts()
    ApplyIconColors()

    -- The bail. The flag coalesces a burst of option changes into one deferred
    -- apply instead of a dozen queued ones.
    if InCombatLockdown() then Defer() return end

    -- Half two: every line below is protected.
    ApplySize()
    ApplyPosition()
    if ns.TopBar.ApplyVisibility then ns.TopBar.ApplyVisibility() end
    WireSecureAttributes()
    LayoutPanels()
    FitBarWidth()
end

---------------------------------------------------------------------------------
-- Public state
---------------------------------------------------------------------------------

function ns.TopBar.Enabled()
    return Get("tbEnabled", ns.EUI_DEFAULTS.tbEnabled) and true or false
end

function ns.TopBar.SetEnabled(v)
    Set("tbEnabled", v and true or false)
    ns.TopBar.Apply()
end

function ns.TopBar.Frame()
    return bar
end

-- ApplyPosition falls back to the default top-centre anchor whenever tbPos is
-- absent, so clearing it here is enough; Apply() puts the bar back on screen.
-- tbSysPos gets the same treatment: clearing it drops the FPS/MS readout
-- back to following the clock the next time Readouts.lua repositions it.
function ns.TopBar.ResetPositions()
    Set("tbPos", nil)
    Set("tbSysPos", nil)
    ns.TopBar.Apply()
end

-- Reset/uninstall teardown. Order is load-bearing: EllesmereUI's own FPS counter
-- comes back FIRST, so a caller that throws partway through never strands the
-- counter hidden with no bar left to give it back.
function ns.TopBar.Teardown()
    -- 1. Nil-guarded: Readouts.lua may not have loaded.
    if ns.TopBar.SuppressEUIFps then ns.TopBar.SuppressEUIFps(false) end

    -- 2. The FPS readout frame is local to Readouts.lua; reach it by its
    -- global name the same way SuppressEUIFps reaches EUI_FPSCounter. A plain
    -- Hide is enough: the readout carries no driver of its own (see
    -- ApplyVisibility), so nothing will show it back.
    local sysFrame = _G.KitnUITopBarSys
    if sysFrame then sysFrame:Hide() end

    -- 3. Protected: the bar parents secure buttons, so hiding it is protected
    -- too. The only caller (ns.EUIResetAll) already refuses in combat before
    -- it ever reaches here, so a deferral here would be dead code -- return
    -- early instead.
    if InCombatLockdown() then return end
    HideBar()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

-- Core.lua already hooks SwitchProfile, OnSpecSwitchComplete and
-- ApplyProfileData into ns.EUIQueueReapply, so registering here is enough.
ns.EUIRegisterReapply(function()
    ns.TopBar.Apply()
end)

---------------------------------------------------------------------------------
-- Unlock Mode
---------------------------------------------------------------------------------

local function RegisterUnlock()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterUnlockElements and EUI.MakeUnlockElement) then return end

    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key   = "KitnUI_TopBar",
            label = "KitnUI Top Bar",
            group = "KitnUI",
            order = 1,
            -- The bar auto-fits on every Apply, so a resize handle would be
            -- overwritten by the next one.
            noResize = true,
            isHidden = function() return not ns.TopBar.Enabled() end,
            -- Deliberately does NOT create. EllesmereUI calls this
            -- unconditionally on login and every zone change, before its own
            -- combat gate and without consulting isHidden, so creating here
            -- would build the bar and its secure buttons in combat for a user
            -- who has the feature switched off. Apply() owns creation.
            getFrame = function() return bar end,
            getSize = function()
                if not bar then return 1, 1 end
                return bar:GetWidth(), bar:GetHeight()
            end,
            -- Save the dragged position by replacing tbPos wholesale.
            savePos = function(_, point, relPoint, x, y)
                Set("tbPos", { point = point, relPoint = relPoint, x = x, y = y })
            end,
            -- Hand back a copy: Unlock Mode is free to keep or mutate what it
            -- is given.
            loadPos = function()
                local p = Get("tbPos")
                if type(p) ~= "table" then return nil end
                return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
            end,
            clearPos = function() Set("tbPos", nil) end,
            applyPos = ApplyPosition,
        }),
    }, "KitnUI_EUI")
end

-- Its own frame: registering with Unlock Mode has nothing to do with
-- EllesmereUI's config panel capability, so it must not share Core.lua's
-- RegisterModule/Widgets gate. Registered even while the bar is off; the
-- hooks above cope with a bar that does not exist yet.
local unlockBoot = CreateFrame("Frame")
unlockBoot:RegisterEvent("PLAYER_LOGIN")
unlockBoot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    RegisterUnlock()
end)
