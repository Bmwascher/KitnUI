-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab/General.lua                                          ║
-- ║  Purpose: The General page: appearance preset, Lulu Mode,    ║
-- ║           accent scoping.                                    ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

---------------------------------------------------------------------------------
-- Appearance preset
---------------------------------------------------------------------------------

-- The seven units EllesmereUI's runtime resolver maps. The defaults table also
-- carries a playerTarget entry, but nothing reads it.
local UNIT_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }

-- Every text slot stores its colour flag next to a content key naming what the
-- slot renders, so the slot showing the name is discoverable instead of
-- guessable. Writing a slot that shows something else would tint text that is
-- not a name.
local TEXT_SLOTS = { "left", "center", "right", "extra" }

-- "both" is NOT a name. EllesmereUI's tag table resolves it to
-- "[curhpshort] | [eui-perhp]%", so it is both HEALTH formats, and the shipped
-- defaults put it on the right slot of every frame. Treating it as a name
-- tinted the health numbers class-coloured on the Dark look.
local function SlotShowsName(settings, slot)
    return settings[slot .. "TextContent"] == "name"
end

-- Whichever element carries the class colour, the other goes neutral, so the
-- readable one stays readable. That is the whole rule.
local LOOKS = {
    dark = {
        label       = "Dark",
        darkMode    = true,
        healthClass = false,
        nameClass   = true,
        raidName    = "class",
    },
    color = {
        label       = "Coloured",
        darkMode    = false,
        healthClass = true,
        nameClass   = false,
        raidName    = "custom",
    },
}

local LOOK_ORDER = { "dark", "color" }

-- The class resource bar is its own dark mode group and always has been.
-- EllesmereUI's Fonts & Colors page carries two master switches, one for Unit
-- Frames plus Raid Frames and one for the resource bar alone, because people
-- mix the two on purpose. The appearance preset follows that split: it owns the
-- frames and leaves the bar to the switch below, so choosing a look never
-- repaints a bar the user set up separately.
local function NotResourceBars(p) return p.id ~= "resourceBars" end
local function IsResourceBars(p) return p.id == "resourceBars" end

-- IsDarkModeAllOn answers "are they all on", so it cannot tell "all off" apart
-- from "some on". The selector needs both answers, so read the providers
-- directly. This is the same list IsDarkModeAllOn walks, and each provider
-- knows its own module's storage shape.
--
-- Returns true when every provider in the group is on, false when every one is
-- off, and nil when they disagree or cannot be read. nil is a real answer: it
-- means Custom.
local function DarkModeState(filter)
    local toggles = _G.EllesmereUI and EllesmereUI._darkModeToggles
    if type(toggles) ~= "table" or #toggles == 0 then return nil end

    local anyOn, anyOff = false, false
    local matched = false
    for i = 1, #toggles do
        local provider = toggles[i]
        if type(provider) ~= "table" or type(provider.isOn) ~= "function" then return nil end
        if not filter or filter(provider) then
            matched = true
            local ok, on = pcall(provider.isOn)
            if not ok then return nil end
            if on then anyOn = true else anyOff = true end
        end
    end

    -- An empty group is unreadable, not "all off": answering false would let the
    -- selector claim a look nothing is actually in.
    if not matched then return nil end
    if anyOn and anyOff then return nil end
    return anyOn
end

-- Sets the look and lets go. Nothing is snapshotted and nothing re-applies,
-- because these values are KitnUI's own profile content rather than an override
-- of something the user chose. A user who changes one of them afterwards has
-- simply changed their profile, and the selector reads Custom from then on.
local function ApplyLook(key)
    local look = LOOKS[key]
    if not (look and _G.EllesmereUI) then return end

    -- A pure view over the module providers, each of which flips its own flag
    -- and repaints itself. Writing those flags directly is exactly what this
    -- master exists to prevent. Filtered to the frame group: see NotResourceBars.
    if EllesmereUI.SetDarkModeAll then
        pcall(EllesmereUI.SetDarkModeAll, look.darkMode, NotResourceBars)
    end

    local uf = ns.EUIProfile("EllesmereUIUnitFrames")
    if uf then
        for _, unit in ipairs(UNIT_KEYS) do
            local settings = uf[unit]
            if type(settings) == "table" then
                settings.healthClassColored = look.healthClass
                for _, slot in ipairs(TEXT_SLOTS) do
                    if SlotShowsName(settings, slot) then
                        settings[slot .. "TextClassColor"] = look.nameClass
                    end
                end
            end
        end
        -- Two refreshers, both required. ReloadFrames rebuilds the frames, but
        -- the unit NAME is rendered by its own pass and keeps the colour it was
        -- last painted with, so a look change left names class-coloured with
        -- everything else already switched. EllesmereUI's own spec-override
        -- refresh map names both functions for this module for the same reason.
        if _G._EUF_ReloadFrames then pcall(_G._EUF_ReloadFrames) end
        if _G._EUF_RefreshUnitNames then pcall(_G._EUF_RefreshUnitNames) end
    end

    -- Two name renderers, only one live at a time: the top name bar suppresses
    -- the in-frame name while it is enabled. Both are written so the look
    -- survives the user turning that bar on later. Their custom colours are NOT
    -- written: both already default to white, and overwriting would discard a
    -- colour the user picked on purpose. MatchesLook deliberately reads back
    -- only nameColorMode, the renderer that is live by default: see its comment.
    local rf = ns.EUIProfile("EllesmereUIRaidFrames")
    if rf then
        rf.nameColorMode = look.raidName
        rf.topNameBarTextColorMode = look.raidName
        if _G._ERF_RefreshAll then pcall(_G._ERF_RefreshAll) end
    end
end

-- True only when every value this look writes currently holds that look's
-- value, with ONE deliberate exception: topNameBarTextColorMode is written but
-- not read back. That renderer is off by default and only suppresses the
-- in-frame name once the user turns it on, so letting it decide Custom would
-- report a mismatch about a band most users never see. A module that cannot be
-- reached is skipped rather than counted as a mismatch, so a user who disabled
-- Raid Frames still sees Dark or Coloured instead of a permanent Custom.
local function MatchesLook(key)
    local look = LOOKS[key]
    if not look then return false end

    local dark = DarkModeState(NotResourceBars)
    if dark == nil or dark ~= look.darkMode then return false end

    local uf = ns.EUIProfile("EllesmereUIUnitFrames")
    if uf then
        for _, unit in ipairs(UNIT_KEYS) do
            local settings = uf[unit]
            if type(settings) == "table" then
                if (settings.healthClassColored and true or false) ~= look.healthClass then
                    return false
                end
                for _, slot in ipairs(TEXT_SLOTS) do
                    if SlotShowsName(settings, slot)
                        and (settings[slot .. "TextClassColor"] and true or false) ~= look.nameClass then
                        return false
                    end
                end
            end
        end
    end

    local rf = ns.EUIProfile("EllesmereUIRaidFrames")
    if rf and rf.nameColorMode ~= look.raidName then return false end

    return true
end

-- nil means Custom, which is a real and reachable state rather than an error.
local function CurrentLook()
    for _, key in ipairs(LOOK_ORDER) do
        if MatchesLook(key) then return key end
    end
    return nil
end

local function LookStateText()
    local current = CurrentLook()
    return current and LOOKS[current].label:upper() or "CUSTOM"
end

-- The installer applies the default look once, at import time, so a fresh
-- install never opens on Custom. See Setup.lua for why that is data's job and
-- not the page's.
ns.ApplyLook = ApplyLook

-- Refused in combat because a look is not one write. It flips dark mode across
-- two modules, rewrites the unit frame colour flags, rewrites the raid frame
-- name mode, and asks three different refreshers to repaint. Anything that
-- defers under lockdown leaves the stored values ahead of what is on screen,
-- and the user is left looking at a half-applied look mid-fight.
local function PickLook(key)
    if InCombatLockdown() then
        print(ns.title .. ": Appearance cannot be changed in combat.")
        return
    end

    ApplyLook(key)

    -- The page caches its rows, so the section header keeps naming the old look
    -- until the page is rebuilt. force = true because a header's text is not a
    -- registered widget refresh callback, so the fast path would not update it.
    if _G.EllesmereUI and EllesmereUI.RefreshPage then
        pcall(EllesmereUI.RefreshPage, EllesmereUI, true)
    end
end

-- Same combat refusal as PickLook and for the same reason: the resource bar
-- provider writes its flag first and only then guards its repaint on
-- InCombatLockdown, so a mid-fight flip stores the new value and paints the old
-- one. The refresh puts the switch back where the refusal left the data.
local function SetResourceBarDark(on)
    if InCombatLockdown() then
        print(ns.title .. ": Appearance cannot be changed in combat.")
    elseif _G.EllesmereUI and EllesmereUI.SetDarkModeAll then
        pcall(EllesmereUI.SetDarkModeAll, on, IsResourceBars)
    end

    if _G.EllesmereUI and EllesmereUI.RefreshPage then
        pcall(EllesmereUI.RefreshPage, EllesmereUI)
    end
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

    -- The header carries the current look because the widget factory has no
    -- label row. SectionHeader passes its text through EllesmereUI.L, and a
    -- composed string is simply not in the localisation table, so it comes back
    -- unchanged.
    local lookHeader
    lookHeader, h = W:SectionHeader(parent, "APPEARANCE (" .. LookStateText() .. ")", y)
                                                                                   y = y - h

    -- EllesmereUI caches a built page and re-shows the same wrapper rather than
    -- running the builder again, so a look changed from EllesmereUI's own
    -- options left this header naming the look the user had abandoned until a
    -- reload. Showing the wrapper fires OnShow on its children, which is the one
    -- moment the page is guaranteed to be back on screen. Hooked, not set, so a
    -- handler EllesmereUI adds to its own widget later still runs.
    if lookHeader and lookHeader._label then
        lookHeader:HookScript("OnShow", function()
            lookHeader._label:SetText("APPEARANCE (" .. LookStateText() .. ")")
        end)
    end

    _, h = W:WideDualButton(parent, LOOKS.dark.label, LOOKS.color.label, y,
        function() PickLook("dark") end,
        function() PickLook("color") end);                                        y = y - h

    -- Its own switch, not part of the preset. EllesmereUI splits the resource
    -- bar out of its own dark mode master for the same reason: a dark bar over
    -- coloured frames, or the reverse, is a normal thing to want.
    _, h = W:Toggle(parent, "Dark Class Resource Bar", y,
        function() return DarkModeState(IsResourceBars) == true end,
        function(v) SetResourceBarDark(v) end,
        "Darkens the class resource bar on its own, without changing the unit frames or raid frames.");
                                                                                   y = y - h

    _, h = W:Spacer(parent, y, 20);                                                y = y - h
    _, h = W:SectionHeader(parent, "LULU MODE", y);                                y = y - h

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
