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

    return math.abs(y)
end
