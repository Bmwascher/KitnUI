-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Extras.lua                                                  ║
-- ║  Purpose: Extras actions: optional QoL one-offs (clean       ║
-- ║           icons, chat setup, optimize) used by the Extras    ║
-- ║           page. All idempotent and defensively guarded.      ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- Hide the minimap buttons of companion addons. Shared by the Extras "Clean
-- Icons" button and FinishInstallation.
function ns.CleanMinimapIcons()
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBIcon then
        for _, broker in ipairs({ "BigWigs", "Plater", "NSRT" }) do
            if LDBIcon:IsRegistered(broker) then LDBIcon:Hide(broker) end
        end
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded("BigWigs") and type(BigWigsIconDB) == "table" then
        BigWigsIconDB.hide = true
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded("Plater") and PlaterDBChr and PlaterDBChr.minimap then
        PlaterDBChr.minimap.hide = true
    end
end

-- "Clean Icons": hide the companion minimap buttons AND surface a copyable link
-- to the replacement icon-texture pack. /latest, not /releases: the releases
-- page is a list the user then has to read, and the top entry is not always the
-- one they want.
local CLEAN_ICONS_URL = "https://github.com/AcidWeb/Clean-Icons-Mechagnome-Edition/releases/latest"

StaticPopupDialogs["KITNUI_CLEANICONS_URL"] = {
    text = "|cffFF008CKitn|r|cffffffffUI:|r Clean Icons\n\nCopy the link (Ctrl+C) and install it like any addon to replace the default icon borders:",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 260,
    OnShow = function(self)
        local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
        if not eb then return end
        eb:SetText(CLEAN_ICONS_URL)
        eb:SetCursorPosition(0)
        eb:HighlightText()
        eb:SetFocus()
        -- best-effort: close shortly after the user copies with Ctrl+C
        eb:SetScript("OnKeyDown", function(box, key)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0, function() if box:GetParent() then box:GetParent():Hide() end end)
            end
        end)
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.RunCleanIcons()
    ns.CleanMinimapIcons()
    StaticPopup_Show("KITNUI_CLEANICONS_URL")
    return true
end

-- Run KitnEssentials' system optimization. Returns false if KitnEssentials isn't
-- present; KE prints its own summary and owns its own reload prompt.
--
-- THIS IS THE BALANCED PRESET. OptimizeAll is KitnEssentials' named alias for
-- it, and calling the alias rather than the preset directly keeps this correct
-- if the internals move. The other preset, Max FPS, is not offered here: it
-- drops base graphics to raid values everywhere, which is a choice for the
-- player's own panel rather than an installer button.
function ns.RunOptimize()
    if not (KitnEssentials and KitnEssentials.GetModule) then return false end
    local opt = KitnEssentials:GetModule("Optimize", true)
    if not (opt and opt.OptimizeAll) then return false end
    opt:OptimizeAll()
    return true
end

-- Chat reconfigure: reset to Blizzard defaults, then rebuild the KitnUI layout
-- on top -- CVars, name colouring, tabs, message groups and channels.
--
-- THE RESET IS THE POINT: it wipes any chat layout already on the character, so
-- the rebuild below is the whole result rather than edits over whatever was
-- there. The cost is real -- a window or channel the player made themselves is
-- gone -- which is why this sits behind an opt-in button, not the install run.
--
-- FONT FACE AND FONT SIZE ARE DELIBERATELY ABSENT. KitnEssentials' Chat skin
-- owns both and re-applies them at every login, so writing either here is a
-- fight KitnUI loses on a setting the player already has a panel for. Tabs,
-- message groups and channels are not its business, which is why they stay.
--
-- Position and size repeat where the Edit Mode layout already puts chat, so the
-- two agree rather than take turns. Edit Mode owns ChatFrame1's placement in
-- 12.0, so the call below is a fallback for someone who ran this button without
-- importing the layout, not the authority.

-- The docked tab set, left to right, plus one repair entry.
--
-- ChatFrame3 (Voice) IS listed, with no dock and no name. FCF_ResetChatWindows
-- clears the message groups of every frame except ChatFrame1, which takes
-- VOICE_TEXT off the Voice tab; putting it back is all this entry does. No dock,
-- because Voice is undocked by default, and no name, because Blizzard's is
-- localized and the reset already restored it.
--
-- `groups` are message groups (SAY, GUILD, LOOT), set wholesale so a second run
-- cannot drift.
--
-- `channels` are held as Blizzard's zone channel IDs rather than names, because
-- the name is localized and the ID is not. 1 General, 2 Trade, 22 LocalDefense,
-- 42 Services.
--
-- Channels are added, never removed: the reset has already cleared the slate, so
-- a channel that reappears afterwards is one the player joined themselves.
local CHAT_WINDOWS = {
    {
        name = "General", dock = 1, reserved = "ChatFrame1",
        channels = { 1, 22 },
        groups = {
            "SYSTEM", "SYSTEM_NOMENU", "SAY", "EMOTE", "YELL", "WHISPER",
            "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
            "GUILD", "OFFICER", "MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE",
            "MONSTER_WHISPER", "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER",
            "ERRORS", "AFK", "DND", "IGNORED", "BG_HORDE", "BG_ALLIANCE",
            "BG_NEUTRAL", "COMBAT_FACTION_CHANGE", "SKILL", "LOOT", "MONEY",
            "CHANNEL", "ACHIEVEMENT", "GUILD_ACHIEVEMENT", "TARGETICONS",
            "BN_WHISPER", "BN_WHISPER_INFORM", "BN_CONVERSATION",
            "BN_INLINE_TOAST_ALERT", "CURRENCY", "BN_WHISPER_PLAYER_OFFLINE",
            "PET_BATTLE_INFO", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
            "GUILD_ITEM_LOOTED", "COMBAT_HONOR_GAIN", "PING",
        },
    },
    {
        name = "Combat Log", dock = 2, reserved = "ChatFrame2",
        groups = {
            "OPENING", "TRADESKILLS", "PET_INFO", "COMBAT_XP_GAIN",
            "COMBAT_HONOR_GAIN", "COMBAT_MISC_INFO",
        },
    },
    {
        reserved = "ChatFrame3",
        groups = { "VOICE_TEXT" },
    },
    {
        name = "Whisper", dock = 3,
        groups = { "WHISPER", "CHANNEL", "BN_WHISPER" },
    },
    {
        name = "Trade/Services", dock = 4,
        channels = { 2, 42 },
        groups = { "CHANNEL" },
    },
}

-- Locate an already-open window by its tab name, so a second run reuses the
-- window the first run made instead of stacking a duplicate beside it.
local function FindChatWindow(name)
    if not (FCF_IterateActiveChatWindows and GetChatWindowInfo) then return nil end
    local found
    FCF_IterateActiveChatWindows(function(chatFrame, index)
        local windowName = GetChatWindowInfo(index)
        if type(windowName) == "string" and strlower(windowName) == strlower(name) then
            found = chatFrame
            return true
        end
    end)
    return found
end

-- Reserved windows are always the same frame. Everything else is found by name
-- or opened. FCF_OpenNewWindow returns the new frame; the index captured before
-- the call is a fallback for a build where that return goes away.
local function EnsureChatWindow(entry)
    if entry.reserved then return _G[entry.reserved] end

    local existing = FindChatWindow(entry.name)
    if existing then return existing end

    if not (FCF_OpenNewWindow and FCF_CanOpenNewWindow) then return nil end
    if not FCF_CanOpenNewWindow() then return nil end

    local index = FCF_GetNextOpenChatWindowIndex and FCF_GetNextOpenChatWindowIndex()
    local created = FCF_OpenNewWindow(entry.name, true)
    if type(created) == "table" then return created end
    if index then return _G["ChatFrame" .. index] end
    return nil
end

local function ApplyChatWindow(entry)
    local cf = EnsureChatWindow(entry)
    if not cf then return end

    -- No name means leave the tab's own name alone. Only the Voice repair entry
    -- does that, and only because its name is localized.
    if entry.name and FCF_SetWindowName then FCF_SetWindowName(cf, entry.name) end

    if cf.RemoveAllMessageGroups and cf.AddMessageGroup then
        cf:RemoveAllMessageGroups()
        for _, group in ipairs(entry.groups) do
            cf:AddMessageGroup(group)
        end
    end

    if entry.channels and cf.AddChannel and cf.ContainsChannel
        and C_ChatInfo and C_ChatInfo.GetChannelShortcutForChannelID then
        for _, channelID in ipairs(entry.channels) do
            local shortcut = C_ChatInfo.GetChannelShortcutForChannelID(channelID)
            if shortcut and not cf:ContainsChannel(shortcut) then
                cf:AddChannel(shortcut)
            end
        end
    end

    -- Normally dead, and kept anyway. FCF_OpenNewWindow already docks what it
    -- opens at the END of the strip, so these entries land in list order. The
    -- numbers are a relative fallback, not a promise of absolute position:
    -- Blizzard redocks ChatFrame3 when Speak For Me is active, and the two new
    -- tabs then sit one place further along -- correctly, since the player
    -- really does have a Voice tab. FCF_DockFrame returns early on an
    -- already-docked frame, so the normal path costs nothing.
    if entry.dock and not cf.isDocked and FCF_DockFrame then
        FCF_DockFrame(cf, entry.dock, false)
    end
end

-- pcall-guarded throughout: a CVar name that shifts across builds should cost
-- the one setting, not the rest of the chat rebuild.
local CHAT_CVARS = {
    showTimestamps = "%I:%M %p ",
    chatStyle = "classic",
    whisperMode = "inline",
    chatMouseScroll = "1",
    chatClassColorOverride = "0",
    colorChatNamesByClass = "1",
    wholeChatWindowClickable = "0",
    speechToText = "0",
    textToSpeech = "0",
}

-- Class-coloured player names, per message group. colorChatNamesByClass above is
-- the master switch; this is the per-group list it reads.
local CLASS_COLOR_GROUPS = {
    "SAY", "EMOTE", "YELL", "WHISPER", "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT",
    "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER",
    "ACHIEVEMENT", "GUILD_ACHIEVEMENT",
    "CHANNEL1", "CHANNEL2", "CHANNEL3", "CHANNEL4", "CHANNEL5",
}

function ns.RunChatSetup()
    local cf = _G.ChatFrame1
    if not cf then return false end

    if SetCVar then
        for name, value in pairs(CHAT_CVARS) do pcall(SetCVar, name, value) end
    end

    -- Blank slate. Everything below is written onto Blizzard's defaults, so the
    -- result does not depend on what the character had before.
    if FCF_ResetChatWindows then FCF_ResetChatWindows() end

    if SetChatColorNameByClass then
        for _, group in ipairs(CLASS_COLOR_GROUPS) do
            SetChatColorNameByClass(group, true)
        end
    end

    for _, entry in ipairs(CHAT_WINDOWS) do
        ApplyChatWindow(entry)
    end

    -- Position and size LAST: the reset above moves ChatFrame1 back to
    -- Blizzard's default spot, so setting it any earlier would be undone.
    cf:ClearAllPoints()
    cf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 5, 5)
    if cf.SetSize then cf:SetSize(420, 205) end

    -- Save every active window's placement and stop it being dragged loose,
    -- which is what makes the docked strip survive the reload that follows.
    if FCF_IterateActiveChatWindows then
        FCF_IterateActiveChatWindows(function(chatFrame)
            if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(chatFrame) end
            if FCF_StopDragging then FCF_StopDragging(chatFrame) end
        end)
    end

    -- Finish on General rather than whichever tab was made last.
    if FCFDock_SelectWindow and GENERAL_CHAT_DOCK then
        FCFDock_SelectWindow(GENERAL_CHAT_DOCK, cf)
    end

    return true
end
