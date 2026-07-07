local _, ns = ...

------------------------------------------------------------
-- Extras: optional, repeatable QoL actions used by the Extras
-- installer page. All idempotent and defensively guarded.
------------------------------------------------------------

-- Hide the minimap buttons of companion addons (extracted from FinishInstallation
-- so the Extras "Clean Icons" button and Finish share one implementation).
function ns.CleanMinimapIcons()
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBIcon then
        for _, broker in ipairs({ "BigWigs", "Plater", "NSRT" }) do
            if LDBIcon:IsRegistered(broker) then LDBIcon:Hide(broker) end
        end
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded("BigWigs") and type(BigWigsIconDB) == "table" then
        BigWigsIconDB.hide = true
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded("Plater") and PlaterDBChr and PlaterDBChr.minimap then
        PlaterDBChr.minimap.hide = true
    end
end

-- Run KitnEssentials' system optimization. Returns false if KitnEssentials isn't
-- present; KE prints its own summary and owns its own reload prompt.
function ns.RunOptimize()
    if not (KitnEssentials and KitnEssentials.GetModule) then return false end
    local opt = KitnEssentials:GetModule("Optimize", true)
    if not (opt and opt.OptimizeAll) then return false end
    opt:OptimizeAll()
    return true
end

-- Full chat reconfigure: main-frame position/size, font, timestamps, and named
-- tabs (General + Combat Log). Idempotent -- running twice yields the same state.
function ns.RunChatSetup()
    local cf = _G.ChatFrame1
    if not cf then return false end

    -- Position + size the main chat frame (bottom-left, standard KitnUI spot).
    cf:ClearAllPoints()
    cf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 22)
    if cf.SetSize then cf:SetSize(400, 170) end
    if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(cf) end

    -- Font + size via the chat frame's font object.
    local fo = cf.GetFontObject and cf:GetFontObject()
    if fo and fo.SetFont then
        fo:SetFont("Interface\\AddOns\\KitnUI\\Media\\Fonts\\Expressway.TTF", 13, "")
    end

    -- Chat timestamps (pcall-guarded in case the CVar name shifts across builds).
    if SetCVar then pcall(SetCVar, "showTimestamps", "%H:%M ") end

    -- Named tabs: General (main) + Combat Log (ChatFrame2).
    if FCF_SetWindowName then
        FCF_SetWindowName(cf, "General")
        if _G.ChatFrame2 then FCF_SetWindowName(_G.ChatFrame2, "Combat Log") end
    end

    return true
end
