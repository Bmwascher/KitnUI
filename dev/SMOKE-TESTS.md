# KitnUI smoke tests

In-game verification for work that has no headless gate. KitnUI has exactly two
automated gates — `luacheck` and `dev/tests/cdm-fingerprint.lua` — and neither of
them can see a frame, a saved variable written by another addon, or a switch that
moves and does nothing. Everything in this file is checked by hand, in the game,
by Kitn.

This file is stripped from the player zip by `.pkgmeta` (`- dev`).

## How this file is used

One section per work item. Each section is written BEFORE the code is built, from
the item's plan, and is updated at the end of every phase of that item. A section
is only ever deleted when the item ships and the behaviour it covers is folded
into a later item's checks.

Each check says what to do and what must happen. A check that says "confirm it
works" is a bad check: if it cannot fail, it cannot pass. Where a defect is
invisible on screen, the check must name the probe that makes it visible.

**Every check is Kitn's to run. Nothing in this file may be recorded as passed by
an agent.**

## Status

| Item | Branch | Built | Reviewed | In-game |
|---|---|---|---|---|
| 1. Unowned switch | `feature/unowned-switch` | yes, `e90048b` | Sol PASS, Fable PASS | **PENDING** |
| 2. Every loader says when it refused | `feature/unowned-switch` | yes, `f81b8d7` | Sol PASS, Fable PASS | **PENDING** |
| 3. Ownership tooltip on forcing switches | `feature/ownership-tooltip` | yes, `792a53b` | Sol PASS, Fable PASS | **PENDING** |
| 4. Installer polish (sidebar, version, NSRT nickname, EUI looks) | `feature/ownership-tooltip` | yes, `a9ea04b..20601ae` | Kimi PASS (3 rounds), Fable PASS (2 rounds) | **PENDING** |
| 5. Mouse-button pictures in the Top Bar tooltips | `feature/topbar-click-tooltips` | yes, `df7e962` | Sol PASS (7 rounds), Fable PASS (2 rounds) | **PASS** (Kitn, 2026-08-21) |
| 6. Lulu Mode holds the whole circle layout | `feature/lulu-circle-layout` | yes, `eb0c6ab..c8d94a2` | plan panel: Kimi PASS, Fable PASS, Sol FIX applied. Diff: Fable PASS on `75862c6`, one should-fix applied as `c8d94a2` | **PASS** (Kitn, 2026-08-21) |
| 7. Tweaks section, and Accents folded into Appearance | `feature/tweaks-and-accents` | yes, `a1791c9..778f65c` | plan: Sol PASS (3 rounds); Fable PASS on the earlier single-switch design only | **PENDING** |

**Both branches were rebased onto `v2.0.1` on 2026-08-14.** The SHAs above are the
rebased ones; anything you wrote down before that date is gone. The rebase also
retired one check — see the NSRT note in Item 2.

**The SHAs name where each item landed, not the branch tip.** A later commit on
`feature/ownership-tooltip` carries the fixes the cross-model review found. Always
test the tip: `git log main..HEAD` lists everything above `v2.0.1`.

## Shared tools

### The snapshot probe

Prints every note KitnUI is holding: one line per live note as a path, then the
recorded original, and a final count. **`NOTES 0` is the success marker. No output
at all means the macro did not run**, which is not the same thing.

```
/run local n=0 local function w(t,p) for k,v in pairs(t) do if k=="prev" then n=n+1 print(p,tostring(v)) elseif type(v)=="table" then w(v,p.."/"..k) end end end w((KitnUIDB or {}).euiSnap or {},"") print("NOTES",n)
```

214 characters, inside the 255-character macro limit. It walks `KitnUIDB.euiSnap`
only. The account-wide popup colour lives in `euiSnapGlobal` and is NOT covered by
`NOTES`; it is covered by its own sentinel instead.

---

# Item 1 — A switch that is on without owning the setting

**Plan:** `dev/docs/superpowers/plans/2026-08-11-unowned-switch.md` (local only).
**Commit:** `e90048b` (rebased onto v2.0.1). **Status: awaiting Kitn.**

## What changed and why it needs testing

KitnUI's EllesmereUI tab has switches that force an EllesmereUI setting to a
KitnUI value and record what was there before. Switch states live in the
EllesmereUI profile; the notes live in `KitnUIDB`. Copying a profile carried the
switch and left the note behind, so the next re-apply recorded KitnUI's own forced
value as the user's original, and turning the switch off handed KitnUI's value
back as though it were yours.

A note may now only be created by a user action. On a re-apply with no note,
nothing is written at all.

## Read this before starting

**Run the sequence twice.** Pass A with **Lulu Mode OFF**, covering accent,
Beginner Mode and nameplate arrows and their seven targets. Pass B for **Lulu Mode
alone**, covering its one target. Lulu unloads the EllesmereUI action bar module,
and while it is on, two of Beginner Mode's three paths never execute — an
all-switches-on run would pass with both of them broken.

Checks 1 to 9 and check 11 run in BOTH passes. Checks 10 and 12 are Beginner Mode
checks and run in pass A only. Check 13 is a mandatory standalone check run once
after both passes. "Every target" means seven in pass A and one in pass B; eight is
the total across both.

**The central defect is invisible on screen after a profile copy.** Both a fixed
and a broken build leave the same pixels. Two things make it visible and the checks
use both: perturbing the value before turning the switch off, and reading the notes
with the probe.

**One unowned state looks alarming and is not a defect.** An imported profile with
the arrows switch ON shows DOUBLE arrows, because KitnUI draws its own while
declining to suppress EllesmereUI's. One toggle clears it. Do not record it as a
failure.

## The checks

- [ ] **1. Sentinels first.** Fresh profile. Before touching any switch, set the
  underlying host value on every target for this pass to something recognisable
  and write it down. Eight targets across both passes: the seven profile-keyed
  force paths plus the account-wide popup and menu colour. One representative per
  target, **except the Cooldown Manager, which needs two** — `showTooltip` and one
  keybind property — because it has two independent write groups and one could be
  correct while the other is broken.
- [ ] **2. Turn on the switches for this pass.** Pass A: accent, Beginner Mode,
  arrows, and six paths must change (accent colour, accent scope, Cooldown Manager
  bars, action bar keybinds, action bar visibility, host nameplate arrows). Pass B:
  Lulu Mode and the minimap shape. The account-wide popup colour IS forced in pass
  A, because a fresh click is a claim.
- [ ] **3. Probe.** `NOTES` counts every path just claimed, and the printed paths
  include the accent scope entries nested under `.../scope/keys/...`.
- [ ] **4. Turn each switch off.** Every sentinel for this pass comes back. Probe
  again: `NOTES 0`.
- [ ] **5. The decisive check.** Switches back on. **Save Current as Profile** to a
  new name, switch to the copy, and probe. **There must be no note whose path
  contains the copy's name.** Run this BEFORE any OFF in the copy — an OFF erases
  the fabricated note that proves the bug.
- [ ] **6. Perturb, then off.** Still in the copy, switches ON, change each
  underlying value to a NEW recognisable value. Turn each switch off. **Your new
  values must be untouched.** A build that hands back the value KitnUI forced has
  failed. Probe: still nothing under the copy's name.
- [ ] **7. Back to the original.** Switch back and turn each switch off there.
  Every sentinel for this pass returns, proving the original profile's notes
  survived. **In pass B the Lulu reconcile prompt appears on this switch back —
  DECLINE it**, then carry on. It fires because check 6's OFF re-enabled the action
  bar module while the original profile still reads ON. Accepting would reload and
  derail checks 7 to 9.
- [ ] **8. Reset.** Switches on again, then `/kitn reset`. Every forced value is
  restored to its sentinel and the probe prints `NOTES 0`.
- [ ] **9. Spec change.** Set the sentinels again, switches on. **Confirm both
  specs are assigned to the SAME EllesmereUI profile first**, or the spec change
  switches profiles and this silently tests a different profile. Change spec, then
  turn each switch off: the sentinels recorded before the change must return.
- [ ] **10. All three paths, pass A only.** Flip Beginner Mode on, out of combat,
  which is the only way it can be flipped at all. All THREE of its paths apply, and
  turning it off restores all three sentinels. It is the only switch whose apply
  rides a closure, so this is what proves that closure runs.

  **This check used to ask for a combat toggle. That was impossible.** EllesmereUI
  refuses to open its panel in combat and closes it when combat starts, so no
  switch on that page can be clicked while locked down. The deferred branch stays
  in the code as a defence against a host rule change and is documented as such.
- [ ] **11. Partial import.** Fresh distinct sentinels on every path. Import a
  profile carrying the switches ON while excluding the module blobs they force, and
  exclude Global Settings so `euiAccent` is not carried. **Every sentinel survives
  untouched** and the probe prints `NOTES 0`. Some effects will be absent while the
  switch reads ON; that is the accepted state. **In pass B, DECLINE the Lulu
  reconcile prompt** — accepting is a legitimate claim and would read as a failure.
  Then finish the cycle: off changes nothing; on claims and the probe shows the new
  notes; a final off restores every sentinel and returns to `NOTES 0`.
- **12. The eviction race. REMOVED, not skipped, and not a pass.** It asked you to
  turn Beginner Mode on during combat and switch profile before combat ended. That
  cannot be done: the panel is closed in combat, so the switch cannot be clicked
  and the race has no way in. The queued-claim branch and its cancelling message
  stay in the code as a defence against a host rule change, and neither is
  reachable from the interface today. Nothing here needs testing.
- [ ] **13. MANDATORY STANDALONE, after both passes.** The unloaded-module restore
  path, which neither pass reaches. Set the action bar sentinels, claim Beginner
  Mode with Lulu OFF, turn Lulu ON and reload. Now turn Beginner Mode OFF while
  Lulu is still ON: the probe must show its action bar notes cleared. Then turn
  Lulu OFF and reload: both action bar sentinels must be back.
- [ ] **14. MANDATORY STANDALONE. ACCEPTING the Lulu prompt, which is the only
  re-apply route allowed to claim.** Every other check declines it, so nothing else
  covers this. Set a minimap shape sentinel (square) with Lulu OFF and no Lulu note.
  Import a profile that carries Lulu ON, by check 11's route. When the reconcile
  prompt appears, **ACCEPT it.** After the reload: the minimap is round, and the
  probe shows a Lulu note holding your square sentinel. Then turn Lulu OFF and
  reload: the minimap is square again. Accepting the prompt is a user action, and
  it is the only thing outside a switch click that may record an original.

## Result

Kitn, record the outcome here.

- Date:
- Pass A:
- Pass B:
- Check 13:
- Check 14 (accepting the Lulu prompt):
- Notes:

---

# Item 2 — Every loader says when it refused

**Plan:** `dev/docs/superpowers/plans/2026-08-11-refusal-contract.md` (local only).
**Status: awaiting Kitn.**

## What changed and why it needs testing

The installer announced success over steps that silently did nothing. Eight of the
nine setup functions never signalled a refusal, one wizard page threw the answer
away and toasted "loaded!" regardless, and four third-party API calls raised a Lua
error instead of refusing. The Load All loop has no `pcall`, so one of those errors
also skipped every step after it.

Now: success returns nothing, a refusal prints why and returns `false`, and the
wizard counts it. Four producers return `true` on success instead, deliberately:
EllesmereUI in both modes, NSRT in both modes, Edit Mode install and CDM install.
Four callers test that truthiness and depend on it, so a `true` there is not a
defect. The full contract is at the top of `Installer/Setup.lua`.

One carve-out stays and would look like a bug if you did not know: **BigWigs'
install still toasts before you answer its prompt**, because that call is
asynchronous and always has been.

**Changed since this section was written.** It used to say NSRT's load did nothing
and that this was success. v2.0.1 rebuilt the NSRT import on NSAPI's profile
support, so NSRT now has a real profile to load and a missing one is a genuine
refusal. Check 5 below is rewritten to match.

## Read this before starting

Most of these need an addon DISABLED and a reload, because the whole item is about
what happens when something is absent.

**Do not use Plater for the disable checks.** Plater is dormant with an empty
payload, so a fresh character can never record it in the ledger, Load All skips it,
and the check would be unrunnable rather than passing. Only use Plater on a
character carrying a legacy Plater install.

## The checks

- [ ] **1. The regression check, and it matters most.** With every optional addon
  installed, run a full install. Every step reports success exactly as it does
  today. Nothing about a working install may change.
- [ ] **2.** `/kitn load` with everything installed: "All profiles loaded!" as
  today.
- [ ] **3.** Disable **BigWigs**, reload, `/kitn load`. A printed line names it and
  the "could not be loaded" toast counts it. **No Lua error**, and every step after
  it still runs.
- [ ] **4.** Same for KitnEssentials, then BuffReminders, one at a time.
- [ ] **5.** Disable NSRT, reload, `/kitn load`. It names NSRT as not loaded and
  counts the refusal, same as the others. **This is the opposite of what this check
  said before v2.0.1** — NSRT used to have nothing to do on load. Now it does.
- [ ] **5b.** With NSRT installed, delete the KitnUI profile from inside NSRT, then
  `/kitn load`. It says no NSRT profile was found and tells you to run the installer,
  rather than reporting success.
- [ ] **6.** Install BigWigs' profile and **DECLINE** its prompt. A printed line
  says the profile was not imported. This is the async path; it cannot toast, and
  the "imported!" toast you already saw is expected and unchanged.
- [ ] **7. Deleted companion profile, ledger intact.** Install normally, then
  delete the KitnUI profile from inside the companion addon's own options, reload,
  `/kitn load`. That step names the missing profile rather than claiming success.
  **Run this against BigWigs AND KitnEssentials, both.** KitnEssentials is the one
  that would otherwise rebuild an empty profile behind your back and report
  success, so a free choice of addon here could hide the defect.
- [ ] **8.** Delete the KitnUI EllesmereUI profile from EllesmereUI's own profile
  UI, then `/kitn load`. The EllesmereUI step refuses rather than reporting loaded.
- [ ] **9.** Delete the KitnUI Edit Mode layout in Edit Mode, then run the Edit Mode
  load page. It refuses and names the layout it looked for, instead of toasting
  "loaded!".
- [ ] **9b. The Edit Mode layout still activates.** Re-run the installer's Edit Mode
  step to recreate the layout, then use the Edit Mode load page. The KitnUI layout
  must become the ACTIVE layout, not a neighbouring one. The load path now reads the
  preset count into a variable before using it, so an off-by-one would show here.
- [ ] **10. The CDM import still works, every spec.** Run the CDM step for each of
  your specs, including one that already has a KitnUI layout, so the remove-then-
  recreate path runs. Each spec's layout imports, is named `KUI - <spec>`, and the
  current spec's becomes active. The import now checks its layout-manager methods
  before it deletes anything, so a regression shows as a refusal here.
- [ ] **10b. Re-importing over the ACTIVE layout raises nothing.** This is the
  2026-08-18 crash, and it needs the same conditions you hit it in: the Cooldown
  Manager on screen, holding live spell data, with `KUI - <spec>` already the
  active layout. Run the CDM step for that spec again. BugSack must stay empty.
  Before the fix this threw from inside Blizzard's own redraw
  (`CooldownViewer.lua:946` and `:344`), and it threw HALFWAY, which wiped the
  active layout and imported nothing.
  - The Cooldown Manager not redrawing until you click Finish is EXPECTED, not a
    defect. Dropping that redraw is the fix. Finish reloads the UI and rebuilds
    the viewer from the saved layouts.
  - What must be true after Finish: the layout exists once, not twice, is named
    `KUI - <spec>`, and is active.

## What cannot be tested by hand, and why that is recorded rather than skipped

Some refusals this item adds can only fire when a game or addon API is missing.
There is no way to remove a method from a loaded addon from inside the game, so
these have no manual check and are not counted as untested work:

- Every INSTALL refusal for a missing API: EllesmereUI, Plater, BigWigs,
  KitnEssentials, BuffReminders. The installer skips an addon it cannot detect at
  all, so a disabled addon never reaches these lines.
- The Edit Mode load refusals for a missing `SetActiveLayout` or a missing preset
  count enum.
- The CDM import refusal for a missing layout-manager method.
- The CDM import's DEGRADED path when `C_SpecializationInfo.GetSpecialization` is
  missing. This one does not refuse: the layout is already created, named and
  saved by that line, so the import still succeeds and only the automatic
  activation is skipped. You would pick the layout yourself in Edit Mode.
- The CDM import's other DEGRADED path, when `GetSpecializationInfoForClassID` is
  missing. The layout is named `KUI - Spec<n>` instead of `KUI - <spec name>` and
  everything else runs unchanged.
- The CDM import running WITHOUT Blizzard's `LockNotifications`, which is what
  check 10b exercises the working half of. If a future build drops those two
  methods the import stops suppressing the redraw and behaves as it did before
  2026-08-18, which is to say it throws from inside Blizzard's code. That is
  deliberate: the alternative was to refuse the import outright over a method
  that only makes it quieter.

Their value is that a future API change refuses and prints instead of throwing and
stranding the rest of the run. Check 9 and check 5b cover the same shape on the
paths that CAN be reached, by deleting a profile or layout rather than an API.

## Result

Kitn, record the outcome here.

- Date:
- Regression (checks 1-2):
- Disabled-addon (checks 3-5):
- BigWigs decline (check 6):
- Deleted profiles (checks 7-9):
- Edit Mode activation and CDM import (checks 9b-10b):
- Notes:

---

# Item 3 — Each forcing switch says whether it is really holding your setting

**Plan:** `dev/docs/superpowers/plans/2026-08-11-ownership-tooltip.md` (local only).
**Commit:** `792a53b` (rebased onto v2.0.1). **Status: awaiting Kitn.**

## What is changing and why it needs testing

Item 1 created a state that nothing on screen distinguishes: a switch reads ON
while KitnUI holds none of your setting. It usually happens when a host profile is
copied, because the switch travels with the profile and the note does not.

Four switches get a line on hover saying which state they are really in: holding,
or on-but-not-holding. Everything else keeps the tooltip it has now.

## Read this before starting

**Leaving the page and coming back proves NOTHING here.** EllesmereUI re-shows a
cached page instead of rebuilding it, so the tooltip you see after navigating away
and back can be the old one. Several checks below say "without leaving the page"
for exactly this reason, and swapping in a leave-and-return would let a broken
build pass.

**The line is refreshed when ownership actually changes.** For Beginner Mode that
is inside the apply, not at the click.

**You cannot test any of this in combat.** EllesmereUI refuses to open its panel in
combat and closes it when combat starts, so no switch here can be clicked while
locked down. An earlier version of this document asked for an in-combat toggle;
that check was impossible and has been replaced.

**Three checks can only fail loudly, so do not skip them.** Check 4 proves the
unowned state is visible at all. Check 5 proves the page really is rebuilt. Check 8
proves the rejected design did not sneak back in as a thrown Lua error.

## The checks

- [ ] **1. Off is quiet.** Fresh profile, all four switches OFF. Hover each: no
  ownership line on any of them. Pink Accent, Lulu Mode and Beginner Mode keep the
  descriptions they had before this item. **Target Arrows does NOT** — its old
  description promised that EllesmereUI's arrows come back when you switch off,
  which is untrue in the unowned state, so that promise was deliberately deleted.
  Its new base description ends at "these do not."
- [ ] **2. On says holding.** Turn each on and hover each. Each says KitnUI is
  holding the setting and names the right one. **Beginner Mode must say it once, not
  once per action bar.**
- [ ] **3. Off takes it back.** Turn each off. The ownership line disappears again.
- [ ] **4. THE DECISIVE CHECK.** Switches on. **Save Current as Profile**, switch to
  the copy, open KitnUI's tab and hover each of the four. Each must say it is ON but
  NOT holding, and tell you to toggle it. Before this item there was no way to tell
  this state from a healthy one.
- [ ] **5. Claiming in the copy, without leaving the page.** Still in the copy,
  toggle **Pink Accent or Target Arrows** off and on, then hover it again **without
  leaving the page.** It must ALREADY read holding. **Do not use Lulu Mode here** —
  accepting its prompt reloads everything, so there is no "without leaving the page"
  left to test.
- [ ] **6. Beginner Mode names only what it holds, BOTH ways.** Beginner Mode holds
  two halves and can hold either alone. The sentence is built from the NOTES, not
  from which modules are loaded, so test the difference.
  - With both modules on, turn Beginner Mode on and hover: "your Cooldown Manager
    and action bar settings".
  - **Now turn Lulu Mode on and accept the reload, then hover again. It must STILL
    say both.** Lulu switches EllesmereUI's action bars off, but the action bar
    notes are still live and still owe you a restore, so KitnUI is still holding
    them. A sentence that drops to Cooldown Manager here is the defect.
  - Turn Lulu back off and reload. Now turn Beginner Mode **OFF while the Cooldown
    Manager module is still enabled**, which is what clears its notes. THEN disable
    EllesmereUI's **Cooldown Manager** module, reload, and turn Beginner Mode ON.
    Hover: "your action bar settings" only. **The order matters.** Turning it off
    with that module already disabled cannot clear its notes, so they stay live,
    and the sentence correctly says both. That would look like a failure and would
    not be one.
  - Re-enable the Cooldown Manager module, turn Beginner off and on again with
    Lulu ON. Hover: "your Cooldown Manager settings" only.
- [ ] **7. Nothing else changed.** Hover Additive Glow, the **Dark Class Resource
  Bar**, and any Top Bar switch. No ownership line on any of them, and the
  description is word for word what it is today. The Dark Class Resource Bar matters
  most here: it does change a host setting, and it still must not claim ownership.
- [ ] **8. THE THROW CHECK.** Make EllesmereUI's panel as narrow as it goes, so the
  Target Arrows label is cut short with an ellipsis, and hover all four switches. A
  tooltip must appear each time and **BugSack must stay empty.** An error here means
  the build regressed to the rejected dynamic-tooltip design.
- **9. Combat. REMOVED, not skipped.** It asked you to hover a forcing switch in
  combat. The panel is closed in combat, so there is nothing to hover. Nothing here
  needs testing.
- [ ] **10. Search still finds them.** In EllesmereUI's settings search, type
  "accent", "lulu", "beginner" and "arrows" and confirm each row is found. Then
  search a distinctive word from one of the four descriptions and confirm the row
  still matches, which proves the descriptions are still indexed.
- [ ] **11. The rebuild broke nothing.** Toggle each forcing switch a few times and
  watch the settings page. It must not flicker into a broken layout, lose its scroll
  position badly, or make other pages disappear. This work tears the page down and
  builds it again, so a layout fault shows up here.
- [ ] **12. The Lulu prompt no longer counts parts.** Get the Lulu reconcile prompt
  to appear (Item 1 check 7 or 11 both raise it). Its apply wording must read "Lulu
  Mode is on, but it is not applied", with **no count of parts**. A count would be a
  promise about the screen that two states can defeat.

## Result

Kitn, record the outcome here.

- Date:
- Off / on / off (checks 1-3):
- Copied profile and claiming (checks 4-5):
- Beginner Mode names only what it holds (check 6):
- Untouched switches (check 7):
- Narrow panel, BugSack (check 8):
- Search, rebuild, Lulu wording (checks 10-12):
- Notes:


---

# Item 4 — Installer polish: sidebar, version, NSRT nickname, EllesmereUI looks

Three separate changes that all show up in the installer wizard. Design:
`dev/docs/superpowers/specs/2026-08-18-installer-polish-design.md`.

Commits: `a9ea04b` (sidebar), `9d7352a` (looks), `643ca4e` (nickname),
`d69d818` (version string), `d388c51` (version helper), `ad33cf1` and `20601ae`
(review fixes).

Cross-model review closed 2026-08-19, verdict PASS on `d13af7d..20601ae`,
verification status FULL. Round artifacts:
`dev/docs/superpowers/rounds/2026-08-19-installer-polish/`.

## What changed and why it needs testing

**The sidebar step names moved 8 pixels left.** The rail, the green tick and the
label all shifted, and the tick shrank from 14 to 12 pixels to make the room.
Nothing but geometry changed, so the only way this can be wrong is on screen: a
name overlapping the tick, or a long name crossing the baked divider.

**The Northern Sky Raid Tools step gained a text box.** It is the wizard's first
EditBox, so it is the first thing here that can take keyboard focus. Two things
about focus matter more than the feature itself: Escape must not close the
wizard, and merely visiting the page must not write anything. Writing an empty
nickname is not harmless - NSRT treats it as "delete my nickname" and tells your
raid.

**The EllesmereUI step gained Dark and Colored buttons.** They call the same
function the config tab's own buttons call. They appear only once the profile is
imported, and the highlighted one is read live, so a look changed elsewhere has
to show up here.

## Read this before starting

- The nickname box only appears if NorthernSkyRaidTools is loaded. On a
  character without it, checks 3 to 8 do not apply.
- The look buttons only appear if the EllesmereUI profile is imported. Check 9
  is deliberately the "before" state.
- The installer applies Dark at import time, so check 10 expects Dark marked.

## The checks

- [ ] **1. Names sit further left.** Run `/kitn install`. The step names in the
  left rail start visibly closer to the panel edge than before. Nothing is cut
  off and no name crosses the divider line at the right of the sidebar.
- [ ] **2. The tick and the bar still work.** Step past an addon you actually
  import. Its row shows the green tick, and the tick does not touch or sit under
  the first letter of the name. The current row still shows the pink bar and the
  pink wash.
- [ ] **2b. The footer version reads plainly.** Bottom left of the sidebar reads
  **`Version dev`** in your symlinked checkout. It must NOT read a number: a
  number there is a stale hand-written guess, which is the bug. A packaged build
  reads `Version 2.0.1`, with no `v` in front - only testable from a real
  CurseForge or Wago install.
- [ ] **2c. Chat says it the same way.** Run `/kitn version` and `/kitn` with no
  argument. Both name the version the same as the footer does - `dev` in your
  checkout, with no `v` and no stale number. The same rule now covers the
  "KitnUI has been updated" popup, which you will only see on a real update.
- [ ] **3. The box shows your real nickname.** Go to the Northern Sky Raid Tools
  step. The box under the status block shows your current NSRT nickname, or the
  grey words `Type a nickname` if you have none.
- [ ] **3b. It is easy to spot.** The caption above the box is pink, the box has a
  pink edge down its left side, and its border brightens when you click into it.
  It should read as the one thing on the page asking you to type.
- [ ] **3c. The same box is on the other two wizards.** Run `/kitn load` on any
  character with an NSRT profile: the Northern Sky Raid Tools step has the same
  box, showing the same value. Run `/kitn update` when NSRT has an update
  pending: same again. Change the nickname in one and it reads the same in the
  others - there is only one value, so they cannot drift.
- [ ] **4. Typing a name saves it.** Type a name and press Enter. Open NSRT's own
  options and confirm the same name is there.
- [ ] **5. Clearing works.** Empty the box and press Enter. NSRT's options show it
  cleared.
- [ ] **6. Long names are cut.** Type more than 12 characters and press Enter. The
  box comes back showing 12 characters or fewer, which is what NSRT kept.
- [ ] **6b. A non-Latin name is not silently cut.** If you can, set a nickname in
  NSRT's own options using 12 characters of a non-Latin alphabet (Cyrillic,
  Korean, Chinese). Open the KitnUI installer's NSRT step. The box must show the
  WHOLE name, not a chopped one. Then click into the box and click away WITHOUT
  typing: NSRT's nickname must be completely unchanged and nothing may be sent
  to your group. This is the check for the defect the review found.
- [ ] **7. Escape does not close the wizard.** Start typing in the box and press
  Escape. Focus leaves the box, the box goes back to its old value, and **the
  wizard stays open**.
- [ ] **8. Just visiting writes nothing.** With NO nickname set, walk onto the
  NSRT step, click the box, click away without typing, then leave the page. NSRT
  must still have no nickname. Nothing about a nickname may be sent to your
  group.
- [ ] **9. Importing keeps the nickname.** Set a nickname, then import the NSRT
  profile on that same step. The nickname is still there afterwards.
- [ ] **10. No looks before the profile.** On the EllesmereUI step, before
  importing, there are no Dark or Colored buttons - only the hint saying the
  looks live in the KitnUI tab.
- [ ] **11. Looks appear after the import.** Import the profile. Dark and Colored
  appear straight away, with **Dark** marked.
- [ ] **12. Colored works.** Click Colored. The UI recolours and Colored takes the
  mark.
- [ ] **13. The config tab agrees.** Open KitnUI's EllesmereUI tab. Its appearance
  header names the same look the installer has marked.
- [ ] **14. Custom is honest.** In the config tab, hand-change one colour so the
  header reads CUSTOM. Return to the installer step. **Neither** button is
  marked.
- [ ] **15. Combat is refused.** Pull a target dummy. Click Dark: refused with a
  message and nothing changes. Type in the nickname box and press Enter: refused
  in chat, and the box goes back to the stored value.
- [ ] **15b. Importing in combat does not force a look.** With the installer
  already open, get into combat, then import the EllesmereUI profile. The
  profile imports, and chat says the appearance was not applied because you are
  in combat. Nothing about the UI colours changes mid-fight.
- [ ] **16. BugSack is empty.** After all of the above.

## Result

Kitn, record the outcome here.

- Date:
- Sidebar and version (checks 1-2c):
- Nickname (checks 3-9, including 3b, 3c and 6b):
- Looks (checks 10-15b):
- BugSack (check 16):
- Notes:

---

# Item 5 — Mouse-button pictures in the Top Bar tooltips

Branch `feature/topbar-click-tooltips`. Touches `KitnUI_EUI/TopBar/Elements.lua`,
`KitnUI_EUI/TopBar/Readouts.lua`, and twelve names in `.luacheckrc`. Nothing else
moves.

## What changed and why it needs testing

- The **hearthstone** tooltip is now one row per mouse button: the button's own
  picture, the stone's icon, the stone's name, and that stone's own cooldown in
  the right-hand column. It used to be one shared cooldown line at the top and
  three plain sentences under it.
- The cooldown is now asked **per stone**, not once for the button. That is the
  point: the Dalaran Hearthstone and the Key to the Arcantina run on cooldowns
  separate from the main pool, so three rows can honestly disagree.
- A last line names where a plain hearthstone sends you (`GetBindLocation`).
- The **clock** gained a **right click**: the stopwatch and alarm window
  (`ToggleTimeManager`). Left click (calendar) and middle click (reload) are
  unchanged. Its tooltip gained a title and the same three pictures.
- **Home** and **volume** now use the same pictures in place of the words
  "Left-click:" and friends.
- The **clock tooltip** gained a body: the raid and dungeon lockouts this
  character holds, then the daily and weekly reset clocks, then ONE time line
  naming whichever clock the face is not showing. Nothing here runs on a
  timer; it is read only while the tooltip is open, apart from a one-time
  Encounter Journal walk on the first hover that needs the instance art.
  The one call that reaches the server, `RequestRaidInfo`, is throttled to once
  per 30 seconds, so its answer lands on a LATER hover by design.
- Every tooltip whose title has content under it gained a **blank line** between
  the two, so the name reads as a heading. Tooltips that are their title alone
  (Toy Box, Talents, Game Menu, Mythic+ Portals, every other passthrough) must
  NOT gain one, and friends and guild pay theirs from inside `Readouts.lua`
  because in a dungeon or raid they list nothing at all.
- The three pictures are cut out of Blizzard's own `UI-TUTORIAL-FRAME` sheet by
  pixel coordinates. **Nothing offline can prove the three crops are the right
  way round** - that is check 2 and it is the reason this section exists.

## Read this before starting

- The stone names and icons resolve asynchronously after login. A tooltip opened
  in the first seconds of a session can legitimately show a name with no icon.
- The tooltip redraws every 0.5s while hovered. That is existing behaviour, not
  new.
- Tooltips must be switched ON in the Top Bar options, or none of this appears.

## The checks

- [ ] **1. Three rows, four parts each.** Hover the hearthstone button. There are
  exactly three rows. Each has a mouse picture, a stone icon, a stone name, and
  either a green **Ready** or a red countdown at the right.
- [ ] **2. The pictures match the buttons.** Row one's picture must be a mouse
  with the **left** button highlighted, row two the **scroll wheel**, row three
  the **right** button. If any two are swapped, say which - the fix is swapping
  two coordinate strings.
- [ ] **3. The countdown is real.** Use the left-click stone. Its row switches to
  a red countdown that ticks down while you keep hovering, and reaches Ready
  again on its own.
- [ ] **3b. The global cooldown is not a cooldown.** Use any item at all, or any
  stone, then hover immediately. No row may flash `0:01`. A stone that is
  genuinely ready says **Ready** the whole time; a stone you actually used shows
  a countdown. If any stone you own reports a real cooldown of two seconds or
  less, this check fails and the filter needs revisiting - say which stone.
- [ ] **4. The rows can disagree.** Set one button to the Dalaran Hearthstone or
  the Key to the Arcantina and another to any ordinary stone. Use the ordinary
  one. The other row must still read **Ready** - a single shared cooldown line
  was the old bug this replaces.
- [ ] **5. Random says so.** Set a button to Random. Its row reads
  `Random: <stone name>` with that stone's icon. Click the button, hover again:
  the name and the icon have changed to the next roll.
- [ ] **5b. The row names what WILL be used, not what was.** Hover, read the
  Random row, then click that button. The stone that actually goes off must be
  the one the row was naming. Hover again: a different stone is named, and
  clicking again uses THAT one. This is the check for the defect Kitn found on
  2026-08-21, where the row named the stone just used.
- [ ] **5c. One click does not disturb the other buttons.** Set two buttons to
  Random. Note both rows, click one. The OTHER row must still name the same
  stone it did before.
- [ ] **5d. Random never lands somewhere fixed.** Click a Random button twenty
  times, hovering between clicks. It must never name the **Dalaran Hearthstone**
  or the **Personal Key to the Arcantina**: those two go to a fixed place rather
  than to your hearth. Both must still be pickable by hand in all three
  dropdowns.
- [ ] **6. The destination is right.** The last line reads `Hearth set to` and
  your actual inn. Hearth somewhere else, `/reload`, hover again: it has changed.
- [ ] **7. A stone you do not own is not offered.** Nothing in the three rows may
  show a bare number instead of a name once you have been logged in a few
  seconds.
- [ ] **7b. Nor on the very first hover.** Log in fresh, or `/reload`, and hover
  the hearthstone as fast as you can. No row may read `Random: 6948` or any
  other bare number: a stone whose name has not arrived yet must say
  **Hearthstone** and then correct itself within a second while you keep
  hovering. This is the check for the defect Kitn found on 2026-08-21.
- [ ] **8. The clock's right click opens the stopwatch.** Right click the clock.
  The Time Manager window opens, with the stopwatch and the alarm in it. Right
  click again: it closes.
- [ ] **9. The other two clock clicks are untouched.** Left click still opens the
  calendar. Middle click still reloads.
- [ ] **10. The clock tooltip reads as three choices.** Hover the clock: a
  **Clock** title, then three rows with the same three pictures, reading
  Calendar, Stopwatch and Alarm, Reload UI.
- [ ] **11. Combat is refused.** Pull a target dummy. Right click the clock: the
  red "not in combat" message, and no window opens.
- [ ] **12. Home and volume read the same way.** Hover each. Home shows a left
  and a right picture; volume shows left, right and scroll. No line anywhere on
  the bar still reads "Left-click:" in words.
- [ ] **13. Every title has a gap under it.** Hover friends, guild, Great Vault,
  hearthstone, home, volume and the clock. Each shows its name, one blank row,
  then its content.
- [ ] **14. No gap where there is nothing to say.** Hover Toy Box, Talents, Game
  Menu, Mythic+ Portals. Each is its name alone, with **no** empty row under it.
- [ ] **15. No gap under an empty roster.** Zone into a dungeon or raid, then
  hover friends and guild. Each must be its name alone with no empty row: in
  there the name lists are withheld, and the gap must be withheld with them.
- [ ] **16. The clock lists your lockouts.** On a character saved to something,
  hover the clock. Under a **Saved Raid(s)** heading in your accent colour there
  is one row per lockout: the instance picture, its name, its size and difficulty
  in grey, the boss count where the instance has one, and the time left on the
  right.
- [ ] **16b. The pictures are the right instances.** Each row's picture is that
  instance's own art from the Encounter Journal, cropped square. A row with no
  picture is not a fault by itself - the join is by name - but tell me which
  instance, because a missing one means its name does not match the journal's.
- [ ] **16c. The journal is not disturbed.** Open the Encounter Journal, pick an
  expansion that is NOT the current one, leave it open, and hover the clock. The
  journal must still be on the expansion you chose. Close it and hover again:
  the pictures appear from then on.
- [ ] **17. It matches Blizzard.** Open the game's own raid info panel (the Raid
  tab of the social window). The same lockouts, the same boss counts, the same
  times give or take a minute of rounding. **Read the boss counts carefully.**
  They come from two fields Blizzard's own code never uses, so if they are the
  wrong fields the row shows a plausible but WRONG count rather than showing
  nothing. A count that disagrees with Blizzard's panel is the finding.
- [ ] **18. No heading with nothing under it.** On a character saved to nothing,
  hover the clock. There is **no** Saved Raid(s) heading and no empty row - the
  tooltip goes straight from the title to the reset lines.
- [ ] **19. The reset clocks are right.** Daily reset and Weekly reset both show
  a time, and both count down rather than up if you hover again later.
- [ ] **20. The time line shows the OTHER clock.** Exactly ONE time line shows,
  and it is never the one on the bar. With the Top Bar's server-time setting on,
  the face shows realm time and the line reads **Local time**; with it off, the
  reverse. If the two ever read the same number, that is the bug. Flip the 12/24
  hour setting: the line follows it.
- [ ] **20b. The labels lead.** On the Daily reset, Weekly reset and time lines
  the left-hand label is white and the time on the right is grey. That is the
  reverse of what it was.
- [ ] **21. Hovering is cheap.** Hover the clock, move away, hover again, twenty
  times in a row. No stutter, no chat spam, and nothing in BugSack. This is the
  check for the throttle: a fresh lockout you just earned may take up to 30
  seconds and a second hover to appear, and that is expected, not a defect.
- [ ] **22. BugSack is empty.** After all of the above, including hovering every
  button while in combat.

## Result

- Date: 2026-08-21
- Reported by Kitn: **all checks passed.**
- Hearthstone tooltip (checks 1-7): pass
- Clock clicks (checks 8-11): pass
- Spacing and pictures elsewhere (checks 12-15): pass
- Clock tooltip body (checks 16-21, including 16b, 16c and 20b): pass
- BugSack (check 22): pass
- Notes: the individual boxes above are left unticked on purpose. This file says
  no agent may record a check as passed, and a tick written by an agent looks
  exactly like one written by the tester. The line above is Kitn's own report,
  attributed; tick the boxes yourself if you want them ticked.

---

# Item 6 — Lulu Mode holds the whole circle layout

Branch `feature/lulu-circle-layout`. Touches `KitnUI_EUI/Lulu.lua`, one string in
`KitnUI_EUI/General.lua`, and adds `dev/tests/lulu-minimap-keys.lua`. Nothing else
moves.

## What changed and why it needs testing

- Lulu Mode used to force **one** EllesmereUI minimap key, `shape`. It now forces
  **eighteen**: the shape, and the position and offsets of the clock, the zone
  text, the FPS/MS readout, the mail icon, the difficulty text, and the minimap
  button row's distance from the map.
- A round minimap moves nothing on its own. Everything above was anchored for a
  square and sat wrong the moment the corners went. These values were tuned in
  game against the circle.
- Every one of the eighteen takes its own note, so switching Lulu off puts each one
  back to exactly what the user had, one at a time. **That is the risk this section
  exists for.** A note that is missed leaves a setting held forever; a note that
  records KitnUI's own forced value hands back the wrong thing.
- Someone who already had Lulu Mode on before this release gets **asked once**.
  The background re-apply is not allowed to write down what a setting was before;
  only a click may. So a popup appears saying the minimap positions are not
  applied yet, and accepting it applies them.
- No reload is needed for any of this. It applies on the toggle, and on that
  popup's accept.

## Read this before starting

- **Write down what your minimap looks like before you start**, or better, run the
  snapshot probe from "Shared tools" after switching Lulu on and keep the output.
  Check 3 compares against it and there is no other record.
- Lulu Mode still reloads when toggled, for its action bar and Edit Mode halves.
  The minimap half applies before the reload, not because of it.
- EllesmereUI's own clock and FPS/MS box are hidden **per readout**, not per bar:
  the Top Bar takes the host's clock only while the bar is up AND the bar's clock
  element is on, and takes the host's FPS box only while the bar's own FPS readout
  is showing. Hiding the whole Top Bar is the simplest way to see both host
  readouts, and that is what checks 2 and 3 assume.
- The difficulty text only appears when "Show Instance Difficulty as Text" is on
  in EllesmereUI's minimap options, and you need to be in an instance for it to
  say anything. Lulu deliberately does not switch it on for you.
- The mail offsets only apply when Mail Position is a corner rather than "Minimap
  Button". Lulu forces the corner, so under Lulu they always apply.

## The checks

- [ ] **1. It goes round and everything moves with it.** Start with Lulu Mode off.
  Switch it on and accept. After the reload the minimap is a circle, and the zone
  text, mail icon, difficulty text and button row have all moved. If the minimap is
  round but any of those four is still sitting where it was, that key is not being
  written -- say which one.
- [ ] **2. The clock and FPS/MS moved too.** With Lulu on, hide the Top Bar. The
  clock sits at the bottom of the minimap and the FPS/MS readout just below it,
  not overlapping. Show the Top Bar again; both disappear, which is correct.
- [ ] **2b. Per readout, not per bar.** Put the Top Bar back up, then switch OFF
  just its clock element in the Top Bar options. EllesmereUI's own clock returns to
  the minimap, and it must be in Lulu's bottom position, not its old one.
- [ ] **3. Everything comes back.** Switch Lulu Mode off and accept. Every one of
  the six things above returns to exactly where it was before check 1, including
  the small sideways nudges the clock, zone and FPS had. Then run the snapshot
  probe: it must print **`NOTES 0`**. A number other than zero names a setting
  KitnUI is still holding after it said it let go.
- [ ] **4. An already-on Lulu is ASKED, not changed behind your back.** This is the
  only check for the upgrade path and it cannot be done after check 3, so do it on
  a character where Lulu Mode was already on before this build. Log in without
  touching the switch. A popup must appear saying Lulu Mode is on but its minimap
  positions are not applied. **Before you accept, look at the minimap: nothing has
  moved yet.** A minimap that has already moved means the re-apply claimed on its
  own, which is the defect this design exists to prevent.
- [ ] **4b. Accepting applies it, with no reload.** Accept the popup. The six
  things move to their circle positions immediately and the screen does NOT
  reload. Then switch Lulu off: all six come back to what that character had
  before, and the probe reads `NOTES 0`.
- [ ] **4c. Declining leaves everything alone.** On another such character, decline
  the popup. Nothing moves, and the probe shows only the one shape note. The popup
  must come back at the next login or profile switch, not be gone for good.
- [ ] **5. It survives a profile switch.** With Lulu on, switch to another
  EllesmereUI profile and back. The circle layout is still correct and the probe
  count has not changed. Switching to a profile whose Lulu is off must NOT leave
  the text positions forced.
- [ ] **6. The tooltip tells the truth.** Hover the Lulu Mode switch with Lulu on.
  The ownership sentence names the minimap shape and the readouts, not the shape
  alone.
- [ ] **7. Two off in a row is not an error.** Switch Lulu off twice, by toggling
  it on and off and then off again from another profile if you can reach that
  state. Nothing is printed twice, nothing errors, and the probe still reads
  `NOTES 0`.
- [ ] **8. BugSack is empty.** Through all of the above. Any error at all is a
  fail, even one that looks unrelated.

## Result

- Date: 2026-08-21
- Reported by Kitn: **all checks passed.**
- The eighteen keys applying and coming back (checks 1, 2, 2b, 3): pass
- The upgrade prompt (checks 4, 4b, 4c): pass
- Profile switch, tooltip, double-off (checks 5, 6, 7): pass
- BugSack (check 8): pass
- Notes: the individual boxes above are left unticked on purpose. This file says
  no agent may record a check as passed, and a tick written by an agent looks
  exactly like one written by the tester. The line above is Kitn's own report,
  attributed; tick the boxes yourself if you want them ticked.

---

# Item 7 — A Tweaks section, and Accents folded into Appearance

**Plan:** `dev/docs/superpowers/plans/2026-08-21-tweaks-and-accents.md` (local only).
**Branch** `feature/tweaks-and-accents`. Touches `KitnUI_EUI/Core.lua` and
`KitnUI_EUI/General.lua`. Nothing else moves. **Status: awaiting Kitn.**

## What changed and why it needs testing

- The General page is regrouped. `APPEARANCE` keeps the Dark/Colored buttons.
  `ACCENTS` sits directly under it with no gap, so it reads as part of Appearance.
  `TWEAKS` is a new section below a gap, holding Dark Class Resource Bar, Lulu
  Mode, and a not-yet-built Bite Mode.
- The single accent switch became **three rows**, and this is the part that can go
  wrong. It used to do two jobs at once: set the accent to KitnUI pink, and scope
  the accent (put it on the quest tracker header, keep it off the tracker's divider
  lines, the Mythic+ timer, the damage meter and the Friends tab). Those two jobs
  are now split:
  - **KitnUI Accent Coloring** is the master. It is the ONLY control that records
    what you had before and the ONLY one that hands it back. Its mechanics did not
    change.
  - **Use KitnUI Pink** chooses the colour and must NEVER touch the scoping.
  - **Accent Color** stores your own colour. Picking one also switches Use KitnUI
    Pink off.
- Two new saved settings, `accentUseDefault` and `accentCustom`. The second is a
  table, and tables in this addon have vanished at logout before when written the
  wrong way. Check 8 is what proves this one does not.
- Bite Mode is a real row with a dead veil over it. No saved setting at all.

## Read this before starting

- **Start from a profile where you have set your OWN accent colour**, something you
  will recognise and that is neither KitnUI pink nor the test colour. Several
  checks below are meaningless without it, because they ask whether YOUR colour
  comes back.
- Have the quest tracker, the Friends tab and, if you can, the damage meter
  visible. Those are where the scoping shows.
- Use the snapshot probe from "Shared tools" above whenever a check mentions
  `NOTES`.

## The checks

- [ ] **1. The page reads in three blocks.** Open the KitnUI tab, General page.
  Top to bottom: `APPEARANCE (...)`, the Dark/Colored buttons, then `ACCENTS` with
  **no gap above it**, then its three rows, then a gap, then `TWEAKS`. If ACCENTS
  looks like a separate island rather than part of Appearance, say so — that is the
  one judgement call in this item and it is yours.
- [ ] **2. With the master OFF, the two rows below it are dead.** Use KitnUI Pink
  and Accent Color are both dimmed. Click each one. Nothing moves, nothing opens,
  BugSack stays empty.
- [ ] **3. TWEAKS holds three rows, in order.** Dark Class Resource Bar, Lulu Mode,
  Bite Mode.
- [ ] **4. Bite Mode is dead.** Dimmed, with a pink-bordered "Coming Soon" box.
  Clicking it does nothing at all: the switch does not move. Hovering may or may
  not show its tooltip through the veil — **either is fine**, just note which
  happened.
- [ ] **5. Dark Class Resource Bar still works from its new home.** Toggle it and
  watch the class resource bar. Then pull a target, and while in combat try it
  again: it must refuse with the usual message rather than half-applying.
- [ ] **6. Turn the master ON.** `KitnUI Accent Coloring`. The accent goes KitnUI
  pink exactly as the old switch did, the quest tracker header takes it, and the
  two rows below come alive. The probe shows notes present.
- [ ] **7. The one that matters most — colour without losing the scoping.** Switch
  **Use KitnUI Pink** off and pick something obviously different, say green. Then
  check all four scoped places:
  - the quest tracker header is green, not class-coloured,
  - the tracker's divider lines are still NOT tinted,
  - the Mythic+ timer title is still NOT tinted,
  - the damage meter and the Friends tab are still NOT tinted.

  **If any of those changed, stop and report it.** That is the defect this whole
  split exists to prevent.
- [ ] **7b. Pick a colour straight from the swatch while Use KitnUI Pink is ON.**
  The colour applies AND Use KitnUI Pink switches itself off, in the same click,
  without a reload.
- [ ] **7c. Cancel the picker.** Open the swatch while Use KitnUI Pink is ON, drag
  around so the preview changes, then press **cancel**. The accent returns to pink
  AND Use KitnUI Pink is still ON. It flipping off would be a fail.
- [ ] **7d. Switching pink off is visible on a fresh profile.** On a profile where
  you have never picked a colour, switch Use KitnUI Pink off. The accent goes
  WHITE, not pink. A default of pink is what made this switch look dead the first
  time round.
- [ ] **7d2. Pink typed as hex re-arms the switch.** With Use KitnUI Pink OFF and
  a custom colour set, open the swatch and type `FF008C` into the Hex box, or click
  the pink favourite. The accent goes pink AND Use KitnUI Pink switches itself back
  ON. It staying off would be a fail: the comparison is on 8-bit values precisely
  so that a hex-entered pink counts as pink.
- [ ] **7e. The refusal speaks.** Force the unowned state: with the master ON,
  switch to an EllesmereUI profile KitnUI has never claimed, or clear the accent
  note. Change the colour. Chat prints "Color saved, but KitnUI is not holding the
  accent for this profile...". Then drag inside the picker for several seconds:
  that line must appear **once**, not once per frame.
- [ ] **7f. The refusal speaks again on a second profile.** Still unowned, switch
  to a DIFFERENT profile KitnUI has never claimed and change the colour there. The
  message appears again. Silence would mean the warning latch is stuck.
- [ ] **8. The custom colour survives a logout.** With the master on and a custom
  colour set, `/reload`. Both the colour and the Use KitnUI Pink state come back as
  you left them. Then log out to character select and back in, and check again —
  the reload is the weaker test of the two.
- [ ] **9. Pink comes back, and so does your colour.** Switch Use KitnUI Pink ON:
  the accent is pink. Switch it OFF: **your green comes back**, not black and not
  pink. Scoping unchanged throughout.
- [ ] **10. Turn the master OFF.** Your own original accent from before check 6
  comes back — NOT pink, NOT green. All the scoped places return to how you had
  them. The probe reads `NOTES 0`. This is the check that proves the colour rows
  never touched the ownership record.
- [ ] **11. Search still finds it.** Type `pink` into EllesmereUI's settings
  search. The KitnUI accent block comes up.
- [ ] **12. Profile switch.** With the master on and a custom colour, switch to
  another EllesmereUI profile and back. The colour and the scoping are still right,
  and nothing is printed twice.
- [ ] **13. `/kitn reset`, run while the master is ON with a custom colour.** The
  obvious guess is wrong, and the difference between what is LIVE and what is
  merely SELECTED is the whole point of this check:
  - EllesmereUI's live accent is **your own original colour**, NOT pink and NOT the
    custom one. Reset re-merges the defaults and only then re-applies, so the
    master reads off while the notes are still there to restore from.
  - All the scoped places are back to your originals.
  - KitnUI Accent Coloring reads OFF, Use KitnUI Pink reads ON.
  - The Accent Color swatch, dimmed under its veil, shows PINK. That is only what
    is SELECTED, never what is live: the accent on screen is still your original.
    Pink is selected because `accentUseDefault` reset to true, NOT because the
    stored colour reset to pink. It reset to white.
  - Prove that last part: turn KitnUI Accent Coloring back ON, which lifts the veil
    and makes the accent pink for real. Then switch Use KitnUI Pink off: the accent
    goes WHITE. That is the stored default, and it shows the reset reached
    `accentCustom`.
- [ ] **14. BugSack is empty.** Through all of the above. Any error at all is a
  fail, even one that looks unrelated.

## Result

- Date:
- Reported by Kitn:
- Notes:
