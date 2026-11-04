-- Draws the XP bar's three textures as uncompressed TGA: white shapes on
-- alpha, tinted in game. Run by hand from the repo root, with the folder
-- KitnUI_EUI/Media/XPBar already made:
--
--   lua dev/scripts/gen-xpbar-media.lua

local SIZE = 32
local OUT = "KitnUI_EUI/Media/XPBar/"
-- How much of a stripe shows, so the rested color still reads through it.
local STRIPE_ALPHA = 0.45

local function u16(n)
    return string.char(n % 256, math.floor(n / 256))
end

-- The origin is bottom-left, so y runs up.
local function write(name, alphaAt)
    local parts = { string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0) .. u16(SIZE) .. u16(SIZE) .. string.char(32, 8) }
    for y = 0, SIZE - 1 do
        for x = 0, SIZE - 1 do
            parts[#parts + 1] = string.char(255, 255, 255, alphaAt(x, y))
        end
    end
    local f = assert(io.open(OUT .. name .. ".tga", "wb"))
    f:write(table.concat(parts))
    f:close()
end

-- The share of a pixel that is inside, from 16 samples.
local function coverage(inside, x, y)
    local hits = 0
    for sy = 1, 4 do
        for sx = 1, 4 do
            if inside(x + (sx - 0.5) / 4, y + (sy - 0.5) / 4) then hits = hits + 1 end
        end
    end
    return hits / 16
end

local function polygon(points)
    return function(px, py)
        local inside = false
        local j = #points
        for i = 1, #points do
            local xi, yi, xj, yj = points[i][1], points[i][2], points[j][1], points[j][2]
            if (yi > py) ~= (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi then
                inside = not inside
            end
            j = i
        end
        return inside
    end
end

local function solid(inside, scale)
    return function(x, y)
        return math.floor(coverage(inside, x, y) * 255 * scale + 0.5)
    end
end

-- One diagonal stripe per tile, seamless when repeated.
write("stripes", solid(function(x, y) return (x + y) % SIZE < SIZE / 2 end, STRIPE_ALPHA))

write("arrow", solid(polygon({ { 16, 30 }, { 28, 16 }, { 20, 16 }, { 20, 3 }, { 12, 3 }, { 12, 16 }, { 4, 16 } }), 1))

-- One straight fade, opaque on the bottom row and clear on the top. The Sweep's
-- strips turn it, and Energy Wave's streak crops it, with texture coordinates.
write("glowfade", function(_, y) return math.floor(255 * (1 - y / (SIZE - 1)) + 0.5) end)

print("wrote stripes.tga, arrow.tga and glowfade.tga to " .. OUT)
