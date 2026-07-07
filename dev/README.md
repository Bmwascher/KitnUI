# KitnUI dev tooling

Everything under `dev/` is **git-tracked but stripped from the player zip** by
`.pkgmeta`'s `- dev` entry — players never receive it.

| Path | Tracked? | Contents |
|------|----------|----------|
| `dev/Annotations/` | yes | wowlua-ls `---@meta` type stubs (`KitnUI.lua` = the `ns` namespace, `Types.lua` = companion-addon APIs). LS-only; never loaded by WoW, never shipped. |
| `dev/claude-hooks/` | yes | Durable copies of the Claude Code edit-time lint hook (`luacheck-postedit.ps1`) + its `settings.template.json`. `.claude/` is gitignored, so these templates are what survive a re-clone. |
| `dev/githooks/` | yes | `pre-push` — release-tag guard + luacheck gate. Opt in with `git config core.hooksPath dev/githooks` (the installer does this for you). |
| `dev/scripts/` | yes | `install-claude-hooks.ps1` — restores the hooks + pre-push config after a re-clone or PC reset. |
| `dev/docs/` | **no** (gitignored) | Local-only: the CurseForge readme (`CURSEFORGE_README.md`), art masters (`art/` — the `.png` the shipped `.tga` is baked from), and planning / Superpowers artifacts (`superpowers/`). |

KitnUI has no headless test suite — it's a profile loader with no pure-Lua logic
to unit-test. Verification is **`luacheck`** (shared config in the tracked
`.luacheckrc`) plus the in-game installer flow (`/kitn install`, then `/reload`).

## Where luacheck runs

One `.luacheckrc`, four places:

- **On edit** — the Claude Code PostToolUse hook (`.claude/hooks/luacheck-postedit.ps1`) lints every `.lua` you touch and blocks on warnings.
- **On push** — the `dev/githooks/pre-push` gate (opt-in), blocking at the zero-warning baseline.
- **In CI** — `.github/workflows/lint.yml` on every push/PR, and again as the `luacheck` job that gates release packaging.
- **By hand** — `luacheck .` from the repo root.

## Claude Code hooks (restore after a re-clone or PC reset)

Everything under `.claude/` is gitignored, so the edit-time lint hook dies with
the checkout. The tracked templates in `dev/claude-hooks/` are the durable
copies — restore them (and the pre-push `core.hooksPath` config) with:

```powershell
pwsh dev/scripts/install-claude-hooks.ps1
```

Idempotent; never overwrites an existing hooks block or personal permissions in
`.claude/settings.json`. When changing the live hook under `.claude/hooks/`,
mirror the change into `dev/claude-hooks/` so the template stays current.

## Pre-push gate (optional)

```sh
git config core.hooksPath dev/githooks
```

Runs `luacheck` (blocking, zero-warning baseline) before every push, and blocks
a `v*` tag that doesn't point at a `vX.Y.Z:` release commit on `main`. If
luacheck isn't on PATH the hook skips it with a notice rather than blocking (CI
still lints). Override a single push with `git push --no-verify`.
