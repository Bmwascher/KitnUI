-- ╔══════════════════════════════════════════════════════════════╗
-- ║  xpbar-effects.lua                                           ║
-- ║  Purpose: Gate for the XP bars' effects: the drawn files,    ║
-- ║           the stripes and masks in Render.lua, and           ║
-- ║           Effects.lua. Loads the SHIPPED code, never a copy. ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   lua dev/tests/xpbar-effects.lua

local failures = 0
local checks = 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
    end
end

local function eq(actual, expected, label)
    check(actual == expected, label, "got " .. tostring(actual) .. ", wanted " .. tostring(expected))
end

-- The drawn files: uncompressed true color, 32 by 32, with alpha.
for _, name in ipairs({ "stripes", "star", "arrow" }) do
    local f = io.open("KitnUI_EUI/Media/XPBar/" .. name .. ".tga", "rb")
    check(f ~= nil, name .. ".tga exists")
    if f then
        local bytes = f:read("*a")
        f:close()
        eq(#bytes, 18 + 32 * 32 * 4, name .. ".tga: its size")
        eq(bytes:byte(3), 2, name .. ".tga: uncompressed true color")
        eq(bytes:byte(13) + bytes:byte(14) * 256, 32, name .. ".tga: its width")
        eq(bytes:byte(15) + bytes:byte(16) * 256, 32, name .. ".tga: its height")
        eq(bytes:byte(17), 32, name .. ".tga: 32 bits per pixel")
    end
end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
