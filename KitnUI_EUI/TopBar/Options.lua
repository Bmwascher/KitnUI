-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/TopBar/Options.lua                                ║
-- ║  Purpose: The top bar's options page: TOP BAR, ELEMENTS,      ║
-- ║           APPEARANCE, VISIBILITY, CLOCK and HEARTHSTONE.      ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

-- Core.lua sets this and stops when KitnUI's shared namespace is unreachable, so
-- ns has no title, no db and no data. Everything below needs all three.
if ns.EUI_INERT then return end

ns.EUIPages["Top Bar"] = function(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h, row

    _, h = W:SectionHeader(parent, "TOP BAR", y);                                  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Top Bar",
          tooltip = "Draws the KitnUI top bar. Off by default: running /install turns it on, because that is you asking for the KitnUI look.",
          getValue = function() return ns.TopBar.Enabled() end,
          setValue = function(v) ns.TopBar.SetEnabled(v) end },
        { type = "button", text = "Reset Positions",
          tooltip = "Puts the bar and the FPS readout back where they started. Use this if either has ended up off-screen after a UI scale change.",
          onClick = function() ns.TopBar.ResetPositions() end }
    );                                                                             y = y - h

    _, h = W:SectionHeader(parent, "ELEMENTS", y);                                 y = y - h

    -- Generated from the registry rather than listed, so adding an element to
    -- Elements.lua is the only edit an element ever needs. Panel is read-only text
    -- in stage one; stage two's preview takes over arranging and this text goes.
    local rows = {}
    for _, el in ipairs(ns.TopBar.Elements) do
        -- clock is the centre panel's only occupant and cannot be switched off.
        if el.id ~= "clock" and (not el.requires or el.requires()) then
            rows[#rows + 1] = el
        end
    end

    -- Read-only: stage one has no way to change an element's panel, so the page
    -- states where each one sits. Stage two's drag preview replaces this entirely
    -- and this suffix goes with it. fps has no panel (it anchors itself under the
    -- clock), which is the one case the fallback exists for.
    local PANEL_LABEL = { left = "Left", centre = "Centre", right = "Right" }
    local function RowLabel(el)
        return el.label .. "  (" .. (PANEL_LABEL[el.panel] or "Under clock") .. ")"
    end

    for i = 1, #rows, 2 do
        local leftEl, rightEl = rows[i], rows[i + 1]
        local rightCfg = { type = "label", text = "" }
        if rightEl then
            rightCfg = { type = "toggle", text = RowLabel(rightEl),
                getValue = function() return not ns.TopBar.IsOff(rightEl.id) end,
                setValue = function(v) ns.TopBar.SetOff(rightEl.id, not v); ns.TopBar.Apply() end }
        end
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = RowLabel(leftEl),
              getValue = function() return not ns.TopBar.IsOff(leftEl.id) end,
              setValue = function(v) ns.TopBar.SetOff(leftEl.id, not v); ns.TopBar.Apply() end },
            rightCfg
        );                                                                         y = y - h

        -- Sits immediately after whichever row the friends element landed in,
        -- left or right slot: Task 3 left this out because it has to sit right
        -- after the friends row, and there was no friends row before Task 5.
        if leftEl.id == "friends" or (rightEl and rightEl.id == "friends") then
            _, h = W:DualRow(parent, y,
                { type = "toggle", text = "Only Friends In World Of Warcraft",
                  tooltip = "Counts and lists only friends who are actually playing WoW, ignoring anyone online in another Blizzard game.",
                  getValue = function() return ns.TopBar.Get("tbFriendsInGameOnly") end,
                  setValue = function(v) ns.TopBar.Set("tbFriendsInGameOnly", v and true or false); ns.TopBar.Apply() end },
                { type = "label", text = "" }
            );                                                                     y = y - h
        end
    end

    _, h = W:SectionHeader(parent, "APPEARANCE", y);                               y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Icon Size", min = 12, max = 32, step = 1,
          tooltip = "Size of the launcher icons either side of the clock.",
          getValue = function() return ns.TopBar.Get("tbIconSize", 20) end,
          setValue = function(v) ns.TopBar.Set("tbIconSize", v); ns.TopBar.Apply() end },
        { type = "slider", text = "Clock Size", min = 10, max = 36, step = 1,
          tooltip = "Size of the clock text.",
          getValue = function() return ns.TopBar.Get("tbClockSize", 24) end,
          setValue = function(v) ns.TopBar.Set("tbClockSize", v); ns.TopBar.Apply() end }
    );                                                                             y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "FPS/MS Size", min = 6, max = 24, step = 1,
          tooltip = "Size of the FPS / MS readout text.",
          getValue = function() return ns.TopBar.Get("tbSysSize", 11) end,
          setValue = function(v) ns.TopBar.Set("tbSysSize", v); ns.TopBar.Apply() end },
        { type = "slider", text = "Panel Opacity", min = 0, max = 100, step = 5,
          tooltip = "How solid the bar's background panels are.",
          getValue = function() return ns.TopBar.Get("tbOpacity", 85) end,
          setValue = function(v) ns.TopBar.Set("tbOpacity", v); ns.TopBar.Apply() end }
    );                                                                             y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Button Spacing", min = 4, max = 30, step = 1,
          tooltip = "Gap between the icons on each side of the bar.",
          getValue = function() return ns.TopBar.Get("tbSpacing", 14) end,
          setValue = function(v) ns.TopBar.Set("tbSpacing", v); ns.TopBar.Apply() end },
        { type = "toggle", text = "Panel Backdrop",
          tooltip = "Draws a dark panel behind the bar's icons and clock. Turning it off leaves the icons and the accent line.",
          getValue = function() return ns.TopBar.Get("tbBackdrop", true) end,
          setValue = function(v) ns.TopBar.Set("tbBackdrop", v and true or false); ns.TopBar.Apply() end }
    );                                                                             y = y - h

    -- The swatch rides this toggle's row rather than taking one of its own:
    -- DualRow has no colour entry type. The setter is the seeding one from
    -- Task 2: turning the override on captures the live accent first, so the
    -- colour does not jump. Forward-declared so the setter, built first, can
    -- reach the swatch and its repaint function built just below it.
    local accentSwatch, updateAccentSwatch

    row, h = W:DualRow(parent, y,
        { type = "toggle", text = "Use A Custom Accent",
          tooltip = "Uses a fixed colour for the bar's accent line instead of following EllesmereUI's own accent.",
          getValue = function() return ns.TopBar.Get("tbAccentOverride", false) end,
          setValue = function(v)
              if v and EllesmereUI and EllesmereUI.GetAccentColor then
                  local r, g, b = EllesmereUI.GetAccentColor()
                  if r then
                      ns.TopBar.Set("tbAccentR", r)
                      ns.TopBar.Set("tbAccentG", g)
                      ns.TopBar.Set("tbAccentB", b)
                      -- Repaints the swatch from the seeding write above.
                      -- Without this it keeps showing whatever colour it was
                      -- last built with until the page happens to rebuild.
                      if updateAccentSwatch then updateAccentSwatch() end
                  end
              end
              ns.TopBar.Set("tbAccentOverride", v and true or false)
              if accentSwatch then
                  if v then accentSwatch:Show() else accentSwatch:Hide() end
              end
              ns.TopBar.Apply()
          end },
        { type = "label", text = "" }
    );                                                                             y = y - h

    local leftRgn = row and row._leftRegion
    if leftRgn and leftRgn._control and EllesmereUI
       and EllesmereUI.BuildColorSwatch and EllesmereUI.PP then
        accentSwatch, updateAccentSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
            function()
                return ns.TopBar.Get("tbAccentR", 1), ns.TopBar.Get("tbAccentG", 0), ns.TopBar.Get("tbAccentB", 0.549)
            end,
            function(r, g, b)
                ns.TopBar.Set("tbAccentR", r)
                ns.TopBar.Set("tbAccentG", g)
                ns.TopBar.Set("tbAccentB", b)
                ns.TopBar.Apply()
            end, nil, 20)
        if accentSwatch then
            EllesmereUI.PP.Point(accentSwatch, "RIGHT", leftRgn._control, "LEFT", -8, 0)
            -- Shown only when the override is on: AccentRGB() (Bar.lua) only
            -- reads tbAccentR/G/B while tbAccentOverride is true, so with the
            -- override off this is a dead control and stays hidden.
            if ns.TopBar.Get("tbAccentOverride", false) then
                accentSwatch:Show()
            else
                accentSwatch:Hide()
            end
        end
    end

    -- Bar.lua's OnEnter handler already checks this flag before calling an
    -- element's tooltip function; this is only the switch that sets it. Last
    -- control in APPEARANCE, per the design's control table.
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Tooltips",
          tooltip = "Shows a tooltip when you hover a top bar icon.",
          getValue = function() return ns.TopBar.Get("tbTooltips", true) end,
          setValue = function(v) ns.TopBar.Set("tbTooltips", v and true or false); ns.TopBar.Apply() end },
        { type = "label", text = "" }
    );                                                                             y = y - h

    _, h = W:SectionHeader(parent, "VISIBILITY", y);                              y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Hide In Combat",
          tooltip = "Hides the bar the moment you enter combat.",
          getValue = function() return ns.TopBar.Get("tbHideCombat", false) end,
          setValue = function(v) ns.TopBar.Set("tbHideCombat", v and true or false); ns.TopBar.Apply() end },
        { type = "toggle", text = "Hide In Pet Battles",
          tooltip = "Hides the bar during a pet battle. On by default, since the bar has nothing useful to show there.",
          getValue = function() return ns.TopBar.Get("tbHidePetBattle", true) end,
          setValue = function(v) ns.TopBar.Set("tbHidePetBattle", v and true or false); ns.TopBar.Apply() end }
    );                                                                             y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Hide In Vehicles",
          tooltip = "Hides the bar while you are in a vehicle.",
          getValue = function() return ns.TopBar.Get("tbHideVehicle", false) end,
          setValue = function(v) ns.TopBar.Set("tbHideVehicle", v and true or false); ns.TopBar.Apply() end },
        { type = "toggle", text = "Hide In Keystones, Raids And Rated PvP",
          tooltip = "Hides the bar in a Mythic+ dungeon, a raid, or rated PvP. A normal dungeon or an unrated arena leaves it alone.",
          getValue = function() return ns.TopBar.Get("tbHideSerious", false) end,
          setValue = function(v) ns.TopBar.Set("tbHideSerious", v and true or false); ns.TopBar.Apply() end }
    );                                                                             y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Fade Until Moused Over",
          tooltip = "Rests the bar at low visibility until you move your mouse over it.",
          getValue = function() return ns.TopBar.Get("tbFade", false) end,
          setValue = function(v) ns.TopBar.Set("tbFade", v and true or false); ns.TopBar.Apply() end },
        { type = "slider", text = "Fade Time", min = 0, max = 2, step = 0.05,
          tooltip = "How long the fade in and out takes, in seconds.",
          getValue = function() return ns.TopBar.Get("tbFadeTime", 0.25) end,
          setValue = function(v) ns.TopBar.Set("tbFadeTime", v); ns.TopBar.Apply() end }
    );                                                                             y = y - h

    _, h = W:SectionHeader(parent, "CLOCK", y);                                    y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "24-Hour Clock",
          tooltip = "Shows 18:30 rather than 6:30 PM.",
          getValue = function() return ns.TopBar.Get("tbUse24h", true) end,
          setValue = function(v) ns.TopBar.Set("tbUse24h", v and true or false); ns.TopBar.Apply() end },
        { type = "toggle", text = "Server Time",
          tooltip = "Shows the realm's time instead of your computer's. Useful when your machine is in a different time zone from your raid.",
          getValue = function() return ns.TopBar.Get("tbServerTime", false) end,
          setValue = function(v) ns.TopBar.Set("tbServerTime", v and true or false); ns.TopBar.Apply() end }
    );                                                                             y = y - h

    _, h = W:SectionHeader(parent, "HEARTHSTONE", y);                              y = y - h

    -- All three dropdowns read the same owned-stone list HearthValues()
    -- returns: the ownership scan (Elements.lua) is paid once and shared
    -- here, never rescanned per dropdown.
    local hearthValues, hearthOrder = ns.TopBar.HearthValues()

    _, h = W:WideDropdown(parent, "Left Click", y, hearthValues,
        function() return ns.TopBar.Get("tbHearthLeft", ns.EUI_DEFAULTS.tbHearthLeft) end,
        function(v) ns.TopBar.Set("tbHearthLeft", v); ns.TopBar.Apply() end,
        hearthOrder);                                                              y = y - h

    _, h = W:WideDropdown(parent, "Middle Click", y, hearthValues,
        function() return ns.TopBar.Get("tbHearthMiddle", ns.EUI_DEFAULTS.tbHearthMiddle) end,
        function(v) ns.TopBar.Set("tbHearthMiddle", v); ns.TopBar.Apply() end,
        hearthOrder);                                                              y = y - h

    _, h = W:WideDropdown(parent, "Right Click", y, hearthValues,
        function() return ns.TopBar.Get("tbHearthRight", ns.EUI_DEFAULTS.tbHearthRight) end,
        function(v) ns.TopBar.Set("tbHearthRight", v); ns.TopBar.Apply() end,
        hearthOrder);                                                              y = y - h

    return math.abs(y)
end

-- Live accent changes: repaints the bar without a reload, unless the user has
-- pinned it to a fixed colour with Use A Custom Accent above.
if EllesmereUI and EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function()
        if not ns.TopBar.Get("tbAccentOverride", false) then ns.TopBar.Apply() end
    end })
end
