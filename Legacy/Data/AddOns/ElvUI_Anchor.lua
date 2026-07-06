local _, ns = ...
ns.data = ns.data or {}

------------------------------------------------------------
-- ElvUI_Anchor (frame positioning for ElvUI_Anchor plugin)
-- "dps" is used for Normal + Class Color profiles
-- "healer" is used for Healer + Healer Class Color profiles
------------------------------------------------------------

ns.data.ElvUI_Anchor = {
    dps = {
        ["focusY"] = 80,
        ["playerPowerEnabled"] = false,
        ["targetCastRelative"] = "BOTTOMLEFT",
        ["petPoint"] = "TOPLEFT",
        ["focusRelative"] = "TOPRIGHT",
        ["targetCastY"] = -2,
        ["focusPoint"] = "BOTTOMLEFT",
        ["targetCastPoint"] = "TOPLEFT",
        ["targetCastX"] = 1,
        ["focusX"] = 80,
        ["focusParent"] = "ElvUF_Target",
        ["focusCastEnabled"] = false,
        ["totEnabled"] = false,
        ["petY"] = -36,
        ["petRelative"] = "BOTTOMLEFT",
        ["targetPowerEnabled"] = false,
        ["playerCastEnabled"] = false,
    },
    healer = {
        ["targetX"] = 415,
        ["petPoint"] = "TOPLEFT",
        ["targetParent"] = "UIParent",
        ["targetCastX"] = 1,
        ["targetRelative"] = "CENTER",
        ["playerPoint"] = "CENTER",
        ["focusEnabled"] = false,
        ["targetCastRelative"] = "BOTTOMLEFT",
        ["targetY"] = -275,
        ["totEnabled"] = false,
        ["playerX"] = -415,
        ["targetPoint"] = "CENTER",
        ["focusCastEnabled"] = false,
        ["playerParent"] = "UIParent",
        ["playerRelative"] = "CENTER",
        ["playerY"] = -275,
        ["targetPowerEnabled"] = false,
        ["playerCastEnabled"] = false,
        ["targetCastY"] = -2,
        ["targetCastPoint"] = "TOPLEFT",
        ["petY"] = -36,
        ["petRelative"] = "BOTTOMLEFT",
        ["playerPowerEnabled"] = false,
    },
}
