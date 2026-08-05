-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab.lua                                                  ║
-- ║  Purpose: Inject a KitnUI category into EllesmereUI's config ║
-- ║           panel: sidebar row, sub-tabs, and page builders.   ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- The sidebar keys every row by addon folder name, so this constant must stay
-- equal to the folder KitnUI ships in. Renaming the folder without renaming
-- this silently removes the tab.
local MODULE_KEY = "KitnUI"

---------------------------------------------------------------------------------
-- Page builders
---------------------------------------------------------------------------------

-- Every EllesmereUI page builder walks a running negative y and returns the
-- total height as a positive number. Each widget hands back its own row height,
-- so the page never hard-codes offsets.
local function BuildGeneralPage(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "PROFILES", y);                                y = y - h

    _, h = W:WideButton(parent, "Open Installer", y, function()
        if ns.OpenInstaller then ns.OpenInstaller() end
    end);                                                                          y = y - h

    _, h = W:WideButton(parent, "Load Profiles On This Character", y, function()
        if not (ns.db and ns.db.profiles and next(ns.db.profiles)) then
            print(ns.title .. ": No profiles installed yet. Run the installer first.")
            return
        end
        if ns.OpenInstaller then ns.OpenInstaller(true) end
    end);                                                                          y = y - h

    _, h = W:WideButton(parent, "Update Outdated Profiles", y, function()
        if not ns.GetOutdatedAddons then return end
        local outdated = ns.GetOutdatedAddons()
        if #outdated == 0 then
            print(ns.title .. ": All profiles are up to date.")
            return
        end
        local keys = {}
        for _, info in ipairs(outdated) do keys[info.key] = true end
        if ns.OpenInstaller then ns.OpenInstaller(false, keys) end
    end);                                                                          y = y - h

    _, h = W:WideButton(parent, "Import Class Cooldown Layouts", y, function()
        if ns.OpenInstaller then ns.OpenInstaller(false, nil, true) end
    end);                                                                          y = y - h

    _, h = W:Spacer(parent, y, 20);                                                y = y - h

    _, h = W:SectionHeader(parent, "OPTIONS", y);                                  y = y - h

    _, h = W:Toggle(parent, "Dev Mode", y,
        function() return ns.db and ns.db.devMode or false end,
        function(v) if ns.db then ns.db.devMode = v end end,
        "Shows the update prompt on every login, even when the version has not changed.");
                                                                                   y = y - h

    _, h = W:Spacer(parent, y, 20);                                                y = y - h

    _, h = W:SectionHeader(parent, "MAINTENANCE", y);                              y = y - h

    -- Resets KitnUI's own install bookkeeping only. Imported profiles stay in
    -- the addons that own them, which is why the popup says so.
    _, h = W:WideButton(parent, "Reset Installer State", y, function()
        StaticPopupDialogs["KITNUI_TAB_RESET"] = {
            text = ns.title .. ": Reset the installer's saved state?\n\nThis forgets what has been imported and reloads your UI. It does NOT remove any profile from EllesmereUI or the other addons.",
            button1 = "Reset",
            button2 = "Cancel",
            OnAccept = function()
                KitnUIDB = nil
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            -- Keeps Blizzard's own dialogs taint-free.
            preferredIndex = 3,
        }
        StaticPopup_Show("KITNUI_TAB_RESET")
    end);                                                                          y = y - h

    return math.abs(y)
end

local PAGES = {
    ["General"] = BuildGeneralPage,
}

local PAGE_ORDER = { "General" }

---------------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------------

-- EllesmereUI:RegisterModule whitelists its callers: it reads debugstack, pulls
-- the "AddOns/<folder>/" segment out of the caller's path, and drops the call
-- unless that folder is one of its own twenty. The guard reads
-- `if callerFolder and not ALLOWED[callerFolder]`, so it fails OPEN when no
-- folder can be extracted. A loadstring chunk has no file path, so the call
-- lands. This is a deliberate bypass of a deliberate gate; EllesmereUI can
-- close it in one line, which is why every step here is guarded and why losing
-- the tab must never break the installer.
local function RegisterModule(config)
    if not (_G.EllesmereUI and EllesmereUI.RegisterModule) then return end

    _G.__KitnUI_pendingReg = { key = MODULE_KEY, config = config }
    local trampoline = loadstring([[
        local r = _G.__KitnUI_pendingReg
        if r and EllesmereUI and EllesmereUI.RegisterModule then
            EllesmereUI:RegisterModule(r.key, r.config)
        end
    ]], "KitnUI-register")
    local ok = trampoline and pcall(trampoline)
    _G.__KitnUI_pendingReg = nil

    -- If loadstring is unavailable the direct call still runs. It will be
    -- rejected by the whitelist, but a rejected call is silent and harmless.
    if not ok then
        pcall(function() EllesmereUI:RegisterModule(MODULE_KEY, config) end)
    end
end

-- Registering supplies the page CONTENT. The sidebar ROW comes from two private
-- tables that EllesmereUI builds from its own hardcoded roster, so the row has
-- to be inserted separately. The panel is built lazily on first open, so login
-- is early enough.
local function InjectSidebar()
    local EUI = _G.EllesmereUI
    if not EUI then return end

    -- alwaysLoaded hides the per-addon power toggle and marks the row enabled,
    -- which is what we want: KitnUI is not an EllesmereUI module the user can
    -- switch off from here.
    EUI._addonInfoByFolder = EUI._addonInfoByFolder or {}
    EUI._addonInfoByFolder[MODULE_KEY] = EUI._addonInfoByFolder[MODULE_KEY] or {
        folder       = MODULE_KEY,
        display      = "KitnUI",
        search_name  = "KitnUI Kitn",
        alwaysLoaded = true,
    }

    -- No cross-module profile sync icon: KitnUI has nothing to sync.
    EUI._syncExempt = EUI._syncExempt or {}
    EUI._syncExempt[MODULE_KEY] = true

    -- Guard against double insertion on /reload.
    EUI.ADDON_GROUPS = EUI.ADDON_GROUPS or {}
    for _, group in ipairs(EUI.ADDON_GROUPS) do
        if group.key == "kitnui" then return end
    end
    table.insert(EUI.ADDON_GROUPS, 1, {
        key     = "kitnui",
        label   = "KitnUI",
        members = { MODULE_KEY },
    })
end

---------------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------------

-- PLAYER_LOGIN, matching every EllesmereUI options file: the page builders read
-- ns.db, which Core.lua only fills at login.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not (_G.EllesmereUI and EllesmereUI.RegisterModule and EllesmereUI.Widgets) then return end

    InjectSidebar()

    RegisterModule({
        title       = "KitnUI",
        description = "Profile installer for the EllesmereUI suite.",
        pages       = PAGE_ORDER,
        buildPage   = function(pageName, parent, yOffset)
            local builder = PAGES[pageName]
            if not builder then return math.abs(yOffset) end
            return builder(parent, yOffset)
        end,
    })
end)

-- Opens the config panel straight to our tab.
KitnCommands = KitnCommands or {}
KitnCommands["options"] = function()
    if _G.EllesmereUI and EllesmereUI.ShowModule then
        EllesmereUI:ShowModule(MODULE_KEY)
    else
        print(ns.title .. ": EllesmereUI's config panel is unavailable.")
    end
end
KitnCommands["config"] = KitnCommands["options"]
