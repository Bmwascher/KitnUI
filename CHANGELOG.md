# [Changelog](https://github.com/Bmwascher/KitnUI/blob/main/CHANGELOG.md)

## v2.2.0

### EllesmereUI Profile Update

- **NEW:** **Update Profile** keeps your changes. A newer KitnUI profile
  comes in on top of what you changed; where you both changed the same
  setting KitnUI's version is used, and the confirm shows how many
- **NEW:** **Restore previous** puts back the profile you had before the
  last update, and sits beside the update button. **Reset to KitnUI's
  profile** is still there for a clean start
- A part placed against or sized to a part you are keeping shows a warning
  band, with a button to take both
- The update and reset confirms group their parts and counts, and a confirm
  that would replace your changes says **Replace**
- Every message plays a sound and repeats in chat. A failed update keeps
  its message short with the error on its own line, a failure that changed
  your UI scale tells you to `/reload`, and `/kitn reset` says where your
  previous profile went
- Works again on EllesmereUI 9.2.9, which said "Update needs a newer
  EllesmereUI" and offered only a full reset
- Keeps the Extra Width and Extra Height you set on size-matched elements
  instead of clearing them. When KitnUI re-points a link you had tuned,
  your extra goes with the old link and counts as one of your changes
  replaced
- Spec Overrides saved by EllesmereUI 9.2.9 no longer read as changed by
  you when you have not touched them
- Keeps the "Pull Colors From" profile each color section can pick in
  EllesmereUI 9.4, and the confirm no longer opens with a blank band

### EllesmereUI Modules

- **NEW:** **Modules** on the EllesmereUI step lists each part of your
  profile on its own: Action Bars, Unit Frames, Resource & Cast Bars, the
  Top Bar and the rest
- Each row shows whether you changed that part since KitnUI installed it
  and what KitnUI's next update would change; hover a count to see the
  settings
- **NEW:** Untick a part to keep yours through an update, and take it any
  time later from Modules
- **NEW:** **Reset** on a row puts just that part back to KitnUI's
  version; **Restore previous** undoes it
- Right after an install or an update a part reads "Reload to Check" until
  your next reload, so values EllesmereUI adjusts on load don't count as
  your changes
- With no record of what KitnUI installed, a part that differs shows how
  many settings differ, such as "Differs - 18", and hovering lists them
- Hover lists name Cooldown Manager specs, spells and trinket slots, Top
  Bar settings and the spells in aura lists instead of bare IDs
- The update and Modules pages are redrawn: a dark panel behind the list,
  taller rows, colored badges such as "Changed by You - 12", tick boxes
  with a check or a cross, and nothing dimmed

### Installer

- **NEW:** **Skip until next update** on a step whose profile is new or
  has an update waiting (Blizzard Cooldown Manager excepted). A skipped
  profile stays out of the login reminder, the update popup and
  `/kitn update` until KitnUI ships a newer one; installing it clears the
  skip
- The step list marks a skipped step in amber, and the finish page lists
  it on its own
- **Load All** in `/kitn load` goes straight to the finish page when every
  profile loads, and stays on the failing step when one doesn't
- `/kitn load` has a **Blizzard Cooldown Manager** step, since each
  character needs its own copy of the layouts
- The login prompts take only **Later** or **No** as an answer. Escape, or
  a prompt that never reached the screen, used to count as No and could
  silence it for good
- The window is a little larger so long counts fit their column, the
  filled buttons are softer, and the **Modules** button sits beside the
  profile status
- New KitnUI and KitnUI Rasta backgrounds with a constellation cat
- Slash commands in KitnUI's popups, chat messages and `/kitn` help are
  highlighted

### Top Bar

- After teleporting home from the housing dashboard, the Home button
  offers **Return to Previous Location** again, and keeps it across a
  reload and after you hearth away
- **Reset Positions** shows its tooltip again
- The friends badge refreshes every 30 seconds and reads far less of your
  friends list, so a large list no longer piles up memory

### Settings Tab

- **NEW:** **Accent Source** picks where the accent color comes from:
  KitnUI Pink, Rasta Amber, Custom, or **Match KitnEssentials**, which takes
  KitnEssentials' theme color and follows it when it changes. The swatch
  always shows the color in use and is editable on Custom
- KitnUI Pink setups now match KitnEssentials. Its default theme is the
  same pink, so the accent only changes if you picked another KitnEssentials
  theme color. Rasta Amber and custom colors carry over
- The KitnUI section registers through EllesmereUI's plugin support, so it
  keeps working as EllesmereUI updates and its settings show up in the
  options search. It needs EllesmereUI 9.4 or newer, and like other add-on
  sections it is locked while you edit Spec Overrides
- The KitnUI and KitnUI Rasta options backgrounds are redrawn for
  EllesmereUI 9.4's title bar and fold away with the panel, and the folded
  mini window shows the KitnUI cat

### Profiles

- EllesmereUI, KitnEssentials, BigWigs, Northern Sky Raid Tools, Edit Mode,
  BuffReminders and Baganator profiles refreshed
- The EllesmereUI profile no longer carries Quickdraw, so an update leaves
  your Quickdraw settings alone
- BetterFriendlist installs in its Modern style, sorted by status then
  name, in Simple Mode with search and whispering on a double click. The
  side tabs are reordered, Guild is hidden, and Friend Requests appears
  only when a request is waiting. `/kitn reset` puts your own settings back

---

## v2.1.6

### Settings Tab

- **NEW:** **Bite Mode** swaps your cast bar and power bar on the specs
  that use an emphasized cast bar, darkens the cast bar and hides its spell
  name. Other specs take only the cast bar changes. It needs no reload, and
  switching it off hands everything back
- **NEW:** **Dark Cast Bar** darkens the cast bar on its own, without
  touching the class resource bar, unit frames or raid frames. Bite Mode
  turns it on and then leaves it to you
- **NEW:** **Dark Class Resource Bar** lights the seams between the bar's
  segments instead of leaving them black; switching it off gives your own
  spacing color back
- Turning off EllesmereUI's own Dark Mode for the class resource bar hands
  the seam color back at once. A color you set yourself while KitnUI held
  it is left alone

### Profiles

- BuffReminders and KitnEssentials profiles refreshed, plus 21 Cooldown
  Manager layouts across Warrior, Paladin, Hunter, Priest, Death Knight,
  Druid, Demon Hunter and Evoker

### General

- About 2 MB smaller to download and about 7 MB smaller on disk. The
  artwork is unchanged, and two unused texture files are gone

---

## v2.1.5

### Options Themes

- **NEW:** **KitnUI** and **KitnUI Rasta** themes sit under EllesmereUI in
  the Options Theme dropdown. They differ in artwork only and both keep the
  KitnUI pink accent
- **NEW:** **Use Rasta Amber**, in the Accents section, sets the accent to
  the amber the Rasta artwork is built around
- Each character is matched to one theme. Your first install applies that
  match to the account; later installs leave the theme alone, so a theme
  you pick yourself stays

### Installer

- **NEW:** The Welcome page lets you pick either installer theme for the
  character you are on; the window repaints at once and the choice is
  remembered
- On Rasta characters the installer uses the warm amber for its progress
  bar, buttons, side rail and text. Chat messages stay KitnUI pink
- The installer window follows the character you are on, not the account
- **NEW:** A page that is already up to date shows its Install button as
  done and points you at **Next**. A profile with a newer version waiting
  reads **Update**
- **NEW:** The Cooldown Manager page marks each specialization with a
  tick, a warning or a cross and shows your spec icons, and **Import All
  Specs** stays highlighted until every layout is in
- The EllesmereUI page keeps **Dark** and **Colored** on their own row
  under an **APPEARANCE** heading
- Buttons no longer lose their highlight the first time the mouse passes
  over them
- **Chat Setup** no longer leaves Trade and Services on the General tab.
  General carries only General and LocalDefense; channels you joined
  yourself are untouched

---

## v2.1.4

### Top Bar

- After teleporting to housing, the Home button's left click becomes
  **Return to Previous Location**, even when the Housing Dashboard started
  the teleport or picked another of your houses

### Settings Tab

- The Dark, Colored and Custom preset is labeled **Unit Frame Appearance**
- The Edit Mode warning describes KitnUI's Cooldown Manager
  **configuration** rather than calling it a layout

### General

- The installer and both AddOns-list entries use the same purple cat icon
  as KitnEssentials, and the `_EUI` suffix is white

---

## v2.1.3

### Installer

- **NEW:** KitnUI notices when the spec you are playing isn't using its
  Edit Mode or Cooldown Manager layout and offers to switch. The game keeps
  these per spec, and the installer only ever set the one you were on
- The prompt names the spec, asks before it changes anything, and has a
  **Never for this spec** button
- The Edit Mode switch applies at once; the Cooldown Manager switch needs a
  reload, and the prompt says so
- It stays quiet on a character you have never set up
- **No** stays quiet for that spec until your next login. Escape is not an
  answer, so it asks again the next time you switch to that spec
- With Lulu Mode on, the prompt names the Lulu layout
- Loading the Edit Mode layout is refused during a fight instead of
  attempted, with a note in chat
- EllesmereUI's Data Bars module is switched off at install, since the Edit
  Mode profile already places Blizzard's experience and reputation bar

### Top Bar

- **NEW:** **Show Clock** turns the bar's clock off. The two halves close
  into one run of icons with a dimmed divider, and the minimap gets its own
  clock back
- Clock Size, 24-Hour Clock and Server Time gray out while the clock is off
- **NEW:** **Accent Opacity** sets how solid the accent line along the
  bottom is; at zero, with Panel Backdrop off, the bar has no background
- Opening the dungeon portal flyout during a fight, an encounter, a
  keystone or a rated match no longer errors

### Profiles

- The Lulu Edit Mode layout moves the pet bar and a couple of side bars so
  they stop clipping other parts of the UI
- KitnEssentials and Northern Sky Raid Tools profiles refreshed

---

## v2.1.2

### Installer

- Loading profiles on an alt finishes in one pass. **Load All** applies
  everything as it goes, so a reload asked for by another addon no longer
  loses your place
- **NEW:** **Load All** also imports the Cooldown Manager layouts for your
  class, which belong to each character rather than the account
- **NEW:** When Blizzard's five-layout limit blocks an import, KitnUI names
  the specs it could not fit, in chat and in a popup after the reload, and
  reminds you to delete unused layouts and run `/kitn cdm`
- Cooldown Manager layouts are named like **KitnUI - Frost** instead of
  **KUI - Frost**, and a layout under either name is replaced
- The wizard no longer reports success over a Cooldown Manager step that
  did nothing because the Cooldown Manager was switched off

---

## v2.1.1

### Installer

- **NEW:** BetterFriendlist is set up for you: the Legacy style, the Dark
  theme, the General display options and the Expressway fonts, with its own
  look picker marked done. Your old settings are saved first, so
  `/kitn reset` brings them back

### Profiles

- BigWigs profiles refreshed, including per-boss settings, and
  KitnEssentials
- **NEW:** The BigWigs profile turns off **Boss debuffs on you**, which a
  BigWigs export cannot carry
- **NEW:** Northern Sky Raid Tools reminder frames arrive locked instead of
  leaving a resize grip floating over the world

---

## v2.1.0

### Settings Tab

- **NEW:** Pick your own accent color. **KitnUI Accent Coloring** decides
  whether KitnUI colors your accent, and **Use KitnUI Pink** decides which
  color; turn the second off for a color swatch
- **NEW:** A **Tweaks** section on the General page, with Dark Class
  Resource Bar, Lulu Mode and a Bite Mode row marked Coming Soon
- The General page is three labeled blocks: Appearance, Accents and Tweaks
- The KitnUI pink accent colors the quest tracker header
- A color change that cannot take effect says so in chat instead of
  appearing to work
- Dark and Colored also set the power text color on the unit frames
- A switch that is on no longer hands back KitnUI's own value as your
  original after a profile copy
- Four forcing switches say on hover whether KitnUI is really holding your
  setting or is only switched on
- **Lulu Mode** holds the whole round minimap layout, not just the shape,
  and hands all of it back when you switch it off

### Installer

- **NEW:** A nickname box on the Northern Sky Raid Tools step
- **NEW:** Dark and Colored buttons on the EllesmereUI step once the
  profile is imported
- The installer opens by itself on a first install; it used to close again
  a moment after login
- A step that cannot import or load says why instead of reporting success
- Reimporting a Cooldown Manager layout for a spec whose layout was already
  active no longer clears it and imports nothing
- The Baganator step installs the whole Baganator profile, not just the
  category groups; window positions are left to Baganator
- Step names sit closer to the panel edge, with a smaller tick

### Top Bar

- **NEW:** Mouse-button pictures in the hearthstone and clock tooltips
- Right-clicking the clock opens EllesmereUI's settings; left click still
  opens the calendar and middle click still reloads
- The clock tooltip lays the three clicks out in two columns and shows the
  clock the face is not showing
- **NEW:** The clock tooltip lists your saved raid lockouts and the daily
  and weekly reset timers
- **NEW:** Mythic+ portals on cooldown count down in the flyout, as `8h`,
  `45m` or `30s`
- The portal flyout carries this season's eight dungeons, and account-wide
  teleports light up correctly
- The random hearthstone is rolled after you click, so a tooltip can't
  spoil it, and fixed-destination stones stay out of the roll
- The hearthstone tooltip no longer shows a raw item number while a stone's
  name loads
- The friends and guild counts read the friends list once per update
  instead of once per event

### Profiles

- Every bundled profile refreshed for 12.1: EllesmereUI, BigWigs with its
  per-boss settings, BuffReminders, Northern Sky Raid Tools,
  KitnEssentials, both Edit Mode layouts and all 40 Cooldown Manager
  layouts
- Edit Mode layouts rebuilt on the 12.1 format, with the new frames it adds

---

## v2.0.1

### Settings Tab

- The KitnUI tab is back in EllesmereUI's settings on EllesmereUI 8.8 and
  newer, along with its entry in the profile export list and the re-apply
  of KitnUI's switches after a profile or spec change
- The nameplate arrows' layout safeguard works again on EllesmereUI 8.8

### Installer

- The Northern Sky Raid Tools import no longer fails with a decode error;
  it goes through NSRT's own profile import, and `/kitn load` puts alts on
  the KitnUI profile
- KitnUI loads without EllesmereUI and says what to install, enable or
  update: new users get a login prompt, existing installs a chat line
- With KitnUI Lite enabled too, the `/kitn` commands stay KitnUI's, and a
  login prompt offers to disable Lite

---

## v2.0.0

### EllesmereUI Rework

- **NEW:** KitnUI installs **EllesmereUI** profiles instead of ElvUI.
  EllesmereUI is required and is the base UI
- **NEW:** One profile instead of a set: every spec, healers included, is
  in one import, and **Dark** and **Colored** are a preset in KitnUI's tab
- **NEW:** A single-window installer in EllesmereUI's style, on KitnUI
  background art
- The companion set is BuffReminders, BigWigs, Northern Sky Raid Tools,
  KitnEssentials, Baganator, Blizzard Edit Mode and per-spec Blizzard
  Cooldown Manager; Details, WarpDeplete, MRT and Ayije CDM are dropped
- BigWigs imports its per-boss settings with the main profile
- Plater is dormant: no Plater profile is offered, but `/kitn load` still
  reactivates one installed by an earlier version

### Top Bar

- **NEW:** KitnUI draws its own top bar: a clock, an FPS and latency
  readout, and one-click launchers down each side (Group Finder, Encounter
  Journal, Achievements, Collections, Toy Box, Character, Spellbook,
  Talents, Professions, Volume, EllesmereUI settings, KitnEssentials, Game
  Menu and more)
- **NEW:** A hearthstone launcher with its own stone on left, middle and
  right click, a fixed stone or a random roll, from bags or the Toy Box
- **NEW:** A Mythic+ portal flyout for this season's dungeon teleports
- **NEW:** Live friend and guild online counts and Great Vault progress
- Off by default; the installer turns it on
- Hide it in combat, pet battles, vehicles, keystones, raids or rated PvP
- An optional mouseover fade rests the bar at low visibility
- Drag it anywhere from EllesmereUI's Unlock Mode

### Settings Tab

- **NEW:** A KitnUI tab in EllesmereUI's settings with four pages:
  General, Gameplay, Nameplates and Top Bar
- **NEW:** **Lulu Mode**: an alternate layout with a round minimap,
  Blizzard's own action bars and its own Edit Mode layout. It asks first,
  reloads, and hands everything back when you switch it off
- **NEW:** **Beginner Mode**: tooltips, keybinds and key-press highlights
  on the Cooldown Manager, with Action Bars 1, 2, 3 and 5 always visible
- **NEW:** KitnUI target arrows for nameplates, with an optional glow
- **NEW:** An optional KitnUI pink accent for EllesmereUI, kept off the
  quest tracker, Mythic+ timer, damage meter and Friends tab
- Hide tooltips in combat: all of them, or the Cooldown Manager's only

### Installer

- **NEW:** A clickable step sidebar showing what is really imported, with
  the current step highlighted; click a step to install one profile again
- **NEW:** A marker shows which EllesmereUI look is live
- **NEW:** An Extras page: chat setup, KitnEssentials optimization and
  minimap icon cleanup, one click each
- **NEW:** A finish summary of what was imported, skipped and run
- Cooldown Manager layouts are tracked per spec, so editing one spec's
  layout no longer asks you to reimport the rest
- Each step reads Imported, Update available or Not Imported
- A step that cannot import or load says so instead of reporting success
- Escape closes the installer, and `/kitn options` is new

---

## v1.0.8 (never released)

### Baganator

- Written but never tagged; everything here shipped in v2.0.0 instead
- **NEW:** Baganator profile import, with the category view and the
  welcome popup dismissed, saved as a "KitnUI" profile so your changes
  persist
- `/kitn version` lists Baganator and BuffReminders

---

## v1.0.7

### Profiles

- MRT profile fonts and textures load again
- KitnEssentials profile refreshed

### Slash Commands

- The help text no longer prints a doubled "v" before the version

---

## v1.0.6

### Profiles

- The ElvUI private profile (Parchment Remover) applies again
- KitnEssentials profile refreshed with its new modules, and BuffReminders
  refreshed

---

## v1.0.5

### Installer

- Details imports its auto-run scripts, including one that switches the
  display between dungeons and raids
- Edit Mode and Blizzard Cooldown Manager check the five-layout limit and
  show a red error when it is reached
- Import success messages show the addon name in color

### Profiles

- Details profile refreshed

---

## v1.0.4

### Installer

- Reinstalling KitnEssentials no longer creates a duplicate profile
- **Later** on the update popup holds it until the next version

### Profiles

- KitnEssentials profile refreshed

---

## v1.0.3

### Installer

- **NEW:** BuffReminders profile import and loading
- The update flow offers newly supported addons, not only outdated ones,
  and its popup and chat say "Updated" or "New"
- BuffReminders shows in the install list even when it isn't loaded
- The update popup no longer prints a doubled "v"

---

## v1.0.2

### Profiles

- The ElvUI private profile always uses the base profile name

---

## v1.0.1

### Profiles

- ElvUI profiles and ElvUI Private settings apply correctly
- **NEW:** KitnEssentials import (it was a placeholder)
- ElvUI class aura indicators are part of the global import
- Plater imports its full settings for consistent nameplates
- All ElvUI profiles (Dark, Color, Healer Dark, Healer Color, Private) and
  the Plater profile refreshed
- **NEW:** Ayije CDM Bite profile

### Installer

- The Blizzard Cooldown Manager import no longer causes taint errors

---

## v1.0.0

### Initial Release

- ElvUI profile installer with step-by-step guided setup
- Dark and Color variants with DPS and Healer layouts
- Profiles for Details, Plater, BigWigs, WarpDeplete, MRT, Edit Mode, Ayije
  CDM and KitnEssentials
- Blizzard Cooldown Manager layouts for all 40 specs
- Install, Update, Load and Cooldown Manager flows
- Per-addon version tracking that knows what needs an update
- Offers to load profiles on a new character
- Minimap icon cleanup for Details, BigWigs, Plater, SimulationCraft, Wago
  and MRT
- 1440p UI scale set for you
- `/kitn install`, `/kitn update`, `/kitn load`, `/kitn cdm`,
  `/kitn version` and `/kitn reset`
