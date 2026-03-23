local _, ns = ...
ns.data = ns.data or {}

-- ElvUI private settings (shared across all profile variants)
ns.data.ElvUIPrivate = {
    ["bags"] = {
        ["enable"] = false,
    },
    ["general"] = {
        ["chatBubbleFont"] = "Expressway",
        ["chatBubbleFontOutline"] = "OUTLINE",
        ["chatBubbles"] = "disabled",
        ["glossTex"] = "KitnUI",
        ["minimap"] = {
            ["hideTracking"] = true,
        },
        ["nameplateFont"] = "Expressway",
        ["nameplateLargeFont"] = "Expressway",
        ["normTex"] = "KitnUI",
        ["totemTracker"] = false,
    },
    ["install_complete"] = 15.09,
    ["nameplates"] = {
        ["enable"] = false,
    },
    ["skins"] = {
        ["blizzard"] = {
            ["bags"] = false,
            ["bgmap"] = false,
        },
        ["parchmentRemoverEnable"] = true,
    },
}
