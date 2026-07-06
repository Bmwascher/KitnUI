# KitnUI v2 (EllesmereUI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate KitnUI from an ElvUI plugin/profile-installer into a standalone addon that installs a curated **EllesmereUI** profile (plus a trimmed companion set) through a hand-built wizard skinned with EllesmereUI's own public widget builders.

**Architecture:** KitnUI v2 stops registering as an ElvUI module. It becomes a standalone addon that hard-requires EllesmereUI, boots on `PLAYER_LOGIN`, and drives EllesmereUI through its public **WagoUI / LibAddonProfiles** API (`EllesmereUI.ImportProfile`, `AssignProfileToSpec`, `RefreshAllAddons`). The installer wizard is rebuilt from Blizzard `CreateFrame` scaffolding skinned with EllesmereUI's ungated helpers (`SolidTex` / `MakeBorder` / `MakeFont` / `MakeStyledButton` / `Build*Control` / `ShowConfirmPopup`). The v1 ElvUI code is frozen at a `v1.x` git tag and parked dormant in a `Legacy/` tree (TOC-excluded).

**Tech Stack:** Lua 5.1 (WoW embedded), WoW 12.0 "Midnight" client API, EllesmereUI 8.3.8 public API, LibSharedMedia-3.0, LibDeflate (via EllesmereUI), luacheck. No busted (see Verification Model).

## Verification Model (read before executing)

This project has **no automated UI test runner and no busted suite** (AGENTS.md). Every task therefore verifies with:

1. **`luacheck <file>`** after each `.lua` edit — must be warning/error clean against the repo `.luacheckrc`. In Claude Code this auto-runs via PostToolUse hook; other agents run it manually.
2. **In-game checkpoint** — an exact `/reload` + `/kitn …` sequence and what to observe in BugSack. **In-game verification is always Kitn's** (per project rule); an agent's task is "done" when luacheck is clean and the in-game checkpoint is *written and ready to run* — Kitn runs it and reports pass/fail before the next dependent task starts.

Where a value can only be confirmed in-game (an EllesmereUI internal field name, a module-disable path), the plan gives an **exact `/run` probe** to capture it — these are real verification steps, not placeholders.

## Reference Sources (read these; do not re-derive)

- **v1 code to port from** lives in `Legacy/` after Task 0.2 (originals: `Core.lua`, `Setup.lua`, `Installer.lua`).
- **EllesmereUI source** is cloned locally at `References/EllesmereUI-v8.3.8/EllesmereUI/`. Key files: `EllesmereUI_Profiles.lua` (import/export/activate API), `EllesmereUI_Widgets.lua` (widget builders), `EllesmereUI.lua` (globals, primitives, popups).
- **Project memory** `kitnui-v2-ellesmereui` (in `~/.claude/projects/.../memory/`) is the design of record.

## Global Constraints

Every task's requirements implicitly include this section.

- **Language/runtime:** Lua 5.1, WoW 12.0. Local variables over globals. camelCase local functions, PascalCase module-level functions.
- **Addon identity:** globals prefixed `KitnUI` / `KITNUI`. Print prefix `|cffFF008CKitn|r|cffffffffUI:|r` (available as `ns.title`).
- **SavedVariables:** `KitnUIDB` — declared in `KitnUI.toc` AND initialized in `Core.lua`. Leave the v1 `KitnUIElvDB` untouched (never declared in the v2 TOC).
- **Hard dependency:** `## RequiredDeps: EllesmereUI`. KitnUI never runs without it.
- **EllesmereUI is read-through-API only:** NEVER modify EllesmereUI core files. Only call `_G.EllesmereUI.*` functions and write `EllesmereUIDB`. Guard EVERY call: `if _G.EllesmereUI and EllesmereUI.<fn> then …`. The per-module `EllesmereUI*DB` globals are vestigial — never read/write them; all data lives in `EllesmereUIDB.profiles[name].addons[folder]`.
- **Idempotency:** running any install step twice produces the same result.
- **Bundled EllesmereUI string:** MUST be a **version-3** `!EUI_` export (`DecodeImportString` rejects other versions). Build against a fixture export until final art lands.
- **Git:** feature branch `feature/v2-ellesmereui`, never main. Commit messages lowercase, imperative, one logical change each. **No AI attribution / Co-Authored-By / Claude-Session trailers.**
- **luacheck** clean after every `.lua` edit.

---

## File Structure (end state on the feature branch)

**Active (listed in `KitnUI.toc`, loaded):**
- `KitnUI.toc` — rewritten manifest
- `Core.lua` — standalone bootstrap, SavedVariables, media, slash commands, version tracking, installer entry points
- `Setup.lua` — `ns.SetupAddon` dispatch: EllesmereUI handler + 7 kept companion handlers
- `UI/Wizard.lua` — generic EllesmereUI-skinned multi-page wizard frame (the `PluginInstaller` replacement)
- `Installer.lua` — KitnUI-specific pages/steps/modes, built on `UI/Wizard.lua`
- `Data/AddOns/EllesmereUI.lua` — the `!EUI_` v3 export string(s) (NEW; fixture first)
- `Data/AddOns/Plater.lua`, `BuffReminders.lua`, `BigWigs.lua`, `NSRT.lua`, `KitnEssentials.lua`, `EditMode.lua` — kept verbatim (EditMode content re-authored in Phase 4)
- `Data/Classes/BlizzardCDM.lua` — kept verbatim

**Dormant (in `Legacy/`, NOT in the TOC, present for reference; true rollback is the `v1.x` git tag):**
- `Legacy/Core.lua`, `Legacy/Setup.lua`, `Legacy/Installer.lua` — v1 originals (Setup.lua preserves all v1 SV-shape handlers)
- `Legacy/Data/AddOns/ElvUI/*.lua`, `Legacy/Data/AddOns/ElvUI_Anchor.lua`
- `Legacy/Data/AddOns/Details.lua`, `WarpDeplete.lua`, `MRT.lua`, `AyijeCDM.lua`, `Baganator.lua`

---

## Phase 0 — Branch, freeze, and park the ElvUI code

### Task 0.1: Create the feature branch

**Files:** none (git only)

- [ ] **Step 1: Branch off the current work branch**

The latest v1 code + data lives on `feature/v2-reference-updates` (WIP commit `7845149` — it rewrote Core/Setup/Installer/TOC and updated many Data files), NOT on `main`. Branch off it so the rewrite ports from the current state; branching off `main` would discard that work.

```bash
git checkout feature/v2-reference-updates
git checkout -b feature/v2-ellesmereui
```

- [ ] **Step 2: Confirm state**

Run: `git status`
Expected: `On branch feature/v2-ellesmereui`. A pending `.gitignore` edit (adds `AGENTS.md`) rides along uncommitted — it belongs to the user; leave it unstaged. `References/` is gitignored and stays local.

> Note: `main` (v1.0.7) is the pre-WIP release; the v1.x freeze tag in Task 4.5 is cut from the last released commit, not from this branch tip.

---

### Task 0.2: Park v1 ElvUI + dropped-companion files into `Legacy/`

**Files:**
- Move: `Core.lua` → `Legacy/Core.lua`
- Move: `Setup.lua` → `Legacy/Setup.lua`
- Move: `Installer.lua` → `Legacy/Installer.lua`
- Move: `Data/AddOns/ElvUI/` → `Legacy/Data/AddOns/ElvUI/`
- Move: `Data/AddOns/ElvUI_Anchor.lua` → `Legacy/Data/AddOns/ElvUI_Anchor.lua`
- Move: `Data/AddOns/Details.lua`, `WarpDeplete.lua`, `MRT.lua`, `AyijeCDM.lua`, `Baganator.lua` → `Legacy/Data/AddOns/`

**Interfaces:**
- Produces: `Legacy/` tree as the dormant reference the later tasks port verbatim code from (`Legacy/Setup.lua` = full v1 handler set incl. SV shapes; `Legacy/Installer.lua` = v1 page/step/mode logic).

- [ ] **Step 1: Move the files with git**

```bash
mkdir -p Legacy/Data/AddOns
git mv Core.lua Legacy/Core.lua
git mv Setup.lua Legacy/Setup.lua
git mv Installer.lua Legacy/Installer.lua
git mv Data/AddOns/ElvUI Legacy/Data/AddOns/ElvUI
git mv Data/AddOns/ElvUI_Anchor.lua Legacy/Data/AddOns/ElvUI_Anchor.lua
git mv Data/AddOns/Details.lua Legacy/Data/AddOns/Details.lua
git mv Data/AddOns/WarpDeplete.lua Legacy/Data/AddOns/WarpDeplete.lua
git mv Data/AddOns/MRT.lua Legacy/Data/AddOns/MRT.lua
git mv Data/AddOns/AyijeCDM.lua Legacy/Data/AddOns/AyijeCDM.lua
git mv Data/AddOns/Baganator.lua Legacy/Data/AddOns/Baganator.lua
```

- [ ] **Step 2: Confirm the active tree**

Run: `ls Data/AddOns`
Expected: only `BigWigs.lua BuffReminders.lua EditMode.lua KitnEssentials.lua NSRT.lua Plater.lua` remain (EllesmereUI.lua is added in Task 2.4). `Data/Classes/BlizzardCDM.lua` remains.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "move v1 elvui installer and dropped-addon data into legacy/"
```

> At this point the addon will NOT load (the TOC still references moved files) — that is fixed in Task 1.1. Do not `/reload` between here and Task 1.2.

---

## Phase 1 — Standalone bootstrap

### Task 1.1: Rewrite `KitnUI.toc`

**Files:**
- Modify: `KitnUI.toc` (full rewrite)

**Interfaces:**
- Produces: load order `Core.lua` → `Setup.lua` → `UI/Wizard.lua` → `Installer.lua` → data files; `## SavedVariables: KitnUIDB`; `## RequiredDeps: EllesmereUI`.

- [ ] **Step 1: Write the new TOC**

Replace the entire file with:

```
## Title: |cffFF008CKitn|r|cffffffffUI|r
## Notes: EllesmereUI profile installer for KitnUI.
## Author: Bitebtw
## Version: @project-version@
## Interface: 120007
## RequiredDeps: EllesmereUI
## OptionalDeps: Plater, BigWigs, NorthernSkyRaidTools, KitnEssentials, BuffReminders
## SavedVariables: KitnUIDB
## IconTexture: Interface\Icons\INV_Misc_Gift_05
## Category-enUS: |cffFF008CKitn|rUI
## X-Curse-Project-ID: 1493282
## X-Wago-ID: rNkyB8Ka

## X-EllesmereUI-Version: 2.0
## X-Plater-Version: 1.1
## X-BigWigs-Version: 1.0
## X-NSRT-Version: 1.0
## X-EditMode-Version: 1.0
## X-KitnEssentials-Version: 1.4
## X-BuffReminders-Version: 1.1
## X-BlizzardCDM-Version: 1.0

Core.lua

UI\Wizard.lua

Setup.lua
Installer.lua

# Profile Data - EllesmereUI
Data\AddOns\EllesmereUI.lua

# Profile Data - Companions
Data\AddOns\Plater.lua
Data\AddOns\BigWigs.lua
Data\AddOns\NSRT.lua
Data\AddOns\EditMode.lua
Data\AddOns\KitnEssentials.lua
Data\AddOns\BuffReminders.lua

# Profile Data - Classes
Data\Classes\BlizzardCDM.lua
```

> **Execution note (incremental load):** `Setup.lua`, `UI\Wizard.lua`, `Installer.lua`, and `Data\AddOns\EllesmereUI.lua` do not exist until Phases 2–3. When executing, write the TOC WITHOUT those four lines and add each one in the task that creates the file (Tasks 2.1, 3.1, 3.2, 2.4). The block above is the final end-state TOC; only list files that exist so `/reload` stays clean at each checkpoint.

- [ ] **Step 2: Confirm `## Interface` against the live build**

Run (in-game, Kitn): `/run print((select(4, GetBuildInfo())))`
Expected: a number like `120007`. If it differs, set `## Interface` to that value. Cross-check `References/EllesmereUI-v8.3.8/EllesmereUI/EllesmereUI.toc`'s Interface line.

- [ ] **Step 3: Commit**

```bash
git add KitnUI.toc
git commit -m "rewrite toc for standalone ellesmereui installer"
```

---

### Task 1.2: Rewrite `Core.lua` as a standalone bootstrap

**Files:**
- Create: `Core.lua` (new standalone version; the v1 one is at `Legacy/Core.lua`)

**Interfaces:**
- Consumes: EllesmereUI globals (guarded).
- Produces (used by Setup.lua and Installer.lua via the `ns` table):
  - `ns.title` (string), `ns.profileName = "KitnUI"`, `ns.version` (string), `ns.data` (table), `ns.db` (KitnUIDB), `ns.FONT` (path)
  - `ns.Color/Green/Red/ClassColor(text) -> string`
  - `ns.GetAddonDataVersion(addonKey) -> string|nil`, `ns.GetOutdatedAddons() -> table`
  - `ns.IsAddOnAvailable(addon) -> bool`, `ns.EUIReady() -> bool`
  - `ns.OpenInstaller(profileLoadMode, updateKeys, cdmMode)` (assigned by Installer.lua in Task 3.3; Core only calls it)
  - `KitnCommands` table + `/kitn` `/kitnui` `/kui` slash handler

- [ ] **Step 1: Write the standalone Core.lua**

Port the framework-agnostic pieces from `Legacy/Core.lua` verbatim, and replace the ElvUI-coupled pieces. Concretely:

**Keep verbatim from `Legacy/Core.lua`** (they have no ElvUI dependency): the `addonVersionHeaders` map (pruned to the kept keys below), `ns.GetAddonDataVersion`, `ns.GetOutdatedAddons`, `ns.Color/Green/Red/ClassColor`, `GetCharKey`, `ns.IsCharLoaded/SetCharLoaded`, the `KitnCommands` table and `SLASH_KITN*` handler, and the `ConfirmOverwriteInstall` popup.

**Prune** `addonVersionHeaders` to:
```lua
local addonVersionHeaders = {
    EllesmereUI     = "X-EllesmereUI-Version",
    Plater          = "X-Plater-Version",
    BigWigs         = "X-BigWigs-Version",
    NSRT            = "X-NSRT-Version",
    Blizzard_EditMode = "X-EditMode-Version",
    KitnEssentials  = "X-KitnEssentials-Version",
    BuffReminders   = "X-BuffReminders-Version",
    BlizzardCDM     = "X-BlizzardCDM-Version",
}
```

**Replace** the ElvUI header/module/media block with a standalone header:

```lua
local addonName, ns = ...

local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

-- Media
local FONT_PATH = "Interface\\AddOns\\KitnUI\\Media\\Fonts\\Expressway.TTF"
local BAR_TEXTURE_PATH = "Interface\\AddOns\\KitnUI\\Media\\Statusbars\\KitnUI_Bar"
ns.FONT = FONT_PATH

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM then
    LSM:Register("font", "Expressway", FONT_PATH)
    LSM:Register("statusbar", "KitnUI", BAR_TEXTURE_PATH)
end

-- Shared namespace
ns.title = "|cffFF008CKitn|r|cffffffffUI|r"
ns.profileName = "KitnUI"
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version")
ns.data = ns.data or {}
ns.db = nil

-- EllesmereUI readiness guard (used before touching EUI API / showing the wizard)
function ns.EUIReady()
    return _G.EllesmereUI and EllesmereUI.ImportProfile and true or false
end
```

**Replace** SavedVariables defaults + `Initialize` (which was an ElvUI-module callback) with an event-driven bootstrap:

```lua
local defaults = {
    profiles = {},          -- [addonKey] = true when imported
    addonVersions = {},     -- [addonKey] = X-header version at import time
    installedVersion = nil,
    perChar = {},           -- [charName-realm] = { loaded = true/false }
    devMode = false,
}

local function InitDB()
    if not KitnUIDB then KitnUIDB = CopyTable(defaults) end
    ns.db = KitnUIDB
    ns.db.profiles = ns.db.profiles or {}
    ns.db.addonVersions = ns.db.addonVersions or {}
    ns.db.perChar = ns.db.perChar or {}
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    InitDB()

    -- First-run / update / new-char entry logic (ported from Legacy/Core.lua
    -- KitnUI:Initialize, minus all ElvUI-private writes). ns.OpenInstaller is
    -- assigned by Installer.lua (Task 3.3); guard on ns.EUIReady() first.
    if not ns.EUIReady() then
        print(ns.title .. ": EllesmereUI not detected — installer unavailable.")
        return
    end

    local hasProfiles = ns.db.profiles and next(ns.db.profiles)
    if not hasProfiles and not ns.db.installedVersion then
        if ns.OpenInstaller then ns.OpenInstaller() end
    elseif hasProfiles and not ns:IsCharLoaded() then
        StaticPopupDialogs["KITNUI_LOAD"] = {
            text = ns.title .. ": Load your installed profiles onto this character?",
            button1 = "Yes", button2 = "No",
            OnAccept = function() if ns.OpenInstaller then ns.OpenInstaller(true) end end,
            OnCancel = function() ns:SetCharLoaded() end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("KITNUI_LOAD")
    end

    C_Timer.After(2, function()
        print(ns.title .. ": Type |cffFF008C/kitn install|r to open the installer.")
    end)
end)
```

> Drop entirely from v1 Core: `unpack(ElvUI)`, `E:NewModule`, `LibElvUIPlugin`, `EP:RegisterPlugin`, `SetFont` (used `E:UpdateMedia`), `GetDualSpecConfig` (moves to Setup.lua as a spec-ID mapping in Task 2.2), every `E.private.*` / `E.global.*` write, the ElvUI update-popup (`KITNUI_ELV_UPDATE`) and `ShutDownDetails`. The Details/BigWigs/Plater minimap-hide logic from v1 `FinishInstallation` moves to Setup.lua's finish handler (Task 2.3).

- [ ] **Step 2: luacheck**

Run: `luacheck Core.lua`
Expected: 0 warnings / 0 errors. (If globals like `KitnUIDB`, `EllesmereUI`, `LibStub`, `C_Timer` warn, confirm they are in `.luacheckrc` globals/read_globals — they were for v1; add `EllesmereUI` and `KitnUIDB` if missing.)

- [ ] **Step 3: In-game checkpoint (Kitn)**

Run: `/reload` (with EllesmereUI enabled), then `/kitn version`.
Expected: no BugSack errors on load; `/kitn version` prints `KitnUI version …` and the per-addon status list. `/kitn` with no arg prints the help block. The installer will not open yet (`ns.OpenInstaller` is nil until Task 3.3) — that is expected; confirm no error is thrown from the nil guard.

- [ ] **Step 4: Commit**

```bash
git add Core.lua
git commit -m "rewrite core as standalone bootstrap (no elvui plugin)"
```

---

## Phase 2 — Setup dispatch (import path) against a fixture

### Task 2.1: New `Setup.lua` skeleton + shared helpers

**Files:**
- Create: `Setup.lua` (new; v1 at `Legacy/Setup.lua`)

**Interfaces:**
- Consumes: `ns.db`, `ns.data`, `ns.profileName`, `ns.GetAddonDataVersion` (Task 1.2).
- Produces:
  - `ns.SetupAddon(addonKey, import, ...) -> bool` — dispatch into `setupFunctions[addonKey]`
  - `local HasData(addonKey) -> bool`, `local CompleteSetup(addonKey)` (file-local, used by handlers)
  - `ns.variantBase` table
  - `setupFunctions` table (populated across Tasks 2.2–2.3)

- [ ] **Step 1: Port the dispatch scaffolding**

Copy verbatim from `Legacy/Setup.lua` the blocks: `setupFunctions` local, `ns.SetupAddon`, `variantBase` + `ns.variantBase`, `CompleteSetup`, `HasData` (lines ~73–120 of the v1 file). Delete the `DecodeElvUIData` helper and the Details auto-run/`DETAILS_ZONE_SCRIPT`/`detailsLogoutFrame` block (Details is dropped). Keep the file header:

```lua
local _, ns = ...
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
```

- [ ] **Step 2: luacheck**

Run: `luacheck Setup.lua`
Expected: 0 warnings / 0 errors (unused `setupFunctions` entries are fine; they populate in later tasks).

- [ ] **Step 3: Commit**

```bash
git add Setup.lua
git commit -m "add setup dispatch skeleton"
```

---

### Task 2.2: EllesmereUI setup handler (the core import)

**Files:**
- Modify: `Setup.lua` (append the EllesmereUI handler + spec mapping)

**Interfaces:**
- Consumes: `ns.data.EllesmereUI` (+ variant keys), `EllesmereUI.ImportProfile/SetProfile/AssignProfileToSpec/RefreshAllAddons`, `EllesmereUIDB`.
- Produces: `setupFunctions["EllesmereUI"](addonKey, import, useColor, useHealer)`; `local GetSpecProfileMap(className) -> {specIndex = profileName}`.

Confirmed EllesmereUI API (from `References/EllesmereUI-v8.3.8/EllesmereUI/EllesmereUI_Profiles.lua`):
- `EllesmereUI.ImportProfile(importStr, profileName) -> success, errMsg [, "spec_locked"]` — stores under `EllesmereUIDB.profiles[profileName]` and auto-activates (unless `"spec_locked"`).
- `EllesmereUI.SetProfile(profileKey)` — public activate alias for `SwitchProfile`.
- `EllesmereUI.AssignProfileToSpec(profileName, specID)` — `specID` is the numeric `GetSpecializationInfo(GetSpecialization())` id, NOT the 1–4 index.
- `EllesmereUI.RefreshAllAddons()` — live re-apply (avoids a reload).

- [ ] **Step 1: Write the spec→profile map**

Port v1's healer/DPS intent from `Legacy/Core.lua`'s `GetDualSpecConfig`, but return profile NAMES keyed by spec index (the installer resolves the numeric specID at call time):

```lua
-- Which KitnUI EUI profile each spec should use. Healer specs get " Healer".
-- Names must match the profileName the import created (see useColor/useHealer).
local function GetSpecProfileMap(className, useColor)
    local base   = useColor and (ns.profileName .. " Colored") or ns.profileName
    local healer = useColor and (ns.profileName .. " Healer Colored") or (ns.profileName .. " Healer")
    local maps = {
        ["Shaman"]  = { base, base, healer },
        ["Paladin"] = { healer, base, base },
        ["Priest"]  = { healer, healer, base },
        ["Monk"]    = { base, healer, base },
        ["Druid"]   = { base, base, base, healer },
        ["Evoker"]  = { base, healer, base },
    }
    return maps[className]  -- nil for pure-DPS classes (all specs use base)
end
```

- [ ] **Step 2: Write the handler**

```lua
setupFunctions["EllesmereUI"] = function(addonKey, import, useColor, useHealer)
    if not ns.EUIReady() then
        print(ns.title .. ": EllesmereUI API not available.")
        return false
    end

    if import then
        -- Pick the variant data key. Fixture/first release may only define "EllesmereUI".
        local dataKey = "EllesmereUI"
        if useColor and useHealer and ns.data.EllesmereUIHealerColored then dataKey = "EllesmereUIHealerColored"
        elseif useColor and ns.data.EllesmereUIColored then dataKey = "EllesmereUIColored"
        elseif useHealer and ns.data.EllesmereUIHealer then dataKey = "EllesmereUIHealer" end

        if not HasData(dataKey) then
            print(ns.title .. ": No EllesmereUI profile data for '" .. dataKey .. "'.")
            return false
        end

        local profileName = ns.profileName
        if useColor and useHealer then profileName = ns.profileName .. " Healer Colored"
        elseif useColor then profileName = ns.profileName .. " Colored"
        elseif useHealer then profileName = ns.profileName .. " Healer" end

        local ok, err = EllesmereUI.ImportProfile(ns.data[dataKey], profileName)
        if not ok then
            print(ns.title .. ": EllesmereUI import failed - " .. (err or "unknown error"))
            return false
        end

        -- Forced overrides that don't survive export (poke the profile blob, NOT
        -- the vestigial *DB globals). EXACT field names are confirmed in Task 4.3.
        ns.ApplyEUIOverrides(profileName)   -- defined in Task 2.3 finish handler section

        CompleteSetup(addonKey)
    end

    -- Activate + assign per-spec (runs on both import and load)
    local _, className = UnitClass("player")
    local activeName = ns.profileName
    if useColor and useHealer then activeName = ns.profileName .. " Healer Colored"
    elseif useColor then activeName = ns.profileName .. " Colored"
    elseif useHealer then activeName = ns.profileName .. " Healer" end

    if EllesmereUI.SetProfile then EllesmereUI.SetProfile(activeName) end

    -- Per-spec assignment: map each spec index to its profile, resolve to specID
    local specMap = GetSpecProfileMap(className, useColor)
    if specMap and EllesmereUI.AssignProfileToSpec then
        for specIndex, pName in ipairs(specMap) do
            local specID = GetSpecializationInfoForClassID(select(3, UnitClass("player")), specIndex)
            if specID and (EllesmereUIDB and EllesmereUIDB.profiles and EllesmereUIDB.profiles[pName]) then
                EllesmereUI.AssignProfileToSpec(pName, specID)
            end
        end
    end

    if EllesmereUI.RefreshAllAddons then EllesmereUI.RefreshAllAddons() end
    return true
end
```

- [ ] **Step 3: luacheck**

Run: `luacheck Setup.lua`
Expected: 0/0. (`ns.ApplyEUIOverrides` is defined in Task 2.3; if luacheck flags it as undefined-field on `ns`, that is fine — `ns` is a table param, not a tracked global.)

- [ ] **Step 4: In-game checkpoint deferred**

This handler is exercised end-to-end in Task 3.2's checkpoint (needs the wizard + a fixture string). No standalone in-game run here.

- [ ] **Step 5: Commit**

```bash
git add Setup.lua
git commit -m "add ellesmereui import handler with per-spec assignment"
```

---

### Task 2.3: Port kept companion handlers + finish handler

**Files:**
- Modify: `Setup.lua` (append 7 handlers + `ns.ApplyEUIOverrides` + `ns.FinishInstallation`)

**Interfaces:**
- Produces: `setupFunctions["Plater"|"BuffReminders"|"BigWigs"|"NSRT"|"KitnEssentials"|"Blizzard_EditMode"|"BlizzardCDM"]`; `ns.ApplyEUIOverrides(profileName)`; `ns.FinishInstallation()`.

- [ ] **Step 1: Port the seven companion handlers verbatim**

From `Legacy/Setup.lua`, copy these `setupFunctions[...]` blocks **unchanged** (none touch ElvUI): `Plater`, `BigWigs`, `NSRT` (incl. its `DecodeNSRTString` local), `Blizzard_EditMode`, `KitnEssentials`, `BuffReminders`, `BlizzardCDM`. These handlers only read `ns.data`, `ns.profileName`, and their own addon globals.

> Do NOT port `ElvUI`, `Details`, `WarpDeplete`, `MRT`, `Ayije_CDM`, `Baganator` — those stay dormant in `Legacy/Setup.lua`.

- [ ] **Step 2: Write `ns.ApplyEUIOverrides`**

```lua
-- Forced settings that don't travel in an export. Poke the profile blob and let
-- RefreshAllAddons pick them up. Field names marked (VERIFY 4.3) are confirmed
-- in-game in Task 4.3 before this ships for real; against the fixture they no-op.
function ns.ApplyEUIOverrides(profileName)
    if not (EllesmereUIDB and EllesmereUIDB.profiles and EllesmereUIDB.profiles[profileName]) then return end

    -- UIScale is account-global, not per-profile:
    if ns.EUI_UISCALE then EllesmereUIDB.ppUIScale = ns.EUI_UISCALE end   -- value set in Task 4.3

    -- Media: reference KitnUI's LSM-registered assets as "sm:<name>" where the
    -- profile stores a texture/font key. Exact per-module keys: (VERIFY 4.3).
end
```

- [ ] **Step 3: Write `ns.FinishInstallation`**

Port the minimap-hide + reload logic from `Legacy/Core.lua`'s `FinishInstallation`, dropping every ElvUI/Details/Plater-CVar line and adding EUI module ownership. Module-disable calls are confirmed in Task 4.3:

```lua
function ns.FinishInstallation()
    ns.db.installedVersion = ns.version
    ns:SetCharLoaded()

    -- Ownership: standalone tools win, so disable the overlapping EUI modules.
    -- EXACT disable API/CVar confirmed in Task 4.3; guard so the fixture no-ops.
    if ns.DisableEUIModule then
        if IsAddOnLoaded("Plater") then ns.DisableEUIModule("EllesmereUINameplates") end
        if IsAddOnLoaded("BuffReminders") then ns.DisableEUIModule("EllesmereUIAuraBuffReminders") end
        ns.DisableEUIModule("EllesmereUICooldownManager")  -- Blizzard CDM owns cooldowns
    end

    -- Hide companion minimap icons (ported from Legacy/Core.lua FinishInstallation)
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBIcon then
        for _, broker in ipairs({ "BigWigs", "Plater", "NSRT" }) do
            if LDBIcon:IsRegistered(broker) then LDBIcon:Hide(broker) end
        end
    end
    if IsAddOnLoaded("BigWigs") and type(BigWigsIconDB) == "table" then BigWigsIconDB.hide = true end
    if IsAddOnLoaded("Plater") and PlaterDBChr and PlaterDBChr.minimap then PlaterDBChr.minimap.hide = true end

    ReloadUI()
end
```

- [ ] **Step 4: luacheck**

Run: `luacheck Setup.lua`
Expected: 0/0.

- [ ] **Step 5: Commit**

```bash
git add Setup.lua
git commit -m "port kept companion handlers and finish/override logic"
```

---

### Task 2.4: Add the fixture EllesmereUI data file

**Files:**
- Create: `Data/AddOns/EllesmereUI.lua`

**Interfaces:**
- Produces: `ns.data.EllesmereUI` (a valid v3 `!EUI_` string). Optional variant keys `ns.data.EllesmereUIColored/Healer/HealerColored` are added when authored (Phase 4); absent keys make the handler fall back to `EllesmereUI`.

- [ ] **Step 1: Capture a fixture export (Kitn, in-game)**

Run (with any EllesmereUI profile active): `/run KitnUIExport = EllesmereUI.ExportCurrentProfile(true, true)`
Then paste the copy popup contents, OR: `/run EllesmereUI:ShowCopyPopup("fixture","", EllesmereUI.ExportCurrentProfile(true,true))` and copy the string. It must begin with `!EUI_`.

- [ ] **Step 2: Write the data file**

```lua
local _, ns = ...

-- Fixture EllesmereUI profile (v3 !EUI_ export). Replaced with the final
-- Kitn-branded export(s) in Phase 4. Variant keys (…Colored/…Healer/
-- …HealerColored) are added when those variants are authored.
ns.data.EllesmereUI = "!EUI_PASTE_FIXTURE_STRING_HERE"
```

- [ ] **Step 3: luacheck + commit**

Run: `luacheck Data/AddOns/EllesmereUI.lua`
Expected: 0/0.

```bash
git add Data/AddOns/EllesmereUI.lua
git commit -m "add fixture ellesmereui profile data"
```

---

## Phase 3 — EllesmereUI-skinned wizard

### Task 3.1: `UI/Wizard.lua` — generic skinned multi-page wizard

**Files:**
- Create: `UI/Wizard.lua`

**Interfaces:**
- Consumes: EllesmereUI public builders (all ungated, from `References/EllesmereUI-v8.3.8/EllesmereUI/`): `EllesmereUI.SolidTex(parent,layer,r,g,b,a)`, `EllesmereUI.MakeBorder(parent,r,g,b,a,ppOverride)`, `EllesmereUI.MakeFont(parent,size,flags,r,g,b,a)`, `EllesmereUI.MakeStyledButton(btn,text,fontSize,colours,onClick)`, `EllesmereUI.GetAccentColor()`, `EllesmereUI.PanelPP`, and `EllesmereUI:ShowConfirmPopup{...}`.
- Produces: `ns.Wizard` with:
  - `ns.Wizard:Build()` — creates the frame once (idempotent), returns the root frame
  - `ns.Wizard:Queue(data)` where `data = { Title, Name, Pages = {fn,...}, StepTitles = {str,...} }` — matches the shape v1 passed to ElvUI's `PluginInstaller:Queue`, so Installer.lua's page functions port directly
  - `ns.Wizard:SetPage(n)`, `ns.Wizard:Show()`, `ns.Wizard:Hide()`
  - `ns.Wizard.frame` exposing v1-compatible fields the page functions write to: `.SubTitle`, `.Desc1`, `.Desc2`, `.Desc3`, `.Option1`..`.Option4` (so ported page code needs minimal edits)

- [ ] **Step 1: Guarded construction skeleton**

```lua
local _, ns = ...

ns.Wizard = ns.Wizard or {}
local W = ns.Wizard

local PANEL_BG = { 0.05, 0.07, 0.09 }
local BTN_COLOURS = {  -- EUI button palette (bg / bg-hover / border / border-hover / text / text-hover)
    0.061,0.095,0.120,0.6,  0.061,0.095,0.120,0.65,
    1,1,1,0.3,              1,1,1,0.45,
    1,1,1,0.55,             1,1,1,0.70,
}

local function skin(frame, a)
    local bg = EllesmereUI.SolidTex(frame, "BACKGROUND", PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], a or 0.97)
    bg:SetAllPoints()
    EllesmereUI.MakeBorder(frame, 1, 1, 1, 0.15, EllesmereUI.PanelPP)
    return bg
end
```

- [ ] **Step 2: `W:Build()` — container, title, step rail, content, nav**

Build order (all ungated EllesmereUI calls; structure from the source agent's verdict):

```lua
function W:Build()
    if W.frame then return W.frame end
    if not (_G.EllesmereUI and EllesmereUI.MakeBorder) then
        print(ns.title .. ": EllesmereUI UI not ready.")
        return nil
    end

    local f = CreateFrame("Frame", "KitnUIWizard", UIParent)
    f:SetSize(720, 500); f:SetPoint("CENTER"); f:SetFrameStrata("HIGH")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f, 0.98)

    f.SubTitle = EllesmereUI.MakeFont(f, 18, "", 1, 1, 1); f.SubTitle:SetPoint("TOP", 0, -22)
    local accent = { EllesmereUI.GetAccentColor() }
    local underline = EllesmereUI.SolidTex(f, "ARTWORK", accent[1], accent[2], accent[3], 0.9)
    underline:SetPoint("TOP", f.SubTitle, "BOTTOM", 0, -4); underline:SetSize(200, 2)

    f.Desc1 = EllesmereUI.MakeFont(f, 14, "", 1,1,1,0.9); f.Desc1:SetPoint("TOP", 0, -70); f.Desc1:SetWidth(600); f.Desc1:SetJustifyH("CENTER")
    f.Desc2 = EllesmereUI.MakeFont(f, 14, "", 1,1,1,0.8); f.Desc2:SetPoint("TOP", f.Desc1, "BOTTOM", 0, -12); f.Desc2:SetWidth(600); f.Desc2:SetJustifyH("CENTER")
    f.Desc3 = EllesmereUI.MakeFont(f, 13, "", 1,1,1,0.7); f.Desc3:SetPoint("TOP", f.Desc2, "BOTTOM", 0, -10); f.Desc3:SetWidth(600); f.Desc3:SetJustifyH("CENTER")

    -- Option buttons Option1..Option4 (bottom row)
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, f); b:SetSize(150, 30)
        EllesmereUI.MakeStyledButton(b, "", 13, BTN_COLOURS, function() if b._onClick then b._onClick() end end)
        f["Option" .. i] = b
    end
    f.Option1:SetPoint("BOTTOM", -240, 24)
    f.Option2:SetPoint("BOTTOM", -80, 24)
    f.Option3:SetPoint("BOTTOM", 80, 24)
    f.Option4:SetPoint("BOTTOM", 240, 24)

    -- Step rail (left) + Next/Back
    f.stepRail = CreateFrame("Frame", nil, f); f.stepRail:SetSize(180, 400); f.stepRail:SetPoint("TOPLEFT", 12, -60)
    f.Next = CreateFrame("Button", nil, f); f.Next:SetSize(90, 26); f.Next:SetPoint("BOTTOMRIGHT", -16, 24)
    EllesmereUI.MakeStyledButton(f.Next, "Next", 13, BTN_COLOURS, function() W:SetPage((W.page or 1) + 1) end)
    f.Back = CreateFrame("Button", nil, f); f.Back:SetSize(90, 26); f.Back:SetPoint("BOTTOMLEFT", 16, 24)
    EllesmereUI.MakeStyledButton(f.Back, "Back", 13, BTN_COLOURS, function() W:SetPage((W.page or 1) - 1) end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() W:Hide() end)

    f:Hide()
    W.frame = f
    return f
end
```

> Provide a `MakeStyledButton`-based helper `W:SetOption(i, text, onClick)` that sets the label (via the returned `lbl` from `MakeStyledButton`, or by re-skinning) and stores `_onClick`, plus `W:HideOptions()`; page functions call these. Model the label-set on how `EllesmereUI_Widgets.lua:371 MakeStyledButton` returns `bg, brd, lbl`.

- [ ] **Step 3: `W:Queue` / `W:SetPage` — paging engine**

```lua
function W:Queue(data)
    W:Build(); if not W.frame then return end
    W.pages = data.Pages; W.stepTitles = data.StepTitles
    W.frame.SubTitle:SetText(data.Name or ns.title)
    -- (Re)build the step-rail labels from data.StepTitles using EllesmereUI.MakeFont;
    -- highlight the active one with GetAccentColor. See EUI rail styling values in
    -- the design memory (dim text alpha 0.53, accent for active).
    W:SetPage(1); W:Show()
end

function W:SetPage(n)
    if not (W.pages and W.pages[n]) then return end
    W.page = n
    W:HideOptions()
    W.frame.Desc1:SetText(""); W.frame.Desc2:SetText(""); W.frame.Desc3:SetText("")
    W.frame.Back:SetShown(n > 1)
    W.frame.Next:SetShown(n < #W.pages)
    W.pages[n]()   -- the page function populates SubTitle/Desc*/Option*
end

function W:Show() if W.frame then W.frame:Show() end end
function W:Hide() if W.frame then W.frame:Hide() end end
```

- [ ] **Step 4: luacheck**

Run: `luacheck UI/Wizard.lua`
Expected: 0/0. Ensure `EllesmereUI` is in `.luacheckrc` read_globals.

- [ ] **Step 5: In-game checkpoint (Kitn)**

Temporarily add `/run ns` is not accessible; instead verify via Task 3.3 wiring. For an isolated smoke test, add a throwaway slash in `Core.lua` (removed after): `KitnCommands["wiz"] = function() ns.Wizard:Queue({ Name = "KitnUI", Pages = { function() ns.Wizard.frame.Desc1:SetText("hello") end }, StepTitles = {"Test"} }) end`. `/reload`, `/kitn wiz`.
Expected: a dark EUI-styled frame with a 1px pixel-perfect border, accent underline, "hello" text, a working close button, no BugSack errors. Remove the throwaway slash before committing.

- [ ] **Step 6: Commit**

```bash
git add UI/Wizard.lua
git commit -m "add ellesmereui-skinned wizard frame"
```

---

### Task 3.2: Rewrite `Installer.lua` — pages, steps, modes

**Files:**
- Create: `Installer.lua` (new; v1 at `Legacy/Installer.lua`)

**Interfaces:**
- Consumes: `ns.Wizard:Queue`, `ns.SetupAddon`, `ns.GetAddonDataVersion`, `ns.db`, EllesmereUI `ShowConfirmPopup`.
- Produces: `ns:GetInstallerData(profileLoadMode, updateKeys, cdmMode) -> {Title,Name,Pages,StepTitles}`; the toast + `ConfirmImport` helpers; the `addonSteps` table.

- [ ] **Step 1: Port toast, ConfirmImport, status helpers, page builders**

From `Legacy/Installer.lua`, port verbatim (they render into `PluginInstallFrame` in v1 — change every `PluginInstallFrame` reference to `ns.Wizard.frame`): `PlayInstallSound`, `ShowInstallToast`, `SuccessToast`, `SnapshotProfiles`/`preSessionProfiles`, `GetImportStatus`, `GetVersionLine`, `ShowStatusAndVersion`, `ShowLoadStatusAndVersion`, `GetCDMSpecStatus`, `BuildCDMStatusText`, and the page builders. Replace `ConfirmImport`'s `StaticPopupDialogs` with EUI's popup:

```lua
local function ConfirmImport(addonKey, displayName, callback)
    if preSessionProfiles[addonKey] and _G.EllesmereUI and EllesmereUI.ShowConfirmPopup then
        EllesmereUI:ShowConfirmPopup({
            title = "Overwrite?",
            message = ns.Color(displayName) .. " has already been imported. Overwrite with the fresh profile?",
            confirmText = "Overwrite", cancelText = "Cancel",
            onConfirm = callback,
        })
    else
        callback()
    end
end
```

- [ ] **Step 2: Update `addonSteps` to the v2 set**

```lua
local addonSteps = {
    { key = "EllesmereUI",       display = "EllesmereUI Profile", checkAddon = "EllesmereUI",       alwaysAvailable = true },
    { key = "Plater",            display = "Plater Nameplates",   checkAddon = "Plater",            alwaysAvailable = false, showWhenMissing = true },
    { key = "BuffReminders",     display = "BuffReminders",       checkAddon = "BuffReminders",     alwaysAvailable = false, showWhenMissing = true },
    { key = "BigWigs",           display = "BigWigs",             checkAddon = "BigWigs",           alwaysAvailable = false, showWhenMissing = true },
    { key = "NSRT",              display = "Northern Sky Raid Tools", checkAddon = "NorthernSkyRaidTools", alwaysAvailable = false, showWhenMissing = true },
    { key = "KitnEssentials",    display = "KitnEssentials",      checkAddon = "KitnEssentials",    alwaysAvailable = false, showWhenMissing = true },
    { key = "Blizzard_EditMode", display = "Edit Mode",           checkAddon = "Blizzard_EditMode", alwaysAvailable = true },
    { key = "BlizzardCDM",       display = "Blizzard CDM",        checkAddon = nil,                 alwaysAvailable = true },
}
```

- [ ] **Step 3: EllesmereUI page (variant selection)**

Replace v1's `ElvUIPage` (Normal / Class Color) with the EllesmereUI equivalent. Offer Normal / Class Color; healer is auto-assigned per spec by the handler, so no separate healer button is needed:

```lua
local function EllesmereUIPage()
    local f = ns.Wizard.frame
    f.SubTitle:SetText("EllesmereUI Profile")
    f.Desc1:SetText("Select the EllesmereUI look. Healer specs auto-swap to the Healer variant.")
    ShowStatusAndVersion("EllesmereUI")
    ns.Wizard:SetOption(1, "Normal", function()
        ConfirmImport("EllesmereUI", "EllesmereUI Profile", function()
            ns.SetupAddon("EllesmereUI", true, false, false)
            ShowStatusAndVersion("EllesmereUI"); SuccessToast("EllesmereUI", "imported!"); PlayInstallSound()
        end)
    end)
    ns.Wizard:SetOption(2, ns.ClassColor("Class Color"), function()
        ConfirmImport("EllesmereUI", "EllesmereUI Profile", function()
            ns.SetupAddon("EllesmereUI", true, true, false)
            ShowStatusAndVersion("EllesmereUI"); SuccessToast("EllesmereUI Class Color", "imported!"); PlayInstallSound()
        end)
    end)
end
```

- [ ] **Step 4: Port remaining pages + `GetInstallerData`**

Port `WelcomePage` (drop the ElvUI_Anchor warning block), `EditModePage`, `KitnEssentialsPage`, `BlizzardCDMPage` (uses the custom "Import All Specs" button — port it, parenting to `ns.Wizard.frame`, skinning the button with `EllesmereUI.MakeStyledButton` instead of ElvUI `S:HandleButton`), `SimpleInstallPage`, load-mode pages, update-mode pages, `FinishPage`, and `ns:GetInstallerData` — verbatim from `Legacy/Installer.lua` except: dispatch `EllesmereUI` → `EllesmereUIPage`/load page; remove ElvUI/Details/etc. branches; `PluginInstallFrame` → `ns.Wizard.frame`; the final `Queue` returns the data table for `ns.Wizard:Queue`.

- [ ] **Step 5: luacheck**

Run: `luacheck Installer.lua`
Expected: 0/0.

- [ ] **Step 6: Commit**

```bash
git add Installer.lua
git commit -m "rewrite installer pages onto skinned wizard"
```

---

### Task 3.3: Wire Core → Installer entry points

**Files:**
- Modify: `Core.lua` (define `ns.OpenInstaller`; wire slash commands)

**Interfaces:**
- Consumes: `ns:GetInstallerData`, `ns.Wizard`, `ns.SnapshotProfiles`.
- Produces: `ns.OpenInstaller(profileLoadMode, updateKeys, cdmMode)`.

- [ ] **Step 1: Define `ns.OpenInstaller`**

```lua
function ns.OpenInstaller(profileLoadMode, updateKeys, cdmMode)
    if InCombatLockdown() then print(ns.title .. ": Cannot open the installer in combat."); return end
    if not ns.EUIReady() then print(ns.title .. ": EllesmereUI not ready."); return end
    ns.SnapshotProfiles()
    ns.installerIsLoadMode = profileLoadMode or false
    ns.Wizard:Queue(ns:GetInstallerData(profileLoadMode, updateKeys, cdmMode))
end
```

Confirm the `KitnCommands` handlers (`install`/`load`/`update`/`cdm`/`reset`/`version`/`dev`) ported in Task 1.2 call `ns.OpenInstaller` (v1 called a local `OpenInstaller`; they now call `ns.OpenInstaller`). Update `KitnCommands["reset"]` to null `KitnUIDB` (not `KitnUIElvDB`).

- [ ] **Step 2: luacheck + in-game full flow (Kitn)**

Run: `luacheck Core.lua`, then in-game: `/kitn reset`, `/reload`.
Expected: the installer opens on first run (fixture EllesmereUI import path), you can step Welcome → EllesmereUI → companions → Finish. Clicking EllesmereUI "Normal" imports the fixture and activates it (BugSack clean); Finish reloads. `/kitn load` on an alt shows only imported steps. `/kitn cdm` shows the CDM-only flow.

- [ ] **Step 3: Commit**

```bash
git add Core.lua
git commit -m "wire installer entry points to the wizard"
```

---

## Phase 4 — Data, in-game verification, release

### Task 4.1: Confirm EUI override + module-disable paths (Kitn, in-game)

**Files:**
- Modify: `Setup.lua` (`ns.ApplyEUIOverrides`, add `ns.DisableEUIModule`, set `ns.EUI_UISCALE`)

- [ ] **Step 1: Probe the UIScale + a sample module DB field**

Run: `/run print(EllesmereUIDB.ppUIScale)` (note the value you want to force → set `ns.EUI_UISCALE`).
Run: `/run local p=EllesmereUIDB.profiles[EllesmereUIDB.activeProfile]; for k in pairs(p.addons) do print(k) end` (confirm folder keys, e.g. `EllesmereUINameplates`).

- [ ] **Step 2: Determine module-disable mechanism**

EllesmereUI modules are separate loadable addons and toggled via its FirstInstall/enable system. Probe how a module is turned off (a DB flag vs `C_AddOns.DisableAddOn`):
Run: `/run for k,v in pairs(EllesmereUIDB) do if type(v)=="table" and (k:match("[Ee]nable") or k:match("[Mm]odule")) then print(k) end end`
Then implement `ns.DisableEUIModule(folder)` to set the confirmed flag (guarded). If the only clean path is `C_AddOns.DisableAddOn(folder)`, implement that + note it needs a reload (the installer reloads at Finish anyway).

- [ ] **Step 3: luacheck + in-game verify + commit**

Verify Plater active / EUI Nameplates off after a full install; `luacheck Setup.lua`; commit `wire eui override and module-disable paths`.

---

### Task 4.2: Author + drop in final EllesmereUI export(s)

**Files:**
- Modify: `Data/AddOns/EllesmereUI.lua`

- [ ] **Step 1: Author the look in-game (Kitn)** — up to 4 variants (Dark / Class Color × DPS / Healer), final count your call.
- [ ] **Step 2: Export each** with `EllesmereUI.ExportCurrentProfile(true, true, <cdmSpecs>)`; paste into `ns.data.EllesmereUI` / `…Colored` / `…Healer` / `…HealerColored`.
- [ ] **Step 3:** `luacheck`; full install verification per variant; commit `add final ellesmereui profile exports`.

---

### Task 4.3: Re-author EditMode content for the EUI world

**Files:**
- Modify: `Data/AddOns/EditMode.lua`

- [ ] **Step 1 (Kitn):** In-game, set up Edit Mode for whatever Blizzard frames EllesmereUI does NOT own, export the layout string (`C_EditMode` export), replace the string in `Data/AddOns/EditMode.lua`.
- [ ] **Step 2:** `luacheck`; verify the EditMode step imports cleanly and positions the intended frames; commit `re-author edit mode layout for ellesmereui`.

---

### Task 4.4: Full end-to-end verification pass (Kitn)

- [ ] Fresh install on a new character (no `KitnUIDB`): wizard auto-opens, every step imports, Finish reloads, BugSack clean.
- [ ] `/kitn load` on an alt of a different class + a healer spec: correct per-spec profile is active after reload.
- [ ] `/kitn update` after bumping an `X-*-Version`: only the bumped step shows.
- [ ] `/kitn cdm` imports per-spec Blizzard CDM layouts; EUI CooldownManager is disabled (no doubled cooldowns).
- [ ] Confirm Plater owns nameplates (EUI Nameplates off) and BuffReminders owns reminders (EUI AuraBuffReminders off).

---

### Task 4.5: Release

**Files:** `README`, `CHANGELOG`, version metadata (per the `feedback_commit_workflow` memory).

- [ ] **Step 1: Freeze v1 first.** On `main`, tag the last ElvUI release commit: confirm its subject starts `v1.x.y:`; `git tag v1.0.8` (or the next patch) on that commit if not already tagged. This is the rollback point.
- [ ] **Step 2:** Merge `feature/v2-ellesmereui` → `main` (after Codex review).
- [ ] **Step 3:** Update README + CHANGELOG (document the EllesmereUI switch, dropped addons, hard EllesmereUI requirement, rollback path), bump version to `2.0.0`, update `X-*-Version` headers as needed.
- [ ] **Step 4:** `git tag v2.0.0` on the `2.0.0:` commit; push branch + tags. Packager ships via GitHub Actions `.pkgmeta`.

---

## Self-Review

**Spec coverage** (against the design memory `kitnui-v2-ellesmereui`):
- Standalone addon, no plugin → Task 1.2 (Core rewrite drops `E:NewModule`/`LibElvUIPlugin`). ✔
- Hard-require EllesmereUI, `KitnUIDB` → Task 1.1 (TOC), Task 1.2 (InitDB). ✔
- 8 steps, drop 4 → Task 3.2 `addonSteps`; drops parked in Task 0.2. ✔
- Overlaps (Plater/BuffReminders/BlizzardCDM own; disable EUI modules) → Task 2.3 finish + Task 4.1. ✔
- Import via `ImportProfile` + `AssignProfileToSpec` → Task 2.2. ✔
- EUI-skinned hand-built wizard → Tasks 3.1–3.2. ✔
- Only EUI payload new; 7 carry over; EditMode re-authored → Tasks 2.3 (ports), 2.4 (fixture), 4.2/4.3. ✔
- ElvUI frozen at tag + dormant in `Legacy/` → Task 0.2, Task 4.5. ✔
- Build against fixture first → Task 2.4, exercised Task 3.3. ✔
- Media via LSM `"sm:<name>"` → Task 1.2 register, Task 2.3/4.1 reference. ✔
- Version 3 export gate, poke profile blob not `*DB` globals → Task 2.2/2.3 (documented). ✔

**Placeholder scan:** in-game-gated values (ppUIScale, module-disable API, per-module media field names, final exports, EditMode string) are explicit **probe-and-set** verification steps owned by Kitn per project rule — not lazy TODOs. All new code blocks are complete and runnable against the fixture (guards make unconfirmed pokes no-op).

**Type consistency:** `ns.SetupAddon`, `ns.Wizard:Queue/SetPage/SetOption/HideOptions`, `ns.Wizard.frame.{SubTitle,Desc1..3,Option1..4}`, `ns.OpenInstaller`, `ns.FinishInstallation`, `ns.ApplyEUIOverrides`, `ns.DisableEUIModule`, `ns.EUI_UISCALE`, `GetSpecProfileMap` — names are consistent across Tasks 1.2 → 4.1. Profile names (`ns.profileName` [+ " Colored"/" Healer"/" Healer Colored"]) match between the import handler (2.2) and the spec map (2.2).

**Open item flagged for Codex review:** Task 3.1 `W:SetOption` is specified by contract but its body depends on `MakeStyledButton`'s return shape — the implementer must read `EllesmereUI_Widgets.lua:371` and set the label via the returned `lbl`. This is the one spot most likely to need an in-game tweak.
