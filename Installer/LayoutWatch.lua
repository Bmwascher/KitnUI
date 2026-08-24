-- ╔══════════════════════════════════════════════════════════════╗
-- ║  LayoutWatch.lua                                             ║
-- ║  Purpose: Sees when the current spec is not on KitnUI's      ║
-- ║           Edit Mode or Cooldown Manager layout, and offers   ║
-- ║           a one-click fix. Asks, never switches silently.    ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- Blizzard remembers the active Edit Mode layout PER SPECIALIZATION and the
-- installer only ever sets it for the spec that was current when the step ran,
-- so every other spec silently sits on whatever it was last left on. The
-- Cooldown Manager has the same shape with a self-heal of its own, which covers
-- everything except a spec whose previously-active layout is recorded as the
-- default.
--
-- Nothing here writes a layout on its own, and a reading that could not be taken
-- is silence rather than a prompt: prompting on a failed read nags a user whose
-- UI is already correct.

local DIALOG = "KITNUI_SPEC_LAYOUT"

-- [latchKey] = specIndex, written when the user ANSWERS and never when the
-- dialog merely appears: anything that hides a dialog without a button press
-- would otherwise be indistinguishable from pressing No.
-- A table rather than a single value because the key carries both verdicts, so
-- one spec can own more than one key across a session, and because a single slot
-- would be cleared by passing through a correctly configured spec -- which is
-- this feature's own user, rotating specs, being re-asked a question they have
-- already answered.
local held = {}

-- The generation of the most recently queued check. A queued callback that is no
-- longer the latest does nothing, so a burst of events still collapses into ONE
-- check, and that check runs the full delay after the LAST event rather than
-- after the first.
local checkGeneration = 0

local watcher = CreateFrame("Frame")

local RunCheck

-- Only the entries belonging to THIS spec. Deleting by value rather than by key
-- is what makes it complete: a spec prompted for Edit Mode alone and later for
-- both owns two keys, and clearing one would leave the other suppressing a
-- prompt the user never answered.
local function ClearSpecLatch(specIndex)
    for key, spec in pairs(held) do
        if spec == specIndex then held[key] = nil end
    end
end

-- A later event SUPERSEDES a queued check rather than being dropped by it.
-- Dropping breaks two promises at once: the surviving check can land less than
-- its own delay after the event that wanted it, and a queued RETRY would go on to
-- serve a different event while still spending that event's single retry.
local function QueueCheck(delay, fromRetry)
    checkGeneration = checkGeneration + 1
    local generation = checkGeneration
    C_Timer.After(delay, function()
        if generation ~= checkGeneration then return end
        RunCheck(fromRetry)
    end)
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------

-- "ok", "unknown" or "wrong".
--
-- Never installed is unknown, not wrong: a user who never ran the Edit Mode step
-- has no layout of ours and no interest in one. A wanted layout that no longer
-- exists is unknown too, because there is nothing to switch to and deleting it
-- was the user's right. So is a character the layout has never been applied to,
-- and that one is tested last because a character already on the layout proves
-- its own participation.
local function EditModeVerdict()
    local profiles = ns.db and ns.db.profiles
    if not profiles or profiles["Blizzard_EditMode"] ~= true then return "unknown" end

    local wanted
    if ns.EditModeTarget then wanted = select(2, ns.EditModeTarget()) end
    if type(wanted) ~= "string" then return "unknown" end

    local active = ns.ActiveEditModeLayout and ns.ActiveEditModeLayout()
    if active == nil then return "unknown" end

    if not (C_EditMode and C_EditMode.GetLayouts) then return "unknown" end
    local ok, info = pcall(C_EditMode.GetLayouts)
    if not (ok and type(info) == "table" and type(info.layouts) == "table") then return "unknown" end

    local present = false
    for _, entry in ipairs(info.layouts) do
        if type(entry) == "table" and entry.layoutName == wanted then
            present = true
            break
        end
    end
    if not present then return "unknown" end

    -- A number is a preset index and a string is a saved layout's name. Keeping
    -- the two apart is what lets a preset read as wrong without naming it.
    local verdict
    if type(active) == "number" then
        verdict = "wrong"
    else
        verdict = active == wanted and "ok" or "wrong"
    end

    if ns.HasEditModeApplied and ns:HasEditModeApplied() then return verdict end

    -- Unknown rather than wrong, so an unmarked character still reaches the
    -- clean path that clears stale latch entries and hides a stale dialog.
    if verdict ~= "ok" then return "unknown" end

    -- Already sitting on the layout IS participation, and for a character
    -- configured before the mark existed it is the only proof available. The
    -- cost is stated rather than hidden: such a character stays silent until it
    -- is next seen on a spec where the layout is active.
    --
    -- Unknown when the write did not happen. Answering ok would claim a mark
    -- that is not there, and the next check would read unmarked again.
    if not (ns.MarkEditModeApplied and ns:MarkEditModeApplied()) then return "unknown" end
    return "ok"
end

---------------------------------------------------------------------------------
-- Cooldown Manager
---------------------------------------------------------------------------------

-- "ok", "unknown" or "wrong", and on "wrong" the layout manager and the matching
-- layout id as well, because the fix needs both and nothing else produces them.
-- Neither handle may be carried across the dialog: see AcceptFix.
--
-- ns.GetCDMSpecState is what keeps this quiet for specs KitnUI never touched.
-- "current" and "stale" both mean a fingerprint is stored for this class and
-- spec, which only happens after an import; the other three all mean not ours.
local function CDMVerdict(classId, specIndex)
    local state = ns.GetCDMSpecState and ns.GetCDMSpecState(classId, specIndex)
    if state ~= "current" and state ~= "stale" then return "unknown" end

    if not (CooldownViewerSettings and CooldownViewerSettings.GetLayoutManager) then return "unknown" end
    local lm = CooldownViewerSettings:GetLayoutManager()
    if not lm then return "unknown" end
    if type(lm.EnumerateLayouts) ~= "function" or type(lm.GetActiveLayout) ~= "function" then
        return "unknown"
    end
    if type(CooldownManagerLayout_GetName) ~= "function" then return "unknown" end

    -- Guarded on the TABLE and tested against nil, never on the value:
    -- Enum.CDMLayoutMode.AccessOnly IS false, so a truthiness test would reject
    -- the enum every time it was present and this half would never speak.
    local modes = Enum and Enum.CDMLayoutMode
    if type(modes) ~= "table" or modes.AccessOnly == nil then return "unknown" end

    local wanted = ns.CDMLayoutName and ns.CDMLayoutName(classId, specIndex)
    if type(wanted) ~= "string" then return "unknown" end

    -- The current name only. A legacy layout is an import-time concern, and
    -- treating one as correct would suppress the prompt that gets the user onto
    -- the current layout.
    local _, layouts = lm:EnumerateLayouts()
    if type(layouts) ~= "table" then return "unknown" end

    local matchID
    for layoutID, layout in pairs(layouts) do
        if type(layout) == "table" and layout.layoutName == wanted then
            matchID = layoutID
            break
        end
    end
    if matchID == nil then return "unknown" end

    -- AccessOnly, never AllowCreate: AllowCreate makes the getter CREATE a layout
    -- as a side effect, which a read must never do.
    local active = lm:GetActiveLayout(modes.AccessOnly)
    local activeName = active and CooldownManagerLayout_GetName(active)
    if activeName == wanted then return "ok" end

    return "wrong", lm, matchID
end

---------------------------------------------------------------------------------
-- The prompt
---------------------------------------------------------------------------------

-- Applies whichever halves the dialog named, after proving they are still the
-- halves that are wrong. The dialog carries no timeout and the stale-dialog hide
-- only runs when a check runs, so without this there is a window in which a
-- prompt raised for the previous spec can still be accepted.
--
-- The handles come from THIS run, never from the build. A Cooldown Manager layout
-- deleted and re-imported while the dialog sat open keeps its NAME and gets a new
-- id, and a stale id does not refuse: SetActiveLayoutByID resolves it through
-- GetLayout, which answers nil, and the setter then reads a field off that nil.
-- That is a throw in a handler the user just clicked.
local function AcceptFix(builtSpec, builtEM, builtCDM)
    local classId = select(3, UnitClass("player"))
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        and C_SpecializationInfo.GetSpecialization()
    if type(classId) ~= "number" or type(specIndex) ~= "number" then return end
    if specIndex ~= builtSpec then return end

    local em = EditModeVerdict()
    local cdm, lm, layoutID = CDMVerdict(classId, specIndex)
    if em ~= builtEM or cdm ~= builtCDM then return end

    local editModeDone = false
    if em == "wrong" and ns.EditModeActivateWanted then
        editModeDone = ns.EditModeActivateWanted() == true
    end

    -- Edit Mode applies live, so an Edit Mode only fix ends here with no reload.
    if cdm ~= "wrong" then return end
    if not (ns.CDMSetActiveLayout and ns.CDMSetActiveLayout(lm, layoutID)) then return end

    -- The queue and the reload are one decision on one boolean. Queued lines drain
    -- at the NEXT login, so a line about a switch that did not happen would
    -- surface out of context, and false, in a session the user has no reason to
    -- connect to it.
    --
    -- Reached only through a "wrong" Cooldown Manager verdict, which CDMVerdict
    -- cannot return unless ns.CDMLayoutName already answered with a string.
    local specLabel = select(3, ns.CDMLayoutName(classId, specIndex))
    local line
    if editModeDone then
        line = ns.title .. ": " .. specLabel .. " is now using KitnUI's Edit Mode and Cooldown Manager layouts."
    else
        -- Edit Mode can be named in the prompt and still refuse, and the reload
        -- below destroys its refusal print. Naming both halves here would make
        -- the addon's only surviving statement about the click a false one.
        line = ns.title .. ": " .. specLabel .. " is now using KitnUI's Cooldown Manager layout."
    end
    ns.QueueMessage(line)
    ReloadUI()
end

-- Without this a user who deliberately runs a different layout on one spec is
-- asked once every session for ever, and the only way to stop it is to stop using
-- the feature.
--
-- The key is the one the check already validated, never a second read. A SILENT
-- failure here is the worst outcome available: the latch is already held, so the
-- button would look like it worked, and the prompt would come back at the next
-- login with nothing saved and no explanation.
local function OptOut(charKey, specIndex)
    if not ns.db then
        print(ns.title .. ": Could not save that choice, so it will be asked again.")
        ClearSpecLatch(specIndex)
        return
    end

    -- Written key by key. A fresh table would erase every other spec's opt-out on
    -- this character, which is the opposite of what the button promises. The
    -- character record is not guaranteed to exist either: three paths create it on
    -- demand and a character none of them has reached has none.
    ns.db.perChar = ns.db.perChar or {}
    local rec = ns.db.perChar[charKey]
    if not rec then
        rec = {}
        ns.db.perChar[charKey] = rec
    end
    rec.layoutWatchOff = rec.layoutWatchOff or {}
    rec.layoutWatchOff[specIndex] = true
end

-- True once the dialog is on screen. Built here rather than at file scope because
-- ns.title is not necessarily filled at load time.
--
-- The text names the spec and what is wrong, and never guesses why.
local function ShowPrompt(charKey, specLabel, specIndex, em, cdm, latchKey)
    local text
    if em == "wrong" and cdm == "wrong" then
        text = specLabel .. " is not using KitnUI's Edit Mode or Cooldown Manager layout. Switch to both now? This needs a reload."
    elseif cdm == "wrong" then
        text = specLabel .. " is not using KitnUI's Cooldown Manager layout. Switch to it now? This needs a reload."
    else
        text = specLabel .. " is not using KitnUI's Edit Mode layout. Switch to it now?"
    end

    -- Every button records the answer, and the show site records nothing.
    local function Answered()
        held[latchKey] = specIndex
    end

    StaticPopupDialogs[DIALOG] = {
        text = ns.title .. ": " .. text,
        button1 = "Yes",
        button2 = "No",
        button3 = "Never for this spec",
        -- Without this Blizzard routes the third button to OnAlt rather than to
        -- OnButton3. No other dialog in this addon has a third button, so it is
        -- stated here rather than inferred from a sibling.
        selectCallbackByIndex = true,
        OnAccept = function()
            Answered()
            AcceptFix(specIndex, em, cdm)
        end,
        -- There is deliberately NO OnCancel. Its absence is what routes the No
        -- button here and leaves Escape reaching nothing, so a dialog dismissed
        -- without an answer stays unanswered. It also closes the rejected-show
        -- hazard by construction: the two places Blizzard calls OnCancel with no
        -- dialog now call nothing at all, so a prompt the user never saw cannot
        -- write a latch or an opt-out.
        OnButton2 = function() Answered() end,
        -- The spec the dialog NAMES, not whatever is current when it is clicked:
        -- "never for this spec" is an answer to the sentence being read.
        --
        -- Latched before the write, because the write's own failure path clears
        -- this spec's entries so the user is asked again, and it can only clear
        -- an entry that is already there.
        OnButton3 = function()
            Answered()
            OptOut(charKey, specIndex)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    return StaticPopup_Show(DIALOG) ~= nil
end

---------------------------------------------------------------------------------
-- The check
---------------------------------------------------------------------------------

RunCheck = function(fromRetry)
    -- The identity the rest of this runs on. Anything but two numbers means the
    -- client is not ready, and then no layout is read and nothing is latched.
    local classId = select(3, UnitClass("player"))
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        and C_SpecializationInfo.GetSpecialization()
    if type(classId) ~= "number" or type(specIndex) ~= "number" then return end

    local charKey = ns.GetCharKey and ns.GetCharKey()
    if type(charKey) ~= "string" then return end

    -- Read before combat and before any layout: a user who said never must not be
    -- able to reach this prompt by any route. A character with no record is an
    -- ordinary state rather than an error, so this is a guarded chain.
    local rec = ns.db and ns.db.perChar and ns.db.perChar[charKey]
    local off = rec and rec.layoutWatchOff
    if off and off[specIndex] then
        ClearSpecLatch(specIndex)
        StaticPopup_Hide(DIALOG)
        return
    end

    if InCombatLockdown() then
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    local em = EditModeVerdict()
    -- The manager and the id this returns are deliberately dropped. The accept
    -- handler re-runs the check and uses the handles that run produces.
    local cdm = CDMVerdict(classId, specIndex)

    if em ~= "wrong" and cdm ~= "wrong" then
        ClearSpecLatch(specIndex)
        -- A dialog still up was raised for a state that no longer holds, and its
        -- accept handler carries the verdicts it was built with, so leaving it up
        -- lets the user apply the wrong fix.
        StaticPopup_Hide(DIALOG)
        return
    end

    local latchKey = specIndex .. ":" .. em .. ":" .. cdm
    if held[latchKey] then return end

    local specLabel = ns.CDMLayoutName and select(3, ns.CDMLayoutName(classId, specIndex))
    if type(specLabel) ~= "string" then return end

    if not ShowPrompt(charKey, specLabel, specIndex, em, cdm, latchKey) then
        -- A rejected show writes nothing: no latch, no opt-out, and the prompt is
        -- still owed. One retry, and a check reached BY that retry may not queue
        -- another -- without the budget a full dialog stack schedules a retry that
        -- is rejected, which schedules a retry, for ever.
        --
        -- Two seconds rather than one, and the reason is verification rather than
        -- behaviour: the first attempt lands about a second after the event, and a
        -- tester freeing a dialog slot by hand cannot reliably land inside a
        -- one-second window between the two.
        if not fromRetry then QueueCheck(2, true) end
        return
    end
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------

-- A unit event for the player, so a spec change on a party member's frame cannot
-- wake it. Blizzard's own Edit Mode manager registers it the same way.
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

watcher:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Behind the boot handler's own two-second drain and the dialogs it can
        -- raise. It does NOT guarantee a free dialog frame: those dialogs have no
        -- timeout and stay up until they are answered. It only makes a rejected
        -- show rarer.
        QueueCheck(3)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Never straight off the event. The client updates the active layout on
        -- its own handler for this same event, so reading in the same frame risks
        -- reading a value that is about to change and reporting a mismatch that
        -- is about to fix itself.
        QueueCheck(1)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Registered only while a check is owed, and dropped as soon as one runs.
        -- Nothing about the end of a fight makes the layout state easier to read,
        -- so it gets the same delay as the event it was deferred from.
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        QueueCheck(1)
    end
end)
