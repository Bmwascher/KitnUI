-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/XPBar/Options.lua                                ║
-- ║  Purpose: The XP Bar options page: the XP bar, its session   ║
-- ║           and the faction bar.                               ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

if ns.EUI_INERT then return end

ns.XPBar = ns.XPBar or {}
local X = ns.XPBar

-- values and order for a dropdown, from key, label pairs.
local function Choices(...)
    local values, order = {}, {}
    for i = 1, select("#", ...), 2 do
        local key, label = select(i, ...)
        values[key] = label
        order[#order + 1] = key
    end
    return values, order
end

local POS_V, POS_O = Choices("inside", "Inside", "above", "Above", "below", "Below", "hidden", "Hidden")
local EDGE_V, EDGE_O = Choices("above", "Above", "below", "Below")
local VIS_V, VIS_O = Choices("always", "Always", "mouseover", "Mouseover", "in_combat", "In Combat",
    "out_of_combat", "Out of Combat", "in_raid", "In a Raid", "in_party", "In a Party", "solo", "Solo", "never", "Never")
local NUM_V, NUM_O = Choices("full", "Full (45,000)", "plain", "Plain (45000)", "short", "Short (45.0K)")
local FILL_V, FILL_O = Choices("gradient", "Gradient", "class", "Class Color", "accent", "KitnUI Accent",
    "solid", "Solid", "profession", "Profession Fill")
local DIR_V, DIR_O = Choices("HORIZONTAL", "Horizontal", "VERTICAL", "Vertical")
local PLAY_V, PLAY_O = Choices("gain", "Play on XP Gain", "loop", "Loop", "still", "Still")
local DIV_V, DIV_O = Choices("off", "Off", "gaps", "20 Gaps", "lines", "Lines")
local TICK_V, TICK_O = Choices("dashed", "Dashed", "dotted", "Dotted", "solid", "Solid", "none", "None")
local OUTLINE_V, OUTLINE_O = Choices("", "EllesmereUI Outline", "NONE", "None", "OUTLINE", "Outline",
    "THICKOUTLINE", "Thick Outline")
local SOURCE_V, SOURCE_O = Choices("watched", "Watched Faction", "companion", "Current Delve Companion",
    "pinned", "Pinned Faction")
local FBFILL_V, FBFILL_O = Choices("custom", "Custom Color", "standing", "Standing Color")
local STYLE_NAMES = { eui = "EUI Border", prof = "Profession Frame", classic = "Classic", forever = "Forever", blizzard = "Blizzard" }
local STYLE_ORDER = { "eui", "prof", "classic", "forever", "blizzard" }

local HIDE_TIPS = {
    xp = "Hides the XP bar you already had while this one is on: Blizzard's for the session, or EllesmereUI's by setting its Visibility to Never until this goes off.",
    rep = "Hides the reputation bar you already had while this one is on: Blizzard's for the session, or EllesmereUI's by setting its Visibility to Never until this goes off.",
}

ns.EUIPages["XP Bar"] = function(parent, yOffset)
    -- The cold mount. getHeaderBuilder (Core.lua) only stashes the builder for
    -- the page cache; this call is the one that mounts the header.
    if EllesmereUI and EllesmereUI.SetContentHeader and X.BuildPreviewHeader then
        EllesmereUI:SetContentHeader(X.BuildPreviewHeader)
    end
    local W = EllesmereUI and EllesmereUI.Widgets
    if not W then return math.abs(yOffset) end
    local y = yOffset

    local function Changed()
        X.Apply()
        if X.PreviewRefresh then X.PreviewRefresh() end
    end

    -- A toggle click does not sweep the refresh list itself, so controls it
    -- grays out would not update until the page is rebuilt.
    local function RefreshWidgets()
        local rl = EllesmereUI._widgetRefreshList
        if rl then for i = 1, #rl do rl[i]() end end
    end

    local function Header(text)
        local _, h = W:SectionHeader(parent, text, y)
        y = y - h
    end

    local function Row(left, right)
        local row, h = W:DualRow(parent, y, left, right)
        y = y - h
        return row
    end

    local function Spacer() return { type = "spacer" } end

    -- disabled: true while the key is not true / not the value.
    local function Off(key) return function() return X.Get(key) ~= true end end
    local function Unless(key, value) return function() return X.Get(key) ~= value end end

    local function Toggle(text, key, tip, disabled, regray)
        return { type = "toggle", text = text, tooltip = tip, disabled = disabled,
            getValue = function() return X.Get(key) == true end,
            setValue = function(v)
                X.Set(key, v and true or false)
                Changed()
                if regray then RefreshWidgets() end
            end }
    end

    local function Slider(text, key, lo, hi, tip, disabled)
        return { type = "slider", text = text, min = lo, max = hi, step = 1, tooltip = tip, disabled = disabled,
            getValue = function() return X.Get(key) end,
            setValue = function(v)
                X.Set(key, v)
                Changed()
            end }
    end

    local function Drop(text, key, values, order, tip, disabled, regray)
        return { type = "dropdown", text = text, values = values, order = order, tooltip = tip, disabled = disabled,
            getValue = function() return X.Get(key) end,
            setValue = function(v)
                X.Set(key, v)
                Changed()
                if regray then RefreshWidgets() end
            end }
    end

    local function Color(text, stem, alpha, tip, disabled)
        return { type = "colorpicker", text = text, hasAlpha = alpha, tooltip = tip, disabled = disabled,
            getValue = function()
                if alpha then return X.Get(stem .. "R"), X.Get(stem .. "G"), X.Get(stem .. "B"), X.Get(stem .. "A") end
                return X.Get(stem .. "R"), X.Get(stem .. "G"), X.Get(stem .. "B")
            end,
            setValue = function(r, g, b, a)
                X.Set(stem .. "R", r)
                X.Set(stem .. "G", g)
                X.Set(stem .. "B", b)
                if alpha and a then X.Set(stem .. "A", a) end
                Changed()
            end }
    end

    local function HideTip(kind)
        local enableKey = kind == "xp" and "xpEnabled" or "fbEnabled"
        local hideKey = kind == "xp" and "xpHideExisting" or "fbHideExisting"
        if not ns.EUIOwnershipTip then return HIDE_TIPS[kind] end
        -- Both switches share the "xpbar" section, so each asks after its
        -- own bar's note.
        return ns.EUIOwnershipTip(HIDE_TIPS[kind], "xpbar", function()
            return X.Get(enableKey) == true and X.Get(hideKey) == true and X.UsesEUIBars()
        end, "EllesmereUI's bar hidden", function() return X.HoldsExisting(kind) end)
    end

    -- Lists built once per page build from what the running client has.
    local fontV, fontO = { [""] = "EllesmereUI Font" }, { "" }
    for _, name in ipairs(X.LSMList("font") or {}) do
        fontV[name] = name
        fontO[#fontO + 1] = name
    end
    local texV, texO = { [""] = "Flat" }, { "" }
    for _, name in ipairs(X.LSMList("statusbar") or {}) do
        texV[name] = name
        texO[#texO + 1] = name
    end
    local borderV, borderO = { solid = "Solid" }, { "solid" }
    if EllesmereUI.GetBorderTextureDropdown then
        local ok, v, o = pcall(EllesmereUI.GetBorderTextureDropdown)
        if ok and type(v) == "table" and type(o) == "table" then borderV, borderO = v, o end
    end
    local styleV, styleO = {}, {}
    for _, s in ipairs(STYLE_ORDER) do
        if X.StyleAvailable(s) then
            styleV[s] = STYLE_NAMES[s]
            styleO[#styleO + 1] = s
        end
    end
    local profV, profO = {}, {}
    for _, name in ipairs(X.PROFESSIONS) do
        if X.ProfessionAvailable(name) then
            profV[name] = name
            profO[#profO + 1] = name
        end
    end
    local noProfessions = #profO == 0
    if noProfessions then
        local stored = X.Get("xpProfFill")
        profV[stored] = stored
        profO[1] = stored
    end

    local function Appearance(p, title)
        Header(title)
        local function NotStyle(style)
            return function() return X.ResolveStyle(X.Get(p .. "FrameStyle")) ~= style end
        end
        Row({ type = "dropdown", text = "Frame Style", values = styleV, order = styleO,
              tooltip = "The art around the bar. Only styles this client has art for are listed.",
              getValue = function() return X.ResolveStyle(X.Get(p .. "FrameStyle")) end,
              setValue = function(v)
                  X.Set(p .. "FrameStyle", v)
                  Changed()
                  RefreshWidgets()
              end },
            Drop("Border Texture", p .. "BorderTexture", borderV, borderO, "Applies to the EUI border only.", NotStyle("eui")))
        Row(Slider("Border Size", p .. "BorderSize", 0, 4, "Applies to the EUI border only.", NotStyle("eui")),
            Color("Border Color", p .. "Border", true, "Applies to the EUI border only.", NotStyle("eui")))
        if p == "xp" then
            Row({ type = "dropdown", text = "Fill Style", values = FILL_V, order = FILL_O,
                  itemDisabled = function(v) return v == "profession" and noProfessions end,
                  getValue = function() return X.Get("xpFillStyle") end,
                  setValue = function(v)
                      X.Set("xpFillStyle", v)
                      Changed()
                      RefreshWidgets()
                  end },
                Drop("Gradient Direction", "xpGradDir", DIR_V, DIR_O, nil, Unless("xpFillStyle", "gradient")))
            Row(Color("Gradient Start", "xpGradStart", false, nil, Unless("xpFillStyle", "gradient")),
                Color("Gradient End", "xpGradEnd", false, nil, Unless("xpFillStyle", "gradient")))
            Row(Color("Solid Color", "xpSolid", false, "The solid fill, and the profession fill's color where its art cannot draw.",
                    function() local s = X.Get("xpFillStyle"); return s ~= "solid" and s ~= "profession" end),
                Drop("Profession", "xpProfFill", profV, profO, nil, Unless("xpFillStyle", "profession")))
            Row(Drop("Profession Animation", "xpProfPlay", PLAY_V, PLAY_O, nil, Unless("xpFillStyle", "profession")),
                Toggle("Stretch to Bar", "xpProfStretch", "Draws one copy of the art across the whole bar.", Unless("xpFillStyle", "profession")))
            Row(Color("Completed Quest Color", "xpQuest", true), Color("Rested Color", "xpRested", true))
        else
            Row(Drop("Fill Mode", "fbFillMode", FBFILL_V, FBFILL_O, "Standing Color follows the standing's own color.", nil, true),
                Color("Fill Color", "fb", false, nil, Unless("fbFillMode", "custom")))
        end
        Row(Drop("Dividers", p .. "Divider", DIV_V, DIV_O, nil, nil, true),
            Slider("Gap Size", p .. "GapSize", 0, 12, nil, Unless(p .. "Divider", "gaps")))
        Row(Drop("5% Line Style", p .. "Tick5Style", TICK_V, TICK_O, nil, Unless(p .. "Divider", "lines")),
            Color("5% Line Color", p .. "Tick5", true, nil, Unless(p .. "Divider", "lines")))
        Row(Color("10% Line Color", p .. "Tick10", true, nil, Unless(p .. "Divider", "lines")),
            Toggle("Smart Ticks", p .. "SmartTicks", "Hides the marks the fill has passed.", Unless(p .. "Divider", "lines")))
        Row(Toggle("10% Labels", p .. "TickLabels", nil, Unless(p .. "Divider", "lines"), true),
            Slider("Label Size", p .. "TickLabelSize", 6, 20, nil, function()
                return X.Get(p .. "Divider") ~= "lines" or X.Get(p .. "TickLabels") ~= true
            end))
        local function NoLabels()
            return X.Get(p .. "Divider") ~= "lines" or X.Get(p .. "TickLabels") ~= true
        end
        Row(Slider("Label X Offset", p .. "TickLabelOffX", -50, 50,
                "Moves the 10% labels sideways, clear of the texts inside the bar.", NoLabels),
            Slider("Label Y Offset", p .. "TickLabelOffY", -50, 50,
                "Moves the 10% labels up or down, clear of the texts inside the bar.", NoLabels))
        Row(Color("Label Color", p .. "TickLabel", false, nil, NoLabels),
            Color("Background", p .. "Bg", true))
        Row(Drop("Font", p .. "Font", fontV, fontO), Drop("Outline", p .. "Outline", OUTLINE_V, OUTLINE_O))
        Row(Slider("Font Size", p .. "FontSize", 8, 32), Drop("Texture", p .. "Texture", texV, texO))
        local wr, hr = X.RANGES[p .. "Width"], X.RANGES[p .. "Height"]
        Row(Slider("Width", p .. "Width", wr[1], wr[2]), Slider("Height", p .. "Height", hr[1], hr[2]))
    end

    Header("XP BAR")
    Row({ type = "toggle", text = "Enable XP Bar", tooltip = "Draws KitnUI's XP bar. Move it in EllesmereUI's Unlock Mode.",
          getValue = function() return X.XPEnabled() end,
          setValue = function(v)
              X.SetXPEnabled(v)
              if X.PreviewRefresh then X.PreviewRefresh() end
          end },
        { type = "toggle", text = "Hide Existing XP Bar", tooltip = HideTip("xp"),
          getValue = function() return X.Get("xpHideExisting") == true end,
          setValue = function(v) X.SetHideExisting("xp", v) end })

    Header("XP VISIBILITY")
    Row(Drop("Visibility", "xpVisibility", VIS_V, VIS_O, "When the XP bar shows, with the same choices as EllesmereUI's own frames."),
        Toggle("Show at Maximum Level", "xpShowAtMax", "Keeps the bar at maximum level, full, with the session time."))

    Header("XP DISPLAY")
    Row(Drop("Amount Position", "xpAmountPos", POS_V, POS_O, "Where the XP amount sits; Hidden removes it."),
        Drop("Number Style", "xpNumberStyle", NUM_V, NUM_O, "How the amounts and the tooltips' numbers read."))
    Row(Toggle("Show Remaining", "xpShowRemaining", "Adds the XP still needed after the amount."),
        Toggle("Show Completed Quest Overlay", "xpShowQuest", "Draws the XP of completed quests after the fill."))
    Row(Toggle("Time This Level", "xpShowLevelTime", nil, nil, true),
        Drop("Time This Level Position", "xpLevelTimePos", EDGE_V, EDGE_O, nil, Off("xpShowLevelTime")))
    Row(Toggle("Time This Session", "xpShowSessionTime", nil, nil, true),
        Drop("Time This Session Position", "xpSessionTimePos", EDGE_V, EDGE_O, nil, Off("xpShowSessionTime")))
    Row(Toggle("Leveling Rate", "xpShowRate", nil, nil, true),
        Drop("Leveling Rate Position", "xpRatePos", EDGE_V, EDGE_O, nil, Off("xpShowRate")))
    Row(Toggle("Completed and Rested", "xpShowCompRested", nil, nil, true),
        Drop("Completed and Rested Position", "xpCompRestedPos", EDGE_V, EDGE_O, nil, Off("xpShowCompRested")))

    Appearance("xp", "XP APPEARANCE")

    Header("XP TOOLTIP")
    Row(Toggle("Show Tooltip", "xpTooltip", "Shows the XP details when you hover the bar.", nil, true),
        Toggle("Hide Tooltip in Combat", "xpTooltipCombat", nil, Off("xpTooltip")))

    Header("SESSION")
    Row(Toggle("Reset Session on Reload", "xpResetOnReload", "Starts a new session on every /reload instead of continuing it."),
        { type = "labeledButton", text = "Reset XP Session Now", buttonText = "Reset", width = 100,
          tooltip = "Sets this session's XP and time back to zero. The time this level is kept.",
          onClick = function()
              X.ResetSession()
              Changed()
          end })
    Row(Toggle("Mute /played in Chat", "xpMutePlayed", "Keeps the played-time lines KitnUI asks for out of chat."), Spacer())

    Header("FACTION BAR")
    Row({ type = "toggle", text = "Enable Faction Bar", tooltip = "Draws KitnUI's faction bar. Move it in EllesmereUI's Unlock Mode.",
          getValue = function() return X.FactionEnabled() end,
          setValue = function(v)
              X.SetFactionEnabled(v)
              if X.PreviewRefresh then X.PreviewRefresh() end
          end },
        { type = "toggle", text = "Hide Existing Reputation Bar", tooltip = HideTip("rep"),
          getValue = function() return X.Get("fbHideExisting") == true end,
          setValue = function(v) X.SetHideExisting("rep", v) end })

    Header("FACTION VISIBILITY")
    Row(Drop("Visibility", "fbVisibility", VIS_V, VIS_O, "When the faction bar shows, with the same choices as EllesmereUI's own frames."),
        Toggle("Show at Max Standing", "fbShowAtMax", "Keeps the bar at maximum standing. A progressing paragon track always shows."))

    Header("FACTION SOURCE")
    -- Filled from the faction catalog each time the dropdown opens, so a
    -- faction met since the last opening is listed even on a cached page: the
    -- catalog opens reputation headers, so it is not run on every page build.
    local pinV, pinO = {}, {}
    local function FillPinned(withCatalog)
        for k in pairs(pinV) do pinV[k] = nil end
        for i = #pinO, 1, -1 do pinO[i] = nil end
        pinV[0], pinO[1] = "None", 0
        local values, order
        if withCatalog then values, order = X.FactionCatalog() end
        if values and order then
            for _, id in ipairs(order) do
                pinV[id] = values[id]
                pinO[#pinO + 1] = id
            end
        end
        local cur = tonumber(X.Get("fbFactionID")) or 0
        if cur ~= 0 and not pinV[cur] then
            pinV[cur] = X.FactionName(cur) or ("Faction " .. cur)
            pinO[#pinO + 1] = cur
        end
    end
    FillPinned(false)
    local sourceRow = Row({ type = "dropdown", text = "Source", values = SOURCE_V, order = SOURCE_O,
          tooltip = "Current Delve Companion uses the companion's faction inside a delve and the watched faction elsewhere.",
          itemDisabled = function(v) return v == "companion" and ns.IS_FOREVER == true end,
          getValue = function() return X.Get("fbSource") end,
          setValue = function(v)
              X.Set("fbSource", v)
              Changed()
              RefreshWidgets()
          end },
        Drop("Pinned Faction", "fbFactionID", pinV, pinO, "The faction the bar shows with the Pinned source.",
            Unless("fbSource", "pinned")))
    local pinControl = sourceRow and sourceRow._rightRegion and sourceRow._rightRegion._control
    if pinControl and pinControl.HookScript then
        -- Only the press that opens the menu refills it: dropping an open menu
        -- would let the same click build a fresh one and show it again.
        pinControl:HookScript("OnMouseDown", function()
            local menu = pinControl._ddMenu
            if menu and menu.IsShown and menu:IsShown() then return end
            FillPinned(true)
            if pinControl._invalidateMenu then pcall(pinControl._invalidateMenu) end
        end)
    end

    Header("FACTION DISPLAY")
    Row(Drop("Name Position", "fbNamePos", POS_V, POS_O, "Where the faction's name, standing and percent sit."),
        Drop("Amount Position", "fbAmountPos", POS_V, POS_O, "Where the faction's values sit."))
    Row(Toggle("Show Tooltip", "fbTooltip", "Shows the faction's details when you hover the bar.", nil, true),
        Toggle("Hide Tooltip in Combat", "fbTooltipCombat", nil, Off("fbTooltip")))

    Appearance("fb", "FACTION APPEARANCE")

    Header("POSITION")
    Row({ type = "labeledButton", text = "Position: use EUI Unlock Mode", buttonText = "Unlock Mode", width = 120,
          tooltip = "Both bars are moved and resized in EllesmereUI's Unlock Mode.",
          onClick = function()
              if EllesmereUI and EllesmereUI.OpenUnlockMode then pcall(EllesmereUI.OpenUnlockMode, EllesmereUI) end
          end },
        Spacer())

    return math.abs(y)
end
