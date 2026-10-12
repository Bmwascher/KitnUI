-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Baganator.lua                                               ║
-- ║  Purpose: Profile data: the raw Baganator profile export     ║
-- ║           string.                                            ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS
ns.data = ns.data or {}

-- Written into a named BAGANATOR_CONFIG.Profiles entry on import and activated
-- for this character through BAGANATOR_CURRENT_PROFILE, which is a per-character
-- SavedVariable. Applied only on an explicit install or load action, never on
-- PLAYER_LOGIN, so changes the user makes inside the profile survive a reload.
--
-- HOW TO UPDATE: in game, open Baganator > Customise, click Export on the
-- GENERAL page (not the Categories page), and paste the whole string below.
-- That one string is the entire profile, categories included; the separate
-- Categories export is a subset and is not used here.
--
-- The format is Baganator's own: "BGR!1!" followed by base64 of a deflated
-- CBOR table (CustomiseDialog/Main.lua:758). Setup.lua decodes it with
-- C_EncodingUtil and writes the result straight into the profile. Baganator
-- exported plain JSON until 2026; the old categoriesJSON field is gone.
ns.data.Baganator = {
    profileString = [[BGR!1!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]]
}
