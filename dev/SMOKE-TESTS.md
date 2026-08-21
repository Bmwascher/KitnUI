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
| 5. Mouse-button pictures in the Top Bar tooltips | `feature/topbar-click-tooltips` | yes | not yet | **PENDING** |

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

Branch `feature/topbar-click-tooltips`. Touches `KitnUI_EUI/TopBar/Elements.lua`
and two names in `.luacheckrc`. Nothing else moves.

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
  character holds, then the daily and weekly reset clocks and realm and local
  time. Nothing here runs on a timer; it is read only while the tooltip is open.
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
- [ ] **4. The rows can disagree.** Set one button to the Dalaran Hearthstone or
  the Key to the Arcantina and another to any ordinary stone. Use the ordinary
  one. The other row must still read **Ready** - a single shared cooldown line
  was the old bug this replaces.
- [ ] **5. Random says so.** Set a button to Random. Its row reads
  `Random: <stone name>` with that stone's icon. Click the button, hover again:
  the name and the icon have changed to the next roll.
- [ ] **6. The destination is right.** The last line reads `Hearth set to` and
  your actual inn. Hearth somewhere else, `/reload`, hover again: it has changed.
- [ ] **7. A stone you do not own is not offered.** Nothing in the three rows may
  show a bare number instead of a name once you have been logged in a few
  seconds.
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
  times give or take a minute of rounding.
- [ ] **18. No heading with nothing under it.** On a character saved to nothing,
  hover the clock. There is **no** Saved to heading and no empty row - the
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

Kitn, record the outcome here.

- Date:
- Hearthstone tooltip (checks 1-7):
- Clock clicks (checks 8-11):
- Spacing and pictures elsewhere (checks 12-15):
- Clock tooltip body (checks 16-21, including 16b, 16c and 20b):
- BugSack (check 22):
- Notes:
