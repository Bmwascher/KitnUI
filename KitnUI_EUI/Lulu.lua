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
    else
        C_AddOns.EnableAddOn(ACTION_BARS)
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
-- The reverse mismatch is not prompted. Lulu OFF with the module unloaded is what
-- a pending Enable looks like between the toggle and the reload the toggle
-- already asked for.
local ACTION_BARS_LOADED_UNKNOWN = "unknown"

local function ActionBarsLoaded()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return ACTION_BARS_LOADED_UNKNOWN end
    if C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist(ACTION_BARS) then
        -- Not installed, so Lulu's action bar half has nothing to do and is not
        -- missing. Reported as loaded, which is the no-mismatch answer.
        --
        -- Known gap: this module is the proxy for all three halves, so a user
        -- without it who imports Lulu ON is never prompted and the Edit Mode half
        -- stays unapplied. Detecting that half directly means asking Edit Mode
        -- which layout is active, which is a different problem; running
        -- EllesmereUI without its action bars is the rarer state of the two.
        return true
    end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, ACTION_BARS)
    if not ok then return ACTION_BARS_LOADED_UNKNOWN end
    return loaded and true or false
end

-- Cleared when the mismatch clears, so a user who declines gets asked again the
-- next time they load a profile rather than on every single reconcile pass.
local promptedForMismatch = false

function ns.LuluReconcile()
    local on = false
    if ns.LuluEnabled then on = ns.LuluEnabled() end

    local loaded = ActionBarsLoaded()
    -- Unknown is not a mismatch. Prompting for a reload on a reading we could not
    -- take would nag a user whose UI is already correct.
    local mismatch = on and loaded == true

    if not mismatch then
        promptedForMismatch = false
        return
    end

    if promptedForMismatch then return end

    -- Not in combat, and not latched either: the mismatch is still there
    -- afterwards, so the next reconcile trigger prompts instead.
    if InCombatLockdown() then return end

    promptedForMismatch = true

    -- Built here rather than at file scope. At file scope ns.title is read before
    -- KitnUI has necessarily filled it, and a nil there is a load error in a file
    -- that would otherwise degrade quietly. The Edit Mode forecast is the same one
    -- the toggle shows, for the same reason: a full layout list costs the user a
    -- second reload to discover afterwards and nothing to cancel on now.
    -- Describes the STATE, not how it got there. An imported profile is the common
    -- cause, but re-enabling EllesmereUI's action bars by hand reaches the same
    -- mismatch, and a message that blamed an import would be wrong there.
    local text = ns.title .. ": Lulu Mode is on, but two of its three parts are not.\n\nEllesmereUI's action bars still need to switch off so Blizzard's own bars return, and Lulu's Edit Mode layout still needs to apply. Both need a reload. Do that now?"
    local warning = EditModeWarning(true)
    if warning then text = text .. warning end

    StaticPopupDialogs["KITNUI_LULU_IMPORTED"] = {
        text = text,
        button1 = YES,
        button2 = NO,
        -- Applies the two halves, then reloads. A bare ReloadUI would put the user
        -- back exactly where they started: the switch is already ON, so nothing
        -- would prompt a second time and nothing would ever apply.
        OnAccept = function()
            -- Rechecked, as in ns.SetLuluMode: the popup has no timeout, so it can
            -- be opened out of combat and accepted mid-fight, and
            -- ApplyPresetEditMode refuses in combat. The reload on the next line
            -- means nothing retries, so a half-applied Lulu would be permanent.
            if InCombatLockdown() then
                print(ns.title .. ": Lulu Mode cannot be applied in combat. Try again after this fight.")
                promptedForMismatch = false
                return
            end
            ApplyEditModeLayout(true)
            ApplyActionBarModule(true)
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("KITNUI_LULU_IMPORTED")
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
