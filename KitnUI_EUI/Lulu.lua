-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/Lulu.lua                                         ║
-- ║  Purpose: Lulu Mode: round minimap, Blizzard action bars,    ║
-- ║           and a dedicated Edit Mode layout, as one switch.   ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- Core.lua sets this and stops when KitnUI's shared namespace is unreachable, so
-- ns has no title, no db and no data. Everything below needs all three.
if ns.EUI_INERT then return end

local ACTION_BARS = "EllesmereUIActionBars"

-- BOTH of Lulu's records are per character, because both of the things they
-- describe are: an addon's enable state is per character, and so is which Edit
-- Mode layout is ACTIVE (the definitions are account-wide, but Blizzard builds
-- the list for the current player).
--
-- One shared record would let an alt undo with a layout it never had, and let
-- whichever character undid first take the record away from every other.
--
-- The key is the player GUID, the same value Blizzard's own addon-list selector
-- passes to these functions.
local function LuluCharacter()
    if not UnitGUID then return nil end
    local guid = UnitGUID("player")
    if type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

local function LuluSnapKey(name, guid)
    return name .. ":" .. guid
end

function ns.LuluEnabled()
    local s = ns.EUISettings()
    return s.lulu and true or false
end

ns.LuluLayoutName = function()
    return ns.profileName .. " Lulu"
end

-- Every EllesmereUI minimap key Lulu Mode holds down, and the value it holds it
-- at. A round minimap moves nothing on its own: the clock, the zone text, the
-- FPS/MS readout, the mail icon, the difficulty text and the button row are all
-- anchored for a square and sit wrong the moment the corners go. Each one is a
-- separate key in the same table, so each is a separate note and each comes back
-- on its own.
--
-- `snap` is the name of the note, and it is NOT always the key. `shape` shipped
-- alone under the name "minimapShape", and every user who has Lulu Mode on right
-- now has their original shape recorded under that name. Renaming the note would
-- orphan theirs: the off path would find no record, restore nothing, and leave
-- them a circle with no way back through the switch. So `shape` keeps the name it
-- has always had and everything added since is named after its own key.
--
-- ONE CONTROL PER KEY is the standing rule in ns.EUIOverride, and this table is
-- the whole of Lulu's claim. Nothing else in KitnUI HOLDS DOWN any of these
-- eighteen. The profile install writes them once through EllesmereUI's own
-- importer and takes no note, which is a write and not a claim.
--
-- The values were tuned in game against a round minimap. The positions are the
-- host's own names, from MAP_POS_VALUES, ROW_POS_VALUES and the mail dropdown in
-- EllesmereUIOptions/EUI_Minimap_Options.lua; the mail corners are UPPERCASE
-- there and the map positions are not, which is the host's casing, not a slip.
-- dev/tests/lulu-minimap-keys.lua checks every one of them against those lists.
local MINIMAP_KEYS = {
    { key = "shape",            snap = "minimapShape", value = "circle" },

    { key = "clockPosition",    value = "bottom" },
    { key = "clockOffsetX",     value = 0 },
    { key = "clockOffsetY",     value = 18 },

    { key = "locationPosition", value = "top" },
    { key = "locationOffsetX",  value = 0 },
    { key = "locationOffsetY",  value = -10 },

    { key = "fpsPosition",      value = "bottom" },
    { key = "fpsOffsetX",       value = 0 },
    { key = "fpsOffsetY",       value = 8 },

    { key = "mailPosition",     value = "TOPRIGHT" },
    { key = "mailOffsetX",      value = -30 },
    { key = "mailOffsetY",      value = -35 },

    { key = "diffTextPosition", value = "topLeft" },
    { key = "diffTextOffsetX",  value = 30 },
    { key = "diffTextOffsetY",  value = -38 },

    { key = "btnRowPosition",   value = "brLeft" },
    { key = "btnRowDistance",   value = 35 },
}

-- Reachable only so dev/tests/lulu-minimap-keys.lua can load this file as a chunk
-- and check the table it actually ships. It is NOT in KitnUI_EUI/Core.lua's
-- EXPORTS list, so it stays invisible to KitnUI itself.
ns.LuluMinimapKeys = MINIMAP_KEYS

-- The minimap is the only part of Lulu Mode that applies without a reload, so it
-- is the only part that snapshots. The other two are reversed by re-enabling the
-- addon and re-activating the standard layout.
--
-- Named for the shape it started as. Every caller passes the same two arguments
-- it always did and gets the same behaviour for the shape, plus seventeen more
-- keys carried the same way.
local function ApplyMinimapShape(on, claiming)
    local profile = ns.EUIProfile("EllesmereUIMinimap")
    local minimap = profile and profile.minimap
    if type(minimap) ~= "table" then return end

    -- Whether anything was actually reached. The old single-key version returned
    -- before the rebuild when there was no note to act on, and skipping a rebuild
    -- nobody needs is worth keeping: the off path runs on every profile switch,
    -- and ApplyAll is not free.
    local touched = false

    for i = 1, #MINIMAP_KEYS do
        local entry = MINIMAP_KEYS[i]
        local name = entry.snap or entry.key

        -- Unchanged from the single-key version, per key. EUISnap builds a record
        -- on the way down and so is used only where this is allowed to claim;
        -- EUIPeekSnap asks without building, so merely visiting a profile does
        -- not seed eighteen empty records in it.
        local saved
        if on and claiming then
            saved = ns.EUISnap("lulu", name)
        else
            saved = ns.EUIPeekSnap("lulu", name)
        end

        if saved then
            if on then
                ns.EUIOverride(minimap, saved, entry.key, entry.value, claiming)
            else
                ns.EUIRestore(minimap, saved, entry.key)
            end
            touched = true
        end
    end

    if not touched then return end

    -- RefreshAllAddons does not apply the minimap, and a shape change needs the
    -- full rebuild rather than a plain apply because visibility only
    -- re-evaluates there. The other seventeen keys would be satisfied by the
    -- plain apply the host's own options page calls, and the full rebuild is a
    -- superset of it, so one call still covers all eighteen.
    if _G._EMM_FullRebuildMinimap then _G._EMM_FullRebuildMinimap() end
end

---------------------------------------------------------------------------------
-- Edit Mode layout, read and re-activate
---------------------------------------------------------------------------------

-- Which layout is active now, in a form that survives the list being reordered.
--
-- C_EditMode.GetLayouts returns SAVED layouts only, while its activeLayout field
-- indexes the presets-first COMBINED list, so the two need reconciling.
--
-- A preset is recorded as its INDEX: presets come first and their count is fixed,
-- so those indices cannot shift. A saved layout is recorded as its NAME, because
-- ApplyPresetEditMode inserts ahead of existing layouts and shifts every index
-- after it, so a saved index goes stale the moment Lulu Mode runs.
local function ActiveEditModeLayout()
    if not (C_EditMode and C_EditMode.GetLayouts) then return nil end

    local ok, info = pcall(C_EditMode.GetLayouts)
    if not (ok and type(info) == "table" and type(info.layouts) == "table") then return nil end
    if type(info.activeLayout) ~= "number" then return nil end

    local presets = Enum and Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues
    if type(presets) ~= "number" then return nil end

    if info.activeLayout <= presets then return info.activeLayout end

    local entry = info.layouts[info.activeLayout - presets]
    if type(entry) ~= "table" or type(entry.layoutName) ~= "string" then return nil end

    -- Override layouts (Plunderstorm and its kin) need no handling. Blizzard keeps
    -- the active override in a separate field from the saved list this reads, so
    -- an override never reaches this line and what is recorded is the ordinary
    -- layout underneath it -- the one worth going back to anyway.
    return entry.layoutName
end

-- Puts back what ActiveEditModeLayout recorded. Three outcomes, not two:
--   "ok"          — the layout is active again.
--   "gone"        — the record names a layout that no longer exists. Ordinary
--                   rather than an error: the user can rename or delete a layout
--                   between Lulu Mode going on and coming off.
--   "unavailable" — the attempt could not be made at all.
-- The caller must never release the record on "unavailable". A missing capability
-- this moment can be back the next, and the record is the only thing that knows
-- the way back; treating it as "gone" would throw away a layout that still exists.
local function ActivateEditModeLayout(record)
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SetActiveLayout) then return "unavailable" end

    local presets = Enum and Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues
    if type(presets) ~= "number" then return "unavailable" end

    if type(record) == "number" then
        -- A preset index outside the preset range can never be honoured, so it is
        -- "gone" rather than "unavailable": retrying it forever would help nobody.
        if record < 1 or record > presets then return "gone" end
        if pcall(C_EditMode.SetActiveLayout, record) then return "ok" end
        return "unavailable"
    end

    local ok, info = pcall(C_EditMode.GetLayouts)
    if not (ok and type(info) == "table" and type(info.layouts) == "table") then return "unavailable" end

    for i, entry in ipairs(info.layouts) do
        if type(entry) == "table" and entry.layoutName == record then
            if pcall(C_EditMode.SetActiveLayout, presets + i) then return "ok" end
            return "unavailable"
        end
    end

    return "gone"
end

-- What Lulu recorded replacing, or nil when it replaced nothing. ns.EUI_ABSENT
-- means it did replace a layout but could not read which one.
--
-- Three callers ask three different questions of the same record: whether any of
-- Lulu's Edit Mode half is still in force, whether the way back is an activation
-- or an import, and whether the toggle should warn about the layout limit.
local function LuluLayoutRecord()
    local guid = LuluCharacter()
    if not guid then return nil end
    local saved = ns.EUIPeekSnapGlobal(LuluSnapKey("luluEditModeLayout", guid))
    if not saved then return nil end
    return saved.prev
end

-- Every message here is QUEUED, never printed: both callers reload immediately
-- afterwards, so a print lands in a chat frame the client destroys before the
-- user can read it. Every one reports something that did NOT happen, so every
-- one is red -- they arrive in the middle of the client's own startup output,
-- where a plain white line reads as more of it and is scrolled past.
local function ApplyEditModeLayout(on)
    if not (_G.EllesmereUI and EllesmereUI.ApplyPresetEditMode) then return end

    if on then
        local data = ns.data and ns.data.Blizzard_EditMode_Lulu
        if type(data) ~= "string" or strtrim(data) == "" then
            ns.QueueMessage(ns.title .. ": " .. ns.Red("No Lulu Edit Mode layout data yet. The rest of Lulu Mode still applies."))
            return
        end
        local name = ns.LuluLayoutName()
        -- Without this the write fails at five layouts and the message below
        -- blames Edit Mode not being open, which sends the user hunting in the
        -- wrong place. The rest of Lulu Mode still applies either way.
        if not ns.EditModeSlotFree(name) then
            ns.QueueMessage(ns.title .. ": " .. ns.Red("Edit Mode layout limit reached (5 account layouts), so Lulu's layout was skipped. Delete an account layout and toggle Lulu again."))
            return
        end
        -- Somewhere to write the way back, secured BEFORE the layout moves.
        -- UnitGUID is declared nilable, and a layout swapped with nowhere to
        -- record what it replaced can never be undone. Skipping is recoverable;
        -- that is not.
        local guid = LuluCharacter()
        local saved = guid and ns.EUISnapGlobal(LuluSnapKey("luluEditModeLayout", guid))
        if not saved then
            ns.QueueMessage(ns.title .. ": " .. ns.Red("Lulu's Edit Mode layout was skipped, because KitnUI could not tell which character this is and would not have been able to undo it. The rest of Lulu Mode still applies."))
            return
        end

        -- Read BEFORE the import, because ApplyPresetEditMode overwrites
        -- info.activeLayout on its way out. Committed only AFTER the import
        -- succeeds: recording a layout to go back to, for a switch that never
        -- happened, is worse than recording nothing.
        local current = ActiveEditModeLayout()

        if not EllesmereUI.ApplyPresetEditMode(data, name) then
            ns.QueueMessage(ns.title .. ": " .. ns.Red("Lulu Edit Mode import failed. Open Edit Mode once, then try again out of combat."))
            return
        end

        -- Record-once, like every other snapshot in this addon: a second apply
        -- must not capture Lulu's OWN layout as the thing to go back to.
        if saved.prev == nil then
            if current == nil then current = ns.EUI_ABSENT end
            saved.prev = current
        end
        return
    end

    -- Turning Lulu OFF puts back the layout that was active before Lulu replaced
    -- it, whatever that was. Restoring KitnUI's OWN layout instead leaves a user
    -- who skipped the Edit Mode install step stuck in Lulu's layout with no way
    -- out through the switch. What the ON path replaced is what the OFF path owes
    -- back -- no more, and no less.
    local guid = LuluCharacter()
    local saved = guid and ns.EUIPeekSnapGlobal(LuluSnapKey("luluEditModeLayout", guid))
    local record = saved and saved.prev

    -- Nothing recorded means Lulu never replaced a layout. Its ON path skips the
    -- Edit Mode step whenever the layout data is missing or the account is at
    -- Blizzard's five-layout limit, and applies the other halves regardless, so
    -- the layout on screen is the user's own choice. Changing it here would be
    -- KitnUI overwriting an arrangement it never touched.
    if record == nil then return end

    if record ~= ns.EUI_ABSENT then
        local result = ActivateEditModeLayout(record)
        if result == "ok" then
            saved.prev = nil
            return
        end
        if result == "unavailable" then
            -- Record KEPT. Edit Mode could not be asked this time, which says
            -- nothing about whether the layout still exists, and the record is the
            -- only thing that knows the way back.
            ns.QueueMessage(ns.title .. ": " .. ns.Red("Edit Mode could not be reached, so the layout you used before Lulu Mode is still waiting. Toggle Lulu Mode off again out of combat."))
            return
        end
        -- Renamed or deleted while Lulu was on. Falling through to KitnUI's own
        -- layout is better than leaving Lulu's, but the user is told, because the
        -- arrangement they get is not the one they had.
        ns.QueueMessage(ns.title .. ": " .. ns.Red("The Edit Mode layout you used before Lulu Mode is gone, so it could not be put back."))
    end

    -- The record is NOT released yet, and the order below is the whole point.
    -- Everything from here can fail: the account can be at the layout limit, and
    -- the import can refuse. Releasing first left Lulu's layout active with
    -- nothing that knew a change was still owed, so the undo prompt never offered
    -- the retry that would have worked a minute later. It is released on exactly
    -- two outcomes: the debt is settled, or it can never be settled.
    --
    -- Fallback only, for the two cases above: the record could not be read when it
    -- was taken, or it names a layout that has since gone.
    --
    -- KitnUI's layout is ACTIVATED where it already exists, and only imported
    -- where it does not. Activating costs no layout slot, so it is the only way
    -- out when the account list is full, and it does not depend on KitnUI still
    -- remembering the install: /kitn reset forgets that, but it does not delete
    -- the layout from Edit Mode, and a debt carried across a reset has to be
    -- settleable afterwards or it was pointless to carry.
    local fallback = ActivateEditModeLayout(ns.profileName)
    if fallback == "ok" then
        saved.prev = nil
        return
    end
    if fallback == "unavailable" then
        -- Record KEPT, for the same reason as the branch above: not being able to
        -- ask Edit Mode says nothing about what Edit Mode holds. Treating this as
        -- "KitnUI has no layout" would drop the debt over a question never asked.
        ns.QueueMessage(ns.title .. ": " .. ns.Red("Edit Mode could not be reached, so the layout change Lulu Mode made is still waiting to come back. Toggle Lulu Mode off again out of combat."))
        return
    end

    -- Still gated on the install step: writing KitnUI's layout over the
    -- arrangement of someone who never asked for it would be worse than leaving
    -- Edit Mode alone.
    --
    -- Emptiness tested exactly as the ON path and EditModeWarning test it, so the
    -- popup's forecast and this outcome cannot disagree.
    local installed = ns.db and ns.db.profiles and ns.db.profiles["Blizzard_EditMode"]
    local standard = ns.data and ns.data.Blizzard_EditMode
    if not installed or type(standard) ~= "string" or strtrim(standard) == "" then
        -- Nothing will ever restore this one: KitnUI has no layout of its own to
        -- offer here. Holding the record would prompt the user forever to retry
        -- work that cannot be done.
        saved.prev = nil
        return
    end

    if not ns.EditModeSlotFree(ns.profileName) then
        ns.QueueMessage(ns.title .. ": " .. ns.Red("Edit Mode layout limit reached (5 account layouts), so KitnUI's layout was not restored. Delete an account layout and toggle Lulu again."))
        return
    end

    if not EllesmereUI.ApplyPresetEditMode(standard, ns.profileName) then
        ns.QueueMessage(ns.title .. ": " .. ns.Red("Restoring KitnUI's Edit Mode layout failed. Open Edit Mode once, then try again out of combat."))
        return
    end

    saved.prev = nil
end

-- Lulu's action bar half is confined to the character that flipped the switch.
--
-- Leaving the character argument off these calls does NOT mean "this character":
-- it means the whole account. Without it, turning Lulu Mode on for one character
-- switches EllesmereUI's action bars off for alts who never asked, and a module
-- enabled on two of five characters comes back enabled on all five.

-- Whether Lulu Mode is what is holding the module off for THIS character right
-- now, and so whether there is anything of KitnUI's to offer to undo.
local function LuluOwnsActionBars()
    local guid = LuluCharacter()
    if not guid then return false end
    local saved = ns.EUIPeekSnapGlobal(LuluSnapKey("luluActionBars", guid))
    if not saved then return false end
    return saved.prev == true
end

local function ClearActionBarState()
    local guid = LuluCharacter()
    if not guid then return end
    local saved = ns.EUIPeekSnapGlobal(LuluSnapKey("luluActionBars", guid))
    if saved then saved.prev = nil end
end

-- Reading the old state and switching the module off are ONE decision, not two
-- steps that can disagree. Recording "could not tell" and switching it off anyway
-- loses the setting for good: the restore has nothing to put back, and there is no
-- second source to ask. So nothing is switched off until the record is in place.
--
-- The record is released OUTSIDE the capability checks, deliberately. Sharing
-- their early returns is what made an uninstalled action bars module a permanent
-- prompt loop: the record survived, every accept restored nothing, and the reload
-- came back to the same question.
local function ApplyActionBarModule(on)
    local guid = LuluCharacter()
    if not guid then return end

    local usable = C_AddOns and C_AddOns.DisableAddOn and C_AddOns.EnableAddOn
        and C_AddOns.GetAddOnEnableState and Enum and Enum.AddOnEnableState
    if usable and C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist(ACTION_BARS) then
        usable = false
    end

    if on then
        if not usable then return end

        -- Record-once, exactly like every other snapshot here: a second apply must
        -- not capture Lulu's own handiwork as the thing to go back to.
        local saved = ns.EUISnapGlobal(LuluSnapKey("luluActionBars", guid))
        if not saved then return end
        if saved.prev == nil then
            local ok, state = pcall(C_AddOns.GetAddOnEnableState, ACTION_BARS, guid)
            if not (ok and type(state) == "number") then return end
            -- Blizzard's own test for enabled. Already off, by the user's hand or
            -- by an earlier pass, means Lulu has nothing to switch and nothing to
            -- remember: recording "it was off" outlives its purpose, and
            -- record-once then refuses to update it if the user switches the
            -- module back on, so Lulu would switch it off and never switch it
            -- back. A record exists ONLY where Lulu owes one.
            if state <= Enum.AddOnEnableState.None then return end
            saved.prev = true
        end

        C_AddOns.DisableAddOn(ACTION_BARS, guid)
        return
    end

    -- Switched back on ONLY where the record says it was on to begin with. A user
    -- who already had EllesmereUI's action bars off must get them back off:
    -- reversing that is a deliberate choice of theirs that KitnUI has no business
    -- overruling.
    if usable and LuluOwnsActionBars() then
        C_AddOns.EnableAddOn(ACTION_BARS, guid)
    end

    ClearActionBarState()
end

-- Reached from Installer/Setup.lua's module pass, which puts EllesmereUI's module
-- set into the state the pack expects and meets the action bars when Lulu is on.
-- That pass must come through here rather than switching the module off itself:
-- its own calls name no character, so they reach every character on the account,
-- and they take no record, so turning Lulu off afterwards had nothing to put back.
ns.LuluApplyActionBars = ApplyActionBarModule

-- What the Edit Mode step is about to do, worked out BEFORE the popup so the
-- user can act on it while acting is still cheap. Told only afterwards, the way
-- out of a full layout list costs three reloads; cancelling on a warning costs
-- none.
--
-- Returns a sentence to append to the popup, or nil when the step will run. The
-- popup text is the forecast and ApplyEditModeLayout is the outcome, so both read
-- the same conditions in the same order: a warning that disagreed with what
-- then happened would be worse than no warning.
local function EditModeWarning(on)
    -- Not nil: nil is this function's word for "the step will run", and
    -- ApplyEditModeLayout returns silently on this same guard. Saying nothing
    -- here promises a layout step that never happens and never explains itself.
    if not (_G.EllesmereUI and EllesmereUI.ApplyPresetEditMode) then
        return "\n\nNote: this version of EllesmereUI cannot apply Edit Mode layouts, so that step will be skipped. Everything else still applies."
    end

    local data, layoutName
    if on then
        data = ns.data and ns.data.Blizzard_EditMode_Lulu
        layoutName = ns.LuluLayoutName()
    else
        -- Only one OFF case reaches the importer, so only one gets a forecast. A
        -- recorded layout comes back by being re-activated, which needs no slot and
        -- no import, and no record at all means Edit Mode is left alone entirely.
        -- Only "Lulu replaced a layout but could not read which one" falls through
        -- to importing KitnUI's own.
        --
        -- One case escapes the forecast: a recorded layout the user has since
        -- deleted also falls through to the import, and this cannot tell without
        -- doing the lookup twice. Both outcomes are still reported afterwards, so
        -- the user is told what happened, just not warned beforehand.
        if LuluLayoutRecord() ~= ns.EUI_ABSENT then return nil end

        -- Someone who never ran the Edit Mode step has nothing to restore, and
        -- nothing to be warned about either. Silent no-op by design.
        if not (ns.db and ns.db.profiles and ns.db.profiles["Blizzard_EditMode"]) then
            return nil
        end
        data = ns.data and ns.data.Blizzard_EditMode
        layoutName = ns.profileName
    end

    if type(data) ~= "string" or strtrim(data) == "" then
        return "\n\nNote: there is no Edit Mode layout to apply yet, so that step will be skipped. Everything else still applies."
    end

    if not ns.EditModeSlotFree(layoutName) then
        -- Coloured, not bolded. A StaticPopup's text is one fontstring with one
        -- font object, so there is no bold to switch on mid-sentence; colour and
        -- capitals are the whole toolkit. ns.Red is the same red the installer
        -- uses for every other failure line.
        return "\n\n" .. ns.Red("WARNING:") .. " you already have 5 account Edit Mode layouts, which is Blizzard's limit, so the Edit Mode step will be SKIPPED.\n\nCancel, delete an account layout, then try again. Carrying on costs you another reload to fix it."
    end

    return nil
end

-- Every part of this needs a reload to be true, so the switch owns the popup and
-- the reload rather than each part doing its own.
function ns.SetLuluMode(on)
    if InCombatLockdown() then
        print(ns.title .. ": Lulu Mode cannot be changed in combat.")
        -- The toggle already animated to the new position when it called this,
        -- and it never re-reads its getter, so it would keep showing a state
        -- that was refused. RefreshPage rebuilds the row from the real value.
        if _G.EllesmereUI and EllesmereUI.RefreshPage then
            pcall(EllesmereUI.RefreshPage, EllesmereUI, true)
        end
        return
    end

    local text
    if on then
        text = ns.title .. ": Turn Lulu Mode on?\n\nThis makes the minimap round, switches EllesmereUI's action bars off so Blizzard's own bars return, and applies the Lulu Edit Mode layout. Your UI will reload."
    else
        text = ns.title .. ": Turn Lulu Mode off?\n\nThis restores the minimap shape, switches EllesmereUI's action bars back on, and puts back the Edit Mode layout you were using before. Your UI will reload."
    end

    local warning = EditModeWarning(on)
    if warning then text = text .. warning end

    StaticPopupDialogs["KITNUI_LULU_CONFIRM"] = {
        text = text,
        button1 = on and "Turn On" or "Turn Off",
        button2 = "Cancel",
        OnAccept = function()
            -- Rechecked here, not only before the popup. The popup has no
            -- timeout, so a player can open it out of combat, get pulled, and
            -- accept mid-fight. ApplyPresetEditMode combat-guards itself and
            -- would return false, and the ReloadUI on the next line means
            -- nothing ever retries: Lulu Mode would end up half applied, with
            -- the minimap and the action bars changed and the layout missing.
            if InCombatLockdown() then
                print(ns.title .. ": Lulu Mode cannot be changed in combat. Try again after this fight.")
                -- Same reason as the entry guard: the knob already moved.
                if _G.EllesmereUI and EllesmereUI.RefreshPage then
                    pcall(EllesmereUI.RefreshPage, EllesmereUI, true)
                end
                return
            end
            local s = ns.EUISettings()
            s.lulu = on and true or false
            ApplyMinimapShape(on, true)
            ApplyEditModeLayout(on)
            ApplyActionBarModule(on)
            ReloadUI()
        end,
        OnCancel = function()
            -- Same reason as the combat guard: the knob already moved.
            if _G.EllesmereUI and EllesmereUI.RefreshPage then
                pcall(EllesmereUI.RefreshPage, EllesmereUI, true)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        -- Keeps Blizzard's own dialogs taint-free.
        preferredIndex = 3,
    }
    StaticPopup_Show("KITNUI_LULU_CONFIRM")
end

-- Only the minimap re-asserts on a profile switch. The module state and the Edit
-- Mode layout are not profile-scoped and would need a reload to change anyway.
ns.EUIRegisterReapply(function()
    ApplyMinimapShape(ns.LuluEnabled(), false)
end)

-- An imported profile that turns Lulu on leaves the switch reading ON with NONE
-- of its three parts applied: two need a reload, and the minimap needs a claim
-- the re-apply is not allowed to make. Accepting the prompt applies all three.
-- Prompt rather than let the switch lie.
--
-- Driven by a STATE MISMATCH, not by watching for an off-to-on transition. The
-- normal import path shows no transition to watch: EllesmereUI reloads the moment
-- its import finishes, so at the next login the imported ON state is simply the
-- state this addon starts in. The mismatch survives that reload -- Lulu reading
-- ON while the action bar module it switches off is still loaded means its
-- reload-only halves were never applied.
--
-- BOTH directions are prompted, because the switch can lie both ways. Switch to a
-- profile whose Lulu is OFF and the minimap goes back to square, because that
-- half re-applies without a reload, while the action bars stay Blizzard's and
-- Lulu's Edit Mode layout stays active: the profile says no Lulu and two thirds
-- of Lulu is on screen, with no reload coming.
--
-- The reverse direction is GUARDED on Lulu's own records and asks about each half
-- separately. The action bars record says whether the module was switched ON
-- before Lulu touched it, so someone who had them off already is never offered
-- them back. The Edit Mode record is asked on its own, because that same user
-- still has Lulu's layout active with the switch reading off.
local ACTION_BARS_LOADED_UNKNOWN = "unknown"

local function ActionBarsLoaded()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return ACTION_BARS_LOADED_UNKNOWN end
    if C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist(ACTION_BARS) then
        -- Not installed, so Lulu's action bar half has nothing left to do. FALSE
        -- is the no-mismatch answer here: the caller's mismatch is "Lulu is on and
        -- this module is STILL LOADED", so returning true would report a mismatch
        -- that can never be cleared, and every accept would reload into the same
        -- prompt again.
        --
        -- Known gap: this module is the proxy for all three halves, so a user
        -- without it who imports Lulu ON is never prompted and the Edit Mode half
        -- stays unapplied. Detecting that half directly means asking Edit Mode
        -- which layout is active, which is a different problem; running
        -- EllesmereUI without its action bars is the rarer state of the two.
        return false
    end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, ACTION_BARS)
    if not ok then return ACTION_BARS_LOADED_UNKNOWN end
    return loaded and true or false
end

-- A record on the action bars is a debt to switch the module back ON. Once it IS
-- on and Lulu is off, that debt is settled, whoever settled it, and the record has
-- to go: held any longer it becomes a claim on a state the user now owns, and the
-- next time they switch the module off themselves KitnUI offers to reverse them.
--
-- EllesmereUI's own profile import is how this happens in practice: it enables
-- every module in the suite for the WHOLE account, so one character installing
-- pays every other character's debt without either addon knowing. The rule lives
-- here rather than after the import because what matters is the state, not which
-- route produced it, and only the character whose record it is can see its own
-- module.
--
-- Not while Lulu is ON: that state is the "apply" mismatch, the record still
-- describes the true original, and the reload is about to switch the module off
-- again.
local function SettleActionBarsIfLoaded()
    if ns.LuluEnabled and ns.LuluEnabled() then return end
    if not LuluOwnsActionBars() then return end
    if ActionBarsLoaded() ~= true then return end
    ClearActionBarState()
end

-- Holds WHICH mismatch was prompted, not merely that one was, so a state that
-- flips from one direction to the other still asks. Set only once the dialog is
-- actually on screen, and cleared by declining it or by the mismatch going away.
-- It stops a second reconcile in the same pass stacking a duplicate prompt; it
-- must never become the reason a prompt is not shown.
local promptedForMismatch

-- Which way the switch is lying, or nil when it is telling the truth. Unknown is
-- neither: prompting for a reload on a reading we could not take would nag a user
-- whose UI is already correct.
local function CurrentMismatch()
    local on = false
    if ns.LuluEnabled then on = ns.LuluEnabled() end

    local loaded = ActionBarsLoaded()

    if on then
        if loaded == true then return "apply" end
        return nil
    end

    -- Either half still in force is a mismatch on its own.
    if loaded == false and LuluOwnsActionBars() then return "undo" end
    if LuluLayoutRecord() ~= nil then return "undo" end
    return nil
end

function ns.LuluReconcile()
    -- Before the mismatch is read, not after: a settled debt must stop counting as
    -- one in the very same pass, or the reading below is taken against a record
    -- that no longer means anything.
    SettleActionBarsIfLoaded()

    local kind = CurrentMismatch()

    if not kind then
        promptedForMismatch = nil
        -- A dialog already on screen was raised for a state that no longer holds.
        -- It has no timeout, and its accept handler carries the direction it was
        -- built with, so leaving it up lets the user apply the OFF work to a
        -- profile that has since switched ON.
        StaticPopup_Hide("KITNUI_LULU_IMPORTED")
        return
    end

    if promptedForMismatch == kind then return end

    -- Not in combat, and not latched either: the mismatch is still there
    -- afterwards, so the next reconcile trigger prompts instead.
    if InCombatLockdown() then return end

    -- Both texts describe the STATE, not how it got there. An imported profile is
    -- the common cause of "apply" and a profile switch of "undo", but each is
    -- reachable other ways and a message that named a cause would be wrong there.
    --
    -- Built here rather than at file scope. At file scope ns.title is read before
    -- KitnUI has necessarily filled it, and a nil there is a load error in a file
    -- that would otherwise degrade quietly. The Edit Mode forecast is the same one
    -- the toggle shows, for the same reason: a full layout list costs the user a
    -- second reload to discover afterwards and nothing to cancel on now.
    local text, apply
    if kind == "apply" then
        apply = true
        -- Count-free on purpose. A count here is a promise about the screen, and
        -- two states defeat it: the import can carry the minimap blob so that half
        -- already looks applied, and a live note under this profile name lets the
        -- re-apply legitimately re-assert it.
        text = ns.title .. ": Lulu Mode is on, but it is not applied.\n\nApplying it needs a reload. Do that now?"
    else
        apply = false
        -- Named half by half, because either can be in force without the other.
        -- A user who had EllesmereUI's action bars off already reaches this with
        -- only the layout to put back, and telling them their action bars are
        -- switched off when that was their own doing would send them looking for
        -- a problem KitnUI did not cause.
        local barsHeld = LuluOwnsActionBars() and ActionBarsLoaded() == false
        local layoutHeld = LuluLayoutRecord() ~= nil

        local parts
        if barsHeld and layoutHeld then
            parts = "EllesmereUI's action bars are still switched off, and Lulu's Edit Mode layout is still the active one. Putting both back needs a reload."
        elseif barsHeld then
            parts = "EllesmereUI's action bars are still switched off. Putting them back needs a reload."
        else
            parts = "Lulu's Edit Mode layout is still the active one. Putting it back needs a reload."
        end

        text = ns.title .. ": Lulu Mode is off for this profile, but part of it is still on.\n\n" .. parts .. " Do that now?"
    end

    local warning = EditModeWarning(apply)
    if warning then text = text .. warning end

    StaticPopupDialogs["KITNUI_LULU_IMPORTED"] = {
        text = text,
        button1 = YES,
        button2 = NO,
        -- Does the work, THEN reloads. A bare ReloadUI would put the user back
        -- exactly where they started: the switch state is unchanged either way, so
        -- nothing else would ever apply it.
        OnAccept = function()
            -- Rechecked, as in ns.SetLuluMode: the popup has no timeout, so it can
            -- be opened out of combat and accepted mid-fight, and
            -- ApplyPresetEditMode refuses in combat. The reload on the next line
            -- means nothing retries, so a half-done Lulu would be permanent.
            if InCombatLockdown() then
                print(ns.title .. ": Lulu Mode cannot be changed in combat. Try again after this fight.")
                promptedForMismatch = nil
                return
            end

            -- Re-checked for the same reason, one step further out: with no
            -- timeout this dialog can sit open across a profile switch, and `apply`
            -- was decided when it was built. Doing the OFF work under a profile
            -- that now says ON would switch the action bars back on and drop the
            -- Lulu layout, against a switch reading on.
            if CurrentMismatch() ~= kind then
                promptedForMismatch = nil
                return
            end

            -- The minimap belongs here too, and it CLAIMS. Accepting this prompt
            -- is a user action, which is the only thing allowed to record an
            -- original. Without it the minimap half would never apply on an
            -- imported profile: the re-apply refuses to claim, and CurrentMismatch
            -- reads only the action bar module and the layout record, so once
            -- those two are settled the prompt never asks again.
            ApplyMinimapShape(apply, true)
            ApplyEditModeLayout(apply)
            ApplyActionBarModule(apply)
            ReloadUI()
        end,
        -- Declining is not the same as being told. The mismatch is still real, so
        -- release the latch and let the next profile switch or login ask again.
        OnCancel = function() promptedForMismatch = nil end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    -- Latched on the SHOWN dialog, never on the attempt: StaticPopup_Show returns
    -- nil when every dialog frame is already taken, and latching on that would
    -- spend the user's only notice on a prompt they never saw.
    if not StaticPopup_Show("KITNUI_LULU_IMPORTED") then return end
    promptedForMismatch = kind
end

-- Called by ns.EUIResetAll, which reloads straight afterwards. The re-apply
-- registry handles the minimap; these two are the parts a reload is required for.
--
-- Keyed on the RECORDS, not on the switch, because the switch misses the exact
-- state the undo prompt exists for: the user switches to a profile whose Lulu
-- reads off while Lulu is still applied, ignores the prompt, and runs /kitn
-- reset. The switch says off, the teardown skips, and the caller then nils
-- KitnUIDB and takes both records with it. The records answer the real question:
-- is there anything of ours still applied.
local function LuluApplied()
    if ns.LuluEnabled and ns.LuluEnabled() then return true end
    if LuluOwnsActionBars() then return true end
    if LuluLayoutRecord() ~= nil then return true end
    return false
end

function ns.LuluTearDown()
    if not LuluApplied() then return end
    ApplyEditModeLayout(false)
    ApplyActionBarModule(false)
end
