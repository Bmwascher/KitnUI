# KitnUI dev tooling

Everything under `dev/` is **git-tracked but stripped from the player zip** by
`.pkgmeta`'s `- dev` entry — players never receive it.

| Path | Tracked? | Contents |
|------|----------|----------|
| `dev/Annotations/` | yes | wowlua-ls `---@meta` type stubs (`KitnUI.lua` = the `ns` namespace, `Types.lua` = companion-addon APIs). LS-only; never loaded by WoW, never shipped. |
| `dev/docs/` | **no** (gitignored) | Local-only: the CurseForge readme (`CURSEFORGE_README.md`), art masters (`art/` — the `.png` the shipped `.tga` is baked from), and planning / Superpowers artifacts (`superpowers/`). |

KitnUI has no headless test suite. Verification is **`luacheck`** on every `.lua`
edit (config in the machine-local `.luacheckrc`) plus the in-game installer flow
(`/kitn install`, then `/reload`).
