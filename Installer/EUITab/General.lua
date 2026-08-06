-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab/General.lua                                          ║
-- ║  Purpose: The General page: appearance preset, Lulu Mode,    ║
-- ║           accent scoping.                                    ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

---------------------------------------------------------------------------------
-- Profile variant
---------------------------------------------------------------------------------

local VARIANT_VALUES = { dark = "Dark", color = "Class Color" }
local VARIANT_ORDER  = { "dark", "color" }

local function CurrentVariant()
    return (ns.db and ns.db.variants and ns.db.variants.EllesmereUI) or "dark"
end

-- EllesmereUI.SetProfile routes to SwitchProfile, which returns silently on a
-- missing profile. A user who only ever installed Dark has no "... Colored"
-- profile, so a plain swap would flip our stored variant and change nothing,
-- leaving this control reading back a lie. Import that variant instead.
local function SetVariant(value)
    local useColor = (value == "color")
    local target = ns.profileName .. (useColor and " Colored" or "")

    local profiles = _G.EllesmereUIDB and EllesmereUIDB.profiles
    local exists = profiles and profiles[target] and true or false

    if not ns.SetupAddon then return end
    -- import = not exists: activate when the profile is there, import when it
    -- is not. Both paths end by writing ns.db.variants and activating.
    ns.SetupAddon("EllesmereUI", not exists, useColor)
end

---------------------------------------------------------------------------------
-- Accent scoping
---------------------------------------------------------------------------------

-- Each entry: the module folder, the sub-table holding the key (nil means the
-- key sits flat on the module profile), the key itself, and the module's own
-- refresh global.
local ACCENT_KEYS = {
    { folder = "EllesmereUIQuestTracker", sub = "questTracker", key = "headerUseAccent",  refresh = "_EQT_RefreshAll"  },
    { folder = "EllesmereUIQuestTracker", sub = "questTracker", key = "lineUseAccent",    refresh = "_EQT_RefreshAll"  },
    { folder = "EllesmereUIMythicTimer",  sub = nil,            key = "titleUseAccent",   refresh = "_EMT_Apply"       },
    { folder = "EllesmereUIMythicTimer",  sub = nil,            key = "enemyBarUseAccent",refresh = "_EMT_Apply"       },
    { folder = "EllesmereUIDamageMeters", sub = "dm",           key = "barColorUseAccent",refresh = "_EDM_Apply"       },
    { folder = "EllesmereUIDamageMeters", sub = "dm",           key = "hdrTextUseAccent", refresh = "_EDM_Apply"       },
    { folder = "EllesmereUIFriends",      sub = "friends",      key = "useAccentTab",     refresh = "_EFR_ApplyFriends"},
}

-- FF008C, the same pink ns.Color uses for the chat prefix.
local ACCENT_R, ACCENT_G, ACCENT_B = 1, 0, 140 / 255

local function AccentSettings()
    local s = ns.EUISettings()
    s.accent = s.accent or {}
    return s.accent
end

-- Half one: the colour. This snapshot holds a TABLE, not a scalar, so it cannot
-- go through ns.EUIOverride and ns.EUIRestore, which write a single key.
local function ApplyAccentColor()
    local on = AccentSettings().pink and true or false
    local saved = on and ns.EUISnap("accent", "color") or ns.EUIPeekSnap("accent", "color")
    if not saved then return end

    local EUI = _G.EllesmereUI
    if not EUI then return end
    local profile = EUI.GetActiveProfileData and EUI.GetActiveProfileData()
    if type(profile) ~= "table" then return end

    if on then
        -- Record once, by value. SetActiveProfileAccent replaces the custom
        -- table rather than mutating it, so the reference stays valid.
        if saved.prev == nil then
            local current = profile.euiAccent
            if current == nil then
                saved.prev = ns.EUI_ABSENT
            else
                saved.prev = { custom = current.custom, useClass = current.useClass }
            end
        end
        if EUI.SetAccentColor then
            EUI.SetAccentColor(ACCENT_R, ACCENT_G, ACCENT_B)
        end
    elseif saved.prev ~= nil then
        -- ResetAccentColor is deliberately NOT used here: it clears the legacy
        -- global EllesmereUIDB.accentColor, not the per-profile euiAccent that
        -- SetAccentColor actually wrote, so it would leave the pink in place.
        if saved.prev == ns.EUI_ABSENT then
            profile.euiAccent = nil
        else
            profile.euiAccent = { custom = saved.prev.custom, useClass = saved.prev.useClass }
        end
        saved.prev = nil
        if EUI.RefreshAccent then EUI.RefreshAccent() end
    end
end

-- Half two: the scoping.
local function ApplyAccentScope()
    local on = AccentSettings().pink and true or false
    local saved = on and ns.EUISnap("accent", "scope") or ns.EUIPeekSnap("accent", "scope")
    if not saved then return end

    saved.keys = saved.keys or {}
    local refreshed = {}

    for _, entry in ipairs(ACCENT_KEYS) do
        local profile = ns.EUIProfile(entry.folder)
        local target = profile
        if target and entry.sub then
            target[entry.sub] = target[entry.sub] or {}
            target = target[entry.sub]
        end
        if type(target) == "table" then
            local slot = entry.folder .. "." .. entry.key
            saved.keys[slot] = saved.keys[slot] or {}
            if on then
                ns.EUIOverride(target, saved.keys[slot], entry.key, false)
            else
                ns.EUIRestore(target, saved.keys[slot], entry.key)
            end
            refreshed[entry.refresh] = true
        end
    end

    -- The popup and menu element colour lives on the EllesmereUIDB ROOT, not in
    -- a profile, so its snapshot must not be profile-keyed. Filed under a
    -- profile it would be invisible from every other one: switching profile
    -- would leave the forced value in place with nothing to restore, and turning
    -- the switch on again would record our own forced value as the original.
    if _G.EllesmereUIDB then
        local popup = on and ns.EUISnapGlobal("popupMenuButtonTextColorMode")
                          or ns.EUIPeekSnapGlobal("popupMenuButtonTextColorMode")
        if popup then
            if on then
                ns.EUIOverride(EllesmereUIDB, popup, "popupMenuButtonTextColorMode", "native")
            else
                ns.EUIRestore(EllesmereUIDB, popup, "popupMenuButtonTextColorMode")
            end
        end
    end

    for name in pairs(refreshed) do
        local fn = _G[name]
        if type(fn) == "function" then pcall(fn) end
    end
end

-- Colour first, then scoping: the scoping pass refreshes the same modules the
-- colour change affects, so doing it in this order costs one refresh, not two.
local function ApplyAccent()
    ApplyAccentColor()
    ApplyAccentScope()
end

ns.EUIRegisterReapply(ApplyAccent)

---------------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------------

ns.EUIPages["General"] = function(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "PROFILE", y);                                 y = y - h

    _, h = W:Dropdown(parent, "Profile Variant", y,
        VARIANT_VALUES,
        CurrentVariant,
        SetVariant,
        VARIANT_ORDER,
        "Swaps the active EllesmereUI profile. Installs the variant first if you have not imported it.");
                                                                                   y = y - h

    _, h = W:Toggle(parent, "Lulu Mode", y,
        function() return ns.LuluEnabled and ns.LuluEnabled() or false end,
        function(v) if ns.SetLuluMode then ns.SetLuluMode(v) end end,
        "Round minimap, Blizzard's own action bars, and a dedicated Edit Mode layout. Asks first, then reloads.");
                                                                                   y = y - h

    _, h = W:Spacer(parent, y, 20);                                                y = y - h
    _, h = W:SectionHeader(parent, "ACCENT", y);                                   y = y - h

    _, h = W:Toggle(parent, "KitnUI Pink Accent", y,
        function() return AccentSettings().pink and true or false end,
        function(v)
            AccentSettings().pink = v and true or nil
            ApplyAccent()
        end,
        "Sets EllesmereUI's accent to KitnUI pink for this profile, and stops that accent tinting quest tracker headers, the Mythic+ timer, the damage meter and the Friends tab.");
                                                                                   y = y - h

    return math.abs(y)
end
