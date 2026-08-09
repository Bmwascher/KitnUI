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
-- Friends, guild and vault badges. Counts render unconditionally; the roster
-- NAME LISTS are gated behind RosterReadable() -- Task 5's own floor, not a
-- ceiling: in combat or inside a protected instance the badge keeps counting
-- but the tooltip stops listing names.
---------------------------------------------------------------------------------

-- The name lists come from C_Club, whose member APIs are marked
-- SecretInChatMessagingLockdown (ClubDocumentation.lua). That predicate is
-- defined at SecretPredicatesDocumentation.lua:53-55 as covering encounter,
-- challenge mode and PvP restrictions AND "when the player is on a
-- communication-restricted map such as a dungeon or raid" -- with no combat
-- requirement in that last clause. EllesmereUI.InProtectedInstance() is
-- narrower than that: it wants combat as well for raid and pvp, and Challenge
-- Mode for party. So test the instance type directly and keep the host's
-- helper as an additional trigger rather than the only one.
local RESTRICTED_INSTANCE = { party = true, raid = true, pvp = true, arena = true }

local function RosterReadable()
    if InCombatLockdown() then return false end
    local inInstance, instanceType = IsInInstance()
    if inInstance and RESTRICTED_INSTANCE[instanceType] then return false end
    if EllesmereUI and EllesmereUI.InProtectedInstance
       and EllesmereUI.InProtectedInstance() then return false end
    return true
end

-- WoW friends are always playing WoW by definition -- only a Battle.net
-- friend's CURRENT game needs checking against tbFriendsInGameOnly. Neither
-- FriendInfo (.wow-api-reference/Interface/AddOns/Blizzard_APIDocumentationGenerated/
-- FriendListDocumentation.lua:602-616) nor BNetGameAccountInfo (.wow-api-reference/
-- Interface/AddOns/Blizzard_APIDocumentationGenerated/BattleNetDocumentation.lua:
-- 247-274) marks any field Secret.
local function FriendsCount()
    local wowOnline = (C_FriendList and C_FriendList.GetNumOnlineFriends
        and C_FriendList.GetNumOnlineFriends()) or 0
    local inGameOnly = Get("tbFriendsInGameOnly", ns.EUI_DEFAULTS.tbFriendsInGameOnly) and true or false
    local bnetOnline = 0
    local numBNet = (BNGetNumFriends and BNGetNumFriends()) or 0
    for i = 1, numBNet do
        local accountInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo
            and C_BattleNet.GetFriendAccountInfo(i)
        local gameInfo = accountInfo and accountInfo.gameAccountInfo
        if gameInfo and gameInfo.isOnline and (not inGameOnly or gameInfo.clientProgram == "WoW") then
            bnetOnline = bnetOnline + 1
        end
    end
    return wowOnline + bnetOnline
end

local ROSTER_CAP = 40

local function BuildFriendsRoster(tt)
    local inGameOnly = Get("tbFriendsInGameOnly", ns.EUI_DEFAULTS.tbFriendsInGameOnly) and true or false
    local rows = 0

    local numFriends = (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends()) or 0
    for i = 1, numFriends do
        if rows >= ROSTER_CAP then break end
        local info = C_FriendList.GetFriendInfoByIndex and C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected and info.name then
            rows = rows + 1
            tt:AddLine(info.name, 1, 1, 1)
        end
    end

    local numBNet = (BNGetNumFriends and BNGetNumFriends()) or 0
    for i = 1, numBNet do
        if rows >= ROSTER_CAP then break end
        local accountInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo
            and C_BattleNet.GetFriendAccountInfo(i)
        local gameInfo = accountInfo and accountInfo.gameAccountInfo
        if accountInfo and gameInfo and gameInfo.isOnline
           and (not inGameOnly or gameInfo.clientProgram == "WoW") then
            rows = rows + 1
            local label = gameInfo.characterName or accountInfo.accountName or accountInfo.battleTag
            tt:AddLine(label or "?", 1, 1, 1)
        end
    end
end

-- Elements.lua's friends element hands its tooltip straight here.
function ns.TopBar.FriendsTooltip(tt)
    if not tt then return end
    if not RosterReadable() then return end
    -- A pcall failure here costs the tooltip, never the bar.
    pcall(BuildFriendsRoster, tt)
end

-- GetNumGuildMembers has no generated-doc entry (it predates the C_
-- namespace and is never exposed through one), but it is not on the
-- deprecated-fallback list either (.wow-api-reference/Interface/AddOns/
-- Blizzard_DeprecatedHousingCatalog/../Blizzard_DeprecatedGuildScript/
-- Deprecated_GuildScript.lua), and two live Mainline files still call it
-- directly and compare its return with `==` (Blizzard_Calendar/Mainline/
-- Blizzard_Calendar.lua:4139, Blizzard_MailFrame/MailFrame.lua:59) -- an
-- ordinary comparison a Secret value could not survive, so its return is
-- provably not Secret even without a machine-readable doc entry. The second
-- return being the ONLINE count is corroborated by WindTools' own working
-- 12.0 code (References/ElvUI_WindTools-v4.19/Modules/Misc/GameBar.lua:699),
-- not independently provable from this reference alone.
local function GuildCount()
    if not (IsInGuild and IsInGuild()) then return 0 end
    if not GetNumGuildMembers then return 0 end
    local _, online = GetNumGuildMembers()
    return online or 0
end

-- The roster LIST has no legacy equivalent left to read: GetGuildRosterInfo
-- does not exist anywhere in this reference (checked across the whole live
-- tree), which the deprecation file above does not explain either -- it was
-- evidently removed outright, not routed through a fallback. The only path
-- left is C_Club, which is what Blizzard's own guild roster now uses
-- (.wow-api-reference/Interface/AddOns/Blizzard_Communities/
-- CommunitiesMemberList.lua:342-354): C_Club.GetGuildClubId(), then
-- CommunitiesUtil's own wrappers (.wow-api-reference/Interface/AddOns/
-- Blizzard_FrameXMLUtil/CommunitiesUtil.lua:109-146 -- always loaded, no
-- LoadOnDemand in Blizzard_FrameXMLUtil's own .toc, the same file spellbook's
-- PlayerSpellsUtil already relies on above). GetMemberInfo and GetClubMembers
-- are both marked SecretInChatMessagingLockdown in the generated docs
-- (ClubDocumentation.lua:433-448, 611-626) -- a combat-adjacent restriction
-- distinct from ordinary Secret Values but handled the same way here: never
-- called unless RosterReadable() already said yes.
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

    local rows = 0
    for _, info in ipairs(online) do
        if rows >= ROSTER_CAP then break end
        if info and info.name then
            rows = rows + 1
            tt:AddLine(info.name, 1, 1, 1)
        end
    end
end

-- Elements.lua's guild element hands its tooltip straight here. The throttled
-- request runs every hover regardless of RosterReadable(): it only ever
-- refreshes local Club state, never writes anything onto a secure button, so
-- it costs nothing to keep warm even when the list itself will not render.
function ns.TopBar.GuildTooltip(tt)
    if not tt then return end
    RequestGuildRoster()
    if not RosterReadable() then return end
    pcall(BuildGuildRoster, tt)
end

-- Great Vault: C_WeeklyRewards.GetActivities() returns nothing useful before
-- a fresh character's first weekly reset, so every field is nil-checked
-- before use. "Done" is progress >= threshold, matching Blizzard's own
-- WeeklyRewardsMixin (.wow-api-reference/Interface/AddOns/
-- Blizzard_WeeklyRewards/Blizzard_WeeklyRewards.lua:412). Neither
-- WeeklyRewardActivityInfo nor its fields are marked Secret in the generated
-- docs (WeeklyRewardsDocumentation.lua:311-326).
local function VaultCounts()
    local activities = C_WeeklyRewards and C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities()
    if type(activities) ~= "table" then return nil end
    local raidDone, dungeonDone, worldDone = 0, 0, 0
    local any = false
    for _, info in ipairs(activities) do
        if type(info) == "table" and info.type and info.progress and info.threshold then
            any = true
            if info.progress >= info.threshold then
                if info.type == Enum.WeeklyRewardChestThresholdType.Raid then
                    raidDone = raidDone + 1
                elseif info.type == Enum.WeeklyRewardChestThresholdType.Activities then
                    dungeonDone = dungeonDone + 1
                elseif info.type == Enum.WeeklyRewardChestThresholdType.World then
                    worldDone = worldDone + 1
                end
            end
        end
    end
    if not any then return nil end
    return raidDone, dungeonDone, worldDone
end

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

-- Badge FontStrings. Fixed size, matching TWEEN_TIME/CLOCK_PAD's own
-- precedent elsewhere in this file: not exposed as a setting because Task 5
-- did not ask for one.
local BADGE_SIZE = 10

local friendsText, guildText, vaultText

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

local function UpdateVaultText()
    if not vaultText then return end
    local raidDone, dungeonDone, worldDone = VaultCounts()
    if not raidDone then
        vaultText:SetText("|cff808080--|r")
        return
    end
    local accentHex = Hex(AccentRGB())
    vaultText:SetText(format("|cff%sR|r%d |cff%sD|r%d |cff%sW|r%d",
        accentHex, raidDone, accentHex, dungeonDone, accentHex, worldDone))
end

-- Refresh triggers: the events that actually change these counts, plus a
-- belt-and-braces re-render every tenth Tick() below.
local badgeWatcher = CreateFrame("Frame")
badgeWatcher:RegisterEvent("FRIENDLIST_UPDATE")
badgeWatcher:RegisterEvent("BN_FRIEND_INFO_CHANGED")
badgeWatcher:RegisterEvent("GUILD_ROSTER_UPDATE")
badgeWatcher:RegisterEvent("WEEKLY_REWARDS_UPDATE")
badgeWatcher:SetScript("OnEvent", function(_, event)
    if event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_INFO_CHANGED" then
        UpdateFriendsBadge()
    elseif event == "GUILD_ROSTER_UPDATE" then
        UpdateGuildBadge()
    elseif event == "WEEKLY_REWARDS_UPDATE" then
        UpdateVaultText()
    end
end)

---------------------------------------------------------------------------------
-- Fonts: Bar.lua's ApplyFonts() calls this on every Apply() once the bar
-- exists and the feature is enabled. It lazily attaches clockText to the
-- clock button the first time it runs, then (re)sizes both readouts from
-- tbClockSize/tbSysSize and refreshes their text immediately, so the size
-- sliders and the 24h/server-time toggles all take effect live.
--
-- friendsText/guildText/vaultText follow the identical lazy pattern. guild's
-- button is secure (Macro()'s SecureActionButtonTemplate), but the lazy
-- creation below only ever fires the FIRST time it sees a non-nil button --
-- which is always inside the same Apply() call that Bar.lua's EnsureCreated
-- just built it in, already past that call's own InCombatLockdown() gate.
-- After that first call friendsText/guildText/vaultText are never nil again,
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
    if friendsBtn and not friendsText then
        friendsText = friendsBtn:CreateFontString(nil, "OVERLAY")
        friendsText:SetPoint("BOTTOM", friendsBtn, "BOTTOM", 0, -2)
    end
    if friendsText then
        friendsText:SetFont(STANDARD_TEXT_FONT, BADGE_SIZE, "OUTLINE")
        UpdateFriendsBadge()
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

    local vaultBtn = _G.KitnUITopBar_vault
    if vaultBtn and not vaultText then
        vaultText = vaultBtn:CreateFontString(nil, "OVERLAY")
        vaultText:SetPoint("BOTTOM", vaultBtn, "BOTTOM", 0, -2)
    end
    if vaultText then
        vaultText:SetFont(STANDARD_TEXT_FONT, BADGE_SIZE, "OUTLINE")
        UpdateVaultText()
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
local tickCount = 0

local function Tick()
    -- The FPS readout updates BEFORE the "is the bar shown" early-out, so the
    -- numbers keep moving while the bar is hidden.
    UpdateSys()
    ns.TopBar.RetryFit()
    local barFrame = ns.TopBar.Frame()
    if not (barFrame and barFrame:IsShown()) then return end
    UpdateClock()

    -- Belt-and-braces re-render, not a request: every tenth tick, same as the
    -- brief asks. The events above already cover the real refresh triggers.
    tickCount = tickCount + 1
    if tickCount >= 10 then
        tickCount = 0
        UpdateFriendsBadge()
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
