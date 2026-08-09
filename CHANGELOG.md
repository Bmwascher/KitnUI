# [Changelog](https://github.com/Bmwascher/KitnUI/blob/main/CHANGELOG.md)

## v2.0.0

### EllesmereUI Rework
- **NEW:** KitnUI now installs **EllesmereUI** profiles instead of ElvUI — EllesmereUI is the required dependency and the base UI it imports (**Dark Mode** / **Class Color**, with healer specs auto-swapping to a dedicated healer layout)
- **NEW:** Rebuilt the installer as a single-window, EllesmereUI-skinned wizard on custom KitnUI background art, replacing the old page-by-page flow
- Trimmed the companion set to Plater, BuffReminders, BigWigs, Northern Sky Raid Tools, KitnEssentials, Blizzard Edit Mode, and per-spec Blizzard CDM (dropped Details, WarpDeplete, MRT, Ayije CDM, Baganator)

### Top Bar
- **NEW:** KitnUI now draws its own top bar, with a clock, an FPS/latency readout, and a row of one-click launchers down each side (Group Finder, Encounter Journal, Achievements, Collections, Toy Box, Character, Spellbook, Talents, Professions, Volume, EllesmereUI settings, KitnEssentials, Game Menu, and more)
- **NEW:** Hearthstone launcher with independent left/middle/right-click stones — pick a specific stone or let it roll one at random, bag items and Toy Box entries both supported
- **NEW:** Mythic+ portal flyout for the current season's dungeon teleports
- **NEW:** Live friend and guild online counts and Great Vault progress
- Off by default — running the installer turns it on for you
- Configurable visibility: hide the bar in combat, pet battles, vehicles, or in keystones, raids and rated PvP
- Optional mouseover fade, resting the bar at low visibility until your mouse moves over it
- Draggable anywhere on screen from EllesmereUI's Unlock Mode

### Installer
- **NEW:** Clickable step sidebar with real per-profile import state (green check = actually imported) and a highlighted current step — click any step to jump straight to it and (re)install a single profile
- **NEW:** Active-variant indicator marks which EllesmereUI color mode is currently live
- **NEW:** Extras page — optional one-click chat setup, KitnEssentials settings optimization, and companion minimap-icon cleanup
- **NEW:** Finish summary recaps which profiles were imported, which were skipped, and which extras were run
- Traffic-light status (Imported / Update available / Not Imported) backed by date-based profile versioning
- Esc closes the installer; the `/kitn` command set is unchanged

---

## v1.0.8

### New Addon Support

- Added Baganator profile import (category view, welcome popup dismissal)
- Creates a named "KitnUI" profile in BAGANATOR_CONFIG — user changes persist across reloads (avoids AUI's reset-on-reload behavior)
- Added Baganator and BuffReminders to `/kitn version` output (BuffReminders was missing)

## v1.0.7

### Bug Fix & Data Updates

- Fixed MRT profile font and texture paths (single backslashes → double backslashes)
- Updated KitnEssentials profile data
- Removed redundant "v" prefix from version display in help text
- Added .luacheckrc and CLAUDE.md to .gitignore

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
