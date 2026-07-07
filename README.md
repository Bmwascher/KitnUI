# KitnUI

An **EllesmereUI** profile installer — guided, one-click setup for a complete, curated interface.

KitnUI walks you through configuring EllesmereUI and its companion addons with a step-by-step installer skinned to match. Pick your color mode, import each profile with a single click, run a few optional cleanups, and load the whole set on every alt.

> **Requires EllesmereUI.** KitnUI creates no UI of its own — it installs pre-configured profiles into EllesmereUI and whichever companion addons you have installed, and silently skips the rest.

## Features

- **Step-by-step installer** — an EllesmereUI-skinned wizard with a clickable step sidebar; jump straight to any step to (re)install a single profile
- **Dark Mode & Class Color** — two EllesmereUI looks, with healer specs auto-swapping to a dedicated healer layout
- **One-click loading** — apply every installed profile to a new character with `/kitn load`
- **Smart updates** — `/kitn update` reimports only the profiles that have changed
- **Per-spec CDM** — Blizzard Cooldown Manager layouts tailored per spec, from the installer or a dedicated `/kitn cdm` flow
- **Extras** — optional one-click cleanups: full chat setup, KitnEssentials settings optimization, and companion minimap-icon cleanup
- **Live status** — traffic-light state per profile (Imported / Update available / Not Imported) with a summary of what was imported, skipped, and run at the end
- **Auto-detection** — prompts new characters to load profiles and notifies you when updated profiles are available

## Supported Addons

| Addon | Profile |
|---|---|
| **EllesmereUI** *(required)* | Full UI — unit frames, action bars, nameplates, cast bars; Dark Mode / Class Color, plus healer variants |
| Plater Nameplates | Nameplate styling matched to KitnUI |
| BuffReminders | Missing buff / food / flask reminders |
| BigWigs | Boss timers and warnings |
| Northern Sky Raid Tools | Raid assignments, timers, and note sync |
| KitnEssentials | Combat, dungeon, and QoL profiles |
| Blizzard Edit Mode | HUD frame layout |
| Blizzard CDM | Per-spec Cooldown Manager layouts |

Every companion is optional — KitnUI installs profiles only for the addons you actually have.

## Requirements

- **EllesmereUI** (required)

## Slash Commands

- `/kitn` — Show all available commands
- `/kitn install` — Open the full installer
- `/kitn update` — Reimport only profiles that have been updated
- `/kitn load` — Apply installed profiles to this character
- `/kitn cdm` — Open the Blizzard CDM importer for the current class
- `/kitn version` — Show addon and per-profile version info
- `/kitn reset` — Reset installer state (does not remove addon profiles)

## Related Addons

- **KitnEssentials** — Standalone combat, QoL, and skinning modules
- **KitnUI Lite** — Standalone profile installer for popular addons (no EllesmereUI required)
