# KitnUI v2 Installer Wizard — GUI Design

> Design spec for the KitnUI v2 installer wizard visual overhaul. Product of a
> brainstorming session (2026-07-06) with the visual companion; the direction
> was validated across mockups v1–v5. This is presentation only — the wizard's
> functional plumbing (profile import, per-spec assignment, EUI module disables)
> is already built and verified in-game. Part of v2 Phase 4.

## 1. Goal

The v2 wizard is hand-built on EllesmereUI's ungated widget builders (it lost
ElvUI's PluginInstaller GUI in the ElvUI→EUI pivot). It currently reads as a
flat, centered panel: a single dark fill with a bare-text step rail, content
anchored to the whole frame's center, a Blizzard `UIPanelCloseButton`, and no
progress bar / version / logo. The goal is a **polished, EUI-native-feeling
themed panel with Kitn pink accents** — a proper sidebar/content layout with the
progress, branding, and status affordances a professional installer has.

## 2. Scope

**In scope**
- Re-theme the wizard shell: native dark-purple panel + Kitn pink accents.
- Restructure to a **sidebar + content** layout (replacing centered-everything).
- Sidebar: KitnUI logo/wordmark at top, step list with done/current/upcoming
  states, version number at bottom.
- Progress bar (pink fill) + checked-off completed steps in the sidebar.
- Native close **X** (top-right), replacing the Blizzard template.
- Header band: white left-aligned page title + thin divider.
- Content area: per-page **description** line, **status** line, action button(s).
- Accent discipline + status-color semantics (see §4).
- Primary-action handoff (Install → Next) and post-install feedback.
- Nav: `Back` / `Next` only (Skip removed).
- **Load All** button on the load-mode welcome page.
- Layer the background so real art can drop in later without a rework (§7).

**Out of scope (deliberately deferred)**
- The actual EllesmereUI "Midnight" character-art PNG. Investigation confirmed
  it is a single baked image sized for EUI's own 1500×1154 frame (its sidebar,
  header, and X are painted into the pixels), can't be recolored, and would mean
  a hardcoded path into EUI's Media folder. Decision: build native now, keep the
  option to drop an art layer in later.
- "Install All" on the install flow (rejected — Next already advances without
  installing; the batch shortcut only makes sense as **Load All** in load mode).
- KitnEssentials repo alignment / file-formatting pass (separate track).
- Reverting the `-test` profile-name scaffold (ship-prep task).

## 3. Layout

Target panel **760 × 480**, two columns.

```
┌──────────────────────────────────────────────────────────────┐
│ [K] KitnUI                    BuffReminders               ✕   │  header band
│ ───────────────  ───────────────────────────────────────────  │  (title + divider)
│ ✓ Welcome                                                     │
│ ✓ EllesmereUI Pr.   Flags missing raid buffs, food, and       │  content
│ ✓ Plater Namepl.    flasks right on your HUD.                 │  (vertically
│ ▸ BuffReminders     Status: Not Imported · Version 1.1        │   centered body,
│   BigWigs           ┌──────────┐                              │   left-aligned)
│   Northern Sky…     │ Install  │                              │
│   KitnEssentials    └──────────┘                              │
│   Edit Mode                                                   │
│   Blizzard CDM                            STEP 4 OF 10        │  progress bar
│   Finish            ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░            │
│ v2.0             ┌──────┐                     ┌──────┐        │  nav row
│                  │ Back │                     │ Next │        │
└──────────────────────────────────────────────────────────────┘
   sidebar (~206)   content (fills remaining)
```

- **Sidebar (~206px):** own darker panel (semi-transparent black over the purple)
  with a 1px right divider. Logo block up top (divider under it), step list, and
  `v2.0` in the bottom-left corner.
- **Content** sits *beside* the sidebar (not centered on the whole panel) — this
  is the fix for the "everything's centered" feel.
- **Header band** spans the content column: page title (white, left-aligned) with
  a thin full-width divider under it; the close **X** rides the top-right corner.
- **Body** is vertically centered in the content region, left-aligned:
  description → status → action button(s).
- **Progress bar** spans the content column just above the nav row.
- **Nav row** at the bottom of the content column: `Back` left, `Next` right.

## 4. Visual system

### Colors (target values; tune in-game)
| Token | Hex | Lua {r,g,b} | Use |
|---|---|---|---|
| Panel base | `#17102a` | `{0.09, 0.06, 0.16}` | dark-purple panel fill (with a subtle top→bottom gradient) |
| Panel border | `#b08cff@0.20` | `{0.69, 0.55, 1.0}` a≈0.20 | 1px frame border |
| Sidebar overlay | black @0.26 | `{0,0,0}` a≈0.26 | sidebar panel over the purple |
| Divider | white @0.08 | `{1,1,1}` a≈0.08 | header + logo-block dividers, sidebar edge |
| **Kitn pink** | `#FF008C` | `{1, 0, 0.549}` | accent — *reserved uses only* (below) |
| Green (done) | `#6DBF9C` | `{0.43, 0.75, 0.61}` | completed check / Imported status |
| Amber (pending) | `#E6B24C` | `{0.90, 0.70, 0.30}` | "Not Imported" status |
| Red (error) | `#FF5555` | `{1.0, 0.33, 0.33}` | errors + "Out of date" only |
| Text primary | white @0.90 | | body / titles |
| Text secondary | white @0.60 | | status, sub-lines |
| Text dim | white @0.35 | | upcoming steps |
| Text done-step | white @0.82 | | completed step labels |

### Accent discipline (the core rule)
Saturated **pink means exactly three things**, nothing else:
1. the **current step** (sidebar: 3px left bar + faint horizontal glow + pink label),
2. the **progress bar** fill,
3. the **single primary action** on the page.

Everything previously pink is demoted: title → white, wordmark → white (only the
logo *mark* stays pink as the brand anchor), completed checks → green, nav →
neutral ghosts. When the accent is everywhere it means nothing; this keeps the
eye on what matters.

### Status semantics (traffic-light)
- **Green** — done / Imported (with a ✓).
- **Amber** — Not Imported (pending; the default pre-install state — stands out
  as a "todo" without the false alarm of red).
- **Red** — actual errors only: import failure, layout-limit reached, CDM
  disabled, or an **out-of-date** profile version.

### Typography
Font: **Expressway** (`Media/Fonts/Expressway.TTF` — the same face EUI uses for
its panels, so titles already match theirs). One family throughout.
- Page title 24 · description 14.5 · body/sidebar 13.5–14 · status 12.5 ·
  version 10. All via `EllesmereUI.MakeFont` (or an equivalent local wrapper).

### Buttons
- **Primary** — solid pink fill (`#FF008C`), dark text, soft glow. Reserved for a
  page's **single** most-useful action (one lone Install, Finish, or Next once
  the page's action is done).
- **Selectable** — pink **outline** (not solid fill), for pages offering **2+
  equal alternatives** (EllesmereUI Normal / Class Color; CDM per-spec + Import
  All). They're peers, not a hierarchy, so outline them rather than stack solid
  pink fills — this keeps the "one solid primary" reading intact.
- **Ghost/neutral** — faint fill + 1px light border, dimmed text. Back, Next
  (pre-action), and the post-install "Re-import".
- **Done** — green-outlined ghost (post-install "✓ Re-import").
- Built via `EllesmereUI.MakeStyledButton` with the existing `BTN_COLOURS`
  array, plus pink-primary, pink-outline, and green-done variants.

## 5. Components

Each is a focused unit of the wizard shell (`ns.Wizard`), populated per-page by
`Installer.lua`.

- **Root panel** — layered background (§7) + border; draggable; strata HIGH.
- **Sidebar**
  - *Logo block*: `KitnUI.tga` mark + "KitnUI" wordmark, divider beneath.
  - *Step list*: one row per page. States: **done** (green ✓ + 0.82 label),
    **current** (pink bar + glow + pink label), **upcoming** (0.35 label).
  - *Version*: `v<version>` bottom-left (from `ns.version` / TOC metadata).
- **Header band** — page title (`SubTitle`), thin divider, close **X**.
- **Content area** — `Desc1` (description), status line, action-button row
  (`Option1..4`), all left-aligned, vertically centered.
- **Progress bar** — track + pink fill; `STEP n OF N` label (right-aligned).
  Texture: `Media/Statusbars/KitnUI_Bar.tga`.
- **Nav row** — `Back` (hidden on first page) / `Next` (becomes `Finish` on the
  last page).
- **Toast** — existing `ShowInstallToast` (unchanged) for import confirmations.

### Close X
Native, replacing `UIPanelCloseButton`: a small button top-right using a simple
"✕" glyph (or a KitnUI-owned close texture), neutral tint → pink on hover.
(EUI's own X is baked into its background image, so there's nothing to reuse —
we draw our own.)

## 6. Per-page structure, behavior, and modes

### Page contract
Every page still populates the shared shell via the existing page-function model
(`Queue` → `SetPage`). Each page provides: **title**, **description** (new —
one line on what the profile does), **status** (via a status helper), and
**action button(s)**. Non-addon pages (Welcome, Finish) provide title +
description only.

### Descriptions (new content to author)
Each addon step gets a short one-liner (what its profile changes). These are
authored strings owned by the page/step definitions (e.g. an added `desc` field
on `addonSteps`, plus bespoke copy for Welcome / EllesmereUI / Edit Mode / CDM).

### Sidebar step states
- Steps the user has navigated **past** = **done** (green ✓).
- The **current** page = pink.
- Steps not yet reached = **upcoming** (dim).
- (Navigation progress, independent of import state, which lives in the status
  line. A page's status can read "Not Imported" even while the step shows done
  if the user skipped its action — that's fine and intended.)

### Progress bar
`fill = currentPageIndex / totalPages`; label `STEP n OF N`, where N is the
number of pages actually in the queue for the active mode (pages are conditional
on installed addons, so N is dynamic).

### Primary-action handoff & post-install feedback
- **Before** the page's action: the action button (Install / Normal / …) is the
  pink **primary**; `Next` is a ghost.
- **After** a successful action: status flips to green **✓ Imported**; the action
  button becomes a de-emphasized **✓ Re-import** (redo still available); `Next`
  takes the pink **primary** to pull the user onward.
- On **failure** (import error, layout limit, CDM disabled): status/message goes
  **red**, a red toast fires, `Next` stays ghost.
- On **multi-option pages** (EllesmereUI, CDM): the option buttons use the
  **selectable** (pink-outline) style; `Next` stays ghost until one option is
  used, then becomes the solid **primary**. The discipline rule is really "nav
  isn't primary until the page's action is taken" — a lone action gets solid
  pink, peers get outlines.

### Modes (unchanged flow, restyled shell)
`ns:GetInstallerData` still assembles pages for four modes:
- **Install** — Welcome → addon steps → Finish. Skip removed.
- **Load** — activate already-imported profiles. **Load All** button on the
  load-mode welcome page (one click activates every imported profile, then
  Finish); step-by-step still available.
- **Update** — reimport outdated profiles (out-of-date shows **red**).
- **CDM-only** — intro → CDM page → Finish.

## 7. Layered background (future art drop-in)

Build the panel background as ordered layers so a future art texture (the EUI
Midnight PNG *or* a KitnUI-owned piece) can be added behind the content without
reworking the shell:

1. **Base fill** — solid dark-purple `SolidTex` (BACKGROUND, sublayer −2).
2. **Gradient** — subtle top→bottom purple via `SetGradient` (BACKGROUND, −1).
3. **Art layer (reserved, empty for now)** — an all-points texture slot
   (BACKGROUND, 0) that stays unset. Dropping a texture here later is the entire
   change needed to add art; everything else (sidebar, content, border) sits on
   ARTWORK/OVERLAY above it.
4. **Border** — `EllesmereUI.MakeBorder` (faint purple-white).

## 8. Architecture / code mapping

Keep the existing shell-vs-pages split — it works and is well-bounded.

- **`UI/Wizard.lua`** (the shell — most changes here):
  - Replace `skin()` with the layered themed background (§7); swap `PANEL_BG`
    to the purple tokens (§4).
  - Add the **sidebar panel** (logo block, version, and turn the current bare
    `stepLabels` rail into stateful rows: done/current/upcoming with the pink
    bar + glow + green checks).
  - Add the **header divider** and a **native close X** (drop the Blizzard
    template).
  - Add the **progress bar** widget (+ `STEP n OF N` label), updated by
    `SetPage`.
  - New **button variants** (pink-primary, green-done) alongside the existing
    ghost styling; a helper to set a button's variant.
  - Re-anchor content into the **content column** (left of nothing, right of the
    sidebar), left-aligned + vertically centered — instead of whole-frame
    centering. Resize root to 760×480.
- **`Installer.lua`** (page content — light changes):
  - Add a **description** line per page (new `desc` copy).
  - Status helpers emit the new **color semantics** (green/amber/red) and drive
    the **primary handoff** (flip primary to Next + button→Re-import on success).
  - **Load All** on `WelcomeLoadPage`.
  - Existing `Queue`/`SetPage`/`Option`/status plumbing stays.

Builders reused from EllesmereUI (all ungated, on the global table): `SolidTex`,
`MakeBorder`, `MakeFont`, `MakeStyledButton`, `PanelPP`. We do **not** use
`GetAccentColor` (it returns EUI's teal/user accent, not pink) — pink is the
hardcoded `KITN_PINK = {1, 0, 0.549}`.

## 9. Assets

Already in `Media/` — no new art required for this pass:
- `Textures/KitnUI.tga` — sidebar logo mark.
- `Textures/KitnUI_Text.tga` — optional wordmark (or draw text).
- `Statusbars/KitnUI_Bar.tga` — progress-bar fill texture.
- `Fonts/Expressway.TTF` — all text.

New **content** (not art): per-addon description strings.

## 10. Success criteria

- `/reload`, run `/kitn install` (and `load` / `update` / `cdm`) and walk each
  flow end-to-end without Lua errors (BugSack clean).
- Panel reads as the v5 direction: purple panel, sidebar with logo + checked
  steps + version, pink current step, progress bar, white left-aligned header,
  native X, ghost nav, content beside the sidebar.
- Accent discipline holds (pink only on current step / progress / primary).
- Status colors: amber "Not Imported" by default, green on import, red on error
  / out-of-date.
- Primary handoff works: Install primary → after success, status green, button
  → Re-import, Next primary.
- Load mode shows **Load All**.
- The reserved art layer exists and is empty (adding a texture there is the only
  change needed to introduce art later).

## 11. Open / deferred

- Exact in-game color/spacing tuning (mockup values are browser approximations).
- Real background art (native piece or EUI PNG) — the reserved layer is ready.
- Per-addon icon by the title — nice-to-have, needs icon assets; descriptions
  cover the substance for now.
