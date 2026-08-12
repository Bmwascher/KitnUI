-- Luacheck configuration for KitnUI (ElvUI profile installer)
std = "lua51"
max_line_length = false
self = false  -- suppress W212 for unused self in colon-call methods
ignore = {"21./_.*"}  -- suppress unused warnings for _prefixed variables
exclude_files = {
    "Libs/**",
    ".wow-api-reference/**",
    "References/**",
    "Legacy/**",  -- dormant v1 ElvUI installer; kept for reference, not linted
    "dev/Annotations/**",  -- ---@meta LS type stubs, not real code
}

-- Globals this addon sets
globals = {
    "KitnUIElvDB",  -- legacy v1 SavedVariable (left intact for rollback)
    "KitnUIDB",     -- v2 SavedVariable

    -- Cross-addon shared globals (other Kitn addons register into these)
    "KitnCommands",
    "KitnUI_Shared",  -- KitnUI's ns table, published for the KitnUI_EUI addon

    -- Slash command registration (required by WoW)
    "SLASH_KITN1", "SLASH_KITN2", "SLASH_KITN3",

    -- Addon SavedVariables we write to during profile import
    "EllesmereUIDB",
    "ElvDB", "ElvPrivateDB",
    "PlaterDB",
    "KitnEssentialsDB",
    "BAGANATOR_CONFIG", "BAGANATOR_CURRENT_PROFILE",

    -- Third-party globals we mutate during profile import
    "NSRT",
    "VMRT",
    "Ayije_CDMDB",
    "WarpDepleteDB",
    "StaticPopupDialogs",
    "BW_FEAT_SHARE",

    -- Third-party globals we write fields on (minimap hide, popup suppress, etc.)
    "SlashCmdList",
    "Details",
    "BigWigsIconDB",
    "PlaterDBChr",
    "_detalhes_global",
}

-- WoW API globals this addon reads
read_globals = {
    -- Core Lua extensions in WoW
    "strsplit", "strjoin", "strtrim", "strlower", "format",
    "tinsert", "tremove", "wipe", "CopyTable", "tContains",
    "select", "math",

    -- Frame and UI
    "CreateFrame", "UIParent", "Settings", "CreateColor",
    "PluginInstallFrame", "UISpecialFrames",
    "UIFrameFadeIn", "UIFrameFadeOut",
    "hooksecurefunc",
    "STANDARD_TEXT_FONT",

    -- Static popups
    "StaticPopup_Show", "StaticPopup_Hide",
    "YES", "NO",  -- Blizzard's localized Yes/No button text

    -- Chat frame (used for programmatic slash commands + Extras chat setup)
    "DEFAULT_CHAT_FRAME", "ChatEdit_SendText",
    "FCF_SavePositionAndDimensions", "FCF_SetWindowName",
    "FCF_IterateActiveChatWindows", "GetChatWindowInfo",
    "FCF_OpenNewWindow", "FCF_CanOpenNewWindow",
    "FCF_GetNextOpenChatWindowIndex", "FCF_DockFrame",
    "C_ChatInfo", "FCF_ResetChatWindows", "FCF_StopDragging",
    "SetChatColorNameByClass", "FCFDock_SelectWindow", "GENERAL_CHAT_DOCK",

    -- Sound
    "PlaySound", "SOUNDKIT",

    -- Unit functions
    "UnitName", "UnitClass", "UnitGUID",
    "GetClassColor",
    "GetRealmName",

    -- Unit state (target arrows: which plate, hostile or not, casting or not)
    "UnitExists", "UnitIsUnit", "UnitCanAttack",
    "UnitCastingInfo", "UnitChannelInfo",

    -- Spec functions
    "C_SpecializationInfo",
    "GetSpecialization", "GetSpecializationInfo",
    "GetSpecializationInfoForClassID", "GetNumSpecializationsForClassID",

    -- Combat lockdown
    "InCombatLockdown",

    -- Top bar launchers (gamemenu, clock: insecure toggles, refuse in combat)
    "UIErrorsFrame", "ERR_NOT_IN_COMBAT", "GameMenuFrame",
    "ShowUIPanel", "HideUIPanel", "ToggleCalendar",

    -- Top bar frame (Bar.lua): tooltip owner, Unlock Mode drag, the visibility
    -- state driver Task 8 wires up
    "GameTooltip", "RegisterStateDriver", "UnregisterStateDriver",

    -- Top bar preview (Preview.lua): manual drag threshold and release polling
    "GetCursorPosition", "IsMouseButtonDown",

    -- Top bar: visibility rules (Task 8) -- keystone/serious-content predicate
    "C_ChallengeMode", "C_PvP", "IsArenaSkirmish",

    -- Top bar readouts (Readouts.lua): clock and the FPS/latency readout
    "date", "GetTime", "GetGameTime", "GetFramerate", "GetNetStats",
    "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage",

    -- Top bar rosters (Readouts.lua): class colour for the friends and guild
    -- tooltips, and the Secret-value test that guards every field read off a
    -- roster structure before it is used as a key or concatenated.
    "issecretvalue",
    "GetGuildInfo", "GetGuildRosterMOTD", "WOW_PROJECT_ID",
    "C_CreatureInfo", "RAID_CLASS_COLORS",
    "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE",

    -- Top bar: home (housing teleport + dashboard)
    "C_Housing", "HousingFramesUtil",

    -- Top bar: friends and guild counts/rosters
    "ToggleFriendsFrame", "C_FriendList", "BNGetNumFriends", "C_BattleNet",
    "GetNumGuildMembers", "IsInGuild", "C_GuildInfo", "C_Club", "CommunitiesUtil",
    "IsInInstance",

    -- Top bar: Great Vault progress
    "C_WeeklyRewards", "WeeklyRewards_ShowUI",

    -- Top bar: hearthstone ownership scan and macro building
    "C_Item", "PlayerHasToy", "C_ToyBox", "Item",

    -- Top bar: portals flyout (spell knowledge and cooldowns)
    "C_Spell", "C_SpellBook",

    -- Keyboard modifiers (Extras clean-icons copy popup)
    "IsControlKeyDown",

    -- CVar
    "SetCVar", "C_CVar",

    -- Addon management
    "C_AddOns",
    "IsAddOnLoaded",

    -- Edit Mode
    "C_EditMode", "Enum",

    -- Cooldown Manager
    "CooldownViewerSettings",

    -- Timer
    "C_Timer",

    -- Encoding (JSON serialize/deserialize, 12.0)
    "C_EncodingUtil",

    -- Libraries
    "LibStub",

    -- EllesmereUI (required dependency); ElvUI kept for the excluded Legacy tree
    "EllesmereUI",
    "ElvUI",

    -- Optional addon globals (read-only access for detection)
    "Plater",
    "BigWigsLoader",
    "BigWigsAPI", "BigWigs3DB",
    "WarpDeplete",
    "MRT", "MRT_DB",
    "Ayije_CDM",
    "NSAPI", "NorthernSkyRaidTools",

    -- Cross-addon globals (read from other Kitn addons)
    "KitnHelpLines",
    "KitnEssentials", "KitnEssentialsAPI",
    "BuffReminders",

    -- Misc
    "ReloadUI", "print",
}
