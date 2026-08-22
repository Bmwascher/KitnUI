-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/General.lua                                      ║
-- ║  Purpose: The General page: appearance preset, Lulu Mode,    ║
-- ║           accent scoping.                                    ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- Core.lua sets this and stops when KitnUI's shared namespace is unreachable, so
-- ns has no title, no db and no data. Everything below needs all three.
if ns.EUI_INERT then return end

---------------------------------------------------------------------------------
-- Appearance preset
---------------------------------------------------------------------------------

-- The seven units EllesmereUI's runtime resolver maps. The defaults table also
-- carries a playerTarget entry, but nothing reads it.
local UNIT_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }

-- Every text slot stores its colour flag next to a content key naming what the
-- slot renders, so the slot showing the name is discoverable rather than
-- guessable. Writing a slot that shows something else would tint text that is
-- not a name.
--
-- Unit frames render text through TWO independent sets: the four in-frame slots
-- and the three on the optional Bottom Text Bar. A profile using the bar shows
-- its name there, so both sets have to be written.
--
-- `bar` marks the Bottom Text Bar slots so the read-back can ignore them while
-- the bar is off. They are still WRITTEN either way, so the look survives the
-- user turning the bar on later.
local TEXT_SLOTS = {
    { content = "leftTextContent",   color = "leftTextClassColor"   },
    { content = "centerTextContent", color = "centerTextClassColor" },
    { content = "rightTextContent",  color = "rightTextClassColor"  },
    { content = "extraTextContent",  color = "extraTextClassColor"  },
    { content = "btbLeftContent",    color = "btbLeftClassColor",   bar = true },
    { content = "btbCenterContent",  color = "btbCenterClassColor", bar = true },
    { content = "btbRightContent",   color = "btbRightClassColor",  bar = true },
}

-- Four content values put the name in a slot, not one: EllesmereUI builds a tag
-- string containing [eui-name] for each of these. Testing only for "name" skips
-- any profile that shows the level or the current target beside it.
--
-- "both" is deliberately absent: it resolves to two HEALTH formats and never a
-- name, and the shipped defaults put it on the right slot of every frame.
local NAME_CONTENT = {
    name         = true,
    nametotarget = true,
    levelname    = true,
    namelevel    = true,
}

local function SlotShowsName(settings, slot)
    return NAME_CONTENT[settings[slot.content]] or false
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
        label       = "Colored",
        darkMode    = false,
        healthClass = true,
        nameClass   = false,
        raidName    = "custom",
    },
}

local LOOK_ORDER = { "dark", "color" }

-- Raid frames render the unit name through two renderers and only one is live:
-- the top name bar suppresses the in-frame name while it is enabled. Both are
-- WRITTEN so the look survives the user switching the bar on later; only the
-- live one is READ BACK, because a header decided by invisible text reports a
-- mismatch the user cannot act on.
local RAID_NAME_KEYS = { "nameColorMode", "topNameBarTextColorMode" }

-- Party frames honour these twins only once the user decouples the matching
-- colour section, so they are written when present and never created. Creating
-- one would decouple a section the user chose to leave joined.
local RAID_NAME_PARTY_KEYS = { "party_nameColorMode", "party_topNameBarTextColorMode" }

-- Which of the two name renderers is on screen, for the raid keys (prefix "")
-- or the party twins (prefix "party_"). A twin counts as governing whenever it
-- EXISTS, which is an approximation -- see the limits noted above MatchesLook.
local function LiveRaidNameKey(rf, prefix)
    local enabled = rf[prefix .. "topNameBarEnabled"]
    if enabled == nil then enabled = rf.topNameBarEnabled end
    if enabled then return prefix .. "topNameBarTextColorMode" end
    return prefix .. "nameColorMode"
end

-- The class resource bar is its own dark mode group. EllesmereUI splits it out
-- because people mix the two on purpose, so the appearance preset owns the
-- frames and leaves the bar to its own switch below.
local function NotResourceBars(p) return p.id ~= "resourceBars" end
local function IsResourceBars(p) return p.id == "resourceBars" end

-- IsDarkModeAllOn answers "are they all on", so it cannot tell "all off" from
-- "some on". The selector needs both, so read the same providers directly.
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
                        settings[slot.color] = look.nameClass
                    end
                end
            end
        end
        -- Two refreshers, both required. ReloadFrames rebuilds the frames, but
        -- the unit NAME is rendered by its own pass and keeps the colour it was
        -- last painted with, so without the second call a look change leaves
        -- names class-coloured with everything else already switched.
        if _G._EUF_ReloadFrames then pcall(_G._EUF_ReloadFrames) end
        if _G._EUF_RefreshUnitNames then pcall(_G._EUF_RefreshUnitNames) end
    end

    -- Two name renderers, only one live at a time: the top name bar suppresses
    -- the in-frame name while enabled. Both are written so the look survives the
    -- user turning that bar on later. Their custom colours are NOT written: both
    -- default to white, and overwriting would discard a deliberate choice.
    local rf = ns.EUIProfile("EllesmereUIRaidFrames")
    if rf then
        for _, k in ipairs(RAID_NAME_KEYS) do
            rf[k] = look.raidName
        end
        for _, k in ipairs(RAID_NAME_PARTY_KEYS) do
            if rf[k] ~= nil then
                rf[k] = look.raidName
            end
        end
        if _G._ERF_RefreshAll then pcall(_G._ERF_RefreshAll) end
    end
end

-- True only when every value this look writes currently holds that look's value,
-- with one deliberate exception: a text renderer that is switched off is written
-- but not read back, because letting invisible text decide Custom reports a
-- mismatch the user cannot act on. The raid frames follow the same rule through
-- LiveRaidNameKey, which reads whichever of their two renderers is on screen.
--
-- Two label-only states slip through the party-twin approximation: a twin on a
-- synced section is read while governing nothing, and party and raid can end up
-- reading different renderers. Neither is reachable by an apply, which writes
-- every key involved, so the header is only ever wrong about a later hand edit.
-- Exact gating would cost a partySyncSections lookup per key and is not worth it
-- for one wrong word in a header.
--
-- A module that cannot be reached is skipped rather than counted as a mismatch,
-- so a user who disabled Raid Frames still sees Dark or Coloured instead of a
-- permanent Custom.
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
                    -- A slot on a switched-off Bottom Text Bar is written but not
                    -- read back: it renders nothing, so letting it decide Custom
                    -- would report a mismatch about text that is not on screen.
                    if (not slot.bar or settings.bottomTextBar)
                        and SlotShowsName(settings, slot)
                        and (settings[slot.color] and true or false) ~= look.nameClass then
                        return false
                    end
                end
            end
        end
    end

    local rf = ns.EUIProfile("EllesmereUIRaidFrames")
    if rf then
        local liveKey = LiveRaidNameKey(rf, "")
        if rf[liveKey] ~= look.raidName then return false end
        -- Read back only while it exists, matching the write.
        local partyKey = LiveRaidNameKey(rf, "party_")
        if rf[partyKey] ~= nil and rf[partyKey] ~= look.raidName then return false end
    end

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

-- The installer's EllesmereUI page offers the same two looks and has to know
-- which one is live to mark it. It reads through this rather than testing the
-- profile itself: a second copy of MatchesLook would drift from this one the
-- first time a look gains a key. Both names must also be listed in Core.lua's
-- EXPORTS or they never cross into KitnUI, silently.
ns.CurrentLook = CurrentLook

-- Refused in combat because a look is not one write: it flips dark mode across
-- two modules, rewrites the unit and raid frame colour flags, and asks three
-- refreshers to repaint. Anything that defers under lockdown leaves the stored
-- values ahead of the screen, half-applied mid-fight.
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
-- key sits flat on the module profile), the key itself, the module's own refresh
-- global, and the value to force. `value` is omitted on the entries that scope
-- the accent OUT, because false is what scoping means and the loop defaults to
-- it; the quest tracker header is the one place the switch scopes the accent IN,
-- so it names its value.
--
-- The header needs BOTH keys: EllesmereUIQuestTracker_Skin.lua:117 reads
-- headerShowClassColor first and returns the class colour without ever looking
-- at headerUseAccent, so forcing the accent on alone is silently ignored on any
-- profile that had class-coloured headers. That citation is 8.9.6, verified
-- 2026-08-20 -- stamped because Core.lua's unstamped 8.7.5 line numbers rotted
-- silently once the host moved its settings panel.
local ACCENT_KEYS = {
    { folder = "EllesmereUIQuestTracker", sub = "questTracker", key = "headerUseAccent",  refresh = "_EQT_RefreshAll", value = true },
    { folder = "EllesmereUIQuestTracker", sub = "questTracker", key = "headerShowClassColor", refresh = "_EQT_RefreshAll" },
    { folder = "EllesmereUIQuestTracker", sub = "questTracker", key = "lineUseAccent",    refresh = "_EQT_RefreshAll"  },
    { folder = "EllesmereUIMythicTimer",  sub = nil,            key = "titleUseAccent",   refresh = "_EMT_Apply"       },
    { folder = "EllesmereUIMythicTimer",  sub = nil,            key = "enemyBarUseAccent",refresh = "_EMT_Apply"       },
    { folder = "EllesmereUIDamageMeters", sub = "dm",           key = "barColorUseAccent",refresh = "_EDM_Apply"       },
    { folder = "EllesmereUIDamageMeters", sub = "dm",           key = "hdrTextUseAccent", refresh = "_EDM_Apply"       },
    { folder = "EllesmereUIFriends",      sub = "friends",      key = "useAccentTab",     refresh = "_EFR_ApplyFriends"},
}

-- The shipped pink, lifted out of the registered default so there is exactly one
-- literal in the addon. Copied into three scalars rather than kept as a reference
-- to that table: a reference is one careless write away from editing the defaults
-- themselves, which is the shape Core.lua's DEFAULTS comment exists to forbid.
--
-- The fallback covers ns.EUISettings()'s own fallback path, which returns a bare
-- table that no defaults were ever merged into.
local ACCENT_R, ACCENT_G, ACCENT_B do
    local d = ns.EUI_DEFAULTS and ns.EUI_DEFAULTS.accentCustom
    ACCENT_R = (d and d.r) or 1
    ACCENT_G = (d and d.g) or 0
    ACCENT_B = (d and d.b) or 0.549
end

-- Tested against false rather than read for truthiness, because the registered
-- default is TRUE and an absent key must therefore mean pink. The settings
-- fallback path merges no defaults, so absent is reachable.
local function AccentUsesDefault()
    return ns.EUISettings().accentUseDefault ~= false
end

-- The colour the master switch forces right now. Falls back to the shipped pink
-- whenever the stored custom colour is not three numbers, so a hand-edited saved
-- variable cannot make SetAccentColor throw.
local function AccentColor()
    if not AccentUsesDefault() then
        local c = ns.EUISettings().accentCustom
        if type(c) == "table" and type(c.r) == "number"
           and type(c.g) == "number" and type(c.b) == "number" then
            return c.r, c.g, c.b
        end
    end
    return ACCENT_R, ACCENT_G, ACCENT_B
end

-- Read and write the switch directly on the settings table, never through a
-- sub-table: in that shape it was the only switch that did not survive a reload.
-- See the DEFAULTS comment in Core.lua.
local function AccentEnabled()
    local s = ns.EUISettings()
    return s.accentPink and true or false
end

-- The retired key is cleared here as well as in Core.lua's fold, so a deliberate
-- click always ends the ambiguity locally. The fold alone is not enough: it is
-- debounced, and an import can hand control back without a reload, so a block
-- carrying both keys can sit in front of the user for that long.
local function SetAccentEnabled(v)
    local s = ns.EUISettings()
    s.accentPink = v and true or false
    s.accent = nil
end

-- Half one: the colour. This snapshot holds a TABLE, not a scalar, so it cannot
-- go through ns.EUIOverride and ns.EUIRestore, which write a single key.
local function ApplyAccentColor(claiming)
    local on = AccentEnabled()
    local saved
    if on and claiming then
        saved = ns.EUISnap("accent", "color")
    else
        saved = ns.EUIPeekSnap("accent", "color")
    end
    if not saved then return end

    local EUI = _G.EllesmereUI
    if not EUI then return end
    local profile = EUI.GetActiveProfileData and EUI.GetActiveProfileData()
    if type(profile) ~= "table" then return end

    if on then
        -- Record once, by value. SetActiveProfileAccent replaces the custom
        -- table rather than mutating it, so the reference stays valid.
        --
        -- Same claim rule as ns.EUIOverride, spelled out again because this
        -- record-once is inline: a note may only be created by a user action, so
        -- an unclaimed re-apply with no note writes nothing at all.
        if saved.prev == nil then
            if not claiming then return end
            local current = profile.euiAccent
            if current == nil then
                saved.prev = ns.EUI_ABSENT
            else
                saved.prev = { custom = current.custom, useClass = current.useClass }
            end
        end
        if EUI.SetAccentColor then
            EUI.SetAccentColor(AccentColor())
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
local function ApplyAccentScope(claiming)
    local on = AccentEnabled()
    local saved
    if on and claiming then
        saved = ns.EUISnap("accent", "scope")
    else
        saved = ns.EUIPeekSnap("accent", "scope")
    end
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
                -- Written this way and not `entry.value or false`, because a
                -- recorded value of false is a real forced value, not an absence.
                local forced = entry.value
                if forced == nil then forced = false end
                ns.EUIOverride(target, saved.keys[slot], entry.key, forced, claiming)
            else
                ns.EUIRestore(target, saved.keys[slot], entry.key)
            end
            refreshed[entry.refresh] = true
        end
    end

    -- The popup and menu element colour lives on the EllesmereUIDB ROOT, so its
    -- snapshot must NOT be profile-keyed. Filed under one profile it would be
    -- invisible from every other, leaving the forced value with nothing to
    -- restore it.
    --
    -- It follows the claim anyway, even though a root key cannot arrive unowned
    -- by being copied. An accent switch that is unowned for its profile-keyed
    -- half must not be owning for this one: turning it off would then restore
    -- here and not there, which is a half-restore.
    if _G.EllesmereUIDB then
        local popup
        if on and claiming then
            popup = ns.EUISnapGlobal("popupMenuButtonTextColorMode")
        else
            popup = ns.EUIPeekSnapGlobal("popupMenuButtonTextColorMode")
        end
        if popup then
            if on then
                ns.EUIOverride(EllesmereUIDB, popup, "popupMenuButtonTextColorMode", "native", claiming)
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
local function ApplyAccent(claiming)
    ApplyAccentColor(claiming)
    ApplyAccentScope(claiming)
end

-- The two colour setters. NEITHER CLAIMS, and the false each passes is the whole
-- reason they are functions rather than inline setValues.
--
-- The note recording what the user's accent was before KitnUI touched it belongs
-- to the master switch and is created once, by it. Passing true from here would
-- let a colour change re-record KitnUI's own forced colour as the user's original,
-- and turning the master off would then hand back KitnUI's colour instead of
-- theirs. Neither of these touches ns.EUIOverride, ns.EUISnap or the scoping.
--
-- Consequence worth knowing: while the master reads ON but KitnUI is not actually
-- holding the accent -- the copied-profile state the ownership tooltip warns about
-- -- ApplyAccentColor finds no note and writes nothing, so these appear to do
-- nothing until the user toggles the master off and on again. That is the same
-- answer the tooltip already gives, so it is not a second surprise.

local function SetAccentUsesDefault(v)
    ns.EUISettings().accentUseDefault = v and true or false
    ApplyAccentColor(false)
end

local function SetAccentCustom(r, g, b)
    local s = ns.EUISettings()
    -- Replace the whole table, never write into it. See the DEFAULTS comment in
    -- Core.lua: an in-place write into a table-valued default is the one shape
    -- that does not survive a logout here.
    s.accentCustom = { r = r, g = g, b = b }
    -- Picking a colour is how a user says they want it, so it turns the pink row
    -- off as well. EllesmereUI's own trio swatch does exactly this
    -- (EllesmereUI_Widgets.lua:2645-2655 calls setMode("custom") from setValue).
    -- The pink is not lost: it is a literal, and the row above puts it back.
    s.accentUseDefault = false
    ApplyAccentColor(false)
end

-- Wrapped rather than registered bare. A bare registration would hand the
-- registry's own arguments straight through as the claim, so the day the
-- registry starts passing one, every re-apply silently becomes a claim.
ns.EUIRegisterReapply(function() ApplyAccent(false) end)

---------------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------------

ns.EUIPages["General"] = function(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    -- The header carries the current look because the widget factory has no
    -- label row. SectionHeader passes its text through EllesmereUI.L, and a
    -- composed string is not in the localisation table, so it comes back
    -- unchanged.
    local lookHeader
    lookHeader, h = W:SectionHeader(parent, "APPEARANCE (" .. LookStateText() .. ")", y)
                                                                                   y = y - h

    -- EllesmereUI caches a built page and re-shows the same wrapper rather than
    -- running the builder again, so a look changed from EllesmereUI's own
    -- options would leave this header naming the abandoned look until a reload.
    -- Showing the wrapper fires OnShow on its children, which is the one moment
    -- the page is guaranteed back on screen. Hooked, not set, so a handler
    -- EllesmereUI adds later still runs.
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
        function()
            if not ns.LuluEnabled then return false end
            return ns.LuluEnabled()
        end,
        function(v) if ns.SetLuluMode then ns.SetLuluMode(v) end end,
        -- No rebuild call here, deliberately. This setter only raises a
        -- confirmation popup; the real change happens in that popup's OnAccept,
        -- which reloads the whole UI (Lulu.lua). A rebuild here would fire before
        -- the user has confirmed, and one in OnAccept would run a line before the
        -- reload throws it away.
        ns.EUIOwnershipTip(
            "Round minimap, Blizzard's own action bars, and a dedicated Edit Mode layout. Asks first, then reloads.",
            "lulu",
            function() return ns.LuluEnabled and ns.LuluEnabled() end,
            "your minimap shape and where its clock, zone, FPS, mail, difficulty and button row sit"));
                                                                                   y = y - h

    _, h = W:Spacer(parent, y, 20);                                                y = y - h
    _, h = W:SectionHeader(parent, "ACCENT", y);                                   y = y - h

    _, h = W:Toggle(parent, "KitnUI Pink Accent", y,
        AccentEnabled,
        function(v)
            SetAccentEnabled(v)
            ApplyAccent(true)
            -- The claim is complete, so the ownership sentence can be recomputed.
            ns.EUIRebuildForOwnership()
        end,
        ns.EUIOwnershipTip(
            "Sets EllesmereUI's accent to KitnUI pink for this profile, puts it on the quest tracker header, and stops it tinting the tracker's divider lines, the Mythic+ timer, the damage meter and the Friends tab.",
            "accent",
            AccentEnabled,
            "EllesmereUI's accent colour"));
                                                                                   y = y - h

    return math.abs(y)
end
