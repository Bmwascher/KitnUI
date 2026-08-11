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
    -- The cold mount. getHeaderBuilder (Core.lua) only STASHES the builder for
    -- the page cache; this call is the one that actually mounts the header.
    -- During EllesmereUI's hidden pre-build pass SetContentHeader is stubbed to
    -- a no-op, so this is naturally inert there.
    if EllesmereUI and EllesmereUI.SetContentHeader
       and ns.TopBar and ns.TopBar.BuildPreviewHeader then
        EllesmereUI:SetContentHeader(ns.TopBar.BuildPreviewHeader)
    end

    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h, row

    -- Shared splits for every three-across checkbox grid on this page,
    -- matching the precedent's own form (EUI_PartyMode_Options.lua:359).
    local CB_SPLITS = { 0.333, 0.333, 0.334, rowHeight = 36 }

    -- Bottom hairline that closes a TripleRow checkbox grid: TripleRow sets
    -- `_skipRowDivider` (EllesmereUI_Widgets.lua:4044), so a grid draws no
    -- divider of its own. Matches EUI_PartyMode_Options.lua:413-419,
    -- nil-guarded on every EllesmereUI field it touches.
    local function CloseGrid(yPos)
        if not (EllesmereUI and EllesmereUI.BORDER_R and EllesmereUI.BORDER_G and EllesmereUI.BORDER_B
           and EllesmereUI.PanelPP and EllesmereUI.CONTENT_PAD) then return end
        local PP = EllesmereUI.PanelPP
        local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
        local sep = parent:CreateTexture(nil, "ARTWORK", nil, 7)
        sep:SetColorTexture(EllesmereUI.BORDER_R, EllesmereUI.BORDER_G, EllesmereUI.BORDER_B, 0.02)
        PP.Size(sep, totalW, 1)
        PP.Point(sep, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, yPos + 1)
    end

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
    -- Elements.lua is the only edit an element ever needs. Filters out the
    -- clock (below) and anything whose requires() predicate currently fails,
    -- leaving the set the checkbox grid below actually builds rows from.
    local rows = {}
    for _, el in ipairs(ns.TopBar.Elements) do
        -- clock is the centre panel's only occupant and cannot be switched off.
        if el.id ~= "clock" and (not el.requires or el.requires()) then
            rows[#rows + 1] = el
        end
    end

    -- Builds a `{ type = "checkbox", ... }` config for one grid slot. `el` is
    -- a function PARAMETER, not a closed-over loop variable -- every call
    -- gets its own fresh binding, so three checkboxes built per row can
    -- never end up sharing one and all driving the last element.
    local function ElementCheckboxCfg(el)
        if not el then return nil end
        return { type = "checkbox", text = el.label,
            getValue = function() return not ns.TopBar.IsOff(el.id) end,
            setValue = function(v)
                ns.TopBar.SetOff(el.id, not v); ns.TopBar.Apply()
                if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end
            end }
    end

    -- The friends qualifier is a CELL of the grid, sitting in the slot
    -- immediately after the friends element's own checkbox, so the two read
    -- as a pair. It is therefore conditional again: no friends element in the
    -- grid, because its requires() failed, means no qualifier either -- which
    -- is how it behaved before the grid existed.
    --
    -- The tooltip rides a hit frame anchored to the slot's generic label
    -- (EllesmereUI_Widgets.lua:4089-4107), and the checkbox branch HIDES that
    -- label (:4261) while drawing its own. The hit frame is a separate frame
    -- and is not hidden with it, so the tooltip still works, but its hover
    -- area sits over the box and the start of the text rather than the whole
    -- label. Search indexing is unaffected (:4050-4052).
    local FRIENDS_QUALIFIER = { type = "checkbox",
        text = "Only Friends In World Of Warcraft",
        tooltip = "Counts and lists only friends who are actually playing WoW, ignoring anyone online in another Blizzard game.",
        getValue = function() return ns.TopBar.Get("tbFriendsInGameOnly") end,
        setValue = function(v)
            ns.TopBar.Set("tbFriendsInGameOnly", v and true or false); ns.TopBar.Apply()
            if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end
        end }

    -- One flat list of grid cells, so the qualifier packs with the elements
    -- instead of the loop having to know about it.
    local cells = {}
    for _, el in ipairs(rows) do
        cells[#cells + 1] = ElementCheckboxCfg(el)
        if el.id == "friends" then cells[#cells + 1] = FRIENDS_QUALIFIER end
    end

    -- Three-across checkbox grid, TripleRow per precedent
    -- (EUI_PartyMode_Options.lua:343-419).
    for i = 1, #cells, 3 do
        _, h = W:TripleRow(parent, y,
            cells[i], cells[i + 1], cells[i + 2],
            CB_SPLITS);                                                            y = y - h
    end
    CloseGrid(y)

    -- Cross-panel drag can empty one side completely with no other way back.
    -- This restores ARRANGEMENT only -- it must never touch tbOff, which
    -- elements are switched on is a separate concern the checkboxes above
    -- already own.
    _, h = W:WideButton(parent, "Reset Icon Arrangement", y, function()
        local d = ns.TopBar.DEFAULT_ORDER
        if not (d and d.left and d.centre and d.right) then return end
        ns.TopBar.SetOrder(d.left, d.centre, d.right)
        ns.TopBar.Apply()
        if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end
    end);                                                                          y = y - h

    _, h = W:SectionHeader(parent, "APPEARANCE", y);                               y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Icon Size", min = 12, max = 32, step = 1,
          tooltip = "Size of the launcher icons either side of the clock.",
          getValue = function() return ns.TopBar.Get("tbIconSize", 20) end,
          setValue = function(v) ns.TopBar.Set("tbIconSize", v); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
        { type = "slider", text = "Clock Size", min = 10, max = 36, step = 1,
          tooltip = "Size of the clock text.",
          getValue = function() return ns.TopBar.Get("tbClockSize", 24) end,
          setValue = function(v) ns.TopBar.Set("tbClockSize", v); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end }
    );                                                                             y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "FPS / MS Size", min = 6, max = 24, step = 1,
          tooltip = "Size of the FPS / MS readout text.",
          getValue = function() return ns.TopBar.Get("tbSysSize", 11) end,
          setValue = function(v) ns.TopBar.Set("tbSysSize", v); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
        { type = "slider", text = "Panel Opacity", min = 0, max = 100, step = 5,
          tooltip = "How solid the bar's background panels are.",
          getValue = function() return ns.TopBar.Get("tbOpacity", 85) end,
          setValue = function(v) ns.TopBar.Set("tbOpacity", v); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end }
    );                                                                             y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Button Spacing", min = 4, max = 30, step = 1,
          tooltip = "Gap between the icons on each side of the bar.",
          getValue = function() return ns.TopBar.Get("tbSpacing", 14) end,
          setValue = function(v) ns.TopBar.Set("tbSpacing", v); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
        { type = "toggle", text = "Panel Backdrop",
          tooltip = "Draws a dark panel behind the bar's icons and clock. Turning it off leaves the icons and the accent line.",
          getValue = function() return ns.TopBar.Get("tbBackdrop", true) end,
          setValue = function(v) ns.TopBar.Set("tbBackdrop", v and true or false); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end }
    );                                                                             y = y - h

    -- The swatch rides this toggle's row rather than taking one of its own:
    -- DualRow has no colour entry type. The setter is the seeding one from
    -- Task 2: turning the override on captures the live accent first, so the
    -- colour does not jump. Forward-declared so the setter, built first, can
    -- reach the swatch and its repaint function built just below it.
    local accentSwatch, updateAccentSwatch

    -- Show Tooltips (2e) rides this row's right half: Use A Custom Accent's
    -- own right half was an empty filler. Bar.lua's OnEnter handler already
    -- checks tbTooltips before calling an element's tooltip function; this
    -- is only the switch that sets it. Last control block in APPEARANCE, per
    -- the design's control table.
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
              if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end
          end },
        { type = "toggle", text = "Show Tooltips",
          tooltip = "Shows a tooltip when you hover a top bar icon.",
          getValue = function() return ns.TopBar.Get("tbTooltips", true) end,
          setValue = function(v) ns.TopBar.Set("tbTooltips", v and true or false); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end }
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
                if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end
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

    _, h = W:SectionHeader(parent, "VISIBILITY", y);                              y = y - h

    -- 2f: rarely touched once set -- collapsed by default via the host's own
    -- expander. Nil-guarded so a host without it still renders every row,
    -- just always expanded.
    local visOpen = true
    if EllesmereUI and EllesmereUI.BuildLessCommonExpander then
        visOpen, y = EllesmereUI.BuildLessCommonExpander(parent, y, "kitnuiTbVisibility", "Show Visibility Options")
    end
    if visOpen then
        -- Both rows of this grid share one splits table: TripleRow draws a
        -- divider at each region boundary, so two touching rows with
        -- different splits would show their dividers at different x
        -- positions -- a visible jog between rows. The keystones label needs
        -- the wider third slot (below), so both rows use it, not just its own.
        local VIS_SPLITS = { 0.25, 0.25, 0.5, rowHeight = 36 }

        _, h = W:TripleRow(parent, y,
            { type = "checkbox", text = "Hide In Combat",
              tooltip = "Hides the bar the moment you enter combat.",
              getValue = function() return ns.TopBar.Get("tbHideCombat", false) end,
              setValue = function(v) ns.TopBar.Set("tbHideCombat", v and true or false); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
            { type = "checkbox", text = "Hide In Pet Battles",
              tooltip = "Hides the bar during a pet battle. On by default, since the bar has nothing useful to show there.",
              getValue = function() return ns.TopBar.Get("tbHidePetBattle", true) end,
              setValue = function(v) ns.TopBar.Set("tbHidePetBattle", v and true or false); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
            { type = "checkbox", text = "Hide In Vehicles",
              tooltip = "Hides the bar while you are in a vehicle.",
              getValue = function() return ns.TopBar.Get("tbHideVehicle", false) end,
              setValue = function(v) ns.TopBar.Set("tbHideVehicle", v and true or false); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
            VIS_SPLITS
        );                                                                         y = y - h

        -- The keystones label is too long for a 33% column at this width, so
        -- this row -- and the one above it, sharing VIS_SPLITS -- gets a
        -- wider split, and the label takes the wide (rightmost) slot instead
        -- of a normal third.
        _, h = W:TripleRow(parent, y,
            { type = "checkbox", text = "Fade Until Moused Over",
              tooltip = "Rests the bar at low visibility until you move your mouse over it.",
              getValue = function() return ns.TopBar.Get("tbFade", false) end,
              setValue = function(v) ns.TopBar.Set("tbFade", v and true or false); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
            nil,
            { type = "checkbox", text = "Hide In Keystones, Raids And Rated PvP",
              tooltip = "Hides the bar in a Mythic+ dungeon, a raid, or rated PvP. A normal dungeon or an unrated arena leaves it alone.",
              getValue = function() return ns.TopBar.Get("tbHideSerious", false) end,
              setValue = function(v) ns.TopBar.Set("tbHideSerious", v and true or false); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
            VIS_SPLITS
        );                                                                         y = y - h

        CloseGrid(y)

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Fade Time", min = 0, max = 2, step = 0.05,
              tooltip = "How long the fade in and out takes, in seconds.",
              getValue = function() return ns.TopBar.Get("tbFadeTime", 0.25) end,
              setValue = function(v) ns.TopBar.Set("tbFadeTime", v); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
            { type = "spacer" }
        );                                                                         y = y - h
    end
    if EllesmereUI and EllesmereUI.FinishLessCommonExpander then
        y = EllesmereUI.FinishLessCommonExpander(parent, y, "kitnuiTbVisibility", "Show Visibility Options")
    end

    _, h = W:SectionHeader(parent, "CLOCK", y);                                    y = y - h

    _, h = W:TripleRow(parent, y,
        { type = "checkbox", text = "24-Hour Clock",
          tooltip = "Shows 18:30 rather than 6:30 PM.",
          getValue = function() return ns.TopBar.Get("tbUse24h", true) end,
          setValue = function(v) ns.TopBar.Set("tbUse24h", v and true or false); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
        { type = "checkbox", text = "Server Time",
          tooltip = "Shows the realm's time instead of your computer's. Useful when your machine is in a different time zone from your raid.",
          getValue = function() return ns.TopBar.Get("tbServerTime", false) end,
          setValue = function(v) ns.TopBar.Set("tbServerTime", v and true or false); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end },
        nil,
        CB_SPLITS
    );                                                                             y = y - h
    CloseGrid(y)

    _, h = W:SectionHeader(parent, "HEARTHSTONE", y);                              y = y - h

    -- 2f: rarely touched once set -- collapsed by default via the host's own
    -- expander. Nil-guarded so a host without it still renders every row,
    -- just always expanded.
    local hearthOpen = true
    if EllesmereUI and EllesmereUI.BuildLessCommonExpander then
        hearthOpen, y = EllesmereUI.BuildLessCommonExpander(parent, y, "kitnuiTbHearth", "Show Hearthstone Options")
    end
    if hearthOpen then
        -- All three dropdowns read the same owned-stone list HearthValues()
        -- returns: the ownership scan (Elements.lua) is paid once and shared
        -- here, never rescanned per dropdown.
        local hearthValues, hearthOrder = ns.TopBar.HearthValues()

        _, h = W:WideDropdown(parent, "Left Click", y, hearthValues,
            function() return ns.TopBar.Get("tbHearthLeft", ns.EUI_DEFAULTS.tbHearthLeft) end,
            function(v) ns.TopBar.Set("tbHearthLeft", v); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end,
            hearthOrder);                                                          y = y - h

        _, h = W:WideDropdown(parent, "Middle Click", y, hearthValues,
            function() return ns.TopBar.Get("tbHearthMiddle", ns.EUI_DEFAULTS.tbHearthMiddle) end,
            function(v) ns.TopBar.Set("tbHearthMiddle", v); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end,
            hearthOrder);                                                          y = y - h

        _, h = W:WideDropdown(parent, "Right Click", y, hearthValues,
            function() return ns.TopBar.Get("tbHearthRight", ns.EUI_DEFAULTS.tbHearthRight) end,
            function(v) ns.TopBar.Set("tbHearthRight", v); ns.TopBar.Apply(); if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end end,
            hearthOrder);                                                          y = y - h
    end
    if EllesmereUI and EllesmereUI.FinishLessCommonExpander then
        y = EllesmereUI.FinishLessCommonExpander(parent, y, "kitnuiTbHearth", "Show Hearthstone Options")
    end

    return math.abs(y)
end

-- Live accent changes: repaints the bar without a reload, unless the user has
-- pinned it to a fixed colour with Use A Custom Accent above.
if EllesmereUI and EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function()
        if not ns.TopBar.Get("tbAccentOverride", false) then
            ns.TopBar.Apply()
            if ns.TopBar.PreviewRefresh then ns.TopBar.PreviewRefresh() end
        end
    end })
end
