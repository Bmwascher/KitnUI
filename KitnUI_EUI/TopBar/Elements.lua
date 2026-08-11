-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/TopBar/Elements.lua                              ║
-- ║  Purpose: The top bar's element registry. Pure data plus     ║
-- ║           per-element handlers. No layout, no storage.       ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.TopBar = ns.TopBar or {}

-- One file per element, named after the element's own id, so adding an element
-- means adding one texture and nothing else. Verified present for all nineteen
-- icon-drawing elements on 2026-08-09.
local ICON_DIR = "Interface\\AddOns\\KitnUI_EUI\\Media\\TopBar\\"
local function Icon(id)
    return ICON_DIR .. "icon-" .. id .. ".tga"
end

-- A launcher's whole job is to click something Blizzard already owns. Secure,
-- because several of the targets are protected, and a macro is the only way to
-- reach them from a click the player made.
--
-- useOnKeyDown is forced false by Bar.lua on every secure element. Without it
-- the ActionButtonUseKeyDown CVar fires on key-down and the AnyUp click never
-- arrives, which presents as "the buttons randomly do not work for some users".
local function Macro(id, label, icon, panel, macrotext, requires)
    return {
        id = id, label = label, icon = icon, panel = panel,
        kind = "launcher", secure = true,
        attrs = function(btn)
            btn:SetAttribute("type1", "macro")
            btn:SetAttribute("macrotext1", macrotext)
        end,
        tooltip = function(tt) tt:AddLine(label, 1, 1, 1) end,
        requires = requires,
    }
end

---------------------------------------------------------------------------------
-- Home: the one launcher that is not a passthrough. Left click teleports home
-- via the "teleporthome" secure action type -- three attributes read straight
-- off the button (house-neighborhood-guid, house-guid, house-plot-id) that the
-- engine itself turns into C_Housing.TeleportHome(...); nothing here calls
-- that protected function directly
-- (.wow-api-reference/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua:620-629).
-- Right click opens the housing dashboard through the same helper the game's
-- own Housing micro button uses
-- (.wow-api-reference/Interface/AddOns/Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua:1012-1020).
--
-- C_Housing.GetPlayerOwnedHouses() is async: it answers through the
-- PLAYER_HOUSE_LIST_UPDATED event, not a return value
-- (.wow-api-reference/Interface/AddOns/Blizzard_HousingDashboard/Blizzard_HousingDashboardHouseInfoContent.lua:101-109).
-- The three field names on each list entry -- neighborhoodGUID, houseGUID,
-- plotID -- are read the same way Blizzard_HousingDashboardHouseUpgrade.lua:362
-- reads them before its own TeleportHome call. WindTools runs this identical
-- pattern already, including taking the first owned house with no further
-- selection UI (References/ElvUI_WindTools-v4.19/Modules/Misc/GameBar.lua:
-- 1461-1473, 1608-1610, 1647-1648) -- confirmation this addon is genuinely
-- 12.0-compatible, not just a plausible guess at the shape.
--
-- SetAttribute is protected, so cachedHouse is only ever written onto the
-- button from inside HomeAttrs, which WireSecureAttributes (Bar.lua) only
-- ever reaches outside combat: Apply() defers its whole protected half
-- whenever InCombatLockdown() is true.
local cachedHouse

local function RequestHouseList()
    if C_Housing and C_Housing.GetPlayerOwnedHouses then
        C_Housing.GetPlayerOwnedHouses()
    end
end

-- Is this the same house we already had? Wrapped in pcall because the two GUID
-- fields are WOWGUIDs, and comparing a Secret value throws rather than
-- answering. A comparison that cannot be made is treated as CHANGED: never a
-- missed re-wire, which is the direction that matters.
--
-- State the cost honestly, because the cheerful version of this sentence is
-- wrong. If the comparison throws it throws on EVERY event, not once. The
-- button re-requests the list from every hover, unthrottled, so the answer to
-- every hover would then drive a full Apply() -- exactly the loop this change
-- test exists to prevent. Correctness survives that (Apply is idempotent and
-- defers its protected half in combat); the cheapness does not. If the 12.0
-- semantics ever turn out to throw here, this needs a throttle, not a comment.
local function SameHouse(a, b)
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    local ok, same = pcall(function()
        return a.neighborhoodGUID == b.neighborhoodGUID
           and a.houseGUID == b.houseGUID
           and a.plotID == b.plotID
    end)
    return ok and same
end

local housingWatcher = CreateFrame("Frame")
housingWatcher:RegisterEvent("PLAYER_LOGIN")
housingWatcher:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
housingWatcher:SetScript("OnEvent", function(_, event, houseInfoList)
    if event == "PLAYER_LOGIN" then
        RequestHouseList()
        return
    end
    local house = nil
    local first = type(houseInfoList) == "table" and houseInfoList[1] or nil
    if first and first.neighborhoodGUID and first.houseGUID and first.plotID then
        house = first
    end

    -- THE FIX, and the whole reason left click did nothing. The house list is
    -- ASYNC: this event is the answer to a request made earlier. Caching the
    -- answer is not enough, because the only thing that writes the secure
    -- attributes is HomeAttrs, and the only thing that calls HomeAttrs is
    -- WireSecureAttributes, and the only thing that calls THAT is
    -- ns.TopBar.Apply(), in its protected half. Apply had already run, before
    -- the answer arrived, and found nothing cached -- so it cleared `type1` and
    -- never came back. The button then had no secure action at all.
    --
    -- That is also why it failed SILENTLY rather than printing the fallback:
    -- HomeOnClick only explains itself while `cachedHouse` is nil, and by the
    -- time the user clicks, it is set. Dead button, empty chat.
    --
    -- Apply() is safe to call in combat -- it defers its protected half and
    -- retries on PLAYER_REGEN_ENABLED -- so no combat gate here.
    -- The change test is what keeps this cheap: the button's OnEnter re-requests
    -- the list on every hover, and without it every hover would drive a full
    -- Apply.
    if SameHouse(house, cachedHouse) then return end
    cachedHouse = house
    if ns.TopBar and ns.TopBar.Apply then ns.TopBar.Apply() end
end)

-- Left click with nothing cached: an insecure fallback that explains why,
-- matching WindTools' own copy for the same state (GameBar.lua:741). Right
-- click always tries the dashboard; ToggleHousingDashboard is itself the
-- combat-agnostic helper Blizzard built for exactly this "call it from
-- outside the Housing addons" case, but the family's own hard rule still
-- applies to the panel toggle underneath it, so it is gated the same way
-- gamemenu gates GameMenuFrame above.
local function HomeOnClick(_self, button)
    if button == "RightButton" then
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
            return
        end
        if HousingFramesUtil and HousingFramesUtil.ToggleHousingDashboard then
            HousingFramesUtil.ToggleHousingDashboard()
        end
        return
    end
    if button == "LeftButton" and not cachedHouse then
        -- Split by cause: "no house yet" and "can't fetch mid-fight" are
        -- different problems with different fixes, and the brief's own copy
        -- conflated them.
        if InCombatLockdown() then
            print(ns.title .. ": house data cannot be updated in combat. Try again after this fight.")
        else
            print(ns.title .. ": no house found yet. If you own one, open the housing dashboard once and try again.")
        end
    end
end

-- WireSecureAttributes (Bar.lua) calls this every Apply(), always outside
-- combat. Clearing type1 when nothing is cached stops a stale partial
-- attribute set from firing a teleport to the wrong plot.
local function HomeAttrs(btn)
    if cachedHouse then
        btn:SetAttribute("type1", "teleporthome")
        btn:SetAttribute("house-neighborhood-guid", cachedHouse.neighborhoodGUID)
        btn:SetAttribute("house-guid", cachedHouse.houseGUID)
        btn:SetAttribute("house-plot-id", cachedHouse.plotID)
    else
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("house-neighborhood-guid", nil)
        btn:SetAttribute("house-guid", nil)
        btn:SetAttribute("house-plot-id", nil)
    end
    if not btn._homeWired then
        -- PostClick, NEVER OnClick. This is a SecureActionButtonTemplate, and
        -- that template performs its action FROM its OnClick script:
        -- `<OnClick function="SecureActionButton_OnClick"/>`
        -- (.wow-api-reference/Interface/AddOns/Blizzard_FrameXML/
        -- SecureTemplates.xml:8). Assigning our own OnClick REPLACED it, so
        -- the teleport action never ran at all -- and because our handler only
        -- explains itself while nothing is cached, a click after the house
        -- data had arrived did nothing and said nothing.
        --
        -- Home is the only secure element in this file that wants an insecure
        -- click behaviour of its own; every other one is a Macro() passthrough
        -- that sets attributes and leaves the template's script alone. That is
        -- exactly why home was the only launcher broken.
        --
        -- PostClick runs AFTER the secure action, alongside it rather than
        -- instead of it, which is what Blizzard's own action buttons use for
        -- insecure follow-up work (Blizzard_ActionBar/Mainline/
        -- ActionButtonTemplate.xml:178). Right click still reaches it because
        -- `type2` is never set, so the secure half is a no-op there.
        btn:SetScript("PostClick", HomeOnClick)
        -- Opportunistic refresh on hover, matching WindTools' ButtonOnEnter
        -- (GameBar.lua:1269-1271). HookScript ADDS to Bar.lua's own OnEnter
        -- (tint + tooltip) rather than replacing it.
        btn:HookScript("OnEnter", function()
            if not InCombatLockdown() then RequestHouseList() end
        end)
        btn._homeWired = true
    end
end

local homeElement = {
    id = "home", label = "Home", icon = Icon("home"), panel = "right",
    kind = "launcher", secure = true,
    attrs = HomeAttrs,
    tooltip = function(tt)
        tt:AddLine("Home", 1, 1, 1)
        tt:AddLine("Left-click: Teleport Home", 1, 1, 1)
        tt:AddLine("Right-click: Housing Dashboard", 1, 1, 1)
    end,
}

---------------------------------------------------------------------------------
-- Friends: no FriendsMicroButton exists in the Mainline micro menu (confirmed
-- against .wow-api-reference/Interface/AddOns/Blizzard_MicroMenu/Mainline/
-- MainMenuBarMicroButtons.xml, which lists Character/Profession/PlayerSpells/
-- Achievement/QuestLog/Housing/Guild/LFD/Collections/EJ/Help/Store/MainMenu
-- and nothing for friends), so this cannot be a Macro() passthrough the way
-- guild below is. ToggleFriendsFrame is the real global
-- (.wow-api-reference/Interface/AddOns/Blizzard_FriendsFrame/Mainline/
-- FriendsFrame.lua:1416), and it is not protected, so this is an insecure
-- toggle guarded the same way gamemenu and clock are above.
--
-- The badge (online count) and the roster tooltip are Readouts.lua's job --
-- everything with a ticker and cross-element state lives there. This element
-- only supplies the click and hands the tooltip off.
local friendsElement = {
    id = "friends", label = "Friends", icon = Icon("friends"), panel = "left",
    kind = "launcher", secure = false,
    onClick = function(_self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
            return
        end
        ToggleFriendsFrame()
    end,
    tooltip = function(tt)
        tt:AddLine("Friends", 1, 1, 1)
        if ns.TopBar.FriendsTooltip then ns.TopBar.FriendsTooltip(tt) end
    end,
}

-- Guild: GuildMicroButton DOES exist (Mainline/MainMenuBarMicroButtons.xml:183),
-- so this stays the ordinary Macro() passthrough every other micro-button
-- launcher in this file uses -- only its tooltip is replaced, because Macro()'s
-- own is a one-line label and this one needs the roster.
local guildElement = Macro("guild", "Guild", Icon("guild"), "left",
    "/click GuildMicroButton")
guildElement.tooltip = function(tt)
    tt:AddLine("Guild", 1, 1, 1)
    if ns.TopBar.GuildTooltip then ns.TopBar.GuildTooltip(tt) end
end

-- Great Vault: WeeklyRewardsFrame is load-on-demand, so opening it goes
-- through WeeklyRewards_ShowUI, the same global the rest of the client uses
-- to load and show it (.wow-api-reference/Interface/AddOns/Blizzard_UIParent/
-- Mainline/UIParent.lua:527-534). Not itself a secure/protected frame, but
-- gated the same way every other insecure launcher in this file is, for the
-- same reason gamemenu is.
local vaultElement = {
    id = "vault", label = "Great Vault", icon = Icon("vault"), panel = "right",
    kind = "launcher", secure = false,
    onClick = function(_self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
            return
        end
        WeeklyRewards_ShowUI()
    end,
    tooltip = function(tt)
        tt:AddLine("Great Vault", 1, 1, 1)
        if ns.TopBar.VaultTooltip then ns.TopBar.VaultTooltip(tt) end
    end,
}

---------------------------------------------------------------------------------
-- Hearthstone: three independently-configurable mouse buttons (tbHearthLeft/
-- Middle/Right), each set to a specific owned stone's item id or "RANDOM".
-- Pinned raw item ids rather than EllesmereUI.ResolveDalaranSlot: that
-- resolver conflates the Dalaran Hearthstone with the Key to the Arcantina
-- and prefers the key, so it can never hand back Dalaran once the key is
-- owned (References/EllesmereUI-v8.7.5/EllesmereUI/EllesmereUI.lua:5691-5696
-- has the two the wrong way round).
--
-- HEARTH_IDS is WindTools' own "hearthstones" table
-- (References/ElvUI_WindTools-v4.19/Modules/Misc/GameBar.lua:114-151), a
-- purpose-built subset of that file's own 51-entry superset
-- (GameBar.lua:153-217) -- not copied wholesale. Left out: the Engineering
-- Wormholes heading (a different mechanic, teleporting to a zone rather than
-- home, and KitnUI's own future portals element's job, not hearthstone's) and
-- the Patch Items heading minus the two ids the design doc's own defaults
-- require. The other three there -- Garrison Hearthstone (110560), Flight
-- Master's Whistle (141605), Translocation Cypher (180817) -- stay out:
-- EllesmereUI's own reverse-engineered model files Garrison Hearthstone in a
-- table explicitly separate from its shared-cooldown pool, "its own cooldown,
-- separate from the shared hearthstone one" (References/EllesmereUI-v8.7.5/
-- EllesmereUIDataBars/EllesmereUIDataBars_Blocks.lua:2468-2478), and neither
-- of the other two appears anywhere in either current 12.0 addon under
-- References/ (both being non-bind-point teleports rather than hearthstones).
--
-- 264367 (Mushroom) and 190237 (Broker Translocation Matrix) are current v4.19
-- WindTools does not know about but a v8.7.5 current-12.0 addon confirms are
-- genuine members of the shared cooldown pool: EllesmereUI's own
-- HEARTHSTONE_IDS (EllesmereUIDataBars_Blocks.lua:2453-2466, "Static
-- hearthstone pool (all expansions) shared by every instance") lists both.
-- 250411 (Timerunner's Hearthstone) was checked and deliberately left out: it
-- appears only in EllesmereUI.lua's separate portal-flyout pool (:5599), not
-- in that shared-cooldown table -- an inconsistency inside EllesmereUI itself
-- that this file is not going to resolve by guessing.
local HEARTH_IDS = {
    6948, 54452, 64488, 93672, 142542, 162973, 163045, 165669, 165670, 165802,
    166746, 166747, 168907, 172179, 180290, 182773, 183716, 184353, 188952,
    190196, 193588, 200630, 206195, 208704, 209035, 210455, 212337, 228940,
    235016, 236687, 245970, 246565, 257736, 263489, 263933, 265100,
    140192, 253629, 264367, 190237,
}

-- The ownership scan is the expensive part of this element and is paid once
-- (ScanOwned, run at PLAYER_LOGIN), then shared by all three dropdowns and
-- all three mouse buttons through these tables.
local owned = {}                           -- numeric item ids the player owns, scan order
local hearthValues = { RANDOM = "Random" } -- [stringKey] = display name; mutated in place as
                                            -- C_Item resolves names, which Options.lua's dropdown
                                            -- refresh reads live off this same table reference
local hearthOrder  = { "RANDOM" }          -- ordered stringKeys matching hearthValues
local hearthIcons  = {}                    -- [stringKey] = icon texture, for the dropdown's icon column
hearthValues._noLoc = true                 -- item/toy names are data, never localization keys
hearthValues._menuOpts = { icon = function(key) return hearthIcons[key] end }

-- Options.lua builds all three dropdowns off this one pair of tables, so the
-- ownership scan is never repeated per-dropdown.
function ns.TopBar.HearthValues()
    return hearthValues, hearthOrder
end

-- One reroll history per mouse button, so left/middle/right set to RANDOM
-- roll independently rather than sharing a single "last stone" memory.
local randomCache = {}

-- Avoids repeating the immediately previous roll when more than one stone is
-- owned. Bounded at 10 attempts, matching WindTools' own guard against a
-- pathological repeat (GameBar.lua:1732-1745); with only two owned stones the
-- odds of needing anywhere near that many are effectively zero.
local function PickRandom(slot)
    if #owned == 0 then return 6948 end
    if #owned == 1 then return owned[1] end
    local last = randomCache[slot]
    local id = owned[math.random(#owned)]
    for _ = 1, 10 do
        if id ~= last then break end
        id = owned[math.random(#owned)]
    end
    return id
end

-- `owned` is the numeric-item-id array ScanOwned populates -- not a set, so
-- this is a linear scan. HEARTH_IDS tops out at 39 entries, so the cost is
-- trivial and it is only ever paid from a click or an Apply(), never a tick.
local function IsOwned(id)
    for _, ownedID in ipairs(owned) do
        if ownedID == id then return true end
    end
    return false
end

-- A fixed setting resolves to its own id, PROVIDED the character actually
-- owns it. A stored id the scan does not find (the shipped default on a
-- character without it, or a stone since disenchanted/deleted) falls
-- through to the RANDOM path instead of resolving to a stone that cannot be
-- clicked -- otherwise the click silently does nothing and the tooltip and
-- dropdown are left showing a raw item id nobody can act on.
--
-- "RANDOM" (and now an unowned fixed id) resolves to whatever this slot last
-- rolled, WITHOUT rolling again here -- rolling on every call would mean an
-- unrelated Apply() (an opacity slider, say) silently swapped the stone
-- nobody clicked. Only RerollAll(), called from an actual click, advances it.
local function ResolveID(setting, slot)
    local id = tonumber(setting)
    if id and IsOwned(id) then return id end
    if not randomCache[slot] then randomCache[slot] = PickRandom(slot) end
    return randomCache[slot]
end

-- Rerolls every slot currently set to RANDOM. Called from PreClick, so each
-- click uses a freshly rolled stone and the immediately preceding roll is
-- never repeated -- "rerolls after use" in effect, since the only way to use
-- one roll is to trigger the next PreClick, which replaces it before firing.
local function RerollAll()
    if ns.TopBar.Get("tbHearthLeft", ns.EUI_DEFAULTS.tbHearthLeft) == "RANDOM" then
        randomCache.left = PickRandom("left")
    end
    if ns.TopBar.Get("tbHearthMiddle", ns.EUI_DEFAULTS.tbHearthMiddle) == "RANDOM" then
        randomCache.mid = PickRandom("mid")
    end
    if ns.TopBar.Get("tbHearthRight", ns.EUI_DEFAULTS.tbHearthRight) == "RANDOM" then
        randomCache.right = PickRandom("right")
    end
end

-- Toys must be used by name, not item:ID -- item:ID only resolves for
-- something actually in the bags, and a toy fired from the Toy Box, not the
-- bags, is exactly what most of HEARTH_IDS are
-- (References/NaowhUI-20260721.01/NaowhUI_EUI/NaowhUI_TopBar.lua:76-79).
local function MacroText(id)
    if not id then return "" end
    local toyName = C_ToyBox and C_ToyBox.GetToyInfo and select(2, C_ToyBox.GetToyInfo(id))
    if toyName then return "/use " .. toyName end
    return "/use item:" .. id
end

local function StoneLabel(id)
    if not id then return "Hearthstone" end
    return hearthValues[tostring(id)] or tostring(id)
end

-- The stone the left click currently resolves to. The tooltip reads THIS
-- id's own cooldown, not an assumed shared one: EllesmereUI's own
-- TRAVEL_EXTRAS table (EllesmereUIDataBars_Blocks.lua:2468-2478) shows the
-- Dalaran Hearthstone (140192) and Key to the Arcantina (253629) -- both
-- valid choices for any of the three slots here -- run on cooldowns separate
-- from the main HEARTHSTONE_IDS pool. Querying the resolved id directly,
-- rather than assuming one shared category, is correct regardless of which
-- pool it actually belongs to; it just means the tooltip only ever reflects
-- the LEFT slot's cooldown, not Middle/Right's, if those differ (matching
-- NaowhUI's own single-id tooltip reading, NaowhUI_TopBar.lua:259-270, which
-- has the same scope).
local _hearthId

local function FmtCD(sec)
    sec = math.floor(sec + 0.5)
    if sec >= 3600 then
        return format("%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
    end
    return format("%d:%02d", sec / 60, sec % 60)
end

-- C_Item.GetItemCooldown's returns carry no SecretReturnsForAspect entry in
-- the generated API docs, unlike a Cooldown WIDGET's own GetCooldownTimes /
-- GetCooldownDuration (those ARE marked Enum.SecretAspect.Cooldown). This
-- reads the item API, never a Cooldown frame, so the arithmetic below is safe.
local function HearthCooldownRemaining()
    if not _hearthId then return nil end
    if not (C_Item and C_Item.GetItemCooldown) then return nil end
    local start, duration = C_Item.GetItemCooldown(_hearthId)
    if type(start) == "number" and type(duration) == "number" and duration > 0 then
        local remaining = start + duration - GetTime()
        if remaining > 0 then return remaining end
    end
    return nil
end

local function HearthTooltip(tt)
    tt:AddLine("Hearthstone", 1, 1, 1)
    local remaining = HearthCooldownRemaining()
    if remaining then
        tt:AddDoubleLine("Cooldown", FmtCD(remaining), 0.7, 0.7, 0.7, 1, 0.3, 0.3)
    else
        tt:AddDoubleLine("Cooldown", "Ready", 0.7, 0.7, 0.7, 0.3, 1, 0.3)
    end
    tt:AddLine(" ")
    tt:AddLine("Left-click: " .. StoneLabel(ResolveID(
        ns.TopBar.Get("tbHearthLeft", ns.EUI_DEFAULTS.tbHearthLeft), "left")), 1, 1, 1)
    tt:AddLine("Middle-click: " .. StoneLabel(ResolveID(
        ns.TopBar.Get("tbHearthMiddle", ns.EUI_DEFAULTS.tbHearthMiddle), "mid")), 1, 1, 1)
    tt:AddLine("Right-click: " .. StoneLabel(ResolveID(
        ns.TopBar.Get("tbHearthRight", ns.EUI_DEFAULTS.tbHearthRight), "right")), 1, 1, 1)
end

-- Forward-declared: the defer watcher below closes over it before it is
-- assigned, and by the time PLAYER_REGEN_ENABLED can actually fire, the
-- assignment further down has long since run.
local HearthAttrs

-- "The Random reroll... rewrites the macro after use: defer it out of combat
-- rather than dropping it" -- a PreClick that finds InCombatLockdown() true
-- cannot write the reroll now, but must not forget it either, or the button
-- would keep firing a stale roll until some later click happens to land
-- outside combat. This is Bar.lua's own Defer()/pendingApply shape, scoped
-- down to this one button.
local hearthDeferPending, hearthDeferBtn = false, nil
local hearthDeferFrame = CreateFrame("Frame")
hearthDeferFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    hearthDeferPending = false
    if hearthDeferBtn then
        RerollAll()
        HearthAttrs(hearthDeferBtn)
    end
end)

local function DeferHearthRefresh(btn)
    hearthDeferBtn = btn
    if hearthDeferPending then return end
    hearthDeferPending = true
    hearthDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- WireSecureAttributes (Bar.lua) calls this every Apply(), always outside
-- combat, so the writes below need no InCombatLockdown() guard of their own
-- -- exactly HomeAttrs' own reasoning above. The PreClick it wires the first
-- time through DOES need one: a click can happen independently of any Apply().
HearthAttrs = function(btn)
    local leftID  = ResolveID(ns.TopBar.Get("tbHearthLeft",   ns.EUI_DEFAULTS.tbHearthLeft),   "left")
    local rightID = ResolveID(ns.TopBar.Get("tbHearthRight",  ns.EUI_DEFAULTS.tbHearthRight),  "right")
    local midID   = ResolveID(ns.TopBar.Get("tbHearthMiddle", ns.EUI_DEFAULTS.tbHearthMiddle), "mid")
    _hearthId = leftID

    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("macrotext1", MacroText(leftID))
    btn:SetAttribute("type2", "macro")
    btn:SetAttribute("macrotext2", MacroText(rightID))
    btn:SetAttribute("type3", "macro")
    btn:SetAttribute("macrotext3", MacroText(midID))

    if not btn._hearthWired then
        -- Toy names may not be cached at login, so every click re-resolves
        -- all three macros fresh rather than trusting whatever Apply() last
        -- wrote, exactly as NaowhUI_TopBar.lua:616-622 does.
        btn:SetScript("PreClick", function(self)
            if InCombatLockdown() then
                DeferHearthRefresh(self)
                return
            end
            RerollAll()
            HearthAttrs(self)
        end)

        -- Live cooldown countdown while hovering. A dedicated ticker rather
        -- than Bar.lua's per-second one: this task's files are Elements.lua
        -- and Options.lua only, and Readouts.lua's own ticker is file-local.
        -- Started on OnEnter, cancelled on OnLeave, so it never runs while
        -- nothing is being hovered.
        local function CancelHearthTicker(self)
            if self._hearthTicker then
                self._hearthTicker:Cancel()
                self._hearthTicker = nil
            end
        end
        btn:HookScript("OnEnter", function(self)
            -- Bar.lua's own OnEnter returns before calling el.tooltip when
            -- tbTooltips is off, but this ticker is wired independently of
            -- that call, so without the same check here it would spin every
            -- 0.5s for as long as the pointer sits on the button, unable to
            -- ever do anything -- gated to match the volume ticker below,
            -- which gets this for free by starting from inside its own
            -- tooltip function instead of an OnEnter hook.
            if not ns.TopBar.Get("tbTooltips", ns.EUI_DEFAULTS.tbTooltips) then return end
            self._hearthTicker = C_Timer.NewTicker(0.5, function()
                if GameTooltip:IsOwned(self) then
                    GameTooltip:ClearLines()
                    HearthTooltip(GameTooltip)
                    GameTooltip:Show()
                end
            end)
        end)
        btn:HookScript("OnLeave", CancelHearthTicker)
        -- A hidden frame does not reliably get OnLeave, and switching the
        -- element off in the ELEMENTS list while hovering it does exactly
        -- that. Without this the tooltip ticker outlives the button for the
        -- rest of the session.
        btn:HookScript("OnHide", CancelHearthTicker)
        btn._hearthWired = true
    end
end

-- Nil-guarded: the bar (and this button) may not exist yet -- the feature can
-- be switched off, or ScanOwned's async name/icon callbacks can land before
-- Apply() has ever built anything. Combat-guarded because this writes secure
-- attributes; ScanOwned only ever runs from PLAYER_LOGIN and an item-load
-- callback, neither of which is realistically mid-combat, but the family's
-- own hard rule applies regardless of how unlikely the timing is.
local function RefreshHearthButton()
    local btn = _G.KitnUITopBar_hearthstone
    if not btn then return end
    if InCombatLockdown() then return end
    HearthAttrs(btn)
end

-- Filters HEARTH_IDS down to what this character actually owns. Names and
-- icons resolve asynchronously (Item:ContinueOnItemLoad), so each one re-runs
-- RefreshHearthButton once it lands rather than leaving the button (and any
-- open dropdown, which reads hearthValues/hearthIcons by the same reference
-- Options.lua was handed) stuck on a raw id.
local function ScanOwned()
    for _, id in ipairs(HEARTH_IDS) do
        local isToy = PlayerHasToy and PlayerHasToy(id)
        local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)
        if isToy or (count and count > 0) then
            owned[#owned + 1] = id
            local key = tostring(id)
            hearthValues[key] = key
            hearthOrder[#hearthOrder + 1] = key

            if Item then
                local item = Item:CreateFromItemID(id)
                item:ContinueOnItemLoad(function()
                    hearthValues[key] = item:GetItemName() or key
                    hearthIcons[key]  = item:GetItemIcon()
                    RefreshHearthButton()
                end)
            end
        end
    end
    RefreshHearthButton()
end

local hearthScanWatcher = CreateFrame("Frame")
hearthScanWatcher:RegisterEvent("PLAYER_LOGIN")
hearthScanWatcher:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    ScanOwned()
end)

local hearthstoneElement = {
    id = "hearthstone", label = "Hearthstone", icon = Icon("hearthstone"), panel = "right",
    kind = "launcher", secure = true,
    attrs = HearthAttrs,
    tooltip = HearthTooltip,
}

---------------------------------------------------------------------------------
-- Mythic+ Portals: a secure flyout of this season's dungeon teleports, parented
-- to the portals launcher button. Modelled directly on
-- References/NaowhUI-20260721.01/NaowhUI_EUI/NaowhUI_Portals.lua:178-296, the
-- one current-12.0 addon in References/ that already solves this exact
-- combat-safe-flyout problem.
--
-- EllesmereUI.SEASON_PORTALS belongs to the host, not to us, and its own
-- comment (EllesmereUI.lua:295-296) says it is updated once per season.
-- Reading it fresh here, on every requires() and CreateFlyout() call, rather
-- than snapshotting it once at file scope the way NaowhUI does (its own
-- comment, Portals.lua:13-14, leans on EllesmereUI being a hard dependency
-- that is already loaded before it), means a season boundary where the
-- host's list is briefly missing or empty degrades to "no portals button"
-- instead of a frozen empty grid baked in at whatever KitnUI_EUI's own load
-- time happened to see.
local function SeasonPortals()
    local EUI = _G.EllesmereUI
    local list = EUI and EUI.SEASON_PORTALS
    if type(list) ~= "table" or #list == 0 then return nil end
    return list
end

local PORTAL_BTN_SIZE, PORTAL_SPACING, PORTAL_PADDING, PORTAL_COLS = 32, 2, 4, 4

local portalFlyout, portalFlyoutBtns

-- Desaturates unknown teleports and keeps cooldown swipes current. known
-- comes from C_SpellBook.IsSpellKnown, which carries no secret marker in
-- SpellBookDocumentation.lua:684-699 (unlike the deprecated global
-- IsPlayerSpell NaowhUI's own copy uses, which only exists at all behind the
-- loadDeprecationFallbacks CVar -- Deprecated_SpellBook.lua:4,11-14 -- so it
-- is not safe to depend on here).
--
-- C_Spell.GetSpellCooldown IS a secret-value risk: its own doc entry carries
-- SecretWhenCooldownsRestricted = true (SpellDocumentation.lua:249-253), and
-- the SpellCooldownInfo it returns does NOT mark startTime or duration
-- NeverSecret (SpellSharedDocumentation.lua:19-31) -- only isEnabled,
-- isActive and isOnGCD are. So this never compares or does arithmetic on
-- startTime/duration; it branches on isActive (NeverSecret) instead, and
-- hands startTime/duration to Cooldown:SetCooldown untouched -- SetCooldown's
-- own "start"/"duration" arguments are explicitly built to accept secret
-- values (SecretArgumentsAddAspect = { Enum.SecretAspect.Cooldown },
-- FrameAPICooldownDocumentation.lua:280-283): the widget can paint a swipe
-- from an opaque cooldown without this file ever reading the real numbers.
local function RefreshPortalButtons()
    if not portalFlyoutBtns then return end
    for _, btn in ipairs(portalFlyoutBtns) do
        local spellID = btn.spellID
        local known = C_SpellBook and C_SpellBook.IsSpellKnown
            and C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player)
        if btn._lastKnown ~= known then
            btn._lastKnown = known
            btn.icon:SetDesaturated(not known)
            btn.icon:SetAlpha(known and 1 or 0.4)
        end
        local cd = known and C_Spell and C_Spell.GetSpellCooldown
            and C_Spell.GetSpellCooldown(spellID)
        if type(cd) == "table" and cd.isActive then
            btn.cooldown:SetCooldown(cd.startTime, cd.duration)
        else
            btn.cooldown:Clear()
        end
    end
end

-- Built once, lazily, on the first click -- never from Apply(). Checks
-- SeasonPortals() again rather than trusting the caller: TogglePortalFlyout
-- only ever reaches this after requires() has already passed once to show
-- the launcher button at all, but a stale or nil list here would build an
-- empty, useless flyout instead of failing safely.
local function CreatePortalFlyout()
    if portalFlyout then return portalFlyout end
    local portals = SeasonPortals()
    if not portals then return nil end

    local rows = math.ceil(#portals / PORTAL_COLS)
    local w = PORTAL_PADDING * 2 + PORTAL_BTN_SIZE * PORTAL_COLS + PORTAL_SPACING * (PORTAL_COLS - 1)
    local h = PORTAL_PADDING * 2 + PORTAL_BTN_SIZE * rows + PORTAL_SPACING * (rows - 1)

    -- SecureHandlerStateTemplate with a CUSTOM state, not "visibility": a
    -- visibility state driver owns Show/Hide outright, so it would force this
    -- flyout open again the instant combat ends. This state only ever closes
    -- it -- on the way out of combat it does nothing, so a flyout the player
    -- closed (or never opened) stays closed. Exactly
    -- NaowhUI_Portals.lua:186-209's own shape. Needed at all because this
    -- frame is about to parent secure buttons: once it does, an ordinary
    -- Hide() call on it from Lua is protected, the same rule Bar.lua's own
    -- HideBar() is built around.
    portalFlyout = CreateFrame("Frame", "KitnUITopBar_portalsFlyout", UIParent,
        "SecureHandlerStateTemplate")
    portalFlyout:SetSize(w, h)
    portalFlyout:SetFrameStrata("DIALOG")
    -- Level as well as strata, matching NaowhUI_Portals.lua:191. Strata alone
    -- leaves the default level inside DIALOG, so another dialog-strata frame
    -- can draw over the flyout.
    portalFlyout:SetFrameLevel(100)
    portalFlyout:SetClampedToScreen(true)
    portalFlyout:Hide()

    local bg = portalFlyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    -- Deliberately NOT the reference's 0.04/0.04/0.06 (NaowhUI_Portals.lua:197).
    -- This is Bar.lua's own panel colour (Bar.lua:214, :358): the flyout has to
    -- match the bar it hangs off, and NaowhUI's value matches NaowhUI's bar.
    bg:SetColorTexture(0.03, 0.03, 0.04, 0.95)

    -- The host's border, when the host offers it. Same nil-guarded shape the
    -- reference uses (NaowhUI_Portals.lua:199-202). Note the colour differs
    -- between the two call sites on purpose, and the reference does the same:
    -- the FLYOUT gets a faint white hairline (1,1,1 at 0.06) so the panel edge
    -- reads against the dark backdrop, while each BUTTON below gets opaque
    -- black to separate the icons from each other.
    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.CreateBorder then
        PP.CreateBorder(portalFlyout, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
    end

    portalFlyout:SetAttribute("_onstate-combat", [[
        if newstate == "in" then self:Hide() end
    ]])
    RegisterStateDriver(portalFlyout, "combat", "[combat] in; out")

    portalFlyoutBtns = {}
    for i, entry in ipairs(portals) do
        local spellID = entry and entry.spellID
        if spellID then
            local col = (i - 1) % PORTAL_COLS
            local row = math.floor((i - 1) / PORTAL_COLS)

            -- SecureActionButtonTemplate: the SetAttribute pair below is a
            -- protected write, safe here only because CreateFlyout is only
            -- ever reached from TogglePortalFlyout, which already refused in
            -- combat before calling it.
            local btn = CreateFrame("Button", nil, portalFlyout, "SecureActionButtonTemplate")
            btn:SetSize(PORTAL_BTN_SIZE, PORTAL_BTN_SIZE)
            btn:SetPoint("TOPLEFT", portalFlyout, "TOPLEFT",
                PORTAL_PADDING + col * (PORTAL_BTN_SIZE + PORTAL_SPACING),
                -(PORTAL_PADDING + row * (PORTAL_BTN_SIZE + PORTAL_SPACING)))
            btn.spellID = spellID

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(6 / 64, 58 / 64, 6 / 64, 58 / 64)
            local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            if si and si.iconID then icon:SetTexture(si.iconID) end
            btn.icon = icon

            -- Per button too, opaque black, matching NaowhUI_Portals.lua:230-232.
            if PP and PP.CreateBorder then
                PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
            end

            local cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
            cooldown:SetAllPoints()
            cooldown:SetHideCountdownNumbers(true)
            cooldown:SetDrawSwipe(true)
            cooldown:SetDrawBling(false)
            cooldown:SetDrawEdge(false)
            btn.cooldown = cooldown

            -- AnyUp AND AnyDown, matching NaowhUI_Portals.lua:257, instead of
            -- Bar.lua's own useOnKeyDown=false fix for the same
            -- ActionButtonUseKeyDown CVar problem: these buttons are never
            -- reached by WireSecureAttributes (they are not in
            -- ns.TopBar.ById), so there is no per-Apply moment to set that
            -- attribute on them the way Bar.lua does for every registered
            -- launcher.
            btn:RegisterForClicks("AnyUp", "AnyDown")
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", spellID)

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spellID)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            portalFlyoutBtns[#portalFlyoutBtns + 1] = btn
        end
    end

    portalFlyout:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        RefreshPortalButtons()
    end)
    portalFlyout:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    portalFlyout:SetScript("OnEvent", function() RefreshPortalButtons() end)

    -- Escape closes it like any other free-floating panel. Nil-guarded: the
    -- helper is EllesmereUI's own (EllesmereUI.lua:12157, backed by a single
    -- UISpecialFrames proxy at :12134-12136), not ours, so a future host
    -- version that renamed or dropped it must not error here.
    if EllesmereUI and EllesmereUI.RegisterEscapeClose then
        EllesmereUI.RegisterEscapeClose(portalFlyout)
    end

    return portalFlyout
end

-- Hide() on the flyout is protected once it holds secure buttons (see the
-- comment on CreatePortalFlyout above), so this whole toggle -- both the
-- Show and the Hide branch -- has to happen outside combat.
local function TogglePortalFlyout(anchorBtn)
    if InCombatLockdown() then return end
    local fly = CreatePortalFlyout()
    if not fly then return end
    if fly:IsShown() then
        fly:Hide()
        return
    end

    -- Wired once per launcher button, the first time it ever opens the
    -- flyout. HookScript, not SetScript: SetScript would REPLACE whatever
    -- OnHide handler already lives on this button; HookScript only adds to
    -- it, so this cannot silently discard behaviour some other file wires
    -- onto the same frame later. A child's OnHide fires whenever its parent
    -- is hidden, not only on a direct Hide() call against the child itself,
    -- so hooking the LAUNCHER button's OnHide catches every path that makes
    -- the button disappear out from under an open flyout: HideBar() hiding
    -- the whole bar when tbEnabled goes off, LayoutSide hiding this one
    -- button when portals is switched off in tbOff, and Task 8's visibility
    -- work later. In each of those the button is simply gone -- no combat
    -- transition fires the state driver above, and Escape has nothing left
    -- to close -- so without this the flyout would sit on screen until the
    -- player entered combat once or reloaded.
    --
    -- This is a hook on the BUTTON, not a reparent of the FLYOUT under it.
    -- Hiding a parent only hides a child visually; it does not flip the
    -- child's own IsShown() to false. A flyout reparented under the launcher
    -- would look closed while still reporting itself open, and would pop
    -- back into view the instant the button (and the bar) were shown again
    -- -- the exact bug the custom "combat" state above exists to prevent,
    -- and what smoke check F3 tests for. Hooking OnHide and calling a real
    -- Hide() on the flyout itself has no such trap.
    if not anchorBtn._portalFlyoutHideHooked then
        anchorBtn._portalFlyoutHideHooked = true
        anchorBtn:HookScript("OnHide", function()
            -- Combat-guarded like every other manual Hide() call on this
            -- frame: once it parents secure buttons, Hide() on it is
            -- protected, and in combat the state driver has already closed
            -- it by the time this could ever fire from a bar/button hide.
            if portalFlyout and portalFlyout:IsShown() and not InCombatLockdown() then
                portalFlyout:Hide()
            end
        end)
    end

    fly:ClearAllPoints()
    fly:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -4)
    fly:Show()
end

local portalsElement = {
    id = "portals", label = "Mythic+ Portals", icon = Icon("portals"), panel = "right",
    kind = "launcher", secure = false,
    onClick = function(self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
            return
        end
        TogglePortalFlyout(self)
    end,
    tooltip = function(tt) tt:AddLine("Mythic+ Portals", 1, 1, 1) end,
    -- SEASON_PORTALS is EllesmereUI's, and it moves every season. Absent
    -- entirely rather than a button that opens an empty grid -- the same
    -- shape kitnessentials below uses for "the dependency is not there right
    -- now".
    requires = function() return SeasonPortals() and true or false end,
}

---------------------------------------------------------------------------------
-- Volume: left click +10% master volume, right click -10%, middle click
-- toggles mute. Sound_MasterVolume and Sound_EnableAllSound are the same pair
-- WindTools' own volume launcher drives
-- (References/ElvUI_WindTools-v4.19/Modules/Misc/GameBar.lua:869-916), and
-- both are still live Mainline cvars (Blizzard_SettingsDefinitions_Shared/
-- Audio.lua:388,415). No InCombatLockdown gate, unlike every other launcher
-- in this file: those guard against opening a Blizzard panel mid-fight; this
-- only ever calls SetCVar on an audio cvar, which carries no protected or
-- secure marker in CVarDocumentation.lua and is safe to call at any time.
local function VolumePercent()
    local v = tonumber(C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("Sound_MasterVolume"))
    return v or 0
end

local function VolumeSetPercent(v)
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar("Sound_MasterVolume", v) end
end

local function VolumeToggleMute()
    if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then return end
    local enabled = tonumber(C_CVar.GetCVar("Sound_EnableAllSound")) == 1
    C_CVar.SetCVar("Sound_EnableAllSound", enabled and 0 or 1)
end

local function VolumeTooltip(tt)
    tt:AddLine("Volume", 1, 1, 1)
    tt:AddDoubleLine("Master", format("%d%%", VolumePercent() * 100), 0.7, 0.7, 0.7, 1, 1, 1)
    tt:AddLine(" ")
    tt:AddLine("Left-click: +10%", 1, 1, 1)
    tt:AddLine("Right-click: -10%", 1, 1, 1)
    tt:AddLine("Middle-click: Mute", 1, 1, 1)
end

-- Live percentage while hovered, the same ticker shape HearthTooltip's own
-- uses above (0.5s, IsOwned-guarded, cancelled on OnLeave AND OnHide so a
-- button hidden mid-hover cannot leak the ticker the way Task 6 originally
-- did). volume has no attrs() -- it is not secure -- so there is no per-Apply
-- moment to wire this the way HearthAttrs wires its own ticker; wiring it
-- from inside the tooltip function itself, keyed off the stable button name
-- Bar.lua always creates, reaches the same end state without one.
--
-- The ticker itself is started here too, synchronously, not only from the
-- OnEnter hook below: a HookScript added while an OnEnter is already running
-- does not fire again for that same hover (the engine has already invoked
-- the handler chain it had when the hover began), so hooking alone is only
-- good enough for OnLeave/OnHide -- later events that have not fired yet --
-- never for a live reading on the very first hover.
local function VolumeCancelTicker(self)
    if self._volumeTicker then
        self._volumeTicker:Cancel()
        self._volumeTicker = nil
    end
end

-- 0.5s, deliberately slower than WindTools' 0.3s (GameBar.lua:899). The
-- readout is a whole-number percentage the user is actively dragging; a third
-- of a second buys nothing visible and costs more ticks.
local function VolumeStartTicker(btn)
    if btn._volumeTicker then return end
    btn._volumeTicker = C_Timer.NewTicker(0.5, function()
        if GameTooltip:IsOwned(btn) then
            GameTooltip:ClearLines()
            VolumeTooltip(GameTooltip)
            GameTooltip:Show()
        end
    end)
end

local function VolumeWireButton(btn)
    if btn._volumeWired then return end
    btn:HookScript("OnLeave", VolumeCancelTicker)
    btn:HookScript("OnHide", VolumeCancelTicker)
    btn._volumeWired = true
end

local volumeElement = {
    id = "volume", label = "Volume", icon = Icon("volume"), panel = "right",
    kind = "launcher", secure = false,
    onClick = function(_self, button)
        if button == "LeftButton" then
            VolumeSetPercent(VolumePercent() + 0.1)
        elseif button == "RightButton" then
            VolumeSetPercent(VolumePercent() - 0.1)
        elseif button == "MiddleButton" then
            VolumeToggleMute()
        end
    end,
    tooltip = function(tt)
        local btn = _G.KitnUITopBar_volume
        if btn then
            VolumeWireButton(btn)
            VolumeStartTicker(btn)
        end
        VolumeTooltip(tt)
    end,
}

ns.TopBar.Elements = {
    friendsElement,
    guildElement,

    Macro("groupfinder", "Group Finder", Icon("groupfinder"), "left",
        "/click LFDMicroButton"),

    Macro("journal", "Encounter Journal", Icon("journal"), "left",
        "/click EJMicroButton"),

    Macro("achievements", "Achievements", Icon("achievements"), "left",
        "/click AchievementMicroButton"),

    -- No `collections` element here. It opened the Collections journal on
    -- whatever tab was last used, which is the same WINDOW `toybox` opens --
    -- two icons for one journal. Removed on Kitn's call, and `toybox` is the
    -- one kept because it lands somewhere definite.
    --
    -- Toy Box is a tab inside the Collections journal, not its own micro
    -- button. Click the micro button to open the journal,
    -- then select the Toy Box tab (index 3, matching
    -- Blizzard_Collections.lua's own titles[3] = TOY_BOX) on the line after:
    -- /click runs its OnClick synchronously, so the journal already exists
    -- and is shown by the time the second line runs.
    Macro("toybox", "Toy Box", Icon("toybox"), "left",
        "/click CollectionsMicroButton\n/run CollectionsJournal_SetTab(CollectionsJournal, 3)"),

    hearthstoneElement,
    portalsElement,
    homeElement,
    vaultElement,

    Macro("character", "Character", Icon("character"), "right",
        "/click CharacterMicroButton"),

    -- No SpellbookMicroButton exists on Mainline: the 12.0 client folded the
    -- spellbook into a tab of PlayerSpellsFrame (the same frame `talents`
    -- opens), reachable only through PlayerSpellsUtil.OpenToSpellBookTab()
    -- (.wow-api-reference/Interface/AddOns/Blizzard_FrameXMLUtil/Mainline/PlayerSpellsUtil.lua:49).
    -- The brief's own instruction to verify micro-button names rather than
    -- trust the table applies here: the table's `/click SpellbookMicroButton`
    -- would silently do nothing, because that global no longer exists.
    Macro("spellbook", "Spellbook", Icon("spellbook"), "right",
        "/run PlayerSpellsUtil.OpenToSpellBookTab()"),

    Macro("talents", "Talents", Icon("talents"), "right",
        "/click PlayerSpellsMicroButton"),

    Macro("professions", "Professions", Icon("professions"), "right",
        "/click ProfessionMicroButton"),

    volumeElement,

    Macro("euiconfig", "EllesmereUI", Icon("euiconfig"), "right",
        "/run if EllesmereUI and EllesmereUI.Toggle then EllesmereUI:Toggle() end"),

    -- Absent entirely, not greyed out, when KitnEssentials is not loaded.
    Macro("kitnessentials", "KitnEssentials", Icon("kitnessentials"), "right", "/kes",
        function()
            return C_AddOns and C_AddOns.IsAddOnLoaded
               and C_AddOns.IsAddOnLoaded("KitnEssentials") and true or false
        end),

    -- Not a macro passthrough: /click GameMenuButtonLogout is wrong (that
    -- button logs out), so this toggles GameMenuFrame directly and refuses in
    -- combat rather than relying on secure attribute handling.
    {
        id = "gamemenu", label = "Game Menu", icon = Icon("gamemenu"), panel = "right",
        kind = "launcher", secure = false,
        onClick = function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
                return
            end
            if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame)
            else ShowUIPanel(GameMenuFrame) end
        end,
        tooltip = function(tt) tt:AddLine("Game Menu", 1, 1, 1) end,
    },

    -- Clock: the centre panel's only occupant (DEFAULT_ORDER.centre), never
    -- switched off, so Options.lua excludes it from the ELEMENTS list by id
    -- rather than this element declining a toggle. Bar.lua creates its button
    -- as "KitnUITopBar_clock" the same as any other element; Readouts.lua
    -- reaches that stable global name to attach the actual time FontString
    -- and to size it from tbClockSize, since neither the button table nor
    -- centrePanel is part of this file's interface. Left click opens the
    -- calendar, middle click reloads; both are insecure (ToggleCalendar and
    -- ReloadUI need no protection) and refuse in combat like gamemenu above.
    {
        id = "clock", label = "Clock", panel = "centre",
        kind = "readout", secure = false,
        onClick = function(_self, button)
            if button ~= "LeftButton" and button ~= "MiddleButton" then return end
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
                return
            end
            if button == "LeftButton" then
                ToggleCalendar()
            else
                ReloadUI()
            end
        end,
        tooltip = function(tt)
            tt:AddLine("Left-click: Calendar", 1, 1, 1)
            tt:AddLine("Middle-click: Reload UI", 1, 1, 1)
        end,
    },

    -- fps: never laid out in a panel — it lives on its own UIParent frame,
    -- positioned against the clock rather than with the icons, per the panel
    -- field's own contract above ("nil means the element is NOT laid out by
    -- a panel: it anchors itself. fps is the only one"). Bar.lua's
    -- EnsureCreated now skips CreateElementButton for any element with no
    -- panel, so this stays out of leftPanel/rightPanel entirely; it is
    -- present here only so the ELEMENTS list picks it up automatically.
    -- Never add "fps" to any tbOrder array — it is not laid out.
    {
        id = "fps", label = "FPS and Latency",
        kind = "readout", secure = false,
    },
}

-- Read from the hoisted default rather than duplicated. Two copies of an
-- ordering drift, and the one that drifts is always the one nobody is looking
-- at. Task 4 Step 3b moved this OFF ns.EUI_DEFAULTS.tbOrder (that key is now
-- registered as {}, see Core.lua) and onto ns.EUI_TB_DEFAULT_ORDER instead --
-- same single-source contract, new name. No `and` guard needed here: unlike
-- the old two-level ns.EUI_DEFAULTS.tbOrder lookup, there is no intermediate
-- table to be nil against; this file already returned above if Core.lua
-- itself bailed (EUI_INERT), which is the only way ns.EUI_TB_DEFAULT_ORDER
-- would be unset.
ns.TopBar.DEFAULT_ORDER = ns.EUI_TB_DEFAULT_ORDER

ns.TopBar.ById = {}
for _, el in ipairs(ns.TopBar.Elements) do
    ns.TopBar.ById[el.id] = el
end
