---@meta
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Annotations/Types.lua — third-party addon stubs ONLY          ║
-- ║                                                                ║
-- ║  Minimal stubs for the companion-addon APIs KitnUI reads/      ║
-- ║  writes during profile import, so wowlua-ls doesn't flag them  ║
-- ║  as undefined. Blizzard's own API comes from the bundled DB    ║
-- ║  (framexml), not here. Loaded by wowlua-ls only; never by WoW; ║
-- ║  never shipped (rides on .pkgmeta's '- dev'). Extend as calls  ║
-- ║  on new addons are added.                                      ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ─── EllesmereUI (required dependency) ────────────────────────────
---@class EllesmereUI
---@field ImportProfile fun(str: string, name: string): boolean, string?, string?
---@field SetProfile fun(name: string)
---@field AssignProfileToSpec fun(name: string, specID: integer)
---@field RefreshAllAddons fun()
---@field MakeFont fun(parent: table, size: number, flags: string?, r: number?, g: number?, b: number?, a: number?): table
---@field MakeBorder fun(frame: table, r: number, g: number, b: number, a: number, pp: any)
---@field MakeStyledButton fun(btn: table, text: string, size: number, colours: number[], onClick: function): table, any, table
---@field SolidTex fun(...): any
---@field ShowConfirmPopup fun(self: EllesmereUI, opts: table)
---@field PanelPP any
EllesmereUI = EllesmereUI

-- ─── Companion addons written during import ───────────────────────
---@class Plater
---@field DecompressData fun(str: string, mode: string): table?
---@field db table
Plater = Plater

---@class BigWigsAPI
---@field RegisterProfile fun(addon: string, data: any, name: string, callback: fun(success: boolean))
BigWigsAPI = BigWigsAPI

---@class KitnEssentialsAPI
---@field DecodeProfileString fun(self: KitnEssentialsAPI, str: string): table?
---@field SetProfile fun(self: KitnEssentialsAPI, name: string)
KitnEssentialsAPI = KitnEssentialsAPI

---@class KitnEssentials
---@field GetModule fun(self: KitnEssentials, name: string, silent: boolean?): table?
---@field db table
KitnEssentials = KitnEssentials

---@class BuffReminders
---@field Import fun(self: BuffReminders, str: string, name: string): boolean, string?
---@field SetProfile fun(self: BuffReminders, name: string)
BuffReminders = BuffReminders

-- Account-wide SavedVariables tables mutated during import (shape is per-addon).
---@type table
EllesmereUIDB = EllesmereUIDB
---@type table
PlaterDB = PlaterDB
---@type table
PlaterDBChr = PlaterDBChr
---@type table
BigWigs3DB = BigWigs3DB
---@type table
BigWigsIconDB = BigWigsIconDB
---@type table
KitnEssentialsDB = KitnEssentialsDB
---@type table
NSRT = NSRT
