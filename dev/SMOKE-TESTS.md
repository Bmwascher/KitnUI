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
| 3. Ownership tooltip on forcing switches | `feature/ownership-tooltip` | yes | Sol PASS, Fable PASS | **PENDING** |

**Both branches were rebased onto `v2.0.1` on 2026-08-14.** The SHAs above are the
rebased ones; anything you wrote down before that date is gone. The rebase also
retired one check — see the NSRT note in Item 2.

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
- [ ] **10. Combat, pass A only.** Flip Beginner Mode during combat with nothing
  else happening. When combat ends, all THREE of its paths apply, and turning it
  off restores all three sentinels. It is the only switch using the deferred
  closure.
- [ ] **11. Partial import.** Fresh distinct sentinels on every path. Import a
  profile carrying the switches ON while excluding the module blobs they force, and
  exclude Global Settings so `euiAccent` is not carried. **Every sentinel survives
  untouched** and the probe prints `NOTES 0`. Some effects will be absent while the
  switch reads ON; that is the accepted state. **In pass B, DECLINE the Lulu
  reconcile prompt** — accepting is a legitimate claim and would read as a failure.
  Then finish the cycle: off changes nothing; on claims and the probe shows the new
  notes; a final off restores every sentinel and returns to `NOTES 0`.
- [ ] **12. The eviction race, pass A only.** Profile A: Beginner Mode OFF, no
  note, its own sentinels. Profile B: Beginner Mode ON, no note, its own distinct
  sentinels — prepare B by check 11's import route, not by clicking the switch,
  because the toggle cannot produce ON-with-no-note. Turn Beginner Mode ON in A
  during combat, then switch to B with the EllesmereUI profile keybind before
  combat ends. The message must list the four cancelling operations; B's sentinels
  are NOT forced and the probe shows no note under B's name. Back in A: the switch
  reads ON, nothing applied, no note under A's name. Then off, on (probe shows A's
  notes holding A's sentinels), off again (every sentinel returns, `NOTES 0`).
- [ ] **13. MANDATORY STANDALONE, after both passes.** The unloaded-module restore
  path, which neither pass reaches. Set the action bar sentinels, claim Beginner
  Mode with Lulu OFF, turn Lulu ON and reload. Now turn Beginner Mode OFF while
  Lulu is still ON: the probe must show its action bar notes cleared. Then turn
  Lulu OFF and reload: both action bar sentinels must be back.

## Result

Kitn, record the outcome here.

- Date:
- Pass A:
- Pass B:
- Check 13:
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
wizard counts it. One carve-out stays and would look like a bug if you did not
know: **BigWigs' install still toasts before you answer its prompt**, because that
call is asynchronous and always has been.

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

## Result

Kitn, record the outcome here.

- Date:
- Regression (checks 1-2):
- Disabled-addon (checks 3-5):
- BigWigs decline (check 6):
- Deleted profiles (checks 7-9):
- Notes:
