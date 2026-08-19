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
-- Readout colours.
--
-- The FPS and latency NUMBERS are plain white, on the bar and in the tooltip.
-- They used to carry a green / amber / red threshold band. Green sat next to
-- the pink accent nearly all the time, so it read as decoration rather than as
-- information, and the tooltip's addon-memory column matched it. Removed
-- rather than re-tuned: a colour that is almost always the same colour is not
-- telling you anything.
--
-- The grey "--" for a value that could not be read STAYS. That is not a
-- quality rating, it is the absence of a reading, and it has to look different
-- from a real number.
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
            -- Two things are going on in this one line, and only one of them is
            -- the colour argument.
            --
            -- The NAME comes from another addon's own TOC title, so it can carry
            -- an escape code this addon did not write, and nothing guarantees it
            -- is closed. An unterminated |cff bleeds forward into the value next
            -- to it and into every row drawn after it, which is why the whole
            -- memory column could come out one colour regardless of what was
            -- passed here. A trailing |r closes any open code and does nothing
            -- when there is none.
            --
            -- The VALUE is then given white explicitly, both as colour arguments
            -- and inline, so it cannot inherit from anything upstream.
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
-- Suppress EllesmereUI's MINIMAP clock and FPS/MS while this bar is showing its
-- own, and hand them straight back when it is not -- including when the bar is
-- hidden by a visibility rule inside a key or a raid, which is the case the
-- plain enabled/off test above cannot see.
--
-- Same trade as SuppressEUIFps: hide the FRAME, never write EllesmereUI's own
-- `clockMode` or `showFPS`. Those live in the minimap module's database, which
-- rides EllesmereUI's profile export and its Spec Overrides engine, so writing
-- them on every instance entry and exit would churn a database this addon does
-- not own.
--
-- Reachable at all only because the minimap module publishes both frames as
-- globals immediately before showing them. Both are file-local otherwise.
--
-- A GLOBAL THAT IS NIL IS NOT THE SAME AS A SETTING THAT IS OFF. Those two
-- assignments happen only on the host's ENABLED branch, but nothing ever clears
-- them: its disabled branch merely hides a frame the global still points at. So
-- the global is nil only for a frame that was never enabled in this session, and
-- a frame the host has since switched off still answers here. Taking that frame
-- and then handing it back would put a clock on the minimap the user had turned
-- off. Shown-state at take time is what settles it, below.
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

-- Derived from what is ACTUALLY on screen rather than from the visibility
-- rules, so it stays correct however those rules change. Two frames decide it
-- because the two readouts are separate frames: the clock is part of the bar,
-- and the FPS readout is parented to UIParent and follows the bar (below).
--
-- HOW MANY FPS COUNTERS THE PLAYER ENDS UP WITH IS ELLESMEREUI'S ANSWER, NOT
-- OURS. It ships TWO independent ones, a minimap readout and a standalone
-- counter, each with its own switch. When ours is up we take both; when ours
-- goes we give back exactly what we took and no more, so both host switches on
-- returns two and both off returns none. Picking one for the player would mean
-- overruling a configuration this addon does not own.
--
-- A frame that does not exist yet cannot be hooked, and that is the hole the
-- bridge hook below closes. `SuppressMinimapFrame` returns early on a nil
-- global, so a readout the user enables for the FIRST TIME while we are already
-- suppressing gets created, published and shown by the host with nothing on our
-- side watching it, and it then sits on the minimap beside ours. EllesmereUI
-- publishes its minimap apply as a bridge for exactly this kind of thing, so
-- re-running the pass after it catches the new frame on its first apply.
--
-- Hooked LAZILY rather than at file load: the bridge is assigned during the
-- minimap module's own init, and this file cannot assume that has happened yet.
-- The flag makes every later pass a single table read.
--
-- THE BRIDGE ALONE IS NOT ENOUGH. hooksecurefunc wraps a GLOBAL, so it only ever
-- sees calls made THROUGH that global; the host's own internal calls to the same
-- function go straight past it. That is reachable today: in combat the host's
-- apply refuses outright and merely queues, so our hook fires with nothing built
-- yet; when the fight ends the host calls its LOCAL apply upvalue rather than
-- the published bridge. The readout the user enabled mid-fight is created there,
-- our hook never fires again, and nothing else reconciles -- so it would sit
-- beside ours for good. The regen retry below is what closes that.
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

-- WoW friends are always playing WoW by definition -- only a Battle.net friend's
-- CURRENT game needs checking against tbFriendsInGameOnly. Neither FriendInfo
-- nor BNetGameAccountInfo marks any field Secret.
--
-- One Battle.net friend can be logged into several WoW game accounts at once,
-- and `accountInfo.gameAccountInfo` describes only the FIRST.
-- tbFriendsSubAccounts decides which of the two things the badge counts: the
-- friend, or each of that friend's active WoW accounts. Neither
-- GetFriendNumGameAccounts nor GetFriendGameAccountInfo declares SecretReturns;
-- both mark only SecretArguments, which constrains what may be passed IN and
-- says nothing about the returns.
--
-- Returns `accountInfo` and the LIST of game accounts this friend contributes,
-- in render order. The badge sums the list lengths and the roster renders the
-- lists, so the two cannot drift: they are not two walks kept in step, they are
-- one walk with two consumers.
--
-- tbFriendsSubAccounts expands a friend into their WoW accounts, and ONLY their
-- WoW accounts -- that is what the switch says. Counting a friend's Heroes
-- session as a second "sub account" would be a different promise.
--
-- A friend with NO WoW account online is not erased by that filter: the switch
-- has nothing to expand for them, so they fall through to the single row the
-- off state would have given, which tbFriendsInGameOnly may then drop on its
-- own terms. Without that fall-through, turning the switch on would silently
-- hide every friend playing something else.
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
-- Class colour for the two rosters, and the guard that makes reading these
-- fields safe.
--
-- ClubMemberInfo marks only `isSelf` and `faction` NeverSecret. Every OTHER
-- field of that structure may therefore arrive as a Secret value. A Secret
-- cannot be used as a table key and cannot be concatenated -- both throw -- so
-- nothing reaches a LOOKUP, a CONCATENATION or a FORMAT without passing Plain()
-- first.
--
-- Plain() guards the UNSAFE OPERATIONS above, not every read. Plain truth-tests
-- (`if info.name then`) and equality tests against a literal (`clientProgram ==
-- "WoW"`) are left raw, deliberately: on the BNet and FriendList paths the
-- fields involved declare no Secret marking at all. The guild path is stricter
-- still: `name` is the one field there that can genuinely be Secret, and it goes
-- through Plain() BEFORE it is tested, so no raw truth-test on the guild path
-- can ever see one. What a Secret does under a bare truth-test is NOT decidable
-- from the static reference, which is why nothing here depends on it.
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
-- FriendInfo carries `className` and nothing else about class, and that string
-- is LOCALISED. Reversing the client's own localised tables is correct in every
-- language the client ships, because both sides come from the same client. It
-- can fail only where a locale gives two DIFFERENT classes the same word, and
-- the map below is built so that such a word resolves to no colour at all rather
-- than to whichever class was absorbed last. A plain white name is a fallback a
-- reader can ignore; a confidently wrong class colour is one they would act on.
--
-- The two source tables are keyed by classFile and both contain every class,
-- so the SAME classFile appearing in both is the ordinary case and must not
-- count as a collision. Only a second, DIFFERENT classFile claiming a word
-- already taken poisons it.
--
-- Built once on first use rather than at load: RAID_CLASS_COLORS and the
-- LOCALIZED_CLASS_NAMES tables all exist by then, and a roster hover is the
-- earliest anything here needs them.
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

-- Both rosters render as two-column rows and both overflow the same way, so the
-- row writer and the overflow line live here once. Counting CONTINUES past the
-- cap rather than breaking, which is what lets the trailing line say how many
-- were left out instead of the list simply stopping.
--
-- Rows are COLLECTED and only drawn by Finish, because grouping cannot be done
-- while writing: a heading has to be printed before rows that are not known to
-- exist until the whole walk is done. Guild rows pass no group and land in one
-- unnamed group, which draws exactly as an ungrouped list.
--
-- The cap counts ROWS and never headings. A heading is not a friend, and
-- letting it consume a slot would make the badge and the list disagree by the
-- number of games your friends happen to be playing.
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

-- "|cffffd10090|r  Kitnpriest <AFK>". Level first so the names line up in a
-- column, and the two halves carry their OWN colour escapes because
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
-- FriendsCount reads a field or two of and drops. Measured in-game on
-- 2026-08-19: one walk allocated 649 KB across 175 Battle.net friends, and
-- BN_FRIEND_INFO_CHANGED fired 69 times in one minute -- any friend changing
-- zone, game or status anywhere fires it -- so walking on every event churned
-- ~44 MB of garbage a minute and the addon's reported memory sawtoothed to
-- 90 MB between GC cycles.
--
-- Every RECURRING trigger therefore funnels through this request, which
-- coalesces however many land inside one window into a single trailing walk.
-- (The one direct call left is the badge's first fill, in ApplyReadoutFonts
-- below, which cannot wait a window.) Trailing rather than leading on
-- purpose: these events arrive in bursts, and a leading edge would pay one
-- walk per burst plus the deferred one. Staleness worst case: one window
-- after an event, TWO on the tick-only path (up to ten seconds until the
-- tenth tick issues the request, then the window). Either is invisible on a
-- badge; the churn was not.
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
-- Fonts: Bar.lua's ApplyFonts() calls this on every Apply() once the bar
-- exists and the feature is enabled. It lazily attaches clockText to the
-- clock button the first time it runs, then (re)sizes both readouts from
-- tbClockSize/tbSysSize and refreshes their text immediately, so the size
-- sliders and the 24h/server-time toggles all take effect live.
--
-- friendsText/guildText follow the identical lazy pattern. guild's
-- button is secure (Macro()'s SecureActionButtonTemplate), but the lazy
-- creation below only ever fires the FIRST time it sees a non-nil button --
-- which is always inside the same Apply() call that Bar.lua's EnsureCreated
-- just built it in, already past that call's own InCombatLockdown() gate.
-- After that first call friendsText/guildText are never nil again,
-- so the branch never re-executes where combat could matter.
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
        -- The first fill is direct and immediate: a badge that sits blank for
        -- a whole throttle window after it appears reads as broken. It runs
        -- from HERE rather than from the creation branch above because "font
        -- before text" (sysText's comment, top of this file) binds this
        -- FontString too -- SetText before the SetFont throws. Every LATER
        -- Apply() goes through the request instead: dragging any Top Bar
        -- slider re-runs Apply() per notch, and each notch used to pay a full
        -- friends walk. The cost is that flipping tbFriendsInGameOnly or
        -- tbFriendsSubAccounts takes up to a window to move the count.
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

    -- Belt-and-braces re-render every tenth tick; the events above cover the
    -- real refresh triggers. The friends half goes through the throttled
    -- request so it coalesces with the event-driven walks rather than adding
    -- walks of its own; guild stays direct because it allocates nothing (see
    -- RequestFriendsBadgeUpdate).
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
