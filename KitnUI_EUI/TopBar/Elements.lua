-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/TopBar/Elements.lua                              ║
-- ║  Purpose: The top bar's element registry. Pure data plus     ║
-- ║           per-element handlers. No layout, no storage.       ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.TopBar = ns.TopBar or {}

-- One file per element, named after the element's own id, so adding an element
-- means adding one texture and nothing else.
local ICON_DIR = "Interface\\AddOns\\KitnUI_EUI\\Media\\TopBar\\"
local function Icon(id)
    return ICON_DIR .. "icon-" .. id .. ".tga"
end

-- Mouse-button pictures for tooltip lines, cut out of Blizzard's own tutorial
-- sheet by pixel coordinates, so there is no art of our own to ship and nothing
-- to keep in step with the Media folder.
--
-- Read the trailing numbers as: draw 13x11 pixels, from a 512x512 sheet, taking
-- the box x=12..66 and the y range that differs per button.
local CLICK_L = "|TInterface\\TUTORIALFRAME\\UI-TUTORIAL-FRAME:13:11:0:-1:512:512:12:66:230:307|t"
local CLICK_R = "|TInterface\\TUTORIALFRAME\\UI-TUTORIAL-FRAME:13:11:0:-1:512:512:12:66:333:410|t"
local CLICK_M = "|TInterface\\TUTORIALFRAME\\UI-TUTORIAL-FRAME:13:11:0:-1:512:512:12:66:127:204|t"

-- An item icon inline in a tooltip line. The crop trims the stock icon border
-- the same way the bar's own launcher textures are trimmed, so a row of these
-- reads as icons rather than as bordered tiles.
local ITEM_ICON = "|T%s:16:16:0:0:64:64:5:59:5:59|t"

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
-- engine itself turns into a TeleportHome call; nothing here calls that
-- protected function directly. Right click opens the housing dashboard through
-- the same helper the game's own Housing micro button uses.
--
-- C_Housing.GetPlayerOwnedHouses() is ASYNC: it answers through the
-- PLAYER_HOUSE_LIST_UPDATED event, not a return value. The first owned house is
-- taken with no further selection UI.
--
-- SetAttribute is protected, so cachedHouse is only ever written onto the
-- button from inside HomeAttrs, which Bar.lua only reaches outside combat --
-- Apply() defers its whole protected half under lockdown.
local cachedHouse

local function RequestHouseList()
    if C_Housing and C_Housing.GetPlayerOwnedHouses then
        C_Housing.GetPlayerOwnedHouses()
    end
end

-- Is this the same house we already had? Wrapped in pcall because the two GUID
-- fields are WOWGUIDs, and comparing a Secret value throws rather than
-- answering. A comparison that cannot be made counts as CHANGED: never a missed
-- re-wire, which is the direction that matters.
--
-- The cost, stated plainly: a comparison that throws throws on EVERY event, and
-- the button re-requests the list from every hover, so every hover would drive a
-- full Apply(). Correctness survives that -- Apply is idempotent and defers its
-- protected half in combat -- but the cheapness does not. If 12.0 ever does throw
-- here, this needs a throttle.
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

    -- Caching the answer is NOT enough, and this Apply() call is why. The only
    -- thing that writes the secure attributes is HomeAttrs, which only
    -- ns.TopBar.Apply() reaches, in its protected half. Apply runs before the
    -- async answer arrives, finds nothing cached, clears `type1` and never comes
    -- back -- leaving the button with no secure action and no message either,
    -- because HomeOnClick only explains itself while cachedHouse is nil.
    --
    -- Apply() is safe to call in combat: it defers its protected half and retries
    -- on PLAYER_REGEN_ENABLED. The change test is what keeps this cheap, since
    -- the button re-requests the list on every hover.
    if SameHouse(house, cachedHouse) then return end
    cachedHouse = house
    if ns.TopBar and ns.TopBar.Apply then ns.TopBar.Apply() end
end)

-- Left click with nothing cached: an insecure fallback that explains why. Right
-- click always tries the dashboard. ToggleHousingDashboard is the helper
-- Blizzard built for calling this from outside the Housing addons, but the panel
-- toggle underneath it is still gated on combat like every other insecure
-- launcher here.
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
        -- Split by cause: "no house yet" and "cannot fetch mid-fight" are
        -- different problems with different fixes.
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
        -- PostClick, NEVER OnClick. SecureActionButtonTemplate performs its
        -- action FROM its own OnClick script, so assigning ours replaces it and
        -- the teleport never runs. PostClick runs AFTER the secure action,
        -- alongside it rather than instead of it, which is what Blizzard's own
        -- action buttons use for insecure follow-up work. Right click still
        -- reaches it because `type2` is never set.
        --
        -- Home is the only secure element here that wants insecure click
        -- behaviour of its own; every other is a Macro() passthrough that sets
        -- attributes and leaves the template's script alone.
        btn:SetScript("PostClick", HomeOnClick)
        -- Opportunistic refresh on hover. HookScript ADDS to Bar.lua's own
        -- OnEnter (tint + tooltip) rather than replacing it.
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
        -- A blank line under every title that has content beneath it, so the
        -- name reads as a heading rather than as the first item in the list.
        -- Only where content is CERTAIN to follow: an element whose tooltip is
        -- its title alone (every Macro() passthrough, portals, gamemenu) must
        -- not add one, and friends and guild pay theirs from inside
        -- Readouts.lua, where whether a roster follows at all is known.
        tt:AddLine(" ")
        tt:AddLine(CLICK_L .. " Teleport Home", 1, 1, 1)
        tt:AddLine(CLICK_R .. " Housing Dashboard", 1, 1, 1)
    end,
}

---------------------------------------------------------------------------------
-- Friends: no FriendsMicroButton exists in the Mainline micro menu, so this
-- cannot be a Macro() passthrough the way guild below is. ToggleFriendsFrame is
-- the real global and is not protected, so this is an insecure toggle guarded
-- like gamemenu and clock.
--
-- The badge (online count) and the roster tooltip are Readouts.lua's job:
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

-- Guild: GuildMicroButton DOES exist, so this stays the ordinary Macro()
-- passthrough. Only its tooltip is replaced, because Macro()'s own is a one-line
-- label and this one needs the roster.
local guildElement = Macro("guild", "Guild", Icon("guild"), "left",
    "/click GuildMicroButton")
guildElement.tooltip = function(tt)
    tt:AddLine("Guild", 1, 1, 1)
    if ns.TopBar.GuildTooltip then ns.TopBar.GuildTooltip(tt) end
end

-- Great Vault: WeeklyRewardsFrame is load-on-demand, so opening it goes through
-- WeeklyRewards_ShowUI, the same global the rest of the client uses. Not itself
-- protected, but gated on combat like every other insecure launcher here.
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
-- Pinned raw item ids rather than EllesmereUI's Dalaran resolver, which
-- conflates the Dalaran Hearthstone with the Key to the Arcantina and prefers
-- the key, so it can never hand back Dalaran once the key is owned.
--
-- HEARTH_IDS is the shared-cooldown pool only. Deliberately excluded:
-- Engineering Wormholes (a zone teleport, which is the portals element's job),
-- Garrison Hearthstone (its own cooldown, separate from the shared pool),
-- Flight Master's Whistle and Translocation Cypher (not hearthstones), and the
-- Timerunner's Hearthstone (it appears in a portal-flyout pool but not in any
-- shared-cooldown table, and this file will not resolve that by guessing).
local HEARTH_IDS = {
    6948, 54452, 64488, 93672, 142542, 162973, 163045, 165669, 165670, 165802,
    166746, 166747, 168907, 172179, 180290, 182773, 183716, 184353, 188952,
    190196, 193588, 200630, 206195, 208704, 209035, 210455, 212337, 228940,
    235016, 236687, 245970, 246565, 257736, 263489, 263933, 265100,
    140192, 253629, 264367, 190237,
}

-- Excluded from the RANDOM pool, never from the dropdowns: both of these go to a
-- FIXED destination rather than to the player's own hearth, so a roll that lands
-- on one sends them somewhere they did not ask for. Picking one deliberately is
-- still a perfectly good choice, which is why they stay in the list and in
-- HEARTH_IDS.
--
-- Exactly these two and no more. The test is the DESTINATION, not the cooldown:
-- several stones in HEARTH_IDS run on their own cooldown and still return the
-- player to their own hearth, and those belong in the pool.
local FIXED_DESTINATION = {
    [140192] = true, -- Dalaran Hearthstone
    [253629] = true, -- Personal Key to the Arcantina
}

-- The ownership scan is the expensive part of this element and is paid once
-- (ScanOwned, run at PLAYER_LOGIN), then shared by all three dropdowns and
-- all three mouse buttons through these tables.
local owned = {}                           -- numeric item ids the player owns, scan order
local randomPool = {}                      -- `owned` minus FIXED_DESTINATION; what RANDOM rolls out of
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

-- Rolls out of `randomPool`, not `owned`: the pool is the owned stones minus the
-- fixed-destination ones above. Avoids repeating the immediately previous roll
-- when more than one is in the pool, bounded at 10 attempts against a
-- pathological repeat.
--
-- The empty-pool fallback is the plain Hearthstone and nothing else. Falling
-- back to the first OWNED stone would be warmer, and it was wrong: a player who
-- owns nothing but the two fixed-destination stones would have RANDOM hand back
-- one of them, defeating the exclusion above on the one character where it
-- matters most. A macro that may fail is the better failure.
local function PickRandom(slot)
    if #randomPool == 0 then return 6948 end
    if #randomPool == 1 then return randomPool[1] end
    local last = randomCache[slot]
    local id = randomPool[math.random(#randomPool)]
    for _ = 1, 10 do
        if id ~= last then break end
        id = randomPool[math.random(#randomPool)]
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
-- nobody clicked. Only RerollSlot(), called after an actual click, advances it.
local function ResolveID(setting, slot)
    local id = tonumber(setting)
    if id and IsOwned(id) then return id end
    if not randomCache[slot] then randomCache[slot] = PickRandom(slot) end
    return randomCache[slot]
end

local SLOT_BY_BUTTON  = { LeftButton = "left", RightButton = "right", MiddleButton = "mid" }
local SETTING_BY_SLOT = { left = "tbHearthLeft", right = "tbHearthRight", mid = "tbHearthMiddle" }

-- Rerolls ONE slot, and only if that slot is actually set to RANDOM: an unowned
-- fixed id also resolves through randomCache (see ResolveID above) and must keep
-- the stone it settled on rather than wandering on every click.
--
-- Called AFTER the click, never before. Rolling first was the original design
-- and it was wrong in the one way that matters: the roll it wrote was the stone
-- that then fired, so from the moment the click ended the tooltip was naming the
-- stone just USED, and the next click would replace it with something else
-- before firing. Rolling afterwards means what the tooltip shows is what the
-- next click will actually use.
--
-- Rerolling only the clicked slot, not all three, follows from the same rule: a
-- left click must not silently change what the right button is about to do, and
-- the tooltip is showing all three at once.
local function RerollSlot(slot)
    if not slot then return end
    local key = SETTING_BY_SLOT[slot]
    if not key then return end
    if ns.TopBar.Get(key, ns.EUI_DEFAULTS[key]) ~= "RANDOM" then return end
    randomCache[slot] = PickRandom(slot)
end

-- Toys must be used by NAME, not item:ID: item:ID only resolves for something
-- actually in the bags, and most of HEARTH_IDS are Toy Box entries.
local function MacroText(id)
    if not id then return "" end
    local toyName = C_ToyBox and C_ToyBox.GetToyInfo and select(2, C_ToyBox.GetToyInfo(id))
    if toyName then return "/use " .. toyName end
    return "/use item:" .. id
end

-- Names and icons normally come from ScanOwned's asynchronous Item load, and on
-- a fresh login that answer can be a second or two behind the first hover. These
-- two fall back through the caches that ARE warm by then -- the Toy Box for a
-- toy, the client's own item cache for anything else -- and end at the word
-- "Hearthstone", never at a raw item id. Printing `6948` told the player nothing
-- and read as a fault; the ticker's next pass replaces the fallback with the
-- real name a half second later either way.
local function StoneLabel(id)
    if not id then return "Hearthstone" end
    local key = tostring(id)
    -- ScanOwned seeds this table with the id itself, so "the cache holds the
    -- key" means the name has NOT landed yet, not that the name is that number.
    local cached = hearthValues[key]
    if cached and cached ~= key then return cached end

    local toyName = C_ToyBox and C_ToyBox.GetToyInfo and select(2, C_ToyBox.GetToyInfo(id))
    if toyName and toyName ~= "" then return toyName end

    local itemName = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if itemName and itemName ~= "" then return itemName end

    -- Nothing knows it yet: ask, so the next pass has something to print.
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return "Hearthstone"
end

local function StoneIcon(id)
    if not id then return nil end
    local cached = hearthIcons[tostring(id)]
    if cached then return cached end
    local toyIcon = C_ToyBox and C_ToyBox.GetToyInfo and select(3, C_ToyBox.GetToyInfo(id))
    if toyIcon then return toyIcon end
    return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or nil
end

local function FmtCD(sec)
    sec = math.floor(sec + 0.5)
    if sec >= 3600 then
        return format("%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
    end
    return format("%d:%02d", sec / 60, sec % 60)
end

-- C_Item.GetItemCooldown's returns carry no SecretReturns marking, unlike a
-- Cooldown WIDGET's GetCooldownTimes/GetCooldownDuration, which are marked
-- Enum.SecretAspect.Cooldown. This reads the item API, never a Cooldown frame,
-- so the arithmetic below is safe.
--
-- Asked per stone rather than once for the button, because an assumed shared
-- cooldown would be wrong: the Dalaran Hearthstone and the Key to the Arcantina
-- -- both valid choices here -- run on cooldowns separate from the main pool, so
-- three rows can legitimately show three different states.
--
-- GCD_MAX is why the rows do not all blink "0:01" the moment anything is used:
-- using any item puts every other item on the global cooldown, and
-- GetItemCooldown reports that exactly like a real one.
--
-- The rule, stated as what the code does rather than as a claim about any item:
-- a reported DURATION at or under two seconds is treated as the global cooldown
-- and the row reads Ready; a longer one is shown as a countdown. Duration and
-- not REMAINING, or the last two seconds of a real cooldown would vanish. No
-- item's own cooldown length is asserted here, because the local reference
-- documents return types and not durations.
local GCD_MAX = 2

local function HearthCooldownRemaining(id)
    if not id then return nil end
    if not (C_Item and C_Item.GetItemCooldown) then return nil end
    local start, duration = C_Item.GetItemCooldown(id)
    if type(start) == "number" and type(duration) == "number" and duration > GCD_MAX then
        local remaining = start + duration - GetTime()
        if remaining > 0 then return remaining end
    end
    return nil
end

-- One tooltip row per mouse button: the button's own picture, the stone's icon,
-- its name, and its cooldown in the right-hand column.
--
-- The icon can still be missing on the first hover after login even with
-- StoneIcon's fallbacks, so the row drops the picture and keeps the text rather
-- than drawing a blank square.
local HEARTH_ROWS = {
    { click = CLICK_L, setting = "tbHearthLeft",   slot = "left"  },
    { click = CLICK_M, setting = "tbHearthMiddle", slot = "mid"   },
    { click = CLICK_R, setting = "tbHearthRight",  slot = "right" },
}

local function HearthTooltip(tt)
    tt:AddLine("Hearthstone", 1, 1, 1)
    tt:AddLine(" ")
    for _, row in ipairs(HEARTH_ROWS) do
        local setting = ns.TopBar.Get(row.setting, ns.EUI_DEFAULTS[row.setting])
        local id = ResolveID(setting, row.slot)
        local icon = StoneIcon(id)
        local label = StoneLabel(id)
        if setting == "RANDOM" then label = "Random: " .. label end

        local left = row.click .. " "
        if icon then left = left .. format(ITEM_ICON, icon) .. " " end
        left = left .. label

        local remaining = HearthCooldownRemaining(id)
        if remaining then
            tt:AddDoubleLine(left, FmtCD(remaining), 1, 1, 1, 1, 0.3, 0.3)
        else
            tt:AddDoubleLine(left, "Ready", 1, 1, 1, 0.3, 1, 0.3)
        end
    end

    -- Where a plain hearthstone sends you. Deliberately its own line rather than
    -- appended to each row: only the shared-pool stones honour it, and the
    -- Dalaran Hearthstone and the Key to the Arcantina in HEARTH_IDS do not, so a
    -- per-row suffix would state a destination that is wrong for those rows.
    -- GetBindLocation carries no secret marking (PlayerScriptDocumentation.lua:247).
    local bind = GetBindLocation and GetBindLocation()
    if type(bind) == "string" and bind ~= "" then
        tt:AddDoubleLine("Hearth set to", bind, 0.7, 0.7, 0.7, 1, 1, 1)
    end
end

-- Forward-declared: the defer watcher below closes over it before it is
-- assigned, and by the time PLAYER_REGEN_ENABLED can actually fire, the
-- assignment further down has long since run.
local HearthAttrs

-- "The Random reroll... rewrites the macro after use: defer it out of combat
-- rather than dropping it" -- a click that finds InCombatLockdown() true cannot
-- write the reroll now, but must not forget it either, or the button would keep
-- firing the same roll until some later click happens to land outside combat.
-- This is Bar.lua's own Defer()/pendingApply shape, scoped down to this one
-- button.
--
-- The slots are remembered with the button: the deferred work is the reroll for
-- each mouse button that was actually clicked, not for all three.
--
-- A SET rather than one slot, because one lockout can hold clicks on more than
-- one button and the second must not erase the first. Keeping the deferral at
-- all is deliberate: dropping it would rest on "a hearthstone cannot fire in
-- combat", which nothing in the local API reference states, and a set is correct
-- whether that holds or not.
local hearthDeferPending, hearthDeferBtn = false, nil
local hearthDeferSlots = {}
local hearthDeferFrame = CreateFrame("Frame")
hearthDeferFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    hearthDeferPending = false
    if hearthDeferBtn then
        for slot in pairs(hearthDeferSlots) do RerollSlot(slot) end
        hearthDeferSlots = {}
        HearthAttrs(hearthDeferBtn)
    end
end)

local function DeferHearthRefresh(btn, slot)
    hearthDeferBtn = btn
    -- A click on a button outside the three mapped ones has no slot to roll.
    -- Recording nothing is what keeps it from discarding a pending one.
    if slot then hearthDeferSlots[slot] = true end
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

    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("macrotext1", MacroText(leftID))
    btn:SetAttribute("type2", "macro")
    btn:SetAttribute("macrotext2", MacroText(rightID))
    btn:SetAttribute("type3", "macro")
    btn:SetAttribute("macrotext3", MacroText(midID))

    if not btn._hearthWired then
        -- Two halves of one click, and the split is the whole point.
        --
        -- BEFORE: rewrite the three macros from the CURRENT rolls, without
        -- rolling. Toy names may not have been cached when Apply() last wrote
        -- them, and a macro still reading "/use item:<id>" for a toy that is not
        -- in the bags does nothing at all. This repairs that in place, and
        -- because it does not roll, the stone that fires is the one the tooltip
        -- was naming a moment earlier.
        btn:SetScript("PreClick", function(self)
            if InCombatLockdown() then return end
            HearthAttrs(self)
        end)

        -- AFTER: roll the clicked slot on for next time and write that. The
        -- tooltip's next pass shows the new stone, which is the one the next
        -- click will use.
        btn:SetScript("PostClick", function(self, button)
            local slot = SLOT_BY_BUTTON[button]
            if InCombatLockdown() then
                DeferHearthRefresh(self, slot)
                return
            end
            RerollSlot(slot)
            HearthAttrs(self)
        end)

        -- Live cooldown countdown while hovering, on its own ticker because
        -- Readouts.lua's is file-local. Started on OnEnter and cancelled on
        -- OnLeave, so it never runs while nothing is hovered.
        local function CancelHearthTicker(self)
            if self._hearthTicker then
                self._hearthTicker:Cancel()
                self._hearthTicker = nil
            end
        end
        btn:HookScript("OnEnter", function(self)
            -- Bar.lua's OnEnter returns before calling el.tooltip when
            -- tbTooltips is off, but this ticker is wired independently of that
            -- call, so without the same check it would spin every 0.5s for as
            -- long as the pointer sits on the button, unable to do anything.
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

-- Nil-guarded: the bar (and this button) may not exist yet -- the feature can be
-- switched off, or ScanOwned's async callbacks can land before Apply() has built
-- anything. Combat-guarded because this writes secure attributes, unlikely
-- timing or not.
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
            if not FIXED_DESTINATION[id] then randomPool[#randomPool + 1] = id end
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
-- Mythic+ Portals: a secure flyout of this season's dungeon teleports, anchored
-- to the portals launcher button.
--
-- KitnUI's own season list, and the Top Bar's first choice for it.
--
-- EllesmereUI owns SEASON_PORTALS, and it has stopped moving: the list in the
-- 8.7.5 and 8.8.2 references and in the live 8.9.2 install is identical, so
-- waiting for the host to roll the season over is waiting for something that is
-- not arriving on time. KitnUI cannot fix it at the source either, because
-- editing EllesmereUI's own files is forbidden.
--
-- The reach is deliberately SMALL. This feeds the Top Bar flyout and nothing
-- else, so EllesmereUI's minimap flyout, chat flyout and /keys resolver still
-- read the host's and can disagree with this one until the host catches up.
-- Assigning over EllesmereUI.SEASON_PORTALS would make the whole UI agree, and
-- was rejected (Kitn, 2026-08-18) because it would also overwrite a newer host
-- list, silently, on the day one finally ships.
--
-- SOURCE, and it is not guesswork: BigWigs v419.2, `Tools/Keystones.lua:367` for
-- the spell ids and `Loader.lua:346` for which maps are this season, both read
-- from the live install on 2026-08-18. BigWigs gates these eight behind build
-- 120100 (`Loader.lua:183`) and the live client is 12.1.0.69382, so they are
-- current rather than pending. Altar of Fangs was cross-checked against Wowhead
-- on its own. The host's eight are the season BEFORE these, which is the whole
-- reason this table exists.
--
-- Only spellID is read. mapID and short ride along for whoever next has to check
-- this against BigWigs; note mapID is the CHALLENGE MODE map, while the host's
-- entries carry an LFG dungeonID, so the two lists do not diff field for field.
--
-- Replace the whole table each season.
local KITN_SEASON_PORTALS = {
    { spellID = 1286809, short = "MR",  mapID = 2813, names = { "murder row" } },
    { spellID = 1286807, short = "DoN", mapID = 2825, names = { "den of nalorakk" } },
    { spellID = 1286801, short = "TBV", mapID = 2859, names = { "the blinding vale" } },
    { spellID = 1286804, short = "VA",  mapID = 2923, names = { "voidscar arena" } },
    { spellID = 1286812, short = "AoF", mapID = 2993, names = { "altar of fangs" } },
    { spellID = 393256,  short = "RLP", mapID = 2521, names = { "ruby life pools" } },
    { spellID = 1286828, short = "ToS", mapID = 1877, names = { "temple of sethraliss" } },
    { spellID = 1286831, short = "KR",  mapID = 1762, names = { "king's rest" } },
}

-- Read fresh on every requires() and CreateFlyout() call rather than snapshotted
-- at file scope, so a season boundary where neither list is usable degrades to
-- "no portals button" instead of a frozen empty grid.
--
-- The host stays as the FALLBACK for the one case the table above cannot cover:
-- a KitnUI that has fallen behind a season the host did roll over. Emptying the
-- table therefore means "use theirs", not "no portals".
local function SeasonPortals()
    if #KITN_SEASON_PORTALS > 0 then return KITN_SEASON_PORTALS end
    local EUI = _G.EllesmereUI
    local list = EUI and EUI.SEASON_PORTALS
    if type(list) ~= "table" or #list == 0 then return nil end
    return list
end

local PORTAL_BTN_SIZE, PORTAL_SPACING, PORTAL_PADDING, PORTAL_COLS = 32, 2, 4, 4

local portalFlyout, portalFlyoutBtns

-- Desaturates unknown teleports and keeps cooldown swipes current. `known` comes
-- from C_SpellBook.IsSpellKnownOrInSpellBook, which carries no secret marker,
-- rather than the deprecated IsPlayerSpell global that only exists behind a CVar.
--
-- Not the narrower IsSpellKnown, which this used until 2026-08-18. Dungeon
-- teleports are account-wide and sit in the General tab of the spellbook rather
-- than being "known" the way a class spell is, so IsSpellKnown answers false for
-- a teleport the player has earned and every icon dims. BigWigs asks the wider
-- question for the same list, and for the same reason (its Loader.lua:157).
--
-- C_Spell.GetSpellCooldown IS a secret-value risk: it is marked
-- SecretWhenCooldownsRestricted, and the SpellCooldownInfo it returns marks only
-- isEnabled, isActive and isOnGCD as NeverSecret. So this never compares or does
-- arithmetic on startTime/duration -- it branches on isActive and hands the two
-- numbers to Cooldown:SetCooldown untouched, whose own arguments are built to
-- accept secret values. The widget paints the swipe without this file ever
-- reading the real numbers.
local function RefreshPortalButtons()
    if not portalFlyoutBtns then return end
    for _, btn in ipairs(portalFlyoutBtns) do
        local spellID = btn.spellID
        local known = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
            and C_SpellBook.IsSpellKnownOrInSpellBook(spellID, Enum.SpellBookSpellBank.Player)
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
    -- visibility driver owns Show/Hide outright and would force this flyout open
    -- again the instant combat ends. This state only ever CLOSES it, so a flyout
    -- the player closed stays closed. Needed at all because this frame is about
    -- to parent secure buttons, after which an ordinary Hide() from Lua is
    -- protected -- the same rule Bar.lua's HideBar() is built around.
    portalFlyout = CreateFrame("Frame", "KitnUITopBar_portalsFlyout", UIParent,
        "SecureHandlerStateTemplate")
    portalFlyout:SetSize(w, h)
    portalFlyout:SetFrameStrata("DIALOG")
    -- Level as well as strata: strata alone leaves the default level inside
    -- DIALOG, so another dialog-strata frame can draw over the flyout.
    portalFlyout:SetFrameLevel(100)
    portalFlyout:SetClampedToScreen(true)
    portalFlyout:Hide()

    local bg = portalFlyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    -- Bar.lua's own panel colour: the flyout has to match the bar it hangs off.
    bg:SetColorTexture(0.03, 0.03, 0.04, 0.95)

    -- The host's border, when the host offers it. The colour differs between the
    -- two call sites on purpose: the FLYOUT gets a faint white hairline so the
    -- panel edge reads against the dark backdrop, while each BUTTON below gets
    -- opaque black to separate the icons from each other.
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

            -- Per button too, opaque black.
            if PP and PP.CreateBorder then
                PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
            end

            local cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
            cooldown:SetAllPoints()
            cooldown:SetDrawSwipe(true)
            cooldown:SetDrawBling(false)
            cooldown:SetDrawEdge(false)

            -- The countdown text is the ENGINE's, and that is the whole point. A
            -- hand-drawn timer would have to subtract GetTime() from the
            -- startTime and duration this file is careful never to touch (see
            -- RefreshPortalButtons above): both are secret whenever cooldowns are
            -- restricted, and arithmetic on a secret throws. The widget formats
            -- the same two numbers internally, where that restriction does not
            -- apply, and ticks itself without an OnUpdate.
            --
            -- Abbreviation OFF is what produces "8h" and "45m" instead of
            -- "7:59:12". A threshold below one minute performs no abbreviation at
            -- all, so every remaining time keeps its unit suffix
            -- (FrameAPICooldownDocumentation.lua:349). Guarded because it is the
            -- newer of the two calls; without it the text still shows, just
            -- abbreviated.
            cooldown:SetHideCountdownNumbers(false)
            if cooldown.SetCountdownAbbrevThreshold then
                cooldown:SetCountdownAbbrevThreshold(0)
            end
            btn.cooldown = cooldown

            -- AnyUp AND AnyDown instead of Bar.lua's useOnKeyDown=false fix for
            -- the same ActionButtonUseKeyDown CVar problem: these buttons are
            -- never reached by WireSecureAttributes (they are not in
            -- ns.TopBar.ById), so there is no per-Apply moment to set that
            -- attribute on them.
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
    -- helper is the host's, not ours, so a future host version that renamed or
    -- dropped it must not error here.
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

    -- Wired once per launcher button, the first time it ever opens the flyout.
    -- HookScript, not SetScript, so this cannot discard an OnHide handler some
    -- other file wires onto the same frame. Hooking the LAUNCHER button's OnHide
    -- catches every path that makes the button disappear out from under an open
    -- flyout: HideBar() hiding the whole bar, LayoutSide hiding this one button
    -- when portals is switched off. In each the button is simply gone -- no
    -- combat transition fires the state driver above, and Escape has nothing
    -- left to close -- so without this the flyout would sit on screen until the
    -- player entered combat once or reloaded.
    --
    -- This is a hook on the BUTTON, not a reparent of the FLYOUT under it.
    -- Hiding a parent only hides a child visually; it does not flip the child's
    -- own IsShown() to false. A reparented flyout would look closed while still
    -- reporting itself open, and would pop back into view the instant the bar
    -- was shown again.
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
    -- SEASON_PORTALS is the host's, and it moves every season. Absent entirely
    -- rather than a button that opens an empty grid.
    requires = function() return SeasonPortals() and true or false end,
}

---------------------------------------------------------------------------------
-- Volume: left click +10% master volume, right click -10%, middle click toggles
-- mute. No InCombatLockdown gate, unlike every other launcher in this file:
-- those guard against opening a Blizzard panel mid-fight; this only ever calls
-- SetCVar on an audio cvar, which carries no protected or secure marker and is
-- safe to call at any time.
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
    tt:AddLine(" ")
    tt:AddDoubleLine("Master", format("%d%%", VolumePercent() * 100), 0.7, 0.7, 0.7, 1, 1, 1)
    tt:AddLine(" ")
    tt:AddLine(CLICK_L .. " +10%", 1, 1, 1)
    tt:AddLine(CLICK_R .. " -10%", 1, 1, 1)
    tt:AddLine(CLICK_M .. " Mute", 1, 1, 1)
end

-- Live percentage while hovered, the same ticker shape HearthTooltip uses above:
-- 0.5s, IsOwned-guarded, cancelled on OnLeave AND OnHide so a button hidden
-- mid-hover cannot leak the ticker. volume has no attrs() -- it is not secure --
-- so there is no per-Apply moment to wire this; wiring it from inside the
-- tooltip function, keyed off the stable button name Bar.lua always creates,
-- reaches the same end state without one.
--
-- The ticker starts from the tooltip function too, not only from the OnEnter
-- hook below: a HookScript added while an OnEnter is already running does not
-- fire again for that same hover, so hooking alone is good enough for
-- OnLeave/OnHide but never for a live reading on the very first hover.
local function VolumeCancelTicker(self)
    if self._volumeTicker then
        self._volumeTicker:Cancel()
        self._volumeTicker = nil
    end
end

-- 0.5s: the readout is a whole-number percentage, so a faster tick buys nothing
-- visible and costs more work.
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

    -- No `collections` element here: it opened the same WINDOW `toybox` opens,
    -- on whatever tab was last used. `toybox` is kept because it lands
    -- somewhere definite.
    --
    -- Toy Box is a tab inside the Collections journal, not its own micro button.
    -- Click the micro button to open the journal, then select tab index 3 on the
    -- line after: /click runs its OnClick synchronously, so the journal already
    -- exists by the time the second line runs.
    Macro("toybox", "Toy Box", Icon("toybox"), "left",
        "/click CollectionsMicroButton\n/run CollectionsJournal_SetTab(CollectionsJournal, 3)"),

    hearthstoneElement,
    portalsElement,
    homeElement,
    vaultElement,

    Macro("character", "Character", Icon("character"), "right",
        "/click CharacterMicroButton"),

    -- No SpellbookMicroButton exists on Mainline: 12.0 folded the spellbook into
    -- a tab of PlayerSpellsFrame (the frame `talents` opens), reachable only
    -- through PlayerSpellsUtil.OpenToSpellBookTab(). A `/click
    -- SpellbookMicroButton` here would silently do nothing.
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

    -- Clock: the centre panel's only occupant, never switched off, so
    -- Options.lua excludes it from the ELEMENTS list by id rather than this
    -- element declining a toggle. Bar.lua creates its button as
    -- "KitnUITopBar_clock" like any other element; Readouts.lua reaches that
    -- stable global name to attach the time FontString and size it from
    -- tbClockSize. Left click opens the calendar, right click the stopwatch and
    -- alarm, middle click reloads; all three are insecure and refuse in combat
    -- like gamemenu above.
    --
    -- ToggleTimeManager is a global Blizzard defines in a bootstrap file
    -- (Blizzard_TimeManager_Bootstrap.lua:7) precisely so the panel can be opened
    -- from outside its own addon: it loads the addon on demand, then toggles.
    -- Nil-guarded like every other host call here.
    {
        id = "clock", label = "Clock", panel = "centre",
        kind = "readout", secure = false,
        onClick = function(_self, button)
            if button ~= "LeftButton" and button ~= "MiddleButton"
               and button ~= "RightButton" then return end
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1, 1, 3)
                return
            end
            if button == "LeftButton" then
                ToggleCalendar()
            elseif button == "RightButton" then
                if ToggleTimeManager then ToggleTimeManager() end
            else
                ReloadUI()
            end
        end,
        tooltip = function(tt)
            tt:AddLine("Clock", 1, 1, 1)
            tt:AddLine(" ")
            -- Lockouts and reset clocks live in Readouts.lua with the other
            -- tooltip bodies that read live game state. It always adds lines, so
            -- the spacer below is always paid for.
            if ns.TopBar.ClockTooltip then ns.TopBar.ClockTooltip(tt) end
            tt:AddLine(" ")
            tt:AddLine(CLICK_L .. " Calendar", 1, 1, 1)
            tt:AddLine(CLICK_R .. " Stopwatch and Alarm", 1, 1, 1)
            tt:AddLine(CLICK_M .. " Reload UI", 1, 1, 1)
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

-- Read from the hoisted default rather than duplicated: two copies of an
-- ordering drift, and the one that drifts is the one nobody is looking at. No
-- nil guard needed -- this file already returned above if Core.lua bailed
-- (EUI_INERT), which is the only way ns.EUI_TB_DEFAULT_ORDER would be unset.
ns.TopBar.DEFAULT_ORDER = ns.EUI_TB_DEFAULT_ORDER

ns.TopBar.ById = {}
for _, el in ipairs(ns.TopBar.Elements) do
    ns.TopBar.ById[el.id] = el
end
