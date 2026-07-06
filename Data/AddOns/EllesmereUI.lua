local _, ns = ...

-- EllesmereUI profile data (v3 !EUI_ export strings).
--
-- ►► FIXTURE PLACEHOLDER — replace the empty string below with a real export
--    captured in-game:
--      /run EllesmereUI:ShowCopyPopup("export","", EllesmereUI.ExportCurrentProfile(true, true))
--    Copy the popup text (it must begin with "!EUI_") and paste it as the value.
--    While it is empty, the EllesmereUI install step reports "No EllesmereUI
--    profile data found" and the rest of the wizard still works.
--
-- Optional variant keys, added when those looks are authored (Phase 4):
--   ns.data.EllesmereUIColored        -- class-color DPS
--   ns.data.EllesmereUIHealer         -- healer (its presence enables per-spec auto-swap)
--   ns.data.EllesmereUIHealerColored  -- class-color healer
ns.data.EllesmereUI = ""
