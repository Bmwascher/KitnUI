-- ╔══════════════════════════════════════════════════════════════╗
-- ║  forever-art.lua                                             ║
-- ║  Purpose: Gate for the marks drawn over the art on Forever.  ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Run from the repo root:
--   C:\Users\Brandon\Documents\KitnDev\tools\lua51\bin\lua.exe dev/tests/forever-art.lua

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

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

-- IHDR is always the first chunk, so these sit at fixed offsets.
local function PngHeader(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local header = file:read(26)
    file:close()
    if not header or #header < 26 or header:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil end
    local b = { header:byte(1, 26) }
    return {
        width      = b[17] * 16777216 + b[18] * 65536 + b[19] * 256 + b[20],
        height     = b[21] * 16777216 + b[22] * 65536 + b[23] * 256 + b[24],
        colorType  = b[26],
    }
end

-- Each mark shares its background's canvas, which is what lets it take the same
-- crop and the same anchors. Color type 6 is RGBA: a mark without alpha would
-- cover the art.
for _, pair in ipairs({
    { "Media/Background/KitnUI-EUI-Background.png", "Media/Background/KitnUI-EUI-Background-Forever.png" },
    { "Media/Background/KitnUI-EUI-Background-Rasta.png", "Media/Background/KitnUI-EUI-Background-Rasta-Forever.png" },
    { "KitnUI_EUI/Media/Backgrounds/KitnUI-EUI-Options.png", "KitnUI_EUI/Media/Backgrounds/KitnUI-EUI-Options-Forever.png" },
    { "KitnUI_EUI/Media/Backgrounds/KitnUI-EUI-Options-Rasta.png", "KitnUI_EUI/Media/Backgrounds/KitnUI-EUI-Options-Rasta-Forever.png" },
}) do
    local art, mark = PngHeader(pair[1]), PngHeader(pair[2])
    check(art ~= nil, pair[1] .. " is readable")
    check(mark ~= nil, pair[2] .. " ships")
    if art and mark then
        eq(mark.width, art.width, pair[2] .. " has its background's width")
        eq(mark.height, art.height, pair[2] .. " has its background's height")
        eq(mark.colorType, 6, pair[2] .. " carries alpha")
    end
end

-- The wizard's real function, lifted out of the file and run against a fake frame.
do
    local source = read("Installer/Wizard.lua")
    local helper = source:match("(local function paintCropped%(tex, path, altPath%).-\nend\n)")
    local body = source:match("(local function paintMark%(frame%).-\nend\n)")
    check(helper ~= nil, "the wizard defines paintCropped")
    check(body ~= nil, "the wizard defines paintMark")
    local paths = {}
    for name, path in source:gmatch('local (MARK_PATH[_ALT]*) = "([^"]+)"') do paths[name] = path end
    check(paths.MARK_PATH and paths.MARK_PATH:find("Background%-Forever%.png$"), "the wizard names the default mark")
    check(paths.MARK_PATH_ALT and paths.MARK_PATH_ALT:find("Background%-Rasta%-Forever%.png$"), "the wizard names the alternate mark")

    -- Each site that paints the art must paint the mark in the same function.
    local skin = source:match("local function skin%(frame%).-\nend\n")
    local refresh = source:match("function W:RefreshTheme%(%).-\nend\n")
    check(skin and skin:find("paintMark(frame)", 1, true), "building the window paints the mark")
    check(refresh and refresh:find("paintMark(W.frame)", 1, true), "a theme swap repaints the mark")
    local _, artSites = source:gsub("paintCropped%([%w%.]+artLayer, ART_PATH, ART_PATH_ALT%)", "")
    eq(artSites, 2, "the art is painted only at the two sites that also paint the mark")

    if helper and body and paths.MARK_PATH then
        local chunk = assert(loadstring(
            "local ns, MARK_PATH, MARK_PATH_ALT, ART_CROP = ...\n" .. helper .. body .. "return paintMark\n"))
        local crop = { 0.1, 0.9, 0.2, 0.8 }

        local function Run(isForever, alt, loads)
            local ns = { IS_FOREVER = isForever, UsesAltTheme = function() return alt end }
            local paintMark = chunk(ns, paths.MARK_PATH, paths.MARK_PATH_ALT, crop)
            local created = 0
            local frame = {}
            function frame:CreateTexture(_, layer, _, sublevel)
                created = created + 1
                local tex = { layer = layer, sublevel = sublevel, shown = false }
                function tex:SetAllPoints() self.allPoints = true end
                function tex:SetTexture(path) self.path = path end
                function tex:GetTexture() return loads and self.path or nil end
                function tex:SetTexCoord(...) self.crop = { ... } end
                function tex:Show() self.shown = true end
                function tex:Hide() self.shown = false end
                return tex
            end
            paintMark(frame)
            return frame, paintMark, function() return created end
        end

        local retail, _, retailCreated = Run(nil, false, true)
        eq(retailCreated(), 0, "retail creates no mark layer")
        eq(retail.markLayer, nil, "retail keeps no mark layer")

        local forever, paint, foreverCreated = Run(true, false, true)
        eq(foreverCreated(), 1, "Forever creates one mark layer")
        eq(forever.markLayer.path, paths.MARK_PATH, "the default look takes the default mark")
        eq(forever.markLayer.layer, "BACKGROUND", "the mark stays in the background layer")
        eq(forever.markLayer.sublevel, 1, "the mark sits over the art's sublevel")
        check(forever.markLayer.allPoints, "the mark fills the frame as the art does")
        eq(forever.markLayer.crop and forever.markLayer.crop[1], crop[1], "the mark takes the art's crop")
        eq(forever.markLayer.crop and forever.markLayer.crop[4], crop[4], "the mark takes all four crop edges")
        check(forever.markLayer.shown, "a loaded mark shows")

        paint(forever)
        eq(foreverCreated(), 1, "a repaint reuses the layer")

        local alt = Run(true, true, true)
        eq(alt.markLayer.path, paths.MARK_PATH_ALT, "the alternate look takes the alternate mark")

        local failed = Run(true, false, false)
        check(not failed.markLayer.shown, "a mark that fails to load stays hidden")
    end
end

-- The real Theme.lua on each client, against a minimal host.
do
    local function Load(isForever)
        local frames, overlay = {}, nil
        local active = "KitnUI"
        local onShow
        _G.CreateFrame = function(_, _, parent)
            local frame = { parent = parent, shown = true, events = {}, scripts = {}, textures = {} }
            function frame:RegisterEvent(event) self.events[event] = true end
            function frame:UnregisterEvent(event) self.events[event] = nil end
            function frame:SetScript(script, handler) self.scripts[script] = handler end
            function frame:SetAllPoints() end
            function frame:SetFrameLevel() end
            function frame:EnableMouse() end
            function frame:Show() self.shown = true end
            function frame:Hide() self.shown = false end
            function frame:CreateTexture(_, layer, _, sublevel)
                local tex = { layer = layer, sublevel = sublevel or 0 }
                function tex:SetAllPoints() end
                function tex:SetTexture(path) self.path = path end
                self.textures[#self.textures + 1] = tex
                return tex
            end
            frames[#frames + 1] = frame
            if parent then overlay = frame end
            return frame
        end
        _G.hooksecurefunc = function(tbl, key, hook)
            local original = tbl[key]
            tbl[key] = function(...)
                original(...)
                hook(...)
            end
        end
        _G.EllesmereUI = {
            THEME_PRESETS = {},
            THEME_ORDER = { "EllesmereUI" },
            _mainFrame = { GetFrameLevel = function() return 20 end },
            GetActiveTheme = function() return active end,
            SetActiveTheme = function(theme) active = theme end,
            RegisterOnShow = function(_, fn) onShow = fn end,
        }
        local ns = { EUI_INERT = false, IS_FOREVER = isForever }
        assert(loadfile("KitnUI_EUI/Theme.lua"))("KitnUI_EUI", ns)
        frames[1].scripts.OnEvent(frames[1], "PLAYER_LOGIN")
        return {
            overlay = function() return overlay end,
            show = function() onShow() end,
            setActive = function(theme) active = theme end,
            apply = ns.ApplyEUIOptionsTheme,
            pick = function(theme) _G.EllesmereUI.SetActiveTheme(theme) end,
        }
    end

    local retail = Load(nil)
    local panel = retail.overlay()
    check(panel ~= nil, "retail builds the overlay")
    if panel then
        eq(#panel.textures, 1, "retail draws the artwork alone")
        eq(panel.textures[1].path, "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\KitnUI-EUI-Options.png",
            "retail keeps the retail artwork")
    end

    local forever = Load(true)
    panel = forever.overlay()
    check(panel ~= nil, "Forever builds the overlay")
    if panel then
        eq(#panel.textures, 2, "Forever draws the artwork and the mark")
        local art, mark = panel.textures[1], panel.textures[2]
        eq(art.path, "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\KitnUI-EUI-Options.png",
            "Forever keeps the retail artwork beneath")
        eq(mark.path, "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\KitnUI-EUI-Options-Forever.png",
            "the default theme takes its mark")
        check(mark.sublevel > art.sublevel, "the mark draws above the artwork")

        forever.setActive("KitnUI Rasta")
        forever.show()
        eq(art.path, "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\KitnUI-EUI-Options-Rasta.png",
            "a theme swap changes the artwork")
        eq(mark.path, "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\KitnUI-EUI-Options-Rasta-Forever.png",
            "a theme swap changes the mark with it")

        -- The dropdown reaches the art through the hook on the host's setter.
        forever.pick("KitnUI")
        eq(mark.path, "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\KitnUI-EUI-Options-Forever.png",
            "picking a theme in the dropdown changes the mark")

        -- The installer reaches it through the bridge.
        eq(forever.apply("KitnUI Rasta"), true, "the installer can apply a theme")
        eq(mark.path, "Interface\\AddOns\\KitnUI_EUI\\Media\\Backgrounds\\KitnUI-EUI-Options-Rasta-Forever.png",
            "a theme applied by the installer changes the mark")

        forever.setActive("EllesmereUI")
        forever.show()
        check(not panel.shown, "a host theme hides the artwork and the mark together")
    end
end

if failures > 0 then
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
print("ok  " .. checks .. " checks passed")
