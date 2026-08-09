-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/TopBar/Elements.lua                              ║
-- ║  Purpose: The top bar's element registry. Pure data plus     ║
-- ║           per-element handlers. No layout, no storage.       ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.TopBar = ns.TopBar or {}

-- Placeholder art. No icon texture was specified for any of the twelve
-- launchers below (Task 1's own brief gives ids, labels, panels and
-- macrotexts, but no icon column), and Blizzard's own frames do not offer one
-- consistent, static, file-path icon to borrow: several of the target panels
-- (CharacterFrame, PlayerSpellsFrame, ProfessionsFrame, AchievementFrame)
-- render a dynamic or spec-dependent portrait instead of a fixed icon, so
-- there is nothing fixed to copy. The question mark makes the gap visible
-- in-game rather than hiding it behind a plausible-looking guess. Real art is
-- a follow-up, and nothing draws yet in Task 1 regardless.
local PLACEHOLDER_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- A launcher's whole job is to click something Blizzard already owns. Secure,
-- because several of the targets are protected, and a macro is the only way to
-- reach them from a click the player made.
--
-- useOnKeyDown is forced false by Bar.lua on every secure element. Without it
-- the ActionButtonUseKeyDown CVar fires on key-down and the AnyUp click never
-- arrives, which presents as "the buttons randomly do not work for some users".
local function Macro(id, label, icon, panel, macrotext, requires)
    return {
        id = id, label = label, icon = icon, panel = panel,
        kind = "launcher", secure = true,
        attrs = function(btn)
            btn:SetAttribute("type1", "macro")
            btn:SetAttribute("macrotext1", macrotext)
        end,
        tooltip = function(tt) tt:AddLine(label, 1, 1, 1) end,
        requires = requires,
    }
end

---------------------------------------------------------------------------------
-- Home: the one launcher that is not a passthrough. Left click teleports home
-- via the "teleporthome" secure action type -- three attributes read straight
-- off the button (house-neighborhood-guid, house-guid, house-plot-id) that the
-- engine itself turns into C_Housing.TeleportHome(...); nothing here calls
-- that protected function directly
-- (.wow-api-reference/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua:620-629).
-- Right click opens the housing dashboard through the same helper the game's
-- own Housing micro button uses
-- (.wow-api-reference/Interface/AddOns/Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua:1012-1020).
--
-- C_Housing.GetPlayerOwnedHouses() is async: it answers through the
-- PLAYER_HOUSE_LIST_UPDATED event, not a return value
-- (.wow-api-reference/Interface/AddOns/Blizzard_HousingDashboard/Blizzard_HousingDashboardHouseInfoContent.lua:101-109).
-- The three field names on each list entry -- neighborhoodGUID, houseGUID,
-- plotID -- are read the same way Blizzard_HousingDashboardHouseUpgrade.lua:362
-- reads them before its own TeleportHome call. WindTools runs this identical
-- pattern already, including taking the first owned house with no further
-- selection UI (References/ElvUI_WindTools-v4.19/Modules/Misc/GameBar.lua:
-- 1461-1473, 1608-1610, 1647-1648) -- confirmation this addon is genuinely
-- 12.0-compatible, not just a plausible guess at the shape.
--
-- SetAttribute is protected, so cachedHouse is only ever written onto the
-- button from inside HomeAttrs, which WireSecureAttributes (Bar.lua) only
-- ever reaches outside combat: Apply() defers its whole protected half
-- whenever InCombatLockdown() is true.
local cachedHouse

local function RequestHouseList()
    if C_Housing and C_Housing.GetPlayerOwnedHouses then
        C_Housing.GetPlayerOwnedHouses()
    end
end

local housingWatcher = CreateFrame("Frame")
housingWatcher:RegisterEvent("PLAYER_LOGIN")
housingWatcher:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
housingWatcher:SetScript("OnEvent", function(_, event, houseInfoList)
    if event == "PLAYER_LOGIN" then
        RequestHouseList()
        return
    end
    local house = type(houseInfoList) == "table" and houseInfoList[1]
    if house and house.neighborhoodGUID and house.houseGUID and house.plotID then
        cachedHouse = house
    else
        cachedHouse = nil
    end
end)

-- Left click with nothing cached: an insecure fallback that explains why,
-- matching WindTools' own copy for the same state (GameBar.lua:741). Right
-- click always tries the dashboard; ToggleHousingDashboard is itself the
-- combat-agnostic helper Blizzard built for exactly this "call it from
-- outside the Housing addons" case, but the family's own hard rule still
-- applies to the panel toggle underneath it, so it is gated the same way
-- gamemenu gates GameMenuFrame above.
local function HomeOnClick(_self, button)
    if button == "RightButton" then
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
            return
        end
        if HousingFramesUtil and HousingFramesUtil.ToggleHousingDashboard then
            HousingFramesUtil.ToggleHousingDashboard()
        end
        return
    end
    if button == "LeftButton" and not cachedHouse then
        print("|cffFF008CKitn|r|cffffffffUI:|r House data cannot be updated in combat.")
    end
end

-- WireSecureAttributes (Bar.lua) calls this every Apply(), always outside
-- combat. Clearing type1 when nothing is cached stops a stale partial
-- attribute set from firing a teleport to the wrong plot.
local function HomeAttrs(btn)
    if cachedHouse then
        btn:SetAttribute("type1", "teleporthome")
        btn:SetAttribute("house-neighborhood-guid", cachedHouse.neighborhoodGUID)
        btn:SetAttribute("house-guid", cachedHouse.houseGUID)
        btn:SetAttribute("house-plot-id", cachedHouse.plotID)
    else
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("house-neighborhood-guid", nil)
        btn:SetAttribute("house-guid", nil)
        btn:SetAttribute("house-plot-id", nil)
    end
    if not btn._homeWired then
        btn:SetScript("OnClick", HomeOnClick)
        -- Opportunistic refresh on hover, matching WindTools' ButtonOnEnter
        -- (GameBar.lua:1269-1271). HookScript ADDS to Bar.lua's own OnEnter
        -- (tint + tooltip) rather than replacing it.
        btn:HookScript("OnEnter", function()
            if not InCombatLockdown() then RequestHouseList() end
        end)
        btn._homeWired = true
    end
end

local homeElement = {
    id = "home", label = "Home", icon = PLACEHOLDER_ICON, panel = "right",
    kind = "launcher", secure = true,
    attrs = HomeAttrs,
    tooltip = function(tt)
        tt:AddLine("Home", 1, 1, 1)
        tt:AddLine("Left-click: Teleport Home", 1, 1, 1)
        tt:AddLine("Right-click: Housing Dashboard", 1, 1, 1)
    end,
}

---------------------------------------------------------------------------------
-- Friends: no FriendsMicroButton exists in the Mainline micro menu (confirmed
-- against .wow-api-reference/Interface/AddOns/Blizzard_MicroMenu/Mainline/
-- MainMenuBarMicroButtons.xml, which lists Character/Profession/PlayerSpells/
-- Achievement/QuestLog/Housing/Guild/LFD/Collections/EJ/Help/Store/MainMenu
-- and nothing for friends), so this cannot be a Macro() passthrough the way
-- guild below is. ToggleFriendsFrame is the real global
-- (.wow-api-reference/Interface/AddOns/Blizzard_FriendsFrame/Mainline/
-- FriendsFrame.lua:1416), and it is not protected, so this is an insecure
-- toggle guarded the same way gamemenu and clock are above.
--
-- The badge (online count) and the roster tooltip are Readouts.lua's job --
-- everything with a ticker and cross-element state lives there. This element
-- only supplies the click and hands the tooltip off.
local friendsElement = {
    id = "friends", label = "Friends", icon = PLACEHOLDER_ICON, panel = "left",
    kind = "launcher", secure = false,
    onClick = function(_self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
            return
        end
        ToggleFriendsFrame()
    end,
    tooltip = function(tt)
        tt:AddLine("Friends", 1, 1, 1)
        if ns.TopBar.FriendsTooltip then ns.TopBar.FriendsTooltip(tt) end
    end,
}

-- Guild: GuildMicroButton DOES exist (Mainline/MainMenuBarMicroButtons.xml:183),
-- so this stays the ordinary Macro() passthrough every other micro-button
-- launcher in this file uses -- only its tooltip is replaced, because Macro()'s
-- own is a one-line label and this one needs the roster.
local guildElement = Macro("guild", "Guild", PLACEHOLDER_ICON, "left",
    "/click GuildMicroButton")
guildElement.tooltip = function(tt)
    tt:AddLine("Guild", 1, 1, 1)
    if ns.TopBar.GuildTooltip then ns.TopBar.GuildTooltip(tt) end
end

-- Great Vault: WeeklyRewardsFrame is load-on-demand, so opening it goes
-- through WeeklyRewards_ShowUI, the same global the rest of the client uses
-- to load and show it (.wow-api-reference/Interface/AddOns/Blizzard_UIParent/
-- Mainline/UIParent.lua:527-534). Not itself a secure/protected frame, but
-- gated the same way every other insecure launcher in this file is, for the
-- same reason gamemenu is.
local vaultElement = {
    id = "vault", label = "Great Vault", icon = PLACEHOLDER_ICON, panel = "right",
    kind = "launcher", secure = false,
    onClick = function(_self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
            return
        end
        WeeklyRewards_ShowUI()
    end,
    tooltip = function(tt)
        tt:AddLine("Great Vault", 1, 1, 1)
        if ns.TopBar.VaultTooltip then ns.TopBar.VaultTooltip(tt) end
    end,
}

ns.TopBar.Elements = {
    friendsElement,
    guildElement,

    Macro("groupfinder", "Group Finder", PLACEHOLDER_ICON, "left",
        "/click LFDMicroButton"),

    Macro("journal", "Encounter Journal", PLACEHOLDER_ICON, "left",
        "/click EJMicroButton"),

    Macro("achievements", "Achievements", PLACEHOLDER_ICON, "left",
        "/click AchievementMicroButton"),

    Macro("collections", "Collections", PLACEHOLDER_ICON, "left",
        "/click CollectionsMicroButton"),

    -- Toy Box is a tab inside the same Collections journal as `collections`,
    -- not its own micro button. Click the micro button to open the journal,
    -- then select the Toy Box tab (index 3, matching
    -- Blizzard_Collections.lua's own titles[3] = TOY_BOX) on the line after:
    -- /click runs its OnClick synchronously, so the journal already exists
    -- and is shown by the time the second line runs.
    Macro("toybox", "Toy Box", PLACEHOLDER_ICON, "left",
        "/click CollectionsMicroButton\n/run CollectionsJournal_SetTab(CollectionsJournal, 3)"),

    homeElement,
    vaultElement,

    Macro("character", "Character panel", PLACEHOLDER_ICON, "right",
        "/click CharacterMicroButton"),

    -- No SpellbookMicroButton exists on Mainline: the 12.0 client folded the
    -- spellbook into a tab of PlayerSpellsFrame (the same frame `talents`
    -- opens), reachable only through PlayerSpellsUtil.OpenToSpellBookTab()
    -- (.wow-api-reference/Interface/AddOns/Blizzard_FrameXMLUtil/Mainline/PlayerSpellsUtil.lua:49).
    -- The brief's own instruction to verify micro-button names rather than
    -- trust the table applies here: the table's `/click SpellbookMicroButton`
    -- would silently do nothing, because that global no longer exists.
    Macro("spellbook", "Spellbook", PLACEHOLDER_ICON, "right",
        "/run PlayerSpellsUtil.OpenToSpellBookTab()"),

    Macro("talents", "Talents", PLACEHOLDER_ICON, "right",
        "/click PlayerSpellsMicroButton"),

    Macro("professions", "Professions", PLACEHOLDER_ICON, "right",
        "/click ProfessionMicroButton"),

    Macro("euiconfig", "EllesmereUI", PLACEHOLDER_ICON, "right",
        "/run if EllesmereUI and EllesmereUI.Toggle then EllesmereUI:Toggle() end"),

    -- Absent entirely, not greyed out, when KitnEssentials is not loaded.
    Macro("kitnessentials", "KitnEssentials", PLACEHOLDER_ICON, "right", "/kes",
        function()
            return C_AddOns and C_AddOns.IsAddOnLoaded
               and C_AddOns.IsAddOnLoaded("KitnEssentials") and true or false
        end),

    -- Not a macro passthrough: /click GameMenuButtonLogout is wrong (that
    -- button logs out), so this toggles GameMenuFrame directly and refuses in
    -- combat rather than relying on secure attribute handling.
    {
        id = "gamemenu", label = "Game Menu", icon = PLACEHOLDER_ICON, panel = "right",
        kind = "launcher", secure = false,
        onClick = function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
                return
            end
            if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame)
            else ShowUIPanel(GameMenuFrame) end
        end,
        tooltip = function(tt) tt:AddLine("Game Menu", 1, 1, 1) end,
    },

    -- Clock: the centre panel's only occupant (DEFAULT_ORDER.centre), never
    -- switched off, so Options.lua excludes it from the ELEMENTS list by id
    -- rather than this element declining a toggle. Bar.lua creates its button
    -- as "KitnUITopBar_clock" the same as any other element; Readouts.lua
    -- reaches that stable global name to attach the actual time FontString
    -- and to size it from tbClockSize, since neither the button table nor
    -- centrePanel is part of this file's interface. Left click opens the
    -- calendar, middle click reloads; both are insecure (ToggleCalendar and
    -- ReloadUI need no protection) and refuse in combat like gamemenu above.
    {
        id = "clock", label = "Clock", panel = "centre",
        kind = "readout", secure = false,
        onClick = function(_self, button)
            if button ~= "LeftButton" and button ~= "MiddleButton" then return end
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
                return
            end
            if button == "LeftButton" then
                ToggleCalendar()
            else
                ReloadUI()
            end
        end,
        tooltip = function(tt)
            tt:AddLine("Left-click: Calendar", 1, 1, 1)
            tt:AddLine("Middle-click: Reload UI", 1, 1, 1)
        end,
    },

    -- fps: never laid out in a panel — it lives on its own UIParent frame,
    -- positioned against the clock rather than with the icons, per the panel
    -- field's own contract above ("nil means the element is NOT laid out by
    -- a panel: it anchors itself. fps is the only one"). Bar.lua's
    -- EnsureCreated now skips CreateElementButton for any element with no
    -- panel, so this stays out of leftPanel/rightPanel entirely; it is
    -- present here only so the ELEMENTS list picks it up automatically.
    -- Never add "fps" to any tbOrder array — it is not laid out.
    {
        id = "fps", label = "FPS and latency",
        kind = "readout", secure = false,
    },
}

-- Read from the registered default rather than duplicated. Two copies of an
-- ordering drift, and the one that drifts is always the one nobody is looking at.
ns.TopBar.DEFAULT_ORDER = ns.EUI_DEFAULTS and ns.EUI_DEFAULTS.tbOrder

ns.TopBar.ById = {}
for _, el in ipairs(ns.TopBar.Elements) do
    ns.TopBar.ById[el.id] = el
end
