-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/Gameplay.lua                                     ║
-- ║  Purpose: The Gameplay page: Beginner Mode, and two combat   ║
-- ║           tooltip switches.                                  ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- Core.lua sets this and stops when KitnUI's shared namespace is unreachable, so
-- ns has no title, no db and no data. Everything below needs all three.
if ns.EUI_INERT then return end

local CDM = "EllesmereUICooldownManager"
local ACTION_BARS = "EllesmereUIActionBars"

-- The action bars Beginner Mode holds visible. Kitn's call, 2026-08-07: bars 1,
-- 2, 3 and 5 are the ones KitnUI's own layout puts on screen. Not every bar,
-- because forcing all eight would reveal bars the profile deliberately hides.
--
-- Keys, not numbers: EllesmereUI's registry names bar 1 "MainBar" and the rest
-- "Bar<n>" (EllesmereUIActionBars.lua:180-186), so bar 5 is "Bar5" and there is
-- no "Bar1".
local AB_KEYS = { "MainBar", "Bar2", "Bar3", "Bar5" }

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
            local saved
            if write then
                saved = ns.EUISnap("beginner", snapKey)
            else
                saved = ns.EUIPeekSnap("beginner", snapKey)
            end
            ApplyOne(bar, saved, "showTooltip", true, on)

            if not on or not IsBuffBar(bar) then
                for _, key in ipairs(CDM_KEYBIND_ORDER) do
                    local k = BarSnapKey(bar, i, key)
                    local rec
                    if write then
                        rec = ns.EUISnap("beginner", k)
                    else
                        rec = ns.EUIPeekSnap("beginner", k)
                    end
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

-- THE one rule for undoing a visibility override, shared by all three call sites
-- so they cannot drift apart. `expand` rewrites the whole six-field model from a
-- mode: the module's own ApplyMode where it is reachable, the ported copy where
-- it is not, and nil where neither applies.
--
-- Two records must NEVER be expanded, and telling them apart is what `saved.plain`
-- exists for. A record the no-compat writer made describes barVisibility ALONE,
-- because that writer changes that one key and leaves the companion fields as the
-- user had them; expanding it would write five fields nobody recorded, over
-- values the user still owns, and mouseoverEnabled true would silently become
-- false. The sentinel is not a mode at all.
--
-- The marker is on the LEGACY writer rather than the compat one on purpose:
-- unmarked therefore means "a mode", which is what every record written so far
-- is, so no existing snapshot is misread.
local function RestoreVisibility(settings, saved, expand)
    if not saved or saved.prev == nil then return end
    if saved.plain or saved.prev == ns.EUI_ABSENT or not expand then
        ns.EUIRestore(settings, saved, "barVisibility")
        return
    end
    expand(settings, saved.prev)
    saved.prev = nil
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
        if saved.prev == nil then
            saved.prev = VC.Normalize(settings)
            -- A mode, so drop any marker a previous no-compat session left on this
            -- same record table. Record tables are reused, never recreated.
            saved.plain = nil
        end
        VC.ApplyMode(settings, "always")
    else
        RestoreVisibility(settings, saved, VC.ApplyMode)
    end
end

-- VisibilityCompat.ApplyMode, ported field for field from
-- References/EllesmereUI-v8.7.5/EllesmereUIActionBars/EllesmereUIActionBars.lua:270-292,
-- for the one case where the live one cannot be reached: the module is switched
-- off, so it is not loaded, while the values KitnUI forced are still in its saved
-- settings and still have to come back out. Writing the mode string on its own
-- there would leave a mouseover bar at alpha 0 and mouseoverEnabled true, so the
-- bar reads "always" and stays invisible.
--
-- Duplicated logic, and the reason it is worth it: this is a pure rewrite of six
-- fields on a table the caller hands in, with no addon state behind it, and the
-- alternative is a restore that cannot happen at all. It drifts if EllesmereUI
-- changes the field set, which is why the live layer is still preferred wherever
-- it exists and this runs nowhere else.
local function ApplyModeStored(settings, mode)
    if not settings then return end

    mode = mode or "always"
    settings.barVisibility = mode
    settings.alwaysHidden = (mode == "never")

    local wasMouseover = settings.mouseoverEnabled
    settings.mouseoverEnabled = (mode == "mouseover")
    if mode == "mouseover" then
        if not settings._savedBarAlpha then
            settings._savedBarAlpha = settings.mouseoverAlpha or 1
        end
        settings.mouseoverAlpha = 0
    elseif wasMouseover and settings._savedBarAlpha then
        settings.mouseoverAlpha = settings._savedBarAlpha
        settings._savedBarAlpha = nil
    end

    settings.combatHideEnabled = (mode == "out_of_combat")
    settings.combatShowEnabled = (mode == "in_combat")
end

-- The OFF path for a module that is not loaded, kept entirely separate from the
-- live one because the table it works on is not the same kind of table.
--
-- EllesmereUI writes a DEFAULTS-STRIPPED copy of every loaded module's profile at
-- logout: any value equal to its registered default is deleted, and a sub-table
-- that empties out under a string key is deleted with it
-- (References/EllesmereUI-v8.7.5/EllesmereUI/EllesmereUI_Lite.lua:193-205, written
-- back at :363-375). Beginner Mode forces barVisibility "always" and hideKeybind
-- false, and those ARE this module's defaults
-- (References/EllesmereUI-v8.7.5/EllesmereUIActionBars/EllesmereUIActionBars.lua:527-539),
-- so the very reload that Lulu Mode triggers can strip the bar table KitnUI wrote
-- into, and `bars` along with it. Treating a missing container as nothing to do
-- would silently skip the restore in exactly the case this function exists for
-- and let the following /kitn reset delete the only record of the originals.
--
-- So containers are rebuilt, but only where a snapshot says this bar was actually
-- held down. Building one for a bar with no record would invent settings the user
-- never had; DeepMergeDefaults fills the rest in when the module next loads.
-- A snapshot record that is CURRENTLY holding a value down, as opposed to one
-- that merely exists. ns.EUIRestore clears .prev and deliberately leaves the
-- record table behind (KitnUI_EUI/Core.lua:299-311), and ns.EUISnap reuses it
-- (:234-241), so a bar Beginner Mode held down and released in some earlier
-- session still has truthy record tables with nothing in them. Reading existence
-- as activity would rebuild containers for a bar that needs nothing.
local function ActiveSnap(key)
    local rec = ns.EUIPeekSnap("beginner", key)
    if rec and rec.prev ~= nil then return rec end
    return nil
end

-- Reached whenever the live lookup fails, which is normally because Lulu Mode
-- switched the module off. It is also correct in the rarer case where the module
-- IS loaded and only the lookup failed, on an EllesmereUI with neither GetAddon
-- nor an exposed _dbRegistry: ns.EUIStoredProfile returns the very table NewDB
-- handed that module (References/EllesmereUI-v8.7.5/EllesmereUI/EllesmereUI_Lite.lua:268-273),
-- so the write still lands on the live settings even there.
local function RestoreStoredActionBars()
    local profile = ns.EUIStoredProfile(ACTION_BARS)
    if not profile then return end

    for _, key in ipairs(AB_KEYS) do
        local hideRec = ActiveSnap(key .. "\31hideKeybind")
        local visRec  = ActiveSnap(key .. "\31barVisibility")

        if hideRec or visRec then
            if type(profile.bars) ~= "table" then profile.bars = {} end
            local settings = profile.bars[key]
            if type(settings) ~= "table" then
                settings = {}
                profile.bars[key] = settings
            end

            ApplyOne(settings, hideRec, "hideKeybind", false, false)

            RestoreVisibility(settings, visRec, ApplyModeStored)
        end
    end

    -- The module is normally unloaded here, so this is normally absent. It is not
    -- always: an ordinary Beginner Mode toggle restores immediately without a
    -- reload, and on an EllesmereUI whose live lookup fails while the module is
    -- loaded this path runs with the frames on screen. Skipping the repaint there
    -- would leave the bars wearing Beginner Mode's look with the switch reading
    -- off (References/EllesmereUI-v8.7.5/EllesmereUIActionBars/EllesmereUIActionBars.lua:12422).
    if _G._EAB_Apply then pcall(_G._EAB_Apply) end
end

local function ApplyActionBars(on)
    -- The live profile is the only route that can apply a change without a
    -- reload, so it is always preferred. Lulu Mode switches this module off,
    -- which is what makes the lookup fail, and the OFF path still owes the user
    -- their settings back: /kitn reset deletes the snapshots immediately
    -- afterwards and nothing else remembers what the originals were.
    --
    -- The ON path has no such fallback and keeps the early return. Forcing values
    -- into a module the user has switched off changes nothing they can see;
    -- Blizzard's own bars are on screen there and carry their own keybind text
    -- setting, and the Cooldown Manager half still applies either way.
    local profile = ns.EUIProfile(ACTION_BARS)
    if not profile then
        if not on then RestoreStoredActionBars() end
        return
    end

    local bars = profile.bars
    if type(bars) ~= "table" then return end

    local VC = VisibilityCompat()

    for _, key in ipairs(AB_KEYS) do
        local settings = bars[key]
        if type(settings) == "table" then
            local hideRec
            if on then
                hideRec = ns.EUISnap("beginner", key .. "\31hideKeybind")
            else
                hideRec = ns.EUIPeekSnap("beginner", key .. "\31hideKeybind")
            end
            ApplyOne(settings, hideRec, "hideKeybind", false, on)

            local visRec
            if on then
                visRec = ns.EUISnap("beginner", key .. "\31barVisibility")
            else
                visRec = ns.EUIPeekSnap("beginner", key .. "\31barVisibility")
            end

            if VC then
                ApplyVisibility(settings, visRec, VC, on)
            elseif on then
                -- ONE record for visibility, exactly as the compat branch keeps
                -- one, because two records for one setting is what several rounds
                -- of review kept breaking on: nothing said which writer made a
                -- record, so every restore had to guess.
                --
                -- Known incomplete, and the cost of that choice: with no compat
                -- layer the companion fields are not touched, so a bar the user had
                -- on mouseover keeps mouseoverEnabled true and mouseoverAlpha 0 and
                -- stays invisible while Beginner Mode reads "always". That is a
                -- cosmetic fault on a version of EllesmereUI that has to predate
                -- VisibilityCompat, and it is strictly better than the alternative,
                -- which was overwriting a setting and destroying the record of it.
                -- Restoring puts the recorded mode back and the bar behaves again.
                --
                -- The marker is what keeps that promise: it tells the restore this
                -- record covers barVisibility alone, so the companion fields this
                -- branch left alone stay left alone.
                if visRec and visRec.prev == nil then visRec.plain = true end
                ApplyOne(settings, visRec, "barVisibility", "always", on)
            else
                RestoreVisibility(settings, visRec, nil)
            end
        end
    end

    if _G._EAB_Apply then pcall(_G._EAB_Apply) end
end

local function ApplyBeginner(on)
    ApplyCdm(on)
    ApplyActionBars(on)
end

-- Off is stored as an explicit false, never by deleting the key. Under the
-- registered defaults in KitnUI_EUI/Core.lua an absent key means "restore me to
-- the default", so a deleted key would come back ON after a reload, and
-- EllesmereUI's spec-override engine would separately bank the absence as a
-- removal marker. Every switch in this addon follows the same rule.
local function SetBeginnerMode(on)
    local s = ns.EUISettings()
    if not s then return end
    s.beginner = on and true or false

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
        "Shows tooltips, keybinds and key-press highlights on the Cooldown Manager, and keeps Action Bars 1, 2, 3 and 5 always visible.");
                                                                                   y = y - h

    _, h = W:Spacer(parent, y, 20);                                                y = y - h
    _, h = W:SectionHeader(parent, "TOOLTIPS", y);                                 y = y - h

    _, h = W:Toggle(parent, "Hide All Tooltips In Combat", y,
        function() local s = ns.EUISettings() return s and s.hideAllTooltipsInCombat and true or false end,
        function(v)
            local s = ns.EUISettings()
            if s then s.hideAllTooltipsInCombat = v and true or false end
        end,
        "Hides every tooltip while you are in combat. EllesmereUI has its own combat tooltip setting with a peek key; KitnUI's is a plain hide, so running both gives you the stricter one.");
                                                                                   y = y - h

    _, h = W:Toggle(parent, "Hide Cooldown Tooltips In Combat", y,
        function() local s = ns.EUISettings() return s and s.hideCdmTooltipsInCombat and true or false end,
        function(v)
            local s = ns.EUISettings()
            if s then s.hideCdmTooltipsInCombat = v and true or false end
        end,
        "Hides only Cooldown Manager tooltips while you are in combat, leaving action bar and unit frame tooltips alone.");
                                                                                   y = y - h

    return math.abs(y)
end
