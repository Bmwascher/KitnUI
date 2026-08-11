-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Plater.lua                                                  ║
-- ║  Purpose: Profile data: Plater nameplate export string.      ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS
ns.data = ns.data or {}

-- DORMANT: the payload is empty, so the installer skips the step. The import
-- path is kept wired because the SavedVariables shape it writes was expensive to
-- work out.
--
-- TO BRING IT BACK: paste a real export below (Plater Options > Profiles >
-- Export Profile), drop `dormant` from the Plater step in
-- Installer/Installer.lua, put "Plater" back in the /kitn version order in
-- Installer/Core.lua, and bump X-Plater-Version in KitnUI.toc -- without the
-- bump, existing installs are never prompted to import it.
ns.data.Plater = [[]]
