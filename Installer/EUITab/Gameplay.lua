-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab/Gameplay.lua                                         ║
-- ║  Purpose: The Gameplay page: Beginner Mode, and two combat   ║
-- ║           tooltip switches.                                  ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

local CDM = "EllesmereUICooldownManager"
local ACTION_BARS = "EllesmereUIActionBars"

-- The two action bars Beginner Mode holds visible. Not every bar: a beginner
-- needs their main rotation bars readable, and forcing all eight would fight
-- whatever layout the profile installed.
local AB_KEYS = { "MainBar", "Bar2" }

-- Written to every non-buff bar. showTooltip is deliberately NOT in here; it
-- goes to every bar including buff bars, because an aura has no keybind but a
-- beginner most wants to know what a buff icon IS.
local CDM_KEYBIND = {
    showKeybind    = true,
    pressMirror    = true,
    keybindSize    = 12,
    keybindOffsetX = -1,
    keybindOffsetY = 0,
}

-- Iterated rather than pairs()'d wherever order would otherwise vary, so a
-- snapshot record set is built the same way twice.
local CDM_KEYBIND_ORDER = {
    "showKeybind", "pressMirror", "keybindSize", "keybindOffsetX", "keybindOffsetY",
}

function ns.BeginnerEnabled()
    local s = ns.EUISettings()
    return s and s.beginner and true or false
end

---------------------------------------------------------------------------------
-- Combat deferral
---------------------------------------------------------------------------------

-- Deferred rather than refused. The two appearance refusals in General.lua give
-- their reason as the write landing while the repaint does not, which argues for
-- deferring as long as BOTH defer together. Nothing about Beginner Mode needs the
-- user standing there.
--
-- It cannot simply run under lockdown either: barVisibility feeds secure
-- visibility drivers, and _EAB_Apply half applies in combat rather than failing.
-- ApplyAll reads InCombatLockdown once and gates the enable/disable pass, the
-- layout, the borders and the shapes behind it, but ApplyFontsForBar sits outside
-- that gate and is what applies hideKeybind. So a combat call repaints the
-- keybind text while the visibility work is skipped, silently.
local pending
local combatWatcher

-- Returns true when it ran now, false when it deferred, so the caller can decide
-- whether anyone needs telling. The helper never prints: the re-apply path shares
-- it and has nobody to tell.
local function RunOutOfCombat(fn)
    if not InCombatLockdown() then
        fn()
        return true
    end

    -- One slot, not a queue: a second toggle during the same fight replaces the
    -- first, and only the final state should apply. One reused frame, because a
    -- frame per call leaks one per toggle.
    pending = fn
    if not combatWatcher then
        combatWatcher = CreateFrame("Frame")
        combatWatcher:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local run = pending
            pending = nil
            if run then run() end
        end)
    end
    combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    return false
end

---------------------------------------------------------------------------------
-- Which bars get the treatment
---------------------------------------------------------------------------------

-- EllesmereUI's own predicate, replicated because IsBarBuffFamily and
-- ResolveBarType are both module-local. The live field wins and the key is only a
-- fallback for profiles written before barType existed, which is the order
-- EllesmereUI resolves them in. A bar whose type resolves to nil is NOT a buff
-- bar, so it gets the treatment, matching what EllesmereUI's own callers do.
--
-- custom_buff is folded in because EllesmereUI folds it in: its own migration
-- rewrites those bars to "buffs" once per profile. Reading the pre-migration
-- docstring instead would put keybinds on aura icons in the window before that
-- migration runs.
local function IsBuffBar(bar)
    if type(bar) ~= "table" then return false end
    if bar.key == "__ghost_cd" then return false end
    if bar.barType then
        return bar.barType == "buffs" or bar.barType == "custom_buff"
    end
    return bar.key == "buffs"
end

-- The ghost bar is an internal routing sink with no icons, and EllesmereUI skips
-- it everywhere it walks the bar list. Six writes into it would be inert and six
-- snapshot records would be noise.
--
-- This is a DIFFERENT test from the one inside IsBuffBar. That one excludes
-- __ghost_cd by key BEFORE resolving a type, which makes the ghost bar report
-- "not a buff bar" and would hand it the treatment. Both are needed.
local function SkipBar(bar)
    if type(bar) ~= "table" then return true end
    return bar.isGhostBar and true or false
end

-- Bars are user-editable and nothing guarantees a key, so a nil one would error
-- on the concatenation below. The index is stable enough for a snapshot record.
local function BarSnapKey(bar, i, settingKey)
    local key = bar.key
    if type(key) ~= "string" or key == "" then key = "#" .. i end
    -- \31 is the separator EllesmereUI uses for its own composite keys.
    return key .. "\31" .. settingKey
end

---------------------------------------------------------------------------------
-- Cooldown Manager
---------------------------------------------------------------------------------

local function CdmBars()
    local profile = ns.EUIProfile(CDM)
    local bars = profile and profile.cdmBars and profile.cdmBars.bars
    if type(bars) ~= "table" then return nil end
    return bars
end

local function ApplyOne(bar, saved, key, value, on)
    if not saved then return end
    if on then
        ns.EUIOverride(bar, saved, key, value)
    else
        ns.EUIRestore(bar, saved, key)
    end
end

local function ApplyCdm(on)
    local bars = CdmBars()
    if not bars then return end

    -- The two skip rules gate WRITES only. Turning the switch off walks every bar
    -- and every key unconditionally, because a bar can change type or become a
    -- ghost while the switch is on: gating the restore the same way would leave
    -- that bar's forced values stranded with its snapshot silently unread.
    -- ns.EUIRestore is a no-op when nothing was recorded, so the extra passes on
    -- bars we never wrote cost nothing.
    for i = 1, #bars do
        local bar = bars[i]
        local write = on and not SkipBar(bar)
        if write or (not on and type(bar) == "table") then
            local snapKey = BarSnapKey(bar, i, "showTooltip")
            local saved = write and ns.EUISnap("beginner", snapKey)
                                or ns.EUIPeekSnap("beginner", snapKey)
            ApplyOne(bar, saved, "showTooltip", true, on)

            if not on or not IsBuffBar(bar) then
                for _, key in ipairs(CDM_KEYBIND_ORDER) do
                    local k = BarSnapKey(bar, i, key)
                    local rec = write and ns.EUISnap("beginner", k)
                                      or ns.EUIPeekSnap("beginner", k)
                    ApplyOne(bar, rec, key, CDM_KEYBIND[key], on)
                end
            end
        end
    end

    -- EllesmereUI's own spec-override system names this function as the module's
    -- refresh, so it is the same entry point EllesmereUI uses when it rewrites
    -- these same keys.
    if _G._ECME_Apply then pcall(_G._ECME_Apply) end
end

---------------------------------------------------------------------------------
-- Action Bars
---------------------------------------------------------------------------------

-- The visibility mode is six fields, not one. ApplyMode sets barVisibility and
-- then alwaysHidden, mouseoverEnabled, combatHideEnabled, combatShowEnabled, and
-- juggles mouseoverAlpha against a saved copy. A direct write on a mouseover bar
-- leaves mouseoverEnabled true and mouseoverAlpha at 0, so the bar stays INVISIBLE
-- while the setting reads "always".
local function VisibilityCompat()
    local eab = ns.EUIAddon(ACTION_BARS)
    local VC = eab and eab.VisibilityCompat
    if type(VC) ~= "table" then return nil end
    if type(VC.ApplyMode) ~= "function" or type(VC.Normalize) ~= "function" then
        return nil
    end
    return VC
end

-- barVisibility uses the snapshot STORE but NOT ns.EUIOverride or ns.EUIRestore,
-- because those write tbl[key] directly and that is the defect above. The
-- record-once guard lives INSIDE ns.EUIOverride, so skipping the helper means
-- re-implementing the guard here: without it the login re-apply would snapshot
-- our own forced "always" over the user's real mode and the switch would become
-- unrestorable.
--
-- ns.EUI_ABSENT is not needed on this path. Normalize never returns nil; it
-- returns "always" for a settings table with nothing set.
local function ApplyVisibility(settings, saved, VC, on)
    if not saved then return end
    if on then
        if saved.prev == nil then saved.prev = VC.Normalize(settings) end
        VC.ApplyMode(settings, "always")
    elseif saved.prev ~= nil then
        VC.ApplyMode(settings, saved.prev)
        saved.prev = nil
    end
end

local function ApplyActionBars(on)
    local profile = ns.EUIProfile(ACTION_BARS)
    local bars = profile and profile.bars
    -- Nil while Lulu Mode is on, which disables this addon outright so Blizzard's
    -- own bars are on screen. Correct: Blizzard's bars carry their own keybind
    -- text setting, and the Cooldown Manager half still applies.
    if type(bars) ~= "table" then return end

    local VC = VisibilityCompat()

    for _, key in ipairs(AB_KEYS) do
        local settings = bars[key]
        if type(settings) == "table" then
            local hideRec = on and ns.EUISnap("beginner", key .. "\31hideKeybind")
                               or ns.EUIPeekSnap("beginner", key .. "\31hideKeybind")
            ApplyOne(settings, hideRec, "hideKeybind", false, on)

            local visRec = on and ns.EUISnap("beginner", key .. "\31barVisibility")
                              or ns.EUIPeekSnap("beginner", key .. "\31barVisibility")
            if VC then
                ApplyVisibility(settings, visRec, VC, on)
            else
                -- No compat layer means no companion fields to keep in step, so
                -- both are plain values and the ordinary trio is correct: it
                -- supplies the record-once guard and the EUI_ABSENT handling for a
                -- profile that never set barVisibility at all, which is the exact
                -- shape this branch exists for.
                --
                -- Known incomplete: the legacy alwaysHidden, combatHideEnabled and
                -- combatShowEnabled flags are not touched, so a bar carrying one
                -- would stay hidden. Chasing them would mean reimplementing
                -- ApplyMode for a version nobody runs.
                ApplyOne(settings, visRec, "barVisibility", "always", on)

                local moRec = on and ns.EUISnap("beginner", key .. "\31mouseoverEnabled")
                                 or ns.EUIPeekSnap("beginner", key .. "\31mouseoverEnabled")
                ApplyOne(settings, moRec, "mouseoverEnabled", false, on)
            end
        end
    end

    if _G._EAB_Apply then pcall(_G._EAB_Apply) end
end

local function ApplyBeginner(on)
    ApplyCdm(on)
    ApplyActionBars(on)
end

local function SetBeginnerMode(on)
    local s = ns.EUISettings()
    if not s then return end
    s.beginner = on and true or nil

    if not RunOutOfCombat(function() ApplyBeginner(ns.BeginnerEnabled()) end) then
        print(ns.title .. ": Beginner Mode applies when you leave combat.")
    end
end

-- Re-read inside the closure rather than captured, because a fight can outlast
-- the user's interest and what applies afterwards has to be the state that is
-- true then. Sharing RunOutOfCombat with the toggle also shares its one pending
-- slot, so a profile switch mid-fight supersedes a toggle made earlier in that
-- same fight and the last state wins.
ns.EUIRegisterReapply(function()
    RunOutOfCombat(function() ApplyBeginner(ns.BeginnerEnabled()) end)
end)

---------------------------------------------------------------------------------
-- Combat tooltips
---------------------------------------------------------------------------------

-- EllesmereUI only reparents its OWN icons under ECME_CDMBar_<key>; Blizzard's
-- real cooldown icons stay under the *CooldownViewer frames, because EllesmereUI's
-- taint rules forbid reparenting a Blizzard frame. Both have to be recognised or
-- the switch misses the cooldowns it is named for.
--
-- Comparing frame identity against _ECME_GetBarFrame instead cannot work: the
-- Blizzard icons are re-anchored and never reparented, so their parent chain
-- never reaches a bar frame.
local CDM_PREFIX, CDM_PREFIX_LEN = "ECME_CDMBar_", 12

local function OwnedByCooldownBar(tooltip)
    local frame = tooltip.GetOwner and tooltip:GetOwner()
    -- Bounded: an unbounded walk up a cyclic or very deep hierarchy would run on
    -- every tooltip in combat.
    for _ = 1, 8 do
        if not frame then return false end
        local name = frame.GetName and frame:GetName()
        if name then
            if name:sub(1, CDM_PREFIX_LEN) == CDM_PREFIX then return true end
            -- Essential / Utility / BuffIcon / BuffBar CooldownViewer.
            if name:find("CooldownViewer", 1, true) then return true end
        end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end

-- One hook, installed once, that reads the two switches every time rather than
-- being installed and removed with them. A hook cannot be unhooked in this API,
-- so installing on demand would leave a dead one behind after the first toggle.
--
-- Hide() inside OnShow is unprotected, so this is safe under combat lockdown.
local function InstallTooltipHook()
    local tip = _G.GameTooltip
    if not (tip and tip.HookScript) then return end
    tip:HookScript("OnShow", function(self)
        if not InCombatLockdown() then return end
        local s = ns.EUISettings()
        if not s then return end
        if s.hideAllTooltipsInCombat then self:Hide() return end
        if s.hideCdmTooltipsInCombat and OwnedByCooldownBar(self) then self:Hide() end
    end)
end

-- Its own login frame, not the page builder and not Core.lua's boot frame.
-- buildPage runs lazily on first panel open, so installing there would leave
-- suppression dead after every reload until the user opened the panel; Core's
-- boot frame returns early when EllesmereUI is missing, and this hook has no
-- EllesmereUI dependency. Login rather than file scope because the handler reads
-- ns.EUISettings, which needs ns.db.
local tooltipBoot = CreateFrame("Frame")
tooltipBoot:RegisterEvent("PLAYER_LOGIN")
tooltipBoot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    InstallTooltipHook()
end)

---------------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------------

ns.EUIPages["Gameplay"] = function(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "BEGINNER MODE", y);                            y = y - h

    _, h = W:Toggle(parent, "Beginner Mode", y,
        function() return ns.BeginnerEnabled() end,
        function(v) SetBeginnerMode(v) end,
        "Shows tooltips, keybinds and key-press highlights on the Cooldown Manager, and keeps Action Bars 1 and 2 always visible. Applies when you leave combat.");
                                                                                   y = y - h

    _, h = W:Spacer(parent, y, 20);                                                y = y - h
    _, h = W:SectionHeader(parent, "TOOLTIPS", y);                                 y = y - h

    _, h = W:Toggle(parent, "Hide All Tooltips In Combat", y,
        function() local s = ns.EUISettings() return s and s.hideAllTooltipsInCombat and true or false end,
        function(v)
            local s = ns.EUISettings()
            if s then s.hideAllTooltipsInCombat = v and true or nil end
        end,
        "Hides every tooltip while you are in combat. EllesmereUI has its own combat tooltip setting with a peek key; KitnUI's is a plain hide, so running both gives you the stricter one.");
                                                                                   y = y - h

    _, h = W:Toggle(parent, "Hide Cooldown Tooltips In Combat", y,
        function() local s = ns.EUISettings() return s and s.hideCdmTooltipsInCombat and true or false end,
        function(v)
            local s = ns.EUISettings()
            if s then s.hideCdmTooltipsInCombat = v and true or nil end
        end,
        "Hides only Cooldown Manager tooltips while you are in combat, leaving action bar and unit frame tooltips alone.");
                                                                                   y = y - h

    return math.abs(y)
end
