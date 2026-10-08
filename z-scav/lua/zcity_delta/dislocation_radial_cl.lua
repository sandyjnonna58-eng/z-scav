if SERVER then return end

-- Z-SCAV: пункты аддона в Q-меню убраны (всё это есть в меню здоровья на N)
local _ZSCAV_offRadialDisloc = (function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or not ply.organism or ply.organism.otrub then return end
    if not hg or not hg.radialOptions or not hg.eyeTrace then return end

    local org = ply.organism
    if (org.pain or 0) > 60 then return end
    if (ply.tried_fixing_limb or 0) > CurTime() then return end

    local function AddOption(label, group, useTarget)
        hg.radialOptions[#hg.radialOptions + 1] = {
            function()
                ply.tried_fixing_limb = CurTime() + 0.5
                if useTarget then
                    RunConsoleCommand("hg_med_dislocation", group, "target")
                else
                    RunConsoleCommand("hg_med_dislocation", group)
                end
            end,
            label
        }
    end

    local function HasDislocation(ent, group)
        if not IsValid(ent) or not ent.organism then return false end
        local eorg = ent.organism
        if group == 1 then return eorg.llegdislocation or eorg.rlegdislocation end
        if group == 2 then return eorg.larmdislocation or eorg.rarmdislocation end
        if group == 3 then return eorg.jawdislocation end
        return false
    end

    local target = hg.eyeTrace(ply).Entity
    if IsValid(target) and target:IsRagdoll() and hg.RagdollOwner then
        target = hg.RagdollOwner(target) or target
    end

    if HasDislocation(ply, 1) then
        AddOption("Fix dislocation (leg)", 1, false)
    elseif IsValid(target) and target:IsPlayer() and HasDislocation(target, 1) then
        AddOption("Fix " .. target:GetPlayerName() .. "'s dislocation (leg)", 1, true)
    end

    if HasDislocation(ply, 2) then
        AddOption("Fix dislocation (arm)", 2, false)
    elseif IsValid(target) and target:IsPlayer() and HasDislocation(target, 2) then
        AddOption("Fix " .. target:GetPlayerName() .. "'s dislocation (arm)", 2, true)
    end

    if HasDislocation(ply, 3) then
        AddOption("Fix dislocation (jaw)", 3, false)
    elseif IsValid(target) and target:IsPlayer() and HasDislocation(target, 3) then
        AddOption("Fix " .. target:GetPlayerName() .. "'s dislocation (jaw)", 3, true)
    end
end)
