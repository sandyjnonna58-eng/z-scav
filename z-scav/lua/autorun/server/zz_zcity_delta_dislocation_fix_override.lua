if CLIENT then return end

local function EnsureDislocationMinigameLoaded()
    if hg and hg.MedicalMinigame and hg.MedicalMinigame.StartDislocationMinigame then return true end
    if file.Exists("zcity_delta/medical_minigame/sv_logic.lua", "LUA") then
        local ok = pcall(include, "zcity_delta/medical_minigame/sv_logic.lua")
        if ok and hg and hg.MedicalMinigame and hg.MedicalMinigame.StartDislocationMinigame then
            return true
        end
    end
    return false
end

concommand.Add("hg_fixdislocation", function(ply, _, args)
    if not IsValid(ply) or not ply:Alive() then return end
    if not ply.organism or ply.organism.otrub then return end

    local org = ply.organism
    if not org.canmove or not org.canmovehead or (org.pain or 0) > 60 then return end
    if (ply.tried_fixing_limb or 0) > CurTime() then return end

    if not EnsureDislocationMinigameLoaded() then return end

    local group = tonumber(args and args[1] or nil)
    if group ~= 1 and group ~= 2 and group ~= 3 then return end

    local useTarget = tonumber(args and args[2] or 0) == 1
    local targetEnt = ply

    if useTarget and hg and hg.eyeTrace then
        targetEnt = hg.eyeTrace(ply).Entity
    end

    if IsValid(targetEnt) and targetEnt:IsRagdoll() and hg and hg.RagdollOwner then
        targetEnt = hg.RagdollOwner(targetEnt) or targetEnt
    end

    if not IsValid(targetEnt) then return end

    if hg.MedicalMinigame.StartDislocationMinigame(ply, targetEnt, group) then
        ply.tried_fixing_limb = CurTime() + (org.pain or 0) / 30
    end
end)
