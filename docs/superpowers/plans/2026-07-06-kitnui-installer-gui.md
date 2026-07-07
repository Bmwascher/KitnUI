# KitnUI v2 Installer Wizard GUI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin and restructure KitnUI's hand-built EllesmereUI-skinned installer wizard into a native dark-purple sidebar+content panel with disciplined Kitn-pink accents, and add an Extras page (Chat Setup / Optimize / Clean Icons).

**Architecture:** The wizard keeps its existing two-part split — `UI/Wizard.lua` is the reusable shell (frame, sidebar, header, content anchors, nav, paging engine) and `Installer.lua` holds per-page content functions that populate the shell via `Queue`/`SetPage`. Most visual work lands in `Wizard.lua`; `Installer.lua` gains descriptions, status colors, a primary-handoff, the Extras page, and Load All. A new `Extras.lua` holds the three Extras action functions. The functional profile-import/module-disable plumbing already works and is untouched by this plan.

**Tech Stack:** Lua 5.1 (WoW 12.0 embedded), EllesmereUI ungated widget builders (`SolidTex`, `MakeBorder`, `MakeFont`, `MakeStyledButton`, `PanelPP`), Blizzard `CreateFrame`/`Texture` APIs, LibDBIcon. Design spec: `docs/superpowers/specs/2026-07-06-kitnui-installer-gui-design.md`.

## Global Constraints

Every task implicitly includes these (verbatim from the spec + project rules):

- **Platform:** WoW 12.0, `## Interface: 120005, 120007`, Lua 5.1. Local variables over globals; `camelCase` locals, `PascalCase` module functions.
- **EllesmereUI is hard-required.** NEVER modify EUI core files. Only *call* its ungated builders on the global `EllesmereUI` table, and **nil-check every EUI API call** defensively. Do **not** use `EllesmereUI.GetAccentColor` (it returns EUI's teal, not pink).
- **Accent discipline:** saturated pink `KITN_PINK = {1, 0, 0.549}` means exactly three things — the current sidebar step, the progress bar, and the single primary action. Nothing else.
- **Status colors:** green `{0.43,0.75,0.61}` = done/Imported; amber `{0.90,0.70,0.30}` = Not Imported (pending); red `{1,0.33,0.33}` = errors + Out-of-date only.
- **Panel geometry:** 760×480; sidebar 206 wide. **Font:** Expressway (`Interface\AddOns\KitnUI\Media\Fonts\Expressway.TTF`).
- **Assets (already in `Media/`):** `Textures\KitnUI.tga` (logo), `Textures\KitnUI_Text.tga` (wordmark), `Statusbars\KitnUI_Bar.tga` (progress fill).
- **Idempotent:** every Extras action produces the same result run twice.
- **Verification (no UI test runner):** each task ends with `luacheck <file>` → **0 warnings / 0 errors** (auto-runs on edit via the PostToolUse hook) **and** an in-game `/reload` checkpoint. No busted tests exist for this addon.
- **Git:** work stays on branch `feature/v2-ellesmereui`. Commit after each task; messages lowercase, imperative; **NO** `Co-Authored-By` / `Claude-Session` / AI-attribution trailers. Leave `KitnUIElvDB` and the `-test` profile-name scaffold (`Core.lua`) untouched.

---

## File Structure

- **Modify `UI/Wizard.lua`** — the shell: layered background, resize, native close X, sidebar panel (logo/version/stateful steps), header band, content-column anchors, progress bar, button-variant helper. (Tasks 1–5.)
- **Modify `Installer.lua`** — status-color helpers, per-page descriptions, primary handoff, Extras page, Load All. (Tasks 5, 6, 8, 9.)
- **Modify `Core.lua`** — add `ns.Amber` color helper. (Task 6.)
- **Create `Extras.lua`** — `ns.RunChatSetup`, `ns.RunOptimize`, `ns.CleanMinimapIcons`. (Task 7.)
- **Modify `Setup.lua`** — `FinishInstallation` calls `ns.CleanMinimapIcons` instead of inline minimap logic. (Task 7.)
- **Modify `KitnUI.toc`** — load `Extras.lua`. (Task 7.)

---

## Task 1: Panel theme — layered background, resize, native close X

**Files:**
- Modify: `UI/Wizard.lua` (constants block ~15–26; `skin()` ~33–38; `W:Build()` size ~52 and close button ~119–121)

**Interfaces:**
- Produces: `skin(frame)` (layered background applied; sets `frame.artLayer` — an empty reserved `BACKGROUND` sublevel-0 texture); the root frame is 760×480 with a native close button that calls `W:Hide()`.

- [ ] **Step 1: Swap the panel color tokens.** Replace the `PANEL_BG` line and add the new tokens right after it (keep `KITN_PINK` and `BTN_COLOURS` as-is):

```lua
local PANEL_BG   = { 0.09, 0.06, 0.16 }        -- dark-purple panel base
local PANEL_GRAD = { 0.14, 0.09, 0.22 }        -- lighter purple for the top of the gradient
local BORDER_COL = { 0.69, 0.55, 1.0, 0.20 }   -- faint purple-white 1px border
local SIDEBAR_W  = 206                          -- sidebar column width (used by later tasks)
```

- [ ] **Step 2: Rewrite `skin()` into the layered background.** Replace the whole `skin` function:

```lua
local function skin(frame)
    -- base fill (BACKGROUND -2)
    local base = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    base:SetColorTexture(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 0.98)
    base:SetAllPoints()
    -- subtle top->bottom purple gradient (BACKGROUND -1)
    local grad = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    grad:SetColorTexture(1, 1, 1, 1)
    grad:SetAllPoints()
    if grad.SetGradient and CreateColor then
        grad:SetGradient("VERTICAL",
            CreateColor(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 0.0),
            CreateColor(PANEL_GRAD[1], PANEL_GRAD[2], PANEL_GRAD[3], 0.85))
    else
        grad:Hide()
    end
    -- reserved art layer (BACKGROUND 0) -- stays empty; drop a texture here later
    frame.artLayer = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    frame.artLayer:SetAllPoints()
    -- border
    if EllesmereUI.MakeBorder then
        EllesmereUI.MakeBorder(frame, BORDER_COL[1], BORDER_COL[2], BORDER_COL[3], BORDER_COL[4], EllesmereUI.PanelPP)
    end
    return base
end
```

Note: `SetGradient(orientation, minColor, maxColor)` with `CreateColor` is the 12.0 signature — the `if grad.SetGradient` guard is the defensive fallback the constraints require.

- [ ] **Step 3: Resize the root and simplify the `skin` call.** In `W:Build()` change `f:SetSize(720, 500)` to `f:SetSize(760, 480)`, and change the `skin(f, 0.98)` call to `skin(f)` (alpha now lives inside `skin`).

- [ ] **Step 4: Replace the Blizzard close button with a native X.** Replace the close-button block (the `UIPanelCloseButton` creation):

```lua
    -- Native close X (neutral -> pink on hover)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetFrameLevel(f:GetFrameLevel() + 10)
    local x = EllesmereUI.MakeFont(close, 20, "", 1, 1, 1, 0.55)
    x:SetPoint("CENTER")
    x:SetText("\195\151")  -- multiplication sign (renders as a thin X)
    close._x = x
    close:SetScript("OnEnter", function() x:SetTextColor(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 1) end)
    close:SetScript("OnLeave", function() x:SetTextColor(1, 1, 1, 0.55) end)
    close:SetScript("OnClick", function() W:Hide() end)
    f.CloseButton = close
```

- [ ] **Step 5: Lint.** Run: `luacheck UI/Wizard.lua`  → Expected: `0 warnings / 0 errors`.

- [ ] **Step 6: In-game checkpoint.** Run in-game: `/reload` then `/kitn`. Expected: the wizard opens as a **760×480 dark-purple panel** with a faint border and a top-right **× that turns pink on hover** and closes on click. (Sidebar/content still look rough — later tasks.)

- [ ] **Step 7: Commit.**

```bash
git add UI/Wizard.lua
git commit -m "theme installer panel with layered purple background and native close"
```

---

## Task 2: Sidebar panel — logo, version, stateful step rows

**Files:**
- Modify: `UI/Wizard.lua` (`W:Build()` step-rail block ~102–106; `updateRail()` ~155–182)

**Interfaces:**
- Consumes: `SIDEBAR_W`, `KITN_PINK` (Task 1).
- Produces: `f.sidebar` (distinct panel frame), `f.stepLabels[i]` rows with `done`/`current`/`upcoming` states set by `updateRail()`, `f.versionText`. Green token `STEP_DONE = {0.43,0.75,0.61}`.

- [ ] **Step 1: Add the green token** near the other color tokens in `UI/Wizard.lua`:

```lua
local STEP_DONE = { 0.43, 0.75, 0.61 }  -- green check for completed steps
```

- [ ] **Step 2: Build the sidebar panel + logo + version.** Replace the existing `f.stepRail`/`f.stepLabels` creation block in `W:Build()` with:

```lua
    -- Sidebar panel (distinct darker column with a right divider)
    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", 0, 0)
    side:SetWidth(SIDEBAR_W)
    local sideBg = side:CreateTexture(nil, "BACKGROUND", nil, 1)
    sideBg:SetColorTexture(0, 0, 0, 0.26)
    sideBg:SetAllPoints()
    local sideEdge = side:CreateTexture(nil, "BORDER")
    sideEdge:SetColorTexture(1, 1, 1, 0.07)
    sideEdge:SetWidth(1)
    sideEdge:SetPoint("TOPRIGHT", 0, 0)
    sideEdge:SetPoint("BOTTOMRIGHT", 0, 0)
    f.sidebar = side

    -- Logo block (KitnUI.tga mark + wordmark + divider)
    local logo = side:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\KitnUI\\Media\\Textures\\KitnUI")
    logo:SetSize(30, 30)
    logo:SetPoint("TOPLEFT", 18, -14)
    local wm = EllesmereUI.MakeFont(side, 16, "", 1, 1, 1)
    wm:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    wm:SetText("KitnUI")
    local logoDiv = side:CreateTexture(nil, "BORDER")
    logoDiv:SetColorTexture(1, 1, 1, 0.08)
    logoDiv:SetHeight(1)
    logoDiv:SetPoint("TOPLEFT", 0, -58)
    logoDiv:SetPoint("TOPRIGHT", 0, -58)

    -- Version (bottom-left)
    f.versionText = EllesmereUI.MakeFont(side, 10, "", 1, 1, 1, 0.38)
    f.versionText:SetPoint("BOTTOMLEFT", 20, 16)
    f.versionText:SetText("v" .. (ns.version or "2.0"))

    -- Step rows container (below the logo block)
    f.stepRail = CreateFrame("Frame", nil, side)
    f.stepRail:SetPoint("TOPLEFT", 0, -72)
    f.stepRail:SetPoint("TOPRIGHT", 0, -72)
    f.stepRail:SetHeight(340)
    f.stepLabels = {}
```

- [ ] **Step 3: Rewrite `updateRail()` for the three states.** Replace the whole function. Each row is a label with a reserved left gutter; done rows show a green ✓, the current row shows a pink left bar + glow + pink label, upcoming rows are dim:

```lua
local function updateRail()
    local f = W.frame
    local titles = W.stepTitles or {}
    for i = 1, math.max(#titles, #f.stepLabels) do
        local row = f.stepLabels[i]
        if not row then
            row = CreateFrame("Frame", nil, f.stepRail)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
            row:SetPoint("TOPRIGHT", 0, -(i - 1) * 30)
            row:SetHeight(28)
            row.bar = row:CreateTexture(nil, "ARTWORK")
            row.bar:SetColorTexture(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 1)
            row.bar:SetWidth(3)
            row.bar:SetPoint("TOPLEFT", 0, -3)
            row.bar:SetPoint("BOTTOMLEFT", 0, 3)
            row.glow = row:CreateTexture(nil, "BACKGROUND")
            row.glow:SetColorTexture(1, 1, 1, 1)
            row.glow:SetPoint("TOPLEFT", 3, 0)
            row.glow:SetPoint("BOTTOMRIGHT", 0, 0)
            if row.glow.SetGradient and CreateColor then
                row.glow:SetGradient("HORIZONTAL",
                    CreateColor(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 0.18),
                    CreateColor(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 0.0))
            end
            row.chk = EllesmereUI.MakeFont(row, 12, "", STEP_DONE[1], STEP_DONE[2], STEP_DONE[3])
            row.chk:SetPoint("LEFT", 15, 0)
            row.chk:SetText("\226\156\147")  -- check mark
            row.label = EllesmereUI.MakeFont(row, 13, "", 1, 1, 1)
            row.label:SetPoint("LEFT", 34, 0)
            row.label:SetJustifyH("LEFT")
            f.stepLabels[i] = row
        end
        local title = titles[i]
        if title then
            row.label:SetText(title)
            local isCurrent = (i == W.page)
            local isDone = (i < (W.page or 1))
            row.bar:SetShown(isCurrent)
            row.glow:SetShown(isCurrent)
            row.chk:SetShown(isDone)
            if isCurrent then
                row.label:SetTextColor(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 1)
            elseif isDone then
                row.label:SetTextColor(1, 1, 1, 0.82)
            else
                row.label:SetTextColor(1, 1, 1, 0.35)
            end
            row:Show()
        else
            row:Hide()
        end
    end
end
```

- [ ] **Step 4: Lint.** Run: `luacheck UI/Wizard.lua` → Expected: `0 warnings / 0 errors`.

- [ ] **Step 5: In-game checkpoint.** `/reload`, `/kitn`, click `Next` a few times. Expected: a **distinct darker sidebar** with the KitnUI logo + "KitnUI" wordmark up top, `v…` at the bottom, and steps showing **green ✓ for passed steps, a pink bar + pink label for the current step, and dim upcoming steps**.

- [ ] **Step 6: Commit.**

```bash
git add UI/Wizard.lua
git commit -m "build distinct installer sidebar with logo, version, and stateful steps"
```

---

## Task 3: Header band + content column reflow

**Files:**
- Modify: `UI/Wizard.lua` (`W:Build()` title/underline block ~64–69 and Desc anchors ~72–83; Option anchors ~97–100)

**Interfaces:**
- Consumes: `SIDEBAR_W` (Task 1).
- Produces: `f.SubTitle` re-anchored as a white left-aligned header with `f.headerDiv`; `f.Desc1/2/3` re-anchored into the content column, left-aligned; `f.Option1..4` re-anchored into the content column.

- [ ] **Step 1: Replace the title + underline block** in `W:Build()` with a left-aligned white header + divider (drop the pink underline):

```lua
    -- Header: white left-aligned title + thin divider
    f.SubTitle = EllesmereUI.MakeFont(f, 24, "", 1, 1, 1)
    f.SubTitle:SetPoint("TOPLEFT", SIDEBAR_W + 46, -24)
    f.SubTitle:SetJustifyH("LEFT")
    f.headerDiv = f:CreateTexture(nil, "ARTWORK")
    f.headerDiv:SetColorTexture(1, 1, 1, 0.09)
    f.headerDiv:SetHeight(1)
    f.headerDiv:SetPoint("TOPLEFT", SIDEBAR_W + 46, -64)
    f.headerDiv:SetPoint("TOPRIGHT", -46, -64)
```

- [ ] **Step 2: Re-anchor the content lines** into the content column, left-aligned. Replace the `Desc1/Desc2/Desc3` creation block:

```lua
    f.Desc1 = EllesmereUI.MakeFont(f, 14, "", 1, 1, 1, 0.9)
    f.Desc1:SetPoint("TOPLEFT", SIDEBAR_W + 46, -104)
    f.Desc1:SetWidth(760 - SIDEBAR_W - 92)
    f.Desc1:SetJustifyH("LEFT")
    f.Desc2 = EllesmereUI.MakeFont(f, 12.5, "", 1, 1, 1, 0.62)
    f.Desc2:SetPoint("TOPLEFT", f.Desc1, "BOTTOMLEFT", 0, -12)
    f.Desc2:SetWidth(760 - SIDEBAR_W - 92)
    f.Desc2:SetJustifyH("LEFT")
    f.Desc3 = EllesmereUI.MakeFont(f, 12, "", 1, 1, 1, 0.5)
    f.Desc3:SetPoint("TOPLEFT", f.Desc2, "BOTTOMLEFT", 0, -8)
    f.Desc3:SetWidth(760 - SIDEBAR_W - 92)
    f.Desc3:SetJustifyH("LEFT")
```

- [ ] **Step 3: Re-anchor the Option buttons** into the content column as a left-aligned row (replace the four `f.Option*:SetPoint(...)` lines):

```lua
    f.Option1:SetPoint("TOPLEFT", f.Desc3, "BOTTOMLEFT", 0, -22)
    f.Option2:SetPoint("LEFT", f.Option1, "RIGHT", 14, 0)
    f.Option3:SetPoint("LEFT", f.Option2, "RIGHT", 14, 0)
    f.Option4:SetPoint("LEFT", f.Option3, "RIGHT", 14, 0)
```

- [ ] **Step 4: Lint.** Run: `luacheck UI/Wizard.lua` → Expected: `0 warnings / 0 errors`.

- [ ] **Step 5: In-game checkpoint.** `/reload`, `/kitn`. Expected: the page **title is white and left-aligned** with a thin divider under it; the description text and the option/install buttons sit **in the content column to the right of the sidebar**, left-aligned — no longer centered on the whole panel.

- [ ] **Step 6: Commit.**

```bash
git add UI/Wizard.lua
git commit -m "reflow installer header and content into the content column"
```

---

## Task 4: Progress bar

**Files:**
- Modify: `UI/Wizard.lua` (`W:Build()` — add after the nav buttons; `W:SetPage()` ~198–210 — update fill/label)

**Interfaces:**
- Consumes: `SIDEBAR_W`, `KITN_PINK`.
- Produces: `f.progFill` (pink fill texture), `f.progLabel` (FontString); both updated inside `W:SetPage(n)`.

- [ ] **Step 1: Build the progress bar** in `W:Build()` (add just before the `f:Hide()` line):

```lua
    -- Progress bar (track + pink fill) above the nav row
    local progTrack = CreateFrame("Frame", nil, f)
    progTrack:SetHeight(5)
    progTrack:SetPoint("BOTTOMLEFT", SIDEBAR_W + 46, 74)
    progTrack:SetPoint("BOTTOMRIGHT", -46, 74)
    local trackBg = progTrack:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(1, 1, 1, 0.08)
    trackBg:SetAllPoints()
    f.progFill = progTrack:CreateTexture(nil, "ARTWORK")
    f.progFill:SetTexture("Interface\\AddOns\\KitnUI\\Media\\Statusbars\\KitnUI_Bar")
    f.progFill:SetVertexColor(KITN_PINK[1], KITN_PINK[2], KITN_PINK[3], 1)
    f.progFill:SetPoint("TOPLEFT", 0, 0)
    f.progFill:SetPoint("BOTTOMLEFT", 0, 0)
    f.progFill:SetWidth(1)
    f.progTrack = progTrack
    f.progLabel = EllesmereUI.MakeFont(f, 10.5, "", 1, 1, 1, 0.45)
    f.progLabel:SetPoint("BOTTOMRIGHT", progTrack, "TOPRIGHT", 0, 4)
    f.progLabel:SetJustifyH("RIGHT")
```

- [ ] **Step 2: Update the bar in `W:SetPage(n)`.** Add these lines inside `W:SetPage`, right after `updateRail()`:

```lua
    local total = (W.pages and #W.pages) or 1
    local frac = total > 0 and (n / total) or 0
    local trackW = W.frame.progTrack:GetWidth()
    if trackW and trackW > 0 then
        W.frame.progFill:SetWidth(math.max(1, trackW * frac))
    end
    W.frame.progLabel:SetText(("STEP %d OF %d"):format(n, total))
```

Note: `progTrack:GetWidth()` returns the resolved width because the frame is anchored on both sides; if it reads 0 on the very first paint, the next `SetPage` corrects it (the bar simply shows minimal on frame 1 — acceptable).

- [ ] **Step 3: Lint.** Run: `luacheck UI/Wizard.lua` → Expected: `0 warnings / 0 errors`.

- [ ] **Step 4: In-game checkpoint.** `/reload`, `/kitn`, click `Next`. Expected: a **pink progress bar** above the nav row that **fills as you advance**, with a right-aligned `STEP n OF N` label that increments.

- [ ] **Step 5: Commit.**

```bash
git add UI/Wizard.lua
git commit -m "add installer progress bar with step counter"
```

---

## Task 5: Button variants + primary handoff

**Files:**
- Modify: `UI/Wizard.lua` (add a `W:SetButtonVariant` helper; style nav ghosts)
- Modify: `Installer.lua` (`WelcomePage`/addon pages: apply variants + handoff on success)

**Interfaces:**
- Consumes: `KITN_PINK`, `STEP_DONE`.
- Produces: `W:SetButtonVariant(btn, variant)` where `variant` ∈ `"primary" | "selectable" | "ghost" | "done"`; retints an existing styled button. Installer pages call it to set button emphasis.

- [ ] **Step 1: Add the variant helper** to `UI/Wizard.lua` (after `W:StyleButton`):

```lua
-- Retint a styled button to one of four emphases. Operates on the bg/border/label
-- textures MakeStyledButton created; safe to call repeatedly.
function W:SetButtonVariant(btn, variant)
    if not (btn and btn._bg) then return end
    local P = KITN_PINK
    if variant == "primary" then
        btn._bg:SetColorTexture(P[1], P[2], P[3], 1)
        if btn._brd then btn._brd:SetColorTexture(P[1], P[2], P[3], 1) end
        if btn._lbl then btn._lbl:SetTextColor(0.09, 0.04, 0.07, 1) end
    elseif variant == "selectable" then
        btn._bg:SetColorTexture(P[1], P[2], P[3], 0.12)
        if btn._brd then btn._brd:SetColorTexture(P[1], P[2], P[3], 0.55) end
        if btn._lbl then btn._lbl:SetTextColor(1, 1, 1, 0.95) end
    elseif variant == "done" then
        btn._bg:SetColorTexture(1, 1, 1, 0.04)
        if btn._brd then btn._brd:SetColorTexture(STEP_DONE[1], STEP_DONE[2], STEP_DONE[3], 0.5) end
        if btn._lbl then btn._lbl:SetTextColor(STEP_DONE[1], STEP_DONE[2], STEP_DONE[3], 1) end
    else -- ghost
        btn._bg:SetColorTexture(1, 1, 1, 0.04)
        if btn._brd then btn._brd:SetColorTexture(1, 1, 1, 0.14) end
        if btn._lbl then btn._lbl:SetTextColor(1, 1, 1, 0.82) end
    end
end
```

Note: `MakeStyledButton` returns `bg, brd, lbl`. In `W:Build()`'s Option-button loop, capture them onto the button so the helper can find them — change the loop's `MakeStyledButton` call so it stores `b._bg, b._brd, b._lbl = EllesmereUI.MakeStyledButton(...)` (the loop already keeps `b._lbl`; add `b._bg` and `b._brd`). Do the same where `f.Next` and `f.Back` are built (capture their bg/brd/lbl too).

- [ ] **Step 2: Default the nav buttons to ghost.** After `f.Next` and `f.Back` are created in `W:Build()`, add:

```lua
    W:SetButtonVariant(f.Next, "ghost")
    W:SetButtonVariant(f.Back, "ghost")
```

- [ ] **Step 3: Add the handoff helper.** In `Installer.lua`, add near the top (after `WF`):

```lua
-- After a successful page action, hand the primary emphasis from the action
-- button to Next, and mark the action button "done".
local function HandoffToNext(actionBtn, doneText)
    if actionBtn then
        if doneText and actionBtn._lbl then actionBtn._lbl:SetText(doneText) end
        ns.Wizard:SetButtonVariant(actionBtn, "done")
    end
    ns.Wizard:SetButtonVariant(WF().Next, "primary")
end
```

- [ ] **Step 3a: Single-action page — `SimpleInstallPage`.** Set Install to primary when shown; hand off on success. Replace its `SetOption` block:

```lua
        ns.Wizard:SetOption(1, "Install", function()
            ConfirmImport(addonKey, displayName, function()
                ns.SetupAddon(addonKey, true)
                ShowStatusAndVersion(addonKey)
                SuccessToast(displayName, "imported!")
                PlayInstallSound()
                HandoffToNext(WF().Option1, "\226\156\147 Re-import")
            end)
        end)
        ns.Wizard:SetButtonVariant(WF().Option1, "primary")
```

- [ ] **Step 3b: Single-action page — `EditModePage`.** Same pattern, but only hand off on the *success* branch (layout-limit failure stays red, no handoff). At the end of `EditModePage`, after its `SetOption(1, "Install", ...)` block, add `ns.Wizard:SetButtonVariant(WF().Option1, "primary")`, and inside the success branch (after `SuccessToast("Edit Mode", "imported!")`) add:

```lua
                HandoffToNext(WF().Option1, "\226\156\147 Re-import")
```

- [ ] **Step 3c: Multi-option page — `EllesmereUIPage`.** Its two buttons (Normal / Class Color) are peers → **selectable**; whichever is used marks itself done and hands off. After both `SetOption` calls in `EllesmereUIPage`, add:

```lua
    ns.Wizard:SetButtonVariant(WF().Option1, "selectable")
    ns.Wizard:SetButtonVariant(WF().Option2, "selectable")
```

and inside **each** option's success callback (after its `PlayInstallSound()`), add the matching handoff — for Option1: `HandoffToNext(WF().Option1, "\226\156\147 Imported")`, for Option2: `HandoffToNext(WF().Option2, "\226\156\147 Imported")`.

- [ ] **Step 3d: Multi-option page — `BlizzardCDMPage`.** The per-spec buttons and the persistent `cdmAllButton` are peers → **selectable**; any successful import hands off to Next. When creating `cdmAllButton`, after `ns.Wizard:StyleButton(cdmAllButton, ...)` add `ns.Wizard:SetButtonVariant(cdmAllButton, "selectable")`. In the per-spec `SetOption(i, label, ...)` loop, after the loop set each shown option to selectable:

```lua
    for i = 1, math.min(numSpecs, 4) do
        if WF()["Option" .. i] and WF()["Option" .. i]:IsShown() then
            ns.Wizard:SetButtonVariant(WF()["Option" .. i], "selectable")
        end
    end
```

and in both the `cdmAllButton._onClick` success path and the per-spec success path (after their `PlayInstallSound()`), add `ns.Wizard:SetButtonVariant(WF().Next, "primary")`.

- [ ] **Step 4: Lint both files.** Run: `luacheck UI/Wizard.lua Installer.lua` → Expected: `0 warnings / 0 errors`.

- [ ] **Step 5: In-game checkpoint.** `/reload`, `/kitn`, go to any simple addon page (e.g. BigWigs if installed). Expected: **Install is solid pink**, Back/Next are quiet ghosts; after clicking Install, the button becomes a green **✓ Re-import** and **Next turns solid pink**.

- [ ] **Step 6: Commit.**

```bash
git add UI/Wizard.lua Installer.lua
git commit -m "add button variants and primary handoff to the installer"
```

---

## Task 6: Status colors + per-page descriptions

**Files:**
- Modify: `Core.lua` (add `ns.Amber` alongside `ns.Red`/`ns.Green`)
- Modify: `Installer.lua` (`GetImportStatus` ~84–95; add `desc` to `addonSteps`; render a description line on each page)

**Interfaces:**
- Consumes: existing `ns.Color`/`ns.Red`/`ns.Green`.
- Produces: `ns.Amber(text)` → amber-colored string; `addonSteps[i].desc` copy; each page writes a description into `Desc1`.

- [ ] **Step 1: Add `ns.Amber`.** In `Core.lua`, next to the existing `ns.Red`/`ns.Green` color helpers, add (amber `{0.90,0.70,0.30}` → hex `E6B24C`):

```lua
function ns.Amber(text) return "|cffE6B24C" .. (text or "") .. "|r" end
```

- [ ] **Step 2: Recolor `GetImportStatus`** in `Installer.lua` — Not Imported becomes amber, Outdated stays red, Imported stays green:

```lua
local function GetImportStatus(addonKey)
    if ns.db and ns.db.profiles and ns.db.profiles[addonKey] then
        local installed = ns.db.addonVersions and ns.db.addonVersions[addonKey]
        local current = ns.GetAddonDataVersion(addonKey)
        if installed and current and installed ~= current then
            return ns.Red("Out of date") .. " (v" .. installed .. " -> v" .. current .. ")"
        end
        return ns.Green("\226\156\147 Imported")
    else
        return ns.Amber("Not Imported")
    end
end
```

- [ ] **Step 3: Add description copy to `addonSteps`.** Add a `desc` field to each entry in `addonSteps`:

```lua
local addonSteps = {
    { key = "EllesmereUI",       display = "EllesmereUI Profile",     checkAddon = "EllesmereUI",          alwaysAvailable = true,  desc = "Your full UI: unit frames, action bars, nameplates, cast bars, and more. Healer specs auto-swap to the Healer variant." },
    { key = "Plater",            display = "Plater Nameplates",       checkAddon = "Plater",               alwaysAvailable = false, desc = "Curated Plater nameplates tuned to match the KitnUI look." },
    { key = "BuffReminders",     display = "BuffReminders",           checkAddon = "BuffReminders",        alwaysAvailable = false, desc = "Flags missing raid buffs, food, and flasks right on your HUD so you never pull under-prepped." },
    { key = "BigWigs",           display = "BigWigs",                 checkAddon = "BigWigs",              alwaysAvailable = false, desc = "Boss timers and warnings, positioned and styled for KitnUI." },
    { key = "NSRT",              display = "Northern Sky Raid Tools", checkAddon = "NorthernSkyRaidTools", alwaysAvailable = false, desc = "Northern Sky raid tooling: assignments, timers, and note sync." },
    { key = "KitnEssentials",    display = "KitnEssentials",          checkAddon = "KitnEssentials",       alwaysAvailable = false, desc = "Kitn's own quality-of-life addon: cooldowns, dungeon tools, and cleanups." },
    { key = "Blizzard_EditMode", display = "Edit Mode",               checkAddon = "Blizzard_EditMode",    alwaysAvailable = true,  desc = "The KitnUI HUD layout (frame positions) for Blizzard Edit Mode." },
    { key = "BlizzardCDM",       display = "Blizzard CDM",            checkAddon = nil,                    alwaysAvailable = true,  desc = "Per-spec Cooldown Manager layouts for your class." },
}
```

- [ ] **Step 4: Render the description on simple pages.** In `SimpleInstallPage`, replace the `Desc1` line with the step's description (look it up by key):

```lua
local function stepDesc(addonKey)
    for _, s in ipairs(addonSteps) do if s.key == addonKey then return s.desc end end
    return ""
end
```

and in `SimpleInstallPage`, change `f.Desc1:SetText(...)` to `f.Desc1:SetText(stepDesc(addonKey))`. Do the same substitution on `EllesmereUIPage`, `EditModePage`, and `BlizzardCDMPage` (use their `desc` copy).

- [ ] **Step 5: Lint.** Run: `luacheck Core.lua Installer.lua` → Expected: `0 warnings / 0 errors`.

- [ ] **Step 6: In-game checkpoint.** `/reload`, `/kitn`. Expected: each addon page shows a **one-line description**; status reads **amber "Not Imported"** before install, **green "✓ Imported"** after, and red only for out-of-date/errors.

- [ ] **Step 7: Commit.**

```bash
git add Core.lua Installer.lua
git commit -m "add amber pending status and per-page descriptions"
```

---

## Task 7: Extras action functions

**Files:**
- Create: `Extras.lua`
- Modify: `Setup.lua` (`FinishInstallation` — replace inline minimap block ~513–521 with a call to `ns.CleanMinimapIcons`)
- Modify: `KitnUI.toc` (load `Extras.lua`)

**Interfaces:**
- Produces: `ns.CleanMinimapIcons()`, `ns.RunOptimize()` → returns `true` if KE ran else `false`, `ns.RunChatSetup()`. All idempotent, all safe to call with missing optional addons.

- [ ] **Step 1: Create `Extras.lua`** with the three actions:

```lua
local _, ns = ...

------------------------------------------------------------
-- Extras: optional, repeatable QoL actions used by the Extras
-- installer page. All idempotent and defensively guarded.
------------------------------------------------------------

-- Hide the minimap buttons of companion addons (extracted from FinishInstallation
-- so the Extras "Clean Icons" button and Finish share one implementation).
function ns.CleanMinimapIcons()
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBIcon then
        for _, broker in ipairs({ "BigWigs", "Plater", "NSRT" }) do
            if LDBIcon:IsRegistered(broker) then LDBIcon:Hide(broker) end
        end
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded("BigWigs") and type(BigWigsIconDB) == "table" then
        BigWigsIconDB.hide = true
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded("Plater") and PlaterDBChr and PlaterDBChr.minimap then
        PlaterDBChr.minimap.hide = true
    end
end

-- Run KitnEssentials' system optimization. Returns false if KE isn't present.
function ns.RunOptimize()
    if not (KitnEssentials and KitnEssentials.GetModule) then return false end
    local opt = KitnEssentials:GetModule("Optimize", true)
    if not (opt and opt.OptimizeAll) then return false end
    opt:OptimizeAll()  -- KE prints its summary and owns its own reload prompt
    return true
end

-- Full chat reconfigure: main frame position/size, font, timestamps, class
-- colors, and a dedicated Combat Log tab. Idempotent.
function ns.RunChatSetup()
    local cf = _G.ChatFrame1
    if not cf then return false end

    -- Position + size the main chat frame (bottom-left, standard KitnUI spot).
    cf:ClearAllPoints()
    cf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 22)
    if cf.SetSize then cf:SetSize(400, 170) end
    if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(cf) end

    -- Font + size via the chat font object.
    local fontFile = "Interface\\AddOns\\KitnUI\\Media\\Fonts\\Expressway.TTF"
    if cf.GetFontObject then
        local fo = cf:GetFontObject()
        if fo and fo.SetFont then fo:SetFont(fontFile, 13, "") end
    end

    -- Chat CVars: timestamps + class colors.
    if SetCVar then
        SetCVar("showTimestamps", "%H:%M ")
        SetCVar("chatClassColorOverride", "0")  -- 0 = allow class colors
    end
    -- Class colors in chat channels.
    if _G.CHAT_CONFIG_CHAT_LEFT then
        -- (Blizzard stores per-channel color prefs; toggling the global CVar above
        --  is the reliable, idempotent path — per-channel colors follow it.)
    end

    -- Ensure a dedicated Combat Log tab exists (ChatFrame2 is the default combat log).
    if _G.ChatFrame2 then
        FCF_SetWindowName(_G.ChatFrame2, "Combat Log")
        if not _G.ChatFrame2:IsShown() and FCF_SelectDockFrame then
            -- leave visibility as the user has it; just ensure the name
        end
    end
    -- Rename the main tab to "General".
    if FCF_SetWindowName then FCF_SetWindowName(cf, "General") end

    return true
end
```

Note: `FCF_*`, `FCF_SavePositionAndDimensions`, and the chat CVars are Blizzard chat APIs — nil-guard each (done above). These are the pieces most likely to need an in-game tweak; the structure is what matters.

- [ ] **Step 2: Point `FinishInstallation` at the shared function.** In `Setup.lua`, replace the inline minimap-hide block in `ns.FinishInstallation` (the `LDBIcon`/`BigWigsIconDB`/`PlaterDBChr` lines) with a single call:

```lua
    -- Hide companion minimap icons (shared with the Extras "Clean Icons" button).
    ns.CleanMinimapIcons()
```

- [ ] **Step 3: Load `Extras.lua` in the TOC.** In `KitnUI.toc`, add `Extras.lua` right after `Installer.lua`:

```
Installer.lua

Extras.lua
```

- [ ] **Step 4: Lint.** Run: `luacheck Extras.lua Setup.lua` → Expected: `0 warnings / 0 errors`. (Add any new globals it flags — `ChatFrame1`, `ChatFrame2`, `FCF_SetWindowName`, `FCF_SavePositionAndDimensions`, `FCF_SelectDockFrame`, `UIParent` — to `.luacheckrc` read_globals if the hook reports them.)

- [ ] **Step 5: In-game checkpoint.** `/reload`, then test each via `/run`:
  - `/run KitnUI_NS_TEST=nil` is not needed — instead: `/run print(ns)` won't work (ns is local). Use the Extras page in Task 8 to exercise them, or temporarily: `/run C_AddOns.IsAddOnLoaded("KitnEssentials")`. Primary verification is Task 8's page. For now confirm no load error in BugSack after `/reload`.

- [ ] **Step 6: Commit.**

```bash
git add Extras.lua Setup.lua KitnUI.toc
git commit -m "add extras action functions and share minimap cleanup"
```

---

## Task 8: Extras page + install-flow insertion

**Files:**
- Modify: `Installer.lua` (add `ExtrasPage`; insert into `ns:GetInstallerData` install flow before Finish)

**Interfaces:**
- Consumes: `ns.RunChatSetup`, `ns.RunOptimize`, `ns.CleanMinimapIcons` (Task 7); `W:SetButtonVariant` (Task 5).
- Produces: `ExtrasPage()` page function; a new "Extras" step in the install-mode queue.

- [ ] **Step 1: Add `ExtrasPage`** in `Installer.lua` (place near `FinishPage`):

```lua
local function ExtrasPage()
    local f = WF()
    f.SubTitle:SetText("Extras")
    f.Desc1:SetText("Optional cleanup and quality-of-life tweaks. None are required; they just complete the KitnUI look and feel. Run any of them as many times as you like.")
    f.Desc2:SetText("")
    f.Desc3:SetText("")

    local slot = 1
    -- Chat Setup
    ns.Wizard:SetOption(slot, "Chat Setup", function()
        if ns.RunChatSetup() then SuccessToast("Chat", "configured!"); PlayInstallSound() end
    end)
    ns.Wizard:SetButtonVariant(WF()["Option" .. slot], "selectable")
    slot = slot + 1

    -- Optimize Settings (only when KitnEssentials is present)
    if C_AddOns and C_AddOns.IsAddOnLoaded("KitnEssentials") then
        ns.Wizard:SetOption(slot, "Optimize Settings", function()
            if ns.RunOptimize() then SuccessToast("Settings", "optimized!"); PlayInstallSound()
            else ShowInstallToast("KitnEssentials not available", 1, 0.8, 0.2) end
        end)
        ns.Wizard:SetButtonVariant(WF()["Option" .. slot], "selectable")
        slot = slot + 1
    end

    -- Clean Icons
    ns.Wizard:SetOption(slot, "Clean Icons", function()
        ns.CleanMinimapIcons(); SuccessToast("Minimap icons", "cleaned!"); PlayInstallSound()
    end)
    ns.Wizard:SetButtonVariant(WF()["Option" .. slot], "selectable")
end
```

- [ ] **Step 2: Insert the Extras step** into the install flow. In `ns:GetInstallerData`, in the install branch (not load/update/cdm), after the addon-steps loop and **before** the Finish page is appended, add:

```lua
    -- Extras (install mode only)
    if not profileLoadMode and not updateKeys and not cdmMode then
        tinsert(pages, ExtrasPage); tinsert(stepTitles, "Extras")
    end
```

Place this immediately before the `-- Finish (always last)` block.

- [ ] **Step 3: Lint.** Run: `luacheck Installer.lua` → Expected: `0 warnings / 0 errors`.

- [ ] **Step 4: In-game checkpoint.** `/reload`, `/kitn`, click `Next` to the **Extras** step (second-to-last). Expected: an "Extras" page with **Chat Setup / Optimize Settings / Clean Icons** buttons (Optimize hidden if KitnEssentials isn't installed). Click each: Chat Setup repositions/reconfigures chat; Optimize prints KE's summary; Clean Icons hides companion minimap buttons. Each toasts and is re-clickable.

- [ ] **Step 5: Commit.**

```bash
git add Installer.lua
git commit -m "add extras installer page with chat, optimize, and clean-icons actions"
```

---

## Task 9: Load All (load mode)

**Files:**
- Modify: `Installer.lua` (`WelcomeLoadPage` ~333–339)

**Interfaces:**
- Consumes: `ns.SetupAddon`, `ns.db.profiles`, `addonSteps`.
- Produces: a "Load All" action on the load-mode welcome page.

- [ ] **Step 1: Add Load All** to `WelcomeLoadPage`. Replace its `SetOption` line with a Load-All action that activates every imported profile:

```lua
    ns.Wizard:SetOption(1, "Load All", function()
        local n = 0
        for _, step in ipairs(addonSteps) do
            if ns.db and ns.db.profiles and ns.db.profiles[step.key] and step.key ~= "BlizzardCDM" then
                ns.SetupAddon(step.key)  -- load mode: activate existing profile, no reimport
                n = n + 1
            end
        end
        SuccessToast("All profiles", "loaded!")
        PlayInstallSound()
        ns.Wizard:SetButtonVariant(WF().Next, "primary")
    end)
    ns.Wizard:SetButtonVariant(WF().Option1, "primary")
```

- [ ] **Step 2: Lint.** Run: `luacheck Installer.lua` → Expected: `0 warnings / 0 errors`.

- [ ] **Step 3: In-game checkpoint.** `/reload`, then `/kitn load`. Expected: the load-mode welcome page shows a **"Load All"** primary button that activates every already-imported profile in one click (toast confirms), then step-by-step load pages still follow.

- [ ] **Step 4: Commit.**

```bash
git add Installer.lua
git commit -m "add load all to the profile loader welcome page"
```

---

## Final verification

- [ ] Full install walk: `/kitn reset` → `/kitn` → walk every step (Welcome → each addon → **Extras** → Finish), confirming: purple panel, sidebar checks/current/upcoming, progress bar, amber→green status, primary handoff, descriptions, native X. BugSack clean.
- [ ] Load walk: `/kitn load` → **Load All** → Finish.
- [ ] `luacheck .` from the repo root → `0 warnings / 0 errors`.
- [ ] Spec cross-check: every §2 scope item maps to a task (theme→T1, sidebar/logo/version/checks→T2, header/reflow→T3, progress→T4, buttons/handoff→T5, status/descriptions→T6, extras actions→T7, extras page→T8, load all→T9, layered art layer→T1 `frame.artLayer`).

## Self-review notes

- **Spec coverage:** every §2 in-scope item has a task (mapping above). The reserved art layer (§7) is created in T1 as `frame.artLayer` and left unset. Traffic-light status (§4) is T6; accent discipline is enforced across T2/T4/T5 (pink only on current step / progress / primary).
- **Type consistency:** `W:SetButtonVariant(btn, variant)` (T5) is the only cross-task shell API and is consumed by T8/T9 with the exact variant strings defined in T5. `ns.RunChatSetup`/`ns.RunOptimize`/`ns.CleanMinimapIcons` (T7) are consumed by T8 by the same names. `ns.Amber` (T6) matches its use in `GetImportStatus`.
- **Known in-game tuning points (call out during execution, don't silently skip):** exact purple/gradient values, `SetGradient` signature, the chat `FCF_*` calls, and progress-bar first-paint width — all guarded, all expected to need a small in-game nudge.
