-- ╔══════════════════════════════════════════════════════════════╗
-- ║  KitnUI_EUI/Bite.lua                                         ║
-- ║  Purpose: Bite Mode switches, registered as scalars in       ║
-- ║           Core.lua's DEFAULTS.profile.                       ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ...

if ns.EUI_INERT then return end

local function Settings()
    return ns.EUISettings and ns.EUISettings() or nil
end

function ns.BiteEnabled()
    local s = Settings()
    return (s and s.bite) and true or false
end

function ns.DarkCastBarEnabled()
    local s = Settings()
    return (s and s.darkCastBar) and true or false
end
