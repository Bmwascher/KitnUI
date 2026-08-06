-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab/Lulu.lua                                             ║
-- ║  Purpose: Lulu Mode: round minimap, Blizzard action bars,    ║
-- ║           and a dedicated Edit Mode layout, as one switch.   ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

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
    local saved = on and ns.EUISnap("lulu", "minimapShape") or ns.EUIPeekSnap("lulu", "minimapShape")
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

local function ApplyEditModeLayout(on)
    if not (_G.EllesmereUI and EllesmereUI.ApplyPresetEditMode) then return end

    if on then
        local data = ns.data and ns.data.Blizzard_EditMode_Lulu
        if type(data) ~= "string" or strtrim(data) == "" then
            print(ns.title .. ": No Lulu Edit Mode layout data yet. The rest of Lulu Mode still applies.")
            return
        end
        local name = ns.LuluLayoutName()
        -- Without this the write fails at five layouts and the message below
        -- blames Edit Mode not being open, which sends the user hunting in the
        -- wrong place. The rest of Lulu Mode still applies either way.
        if not ns.EditModeSlotFree(name) then
            print(ns.title .. ": Edit Mode layout limit reached (5), so Lulu's layout was skipped. Delete a layout and toggle Lulu again.")
            return
        end
        if not EllesmereUI.ApplyPresetEditMode(data, name) then
            print(ns.title .. ": Lulu Edit Mode import failed. Open Edit Mode once, then try again out of combat.")
        end
        return
    end

    -- Turning Lulu OFF restores the layout KitnUI put there, which means there
    -- has to be one. Without this check a user who never ran KitnUI's Edit Mode
    -- step gets KitnUI's layout written the first time they switch Lulu off, and
    -- their own Edit Mode arrangement replaced by one they never asked for.
    local installed = ns.db and ns.db.profiles and ns.db.profiles["Blizzard_EditMode"]
    if not installed then return end

    if type(ns.data and ns.data.Blizzard_EditMode) ~= "string" then return end

    if not ns.EditModeSlotFree(ns.profileName) then
        print(ns.title .. ": Edit Mode layout limit reached (5), so KitnUI's layout was not restored. Delete a layout and toggle Lulu again.")
        return
    end

    if not EllesmereUI.ApplyPresetEditMode(ns.data.Blizzard_EditMode, ns.profileName) then
        print(ns.title .. ": Restoring KitnUI's Edit Mode layout failed. Open Edit Mode once, then try again out of combat.")
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
        text = ns.title .. ": Turn Lulu Mode on?\n\nThis makes the minimap round, switches EllesmereUI's action bars off so Blizzard's own bars return, and applies the Lulu Edit Mode layout. Your UI will reload.\n\nEllesmereUI leaves Blizzard's four extra action bars switched on when it stands down. You can turn those off in Blizzard's own settings."
    else
        text = ns.title .. ": Turn Lulu Mode off?\n\nThis restores the minimap shape, switches EllesmereUI's action bars back on, and re-applies the standard KitnUI Edit Mode layout. Your UI will reload."
    end

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
                return
            end
            local s = ns.EUISettings()
            s.lulu = on and true or nil
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

-- Called by ns.EUIResetAll, which reloads straight afterwards. The re-apply
-- registry handles the minimap; these two are the parts a reload is required for,
-- and leaving them behind would strand the action bars off and the Lulu layout
-- active with the switch reading off and no record of either.
function ns.LuluTearDown()
    if not ns.LuluEnabled() then return end
    ApplyEditModeLayout(false)
    ApplyActionBarModule(false)
end
