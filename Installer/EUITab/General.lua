-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab/General.lua                                          ║
-- ║  Purpose: The General page: profile variant, Lulu Mode,      ║
-- ║           icon shape and zoom, accent scoping.               ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS

---------------------------------------------------------------------------------
-- Profile variant
---------------------------------------------------------------------------------

local VARIANT_VALUES = { dark = "Dark", color = "Class Color" }
local VARIANT_ORDER  = { "dark", "color" }

local function CurrentVariant()
    return (ns.db and ns.db.variants and ns.db.variants.EllesmereUI) or "dark"
end

-- EllesmereUI.SetProfile routes to SwitchProfile, which returns silently on a
-- missing profile. A user who only ever installed Dark has no "... Colored"
-- profile, so a plain swap would flip our stored variant and change nothing,
-- leaving this control reading back a lie. Import that variant instead.
local function SetVariant(value)
    local useColor = (value == "color")
    local target = ns.profileName .. (useColor and " Colored" or "")

    local profiles = _G.EllesmereUIDB and EllesmereUIDB.profiles
    local exists = profiles and profiles[target] and true or false

    if not ns.SetupAddon then return end
    -- import = not exists: activate when the profile is there, import when it
    -- is not. Both paths end by writing ns.db.variants and activating.
    ns.SetupAddon("EllesmereUI", not exists, useColor)
end

---------------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------------

-- The runtime resolver maps exactly these seven. The defaults table also carries
-- a playerTarget entry, but nothing reads it.
local UNIT_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }

local function IconSettings()
    local s = ns.EUISettings()
    s.icons = s.icons or {}
    return s.icons
end

-- Both controls walk the same seven units and the same buff/debuff pair, so one
-- helper does the walking and the caller supplies the two key names.
--
-- `on` is a separate parameter rather than being inferred from `value`, because
-- one of the two controls writes `false` as its value. In Lua 5.1 `false` is
-- falsy, so a `value ~= nil` test would work but a `value and ... or ...` caller
-- would not, and inferring intent from a falsy payload is exactly the kind of
-- trap that survives review.
local function ApplyAuraKeys(saved, on, buffKey, debuffKey, value)
    local uf = ns.EUIProfile("EllesmereUIUnitFrames")
    -- A nil profile means the module is unreachable, usually because the user
    -- disabled it. Returning early LEAVES the snapshot intact on the off path,
    -- so a later re-apply can still restore once the module is back.
    if not uf then return end

    saved.units = saved.units or {}
    for _, unit in ipairs(UNIT_KEYS) do
        local settings = uf[unit]
        if type(settings) == "table" then
            saved.units[unit] = saved.units[unit] or {}
            local slot = saved.units[unit]
            slot.buff = slot.buff or {}
            slot.debuff = slot.debuff or {}
            if on then
                ns.EUIOverride(settings, slot.buff, buffKey, value)
                ns.EUIOverride(settings, slot.debuff, debuffKey, value)
            else
                ns.EUIRestore(settings, slot.buff, buffKey)
                ns.EUIRestore(settings, slot.debuff, debuffKey)
            end
        end
    end

    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
end

local function ApplySquareIcons()
    local on = IconSettings().square and true or false
    -- Snap on the on-path, peek on the off-path: peeking avoids seeding a record
    -- in every profile belonging to a user who never turns this on.
    local saved = on and ns.EUISnap("icons", "square") or ns.EUIPeekSnap("icons", "square")
    if not saved then return end
    ApplyAuraKeys(saved, on, "buffCropIcons", "debuffCropIcons", false)
end

-- EllesmereUI stores zoom as a 0 to 1 fraction. The slider shows 0 to 20 because
-- whole numbers read better than hundredths.
local function ApplyIconZoom()
    local raw = IconSettings().zoom
    local on = raw ~= nil
    local saved = on and ns.EUISnap("icons", "zoom") or ns.EUIPeekSnap("icons", "zoom")
    if not saved then return end
    ApplyAuraKeys(saved, on, "buffIconZoom", "debuffIconZoom", raw and (raw / 100) or nil)
end

ns.EUIRegisterReapply(function()
    ApplySquareIcons()
    ApplyIconZoom()
end)

---------------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------------

ns.EUIPages["General"] = function(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "PROFILE", y);                                 y = y - h

    _, h = W:Dropdown(parent, "Profile Variant", y,
        VARIANT_VALUES,
        CurrentVariant,
        SetVariant,
        VARIANT_ORDER,
        "Swaps the active EllesmereUI profile. Installs the variant first if you have not imported it.");
                                                                                   y = y - h

    _, h = W:Spacer(parent, y, 20);                                                y = y - h
    _, h = W:SectionHeader(parent, "ICONS", y);                                    y = y - h

    _, h = W:Toggle(parent, "Square Aura Icons", y,
        function() return IconSettings().square and true or false end,
        function(v)
            IconSettings().square = v and true or nil
            ApplySquareIcons()
        end,
        "Squares the buff and debuff icons on EllesmereUI's unit frames instead of cropping them.");
                                                                                   y = y - h

    _, h = W:Slider(parent, "Aura Icon Zoom", y, 0, 20, 1,
        function() return IconSettings().zoom or 0 end,
        function(v)
            IconSettings().zoom = (v > 0) and v or nil
            ApplyIconZoom()
        end,
        "Zooms into unit frame aura icons to trim the border built into the artwork.");
                                                                                   y = y - h

    return math.abs(y)
end
