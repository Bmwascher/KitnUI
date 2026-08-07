-- ╔══════════════════════════════════════════════════════════════╗
-- ║  EUITab/Nameplates.lua                                       ║
-- ║  Purpose: KitnUI's own target arrows, replacing EllesmereUI's ║
-- ║           while switched on.                                 ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- This page does NOT clear the bar the other pages clear. EllesmereUI's own
-- target arrows already have 16 styles, a scale, a colour picker, class colour,
-- and automatic dodging of auras, the cast icon, the raid marker and the
-- classification icon. Ours has one style and a manual gap.
--
-- Kitn was shown that and chose to build it anyway, wanting KitnUI's own art and
-- the geometry controls of an old Plater indicator. It is off by default, so a
-- user who does nothing keeps EllesmereUI's arrows exactly as they are.

local _, ns = ... ---@type string, KitnUINS

local NAMEPLATES = "EllesmereUINameplates"
local ARROW_TEX = "Interface\\AddOns\\KitnUI\\Media\\Nameplates\\DoubleArrow.tga"

-- EllesmereUI's own default, read here so a texture taller or shorter than the
-- bar still centres when the profile has never set one.
local DEFAULT_BAR_H = 17

-- The art is 64x64 but the chevron only occupies part of it. Measured from the
-- file's alpha channel on 2026-08-07: opaque pixels run x 12..52 and y 4..59, so
-- 41x56 of 64x64, leaving 12 transparent columns on the left and 11 on the right.
--
-- Uncropped, that padding is why a Side Gap of 0 did not touch the plate and why
-- the arrows looked soft: about a third of the width the user set was invisible,
-- and the visible chevron was drawn from far fewer source pixels than its box
-- suggested. Cropping to the measured box makes the Width slider mean the width
-- of the ARROW rather than the width of its box.
local CROP_L, CROP_R = 12 / 64, 53 / 64
local CROP_T, CROP_B = 4 / 64, 60 / 64

-- Plater's indicator used 15x12 with its own art. This asset's visible chevron is
-- 41x56, so it is TALLER than it is wide and 15x12 squashes it. These defaults
-- keep the native 0.73 ratio at a comparable size. Existing saved values are
-- untouched; this only affects a profile that has never set them.
local DEFAULTS = {
    npArrowW         = 16,
    npArrowH         = 22,
    npArrowGap       = 14,
    npArrowY         = 0,
    npArrowGlow      = true,
    npArrowCastNudge = true,
    npArrowCastKick  = 8,
}

-- KITN_PINK is POSITIONAL, because SetColorTexture takes three arguments. The
-- setting is KEYED, because the draw code reads .r and because that is the shape
-- EllesmereUI uses for every colour in its profiles. Copying without converting
-- gives a table whose .r is nil, and SetVertexColor(nil, nil, nil) errors on the
-- first draw, which luacheck cannot see.
--
-- A fresh table every call: the colour is saved into KitnUIDB, so handing out the
-- shared constant would alias it into SavedVariables and let the picker edit the
-- installer's own chrome.
local function DefaultArrowColor()
    local p = ns.KITN_PINK
    if type(p) ~= "table" then return { r = 1, g = 0, b = 0.549 } end
    return { r = p[1], g = p[2], b = p[3] }
end

function ns.NameplateArrowsEnabled()
    local s = ns.EUISettings()
    return s and s.npArrows and true or false
end

-- Read-through rather than seeded: defaulting into the saved table would write a
-- block into every profile a user merely opens the page on.
local function Cfg()
    local s = ns.EUISettings()
    if not s then return nil end
    local t = {}
    for key, fallback in pairs(DEFAULTS) do
        local cur = s[key]
        if cur == nil then t[key] = fallback else t[key] = cur end
    end
    local c = s.npArrowColor
    if type(c) == "table" and c.r and c.g and c.b then
        t.color = c
    else
        t.color = DefaultArrowColor()
    end
    return t
end

---------------------------------------------------------------------------------
-- Reaching EllesmereUI's plates
---------------------------------------------------------------------------------

-- C_NamePlate.GetNamePlateForUnit returns BLIZZARD's nameplate, which has no
-- .health, and writing our own keys onto it would taint it (EllesmereUI says so
-- itself in EllesmereUINameplates.lua:91-93). EllesmereUI's plate is its own
-- pooled frame, reachable only through the namespace it exports.
local function CanDraw()
    local NS = _G.EllesmereNameplates_NS
    return type(NS) == "table" and type(NS.plates) == "table"
end

-- Prefer EllesmereUI's own cache and fall back to the scan: the cache is cleared
-- when a plate is released, so it can legitimately be nil for a plate we still
-- want, and it can hold a plate that has since been recycled to another unit.
local function TargetPlate()
    local NS = _G.EllesmereNameplates_NS
    if type(NS) ~= "table" then return nil end

    local cached = NS._cachedTargetPlate
    if cached and cached.health and cached.unit and UnitIsUnit(cached.unit, "target") then
        return cached
    end

    local plates = NS.plates
    if type(plates) ~= "table" then return nil end
    for _, plate in pairs(plates) do
        if plate and plate.unit and plate.health and UnitIsUnit(plate.unit, "target") then
            return plate
        end
    end
    return nil
end

local function HealthBarHeight()
    local prof = ns.EUIProfile(NAMEPLATES)
    return (prof and prof.healthBarHeight) or DEFAULT_BAR_H
end

---------------------------------------------------------------------------------
-- Suppressing EllesmereUI's own arrows
---------------------------------------------------------------------------------

-- showTargetArrows is a plain boolean with no companion fields, so unlike the
-- Gameplay page's barVisibility the ordinary trio is exactly right here.
local function ApplyEUIArrowSuppression(on)
    local prof = ns.EUIProfile(NAMEPLATES)
    if not prof then return end

    -- Peek on the off path: EUISnap would seed a record in every profile of a
    -- user who never turned the arrows on.
    local saved = on and ns.EUISnap("nameplates", "euiArrows")
                     or ns.EUIPeekSnap("nameplates", "euiArrows")
    if not saved then return end

    if on then
        ns.EUIOverride(prof, saved, "showTargetArrows", false)
    else
        ns.EUIRestore(prof, saved, "showTargetArrows")
    end

    if _G._ENP_RefreshAllSettings then pcall(_G._ENP_RefreshAllSettings) end
end

---------------------------------------------------------------------------------
-- The arrows
---------------------------------------------------------------------------------

-- The plate we last showed arrows on. Plates are pooled and recycled between
-- units, so the update has to hide the previous one rather than assume its frame
-- went away.
local shownPlate

local function EnsureArrows(plate)
    if plate._kitnArrowL then return true end

    local parent = plate.health
    if not parent then return false end

    -- On 12.1 the aura containers carry UntrustedLayoutScriptExecution and only
    -- aspect-bearing objects may anchor to them. An aspect cannot be gained
    -- later, so a region has to be BORN inside the template holder. We only ever
    -- anchor to the health bar, so this is insurance rather than a present need,
    -- but it is insurance that cannot be retrofitted.
    if EllesmereUI.IS_121 then
        local ok, holder = pcall(CreateFrame, "Frame", nil, plate.health,
            "DisableUntrustedLayoutScriptsTemplate")
        if ok and holder then
            holder:SetAllPoints(plate.health)
            holder:SetFrameLevel(plate.health:GetFrameLevel())
            plate._kitnArrowHost = holder
            parent = holder
        end
    end

    -- NO anchor and NO size at creation. EllesmereUI's own comment is explicit
    -- that this is the safe creation state, because an unanchored hidden texture
    -- has no rect and draws nothing. The first position pass gives them both.
    plate._kitnArrowL = parent:CreateTexture(nil, "OVERLAY")
    plate._kitnArrowL:SetTexture(ARROW_TEX)
    plate._kitnArrowL:Hide()

    plate._kitnArrowR = parent:CreateTexture(nil, "OVERLAY")
    plate._kitnArrowR:SetTexture(ARROW_TEX)
    plate._kitnArrowR:Hide()

    -- Two jobs in one call. The crop trims the transparent padding measured off
    -- the file, so the Width slider sizes the chevron and not its empty box. The
    -- right arrow additionally SWAPS its left and right coordinates, mirroring it
    -- horizontally so both point INTO the plate: >> plate <<
    --
    -- SetTexCoord, not SetRotation(pi): a 180 degree rotation mirrors VERTICALLY
    -- too, which is invisible on a symmetric chevron and wrong on anything else.
    plate._kitnArrowL:SetTexCoord(CROP_L, CROP_R, CROP_T, CROP_B)
    plate._kitnArrowR:SetTexCoord(CROP_R, CROP_L, CROP_T, CROP_B)

    return true
end

local function TargetIsCasting()
    if not UnitExists("target") then return false end
    if not (UnitCastingInfo and UnitChannelInfo) then return false end
    return (UnitCastingInfo("target") or UnitChannelInfo("target")) and true or false
end

-- Only the LEFT arrow takes the cast nudge, matching the base game's own target
-- marker: the cast bar and its spell icon sit on the left.
local function CurrentGaps(t)
    local base = t.npArrowGap
    local left = base
    if t.npArrowCastNudge and TargetIsCasting() then
        left = base + t.npArrowCastKick
    end
    return left, base
end

-- Fully anchored TOP+BOTTOM with a separate width, never single-point plus size:
-- inside 12.1's aspect-restricted plate subtree a single-point rect renders
-- displaced, and EllesmereUI's own arrows are positioned this way for that reason.
--
-- The rendered height is barH + 2*dy and the centre sits at the bar's centre plus
-- npArrowY whatever dy is, because the two offsets are symmetric. So a wrong barH
-- does not move the arrow, it makes the height slider deliver the wrong height.
local function PositionArrows(plate, t, gapL, gapR)
    local PP = EllesmereUI.PP
    if not (PP and PP.Point and PP.Width) then return end

    -- Rounded to whole pixels. A half-pixel offset lands the texture between
    -- screen pixels and the arrow renders soft, which is what an odd difference
    -- between arrow height and bar height produces every time. EllesmereUI rounds
    -- its own arrow geometry the same way.
    local dy  =  math.floor((t.npArrowH - HealthBarHeight()) / 2 + 0.5)
    local lox = -math.floor(gapL + t.npArrowW / 2 + 0.5)
    local rox =  math.floor(gapR + t.npArrowW / 2 + 0.5)
    local y = t.npArrowY

    plate._kitnArrowL:ClearAllPoints()
    plate._kitnArrowR:ClearAllPoints()
    PP.Point(plate._kitnArrowL, "TOP",    plate.health, "TOPLEFT",     lox,  dy + y)
    PP.Point(plate._kitnArrowL, "BOTTOM", plate.health, "BOTTOMLEFT",  lox, -dy + y)
    PP.Width(plate._kitnArrowL, t.npArrowW)
    PP.Point(plate._kitnArrowR, "TOP",    plate.health, "TOPRIGHT",    rox,  dy + y)
    PP.Point(plate._kitnArrowR, "BOTTOM", plate.health, "BOTTOMRIGHT", rox, -dy + y)
    PP.Width(plate._kitnArrowR, t.npArrowW)

    plate._kitnGapL, plate._kitnGapR = gapL, gapR
end

local function StyleArrows(plate, t)
    local blend = t.npArrowGlow and "ADD" or "BLEND"
    local c = t.color
    plate._kitnArrowL:SetBlendMode(blend)
    plate._kitnArrowR:SetBlendMode(blend)
    plate._kitnArrowL:SetVertexColor(c.r, c.g, c.b)
    plate._kitnArrowR:SetVertexColor(c.r, c.g, c.b)
end

local function HideArrowsOn(plate)
    if not (plate and plate._kitnArrowL) then return end
    plate._kitnArrowL:Hide()
    plate._kitnArrowR:Hide()
end

local function HideAllArrows()
    HideArrowsOn(shownPlate)
    shownPlate = nil
end

local function UpdateArrows()
    local t = Cfg()
    if not (t and ns.NameplateArrowsEnabled()) then
        HideAllArrows()
        return
    end

    -- Hostile only, checked before the plate lookup so the common no-target case
    -- costs nothing.
    if not (UnitExists("target") and UnitCanAttack("player", "target")) then
        HideAllArrows()
        return
    end

    local plate = TargetPlate()
    if not plate then
        HideAllArrows()
        return
    end

    if plate ~= shownPlate then
        HideArrowsOn(shownPlate)
        shownPlate = plate
    end

    if not EnsureArrows(plate) then
        shownPlate = nil
        return
    end

    StyleArrows(plate, t)
    -- Never early-out on a full update: this plate may never have been anchored.
    PositionArrows(plate, t, CurrentGaps(t))
    plate._kitnArrowL:Show()
    plate._kitnArrowR:Show()
end

-- Cast events change only the GAP, so they take the cheap path. The early-out is
-- PER PLATE, not a file-local: with per-plate arrows a shared cache would skip
-- the anchor pass after a target switch between two plates whose gaps match,
-- leaving the new plate's arrows unanchored, and an unanchored texture draws
-- nothing.
local function RefreshArrowGap()
    local plate = shownPlate
    if not (plate and plate._kitnArrowL and plate._kitnArrowL:IsShown()) then return end
    local t = Cfg()
    if not t then return end
    local gapL, gapR = CurrentGaps(t)
    if gapL == plate._kitnGapL and gapR == plate._kitnGapR then return end
    PositionArrows(plate, t, gapL, gapR)
end

---------------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------------

-- Called by BOTH the toggle and the re-apply. `announce` is true only for the
-- toggle: the re-apply fires at login and on profile changes with nobody there to
-- read a message.
local function ApplyArrows(announce)
    if not CanDraw() then
        -- Hand EllesmereUI's arrows BACK rather than merely declining to
        -- re-assert. Suppressing them while drawing nothing is the worst state
        -- this page can reach, and the realistic way in is an EllesmereUI update
        -- plus a reload, which lands in the re-apply and not in the toggle.
        --
        -- The stored switch state is deliberately left alone: the snapshot's
        -- existence, not the switch, is what records that we are holding a key
        -- down, so if a later EllesmereUI restores the export the arrows come
        -- back on their own.
        ApplyEUIArrowSuppression(false)
        HideAllArrows()
        if announce then
            print(ns.title .. ": this version of EllesmereUI does not expose its nameplates, so KitnUI's arrows cannot be drawn. EllesmereUI's own arrows have been restored.")
        end
        return
    end

    ApplyEUIArrowSuppression(ns.NameplateArrowsEnabled())
    UpdateArrows()
end

ns.EUIRegisterReapply(function() ApplyArrows(false) end)

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------

-- Unit-filtered to "target": unfiltered these fire for every unit in combat,
-- which is a real cost on a busy pull.
local CAST_EVENTS = {
    UNIT_SPELLCAST_START         = true,
    UNIT_SPELLCAST_STOP          = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP  = true,
    UNIT_SPELLCAST_INTERRUPTED   = true,
    UNIT_SPELLCAST_FAILED        = true,
    UNIT_SPELLCAST_SUCCEEDED     = true,
}

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
ev:RegisterUnitEvent("UNIT_FACTION", "target")
for e in pairs(CAST_EVENTS) do ev:RegisterUnitEvent(e, "target") end

ev:SetScript("OnEvent", function(_, event, unit)
    if CAST_EVENTS[event] then
        RefreshArrowGap()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Plates are rebuilt on a zone change, and EllesmereUINameplates has
        -- certainly loaded by now.
        ApplyArrows(false)
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        if unit and not UnitIsUnit(unit, "target") then return end
    end
    UpdateArrows()
end)

---------------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------------

local function SetNum(key, v)
    local s = ns.EUISettings()
    if not s then return end
    s[key] = v
    UpdateArrows()
end

-- Not `t and t[key] or DEFAULTS[key]`: the house rule bars that shape, and here
-- it would also be wrong the day a slider's value can legitimately be false.
local function GetNum(key)
    local t = Cfg()
    if not t then return DEFAULTS[key] end
    return t[key]
end

local function GetFlag(key)
    local t = Cfg()
    if not t then return DEFAULTS[key] end
    return t[key] and true or false
end

ns.EUIPages["Nameplates"] = function(parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, row, h

    _, h = W:SectionHeader(parent, "TARGET ARROW", y);                             y = y - h

    -- Two controls per row, matching the density of every other page in this
    -- panel. Nine full-width rows made this page twice as tall as EllesmereUI's
    -- own and read as a list rather than a settings group.
    row, h = W:DualRow(parent, y,
        { type = "toggle", text = "KitnUI Target Arrows",
          tooltip = "Draws KitnUI's own chevrons around your target's nameplate. EllesmereUI's own target arrows are switched off while this is on, and given back when you switch it off. Theirs have 16 styles and dodge auras automatically; these do not.",
          getValue = function() return ns.NameplateArrowsEnabled() end,
          setValue = function(v)
              local s = ns.EUISettings()
              if s then s.npArrows = v and true or nil end
              ApplyArrows(true)
          end },
        { type = "toggle", text = "Additive Glow",
          tooltip = "Makes the arrows glow rather than sit flat. Turn it off if they wash out against a bright background.",
          getValue = function() return GetFlag("npArrowGlow") end,
          setValue = function(v) SetNum("npArrowGlow", v and true or false) end }
    );                                                                             y = y - h

    -- The swatch rides the enable toggle rather than taking a row of its own:
    -- DualRow has no colour entry type, and a lone swatch row reads as clutter.
    -- Anchored to the LEFT of that half's control, which is where EllesmereUI puts
    -- the swatch for its own target arrow colour.
    local leftRgn = row and row._leftRegion
    if leftRgn and leftRgn._control and EllesmereUI.BuildColorSwatch and EllesmereUI.PP then
        local swatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
            function()
                local t = Cfg()
                local c = DefaultArrowColor()
                if t and t.color then c = t.color end
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                local s = ns.EUISettings()
                if s then s.npArrowColor = { r = r, g = g, b = b } end
                UpdateArrows()
            end, nil, 20)
        if swatch then
            EllesmereUI.PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -8, 0)
        end
    end

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Arrow Width", min = 4, max = 64, step = 1,
          tooltip = "How wide each chevron is. Width and height are separate, so the arrows do not have to be square.",
          getValue = function() return GetNum("npArrowW") end,
          setValue = function(v) SetNum("npArrowW", v) end },
        { type = "slider", text = "Arrow Height", min = 4, max = 64, step = 1,
          tooltip = "How tall each chevron is. The art is taller than it is wide, so a matching shape is roughly 3 tall for every 2 wide.",
          getValue = function() return GetNum("npArrowH") end,
          setValue = function(v) SetNum("npArrowH", v) end }
    );                                                                             y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Side Gap", min = -30, max = 60, step = 1,
          tooltip = "How far the arrows sit from the nameplate. 0 puts them against its edge, and negative values move them in over it.",
          getValue = function() return GetNum("npArrowGap") end,
          setValue = function(v) SetNum("npArrowGap", v) end },
        { type = "slider", text = "Vertical Offset", min = -30, max = 30, step = 1,
          tooltip = "Moves both arrows up or down without changing their height.",
          getValue = function() return GetNum("npArrowY") end,
          setValue = function(v) SetNum("npArrowY", v) end }
    );                                                                             y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Move Aside While Casting",
          tooltip = "Steps the LEFT arrow out of the cast bar's way while your target is casting. The right arrow stays put.",
          getValue = function() return GetFlag("npArrowCastNudge") end,
          setValue = function(v) SetNum("npArrowCastNudge", v and true or false) end },
        { type = "slider", text = "Cast Nudge", min = 0, max = 30, step = 1,
          tooltip = "How far the left arrow moves while your target is casting.",
          getValue = function() return GetNum("npArrowCastKick") end,
          setValue = function(v) SetNum("npArrowCastKick", v) end }
    );                                                                             y = y - h

    return math.abs(y)
end
