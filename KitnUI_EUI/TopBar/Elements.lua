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

ns.TopBar.Elements = {
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
}

-- fps is absent from every panel on purpose: it is positioned against the clock,
-- not laid out with the icons. Bar.lua treats it as a special case.
--
-- Read from the registered default rather than duplicated. Two copies of an
-- ordering drift, and the one that drifts is always the one nobody is looking at.
ns.TopBar.DEFAULT_ORDER = ns.EUI_DEFAULTS and ns.EUI_DEFAULTS.tbOrder

ns.TopBar.ById = {}
for _, el in ipairs(ns.TopBar.Elements) do
    ns.TopBar.ById[el.id] = el
end
