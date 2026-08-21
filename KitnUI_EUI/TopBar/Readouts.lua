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
-- Readout colours. The FPS and latency numbers are plain white. A green/amber/
-- red threshold band sat on green nearly all the time, so it read as decoration
-- rather than as information.
--
-- The grey "--" stays. It is the absence of a reading, not a quality rating,
-- and it has to look different from a real number.
---------------------------------------------------------------------------------

local WHITE_HEX = "ffffff"

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
-- The clock. clockText is created lazily, on the first ApplyReadoutFonts run,
-- because its parent (KitnUITopBar_clock, built by Bar.lua from the "clock"
-- element) does not exist until the bar does.
--
-- The FPS readout below is EAGER by contrast, and deliberately so: it is
-- parented to UIParent, so it never had anything to wait for.
---------------------------------------------------------------------------------

local clockText

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
    -- taller, while horizontal padding only widens the centre panel.
    btn:SetSize(clockText:GetStringWidth() + CLOCK_PAD * 2,
                clockText:GetStringHeight() + CLOCK_PAD)
end

-- Split out of ClockString so the clock's own tooltip can print realm time and
-- local time side by side in the same 12h/24h style the face is using.
local function FormatHM(hour, minute)
    if not (hour and minute) then return "--:--" end
    if Get("tbUse24h", ns.EUI_DEFAULTS.tbUse24h) then
        return format("%02d:%02d", hour, minute)
    end
    local h12 = hour % 12
    if h12 == 0 then h12 = 12 end
    return format("%d:%02d %s", h12, minute, hour < 12 and "AM" or "PM")
end

local function ClockString()
    if Get("tbServerTime", ns.EUI_DEFAULTS.tbServerTime) then
        return FormatHM(GetGameTime())
    end
    return FormatHM(tonumber(date("%H")), tonumber(date("%M")))
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
    -- Default: two pixels below the bar. Anchoring against a hidden bar resolves
    -- normally, so this stays put even while a visibility rule hides it.
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
    local fpsStr = fps and format("|cff%s%d|r", WHITE_HEX, fps) or "|cff808080--|r"
    local msStr  = home and format("|cff%s%d|r", WHITE_HEX, home) or "|cff808080--|r"
    -- Upper case. Preview.lua's FPS_STRING measures the same case, so the two
    -- must be changed together.
    return format("%s |cff%sFPS|r  %s |cff%sMS|r", fpsStr, accentHex, msStr, accentHex)
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
-- The FPS/latency tooltip. The memory scan is a frame spike, so it is throttled
-- to once every 30 seconds, reusing one table and one hoisted comparator so a
-- rescan allocates nothing.
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
        GameTooltip:AddDoubleLine("FPS", format("%d fps", fps), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    if home then
        GameTooltip:AddDoubleLine("Home Latency", format("%d ms", home), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    if world then
        GameTooltip:AddDoubleLine("World Latency", format("%d ms", world), 0.7, 0.7, 0.7, 1, 1, 1)
    end

    local now = GetTime()
    if (now - _lastMemScan) >= 30 then
        _lastMemScan = now
        UpdateAddOnMemoryUsage()
        local count = 0
        -- GetAddOnMemoryUsage takes the addon NAME in 12.0, not the index.
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
            -- The NAME is another addon's own TOC title, so it can carry an
            -- escape code nothing guarantees is closed, and an open |cff bleeds
            -- into the value beside it and every row after it. The trailing |r
            -- closes one and costs nothing when there is none. The VALUE is then
            -- given white both inline and as colour arguments, so it cannot
            -- inherit from anything upstream.
            GameTooltip:AddDoubleLine(e.name .. "|r",
                format("|cff%s%s|r", WHITE_HEX, memStr), 1, 1, 1, 1, 1, 1)
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

---------------------------------------------------------------------------------
-- Suppress EllesmereUI's MINIMAP clock and FPS/MS while this bar shows its own,
-- and hand them back when it does not -- including when a visibility rule hides
-- the bar inside a key or a raid, which the plain enabled/off test cannot see.
--
-- Same trade as SuppressEUIFps: hide the FRAME, never write the host's own
-- `clockMode` or `showFPS`. Those ride its profile export and its Spec Overrides
-- engine, so writing them on every instance entry and exit would churn a
-- database this addon does not own. Reachable at all only because the minimap
-- module publishes both frames as globals; they are file-local otherwise.
--
-- A GLOBAL THAT IS NIL IS NOT THE SAME AS A SETTING THAT IS OFF. The host
-- assigns them only on its ENABLED branch and never clears them, so a frame it
-- has since switched off still answers here. Taking that one and handing it back
-- would put a clock on a minimap the user had turned off. Shown-state at take
-- time is what settles it, below.
---------------------------------------------------------------------------------

-- Not a boolean. Each held key records what the HOST last wanted -- "shown" or
-- "hidden" -- so the restore gives back only what it actually took. Both values
-- are truthy, so "are we holding this" is still a plain test.
local minimapTaken = {}

-- Set only across a Hide this file issues. The Hide hook below must tell the
-- host switching a readout OFF apart from us holding it down, and those are the
-- same call. Without this flag one of the two has to be guessed, and guessing
-- wrong in either direction is a wrong frame on the user's minimap.
local minimapOurHide = {}

local function TakeMinimapFrame(key, f)
    minimapOurHide[key] = true
    f:Hide()
    minimapOurHide[key] = nil
end

local function SuppressMinimapFrame(key, on)
    local f = _G[key]
    if not f then return end
    if not f._kitnSuppressHook then
        f._kitnSuppressHook = true
        -- EllesmereUI re-shows these on its own refresh, so a one-shot Hide is
        -- undone by the next options change or minimap redraw. The hook makes
        -- the suppression stick without polling for it.
        hooksecurefunc(f, "Show", function(self)
            if not minimapTaken[key] then return end
            -- The host asking for this frame IS the host's own setting saying it
            -- wants it. Record that before hiding it again, so a frame switched
            -- ON while we hold it is still given back when we let go.
            minimapTaken[key] = "shown"
            TakeMinimapFrame(key, self)
        end)
        -- The mirror of the Show hook, and the reason the flag above exists.
        -- EllesmereUI's disabled branches call Hide() straight out, so a readout
        -- switched OFF while we are holding it looks like nothing at all from
        -- here -- and the release would then hand back a frame the user had just
        -- turned off.
        hooksecurefunc(f, "Hide", function()
            if minimapTaken[key] and not minimapOurHide[key] then
                minimapTaken[key] = "hidden"
            end
        end)
    end
    if on then
        if not minimapTaken[key] then
            minimapTaken[key] = f:IsShown() and "shown" or "hidden"
            TakeMinimapFrame(key, f)
        end
    elseif minimapTaken[key] then
        -- Give back only what we took, which means what the host last wanted. A
        -- frame it had already hidden, or hid while we held it, goes back hidden.
        local wasShown = (minimapTaken[key] == "shown")
        -- Cleared BEFORE the Show, so the Show hook above reads us as no longer
        -- holding it and lets the frame through.
        minimapTaken[key] = nil
        if wasShown then f:Show() end
    end
end

-- Derived from what is ACTUALLY on screen rather than from the visibility rules,
-- so it stays correct however those rules change. Two frames decide it: the
-- clock is part of the bar, and the FPS readout follows the bar separately.
--
-- HOW MANY FPS COUNTERS THE PLAYER ENDS UP WITH IS ELLESMEREUI'S ANSWER, NOT
-- OURS. It ships TWO independent ones, each with its own switch. We take both
-- while ours is up and give back exactly what we took, so both host switches on
-- returns two and both off returns none. Choosing one for the player would mean
-- overruling a configuration this addon does not own.
--
-- A frame that does not exist yet cannot be hooked, which is the hole the bridge
-- hook below closes. `SuppressMinimapFrame` returns early on a nil global, so a
-- readout enabled for the FIRST TIME while we are suppressing would be built and
-- shown by the host with nothing watching it, and would sit beside ours. The
-- host publishes its minimap apply as a bridge, so re-running the pass after it
-- catches that frame. Hooked LAZILY, because the bridge is assigned during the
-- minimap module's own init and this file cannot assume that has happened.
--
-- THE BRIDGE ALONE IS NOT ENOUGH. hooksecurefunc wraps a GLOBAL and sees only
-- the calls made through it. In combat the host's apply refuses and merely
-- queues; when the fight ends it calls its LOCAL apply upvalue instead, so a
-- readout enabled mid-fight is created where our hook never fires and nothing
-- else reconciles. The regen retry below is what closes that.
local minimapApplyHooked
local minimapRegenFrame
-- Forward-declared: the retry frame's handler calls it, and it is defined below.
local RefreshMinimapSuppression

local function ArmMinimapRegenRetry()
    if not minimapRegenFrame then
        minimapRegenFrame = CreateFrame("Frame")
        minimapRegenFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            -- NEXT frame, not this one. The host flushes its deferred apply from
            -- its OWN PLAYER_REGEN_ENABLED handler, and the order two addons'
            -- handlers run in is not defined. Waiting a frame means we read the
            -- result of that flush instead of racing it.
            C_Timer.After(0, RefreshMinimapSuppression)
        end)
    end
    -- Re-registering an event already registered is a no-op, so this coalesces
    -- a burst of applies in one fight down to a single retry on its own.
    minimapRegenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function RefreshMinimapSuppression()
    local barFrame = ns.TopBar.Frame and ns.TopBar.Frame()
    local ourClock = barFrame and barFrame:IsShown() and not ns.TopBar.IsOff("clock")
    local ourFps   = sysFrame and sysFrame:IsShown() and true or false
    SuppressMinimapFrame("_EBS_ClockBg", ourClock and true or false)
    SuppressMinimapFrame("_EBS_FpsBg", ourFps)
    ns.TopBar.SuppressEUIFps(ourFps)

    if not minimapApplyHooked and _G._EMM_ApplyMinimap then
        minimapApplyHooked = true
        -- Re-enter on the NEXT frame, never inline: this hook fires from inside
        -- the host's own apply, and hiding a frame it is still setting up would
        -- have us fighting the rest of that pass. C_Timer.After(0, ...) lets the
        -- apply finish and reads the result.
        hooksecurefunc("_EMM_ApplyMinimap", function()
            C_Timer.After(0, RefreshMinimapSuppression)
            -- That next-frame pass reads nothing useful if the host refused the
            -- apply and queued it instead, so arm the post-combat retry too.
            -- Both are cheap and the pair covers either outcome.
            if InCombatLockdown() then ArmMinimapRegenRetry() end
        end)
    end
end

-- THE FPS/MS READOUT FOLLOWS THE BAR, and follows it from here rather than from
-- a state driver of its own. Bar.lua's ApplyVisibility carries the full reason;
-- the short version is that a driver cannot be released during combat, so a
-- resident one would show the readout back after the user switched it off
-- mid-fight. Everything below is a plain Show or Hide on an unprotected frame,
-- so the decision always lands at the moment it is made, combat or not.
local function SysShouldShow()
    if not ns.TopBar.Enabled() then return false end
    if ns.TopBar.IsOff("fps") then return false end
    local barFrame = ns.TopBar.Frame and ns.TopBar.Frame()
    if not barFrame then return false end
    return barFrame:IsShown() and true or false
end

local function RefreshFollowers()
    if sysFrame then
        if SysShouldShow() then sysFrame:Show() else sysFrame:Hide() end
    end
    -- After the readout, never before: the suppression reads sysFrame:IsShown()
    -- and must see the state this pass just set.
    RefreshMinimapSuppression()
end

local minimapVisHooked
function ns.TopBar.RefreshEUIMinimap()
    -- Hooked lazily: the bar frame does not exist until the feature is first
    -- enabled, and HookScript ADDS to whatever Bar.lua already set.
    if not minimapVisHooked then
        local barFrame = ns.TopBar.Frame and ns.TopBar.Frame()
        if barFrame then
            minimapVisHooked = true
            -- The bar's own Show/Hide is the signal, whoever caused it -- the
            -- state driver inside a key, HideBar when the feature is switched
            -- off, or Apply. That is what makes this a follower rather than a
            -- second copy of the visibility rules.
            barFrame:HookScript("OnShow", RefreshFollowers)
            barFrame:HookScript("OnHide", RefreshFollowers)
            if sysFrame then
                sysFrame:HookScript("OnShow", RefreshMinimapSuppression)
                sysFrame:HookScript("OnHide", RefreshMinimapSuppression)
            end
        end
    end
    RefreshFollowers()
end

-- Re-assert the hide after anything that might restore EllesmereUI's own
-- counter. Profile and spec switches are already covered: they run through
-- Bar.lua's re-apply registration, which reaches Apply() -> UpdateTicker()
-- below on every one of them.
if EllesmereUI and EllesmereUI._applyFPSCounter then
    hooksecurefunc(EllesmereUI, "_applyFPSCounter", function()
        -- Shown-state, not the on/off switch: our readout can be switched on and
        -- still be hidden by a visibility rule, and in that case the host's
        -- counter is the one that should be up.
        ns.TopBar.SuppressEUIFps(sysFrame and sysFrame:IsShown() and true or false)
    end)
end

---------------------------------------------------------------------------------
-- Friends and guild badges, and the Great Vault tooltip. Counts render
-- unconditionally; the roster NAME LISTS are gated behind RosterReadable(): in
-- combat or inside a protected instance the badge keeps counting but the tooltip
-- stops listing names.
---------------------------------------------------------------------------------

-- The name lists come from C_Club, whose member APIs are marked
-- SecretInChatMessagingLockdown. That predicate covers encounter, challenge mode
-- and PvP restrictions AND "when the player is on a communication-restricted map
-- such as a dungeon or raid", with no combat requirement in that last clause.
-- EllesmereUI.InProtectedInstance() is narrower: it wants combat as well for
-- raid and pvp, and Challenge Mode for party. So test the instance type directly
-- and keep the host's helper as an additional trigger rather than the only one.
local RESTRICTED_INSTANCE = { party = true, raid = true, pvp = true, arena = true }

local function RosterReadable()
    if InCombatLockdown() then return false end
    local inInstance, instanceType = IsInInstance()
    if inInstance and RESTRICTED_INSTANCE[instanceType] then return false end
    if EllesmereUI and EllesmereUI.InProtectedInstance
       and EllesmereUI.InProtectedInstance() then return false end
    return true
end

-- Returns `accountInfo` and the LIST of game accounts this friend contributes,
-- in render order. The badge sums the list lengths and the roster draws their
-- contents, so the two cannot drift: one walk with two consumers, not two walks
-- kept in step.
--
-- A WoW friend is playing WoW by definition, so only a Battle.net friend's
-- CURRENT game is tested against tbFriendsInGameOnly. Neither FriendInfo nor
-- BNetGameAccountInfo marks any field Secret; GetFriendNumGameAccounts and
-- GetFriendGameAccountInfo mark only SecretArguments, which constrains what may
-- be passed IN and says nothing about the returns.
--
-- One Battle.net friend can be logged into several WoW accounts at once, and
-- `accountInfo.gameAccountInfo` describes only the FIRST. tbFriendsSubAccounts
-- expands a friend into their WoW accounts and ONLY those; a session in another
-- Blizzard game is not a sub account. A friend with no WoW account online still
-- falls through to the single row the off state would have given, or turning the
-- switch on would silently hide everyone playing something else.
local function BNetFriendAccounts(i, inGameOnly, subAccounts)
    local accountInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo
        and C_BattleNet.GetFriendAccountInfo(i)
    local gameInfo = accountInfo and accountInfo.gameAccountInfo
    if not (gameInfo and gameInfo.isOnline) then return nil, nil end

    if subAccounts then
        local n = (C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendNumGameAccounts(i)) or 0
        local out = {}
        for j = 1, n do
            local sub = C_BattleNet.GetFriendGameAccountInfo and C_BattleNet.GetFriendGameAccountInfo(i, j)
            if sub and sub.isOnline and sub.clientProgram == "WoW" then out[#out + 1] = sub end
        end
        if #out > 0 then return accountInfo, out end
    end

    if inGameOnly and gameInfo.clientProgram ~= "WoW" then return accountInfo, {} end
    return accountInfo, { gameInfo }
end

local function FriendsCount()
    local wowOnline = (C_FriendList and C_FriendList.GetNumOnlineFriends
        and C_FriendList.GetNumOnlineFriends()) or 0
    local inGameOnly = Get("tbFriendsInGameOnly", ns.EUI_DEFAULTS.tbFriendsInGameOnly) and true or false
    local subAccounts = Get("tbFriendsSubAccounts", ns.EUI_DEFAULTS.tbFriendsSubAccounts) and true or false
    local bnetOnline = 0
    local numBNet = (BNGetNumFriends and BNGetNumFriends()) or 0
    for i = 1, numBNet do
        local _, list = BNetFriendAccounts(i, inGameOnly, subAccounts)
        if list then bnetOnline = bnetOnline + #list end
    end
    return wowOnline + bnetOnline
end

---------------------------------------------------------------------------------
-- Class colour for the two rosters, and the guard that makes these fields safe
-- to read.
--
-- ClubMemberInfo marks only `isSelf` and `faction` NeverSecret, so every OTHER
-- field may arrive Secret. A Secret cannot be a table key and cannot be
-- concatenated -- both throw -- so nothing reaches a lookup, a concatenation or
-- a format without passing Plain() first.
--
-- Plain() guards those unsafe operations, not every read. Bare truth-tests and
-- equality against a literal are left raw on the BNet and FriendList paths,
-- where the fields involved declare no Secret marking at all. On the guild path
-- `name` is the one field that genuinely can be Secret, and it goes through
-- Plain() BEFORE it is tested. What a Secret does under a bare truth-test is NOT
-- decidable from the static reference, so nothing here depends on it.
---------------------------------------------------------------------------------

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The exact path: classID -> classFile -> RAID_CLASS_COLORS. Guild members and
-- Battle.net friends both carry a numeric classID, and C_CreatureInfo
-- .GetClassInfo declares no SecretReturns, so no locale guessing is involved.
local function ClassColorFromID(classID)
    classID = Plain(classID)
    if type(classID) ~= "number" then return nil end
    local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
    local file = info and Plain(info.classFile)
    if type(file) ~= "string" then return nil end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    if not c then return nil end
    return c.r, c.g, c.b
end

-- The inexact path, and the only one available for a plain WoW friend:
-- FriendInfo carries a LOCALISED `className` and nothing else about class.
-- Reversing the client's own localised tables is correct in every language it
-- ships, because both sides come from the same client. It can fail only where a
-- locale gives two DIFFERENT classes the same word, and such a word resolves to
-- no colour at all: a white name is a fallback a reader can ignore, a
-- confidently wrong class colour is one they would act on.
--
-- Both source tables are keyed by classFile and hold every class, so the SAME
-- classFile appearing in both is the ordinary case, not a collision. Only a
-- second, DIFFERENT classFile claiming a word already taken poisons it.
--
-- Built once on first use rather than at load: the source tables all exist by
-- the time a roster hover needs them.
local localizedClassColor
local function ClassColorFromLocalizedName(className)
    className = Plain(className)
    if type(className) ~= "string" or className == "" then return nil end
    if not localizedClassColor then
        localizedClassColor = {}
        local claimedBy = {}
        local function Absorb(tbl)
            if type(tbl) ~= "table" then return end
            for file, localized in pairs(tbl) do
                local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
                if c and type(localized) == "string" then
                    local owner = claimedBy[localized]
                    if owner == nil then
                        claimedBy[localized] = file
                        localizedClassColor[localized] = c
                    elseif owner ~= file then
                        -- Ambiguous word: no colour, so the name renders white.
                        localizedClassColor[localized] = nil
                    end
                end
            end
        end
        Absorb(LOCALIZED_CLASS_NAMES_MALE)
        Absorb(LOCALIZED_CLASS_NAMES_FEMALE)
    end
    local c = localizedClassColor[className]
    if not c then return nil end
    return c.r, c.g, c.b
end

local ROSTER_CAP = 40

-- Both rosters draw two-column rows and overflow the same way, so the row writer
-- and the overflow line live here once. Counting CONTINUES past the cap rather
-- than breaking, so the trailing line can say how many were left out.
--
-- Rows are COLLECTED and only drawn by Finish: a heading has to be printed above
-- rows whose existence is not known until the walk is done. Guild rows pass no
-- group and land in one unnamed group, which draws as an ungrouped list.
--
-- The cap counts ROWS, never headings. Letting a heading take a slot would make
-- the badge and the list disagree by the number of games friends are playing.
local function NewRoster(tt)
    local groups, order, rows = {}, {}, 0
    return {
        Row = function(left, right, r, g, b, key, label, sortKey)
            key = key or ""
            local grp = groups[key]
            if not grp then
                grp = { label = label, sort = sortKey or 0, seq = #order, rows = {} }
                groups[key] = grp
                order[#order + 1] = grp
            end
            grp.rows[#grp.rows + 1] = { left or "?", right or "", r or 1, g or 1, b or 1 }
            rows = rows + 1
        end,
        Finish = function()
            -- Stable: `seq` is the order the groups were first seen, so two
            -- groups with the same sort key keep the walk's own order rather
            -- than an arbitrary one.
            table.sort(order, function(a, b)
                if a.sort ~= b.sort then return a.sort < b.sort end
                return a.seq < b.seq
            end)
            local shown, hidden = 0, 0
            local anyHeaded = false
            for _, grp in ipairs(order) do
                local headed = false
                for _, row in ipairs(grp.rows) do
                    if shown < ROSTER_CAP then
                        if grp.label and not headed then
                            -- A blank line BETWEEN sections, never above the
                            -- first one: a gap at the top of the list would
                            -- read as a rendering fault rather than as spacing.
                            -- Written only when a heading is actually about to
                            -- be drawn, so a group that exists but is entirely
                            -- past the cap cannot leave a gap behind nothing.
                            if anyHeaded then tt:AddLine(" ") end
                            tt:AddLine(grp.label, 0.6, 0.6, 0.6)
                            headed, anyHeaded = true, true
                        end
                        tt:AddDoubleLine(row[1], row[2], row[3], row[4], row[5], 0.7, 0.7, 0.7)
                        shown = shown + 1
                    else
                        hidden = hidden + 1
                    end
                end
            end
            if hidden > 0 then tt:AddLine(format("... and %d more", hidden), 0.5, 0.5, 0.5) end
            return rows
        end,
    }
end

-- Blizzard's own gold, `NORMAL_FONT_COLOR` (1, 0.82, 0), for the level number.
--
-- Deliberately a FIXED gold and not `GetQuestDifficultyColor`, which is what
-- greys out a level the client considers trivial. That difficulty test is
-- relative to THIS client's own max level, so it mislabels a friend who is at
-- the cap of a DIFFERENT WoW version -- a Season of Discovery or Anniversary
-- character at their own max shows as trivial grey. One colour is right in every
-- version; a clever one is right only in ours.
local LEVEL_HEX = "ffd100"

-- Renders as "|cffffd10090|r  <name> <AFK>". Level first so the names line up in
-- a column, and the two halves carry their OWN colour escapes because
-- AddDoubleLine takes a single colour for the whole left string.
local function RosterLabel(name, level, tag, r, g, b)
    name = Plain(name)
    if type(name) ~= "string" or name == "" then name = "?" end
    -- A cross-realm name arrives as "Name-Realm"; the realm is already on the
    -- right-hand column or irrelevant, and the full form pushes the columns apart.
    name = name:match("[^%-]+") or name
    if r and g and b then name = format("|cff%s%s|r", Hex(r, g, b), name) end

    level = Plain(level)
    local prefix = ""
    if type(level) == "number" and level > 0 then
        prefix = format("|cff%s%d|r  ", LEVEL_HEX, level)
    end
    return prefix .. name .. (tag or "")
end

-- The away/busy suffix. Battle.net reports it on the ACCOUNT (isAFK/isDND) and
-- again per game account (isGameAFK/isGameBusy); the character friend list
-- reports it on the friend. Either source counts, because a friend flagged away
-- in the app and a friend flagged away in game are the same fact to a reader.
-- Yellow for away, red for busy, rather than one grey for both. They mean
-- different things -- "back shortly" against "do not contact me" -- and a
-- reader scanning a roster should not have to read the word to tell which.
local function StatusTag(afk, dnd)
    if afk then return "  |cffffe000<AFK>|r" end
    if dnd then return "  |cffff2020<DND>|r" end
    return ""
end

-- Group headings for the friends list, so the versions do not interleave.
--
-- WoW projects come from `wowProjectID`, whose constants Blizzard defines in its
-- own Constants.lua (MAINLINE 1, CLASSIC 2, WOWLABS 3, BURNING_CRUSADE 5, WRATH
-- 11, CATACLYSM 14, MISTS 19). Season of Discovery and the Anniversary realms
-- have NO id of their own -- they run on Classic Era and report
-- `WOW_PROJECT_CLASSIC` like any other Classic Era realm, so they group together
-- under one heading. Splitting them further would mean pattern matching a
-- rich-presence string, which is guesswork.
local WOW_PROJECT_NAMES = {
    [1]  = "WoW",
    [2]  = "WoW Classic",
    [3]  = "WoW Plunderstorm",
    [5]  = "Burning Crusade Classic",
    [11] = "Wrath Classic",
    [14] = "Cataclysm Classic",
    [19] = "Mists Classic",
}

-- Non-WoW clients, by the program code Battle.net reports. The codes are
-- Blizzard's own and are not localised; the names here are the only part a
-- reader sees. An unlisted code falls back to the code itself, which is ugly but
-- honest and names the gap.
local CLIENT_NAMES = {
    APP  = "Battle.net App",  BSAp = "Battle.net App",
    WTCG = "Hearthstone",     Hero = "Heroes of the Storm",
    D3   = "Diablo III",      ANBS = "Diablo Immortal",
    OSI  = "Diablo II",       S2   = "StarCraft II",
    S1   = "StarCraft",       W3   = "WarCraft III",
    Pro  = "Overwatch",       RTRO = "Blizzard Arcade Collection",
}

-- One Battle.net game account, rendered. `acc` supplies the fallback label for
-- a friend whose character name has not arrived yet.
local function BNetRow(roster, acc, ga)
    local name = Plain(ga.characterName)
    if type(name) ~= "string" or name == "" then
        name = Plain(acc.accountName) or Plain(acc.battleTag)
    end
    -- Only a WoW account has a class to colour. A friend sitting in another
    -- Blizzard game keeps the plain white row and gets their rich presence on
    -- the right instead of an area they do not have.
    --
    -- richPresence, NOT clientProgram. `clientProgram` is a program identifier
    -- such as "Hero" or "CLNT", fit for keying an icon and not for showing a
    -- person. Blizzard's own friends list renders rich presence in that slot,
    -- which is already localised and already says what they are doing.
    local isWoW = Plain(ga.clientProgram) == "WoW"
    local r, g, b
    local right
    if isWoW then
        r, g, b = ClassColorFromID(ga.classID)
        -- The Battle.net account, not the zone. A character name you do not
        -- recognise is the problem this column solves; the zone answers a
        -- question nobody asked of a friends list.
        right = Plain(acc.accountName) or Plain(acc.battleTag)
    else
        right = Plain(ga.richPresence) or Plain(ga.clientProgram)
    end

    -- Away and busy are reported on the account AND on the game account, and
    -- either one is the same fact to a reader.
    local tag = StatusTag(Plain(acc.isAFK) or Plain(ga.isGameAFK),
                          Plain(acc.isDND) or Plain(ga.isGameBusy))

    -- The group this row belongs under. WoW rows group by version; everything
    -- else groups by game. `order` sorts the headings: this client's own
    -- version first, other WoW versions next by id, other games last.
    local key, label, order
    if isWoW then
        local pid = Plain(ga.wowProjectID)
        if type(pid) ~= "number" then pid = 0 end
        key = "wow" .. pid
        label = WOW_PROJECT_NAMES[pid] or "WoW"
        order = (pid == (WOW_PROJECT_ID or 1)) and 0 or (100 + pid)
    else
        local code = Plain(ga.clientProgram)
        if type(code) ~= "string" or code == "" then code = "?" end
        key = "app" .. code
        label = CLIENT_NAMES[code] or code
        order = 1000
    end

    roster.Row(RosterLabel(name, ga.characterLevel, tag, r, g, b), right, 1, 1, 1,
        key, label, order)
end

local function BuildFriendsRoster(tt)
    local inGameOnly = Get("tbFriendsInGameOnly", ns.EUI_DEFAULTS.tbFriendsInGameOnly) and true or false
    local roster = NewRoster(tt)

    -- Character friends: this client's own version by definition, so they join
    -- the same group as a Battle.net friend playing here. They carry no
    -- Battle.net account to name, so their right column keeps the zone -- the
    -- most useful thing that list actually knows about them.
    local numFriends = (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends()) or 0
    local ownPid = WOW_PROJECT_ID or 1
    local ownKey, ownLabel = "wow" .. ownPid, (WOW_PROJECT_NAMES[ownPid] or "WoW")
    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfoByIndex and C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected and info.name then
            -- The localised path, because FriendInfo carries no classID.
            local r, g, b = ClassColorFromLocalizedName(info.className)
            local tag = StatusTag(Plain(info.afk), Plain(info.dnd))
            roster.Row(RosterLabel(info.name, info.level, tag, r, g, b),
                Plain(info.area), 1, 1, 1, ownKey, ownLabel, 0)
        end
    end

    -- The SAME call FriendsCount makes, over the same friend indices. The badge
    -- sums these lists' lengths and this loop draws their contents, so the two
    -- agree by construction rather than by two walks being kept in step.
    -- ROSTER_CAP truncates what is DRAWN, never what is counted, and the
    -- overflow line accounts for the difference.
    local subAccounts = Get("tbFriendsSubAccounts", ns.EUI_DEFAULTS.tbFriendsSubAccounts) and true or false
    local numBNet = (BNGetNumFriends and BNGetNumFriends()) or 0
    for i = 1, numBNet do
        local accountInfo, list = BNetFriendAccounts(i, inGameOnly, subAccounts)
        if accountInfo and list then
            for _, ga in ipairs(list) do BNetRow(roster, accountInfo, ga) end
        end
    end

    return roster.Finish()
end

-- Elements.lua's friends element hands its tooltip straight here.
function ns.TopBar.FriendsTooltip(tt)
    if not tt then return end
    if not RosterReadable() then return end
    -- The blank line under the element's title is paid HERE, past the gate: in a
    -- dungeon or raid this function adds nothing at all, and a spacer added by
    -- the caller would leave the tooltip showing its own name over an empty row.
    -- Only a pcall failure below can still do that, which is the exceptional path.
    tt:AddLine(" ")
    -- A pcall failure here costs the tooltip, never the bar. An empty roster
    -- says so rather than leaving a gap the reader has to interpret; a FAILED
    -- one says nothing, because it does not know whether the list was empty.
    local ok, shown = pcall(BuildFriendsRoster, tt)
    if ok and shown == 0 then tt:AddLine("No friends online", 0.6, 0.6, 0.6) end
end

-- GetNumGuildMembers has no generated-doc entry (it predates the C_ namespace),
-- but it is not on the deprecated-fallback list either, and live Mainline files
-- still call it directly and compare its return with `==` -- an ordinary
-- comparison a Secret value could not survive, so its return is provably not
-- Secret even without a machine-readable doc entry. The second return being the
-- ONLINE count is taken from working 12.0 code elsewhere, not provable from the
-- reference alone.
local function GuildCount()
    if not (IsInGuild and IsInGuild()) then return 0 end
    if not GetNumGuildMembers then return 0 end
    local _, online = GetNumGuildMembers()
    return online or 0
end

-- The roster LIST has no legacy equivalent left to read: GetGuildRosterInfo does
-- not exist anywhere in the 12.0 reference and is not on the deprecation list
-- either, so it was removed outright rather than routed through a fallback. The
-- only path left is C_Club, which is what Blizzard's own guild roster now uses:
-- C_Club.GetGuildClubId(), then CommunitiesUtil's wrappers (always loaded, no
-- LoadOnDemand). GetMemberInfo and GetClubMembers are both marked
-- SecretInChatMessagingLockdown -- a combat-adjacent restriction distinct from
-- ordinary Secret Values but handled the same way here: never called unless
-- RosterReadable() already said yes.
local guildLastRequest = 0
local function RequestGuildRoster()
    local now = GetTime()
    if now - guildLastRequest < 15 then return end
    guildLastRequest = now
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    if C_Club and C_Club.GetGuildClubId and C_Club.FocusMembers then
        local clubId = C_Club.GetGuildClubId()
        if clubId then C_Club.FocusMembers(clubId) end
    end
end

local function BuildGuildRoster(tt)
    if not (C_Club and C_Club.GetGuildClubId and C_Club.AreMembersReady) then return end
    if not (CommunitiesUtil and CommunitiesUtil.GetMemberIdsSortedByName
       and CommunitiesUtil.GetMemberInfo and CommunitiesUtil.GetOnlineMembers) then return end

    local clubId = C_Club.GetGuildClubId()
    if not clubId then return end
    if not C_Club.AreMembersReady(clubId) then return end

    local memberIds = CommunitiesUtil.GetMemberIdsSortedByName(clubId)
    if type(memberIds) ~= "table" then return end
    local infos = CommunitiesUtil.GetMemberInfo(clubId, memberIds)
    local online = CommunitiesUtil.GetOnlineMembers(infos)
    if type(online) ~= "table" then return end

    -- The guild header: name, then YOUR rank in it, then the message of the day.
    -- GetGuildInfo is an old global with no generated-doc entry, so both of its
    -- returns go through Plain() like every other roster read rather than being
    -- trusted on the strength of its age. Its second return is the rank name.
    local gname, grank
    if GetGuildInfo then
        local n, r = GetGuildInfo("player")
        gname, grank = Plain(n), Plain(r)
    end
    if type(gname) == "string" and gname ~= "" then tt:AddLine(gname, 0.1, 1, 0.1) end
    if type(grank) == "string" and grank ~= "" then tt:AddLine(grank, 1, 0.82, 0) end

    -- GetGuildRosterMOTD is deprecated to C_GuildInfo.GetMOTD, so call the new
    -- name and fall back rather than the other way round. Wrapped because a long
    -- message would otherwise force the whole tooltip to that width, and a guild
    -- message of the day is routinely a paragraph.
    local motd
    if C_GuildInfo and C_GuildInfo.GetMOTD then motd = Plain(C_GuildInfo.GetMOTD())
    elseif GetGuildRosterMOTD then motd = Plain(GetGuildRosterMOTD()) end
    if type(motd) == "string" and motd ~= "" then
        tt:AddLine(" ")
        tt:AddLine(motd, 0.6, 0.8, 1, true)
    end
    tt:AddLine(" ")

    local roster = NewRoster(tt)
    for _, info in ipairs(online) do
        -- Plain() BEFORE the truth-test, not after: `name` is the one field on
        -- this path that can genuinely be Secret, and this is the only place a
        -- raw one would be tested. Doing it here means the whole loop body
        -- works from a value already known to be an ordinary string or nil.
        local name = info and Plain(info.name)
        if type(name) == "string" and name ~= "" then
            local r, g, b = ClassColorFromID(info.classID)
            -- ClubMemberPresence: 4 Away, 5 Busy. Through StatusTag, the SAME
            -- source the friends list uses, so the two rosters cannot drift on
            -- what away and busy look like.
            local presence = Plain(info.presence)
            local tag = StatusTag(presence == 4, presence == 5)
            -- Colour goes INTO the label so the level keeps its gold while the
            -- name takes the class colour; the row itself draws plain.
            roster.Row(RosterLabel(name, info.level, tag, r, g, b), Plain(info.zone), 1, 1, 1)
        end
    end
    return roster.Finish()
end

-- Elements.lua's guild element hands its tooltip straight here. The throttled
-- request runs every hover regardless of RosterReadable(): it only ever
-- refreshes local Club state, never writes anything onto a secure button, so
-- it costs nothing to keep warm even when the list itself will not render.
function ns.TopBar.GuildTooltip(tt)
    if not tt then return end
    RequestGuildRoster()
    if not RosterReadable() then return end
    -- Past the gate, so the same reasoning as the friends tooltip above.
    tt:AddLine(" ")
    -- Same split as the friends tooltip: an empty roster says so, a failed or
    -- not-yet-ready one stays quiet. BuildGuildRoster also returns nothing on
    -- its several early exits, which is why the test is `shown == 0` and not
    -- `not shown`.
    local ok, shown = pcall(BuildGuildRoster, tt)
    if ok and shown == 0 then tt:AddLine("No guild members online", 0.6, 0.6, 0.6) end
end

-- Great Vault: C_WeeklyRewards.GetActivities() returns nothing useful before a
-- fresh character's first weekly reset, so every field is nil-checked before
-- use. Neither WeeklyRewardActivityInfo nor its fields are marked Secret, which
-- is what lets the values below be read and formatted directly.
--
-- There is deliberately no R/D/W badge under the icon: the tooltip already says
-- everything it would, in words, with the actual progress numbers. If one is
-- ever wanted back, the "done" test is progress >= threshold, matching
-- Blizzard's own WeeklyRewardsMixin.
--
-- Elements.lua's vault element hands its tooltip straight here.
function ns.TopBar.VaultTooltip(tt)
    if not tt then return end
    -- Unconditional, unlike the two rosters above: every path from here adds at
    -- least one line, including the no-progress one.
    tt:AddLine(" ")
    local activities = C_WeeklyRewards and C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities()
    if type(activities) ~= "table" or #activities == 0 then
        tt:AddLine("No progress yet this week.", 0.7, 0.7, 0.7)
        return
    end
    for _, info in ipairs(activities) do
        if type(info) == "table" and info.type and info.progress and info.threshold then
            local label
            if info.type == Enum.WeeklyRewardChestThresholdType.Raid then label = "Raid"
            elseif info.type == Enum.WeeklyRewardChestThresholdType.Activities then label = "Dungeon"
            elseif info.type == Enum.WeeklyRewardChestThresholdType.World then label = "World" end
            if label then
                tt:AddDoubleLine(label, format("%d/%d", info.progress, info.threshold), 0.7, 0.7, 0.7, 1, 1, 1)
            end
        end
    end
end

---------------------------------------------------------------------------------
-- The clock's tooltip body: this character's raid and dungeon lockouts, then the
-- reset clocks. Elements.lua's clock element hands its tooltip straight here.
--
-- THE COST, because this hangs off a hover. GetNumSavedInstances and
-- GetSavedInstanceInfo read the client's own cached lockout table -- no server
-- round trip -- over a dozen entries at the outside, and the reset calls are the
-- same local reads the clock face already makes on its ticker. Formatting
-- happens only while the tooltip is open, and nothing here runs on a timer.
--
-- The ONE call that reaches the server is RequestRaidInfo, throttled like the
-- guild roster's request above rather than fired per hover. Its answer arrives
-- later, on UPDATE_INSTANCE_INFO, and updates the same cache the walk reads, so
-- the NEXT hover shows it. There is deliberately no event registration and no
-- refresh ticker: the list only moves when a lockout is earned or a reset lands.
--
-- The one exception is the FIRST hover that reaches the icon map: it also walks
-- the Encounter Journal once (InstanceIcons below), roughly three hundred reads,
-- and caches the result for the session. A one-time cost, but not nothing.
--
-- Neither GetNumSavedInstances nor GetSavedInstanceInfo has a generated-doc
-- entry (both predate the C_ namespace, like GetNumGuildMembers above), so the
-- evidence they are not Secret is Blizzard's own live use of them:
-- Blizzard_RaidFrame/Mainline/RaidFrame.lua:142-143 branches on
-- `extended or locked` and passes `reset` straight to SecondsToTime. A Secret
-- boolean cannot be tested in a condition and a Secret number cannot be
-- formatted, so neither line could exist if those returns were marked.
--
-- That proves positions 3, 5 and 6, and nothing else. Position 1 and positions
-- 8 through 12 are branched on, keyed or formatted HERE, while Blizzard either
-- never touches them or only hands them to a display call -- which proves
-- nothing, because a FontString accepts Secret text by design. Showing a value
-- is allowed, inspecting it is not. Their status is therefore unproven, and that
-- is what the pcall at the call site in ClockTooltip contains.
---------------------------------------------------------------------------------

-- 30s, not the roster's 15: a lockout changes when a boss dies or a reset
-- lands, never minute to minute.
local raidInfoLastRequest = 0
local function RequestLockouts()
    local now = GetTime()
    if now - raidInfoLastRequest < 30 then return end
    raidInfoLastRequest = now
    if RequestRaidInfo then RequestRaidInfo() end
end

-- Bounds the tooltip's height on an alt with a long history. Counting continues
-- past the cap so the overflow line can say how many were left out, the same
-- rule ROSTER_CAP follows above.
local LOCKOUT_CAP = 12

-- The instance art the Encounter Journal already ships, so no icon list has to
-- be hand-maintained here and next tier's raids arrive with their own pictures.
--
-- The numbers are the journal's own: it draws this texture at 174x96 out of a
-- 256x128 file (EncounterInstanceButtonTemplate). That is a wide banner, so a
-- straight squeeze into a square would distort it; this takes the middle 96x96
-- of the used area instead, which is where the art is.
local INSTANCE_ICON = "|T%s:16:16:0:0:256:128:39:135:0:96|t"

-- Built once per session, on the first hover that needs it, and only from the
-- journal's own tier walk -- there is no map from a lockout to an Encounter
-- Journal instance id, so the join is by NAME. An instance whose name does not
-- match simply gets no picture; the row still says everything it said before.
--
-- EJ_SelectTier is the reason for the EncounterJournal guard: walking the tiers
-- moves the journal's own selection, and restoring it afterwards would not
-- redraw a journal the player is looking at. Skipped rather than worked around,
-- because the next hover can do it just as well.
local instanceIcons

local function InstanceIcons()
    if instanceIcons then return instanceIcons end
    if not (EJ_GetNumTiers and EJ_GetCurrentTier and EJ_SelectTier and EJ_GetInstanceByIndex) then
        instanceIcons = {}
        return instanceIcons
    end
    if EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown() then
        return nil
    end

    local icons = {}
    local restore = EJ_GetCurrentTier()
    for tier = 1, (EJ_GetNumTiers() or 0) do
        EJ_SelectTier(tier)
        for _, isRaid in ipairs({ true, false }) do
            local index = 1
            while true do
                local _, name, _, _, buttonImage = EJ_GetInstanceByIndex(index, isRaid)
                if not name then break end
                -- First tier wins on a duplicate name: the earliest listing is
                -- the original instance rather than a later revisit of it.
                if buttonImage and not icons[name] then icons[name] = buttonImage end
                index = index + 1
            end
        end
    end
    if restore then EJ_SelectTier(restore) end

    instanceIcons = icons
    return instanceIcons
end

-- SecondsToTime's fourth argument is the maximum number of units, so 2 gives
-- "2 Days 7 Hr" rather than Blizzard's own three-unit "2 Days 7 Hr 4 Min". The
-- rows are read at a glance and the minutes on a multi-day lockout are noise.
local function ResetText(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end
    if not SecondsToTime then return nil end
    return SecondsToTime(seconds, true, nil, 2)
end

-- Collected before anything is drawn, not written as the walk goes: the
-- "Saved Raid(s)" heading has to be printed ABOVE rows whose existence is only known
-- once the walk is finished, and a heading over an empty list is exactly the
-- kind of line the friends roster is careful never to leave behind.
--
-- Returns the number held, drawn or not, so the caller knows whether the block
-- was written at all.
local function AddLockouts(tt)
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return 0 end
    local total = GetNumSavedInstances()
    if type(total) ~= "number" or total <= 0 then return 0 end

    local icons = InstanceIcons()
    local rows, held = {}, 0
    for i = 1, total do
        local name, _, reset, _, locked, extended, _, isRaid, maxPlayers, difficultyName,
              numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        -- `extended` without `locked` is a lockout the player asked to keep, so
        -- both count as held. A row that is neither has already expired and is
        -- only still in the table because the client has not pruned it yet.
        if name and (locked or extended) then
            held = held + 1
            if #rows < LOCKOUT_CAP then
                -- Size and difficulty read as one phrase ("20 Heroic"), and the
                -- boss count is appended only when the instance actually reports
                -- encounters: a world boss or a scenario reports none, and
                -- "0/0" would be worse than saying nothing.
                local detail = difficultyName or (isRaid and "Raid" or "Dungeon")
                if type(maxPlayers) == "number" and maxPlayers > 0 then
                    detail = format("%d %s", maxPlayers, detail)
                end
                if type(numEncounters) == "number" and numEncounters > 0
                   and type(encounterProgress) == "number" then
                    detail = format("%s %d/%d", detail, encounterProgress, numEncounters)
                end
                local icon = icons and icons[name]
                rows[#rows + 1] = {
                    format("%s%s |cff9d9d9d(%s)|r",
                        icon and (format(INSTANCE_ICON, icon) .. " ") or "", name, detail),
                    ResetText(reset) or "",
                }
            end
        end
    end
    if held == 0 then return 0 end

    -- The bar's own accent, so the heading follows a custom accent colour or the
    -- host's rather than being pinned to Blizzard gold.
    tt:AddLine("Saved Raid(s)", AccentRGB())
    for _, row in ipairs(rows) do
        tt:AddDoubleLine(row[1], row[2], 1, 1, 1, 0.7, 0.7, 0.7)
    end
    if held > #rows then
        tt:AddLine(format("and %d more", held - #rows), 0.6, 0.6, 0.6)
    end
    return held
end

function ns.TopBar.ClockTooltip(tt)
    if not tt then return end
    RequestLockouts()

    -- pcall'd for the reason the friends roster above is: several of the
    -- GetSavedInstanceInfo fields this walk branches on and formats are ones no
    -- Blizzard caller uses, so their secret status is unproven, and a Secret
    -- value used in a condition throws rather than answering. A failure costs
    -- the lockout block and leaves the reset clocks below intact. Nothing is
    -- half-drawn either way: AddLockouts collects its rows first and draws only
    -- once the walk has finished.
    local ok, held = pcall(AddLockouts, tt)
    if ok and held and held > 0 then tt:AddLine(" ") end

    local daily = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset
        and ResetText(C_DateAndTime.GetSecondsUntilDailyReset())
    local weekly = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
        and ResetText(C_DateAndTime.GetSecondsUntilWeeklyReset())
    -- White label, grey value: the labels are the fixed part a reader scans down,
    -- so they carry the emphasis and the times sit back.
    if daily then
        tt:AddDoubleLine("Daily reset", daily, 1, 1, 1, 0.7, 0.7, 0.7)
    end
    if weekly then
        tt:AddDoubleLine("Weekly reset", weekly, 1, 1, 1, 0.7, 0.7, 0.7)
    end

    -- The OTHER clock, always: the face is already showing one of the two, and
    -- repeating it would spend a line saying what the player can read on the bar.
    -- So a face set to realm time gets local time here, and the reverse.
    if Get("tbServerTime", ns.EUI_DEFAULTS.tbServerTime) then
        tt:AddDoubleLine("Local time", FormatHM(tonumber(date("%H")), tonumber(date("%M"))),
            1, 1, 1, 0.7, 0.7, 0.7)
    else
        tt:AddDoubleLine("Realm time", FormatHM(GetGameTime()), 1, 1, 1, 0.7, 0.7, 0.7)
    end
end

-- Badge FontStrings. Fixed size, like CLOCK_PAD above: not exposed as a setting.
local BADGE_SIZE = 10

local friendsText, guildText

local function UpdateFriendsBadge()
    if not friendsText then return end
    friendsText:SetText(tostring(FriendsCount()))
end

-- pcall'd: whether GetNumGuildMembers can return a Secret value in combat is
-- unproven in either direction (the two Mainline call sites that prove its
-- return survives an ordinary `==` comparison are both in frames that close
-- on entering combat, so neither says anything about the combat case). A
-- failure here should cost this one refresh, not throw on a ticker during
-- the raid pull the badge is supposed to survive.
local function UpdateGuildBadge()
    if not guildText then return end
    local ok, count = pcall(GuildCount)
    if ok then guildText:SetText(tostring(count)) end
end

-- The friends walk is EXPENSIVE IN GARBAGE, not in time: every
-- GetFriendAccountInfo call returns a freshly allocated struct that
-- FriendsCount reads a field or two of and drops. BN_FRIEND_INFO_CHANGED fires
-- whenever any friend anywhere changes zone, game or status, so walking per
-- event churned tens of megabytes a minute on a large friends list.
--
-- Every recurring trigger therefore funnels through this request, which
-- coalesces a burst into one trailing walk per window. (The one direct call
-- left is the badge's first fill in ApplyReadoutFonts, which cannot wait.)
-- Trailing, not leading: a leading edge would pay one walk per burst plus
-- the deferred one. Worst-case staleness is one window after an event, two
-- on the tick-only path -- invisible on a badge; the churn was not.
--
-- GuildCount stays direct: GetNumGuildMembers returns two numbers, no structs,
-- so there is nothing to throttle.
local BADGE_WALK_WINDOW = 10
local friendsBadgePending

local function RequestFriendsBadgeUpdate()
    if friendsBadgePending then return end
    friendsBadgePending = true
    C_Timer.After(BADGE_WALK_WINDOW, function()
        friendsBadgePending = nil
        UpdateFriendsBadge()
    end)
end

-- Refresh triggers: the events that actually change these counts, plus a
-- belt-and-braces re-render every tenth Tick() below. No WEEKLY_REWARDS_UPDATE
-- here: the vault tooltip reads GetActivities() at the moment it opens, so it
-- needs no event to stay current.
local badgeWatcher = CreateFrame("Frame")
badgeWatcher:RegisterEvent("FRIENDLIST_UPDATE")
badgeWatcher:RegisterEvent("BN_FRIEND_INFO_CHANGED")
badgeWatcher:RegisterEvent("GUILD_ROSTER_UPDATE")
badgeWatcher:SetScript("OnEvent", function(_, event)
    if event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_INFO_CHANGED" then
        RequestFriendsBadgeUpdate()
    elseif event == "GUILD_ROSTER_UPDATE" then
        UpdateGuildBadge()
    end
end)

---------------------------------------------------------------------------------
-- Fonts: Bar.lua's ApplyFonts() calls this on every Apply() once the bar exists
-- and the feature is enabled. It lazily attaches clockText the first time it
-- runs, then (re)sizes both readouts from tbClockSize/tbSysSize and refreshes
-- their text, so the size sliders and the 24h/server-time toggles take effect
-- live.
--
-- friendsText/guildText follow the same lazy pattern. Guild's button is secure,
-- but the lazy creation below only ever fires the FIRST time it sees a non-nil
-- button -- always inside the same Apply() call that built it, already past that
-- call's own InCombatLockdown() gate. After that they are never nil again, so
-- the branch never re-executes where combat could matter.
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

    local friendsBtn = _G.KitnUITopBar_friends
    local friendsFirstBuild
    if friendsBtn and not friendsText then
        friendsText = friendsBtn:CreateFontString(nil, "OVERLAY")
        friendsText:SetPoint("BOTTOM", friendsBtn, "BOTTOM", 0, -2)
        friendsFirstBuild = true
    end
    if friendsText then
        friendsText:SetFont(STANDARD_TEXT_FONT, BADGE_SIZE, "OUTLINE")
        -- The first fill is direct: a badge blank for a whole window after it
        -- appears reads as broken. It runs here rather than in the creation
        -- branch because SetText before SetFont throws (sysText's "font
        -- before text" comment above). Every later Apply() takes the request
        -- path -- sliders re-run Apply() per notch, and each notch used to
        -- pay a full walk. Cost: flipping either tbFriends* filter takes up
        -- to a window to move the count.
        if friendsFirstBuild then
            UpdateFriendsBadge()
        else
            RequestFriendsBadgeUpdate()
        end
    end

    local guildBtn = _G.KitnUITopBar_guild
    if guildBtn and not guildText then
        guildText = guildBtn:CreateFontString(nil, "OVERLAY")
        guildText:SetPoint("BOTTOM", guildBtn, "BOTTOM", 0, -2)
    end
    if guildText then
        guildText:SetFont(STANDARD_TEXT_FONT, BADGE_SIZE, "OUTLINE")
        UpdateGuildBadge()
    end

    -- No vault block here. The Great Vault icon carries no badge; its tooltip
    -- is the whole readout.

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
local tickCount = 0

local function Tick()
    -- The FPS readout updates BEFORE the "is the bar shown" early-out, so the
    -- numbers keep moving while the bar is hidden.
    UpdateSys()
    ns.TopBar.RetryFit()
    local barFrame = ns.TopBar.Frame()
    if not (barFrame and barFrame:IsShown()) then return end
    UpdateClock()

    -- Belt-and-braces re-render every tenth tick; the events above are the
    -- real triggers. Friends goes through the throttled request so it
    -- coalesces with the event walks; guild is direct because it allocates
    -- nothing.
    tickCount = tickCount + 1
    if tickCount >= 10 then
        tickCount = 0
        RequestFriendsBadgeUpdate()
        UpdateGuildBadge()
    end
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
    -- sysText eagerly at load, so it is never nil in practice. Kept because the
    -- cost is a nil check and the alternative is a ticker calling into a frame
    -- that a future refactor made lazy again. Do not read them as evidence that
    -- sysText can currently be nil.
    if ns.TopBar.Enabled() and sysText and not ticker then
        ticker = C_Timer.NewTicker(1, Tick)
    end

    -- The readout's visibility and both EllesmereUI suppressions all resolve
    -- from this one call, off what is actually on screen. It runs on every
    -- Apply(), including the profile- and spec-switch reapply Bar.lua already
    -- wires up.
    --
    -- Deliberately in Apply's FIRST half, which still executes during combat,
    -- and safe there because nothing it reaches is protected. That is what makes
    -- switching the FPS element off mid-fight take effect at once instead of
    -- waiting for the deferred Apply.
    ns.TopBar.RefreshEUIMinimap()
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
            -- calls every registered element's getFrame unconditionally on login
            -- and every zone change, before its own combat gate and without
            -- consulting isHidden. sysFrame already exists unconditionally above
            -- (it carries no secure template, so eager creation costs nothing);
            -- this just hands it back.
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
