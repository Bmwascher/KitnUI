-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/TopBar/Readouts.lua                              ║
-- ║  Purpose: The clock and the FPS/latency readout. Everything  ║
-- ║           with a ticker: text, colour bands, tooltips, its   ║
-- ║           own Unlock Mode element and the EUI FPS suppress.  ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.TopBar = ns.TopBar or {}

local Get, Set = ns.TopBar.Get, ns.TopBar.Set

---------------------------------------------------------------------------------
-- Colour bands. Fixed by the spec, not user-configurable.
---------------------------------------------------------------------------------

local function FpsColor(v)
    if v >= 60 then return 0.3, 1, 0.3 end
    if v >= 30 then return 1, 0.85, 0.3 end
    return 1, 0.35, 0.3
end

local function MsColor(v)
    if v <= 100 then return 0.3, 1, 0.3 end
    if v <= 250 then return 1, 0.85, 0.3 end
    return 1, 0.35, 0.3
end

-- The bar's own accent resolution, duplicated rather than exported: Bar.lua's
-- AccentRGB is file-local, and this file's only consumable interfaces are
-- Get/Set and Frame().
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

local function Hex(r, g, b)
    return format("%02x%02x%02x", math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5), math.floor((b or 1) * 255 + 0.5))
end

---------------------------------------------------------------------------------
-- The clock. clockText is created lazily, the first time ApplyReadoutFonts
-- runs, because it attaches to KitnUITopBar_clock — the button Bar.lua's
-- unmodified CreateElementButton makes for the "clock" element registered in
-- Elements.lua — which only exists once the bar itself has been built.
--
-- The FPS readout further down is EAGER, and the difference is deliberate
-- rather than two minds about it. The clock has a parent that does not exist
-- until the bar does; the readout is parented to UIParent and never needed the
-- bar at all, so there was nothing to wait for.
---------------------------------------------------------------------------------

local clockText

-- NaowhUI's own clock button padding:
-- References/NaowhUI-20260721.01/NaowhUI_EUI/NaowhUI_TopBar.lua:51.
local CLOCK_PAD = 6

-- The clock button cannot be sized from tbIconSize like the launchers: its
-- content is text at tbClockSize, which is wider and taller than any icon.
-- Bar.lua's ApplySize calls this after its generic pass, so the centre panel
-- and FitBarWidth measure the real rendered width. GetStringWidth on an
-- empty FontString returns 0, so this only matters once ApplyReadoutFonts
-- has already set the text — which, in Apply()'s own call order, it always
-- has by the time ApplySize runs.
function ns.TopBar.SizeClockButton()
    local btn = _G.KitnUITopBar_clock
    if not (btn and clockText) then return end
    -- Padding is asymmetric on purpose: a full CLOCK_PAD on each side
    -- horizontally, half that vertically. The bar's height is driven by the
    -- tallest panel, so vertical padding on the clock pushes the whole bar
    -- taller, while horizontal padding only widens the centre panel. NaowhUI
    -- pads horizontally and not at all vertically for the same reason.
    btn:SetSize(clockText:GetStringWidth() + CLOCK_PAD * 2,
                clockText:GetStringHeight() + CLOCK_PAD)
end

local function ClockString()
    local hour, minute
    if Get("tbServerTime", ns.EUI_DEFAULTS.tbServerTime) then
        hour, minute = GetGameTime()
    else
        hour, minute = tonumber(date("%H")), tonumber(date("%M"))
    end
    if not (hour and minute) then return "--:--" end
    if Get("tbUse24h", ns.EUI_DEFAULTS.tbUse24h) then
        return format("%02d:%02d", hour, minute)
    end
    local h12 = hour % 12
    if h12 == 0 then h12 = 12 end
    return format("%d:%02d %s", h12, minute, hour < 12 and "AM" or "PM")
end

local function UpdateClock()
    if not clockText then return end
    clockText:SetText(ClockString())
end

---------------------------------------------------------------------------------
-- The FPS/latency readout. Parented to UIParent, not to the bar, and created
-- unconditionally at file load: it has no secure template and no dependency
-- on the bar existing, so eager creation costs nothing and guarantees
-- UpdateTicker (below) already has a readout to check the very first time
-- Apply() reaches it.
---------------------------------------------------------------------------------

local sysFrame = CreateFrame("Frame", "KitnUITopBarSys", UIParent)
sysFrame:SetClampedToScreen(true)
sysFrame:SetSize(1, 1)
sysFrame:Hide()

local sysText = sysFrame:CreateFontString(nil, "OVERLAY")
sysText:SetPoint("CENTER")
-- Font before text: WoW throws "Font not set" the other way round, and
-- nothing else here ever calls SetText before this line runs.
sysText:SetFont(STANDARD_TEXT_FONT, Get("tbSysSize", ns.EUI_DEFAULTS.tbSysSize), "OUTLINE")

local function ApplyReadoutPosition()
    if not sysFrame then return end
    sysFrame:ClearAllPoints()
    local pos = Get("tbSysPos")
    if type(pos) == "table" then
        sysFrame:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or 0)
        return
    end
    -- Default: two pixels below the bar, matching
    -- References/NaowhUI-20260721.01/NaowhUI_EUI/NaowhUI_TopBar.lua:525.
    -- Anchoring against a hidden bar resolves normally, so this stays put
    -- even while a later visibility rule hides it.
    local barFrame = ns.TopBar.Frame()
    if barFrame then
        sysFrame:SetPoint("TOP", barFrame, "BOTTOM", 0, -2)
    else
        sysFrame:SetPoint("TOP", UIParent, "TOP", 0, -40)
    end
end
ApplyReadoutPosition()

local function BuildSysText(fps, home)
    local ar, ag, ab = AccentRGB()
    local accentHex = Hex(ar, ag, ab)
    local fpsStr = fps and format("|cff%s%d|r", Hex(FpsColor(fps)), fps) or "|cff808080--|r"
    local msStr  = home and format("|cff%s%d|r", Hex(MsColor(home)), home) or "|cff808080--|r"
    return format("%s |cff%sfps|r  %s |cff%sms|r", fpsStr, accentHex, msStr, accentHex)
end

local function UpdateSys()
    if not sysText then return end
    local fps = GetFramerate()
    local home = select(3, GetNetStats())
    fps = fps and math.floor(fps + 0.5)
    home = home and math.floor(home)
    sysText:SetText(BuildSysText(fps, home))
    if sysFrame then
        sysFrame:SetSize(math.max(1, sysText:GetStringWidth() or 1), math.max(1, sysText:GetStringHeight() or 1))
    end
end

---------------------------------------------------------------------------------
-- The FPS/latency tooltip. The memory scan is a frame spike, so it is
-- throttled to once every 30 seconds, reusing one table and one hoisted
-- comparator so a rescan allocates nothing. NaowhUI throttles it for the
-- same reason.
---------------------------------------------------------------------------------

local _memTable, _lastMemScan = {}, 0
local function ByMemDesc(a, b) return a.mem > b.mem end

local function ShowSysTooltip(owner)
    local ar, ag, ab = AccentRGB()
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("FPS and Latency", 1, 1, 1)

    local fps = GetFramerate()
    local _, _, home, world = GetNetStats()
    if fps then
        GameTooltip:AddDoubleLine("FPS", format("%d fps", fps), 0.7, 0.7, 0.7, FpsColor(fps))
    end
    if home then
        GameTooltip:AddDoubleLine("Home Latency", format("%d ms", home), 0.7, 0.7, 0.7, MsColor(home))
    end
    if world then
        GameTooltip:AddDoubleLine("World Latency", format("%d ms", world), 0.7, 0.7, 0.7, MsColor(world))
    end

    local now = GetTime()
    if (now - _lastMemScan) >= 30 then
        _lastMemScan = now
        UpdateAddOnMemoryUsage()
        local count = 0
        -- GetAddOnMemoryUsage takes the addon NAME in 12.0, not the index —
        -- confirmed against .wow-api-reference/Interface/AddOns/Blizzard_AddOnList/AddonList.lua:866.
        for i = 1, C_AddOns.GetNumAddOns() do
            local name, title = C_AddOns.GetAddOnInfo(i)
            local mem = name and GetAddOnMemoryUsage(name)
            if mem and mem > 0 then
                count = count + 1
                local e = _memTable[count]
                if not e then e = {}; _memTable[count] = e end
                e.name = title or name
                e.mem = mem
            end
        end
        for i = count + 1, #_memTable do _memTable[i] = nil end
        table.sort(_memTable, ByMemDesc)
    end

    if #_memTable > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Addon Memory", ar, ag, ab)
        for i = 1, math.min(10, #_memTable) do
            local e = _memTable[i]
            local memStr = e.mem > 1024 and format("%.2f MB", e.mem / 1024) or format("%.0f KB", e.mem)
            GameTooltip:AddDoubleLine(e.name, memStr, 1, 1, 1, ar, ag, ab)
        end
    end
    GameTooltip:Show()
end

sysFrame:EnableMouse(true)
sysFrame:SetScript("OnEnter", function(self)
    if not Get("tbTooltips", ns.EUI_DEFAULTS.tbTooltips) then return end
    ShowSysTooltip(self)
end)
sysFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------------
-- Suppress EllesmereUI's own FPS counter. We hide the FRAME and never touch
-- EllesmereUI's showFPS setting. That is what makes this free: no profile
-- write, no undo record, no spec-override banking, and it is safe in combat
-- because the frame is not secure.
---------------------------------------------------------------------------------

function ns.TopBar.SuppressEUIFps(on)
    local f = _G.EUI_FPSCounter
    if not f then return end
    if on then f:Hide() else
        -- Only give it back if the user's own setting wants it. Their setting
        -- is the authority; we were only ever hiding the frame.
        if EllesmereUI and EllesmereUI.QoLExtrasGet
           and EllesmereUI.QoLExtrasGet("showFPS") then f:Show() end
    end
end

-- Re-assert the hide after anything that might restore EllesmereUI's own
-- counter. Profile and spec switches are already covered: they run through
-- Bar.lua's re-apply registration, which reaches Apply() -> UpdateTicker()
-- below on every one of them.
if EllesmereUI and EllesmereUI._applyFPSCounter then
    hooksecurefunc(EllesmereUI, "_applyFPSCounter", function()
        ns.TopBar.SuppressEUIFps(ns.TopBar.Enabled() and not ns.TopBar.IsOff("fps"))
    end)
end

---------------------------------------------------------------------------------
-- Fonts: Bar.lua's ApplyFonts() calls this on every Apply() once the bar
-- exists and the feature is enabled. It lazily attaches clockText to the
-- clock button the first time it runs, then (re)sizes both readouts from
-- tbClockSize/tbSysSize and refreshes their text immediately, so the size
-- sliders and the 24h/server-time toggles all take effect live.
---------------------------------------------------------------------------------

function ns.TopBar.ApplyReadoutFonts()
    local clockBtn = _G.KitnUITopBar_clock
    if clockBtn and not clockText then
        clockText = clockBtn:CreateFontString(nil, "OVERLAY")
        clockText:SetPoint("CENTER")
    end
    if clockText then
        clockText:SetFont(STANDARD_TEXT_FONT, Get("tbClockSize", ns.EUI_DEFAULTS.tbClockSize), "OUTLINE")
        UpdateClock()
    end

    if sysText then
        sysText:SetFont(STANDARD_TEXT_FONT, Get("tbSysSize", ns.EUI_DEFAULTS.tbSysSize), "OUTLINE")
        UpdateSys()
    end
    ApplyReadoutPosition()
end

---------------------------------------------------------------------------------
-- The ticker
---------------------------------------------------------------------------------

local ticker

local function Tick()
    -- The FPS readout updates BEFORE the "is the bar shown" early-out, so the
    -- numbers keep moving while the bar is hidden.
    UpdateSys()
    ns.TopBar.RetryFit()
    local barFrame = ns.TopBar.Frame()
    if not (barFrame and barFrame:IsShown()) then return end
    UpdateClock()
end

-- Apply() calls this by exact name, nil-guarded, twice: once at the very top
-- (before the bar exists), and once right after EnsureCreated builds it. See
-- Bar.lua's own comments on both call sites.
function ns.TopBar.UpdateTicker()
    -- Cancel first, always. Cheap, and it is the half that must never be skipped.
    if ticker and (not ns.TopBar.Enabled() or not sysText) then
        ticker:Cancel()
        ticker = nil
    end
    -- Start only when there is something to update.
    --
    -- The `sysText` half of both gates is belt and braces: this file creates
    -- sysText eagerly at load, so it is never nil in practice. The plan wrote
    -- these guards for a lazily-created readout, and they are kept because the
    -- cost is a nil check and the alternative is a ticker calling into a frame
    -- that a future refactor made lazy again. Do not read them as evidence that
    -- sysText can currently be nil.
    if ns.TopBar.Enabled() and sysText and not ticker then
        ticker = C_Timer.NewTicker(1, Tick)
    end

    -- fps's own visibility, and EllesmereUI's counter suppression, track the
    -- same enabled/off state. This runs on every Apply(), including the
    -- profile- and spec-switch reapply Bar.lua already wires up, and neither
    -- line touches anything protected.
    local showSys = ns.TopBar.Enabled() and not ns.TopBar.IsOff("fps")
    if sysFrame then
        if showSys then sysFrame:Show() else sysFrame:Hide() end
    end
    ns.TopBar.SuppressEUIFps(showSys)
end

---------------------------------------------------------------------------------
-- Unlock Mode: the FPS readout's own element, separate from the bar's, so it
-- can be dragged anywhere and stays there. Default is to follow the clock; a
-- saved tbSysPos wins. ns.TopBar.ResetPositions() (Bar.lua) clears both.
---------------------------------------------------------------------------------

local function RegisterSysUnlock()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterUnlockElements and EUI.MakeUnlockElement) then return end

    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key   = "KitnUI_TopBarFPS",
            label = "KitnUI FPS / MS Readout",
            group = "KitnUI",
            order = 2,
            noResize = true,
            isHidden = function() return not ns.TopBar.Enabled() or ns.TopBar.IsOff("fps") end,
            -- Deliberately does NOT create. EllesmereUI's ApplySavedPositions
            -- calls every registered element's getFrame unconditionally on
            -- login and every zone change, before its own combat gate and
            -- without consulting isHidden (EUI_UnlockMode.lua:4271-4276).
            -- sysFrame already exists unconditionally above (it carries no
            -- secure template, so eager creation costs nothing); this just
            -- hands it back, or nil if that creation somehow never ran.
            getFrame = function() return sysFrame end,
            getSize = function()
                if not sysFrame then return 1, 1 end
                return sysFrame:GetWidth(), sysFrame:GetHeight()
            end,
            savePos = function(_, point, relPoint, x, y)
                Set("tbSysPos", { point = point, relPoint = relPoint, x = x, y = y })
            end,
            loadPos = function()
                local p = Get("tbSysPos")
                if type(p) ~= "table" then return nil end
                return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
            end,
            clearPos = function() Set("tbSysPos", nil) end,
            applyPos = ApplyReadoutPosition,
        }),
    }, "KitnUI_EUI")
end

local unlockBoot = CreateFrame("Frame")
unlockBoot:RegisterEvent("PLAYER_LOGIN")
unlockBoot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    RegisterSysUnlock()
end)
