# KitnUI

A guided **EllesmereUI** profile installer — one-click setup for a complete, curated interface.

KitnUI walks you through configuring EllesmereUI and its companion addons with a step-by-step, EllesmereUI-skinned installer. Import each profile with a single click, run a few optional cleanups, and load the whole set on every alt. Apart from its own top bar, KitnUI creates no UI — it installs pre-configured profiles into the addons you already have and silently skips the rest.

## Features

- **Step-by-step installer** — an EllesmereUI-skinned wizard with a clickable step sidebar; jump straight to any step to (re)install a single profile
- **One EllesmereUI profile** — every spec, healer included, is baked into a single import; swap between the **Dark** and **Colored** looks from KitnUI's own tab in the EllesmereUI panel
- **Top bar** — KitnUI's own bar across the top of the screen: clock, FPS and latency, friend and guild counts, Great Vault progress, a hearthstone roller, a Mythic+ portal flyout, and one-click launchers for the panels you open most
- **Settings tab** — a KitnUI tab inside EllesmereUI's config panel with four pages: General, Gameplay, Nameplates and Top Bar
- **Lulu Mode** — an alternate layout with a round minimap, Blizzard's own action bars, and its own Edit Mode layout
- **One-click loading** — apply every installed profile to a new character with `/kitn load`
- **Smart updates** — reimport only the profiles that have changed
- **Per-spec CDM** — Blizzard Cooldown Manager layouts tailored per spec, tracked per spec so one edited layout does not prompt you to reimport the rest
- **Extras** — optional one-click chat setup, KitnEssentials settings optimization, and companion minimap-icon cleanup
- **Live status** — traffic-light state per profile (Imported / Update available / Not Imported) with an install summary at the end

## Supported Addons

| Addon | Profile |
|---|---|
| **EllesmereUI** *(required)* | Full UI — unit frames, action bars, nameplates, cast bars; Dark and Colored looks |
| BuffReminders | Missing buff / food / flask reminders |
| BigWigs | Boss timers and warnings, plus per-boss settings |
| Northern Sky Raid Tools | Raid assignments, timers, and note sync |
| KitnEssentials | Combat, dungeon, and QoL profiles |
| Baganator | Category-sorted bags and bank |
| Blizzard Edit Mode | HUD frame layout |
| Blizzard CDM | Per-spec Cooldown Manager layouts |

Every companion is optional — KitnUI installs profiles only for the addons you actually have.

## Requirements

- **EllesmereUI** (required)

## Slash Commands

`/kitn` (also `/kitnui` and `/kui`) is the base command for all of the below.

| Command | Description |
|---|---|
| `/kitn` | List all commands |
| `/kitn install` | Open the full installer |
| `/kitn update` | Reimport only profiles that have been updated |
| `/kitn load` | Apply installed profiles to this character |
| `/kitn cdm` | Open the Blizzard CDM importer for the current class |
| `/kitn options` | Open the KitnUI tab in EllesmereUI's config panel |
| `/kitn version` | Show addon and per-profile version info |
| `/kitn reset` | Reset installer state (does not remove addon profiles) |

## Credits

Built on **EllesmereUI**'s public theming builders — thanks to that project for the toolkit KitnUI's installer is skinned with.

## Related Addons

- **KitnEssentials** — Standalone combat, QoL, and skinning modules
- **KitnUI Lite** — Standalone profile installer for popular addons (no EllesmereUI required)
