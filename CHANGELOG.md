# Changelog

## v1.0.6

### Bug Fix & Data Updates

- Fixed ElvUI private profile (Parchment Remover) not applying by setting profileKey before SetProfile
- Updated KitnEssentials profile data (new modules)
- Updated BuffReminders profile data

## v1.0.5

### Import Improvements & Bug Fixes

- Fixed Details ImportProfile arguments to properly import auto-run scripts
- Added Details on_zonechanged auto-run script (auto-switches display in dungeons vs raids)
- Updated Details profile data
- Added Edit Mode layout limit check (max 5 custom layouts)
- Added Blizzard CDM max layout check and deferred activation
- Edit Mode and Blizzard CDM now show red error toast when layout limit is reached
- Import success toasts now use colored addon name styling
- SetupAddon returns success/failure for Edit Mode and Blizzard CDM

## v1.0.4

### Bug Fixes

- Fixed KitnEssentials import creating duplicate profiles on reinstall
- KitnEssentials now decodes and writes directly to SavedVariable (nuke-and-replace)
- Update popup "Later" button now suppresses popup until next version update
- Updated KitnEssentials profile data

## v1.0.3

### New Addon & Improvements

- Added BuffReminders profile import and loading support
- Detect newly available addon profiles in update flow (not just outdated ones)
- Update popup and chat messages now distinguish "Updated" vs "New" addons
- Fixed double-v prefix in version update popup text
- Dev-mode fallback for update popup when running from source
- BuffReminders shown in install list even when not loaded

## v1.0.2

### Bug Fix

- Fixed ElvUI private profileKey to always use base profile name

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
