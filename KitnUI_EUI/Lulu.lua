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
        if not EllesmereUI.ApplyPresetEditMode(data, name) then
            ns.QueueMessage(ns.title .. ": " .. ns.Red("Lulu Edit Mode import failed. Open Edit Mode once, then try again out of combat."))
        end
        return
    end

    -- Turning Lulu OFF restores the layout KitnUI put there, which means there
    -- has to be one. Without this check a user who never ran KitnUI's Edit Mode
    -- step gets KitnUI's layout written the first time they switch Lulu off, and
    -- their own Edit Mode arrangement replaced by one they never asked for.
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

local function ApplyActionBarModule(on)
    if not (C_AddOns and C_AddOns.DisableAddOn and C_AddOns.EnableAddOn) then return end
    if C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist(ACTION_BARS) then return end

    if on then
        C_AddOns.DisableAddOn(ACTION_BARS)
        -- Records that LULU switched it off, not the user. ns.LuluReconcile needs
        -- that to tell "Lulu is still applied under a profile that says it is
        -- off", which it should offer to undo, from "the user does not want
        -- EllesmereUI's action bars", which is none of KitnUI's business. Kept in
        -- KitnUIDB rather than the profile: whether an addon is switched off is an
        -- account-wide fact about THIS machine, exactly like a snapshot, and it
        -- must not ride an exported profile to a machine where it is untrue.
        if ns.db then ns.db.euiLuluDisabledBars = true end
    else
        C_AddOns.EnableAddOn(ACTION_BARS)
        if ns.db then ns.db.euiLuluDisabledBars = nil end
    end
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
-- The reverse direction is GUARDED on ns.db.euiLuluDisabledBars, so it fires only
-- where Lulu was the one that switched the module off. Someone who switched
-- EllesmereUI's action bars off themselves must never be offered them back.
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

local function LuluOwnsActionBars()
    if not ns.db then return false end
    if ns.db.euiLuluDisabledBars then return true end
    return false
end

-- Holds WHICH mismatch was prompted, not merely that one was, so a state that
-- flips from one direction to the other still asks. Set only once the dialog is
-- actually on screen, and cleared by declining it or by the mismatch going away.
-- It stops a second reconcile in the same pass stacking a duplicate prompt; it
-- must never become the reason a prompt is not shown.
local promptedForMismatch

function ns.LuluReconcile()
    local on = false
    if ns.LuluEnabled then on = ns.LuluEnabled() end

    local loaded = ActionBarsLoaded()

    -- Unknown is neither mismatch. Prompting for a reload on a reading we could
    -- not take would nag a user whose UI is already correct.
    local kind
    if on and loaded == true then
        kind = "apply"
    elseif not on and loaded == false and LuluOwnsActionBars() then
        kind = "undo"
    end

    if not kind then
        promptedForMismatch = nil
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
function ns.LuluTearDown()
    if not ns.LuluEnabled() then return end
    ApplyEditModeLayout(false)
    ApplyActionBarModule(false)
end
