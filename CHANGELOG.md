# [Changelog](https://github.com/Bmwascher/KitnUI/blob/main/CHANGELOG.md)

## v2.1.1 (unreleased)

### Installer
- **NEW:** BetterFriendlist is set up for you. The installer applies the Legacy interface style, the Dark theme, the General display options and the Expressway fonts, and marks that addon's own look picker as done so it does not ask you to choose again. Everything it writes is saved first, so `/kitn reset` gives your old settings back

### Profiles
- BigWigs and KitnEssentials profiles refreshed

## v2.1.0

Every bundled profile refreshed for 12.1, accents you can choose yourself, a
Tweaks section in the settings tab, richer Top Bar tooltips, and a set of fixes
for switches that said they were holding a setting when they were not.

### Settings Tab
- **NEW:** Pick your own accent colour. The pink switch became two rows: **KitnUI Accent Coloring** decides whether KitnUI colours your accent at all, and **Use KitnUI Pink** decides which colour it uses. Turn the second one off and a colour swatch appears; the places KitnUI colours, and the places it deliberately leaves alone, stay exactly the same
- **NEW:** A **Tweaks** section on the General page, holding Dark Class Resource Bar, Lulu Mode and a **Bite Mode** row marked Coming Soon
- The General page is now three labelled blocks: Appearance, Accents and Tweaks. Accent settings sit inside Appearance instead of standing alone
- The KitnUI pink accent now colours the quest tracker header instead of skipping the tracker entirely
- A colour change that cannot take effect now says so in chat instead of appearing to work. This happens on a profile copied from another one, where the switch travelled but the record of your original colour did not
- Dark and Colored now also set the power text colour on the unit frames. Dark puts the unit's own power colour on the number over the power bar; Colored makes it white, because the bar behind it already carries that colour

### Fixes
- Fixed a Cooldown Manager error that could clear your active layout and import nothing. Reimporting a CDM layout for a spec whose layout was already active made Blizzard's Cooldown Manager redraw inside KitnUI's call stack, which the game refuses.
- A switch that is ON no longer hands you KitnUI's own value back as though it were your original. Copying an EllesmereUI profile carried the switch but not the record of what was there before, and a re-apply then recorded KitnUI's forced value as yours. Only a real user action can write that record now
- Four forcing switches say on hover whether KitnUI is really holding your setting, or is only switched on. Nothing on screen distinguished those two states before
- **Lulu Mode** now holds the whole round minimap layout instead of the shape alone, and hands all of it back when you switch it off. On an upgrade it asks before claiming the extra settings
- The installer no longer reports success over a step that did nothing. A step that cannot import or load prints why, and the wizard counts it
- The installer now opens by itself on a first install. It was opening during login and the game closed it again a moment later, so a fresh setup saw no wizard at all, with nothing in chat to say why

### Top Bar
- **NEW:** Mouse-button pictures in the hearthstone and clock tooltips, so left, middle and right click are shown rather than described
- Right clicking the clock now opens EllesmereUI's settings instead of the stopwatch and alarm window. Left click still opens the calendar and middle click still reloads
- The clock tooltip drops its title and lays the three clicks out in two columns: which button on the left, what it opens on the right
- **NEW:** The clock tooltip lists your saved raid lockouts and the daily and weekly reset clocks
- **NEW:** Mythic+ portals on cooldown count down in the flyout, reading `8h`, `45m` or `30s`
- The portal flyout carries its own list of this season's eight dungeons
- Portal icons now light up correctly for account-wide teleports, which sit in the General spellbook
- The random hearthstone is rolled after you click, not before, so it cannot be spoiled by a tooltip. Fixed-destination stones are kept out of the roll
- The hearthstone tooltip no longer prints a raw item number while a stone's name is still loading
- The clock tooltip shows the clock the face is not showing, rather than repeating it
- The friends and guild counts walk the friends list once per update instead of once per event

### Profiles
- Every bundled profile refreshed for this release: EllesmereUI, BigWigs and its per-boss settings, BuffReminders, Northern Sky Raid Tools, KitnEssentials, Blizzard Edit Mode (both the normal and Lulu layouts) and all 40 Cooldown Manager layouts
- Edit Mode layouts rebuilt on the 12.1 format, which adds new frames the old layout did not know about

### Installer
- **NEW:** A nickname box on the Northern Sky Raid Tools step, on every one of its pages
- **NEW:** Dark and Colored buttons appear on the EllesmereUI step once the profile is imported
- Step names in the sidebar moved closer to the panel edge, with a smaller tick to make room
- The version number is printed once, through one helper, and is never stale
- The Baganator step now installs the whole Baganator profile, not the category groups alone. Bag and bank widths, icon corners, sorting, the skin and the junk plugin come with it. Window positions deliberately do not, so Baganator places its frames where it normally would

## v2.0.1

A compatibility release: EllesmereUI 8.8 and the newest Northern Sky Raid Tools
both changed underneath v2.0.0, and this fixes what those breaks took with them.

### Fixes
- Restored the KitnUI tab in EllesmereUI's settings panel on EllesmereUI v8.8+, which moved its options window into a load-on-demand addon. The same break also silently disabled KitnUI's entry in EllesmereUI's profile export list and the re-apply of KitnUI's settings switches after a profile or spec change; both are restored.
- Restored the nameplate arrows' untrusted-layout insurance (its version check died with EllesmereUI 8.8) and retired leftover EllesmereUIBasics handling in the installer
- Fixed the Northern Sky Raid Tools import failing with a decode error: newer NSRT versions export in a new format and keep their own profiles, so the installer now imports through NSRT's own profile import, and `/kitn load` puts alts on the KitnUI profile instead of doing nothing
- KitnUI now loads without EllesmereUI and says what to install, enable or update, instead of silently never loading - new users get a login prompt, users with an existing install get a chat line
- Having KitnUI Lite enabled alongside KitnUI no longer hijacks the /kitn commands, and a login prompt offers to disable Lite for you

## v2.0.0

### EllesmereUI Rework
- **NEW:** KitnUI now installs **EllesmereUI** profiles instead of ElvUI — EllesmereUI is the required dependency and the base UI it imports
- **NEW:** One profile instead of a set — every spec, healer included, is baked into a single import, and the **Dark** / **Colored** looks are a preset you switch in KitnUI's own tab
- **NEW:** Rebuilt the installer as a single-window, EllesmereUI-skinned wizard on custom KitnUI background art, replacing the old page-by-page flow
- Trimmed the companion set to BuffReminders, BigWigs, Northern Sky Raid Tools, KitnEssentials, Baganator, Blizzard Edit Mode, and per-spec Blizzard CDM (dropped Details, WarpDeplete, MRT, Ayije CDM)
- BigWigs now imports its per-boss settings alongside the main profile
- Plater is dormant, not removed — no Plater profile is offered, but `/kitn load` still reactivates one installed by an earlier version

### Top Bar
- **NEW:** KitnUI now draws its own top bar, with a clock, an FPS/latency readout, and a row of one-click launchers down each side (Group Finder, Encounter Journal, Achievements, Collections, Toy Box, Character, Spellbook, Talents, Professions, Volume, EllesmereUI settings, KitnEssentials, Game Menu, and more)
- **NEW:** Hearthstone launcher with independent left/middle/right-click stones — pick a specific stone or let it roll one at random, bag items and Toy Box entries both supported
- **NEW:** Mythic+ portal flyout for the current season's dungeon teleports
- **NEW:** Live friend and guild online counts and Great Vault progress
- Off by default — running the installer turns it on for you
- Configurable visibility: hide the bar in combat, pet battles, vehicles, or in keystones, raids and rated PvP
- Optional mouseover fade, resting the bar at low visibility until your mouse moves over it
- Draggable anywhere on screen from EllesmereUI's Unlock Mode

### Settings Tab
- **NEW:** A KitnUI tab inside EllesmereUI's config panel, with four pages: General, Gameplay, Nameplates and Top Bar
- **NEW:** **Lulu Mode** — an alternate layout with a round minimap, Blizzard's own action bars, and its own Edit Mode layout; it asks first, then reloads, and hands everything back when you switch it off
- **NEW:** **Beginner Mode** — tooltips, keybinds and key-press highlights on the Cooldown Manager, with Action Bars 1, 2, 3 and 5 always visible
- **NEW:** KitnUI target arrows for nameplates, with an optional additive glow
- **NEW:** Optional KitnUI pink accent for EllesmereUI, kept off the quest tracker, Mythic+ timer, damage meter and Friends tab
- Combat tooltip hiding, either for every tooltip or for Cooldown Manager tooltips alone

### Installer
- **NEW:** Clickable step sidebar with real per-profile import state (green check = actually imported) and a highlighted current step — click any step to jump straight to it and (re)install a single profile
- **NEW:** Active-variant indicator marks which EllesmereUI look is currently live
- **NEW:** Extras page — optional one-click chat setup, KitnEssentials settings optimization, and companion minimap-icon cleanup
- **NEW:** Finish summary recaps which profiles were imported, which were skipped, and which extras were run
- CDM layouts are now tracked per spec by content, not by a single version number — editing one spec's layout no longer prompts you to reimport the rest, and a layout imported by an older version is reported as untracked rather than up to date
- Traffic-light status (Imported / Update available / Not Imported) backed by date-based profile versioning
- A step that cannot import or load now says so instead of reporting success — Load All reports how many profiles it could not load, and a Baganator profile whose category data is missing or unreadable is refused outright rather than written half-formed
- Esc closes the installer; the `/kitn` command set gains `/kitn options`

---

## v1.0.8 (never released)

Written but never tagged. Everything below shipped in v2.0.0 instead; the
Baganator payload it describes is the one v2.0.0 restored.

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
