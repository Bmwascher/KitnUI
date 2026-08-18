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
