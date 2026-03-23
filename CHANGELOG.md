# Changelog

## v1.0.1

### Bug Fixes & Data Updates

- Fixed ElvUI profiles not applying correctly (Table export wrapper artifact)
- Fixed ElvUI Private settings not applying (same wrapper issue)
- Implemented KitnEssentials import via API (was a placeholder)
- Added CopyTable to ElvUI data decode to prevent shared references
- Added ElvUI aurawatch (class aura indicators) to Global import
- Switched Plater to full-DB import for consistent nameplate settings
- Removed redundant ElvUI_Anchor overwrite (data now embedded in profiles)
- Removed RefreshLayout call in Blizzard CDM to prevent taint errors
- Updated all ElvUI profile data (Dark, Color, Healer Dark, Healer Color, Private)
- Updated Plater profile data (full DB export)
- Added Ayije CDM Bite profile

## v1.0.0

### Initial Release

- ElvUI profile installer with step-by-step guided setup
- Dark and Color UI variants with DPS and Healer layouts
- Addon profiles: Details, Plater, BigWigs, WarpDeplete, MRT, Edit Mode, Ayije CDM, KitnEssentials
- Class-specific Blizzard CDM profiles (40 specs)
- Multiple installer flows: Install, Update (outdated-only), Load (profile activation), CDM-only
- Per-addon version tracking with smart update detection
- Alt-detection with profile load prompt on new characters
- Minimap icon cleanup for Details, BigWigs, Plater, SimulationCraft, Wago, MRT
- 1440p UI scale auto-forcing
- `/kitn install`, `/kitn update`, `/kitn load`, `/kitn cdm`, `/kitn version`, `/kitn reset` commands
