-- ╔══════════════════════════════════════════════════════════════╗
-- ║  BlizzardCDM.lua                                             ║
-- ║  Purpose: Profile data: per-class Blizzard CDM layout        ║
-- ║           strings for Forever, keyed by class ID.            ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS
ns.data = ns.data or {}

-- Forever has nine classes, each with one spec named after the class.
-- Indexed by classId, then specIndex. An empty string is a spec with no layout
-- yet: the installer shows it as no data and skips it.
ns.data.BlizzardCDM = {
    -- [1] Warrior
    [1] = {
        [1] = "",
    },
    -- [2] Paladin
    [2] = {
        [1] = "",
    },
    -- [3] Hunter
    [3] = {
        [1] = "",
    },
    -- [4] Rogue
    [4] = {
        [1] = "",
    },
    -- [5] Priest
    [5] = {
        [1] = "",
    },
    -- [7] Shaman
    [7] = {
        [1] = "",
    },
    -- [8] Mage
    [8] = {
        [1] = "",
    },
    -- [9] Warlock
    [9] = {
        [1] = "",
    },
    -- [11] Druid
    [11] = {
        [1] = "",
    },
}
