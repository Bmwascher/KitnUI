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
for _, name in ipairs({ "stripes", "arrow", "glowfade" }) do
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

-- The glow's fade, read back from the shipped bytes: white throughout, the same
-- across each row, opaque at the bottom row and clear at the top.
do
    local f = io.open("KitnUI_EUI/Media/XPBar/glowfade.tga", "rb")
    if f then
        local bytes = f:read("*a")
        f:close()
        local white, level, falling = true, true, true
        local above = 256
        for y = 0, 31 do
            local rowAlpha = bytes:byte(18 + y * 32 * 4 + 4)
            for x = 0, 31 do
                local at = 18 + (y * 32 + x) * 4
                local b, g, r, a = bytes:byte(at + 1, at + 4)
                white = white and b == 255 and g == 255 and r == 255
                level = level and a == rowAlpha
            end
            falling = falling and rowAlpha < above
            above = rowAlpha
        end
        check(white, "glowfade.tga: white in every pixel")
        check(level, "glowfade.tga: the same across each row")
        check(falling, "glowfade.tga: alpha falls from row to row")
        eq(bytes:byte(18 + 4), 255, "glowfade.tga: opaque at its bottom row")
        eq(bytes:byte(18 + 31 * 32 * 4 + 4), 0, "glowfade.tga: clear at its top row")
    end
end

local starFile = io.open("KitnUI_EUI/Media/XPBar/star.tga", "rb")
eq(starFile, nil, "star.tga does not ship")
if starFile then starFile:close() end

---------------------------------------------------------------------------------
-- Recording stubs
---------------------------------------------------------------------------------

local NOOP = function() end
local methods = {}
local made = { frames = 0, textures = 0, groups = 0 }

-- A capitalized method is a no-op unless listed below; a data field reads nil.
local function Obj(kind)
    return setmetatable({ kind = kind, shown = true, scripts = {} }, {
        __index = function(_, key)
            if methods[key] then return methods[key] end
            if type(key) == "string" and key:match("^%u") then return NOOP end
            return nil
        end,
    })
end

methods.SetScript = function(self, name, fn) self.scripts[name] = fn end
methods.Show = function(self) self.shown = true end
methods.Hide = function(self) self.shown = false end
methods.SetShown = function(self, v) self.shown = v and true or false end
methods.IsShown = function(self) return self.shown end
methods.IsVisible = function(self) return self.shown end
methods.GetFrameLevel = function() return 1 end
methods.SetFont = function() return true end
methods.CreateTexture = function()
    made.textures = made.textures + 1
    return Obj("Texture")
end
methods.CreateFontString = function() return Obj("FontString") end
methods.CreateMaskTexture = function() return Obj("MaskTexture") end
methods.CreateAnimationGroup = function()
    made.groups = made.groups + 1
    return Obj("AnimationGroup")
end
methods.CreateAnimation = function(_, kind) return Obj(kind) end
methods.GetStatusBarTexture = function(self)
    self.barTex = self.barTex or Obj("Texture")
    return self.barTex
end
methods.SetOffset = function(self, x, y) self.ox, self.oy = x, y end
methods.SetScaleFrom = function(self, x) self.fromX = x end
methods.SetScaleTo = function(self, x) self.toX = x end
methods.Play = function(self)
    self.plays = (self.plays or 0) + 1
    self.playing = true
end
methods.Stop = function(self) self.playing = false end
methods.AddMaskTexture = function(self, mask) self.mask = mask end
methods.RemoveMaskTexture = function(self) self.mask = nil end
methods.SetTexCoord = function(self, ...) self.tc = { ... } end
methods.SetTexture = function(self, file) self.file = file end
methods.SetVertexColor = function(self, r, g, b, a) self.vertex = { r, g, b, a } end
methods.SetPoint = function(self, point, rel, relPoint, x, y) self.pt = { point, rel, relPoint, x, y } end
methods.SetWidth = function(self, v) self.width = v end
methods.SetHeight = function(self, v) self.height = v end
methods.SetGradient = function(self) self.gradients = (self.gradients or 0) + 1 end
methods.SetText = function(self, v) self.text = v end

_G.CreateFrame = function(kind)
    made.frames = made.frames + 1
    return Obj(kind)
end
_G.UIParent = Obj("Frame")
_G.CreateColor = function() return { SetRGBA = NOOP } end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

local missingAtlas
_G.C_Texture = {
    GetAtlasInfo = function(name)
        if name == missingAtlas then return nil end
        return { width = 64, height = 16, file = 1 }
    end,
}

local function loadAll()
    local ns = {}
    function ns.EUIPlain(v)
        if v ~= nil and _G.issecretvalue and _G.issecretvalue(v) then return nil end
        return v
    end
    for _, name in ipairs({ "Math", "Render", "Effects" }) do
        local file = "KitnUI_EUI/XPBar/" .. name .. ".lua"
        local chunk, err = loadfile(file)
        if not chunk then
            print("FAIL  could not load " .. file .. ": " .. tostring(err))
            os.exit(1)
        end
        chunk("KitnUI_EUI", ns)
    end
    return ns.XPBar
end

local settings = {}
local function view(key) return settings[key] end
local function resetSettings()
    for key in pairs(settings) do settings[key] = nil end
    settings.xpWidth, settings.xpHeight = 200, 20
    settings.xpGainEffect, settings.xpGainShowAmount, settings.xpGainMatchBar = "pulse", true, true
    settings.xpGainTextSize, settings.xpLevelEffect, settings.xpGlowSize = 13, "flash", 8
end

local X = loadAll()
local data = { fill = 40, questEnd = 50, restedEnd = 60 }
local function newBar()
    local w = X.NewWidget(_G.UIParent, "xp")
    X.Draw(w, view, data)
    return w
end
local function finished(set) set.group.scripts.OnFinished() end

---------------------------------------------------------------------------------
-- Nothing until the first play
---------------------------------------------------------------------------------

resetSettings()
do
    local w = newBar()
    eq(w.fxClip, nil, "no effect: no frame after a draw")
    eq(w.fxSets, nil, "no effect: no group after a draw")
    settings.xpGainEffect, settings.xpLevelEffect = "off", "off"
    X.PlayGainEffect(w, view, data, 10, 20, 5)
    X.PlayLevelEffect(w, view)
    eq(w.fxClip, nil, "effects off: a play makes no frame")
    eq(w.fxBusy, nil, "effects off: and plays nothing")
end

---------------------------------------------------------------------------------
-- A play, and a repeat
---------------------------------------------------------------------------------

resetSettings()
do
    local w = newBar()
    X.PlayGainEffect(w, view, data, 10, 20, 5)
    local set = w.fxSets and w.fxSets.pulse
    check(set ~= nil, "a play: makes its effect")
    eq(w.fxBusy, set, "a play: it is the active effect")
    eq(set and set.tex.shown, true, "a play: its texture shows")
    eq(set and set.tex.pt[4], 20, "a play: over the gained span's left")
    eq(set and set.tex.width, 20, "a play: and its width")
    eq(w.fxAmount and w.fxAmount.text, "+5", "a play: the amount floats with it")
    if set then finished(set) end
    eq(w.fxBusy, nil, "a play: finished")
    eq(set and set.tex.shown, false, "a play: its texture hides")
    local frames, textures, groups = made.frames, made.textures, made.groups
    X.PlayGainEffect(w, view, data, 20, 30, 5)
    eq(made.frames, frames, "a repeat: no new frame")
    eq(made.textures, textures, "a repeat: no new texture")
    eq(made.groups, groups, "a repeat: no new group")
    eq(set and set.group.plays, 2, "a repeat: the same group plays")

    settings.xpGainShowAmount = false
    if set then finished(set) end
    w.fxAmount:Hide()
    X.PlayGainEffect(w, view, data, 30, 40, 5)
    eq(w.fxAmount.shown, false, "Show Amount Gained off: no amount")
end

---------------------------------------------------------------------------------
-- The Blizzard frame's mask
---------------------------------------------------------------------------------

resetSettings()
do
    local function allMasked(w, mask)
        for i = 1, #w.fxRegions do
            if w.fxRegions[i].mask ~= mask then return false end
        end
        return true
    end
    settings.xpFrameStyle, settings.xpRestedStripes, settings.xpStripeSize = "blizzard", true, 10
    local w = newBar()
    eq(w.masksOn, true, "Blizzard style: the masks are on")
    eq(w.stripes.mask, w.blizzMask, "Blizzard style: the stripes carry the mask")
    X.PlayGainEffect(w, view, data, 10, 20, 5)
    check(#w.fxRegions > 0 and allMasked(w, w.blizzMask), "Blizzard style: a region made between draws carries the mask")
    settings.xpFrameStyle = "eui"
    X.Draw(w, view, data)
    eq(w.masksOn, false, "another style: the masks are off")
    eq(w.stripes.mask, nil, "another style: the stripes lose the mask")
    check(allMasked(w, nil), "another style: every region loses the mask")
end

---------------------------------------------------------------------------------
-- Rested Stripes
---------------------------------------------------------------------------------

resetSettings()
do
    settings.xpRestedStripes, settings.xpStripeSize = true, 10
    local w = newBar()
    eq(w.stripes.shown, true, "stripes: they show over rested XP")
    eq(w.stripes.pt[4], 120, "stripes: to the rested segment's right")
    eq(w.stripes.tc[1], 10, "stripes: coordinates from absolute x")
    eq(w.stripes.tc[2], 12, "stripes: to absolute x")
    eq(w.stripes.tc[4], 2, "stripes: and the bar's height in tiles")
    X.Draw(w, view, { fill = 40, questEnd = 50, restedEnd = 50 })
    eq(w.stripes.shown, false, "stripes: hidden with no rested XP")
    settings.xpRestedStripes = false
    local off = newBar()
    eq(off.stripes, nil, "stripes: with the switch off none is made")

    settings.xpRestedStripes, settings.xpDivider, settings.xpGapSize = true, "gaps", 2
    local gapped = newBar()
    check(gapped.segments ~= nil, "stripes over gaps: the bar is cut")
    if gapped.segments then
        local first = gapped.segments[1].copy.stripes
        local last = gapped.segments[20].copy.stripes
        check(first ~= nil and last ~= nil, "stripes over gaps: every copy has its own")
        eq(first.tc[1], last.tc[1], "stripes over gaps: their coordinates line up")
        eq(first.tc[1], gapped.stripes.tc[1], "stripes over gaps: with the whole bar's")
    end
end

---------------------------------------------------------------------------------
-- When nothing plays
---------------------------------------------------------------------------------

resetSettings()
do
    local w = newBar()
    w.frame:Hide()
    X.PlayGainEffect(w, view, data, 10, 20, 5)
    eq(w.fxBusy, nil, "a hidden bar plays nothing")
    w.frame:Show()

    local SECRET = {}
    local realVisible = methods.IsVisible
    _G.issecretvalue = function(v) return v == SECRET end
    methods.IsVisible = function() return SECRET end
    X.PlayGainEffect(w, view, data, 10, 20, 5)
    eq(w.fxBusy, nil, "a secret visibility counts as hidden")
    methods.IsVisible, _G.issecretvalue = realVisible, nil

    X.UnlockActive = true
    X.PlayGainEffect(w, view, data, 10, 20, 5)
    X.PlayLevelEffect(w, view)
    eq(w.fxBusy, nil, "Unlock Mode: nothing plays")
    X.UnlockActive = nil
end

---------------------------------------------------------------------------------
-- Merging, a level effect and stopping
---------------------------------------------------------------------------------

resetSettings()
do
    local w = newBar()
    X.PlayGainEffect(w, view, data, 10, 20, 5)
    local set = w.fxSets.pulse
    X.PlayGainEffect(w, view, data, 20, 30, 7)
    X.PlayGainEffect(w, view, data, 30, 40, 3)
    eq(set.group.plays, 1, "merge: a gain during a play waits")
    finished(set)
    eq(set.group.plays, 2, "merge: it replays once")
    eq(set.tex.pt[4], 40, "merge: from the first gain's start")
    eq(set.tex.width, 40, "merge: to the last gain's end")
    eq(w.fxAmount.text, "+10", "merge: with the amounts summed")
    finished(set)
    eq(set.group.plays, 2, "merge: and no more")

    X.PlayGainEffect(w, view, data, 30, 40, 5)
    X.PlayGainEffect(w, view, data, 20, 30, 7)
    X.PlayGainEffect(w, view, data, 10, 20, 3)
    finished(set)
    eq(set.tex.pt[4], 20, "merge: gains out of order start at the lowest")
    eq(set.tex.width, 40, "merge: and end at the highest")
    finished(set)

    X.PlayGainEffect(w, view, data, 10, 20, 5)
    X.PlayGainEffect(w, view, data, 20, 30, 7)
    X.PlayLevelEffect(w, view)
    eq(w.fxPendFrom, nil, "a level effect: clears what is pending")
    eq(set.group.playing, false, "a level effect: stops the gain")
    eq(set.tex.shown, false, "a level effect: and hides it")
    local flash = w.fxSets.flash
    eq(w.fxBusy, flash, "a level effect: is the active effect")
    eq(flash.tex.shown, true, "a level effect: shows")
    local plays = set.group.plays
    X.PlayGainEffect(w, view, data, 30, 40, 9)
    eq(set.group.plays, plays, "a level effect: a gain during it waits")
    finished(flash)
    eq(set.group.plays, plays + 1, "a level effect: and replays after it")

    -- A turn-in's gain runs beside a level effect, in either order.
    X.StopEffects(w)
    X.PlayGainEffect(w, view, data, 0, 20, 9, true)
    eq(w.fxQuest, set, "a turn-in's gain: runs in its own slot")
    eq(w.fxBusy, nil, "a turn-in's gain: and leaves the other free")
    X.PlayLevelEffect(w, view)
    eq(set.group.playing, true, "a turn-in's gain: a level effect does not stop it")
    eq(w.fxAmount.shown, true, "a turn-in's gain: nor its amount")
    eq(w.fxBusy, flash, "a turn-in's gain: and both run")
    finished(set)
    eq(w.fxQuest, nil, "a turn-in's gain: finishes on its own")
    eq(w.fxBusy, flash, "a turn-in's gain: and the level effect goes on")
    finished(flash)

    X.PlayLevelEffect(w, view)
    plays = set.group.plays
    X.PlayGainEffect(w, view, data, 0, 20, 9, true)
    eq(set.group.plays, plays + 1, "a turn-in's gain: plays at once during a level effect")
    eq(w.fxAmount.text, "+9", "a turn-in's gain: with its amount")
    X.PlayGainEffect(w, view, data, 20, 30, 1, true)
    eq(set.group.plays, plays + 1, "a turn-in's gain: another merges")
    finished(flash)
    eq(w.fxBusy, nil, "a turn-in's gain: the level effect finishes on its own")
    eq(w.fxQuest, set, "a turn-in's gain: and what it merged still waits for the gain")
    finished(set)
    eq(set.group.plays, plays + 2, "a turn-in's gain: then replays")
    eq(w.fxAmount.text, "+1", "a turn-in's gain: with the merged amount")
    finished(set)

    X.PlayGainEffect(w, view, data, 0, 20, 9, true)
    X.PlayGainEffect(w, view, data, 20, 30, 1)
    eq(w.fxBusy, nil, "a reading's gain: waits for a turn-in's")
    finished(set)

    -- A reading's gain still gives way, and a turn-in merged with it does not.
    X.PlayGainEffect(w, view, data, 0, 20, 5)
    X.PlayLevelEffect(w, view)
    eq(set.group.playing, false, "a reading's gain: a level effect stops it")
    eq(w.fxAmount.shown, false, "a reading's gain: and its amount")
    X.StopEffects(w)
    X.PlayGainEffect(w, view, data, 0, 20, 5)
    X.PlayGainEffect(w, view, data, 20, 30, 9, true)
    eq(w.fxQuest, nil, "a turn-in's gain: waits for a reading's")
    X.PlayLevelEffect(w, view)
    eq(w.fxQuest, set, "a turn-in's gain: and starts when a level effect stops it")
    eq(w.fxBusy, flash, "a turn-in's gain: beside that effect")
    eq(w.fxPendFrom, nil, "a turn-in's gain: with nothing left pending")
    X.StopEffects(w)
    eq(w.fxQuest, nil, "stop: clears a turn-in's gain")
    eq(w.fxPendQuest, nil, "stop: and what it merged")

    -- Turn-ins merged across a level-up replay over the new fill alone.
    X.PlayGainEffect(w, view, data, 10, 20, 9, true)
    X.PlayGainEffect(w, view, data, 80, 90, 5, true)
    X.PlayGainEffect(w, view, data, 0, 10, 2, true)
    finished(set)
    eq(set.tex.pt[4], 0, "across a level-up: a span past it replaces the old level's")
    eq(set.tex.width, 20, "across a level-up: and ends where it ends")
    eq(w.fxAmount.text, "+7", "across a level-up: with the amounts summed")
    finished(set)

    local fillBefore = data.fill
    X.PlayGainEffect(w, view, data, 10, 20, 9, true)
    X.PlayGainEffect(w, view, data, 40, 50, 5, true)
    data.fill = 15
    finished(set)
    eq(set.tex.pt[4], 0, "across a level-up: a fill that fell while it waited starts at 0")
    eq(set.tex.width, 30, "across a level-up: and spans only that fill")
    finished(set)
    data.fill = fillBefore

    X.PlayGainEffect(w, view, data, 10, 20, 9, true)
    X.PlayGainEffect(w, view, data, 40, 50, 5, true)
    finished(set)
    eq(set.tex.pt[4], 80, "across a level-up: a fill that did not fall keeps the span")
    eq(set.tex.width, 20, "across a level-up: at its width")
    finished(set)
    X.StopEffects(w)
    eq(w.fxPendFill, nil, "stop: and the fill it merged at")

    X.PlayGainEffect(w, view, data, 40, 50, 1)
    X.StopEffects(w)
    eq(w.fxBusy, nil, "stop: nothing is active")
    eq(w.fxPendFrom, nil, "stop: nothing is pending")
    eq(set.group.playing, false, "stop: the group stops")
    eq(set.tex.shown, false, "stop: its texture hides")
    eq(w.fxAmount.shown, false, "stop: the amount hides")
    eq(pcall(X.StopEffects, newBar()), true, "stop: on a bar that never played")
end

---------------------------------------------------------------------------------
-- Ready Glow
---------------------------------------------------------------------------------

resetSettings()
do
    local w = newBar()
    eq(w.fxReady, nil, "ready: nothing until it is first set")
    local ready = { fill = 40, questEnd = 50, restedEnd = 60, readyEnd = 100 }
    X.Draw(w, view, ready)
    local set = w.fxReady
    check(set ~= nil, "ready: starts while set and visible")
    eq(set and set.group.plays, 1, "ready: one play")
    eq(set and set.tex.pt[4], 80, "ready: from the fill's end")
    eq(set and set.tex.width, 120, "ready: to the bar's end")
    eq(w.fxGlow, nil, "ready: makes no frame outside the bar")
    X.Draw(w, view, ready)
    eq(set and set.group.plays, 1, "ready: a redraw does not restart it")
    w.frame:Hide()
    X.Draw(w, view, ready)
    eq(set and set.group.playing, false, "ready: stops when hidden")
    eq(set and set.tex.shown, false, "ready: and hides")
    w.frame:Show()
    X.Draw(w, view, ready)
    eq(set and set.group.plays, 2, "ready: restarts on show")
    X.UnlockActive = true
    X.Draw(w, view, ready)
    eq(set and set.group.playing, false, "ready: stops in Unlock Mode")
    X.UnlockActive = nil
    X.Draw(w, view, ready)
    X.StopEffects(w)
    eq(set and set.group.playing, false, "ready: a stop stops it")
    X.Draw(w, view, ready)
    eq(set and set.group.playing, true, "ready: and a redraw brings it back")
    X.Draw(w, view, data)
    eq(set and set.group.playing, false, "ready: stops once no longer set")
end

---------------------------------------------------------------------------------
-- The Sweep's glow
---------------------------------------------------------------------------------

resetSettings()
do
    -- Each strip's field, the coordinates that turn the fade's opaque edge to the
    -- frame, and the dimension Glow Size sets.
    local STRIPS = {
        { "top", "0,1,0,1", "height" },
        { "bottom", "0,1,1,0", "height" },
        { "leftSide", "0,0,1,0,0,1,1,1", "width" },
        { "rightSide", "0,1,1,1,0,0,1,0", "width" },
    }
    local function checkStrips(set, size, when)
        for _, strip in ipairs(STRIPS) do
            local tex = set and set[strip[1]]
            local name = "glow, " .. when .. ", " .. strip[1]
            check(tex ~= nil and tostring(tex.file):find("glowfade", 1, true) ~= nil, name .. ": draws the fade")
            eq(tex and tex.tc and table.concat(tex.tc, ","), strip[2], name .. ": fading away from the frame")
            eq(tex and tex.vertex and table.concat(tex.vertex, ","), "1,0.82,0.25,1", name .. ": tinted gold")
            eq(tex and tex.gradients, nil, name .. ": with no gradient call")
            eq(tex and tex[strip[3]], size, name .. ": as deep as Glow Size")
        end
    end

    local w = newBar()
    settings.xpLevelEffect = "sweep"
    X.PlayLevelEffect(w, view)
    local set = w.fxSets and w.fxSets.sweep
    checkStrips(set, 8, "first play")

    X.StopEffects(w)
    X.Draw(w, view, data)
    settings.xpGlowSize = 12
    X.PlayLevelEffect(w, view)
    checkStrips(set, 12, "second play")
end

---------------------------------------------------------------------------------
-- What each style plays, and the masked fallback
---------------------------------------------------------------------------------

resetSettings()
do
    eq(X.EffectAvailable("pulse"), true, "styles: Pulse always")
    eq(X.EffectAvailable("wave"), true, "styles: Energy Wave always")
    eq(X.EffectAvailable("surge"), true, "styles: Spell Surge with its art")
    eq(X.ResolveGainEffect("surge"), "surge", "styles: a saved Surge plays Surge")
    eq(X.ResolveGainEffect("off"), "off", "styles: off stays off")
    eq(X.ResolveGainEffect("gone"), "pulse", "styles: an unknown style plays Pulse")

    local function playAll(w)
        local function stopNow() X.StopEffects(w) end
        settings.xpGainEffect = "wave"
        X.PlayGainEffect(w, view, data, 10, 20, 5)
        stopNow()
        settings.xpGainEffect = "surge"
        X.PlayGainEffect(w, view, data, 10, 20, 5)
        stopNow()
        settings.xpLevelEffect = "flash"
        X.PlayLevelEffect(w, view)
        stopNow()
        settings.xpLevelEffect = "sweep"
        X.PlayLevelEffect(w, view)
        stopNow()
    end
    local function offsets(w)
        local sets = w.fxSets
        return { sets.wave.moveSpark.ox, sets.wave.moveTrail.ox, sets.surge.moves[1].ox, sets.surge.moves[2].ox,
            sets.surge.moves[3].ox, sets.sweep.move.ox }
    end

    local moving = newBar()
    playAll(moving)
    for i, ox in ipairs(offsets(moving)) do
        check(ox > 0, "another style: moving part " .. i .. " moves", ox)
    end
    eq(moving.fxSets.surge.scale.fromX < 1, true, "another style: the ribbon scales")
    eq(moving.fxSets.flash.scale.toX < 1, true, "another style: the flash drains")

    settings.xpFrameStyle = "blizzard"
    local masked = newBar()
    playAll(masked)
    check(moving.fxSets.wave.moveSpark.ox > 0 and masked.fxSets.wave.moveSpark.ox > 0,
        "Blizzard style, motion on: it moves too")

    X.FX_MASKED_MOTION = false
    playAll(masked)
    for i, ox in ipairs(offsets(masked)) do
        eq(ox, 0, "fallback: moving part " .. i .. " stays put")
    end
    eq(masked.fxSets.surge.scale.fromX, 1, "fallback: the ribbon does not scale")
    eq(masked.fxSets.flash.scale.toX, 1, "fallback: the flash does not drain")

    settings.xpFrameStyle = "eui"
    X.Draw(masked, view, data)
    playAll(masked)
    check(masked.fxSets.wave.moveSpark.ox > 0, "fallback: another style keeps its motion")
    X.FX_MASKED_MOTION = true

    missingAtlas = "ui-castingbar-pip"
    local lacking = loadAll()
    eq(lacking.EffectAvailable("surge"), false, "styles: a missing atlas removes Spell Surge")
    eq(lacking.ResolveGainEffect("surge"), "pulse", "styles: and a saved Surge plays Pulse")
    missingAtlas = nil
end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
