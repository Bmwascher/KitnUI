-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-bite-gap.lua                                            ║
-- ║  Purpose: Gate for Bite Mode's buff offset hold: what it     ║
-- ║           claims, what the panel's show and close do to it,  ║
-- ║           and what it gives back.                            ║
-- ║           Loads the SHIPPED code, never a copy.              ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/eui-bite-gap.lua

local failures = 0
local checks = 0
local say = print

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        say("FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
    end
end

local function eq(actual, expected, label)
    check(actual == expected, label, "got " .. tostring(actual) .. ", wanted " .. tostring(expected))
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = copy(x) end
    return c
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

---------------------------------------------------------------------------------
-- Stubs: KitnUI's namespace, the game, and the EllesmereUI calls Bite.lua makes
---------------------------------------------------------------------------------

local core = { title = "KitnUI", profileName = "KitnUI", data = {} }
for _, file in ipairs({ "Installer/Merge.lua", "Installer/ModuleRows.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        say("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI", core)
end
_G.KitnUI_Shared = core

local combat = false
_G.InCombatLockdown = function() return combat end
_G.UnitGUID = function() return "Player-1-1" end

-- Post-hooks are kept by function name, so a case can run them as the host's
-- call returns.
local hooks = {}
_G.hooksecurefunc = function(_, name, fn)
    hooks[name] = hooks[name] or {}
    local list = hooks[name]
    list[#list + 1] = fn
end

-- Frames are kept so a case can fire the end of a fight at whatever watcher
-- registered for it.
local frames = {}
_G.CreateFrame = function()
    local f = { events = {}, scripts = {} }
    function f.RegisterEvent(self, event) self.events[event] = true end
    function f.RegisterUnitEvent() end
    function f.UnregisterEvent(self, event) self.events[event] = nil end
    function f.SetScript(self, name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = f
    return f
end

local function fireRegen()
    for i = 1, #frames do
        local f = frames[i]
        if f.events.PLAYER_REGEN_ENABLED and f.scripts.OnEvent then
            f.scripts.OnEvent(f, "PLAYER_REGEN_ENABLED")
        end
    end
end

-- Timers queue, so a pass queued by the panel's close runs after the host's
-- own hide work, as it does in the game.
local timers = {}
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

local function runTimers()
    while #timers > 0 do
        local fn = table.remove(timers, 1)
        fn()
    end
end

local said = {}
_G.print = function(msg) said[#said + 1] = tostring(msg) end

local CDM = "EllesmereUICooldownManager"
local function F(i) return CDM .. "\031cdmBars\030bars\030" .. i .. "\030addOffsetY" end
local B3, B6 = F(3), F(6)

-- floating, zero, anchored, and the two bars without a usable key: each is
-- captured, so only its own guard keeps it out of the hold.
local NEGATIVE = { 5, 7, 8, 9, 10 }

local registry = { folder = CDM }

-- A settings database with a real ResetProfile, so the reset cases run the
-- shipped ns.EUIResetAll rather than a stand-in for it.
local function NewDB()
    local db = { profile = {} }
    function db.ResetProfile(self)
        for k in pairs(self.profile) do self.profile[k] = nil end
    end
    return db
end

local EUI = { Lite = { _dbRegistry = { registry }, NewDB = NewDB }, SPECOV_NIL = "__nil__" }
_G.EllesmereUI = EUI
local state = { view = false, session = false, layer = nil, repaints = 0, profile = "KitnUI" }
local prof, bars, anchors, baseline

EUI.GetActiveProfileName = function() return state.profile end
EUI.SwitchProfile = function() end
EUI.DeleteProfile = function() end
EUI.GetActiveProfileData = function() return prof end
EUI.SpecOverrides_UnlockActive = function() return state.layer end
EUI.SpecOverrides_EditSessionActive = function() return state.session end
EUI.SpecOverrides_ViewActive = function() return state.view end
EUI.ReapplyAllUnlockAnchors = function() state.repaints = state.repaints + 1 end
EUI.RefreshPage = function() end

-- The host's bar-delete sweep: every entry capturing any bar setting goes, in
-- both stores.
local BAR_PREFIX = CDM .. "\031cdmBars\030bars\030"
EUI.SpecOverrides_OnCDMBarsRestructured = function()
    for _, store in ipairs({ prof.specOverrides, prof.condOverrides }) do
        for i = #store, 1, -1 do
            for fkey in pairs(store[i].values.default) do
                if fkey:sub(1, #BAR_PREFIX) == BAR_PREFIX then
                    table.remove(store, i)
                    break
                end
            end
        end
    end
end

-- The panel: its two callback lists and its frame.
local panel = { shown = false, onShow = {}, onHide = {} }
EUI.RegisterOnShow = function(_, fn) panel.onShow[#panel.onShow + 1] = fn end
EUI.RegisterOnHide = function(_, fn) panel.onHide[#panel.onHide + 1] = fn end
_G.EllesmereUIFrame = { IsVisible = function() return panel.shown end }

-- What the host's apply puts live for the current spec: its own map, else the
-- shared default.
local function SpecValue(entry, fkey)
    local m = entry.values[EUI._specID] or entry.values.default
    local v = m[fkey]
    if v == nil then v = entry.values.default[fkey] end
    return v
end

-- The host's resolver: the spec store's values, then the applied condition's
-- values on every key no spec entry captures.
local APPLIED_COND = 1
EUI.SpecOverrides_PeekEffectiveValues = function(folder)
    local out = {}
    local function inFolder(fkey) return fkey:sub(1, #folder + 1) == folder .. "\031" end
    for _, entry in ipairs(prof.specOverrides) do
        for fkey in pairs(entry.values.default) do
            if inFolder(fkey) then out[fkey] = SpecValue(entry, fkey) end
        end
    end
    for _, entry in ipairs(prof.condOverrides) do
        local map = entry.values[APPLIED_COND]
        for fkey, def in pairs(entry.values.default) do
            if inFolder(fkey) and out[fkey] == nil then
                local v = map and map[fkey]
                if v == nil then v = def end
                out[fkey] = v
            end
        end
    end
    return out
end

-- Live as the host's apply leaves it: the shared defaults while the Default
-- view is up, otherwise the current spec's values. Every entry is applied in
-- turn, so the last entry capturing a key wins, as in the host.
local function HostApplies()
    for i, bar in ipairs(bars) do
        local fkey = F(i)
        for _, entry in ipairs(prof.specOverrides) do
            if entry.values.default[fkey] ~= nil then
                bar.addOffsetY = state.view and entry.values.default[fkey] or SpecValue(entry, fkey)
            end
        end
    end
end

-- The host entering the Default view banks live into the current spec's own
-- maps first.
local function HarvestCurrent()
    for i, bar in ipairs(bars) do
        local fkey = F(i)
        for _, entry in ipairs(prof.specOverrides) do
            local own = entry.values[EUI._specID]
            if own and own[fkey] ~= nil and bar.addOffsetY ~= nil then own[fkey] = bar.addOffsetY end
        end
    end
end

-- Leaving it banks live into the shared defaults.
local function HarvestDefaults()
    for i, bar in ipairs(bars) do
        local fkey = F(i)
        for _, entry in ipairs(prof.specOverrides) do
            if entry.values.default[fkey] ~= nil and bar.addOffsetY ~= nil then
                entry.values.default[fkey] = bar.addOffsetY
            end
        end
    end
end

local ns = {}
for _, file in ipairs({ "KitnUI_EUI/Core.lua", "KitnUI_EUI/Bite.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        say("FAIL  could not load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("KitnUI_EUI", ns)
end

check(type(ns.SetBiteMode) == "function", "ns.SetBiteMode is defined")
check(type(ns.EUIPeekNotes) == "function", "ns.EUIPeekNotes is defined")
if failures > 0 then
    say(string.format("%d checks, %d failures", checks, failures))
    os.exit(1)
end

---------------------------------------------------------------------------------
-- Fixture: ten bars, two spec-store entries for buffs, one for the negative
-- bars, and a conditional entry. The two buffs entries carry the same maps, as
-- the migration that builds duplicates copies them.
---------------------------------------------------------------------------------

local BAD_KEY = "bad\031key"

local function NegativeMap()
    local map = {}
    for _, i in ipairs(NEGATIVE) do map[F(i)] = (i == 7) and 0 or 21 end
    return map
end

local function fire(list)
    for i = 1, #list do list[i]() end
end

-- One profile's EllesmereUI data, made current. KitnUI's notes are left alone.
local function build()
    bars = {
        { key = "cooldowns" },
        { key = "utility" },
        { key = "buffs", addOffsetY = 21 },
        { key = "custom_10", addOffsetY = 21 },
        { key = "floating", addOffsetY = 21 },
        { key = "condbar", addOffsetY = 21 },
        { key = "zero", addOffsetY = 0 },
        { key = "anchored", anchorTo = "buffs", addOffsetY = 21 },
        { key = BAD_KEY, addOffsetY = 21 },
        { addOffsetY = 21 },
    }
    registry.profile = { cdmBars = { bars = bars } }
    anchors = {
        ERB_Power         = { target = "CDM_cooldowns", side = "TOP", offsetX = 0, offsetY = 0 },
        ERB_ClassResource = { target = "ERB_Power", side = "TOP", offsetX = 0, offsetY = 0 },
        ERB_CastBar       = { target = "CDM_utility", side = "BOTTOM", offsetX = 0, offsetY = -1 },
        TBBG_g4           = { target = "ERB_ClassResource", side = "TOP", offsetX = 0, offsetY = 0 },
        CDM_buffs         = { target = "TBBG_g4", side = "TOP", offsetX = 0, offsetY = 1 },
        CDM_custom_10     = { target = "TBBG_g4", side = "TOP", offsetX = 0, offsetY = 36 },
        CDM_floating      = { target = "SCREEN_TOP", side = "BOTTOM", offsetX = 0, offsetY = 0 },
        CDM_condbar       = { target = "TBBG_g4", side = "TOP", offsetX = -96, offsetY = 38 },
        CDM_zero          = { target = "TBBG_g4", side = "TOP", offsetX = 96, offsetY = 38 },
        ["CDM_" .. BAD_KEY] = { target = "TBBG_g4", side = "TOP", offsetX = 0, offsetY = 74 },
    }
    _G.EllesmereUIDB = { unlockAnchors = anchors }
    prof = {
        specOverrideGroups = { { id = 4, specs = { 264 } }, { id = 13, specs = { 262, 63 } } },
        unlockOverrideAnchors = {
            ERB_CastBar = { [13] = { target = "ERB_ClassResource", side = "TOP", offsetX = 0, offsetY = 1 } },
        },
        specOverrides = {
            { values = { default = { [B3] = 21 }, [262] = { [B3] = 21 }, [63] = { [B3] = 21 }, [264] = { [B3] = 25 } } },
            { values = { default = { [B3] = 21 }, [262] = { [B3] = 21 }, [63] = { [B3] = 21 }, [264] = { [B3] = 25 } } },
            { values = { default = NegativeMap(), [262] = NegativeMap(), [63] = NegativeMap() } },
        },
        condOverrides = {
            { values = { default = { [B6] = 21, [B3] = 21 }, [1] = { [B3] = 21 } } },
        },
    }
    baseline = { defaults = {}, cond = copy(prof.condOverrides) }
    for i, entry in ipairs(prof.specOverrides) do baseline.defaults[i] = copy(entry.values.default) end
end

local function fresh()
    -- A case that ended with the panel open closes it first, so the switch's
    -- own flag starts closed, and every queued pass runs before the reset.
    combat = false
    state.session = false
    if panel.shown then
        panel.shown = false
        fire(panel.onHide)
    end
    runTimers()

    state.profile = "KitnUI"
    build()
    core.db = {}
    EUI._specID = 262
    state.view, state.layer, state.repaints = false, nil, 0
    said = {}
    local settings = ns.EUISettings()
    for k in pairs(settings) do settings[k] = nil end
end

local function A(spec) return prof.specOverrides[1].values[spec][B3] end
local function Bv(spec) return prof.specOverrides[2].values[spec][B3] end

local function notes()
    local root = core.db.euiSnap
    local sect = root and root.bite
    return sect and sect[state.profile] or {}
end

local function held(key)
    local record = notes()[key]
    return record and record.prev
end

local function buffNotes()
    local n = 0
    for key, record in pairs(notes()) do
        if key:sub(1, 11) == "buffOffset\031" and record.prev ~= nil then n = n + 1 end
    end
    return n
end

local function untouched(label)
    for i, entry in ipairs(prof.specOverrides) do
        check(same(entry.values.default, baseline.defaults[i]), label .. ": default map " .. i .. " unchanged")
    end
    check(same(prof.condOverrides, baseline.cond), label .. ": conditional store unchanged")
end

-- The starting copies follow a store change the test itself makes as the host,
-- so untouched() goes on checking only KitnUI's writes.
local function rebase()
    baseline.defaults = {}
    for i, entry in ipairs(prof.specOverrides) do baseline.defaults[i] = copy(entry.values.default) end
    baseline.cond = copy(prof.condOverrides)
end

-- The host's delete flow: the bar goes, then the sweep runs.
local function deleteBar(i)
    table.remove(bars, i)
    EUI.SpecOverrides_OnCDMBarsRestructured()
    rebase()
end

local function reapply()
    ns.EUIQueueReapply()
    runTimers()
end

-- The panel's OnShow runs the callbacks at once; a frame later the host banks
-- live into the current spec's own maps and shows the shared defaults.
local function openPanel()
    panel.shown = true
    fire(panel.onShow)
    HarvestCurrent()
    state.view = true
    HostApplies()
end

-- The callbacks fire first. The host's hide work then leaves the Default view
-- if it is up, banking live into the defaults, and applies the spec's values,
-- and Core's own hide callback queues its pass. The queued passes run later.
local function hideWork()
    panel.shown = false
    fire(panel.onHide)
    if state.view then HarvestDefaults() end
    state.view = false
    HostApplies()
    ns.EUIQueueReapplyOutOfCombat()
end

local function closePanel()
    hideWork()
    runTimers()
end

-- A force close can hide the panel and show it again before the queued pass runs.
local function flashPanel()
    hideWork()
    openPanel()
    runTimers()
end

local function current()
    return { prof = prof, bars = bars, anchors = anchors, baseline = baseline }
end

local function useProfile(name, data)
    state.profile = name
    prof, bars, anchors, baseline = data.prof, data.bars, data.anchors, data.baseline
    registry.profile = { cdmBars = { bars = bars } }
    _G.EllesmereUIDB = { unlockAnchors = anchors }
end

-- The host's switch: it leaves the Default view and banks live against the
-- outgoing profile, swaps the stores, and its post-hooks run as it returns.
local function switchTo(name, data)
    if state.view then
        HarvestDefaults()
        state.view = false
        HostApplies()
    end
    HarvestCurrent()
    useProfile(name, data)
    fire(hooks.SwitchProfile or {})
end

-- The click as the player makes it: inside the open panel, which then closes.
local function clickOn()
    openPanel()
    ns.SetBiteMode(true)
    closePanel()
end

local REC_262 = "buffOffset\031buffs\031262"
local REC_63 = "buffOffset\031buffs\03163"
local REC_264 = "buffOffset\031buffs\031264"
local REC_DEFAULT = "buffOffset\031buffs\031default"

-- Run right after a claim on 262 has been held with the panel closed, so a
-- case that tests a later step cannot pass without the hold.
local function claimed(label)
    eq(A(262), 0, label .. ": precondition: spec 262's map is held")
    eq(held(REC_262), 21, label .. ": precondition: spec 262's record holds 21")
    eq(bars[3].addOffsetY, 0, label .. ": precondition: the held value is live")
end

local function negativesKept(label)
    local entry = prof.specOverrides[3]
    for _, i in ipairs(NEGATIVE) do
        local want = (i == 7) and 0 or 21
        eq(entry.values[262][F(i)], want, label .. ": bar " .. i .. "'s spec 262 map is not written")
        eq(entry.values[63][F(i)], want, label .. ": bar " .. i .. "'s spec 63 map is not written")
        eq(bars[i].addOffsetY, want, label .. ": bar " .. i .. "'s live value is not written")
    end
    eq(bars[4].addOffsetY, 21, label .. ": the uncaptured bar is not written")
    eq(bars[6].addOffsetY, 21, label .. ": the conditional-only bar is not written")
end
---------------------------------------------------------------------------------
-- U: saved holds after a reload into a panel whose show list cannot register.
-- It runs first, while nothing is registered yet.
---------------------------------------------------------------------------------

fresh()
for _, entry in ipairs({ prof.specOverrides[1], prof.specOverrides[2] }) do
    entry.values[262][B3] = 0
    entry.values[63][B3] = 0
end
bars[3].addOffsetY = 0
core.db.euiSnap = { bite = { KitnUI = {
    [REC_262] = { prev = 21, forced = 0, fkey = B3 },
    [REC_63] = { prev = 21, forced = 0, fkey = B3 },
} } }
ns.EUISettings().bite = true
eq(ns.BiteEnabled(), true, "U: precondition: the saved switch is on")
local registerOnShow = EUI.RegisterOnShow
EUI.RegisterOnShow = function() error("unavailable") end
reapply()
EUI.RegisterOnShow = registerOnShow
eq(#panel.onShow, 0, "U: precondition: no show callback is registered")
eq(A(262), 21, "U: with no show callback the saved hold is given back")
eq(Bv(262), 21, "U: in the duplicate entry too")
eq(A(63), 21, "U: and on every held spec")
eq(bars[3].addOffsetY, 21, "U: live too")
eq(held(REC_262), nil, "U: the records are released")
eq(#panel.onHide, 1, "U: the hide list that did register is registered once")
reapply()
eq(#panel.onHide, 1, "U: and is not registered again")
untouched("U")

-- The same, with the Cooldown Manager's data unavailable: the release still
-- runs, at each record's own fkey.
fresh()
for _, entry in ipairs({ prof.specOverrides[1], prof.specOverrides[2] }) do
    entry.values[262][B3] = 0
    entry.values[63][B3] = 0
end
core.db.euiSnap = { bite = { KitnUI = {
    [REC_262] = { prev = 21, forced = 0, fkey = B3 },
    [REC_63] = { prev = 21, forced = 0, fkey = B3 },
} } }
ns.EUISettings().bite = true
registry.profile = nil
EUI.RegisterOnShow = function() error("unavailable") end
reapply()
EUI.RegisterOnShow = registerOnShow
eq(#panel.onShow, 0, "U2: precondition: no show callback is registered")
eq(A(262), 21, "U2: with no live bar data the saved hold is still given back")
eq(Bv(262), 21, "U2: in the duplicate entry too")
eq(A(63), 21, "U2: and on every held spec")
eq(held(REC_262), nil, "U2: the records are released")
untouched("U2")

---------------------------------------------------------------------------------
-- A: the click inside the open panel, then the close
---------------------------------------------------------------------------------

fresh()
openPanel()
ns.SetBiteMode(true)
eq(ns.BiteEnabled(), true, "A: the switch is on")
eq(held(REC_262), 21, "A: spec 262's record holds its own value")
eq(held(REC_63), 21, "A: spec 63's record holds its own value")
eq(buffNotes(), 2, "A: records exist for spec 262 and spec 63 only")
eq(notes()[REC_264], nil, "A: no record for a non-swap spec")
eq(notes()[REC_DEFAULT], nil, "A: no record for the default slot")
eq(A(262), 21, "A: inside the open panel no map is written")
eq(Bv(262), 21, "A: nor the duplicate entry")
eq(bars[3].addOffsetY, 21, "A: nor live")
untouched("A in the panel")
closePanel()
eq(A(262), 0, "A: the close holds spec 262 in the first entry")
eq(Bv(262), 0, "A: and in the duplicate entry")
eq(A(63), 0, "A: the close holds spec 63")
eq(A(264), 25, "A: a non-swap spec's map is not written")
eq(bars[3].addOffsetY, 0, "A: the held value is live")
check(state.repaints > 0, "A: the anchors are repainted")
negativesKept("A")
eq(buffNotes(), 2, "A: still only the two records")
untouched("A")

---------------------------------------------------------------------------------
-- B: a claim with the panel closed, a spec change, and a live layer
---------------------------------------------------------------------------------

fresh()
ns.SetBiteMode(true)
eq(A(262), 0, "B: a claim with the panel closed holds at once")
eq(bars[3].addOffsetY, 0, "B: the held value is live")
negativesKept("B")

EUI._specID = 264
HostApplies()
reapply()
eq(bars[3].addOffsetY, 25, "B: a non-swap spec keeps its own captured value")
eq(A(262), 0, "B: the swap specs' maps stay held on a non-swap spec")

EUI._specID = 262
HostApplies()
reapply()
eq(bars[3].addOffsetY, 0, "B: back on a swap spec the held value is live")

state.layer = 4
reapply()
eq(bars[3].addOffsetY, 21, "B: with a layer live the bar shows the spec's own value")
eq(A(262), 0, "B: with a layer live the map stays held")
eq(held(REC_262), 21, "B: with a layer live the record is kept")
state.layer = nil
untouched("B")

---------------------------------------------------------------------------------
-- C: the release with the panel closed
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("C")
prof.specOverrides[1].values[63][B3] = 30
ns.SetBiteMode(false)
eq(ns.BiteEnabled(), false, "C: the switch is off")
eq(A(262), 21, "C: spec 262 is given back in the first entry")
eq(Bv(262), 21, "C: spec 262 is given back in the duplicate entry")
eq(A(63), 30, "C: a map the user changed keeps their value")
eq(bars[3].addOffsetY, 21, "C: live takes the value the host would apply")
eq(held(REC_262), nil, "C: spec 262's record is released")
eq(held(REC_63), nil, "C: spec 63's record is released")
eq(ns.EUIHolds("bite"), false, "C: nothing is held after the release")
untouched("C")

---------------------------------------------------------------------------------
-- D: the OFF click inside the open panel
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("D")
openPanel()
ns.SetBiteMode(false)
eq(A(262), 21, "D: the maps already carry the original")
eq(held(REC_262), nil, "D: the records are cleared")
closePanel()
eq(A(262), 21, "D: the close holds nothing")
eq(bars[3].addOffsetY, 21, "D: after the close live is the spec's own value")
eq(ns.EUIHolds("bite"), false, "D: nothing is held after the release")
untouched("D")

---------------------------------------------------------------------------------
-- E: the panel's show puts the original back before the host's harvest
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("E")
local repaintsE = state.repaints
openPanel()
check(state.repaints > repaintsE, "E: the show repaints the bars, which the host's view write no longer does")
eq(A(262), 21, "E: spec 262 has its value back, and the harvest banked 21, not 0")
eq(Bv(262), 21, "E: so has the duplicate entry")
eq(A(63), 21, "E: so has spec 63")
eq(held(REC_262), 21, "E: the record is kept")
eq(bars[3].addOffsetY, 21, "E: the panel shows the shared default")
untouched("E open")
closePanel()
eq(A(262), 0, "E: the close holds again")
eq(bars[3].addOffsetY, 0, "E: and live is 0")
untouched("E")

-- In combat the show puts the value back at once; the close's pass waits.
fresh()
clickOn()
claimed("E2")
combat = true
local repaintsE2 = state.repaints
openPanel()
eq(A(262), 21, "E2: in combat the show puts the value back at once")
eq(state.repaints, repaintsE2, "E2: and does not repaint in combat")
hideWork()
runTimers()
eq(A(262), 21, "E2: a close in combat holds nothing until the fight ends")
combat = false
fireRegen()
eq(state.repaints, repaintsE2, "E2: after a close in combat the show's repaint does not run first")
runTimers()
eq(A(262), 0, "E2: the end of the fight holds again")
eq(bars[3].addOffsetY, 0, "E2: and live is 0")
check(state.repaints > repaintsE2, "E2: and the pass repaints")
untouched("E2")

-- Opened in combat and still open when the fight ends: the show's repaint runs.
fresh()
clickOn()
claimed("E3")
combat = true
local repaintsE3 = state.repaints
openPanel()
eq(state.repaints, repaintsE3, "E3: no repaint in combat")
combat = false
fireRegen()
check(state.repaints > repaintsE3, "E3: the show's repaint runs when the fight ends")
eq(A(262), 21, "E3: the maps keep the original for the open panel")
untouched("E3")

---------------------------------------------------------------------------------
-- F: a value the player sets in the open panel is theirs
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("F")
openPanel()
prof.specOverrides[1].values[262][B3] = 5
prof.specOverrides[2].values[262][B3] = 5
closePanel()
eq(A(262), 5, "F: the player's value is kept at the close")
eq(Bv(262), 5, "F: in both entries")
eq(held(REC_262), nil, "F: and that slot is let go")
eq(A(63), 0, "F: the other slot is held again")
eq(bars[3].addOffsetY, 5, "F: live is the player's value")
ns.SetBiteMode(false)
eq(A(262), 5, "F: the release leaves the player's value")
eq(A(63), 21, "F: and gives the other slot back")
untouched("F")

---------------------------------------------------------------------------------
-- V: a value the player sets in one copy of a slot lets the whole slot go
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("V")
openPanel()
prof.specOverrides[1].values[262][B3] = 0
closePanel()
eq(A(262), 0, "V: the player's 0 is kept")
eq(Bv(262), 21, "V: the other copy is not forced")
eq(held(REC_262), nil, "V: the whole slot is let go")
eq(A(63), 0, "V: the other slot is held again")
check(ns.EUIResetAll() ~= false, "V: the reset runs")
eq(A(262), 0, "V: the release leaves the player's 0")
eq(Bv(262), 21, "V: and the other copy's value")
eq(A(63), 21, "V: and gives the other slot back")
untouched("V")

---------------------------------------------------------------------------------
-- G: copies of a slot that disagree refuse the claim before any write
---------------------------------------------------------------------------------

fresh()
prof.specOverrides[2].values[262][B3] = 30
ns.SetBiteMode(true)
eq(ns.BiteEnabled(), false, "G: the switch stays off")
check(said[#said] and said[#said]:find("two different saved values", 1, true), "G: the refusal is printed", said[#said])
eq(A(262), 21, "G: the first entry is not written")
eq(Bv(262), 30, "G: the duplicate entry is not written")
eq(anchors.ERB_Power.target, "CDM_cooldowns", "G: the anchors did not move")
eq(core.db.euiSnap and core.db.euiSnap.bite, nil, "G: no record was made")
untouched("G")

---------------------------------------------------------------------------------
-- H: an editing session
---------------------------------------------------------------------------------

fresh()
ns.SetBiteMode(true)
claimed("H")
state.session = true
bars[3].addOffsetY = 21
reapply()
eq(bars[3].addOffsetY, 21, "H: nothing is written while an editing session is open")
state.session = false
reapply()
eq(bars[3].addOffsetY, 0, "H: the next re-apply catches up")
untouched("H")

---------------------------------------------------------------------------------
-- I: the shipped reset, with the panel closed and with it open
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("I")
check(ns.EUIResetAll() ~= false, "I: the reset runs")
eq(ns.BiteEnabled(), false, "I: the reset turned the switch off")
eq(A(262), 21, "I: the reset gives the maps back")
eq(Bv(262), 21, "I: the reset gives the duplicate entry back")
eq(bars[3].addOffsetY, 21, "I: the reset gives the held bar's live value back")
eq(ns.EUIHolds("bite"), false, "I: no record is left for the reset to discard")
untouched("I")

fresh()
clickOn()
claimed("I2")
openPanel()
check(ns.EUIResetAll() ~= false, "I2: the reset runs with the panel open")
eq(A(262), 21, "I2: the maps keep the original")
eq(ns.EUIHolds("bite"), false, "I2: no record is left")
closePanel()
eq(A(262), 21, "I2: the close holds nothing")
eq(bars[3].addOffsetY, 21, "I2: live is the spec's own value")
untouched("I2")

---------------------------------------------------------------------------------
-- J: a click made in combat is refused, and nothing runs when the fight ends
---------------------------------------------------------------------------------

fresh()
combat = true
ns.SetBiteMode(true)
local refused = said[#said]
check(refused and refused:find("Bite Mode cannot be changed in combat", 1, true), "J: the refusal is printed", refused)
eq(ns.BiteEnabled(), false, "J: the switch is still off in combat")
eq(A(262), 21, "J: no map is written in combat")
eq(bars[3].addOffsetY, 21, "J: no live value is written in combat")
combat = false
fireRegen()
runTimers()
eq(ns.BiteEnabled(), false, "J: nothing was queued for the end of the fight")
eq(A(262), 21, "J: the map is still not written")
eq(core.db.euiSnap and core.db.euiSnap.bite, nil, "J: no record was made")
untouched("J")

fresh()
combat = true
ns.SetDarkCastBar(true)
refused = said[#said]
check(refused and refused:find("Dark Cast Bar cannot be changed in combat", 1, true), "J2: the refusal is printed", refused)
eq(ns.DarkCastBarEnabled(), false, "J2: Dark Cast Bar stays off in combat")
combat = false
fireRegen()
runTimers()
eq(ns.DarkCastBarEnabled(), false, "J2: nothing was queued for the end of the fight")

---------------------------------------------------------------------------------
-- X: the first smoke run of 2026-10-17. The panel opened in combat from the Top
-- Bar clock, and Bite Mode was clicked off, then on, before the fight ended. The
-- toggle's click is setValue(not getValue()), so with the clicks queued both
-- sent off, and the fight's end turned Bite Mode off and released every record.
-- Refused in combat, both clicks leave the hold as it was.
---------------------------------------------------------------------------------

local function toggleClick() ns.SetBiteMode(not ns.BiteEnabled()) end

for _, closeFirst in ipairs({ true, false }) do
    local label = closeFirst and "X close, then the fight ends" or "X the fight ends, then close"
    fresh()
    clickOn()
    claimed(label)
    combat = true
    openPanel()
    toggleClick()
    toggleClick()
    if closeFirst then
        hideWork()
        runTimers()
        combat = false
        fireRegen()
        runTimers()
    else
        combat = false
        fireRegen()
        runTimers()
        closePanel()
    end
    EUI._specID = 264
    HostApplies()
    reapply()
    EUI._specID = 262
    HostApplies()
    reapply()
    eq(ns.BiteEnabled(), true, label .. ": Bite Mode is still on")
    eq(held(REC_262), 21, label .. ": spec 262's record still holds 21")
    eq(held(REC_63), 21, label .. ": so does spec 63's")
    eq(A(262), 0, label .. ": spec 262's map is held")
    eq(bars[3].addOffsetY, 0, label .. ": and live is 0")
    untouched(label)
end

---------------------------------------------------------------------------------
-- K: the reset with the Cooldown Manager's data gone
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("K")
eq(A(63), 0, "K: precondition: spec 63's map is held")
registry.profile = nil
check(ns.EUIResetAll() ~= false, "K: the reset runs")
eq(A(262), 21, "K: the maps are given back at the recorded fkey")
eq(Bv(262), 21, "K: the duplicate entry is given back")
eq(A(63), 21, "K: every held spec is given back")
eq(held(REC_262), nil, "K: the map record is released")
eq(ns.EUIHolds("bite"), false, "K: no record is left for the reset to discard")
untouched("K")

---------------------------------------------------------------------------------
-- L: an uncaptured bar captured in the open panel seeds the player's value
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("L")
openPanel()
-- The host seeds a new capture's default from live as the session saw it.
local F4 = F(4)
local capturedL = { values = { default = { [F4] = bars[4].addOffsetY }, [262] = { [F4] = 5 } } }
prof.specOverrides[#prof.specOverrides + 1] = capturedL
rebase()
eq(capturedL.values.default[F4], 21, "L: the new default is the player's own value")
closePanel()
eq(bars[4].addOffsetY, 5, "L: a bar captured after the click is not held")
eq(capturedL.values[262][F4], 5, "L: its map is not written")
ns.SetBiteMode(false)
eq(bars[4].addOffsetY, 5, "L: the release leaves the captured value")
eq(A(262), 21, "L: the held bar is still given back")
untouched("L")

---------------------------------------------------------------------------------
-- M: a spec added to the swap group after the click
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("M")
local swapGroup = prof.specOverrideGroups[2].specs
swapGroup[#swapGroup + 1] = 70
prof.specOverrides[1].values[70] = { [B3] = 9 }
prof.specOverrides[2].values[70] = { [B3] = 9 }
EUI._specID = 70
HostApplies()
reapply()
eq(A(70), 9, "M: the re-apply does not write the new member's map")
eq(bars[3].addOffsetY, 9, "M: the new member's live value is its own")
ns.SetBiteMode(false)
eq(A(70), 9, "M: the release does not write the new member's map")
eq(Bv(70), 9, "M: nor its duplicate")
eq(notes()["buffOffset\031buffs\03170"], nil, "M: no record is made for the new member")
eq(A(262), 21, "M: the original swap spec is still given back")
untouched("M")

---------------------------------------------------------------------------------
-- N: Remove Override in the open panel, then a new capture
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("N")
openPanel()
-- The player removes both buffs captures and makes a new one: 0 for spec 262,
-- the original for spec 63.
local negativesN = prof.specOverrides[3]
prof.specOverrides = {
    { values = { default = { [B3] = 21 }, [262] = { [B3] = 0 }, [63] = { [B3] = 21 } } },
    negativesN,
}
rebase()
closePanel()
eq(A(262), 0, "N: the player's new 0 is kept")
eq(held(REC_262), nil, "N: and that slot is let go")
eq(A(63), 0, "N: a new capture at exactly the original is held again")
ns.SetBiteMode(false)
eq(A(262), 0, "N: the release leaves the player's 0")
eq(A(63), 21, "N: and gives that original back")
untouched("N")

---------------------------------------------------------------------------------
-- O: the conditional store takes the bar over in the open panel
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("O")
openPanel()
local negativesO = prof.specOverrides[3]
prof.specOverrides = { negativesO }
prof.condOverrides[1].values.default[B3] = bars[3].addOffsetY
rebase()
eq(prof.condOverrides[1].values.default[B3], 21, "O: the conditional store sees the original, not 0")
closePanel()
eq(buffNotes(), 0, "O: the records are cleared")
eq(bars[3].addOffsetY, 21, "O: live is not written")
ns.SetBiteMode(false)
eq(bars[3].addOffsetY, 21, "O: nor at the release")
eq(ns.EUIHolds("bite"), false, "O: nothing is held after the release")
untouched("O")

-- The same takeover, released before the close's pass runs, over a live 0 this
-- switch did not write: the applied condition's value must not replace it.
fresh()
clickOn()
claimed("O2")
openPanel()
local negativesO2 = prof.specOverrides[3]
prof.specOverrides = { negativesO2 }
prof.condOverrides[1].values[APPLIED_COND][B3] = 30
rebase()
hideWork()
bars[3].addOffsetY = 0
check(ns.EUIResetAll() ~= false, "O2: the reset runs")
eq(bars[3].addOffsetY, 0, "O2: the release writes no conditional value into live")
eq(buffNotes(), 0, "O2: the records are cleared")
runTimers()
untouched("O2")

---------------------------------------------------------------------------------
-- P: a bar delete in the open panel
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("P")
openPanel()
deleteBar(1)
eq(bars[2].key, "buffs", "P: the fixture moved buffs to index 2")
eq(bars[2].addOffsetY, 21, "P: live carries the original, not 0, after the delete")
closePanel()
eq(buffNotes(), 0, "P: the close clears the records")
eq(bars[2].addOffsetY, 21, "P: the gap returns")
eq(ns.BiteEnabled(), true, "P: the switch stays on")
untouched("P")

-- The same delete, then a new capture of the bar at its new index, holding 0.
fresh()
clickOn()
claimed("P2")
openPanel()
deleteBar(1)
local F2 = F(2)
local recaptured = { values = { default = { [F2] = 21 }, [262] = { [F2] = 0 }, [63] = { [F2] = 0 } } }
prof.specOverrides[1] = recaptured
rebase()
closePanel()
eq(recaptured.values[262][F2], 0, "P2: the new capture is not held over")
eq(buffNotes(), 0, "P2: no record holds it")
ns.SetBiteMode(false)
eq(recaptured.values[262][F2], 0, "P2: the release does not restore it")
eq(recaptured.values[63][F2], 0, "P2: nor its other spec")
untouched("P2")

---------------------------------------------------------------------------------
-- Q: a swap spec with no map of its own
---------------------------------------------------------------------------------

fresh()
prof.specOverrides[1].values[63] = nil
prof.specOverrides[2].values[63] = nil
clickOn()
eq(A(262), 0, "Q: the swap spec with its own map is held")
eq(notes()[REC_63], nil, "Q: no record for a swap spec without a map of its own")
eq(prof.specOverrides[1].values[63], nil, "Q: no map is made for it")
EUI._specID = 63
HostApplies()
reapply()
eq(bars[3].addOffsetY, 21, "Q: on that spec live is the shared default")
untouched("Q")

---------------------------------------------------------------------------------
-- R: a force-close flash
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("R")
openPanel()
flashPanel()
eq(A(262), 21, "R: the pass a flash queued holds nothing under the reopened panel")
eq(held(REC_262), 21, "R: the record is kept")
closePanel()
eq(A(262), 0, "R: the real close holds again")
untouched("R")

---------------------------------------------------------------------------------
-- S: a spec change with the panel open
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("S")
openPanel()
EUI._specID = 264
HostApplies()
reapply()
eq(A(262), 21, "S: a spec change with the panel open writes nothing")
closePanel()
eq(A(262), 0, "S: the close holds again")
eq(bars[3].addOffsetY, 25, "S: on the non-swap spec live is its own value")
untouched("S")

---------------------------------------------------------------------------------
-- T: a switch inside the open panel to a profile whose holds are in place
---------------------------------------------------------------------------------

fresh()
local home = current()
state.profile = "Alt"
build()
clickOn()
claimed("T")
local alt = current()
useProfile("KitnUI", home)
HostApplies()
openPanel()
switchTo("Alt", alt)
eq(A(262), 21, "T: the switch itself puts the incoming maps back")
eq(Bv(262), 21, "T: in both entries")
eq(A(63), 21, "T: on every held spec")
eq(bars[3].addOffsetY, 21, "T: and live")
eq(held(REC_262), 21, "T: the record is kept")
closePanel()
eq(A(262), 0, "T: the close holds the incoming profile again")
eq(bars[3].addOffsetY, 0, "T: and live is 0")
untouched("T")

---------------------------------------------------------------------------------
-- W: after the last hold is released, the callbacks and hooks do no work, and
-- the panel flag stays current
---------------------------------------------------------------------------------

fresh()
clickOn()
claimed("W")
check(ns.EUIResetAll() ~= false, "W: the reset runs")
eq(ns.EUIHolds("bite"), false, "W: precondition: nothing is held")

-- A show, a switch post-hook and a hide, counting the note walks and the
-- re-apply queue calls they make.
local function panelWork()
    local peeks, queues = 0, 0
    local peekNotes, queueOut = ns.EUIPeekNotes, ns.EUIQueueReapplyOutOfCombat
    ns.EUIPeekNotes = function(...)
        peeks = peeks + 1
        return peekNotes(...)
    end
    ns.EUIQueueReapplyOutOfCombat = function(...)
        queues = queues + 1
        return queueOut(...)
    end
    openPanel()
    fire(hooks.SwitchProfile or {})
    panel.shown = false
    fire(panel.onHide)
    ns.EUIPeekNotes, ns.EUIQueueReapplyOutOfCombat = peekNotes, queueOut
    return peeks, queues
end

local peeks, queues = panelWork()
eq(peeks, 0, "W: with nothing held the show and the switch hook walk no notes")
eq(queues, 0, "W: and Bite's hide callback queues no re-apply of its own")
openPanel()
ns.SetBiteMode(true)
eq(A(262), 21, "W: the flag stayed current: a click inside the open panel writes nothing")
closePanel()
eq(A(262), 0, "W: and the close holds")
untouched("W")

-- The last holds sit in another profile, which is deleted while Bite Mode is
-- off in the active one: Core drops its notes and queues a pass, as its
-- profile-delete handler does.
fresh()
local homeW = current()
state.profile = "Alt"
build()
clickOn()
claimed("W2")
useProfile("KitnUI", homeW)
HostApplies()
ns.EUISettings().bite = false
eq(ns.BiteEnabled(), false, "W2: precondition: Bite Mode is off in the active profile")
core.db.euiSnap.bite.Alt = nil
reapply()
peeks, queues = panelWork()
eq(peeks, 0, "W2: after the delete the show and the switch hook walk no notes")
eq(queues, 0, "W2: and Bite's hide callback queues no re-apply of its own")
untouched("W2")

say(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
