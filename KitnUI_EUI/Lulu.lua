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

function ns.LuluEnabled()
    local s = ns.EUISettings()
    return s.lulu and true or false
end

ns.LuluLayoutName = function()
    return ns.profileName .. " Lulu"
end

-- The minimap is the only part that applies without a reload, so it is the only
-- part that snapshots. The other two are reversed by re-enabling the addon and
-- re-activating the standard layout.
local function ApplyMinimapShape(on)
    local saved
    if on then
        saved = ns.EUISnap("lulu", "minimapShape")
    else
        saved = ns.EUIPeekSnap("lulu", "minimapShape")
    end
    if not saved then return end

    local profile = ns.EUIProfile("EllesmereUIMinimap")
    local minimap = profile and profile.minimap
    if type(minimap) ~= "table" then return end

    if on then
        ns.EUIOverride(minimap, saved, "shape", "circle")
    else
        ns.EUIRestore(minimap, saved, "shape")
    end

    -- RefreshAllAddons does not apply the minimap, and a shape change needs the
    -- full rebuild rather than a plain apply because visibility only
    -- re-evaluates there.
    if _G._EMM_FullRebuildMinimap then _G._EMM_FullRebuildMinimap() end
end

---------------------------------------------------------------------------------
-- Edit Mode layout, read and re-activate
---------------------------------------------------------------------------------

-- Which layout is active now, in a form that survives the list being reordered.
--
-- C_EditMode.GetLayouts returns SAVED layouts only, while its activeLayout field
-- indexes the presets-first COMBINED list, so the two need reconciling. That is
-- the same convention Installer/Setup.lua:327 already uses.
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

    -- Override layouts belong to Plunderstorm and its kin. They are transient and
    -- cannot be re-activated by name afterwards, so there is nothing worth
    -- recording and pretending otherwise would record a name that never comes back.
    local override = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Override
    if override ~= nil and entry.layoutType == override then return nil end

    return entry.layoutName
end

-- Puts back what ActiveEditModeLayout recorded. Returns false when the record can
-- no longer be honoured, which is an ordinary outcome rather than an error: the
-- user can rename or delete a layout between Lulu Mode going on and coming off.
local function ActivateEditModeLayout(record)
    if record == nil then return false end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SetActiveLayout) then return false end

    local presets = Enum and Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues
    if type(presets) ~= "number" then return false end

    if type(record) == "number" then
        if record < 1 or record > presets then return false end
        return pcall(C_EditMode.SetActiveLayout, record) and true or false
    end

    local ok, info = pcall(C_EditMode.GetLayouts)
    if not (ok and type(info) == "table" and type(info.layouts) == "table") then return false end

    for i, entry in ipairs(info.layouts) do
        if type(entry) == "table" and entry.layoutName == record then
            return pcall(C_EditMode.SetActiveLayout, presets + i) and true or false
        end
    end

    return false
end

-- Every message here is QUEUED, never printed. Both callers reload immediately
-- afterwards, so a print lands in a chat frame the client destroys before the
-- user can read it: they flip the switch, the screen reloads, and nothing ever
-- explains why the layout did not change. ns.QueueMessage prints on the far side.
--
-- Every one of them reports something that did NOT happen, so every one is red.
-- They arrive two seconds into a login, in the middle of the client's own
-- startup spam, and a plain white line there reads as more spam and is scrolled
-- past. The whole point of queueing was that the user sees it.
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
        -- Read BEFORE the import, because ApplyPresetEditMode overwrites
        -- info.activeLayout on its way out and never reads it back
        -- (References/EllesmereUI-v8.7.5/EllesmereUI/EllesmereUI_Profiles.lua:4979-4983).
        -- Committed only AFTER the import succeeds: recording a layout to go back
        -- to, for a switch that never happened, is worse than recording nothing.
        local current = ActiveEditModeLayout()

        if not EllesmereUI.ApplyPresetEditMode(data, name) then
            ns.QueueMessage(ns.title .. ": " .. ns.Red("Lulu Edit Mode import failed. Open Edit Mode once, then try again out of combat."))
            return
        end

        -- Record-once, like every other snapshot in this addon: a second apply
        -- must not capture Lulu's OWN layout as the thing to go back to.
        local saved = ns.EUISnapGlobal("luluEditModeLayout")
        if saved and saved.prev == nil then
            if current == nil then current = ns.EUI_ABSENT end
            saved.prev = current
        end
        return
    end

    -- Turning Lulu OFF puts back the layout that was active before Lulu replaced
    -- it, whatever that was. Kitn's in-game test on 2026-08-08 is why: the old
    -- code restored KitnUI's OWN layout and only if the Edit Mode install step had
    -- been run, so a user who skipped that step was left in Lulu's layout with no
    -- way out through the switch. The ON path writes its layout unconditionally,
    -- so the OFF path has to be able to undo it unconditionally too.
    local saved = ns.EUIPeekSnapGlobal("luluEditModeLayout")
    local record = saved and saved.prev

    if record ~= nil and record ~= ns.EUI_ABSENT then
        if ActivateEditModeLayout(record) then
            saved.prev = nil
            return
        end
        -- Renamed or deleted while Lulu was on. Falling through to KitnUI's own
        -- layout is better than leaving Lulu's, but the user is told, because the
        -- arrangement they get is not the one they had.
        ns.QueueMessage(ns.title .. ": " .. ns.Red("The Edit Mode layout you used before Lulu Mode is gone, so it could not be put back."))
    end

    if saved then saved.prev = nil end

    -- Fallback only, for the two cases above: nothing was recorded, or the record
    -- could not be honoured. Still gated on the install step, for the reason it
    -- always was — writing KitnUI's layout over the arrangement of someone who
    -- never asked for it would be worse than leaving Edit Mode alone.
    local installed = ns.db and ns.db.profiles and ns.db.profiles["Blizzard_EditMode"]
    if not installed then return end

    -- Emptiness tested exactly as the ON path and EditModeWarning test it. A bare
    -- type check let an empty string reach the importer, which is both a pointless
    -- call and a forecast the popup would have got wrong.
    local standard = ns.data and ns.data.Blizzard_EditMode
    if type(standard) ~= "string" or strtrim(standard) == "" then return end

    if not ns.EditModeSlotFree(ns.profileName) then
        ns.QueueMessage(ns.title .. ": " .. ns.Red("Edit Mode layout limit reached (5 account layouts), so KitnUI's layout was not restored. Delete an account layout and toggle Lulu again."))
        return
    end

    if not EllesmereUI.ApplyPresetEditMode(standard, ns.profileName) then
        ns.QueueMessage(ns.title .. ": " .. ns.Red("Restoring KitnUI's Edit Mode layout failed. Open Edit Mode once, then try again out of combat."))
    end
end

-- Record-once, exactly like every other snapshot here. It answers one question at
-- restore time: was EllesmereUI's action bars module switched on before Lulu Mode
-- touched it? Nothing about it is a claim of authorship — it exists only because
-- Lulu's ON path wrote it, and that is what makes it trustworthy.
local function RecordActionBarState()
    local saved = ns.EUISnapGlobal("luluActionBars")
    if not (saved and saved.prev == nil) then return end

    -- An unreadable state must NOT be recorded as "was enabled". EUI_ABSENT means
    -- "could not tell", and the restore treats that the same as no record: it
    -- leaves the module alone rather than guessing in the user's stead.
    local prev = ns.EUI_ABSENT
    if C_AddOns and C_AddOns.GetAddOnEnableState and Enum and Enum.AddOnEnableState then
        local ok, state = pcall(C_AddOns.GetAddOnEnableState, ACTION_BARS)
        if ok and type(state) == "number" then
            -- Blizzard's own test for enabled, from
            -- .wow-api-reference/Interface/AddOns/Blizzard_AddOnList/AddonList.lua:188.
            prev = state > Enum.AddOnEnableState.None
        end
    end
    saved.prev = prev
end

local function ClearActionBarState()
    local saved = ns.EUIPeekSnapGlobal("luluActionBars")
    if saved then saved.prev = nil end
end

-- Whether Lulu Mode is what is holding the module off right now, and so whether
-- there is anything of KitnUI's to offer to undo.
local function LuluOwnsActionBars()
    local saved = ns.EUIPeekSnapGlobal("luluActionBars")
    if not saved then return false end
    if saved.prev == true then return true end
    return false
end

-- The record is taken and released OUTSIDE the capability checks, deliberately.
-- Sharing their early returns is what made an uninstalled action bars module a
-- permanent prompt loop: the record survived, every accept restored nothing, and
-- the reload came back to the same question.
local function ApplyActionBarModule(on)
    if on then RecordActionBarState() end

    local usable = C_AddOns and C_AddOns.DisableAddOn and C_AddOns.EnableAddOn
    if usable and C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist(ACTION_BARS) then
        usable = false
    end

    if usable then
        if on then
            C_AddOns.DisableAddOn(ACTION_BARS)
        elseif LuluOwnsActionBars() then
            -- Switched back on ONLY where the record says it was on to begin with.
            -- A user who already had EllesmereUI's action bars off must get them
            -- back off: reversing that is a deliberate choice of theirs that
            -- KitnUI has no business overruling.
            C_AddOns.EnableAddOn(ACTION_BARS)
        end
    end

    if not on then ClearActionBarState() end
end

-- What the Edit Mode step is about to do, worked out BEFORE the popup so the
-- user can act on it while acting is still cheap. Told only afterwards, the way
-- out of a full layout list was: toggle on, reload, read the message, delete a
-- layout, toggle off, reload, toggle on, reload. Three reloads to land one
-- layout. Cancelling on a warning costs none.
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
        text = ns.title .. ": Turn Lulu Mode off?\n\nThis restores the minimap shape, switches EllesmereUI's action bars back on, and re-applies the standard KitnUI Edit Mode layout. Your UI will reload."
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
            ApplyMinimapShape(on)
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
    ApplyMinimapShape(ns.LuluEnabled())
end)

-- Lulu's other two halves need a reload, so an imported profile that turns it on
-- leaves the switch reading ON with only the minimap applied. Prompt rather than
-- let the switch lie.
--
-- Driven by a STATE MISMATCH, not by watching for an off-to-on transition. The
-- normal import path never shows a transition to watch: EllesmereUI's own import
-- button calls ReloadUI the moment it finishes
-- (References/EllesmereUI-v8.7.5/EllesmereUI/EUI__General_Options.lua:5099-5129),
-- so the client is gone before the debounced reconcile runs, and at the next
-- login the imported ON state is simply the state this addon starts in. The
-- mismatch survives that reload and is what the user actually needs telling
-- about: Lulu recorded ON while the action bar module it switches off is still
-- loaded means its reload-only halves were never applied.
--
-- BOTH directions are prompted, because the switch can lie both ways. Kitn's
-- in-game test on 2026-08-08 found the reverse: switch to a profile whose Lulu is
-- OFF and the minimap goes back to square, because that half re-applies without a
-- reload, while the action bars stay Blizzard's and Lulu's Edit Mode layout stays
-- active. The profile says no Lulu and two thirds of Lulu is on screen. This file
-- previously dismissed that state as the moment between the toggle and its
-- reload, which was wrong: a profile switch reaches it with no reload coming.
--
-- The reverse direction is GUARDED on the luluActionBars snapshot, which records
-- whether the module was switched ON before Lulu touched it. Someone who had
-- EllesmereUI's action bars off already must never be offered them back: the
-- record says false there, and nothing of KitnUI's is being held down.
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

    if on and loaded == true then return "apply" end
    if not on and loaded == false and LuluOwnsActionBars() then return "undo" end
    return nil
end

function ns.LuluReconcile()
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
        text = ns.title .. ": Lulu Mode is on, but two of its three parts are not.\n\nEllesmereUI's action bars still need to switch off so Blizzard's own bars return, and Lulu's Edit Mode layout still needs to apply. Both need a reload. Do that now?"
    else
        apply = false
        text = ns.title .. ": Lulu Mode is off for this profile, but two of its three parts are still on.\n\nEllesmereUI's action bars are still switched off, and Lulu's Edit Mode layout is still the active one. Putting both back needs a reload. Do that now?"
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

    -- Latched on the SHOWN dialog, never on the attempt. StaticPopup_Show returns
    -- nil when every dialog frame is already taken
    -- (.wow-api-reference/Interface/AddOns/Blizzard_StaticPopup/StaticPopup.lua:366-370),
    -- and latching on that would spend the user's only notice on a prompt they
    -- never saw.
    if not StaticPopup_Show("KITNUI_LULU_IMPORTED") then return end
    promptedForMismatch = kind
end

-- Called by ns.EUIResetAll, which reloads straight afterwards. The re-apply
-- registry handles the minimap; these two are the parts a reload is required for,
-- and leaving them behind would strand the action bars off and the Lulu layout
-- active with the switch reading off and no record of either.
-- Keyed on the RECORDS, not on the switch. Keying on the switch missed the exact
-- state the undo prompt exists for: the user switches to a profile whose Lulu
-- reads off while Lulu is still applied, declines or ignores the prompt, and runs
-- /kitn reset. The switch says off, so the teardown skipped, and the caller then
-- nils KitnUIDB and takes both records with it — leaving the action bars off and
-- the Lulu layout active with nothing left that knows how to undo either.
--
-- The records answer the real question: is there anything of ours still applied.
local function LuluApplied()
    if ns.LuluEnabled and ns.LuluEnabled() then return true end
    if LuluOwnsActionBars() then return true end

    local layout = ns.EUIPeekSnapGlobal("luluEditModeLayout")
    if layout and layout.prev ~= nil then return true end

    return false
end

function ns.LuluTearDown()
    if not LuluApplied() then return end
    ApplyEditModeLayout(false)
    ApplyActionBarModule(false)
end
