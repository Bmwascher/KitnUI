-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Plater.lua                                                  ║
-- ║  Purpose: Profile data: Plater nameplate export string.      ║
-- ╚══════════════════════════════════════════════════════════════╝

local _, ns = ... ---@type string, KitnUINS
ns.data = ns.data or {}

-- DORMANT. This file still loads and setupFunctions["Plater"] in
-- Installer/Setup.lua is still wired, but the installer no longer OFFERS Plater:
-- its step is commented out of the addon list in Installer/Installer.lua. The
-- whole path is kept rather than deleted because the SavedVariables shape it
-- writes -- PlaterDB.profiles / profileKeys, and the DecompressData round trip
-- -- was expensive to work out and is not worth rediscovering.
--
-- TO BRING IT BACK: paste a real export below, then uncomment the Plater line in
-- Installer/Installer.lua's addonSteps and put "Plater" back in the /kitn version
-- order in Installer/Core.lua. Bump X-Plater-Version in KitnUI.toc at the same
-- time, or existing installs will never be prompted to import it.
--
-- Export from: Plater Options > Profiles > Export Profile (current profile)
ns.data.Plater = [[]]
