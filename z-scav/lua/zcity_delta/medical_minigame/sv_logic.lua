if CLIENT then return end

hg.MedicalMinigame = hg.MedicalMinigame or {}
hg.MedicalMinigame.AmputationSessions = hg.MedicalMinigame.AmputationSessions or {}
hg.MedicalMinigame.DislocationSessions = hg.MedicalMinigame.DislocationSessions or {}

local HasTrait
local GetTraitState
local GetMedicalSeverity
local GetMedicalProgressModifier

local amputationLimbNames = {
    larm = "Левая рука",
    rarm = "Правая рука",
    lleg = "Левая нога",
    rleg = "Правая нога"
}

local amputationLimbBones = {
    larm = "ValveBiped.Bip01_L_Forearm",
    rarm = "ValveBiped.Bip01_R_Forearm",
    lleg = "ValveBiped.Bip01_L_Calf",
    rleg = "ValveBiped.Bip01_R_Calf"
}

local function GetAmputationCutWoundData(target, limb)
    local boneName = amputationLimbBones[limb]
    if not IsValid(target) or not boneName then
        return vector_origin, angle_zero, boneName
    end

    local boneIndex = target:LookupBone(boneName)
    if not boneIndex then
        return vector_origin, angle_zero, boneName
    end

    local upperBoneName = target:GetBoneName(boneIndex - 1)
    local boneLength = target:BoneLength(boneIndex)
    local cutOffset = Vector(boneLength > 0 and boneLength or 5, 0, 0)

    return cutOffset, angle_zero, upperBoneName or boneName
end

local function GetDislocationLimbFromGroup(target, group)
    if not IsValid(target) or not target.organism then return end

    local org = target.organism
    group = math.Round(tonumber(group) or 0)
    if group == 1 then
        if org.llegdislocation then return "lleg" end
        if org.rlegdislocation then return "rleg" end
    elseif group == 2 then
        if org.larmdislocation then return "larm" end
        if org.rarmdislocation then return "rarm" end
    elseif group == 3 then
        if org.jawdislocation then return "jaw" end
    end
end

local function ResolveMinigameTarget(ent)
    if IsValid(ent) and ent:IsRagdoll() then
        ent = hg.RagdollOwner(ent) or ent
    end

    if IsValid(ent) and ent:IsPlayer() then
        return ent
    end
end

local function CanUseMedicalMinigameTarget(ply, target)
    if not IsValid(ply) or not ply:Alive() then return false end
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return false end
    if not target.organism then return false end
    if target ~= ply and ply:GetPos():DistToSqr(target:GetPos()) > 10000 then return false end
    return true
end

local function ApplyAmputationProgress(ply, session, progressDelta, swipeSpeed)
    local target = session.target
    local limb = session.limb
    if not CanUseMedicalMinigameTarget(ply, target) then return end
    if not amputationLimbNames[limb] or target.organism[limb .. "amputated"] then return end

    local org = target.organism
    local delta = math.max(progressDelta or 0, 0)
    if delta <= 0 then return end

    session.progress = math.Clamp((session.progress or 0) + delta, 0, 1)

    local speed = math.max(swipeSpeed or 0, 0)
    local normalizedSpeed = math.Clamp(speed / 700, 0, 1.9)
    local painScale = 0.05 + (normalizedSpeed ^ 1.45) * 1.25
    local painAmount = (0.05 + delta * 2.8) * painScale
    org.painadd = (org.painadd or 0) + painAmount

    local tooFastThreshold = 900
    if speed >= tooFastThreshold then
        local overSpeed = speed - tooFastThreshold
        org.painadd = (org.painadd or 0) + math.Clamp((overSpeed / 140) ^ 1.1, 1.5, 9)

        local dmgInfo = DamageInfo()
        local inflictor = game.GetWorld()
        if IsValid(ply) then
            local activeWeapon = ply:GetActiveWeapon()
            inflictor = IsValid(activeWeapon) and activeWeapon or ply
        end

        dmgInfo:SetAttacker(IsValid(ply) and ply or game.GetWorld())
        dmgInfo:SetInflictor(inflictor)
        dmgInfo:SetDamageType(DMG_SLASH)
        dmgInfo:SetDamage(math.Clamp(overSpeed / 700, 0.5, 3))
        target:TakeDamageInfo(dmgInfo)
    end
end

local function ApplyDislocationProgress(ply, session, progressDelta, appliedForce)
    local target = session.target
    local limb = session.limb
    if not CanUseMedicalMinigameTarget(ply, target) then return end
    if not limb or not target.organism[limb .. "dislocation"] then return end

    local delta = math.max(progressDelta or 0, 0)
    local force = math.max(appliedForce or 0, 0)
    local forceScale = math.Clamp(force, 0, 1.6)

    if delta <= 0 then
        if forceScale <= 0 then return end

        local org = target.organism
        local pushPain = 0.2 + (forceScale ^ 1.55) * 1.55
        local instantPart = pushPain * 0.9
        local slowPart = pushPain - instantPart
        org.avgpain = math.min((org.avgpain or 0) + instantPart, 150)
        org.painadd = (org.painadd or 0) + slowPart
        org.lasthit = CurTime()

        if forceScale > 0.95 then
            local extra = math.Clamp((forceScale - 0.95) * 4.2, 0.25, 2.75)
            org.avgpain = math.min((org.avgpain or 0) + extra * 0.9, 150)
            org.painadd = (org.painadd or 0) + extra * 0.1
            org.lasthit = CurTime()
        end

        return
    end

    session.progress = math.Clamp((session.progress or 0) + delta, 0, 1)

    local org = target.organism
    local painAmount = (0.05 + delta * 1.2) * (0.35 + (forceScale ^ 1.7) * 1.35)
    org.avgpain = math.min((org.avgpain or 0) + painAmount * 0.18, 150)
    org.painadd = (org.painadd or 0) + painAmount * 0.55
    org.lasthit = CurTime()

    if force > 0.95 then
        local extra = math.Clamp((force - 0.95) * 4.2, 0.25, 2.75)
        org.avgpain = math.min((org.avgpain or 0) + extra * 0.18, 150)
        org.painadd = (org.painadd or 0) + extra * 0.55
        org.lasthit = CurTime()
    end
end

local function ClearAmputationSessionsForPlayer(ply)
    hg.MedicalMinigame.AmputationSessions[ply] = nil

    for surgeon, session in pairs(hg.MedicalMinigame.AmputationSessions) do
        if session and session.target == ply then
            hg.MedicalMinigame.AmputationSessions[surgeon] = nil
        end
    end
end

local function ClearDislocationSessionsForPlayer(ply)
    hg.MedicalMinigame.DislocationSessions[ply] = nil

    for fixer, session in pairs(hg.MedicalMinigame.DislocationSessions) do
        if session and session.target == ply then
            hg.MedicalMinigame.DislocationSessions[fixer] = nil
        end
    end
end

function hg.MedicalMinigame.StartAmputationMinigame(ply, ent, limb)
    local target = ResolveMinigameTarget(ent) or ply
    if not CanUseMedicalMinigameTarget(ply, target) then return false end
    if not amputationLimbNames[limb] then return false end
    if target.organism[limb .. "amputated"] then return false end

    local existingSession = hg.MedicalMinigame.AmputationSessions[ply]
    if not existingSession or existingSession.target ~= target or existingSession.limb ~= limb then
        existingSession = {
            target = target,
            limb = limb,
            progress = 0
        }
        hg.MedicalMinigame.AmputationSessions[ply] = existingSession
    end

    net.Start("hg_medical_minigame_start")
    net.WriteString("amputation")
    net.WriteEntity(target)
    net.WriteString(limb)
    net.WriteFloat(math.Clamp(existingSession.progress or 0, 0, 1))
    net.Send(ply)

    return true
end

function hg.MedicalMinigame.StartDislocationMinigame(ply, ent, group)
    local target = ResolveMinigameTarget(ent) or ply
    if not CanUseMedicalMinigameTarget(ply, target) then return false end

    local limb = GetDislocationLimbFromGroup(target, group)
    if not limb then return false end

    local existingSession = hg.MedicalMinigame.DislocationSessions[ply]
    if not existingSession or existingSession.target ~= target or existingSession.limb ~= limb then
        existingSession = {
            target = target,
            limb = limb,
            progress = 0,
            side = math.random(0, 1) == 1 and 1 or -1
        }
        hg.MedicalMinigame.DislocationSessions[ply] = existingSession
    end

    net.Start("hg_medical_minigame_start")
    net.WriteString("dislocation")
    net.WriteEntity(target)
    net.WriteString(limb)
    net.WriteFloat(math.Clamp(existingSession.progress or 0, 0, 1))
    net.WriteInt(existingSession.side or 1, 3)
    net.Send(ply)

    return true
end

net.Receive("hg_medical_minigame_request_amputation", function(len, ply)
    local ent = net.ReadEntity()
    local limb = net.ReadString()
    hg.MedicalMinigame.StartAmputationMinigame(ply, ent, limb)
end)

net.Receive("hg_medical_minigame_cancel", function(len, ply)
    local minigameType = net.ReadString()
    if minigameType == "amputation" then
        ClearAmputationSessionsForPlayer(ply)
        return
    end

    if minigameType == "dislocation" then
        ClearDislocationSessionsForPlayer(ply)
        return
    end
end)

hook.Add("PlayerDeath", "hg_medical_minigame_clear_amputation_progress", function(ply)
    ClearAmputationSessionsForPlayer(ply)
    ClearDislocationSessionsForPlayer(ply)
end)

local function GetMedicalMinigameType(wep)
    local class = wep:GetClass()

    if class == "weapon_bandage_sh" or class == "weapon_bigbandage_sh" or class == "weapon_bruicekit" or (class == "weapon_medkit_sh" and wep.mode == 1) then
        return "bandage"
    end

    if class == "weapon_tourniquet" or (class == "weapon_medkit_sh" and wep.mode == 4) then
        return "tourniquet"
    end

    if class == "weapon_morphine" or class == "weapon_fentanyl" or (class == "weapon_medkit_sh" and wep.mode == 3) then
        return "syringe"
    end
end

local function ApplyBruiceKitProgress(wep, ply, target, progressDelta)
    local org = target.organism
    if not org then return end
    if not wep.modeValues or not wep.modeValues[1] then return end

    local requested = math.max(progressDelta or 0, 0) * 40
    if requested <= 0 then return end

    local currentAmount = math.max(tonumber(wep.modeValues[1]) or 0, 0)
    local consumed = math.min(requested, currentAmount)
    if consumed <= 0 then return end

    wep.modeValues[1] = math.max(currentAmount - consumed, 0)

    local heal = consumed / 40
    local keys = {
        "larm",
        "rarm",
        "lleg",
        "rleg",
        "pelvis",
        "spine1",
        "spine2",
        "spine3",
        "chest",
        "skull"
    }

    local bestKey = nil
    local bestVal = 0
    for i = 1, #keys do
        local key = keys[i]
        local skip = (key == "larm" and org.larmamputated)
            or (key == "rarm" and org.rarmamputated)
            or (key == "lleg" and org.llegamputated)
            or (key == "rleg" and org.rlegamputated)
        if not skip then
            local v = tonumber(org[key] or 0) or 0
            if v > bestVal then
                bestVal = v
                bestKey = key
            end
        end
    end

    if bestKey and bestVal > 0.01 then
        org[bestKey] = math.max(bestVal - heal, 0)
    end

    wep:SetNetVar("modeValues", table.Copy(wep.modeValues))
end

local function GetMinigameModeValueIndex(wep, minigameType)
    if minigameType == "tourniquet" then
        if wep:GetClass() == "weapon_medkit_sh" then
            return 4
        end

        return 1
    end

    if minigameType == "syringe" then
        if wep:GetClass() == "weapon_medkit_sh" then
            return 3
        end

        return 1
    end

    return 1
end

local function AdjustWeaponModeValue(wep, index, delta)
    if not IsValid(wep) or not wep.modeValues or not wep.modeValues[index] then return 0 end
    local oldValue = math.max(tonumber(wep.modeValues[index]) or 0, 0)
    local newValue = math.max(oldValue + (tonumber(delta) or 0), 0)
    wep.modeValues[index] = newValue
    wep:SetNetVar("modeValues", table.Copy(wep.modeValues))
    return newValue - oldValue
end

local function GetModeValueMax(wep, index)
    if not IsValid(wep) then return 0 end
    local configured = wep.modeValuesdef and wep.modeValuesdef[index]
    return math.max(tonumber(istable(configured) and configured[1] or configured) or 0, 0)
end

local function ApplyMedicalFinishEffects(ply, target, minigameType, wep)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not IsValid(target) or not target:IsPlayer() or not target.organism then return end

    local state = GetTraitState(ply)
    local now = CurTime()
    local severity, bleed, woundSeverity, arterialSeverity = GetMedicalSeverity(target)

    if HasTrait(ply, "trained") and target ~= ply and minigameType ~= "syringe" and state then
        state.trainedOpeningUntil = now + 12
    end

    if HasTrait(ply, "medic") then
        target.__zcity_delta_stabilized_until = math.max(tonumber(target.__zcity_delta_stabilized_until or 0) or 0, now + 28)
        target.organism.painadd = math.max((tonumber(target.organism.painadd) or 0) - 18, 0)
        target.organism.avgpain = math.max((tonumber(target.organism.avgpain) or 0) - 6, 0)
        target.organism.pain = math.max((tonumber(target.organism.pain) or 0) - 10, 0)
        target.organism.bleed = math.max((tonumber(target.organism.bleed) or 0) - 0.08, 0)

        if istable(target.organism.arterialwounds) then
            for _, wound in pairs(target.organism.arterialwounds) do
                if istable(wound) and isnumber(wound[1]) then
                    wound[1] = math.max(wound[1] * 0.88, 0)
                end
            end
        end
    end

    if HasTrait(ply, "optimist") then
        for _, near in ipairs(player.GetAll()) do
            if not IsValid(near) or not near:IsPlayer() or not near:Alive() then continue end
            if near:GetPos():DistToSqr(target:GetPos()) > (420 * 420) then continue end
            PushRawMental(near, 2, -4)
        end
    end

    if HasTrait(ply, "in_shape") and ply.organism and istable(ply.organism.stamina) then
        local stamina = ply.organism.stamina
        local maxStamina = math.max(tonumber(stamina.max) or 0, 1)
        stamina[1] = math.min(maxStamina, (tonumber(stamina[1]) or 0) + maxStamina * 0.18)
        if state then
            state.secondWindUntil = now + 10
        end
    end

    if HasTrait(ply, "lucky") and IsValid(wep) then
        local index = GetMinigameModeValueIndex(wep, minigameType)
        if index and math.Rand(0, 1) <= 0.22 then
            local refund = GetModeValueMax(wep, index) * 0.12
            if refund > 0 then
                AdjustWeaponModeValue(wep, index, refund)
            end
            target.organism.bleed = math.max((tonumber(target.organism.bleed) or 0) - 0.04, 0)
        end
    end

    if HasTrait(ply, "unlucky") and IsValid(wep) and math.Rand(0, 1) <= 0.18 then
        local index = GetMinigameModeValueIndex(wep, minigameType)
        if index then
            local penalty = GetModeValueMax(wep, index) * 0.08
            if penalty > 0 then
                AdjustWeaponModeValue(wep, index, -penalty)
            end
        end
        if state then
            state.unluckyFumbleUntil = now + 12
        end
    end

    if HasTrait(ply, "maniac") and state and target ~= ply and (minigameType == "amputation" or minigameType == "dislocation") then
        state.maniacRushUntil = now + 18
        PushRawMental(ply, 4, -2)
    end

    if HasTrait(ply, "gemophobia") and severity >= 18 then
        PushRawMental(ply, -3, 6)
    end

    if HasTrait(ply, "ptsd") and state and (state.ptsdPanicUntil or 0) > now then
        PushRawMental(ply, -2, 5)
    end

    if HasTrait(target, "depressed") and target ~= ply then
        target.__zcity_delta_relief_until = now + 24
        PushRawMental(target, 6, -8)
    end

    if HasTrait(target, "schizophrenia") and target ~= ply then
        target.__zcity_delta_clarity_until = now + 12
        PushRawMental(target, 2, -3)
    end

    if HasTrait(ply, "grunt") and state and (state.gruntFocusUntil or 0) > now then
        PushRawMental(ply, 1, -5)
    end
end

local function ApplySyringeProgress(wep, ply, target, progressDelta)
    local org = target.organism
    if not org then return end

    local modeValueIndex = GetMinigameModeValueIndex(wep, "syringe")
    if not wep.modeValues or not wep.modeValues[modeValueIndex] then return end

    local owner = wep:GetOwner()
    if not IsValid(owner) then return end

    local configuredValue = wep.modeValuesdef and wep.modeValuesdef[modeValueIndex]
    local maxValue = wep.HGMedicalMinigameStartValue or (istable(configuredValue) and configuredValue[1] or configuredValue) or 1
    local requestedAmount = math.max(progressDelta, 0) * math.max(tonumber(maxValue) or 0, 0)
    if requestedAmount <= 0 then return end

    local currentAmount = math.max(tonumber(wep.modeValues[modeValueIndex]) or 0, 0)
    local consumedAmount = math.min(requestedAmount, currentAmount)
    if consumedAmount <= 0 then return end

    wep.modeValues[modeValueIndex] = math.max(currentAmount - consumedAmount, 0)

    local class = wep:GetClass()
    local entOwner = IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or owner
    if class == "weapon_morphine" or class == "weapon_fentanyl" then
        org.analgesiaAdd = math.min((org.analgesiaAdd or 0) + consumedAmount, 4)

        owner.injectedinto = owner.injectedinto or {}
        owner.injectedinto[org.owner] = owner.injectedinto[org.owner] or 0
        owner.injectedinto[org.owner] = owner.injectedinto[org.owner] + consumedAmount

        if owner.injectedinto[org.owner] > 1 then
            local dmgInfo = DamageInfo()
            dmgInfo:SetAttacker(owner)

            local overdoseMul = class == "weapon_fentanyl" and (zb and zb.MaximumHarm or 10) or (zb and zb.MaximumHarm or 1)
            local character = (hg and hg.GetCurrentCharacter) and hg.GetCurrentCharacter(org.owner) or org.owner
            hook.Run("HomigradDamage", org.owner, dmgInfo, HITGROUP_RIGHTARM, character, consumedAmount * overdoseMul)
        end

        entOwner:EmitSound("pshiksnd")
    elseif class == "weapon_medkit_sh" and wep.mode == 3 then
        local efficiency = owner.Profession == "doctor" and 0.5 or 1
        local internalBleed = math.max((org.internalBleed or 0) - (org.internalBleedHeal or 0), 0)
        local healMul = HasTrait(ply, "medic") and 1.5 or 1
        local healAmount = math.min(internalBleed, (consumedAmount / efficiency) * healMul)

        org.internalBleedHeal = (org.internalBleedHeal or 0) + healAmount
        entOwner:EmitSound("snds_jack_gmod/ez_medical/" .. math.random(16, 18) .. ".wav", 60, math.random(95, 105))
    end

    if wep.poisoned2 then
        org.poison4 = CurTime()
        wep.poisoned2 = nil
    end

    wep:SetNetVar("modeValues", table.Copy(wep.modeValues))
end

-- Incremental healing based on minigame progress
net.Receive("hg_medical_minigame_progress", function(len, ply)
    local progressDelta = net.ReadFloat()
    local wep = ply:GetActiveWeapon()
    local minigameType = IsValid(wep) and GetMedicalMinigameType(wep) or nil

    if minigameType then
        if minigameType == "bandage" and wep:GetClass() == "weapon_medkit_sh" and wep.mode ~= 1 then return end
        if minigameType == "syringe" and wep:GetClass() == "weapon_medkit_sh" and wep.mode ~= 3 then return end

        local target = wep.healbuddy or ply
        if not IsValid(target) then return end
        if target ~= ply and ply:GetPos():DistToSqr(target:GetPos()) > 10000 then return end

        local org = target.organism
        if not org then return end

        if IsValid(target) and target:IsPlayer() and GetConVar("zcity_delta_mental_enabled") and GetConVar("zcity_delta_mental_enabled"):GetBool() then
            target.__zcity_delta_mental_last_treated = CurTime()
        end

        progressDelta = tonumber(progressDelta) or 0

        progressDelta = GetMedicalProgressModifier(ply, target, minigameType, progressDelta)

        if minigameType == "syringe" then
            ApplySyringeProgress(wep, ply, target, progressDelta)
            return
        end

        if minigameType == "bandage" and wep:GetClass() == "weapon_bruicekit" then
            ApplyBruiceKitProgress(wep, ply, target, progressDelta)
            return
        end

        local healAmount = 55 * progressDelta
        local modeValueIndex = GetMinigameModeValueIndex(wep, "bandage")
        if wep.modeValues and wep.modeValues[modeValueIndex] then
            if #org.wounds > 0 then
                table.sort(org.wounds, function(a, b) return a[1] > b[1] end)

                local woundSize = org.wounds[1][1]
                local healed = math.min(woundSize, healAmount)

                org.wounds[1][1] = org.wounds[1][1] - healed
                org.bleed = math.max(org.bleed - healed, 0)
                wep.modeValues[modeValueIndex] = math.max(wep.modeValues[modeValueIndex] - (healed * 0.6), 0)
                wep:SetNetVar("modeValues", table.Copy(wep.modeValues))
                ply:SetNetVar("wounds", org.wounds)
            else
                local attemptedUse = healAmount * 0.6
                wep.modeValues[modeValueIndex] = math.max(wep.modeValues[modeValueIndex] - attemptedUse, 0)
                wep:SetNetVar("modeValues", table.Copy(wep.modeValues))
            end
        end

        return
    end

    local dislocationSession = hg.MedicalMinigame.DislocationSessions[ply]
    if dislocationSession then
        local appliedForce = net.ReadFloat()
        local target = dislocationSession.target
        local limb = dislocationSession.limb

        if not CanUseMedicalMinigameTarget(ply, target) or not limb or not target.organism[limb .. "dislocation"] then
            hg.MedicalMinigame.DislocationSessions[ply] = nil
            return
        end

        ApplyDislocationProgress(ply, dislocationSession, progressDelta, appliedForce)
        return
    end

    local amputationSession = hg.MedicalMinigame.AmputationSessions[ply]
    if amputationSession then
        local swipeSpeed = net.ReadFloat()
        local target = amputationSession.target
        local limb = amputationSession.limb

        if not CanUseMedicalMinigameTarget(ply, target) or not amputationLimbNames[limb] or target.organism[limb .. "amputated"] then
            hg.MedicalMinigame.AmputationSessions[ply] = nil
            return
        end

        ApplyAmputationProgress(ply, amputationSession, progressDelta, swipeSpeed)
    end
end)

net.Receive("hg_medical_minigame_finish", function(len, ply)
    local requestedType = net.ReadString()
    local reportedProgress = math.Clamp(net.ReadFloat() or 0, 0, 1)

    if requestedType == "amputation" then
        local amputationSession = hg.MedicalMinigame.AmputationSessions[ply]
        if not amputationSession then return end

        local target = amputationSession.target
        local limb = amputationSession.limb
        if not CanUseMedicalMinigameTarget(ply, target) or not amputationLimbNames[limb] then return end
        if target.organism[limb .. "amputated"] then
            hg.MedicalMinigame.AmputationSessions[ply] = nil
            return
        end

        amputationSession.progress = math.max(amputationSession.progress or 0, reportedProgress)
        if (amputationSession.progress or 0) < 0.999 then return end

        hg.MedicalMinigame.AmputationSessions[ply] = nil
        hg.organism.AmputateLimb(target.organism, limb)
        ApplyMedicalFinishEffects(ply, target, "amputation")
        return
    end

    if requestedType == "dislocation" then
        local dislocationSession = hg.MedicalMinigame.DislocationSessions[ply]
        if not dislocationSession then return end

        local target = dislocationSession.target
        local limb = dislocationSession.limb
        if not CanUseMedicalMinigameTarget(ply, target) or not limb then return end
        if not target.organism[limb .. "dislocation"] then
            hg.MedicalMinigame.DislocationSessions[ply] = nil
            return
        end

        dislocationSession.progress = math.max(dislocationSession.progress or 0, reportedProgress)
        if (dislocationSession.progress or 0) < 0.999 then return end

        hg.MedicalMinigame.DislocationSessions[ply] = nil

        if hg.organism and hg.organism.CompleteDislocationFix then
            hg.organism.CompleteDislocationFix(target.organism, limb, ply)
        else
            local org = target.organism
            org[limb .. "dislocation"] = false
            org.painadd = (org.painadd or 0) + 1.5
            org.fearadd = (org.fearadd or 0) + 0.1
            target:EmitSound("physics/flesh/flesh_impact_hard6.wav", 65)
        end

        ApplyMedicalFinishEffects(ply, target, "dislocation")
        -- Z-SCAV (CU): вправленный вывих +3 к настроению
        if hg.organism and hg.organism.AddMoodPermanent then hg.organism.AddMoodPermanent(target.organism, 3) end

        return
    end

    local wep = ply:GetActiveWeapon()
    local minigameType = IsValid(wep) and GetMedicalMinigameType(wep) or nil
    if minigameType then
        local target = wep.healbuddy or ply
        if not IsValid(target) then target = ply end

        if target ~= ply and ply:GetPos():DistToSqr(target:GetPos()) > 10000 then return end

        if minigameType == "tourniquet" then
            local modeValueIndex = GetMinigameModeValueIndex(wep, minigameType)
            local mode = wep.mode
            local done = wep:Heal(target, mode)

            if IsValid(wep) and done and wep.PostHeal then
                wep:PostHeal(target, mode)
            end

            if IsValid(wep) and not done and wep.modeValues and wep.modeValues[modeValueIndex] then
                wep.modeValues[modeValueIndex] = 0

                if wep:GetClass() == "weapon_tourniquet" and wep.ShouldDeleteOnFullUse then
                    ply:SelectWeapon("weapon_hands_sh")
                    wep:Remove()
                    return
                end
            end

            if IsValid(wep) and wep.modeValues then
                wep:SetNetVar("modeValues", table.Copy(wep.modeValues))
            end

            ApplyMedicalFinishEffects(ply, target, minigameType, wep)

            return
        end

        wep.HGMedicalMinigameStartValue = nil

        if wep.modeValues then
            local allEmpty = true
            for i, v in ipairs(wep.modeValues) do
                if v > 0 then allEmpty = false break end
            end

            if allEmpty and wep.ShouldDeleteOnFullUse then
                ply:SelectWeapon("weapon_hands_sh")
                wep:Remove()
            end
        end

        ApplyMedicalFinishEffects(ply, target, minigameType, wep)

        return
    end

    if not IsValid(wep) then return end
end)

local function ResolveEyeTarget(ply)
    if not IsValid(ply) then return nil end
    local tr = ply:GetEyeTrace()
    local ent = tr and tr.Entity or nil
    if not IsValid(ent) then return nil end
    if ent:IsRagdoll() and hg and hg.RagdollOwner then
        ent = hg.RagdollOwner(ent) or ent
    end
    if not IsValid(ent) then return nil end
    if not ent:IsPlayer() or not ent:Alive() or not ent.organism then return nil end
    if ent ~= ply and ply:GetPos():DistToSqr(ent:GetPos()) > 10000 then return nil end
    return ent
end

local function StartWeaponMinigameFromCommand(ply, requestedType, useTarget)
    if not IsValid(ply) or not ply:Alive() then return end
    if ply.organism and ply.organism.otrub then return end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return end

    local minigameType = GetMedicalMinigameType(wep)
    if not minigameType or minigameType ~= requestedType then
        ply:ChatPrint("Не то оружие для мини-игры: " .. tostring(requestedType))
        return
    end

    local target = useTarget and ResolveEyeTarget(ply) or ply
    if useTarget and not IsValid(target) then
        ply:ChatPrint("Нет подходящей цели.")
        return
    end

    local modeValueIndex = GetMinigameModeValueIndex(wep, minigameType)
    local startValue = wep.modeValues and wep.modeValues[modeValueIndex] or nil
    wep.healbuddy = target
    wep.HGMedicalMinigameStartValue = startValue

    net.Start("hg_medical_minigame_start")
        net.WriteString(minigameType)
    net.Send(ply)
end

concommand.Add("hg_med_minigame", function(ply, cmd, args)
    local requestedType = tostring(args and args[1] or "")
    local useTarget = tostring(args and args[2] or "") == "target"

    if requestedType ~= "bandage" and requestedType ~= "tourniquet" and requestedType ~= "syringe" then
        if IsValid(ply) then
            ply:ChatPrint("Использование: hg_med_minigame <bandage|tourniquet|syringe> [цель]")
        end
        return
    end

    StartWeaponMinigameFromCommand(ply, requestedType, useTarget)
end)

concommand.Add("hg_med_amputate", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local limb = tostring(args and args[1] or "")
    if not amputationLimbNames[limb] then
        ply:ChatPrint("Использование: hg_med_amputate <larm|rarm|lleg|rleg> [цель]")
        return
    end

    local useTarget = tostring(args and args[2] or "") == "target"
    local ent = useTarget and ResolveEyeTarget(ply) or ply
    hg.MedicalMinigame.StartAmputationMinigame(ply, ent, limb)
end)

concommand.Add("hg_med_dislocation", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local group = tonumber(args and args[1] or nil)
    if group ~= 1 and group ~= 2 and group ~= 3 then
        ply:ChatPrint("Использование: hg_med_dislocation <1|2|3> [цель]")
        return
    end

    local useTarget = tostring(args and args[2] or "") == "target"
    local ent = useTarget and ResolveEyeTarget(ply) or ply
    hg.MedicalMinigame.StartDislocationMinigame(ply, ent, group)
end)

concommand.Add("hg_heartstop", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local useTarget = tostring(args and args[1] or "") == "target"
    local ent = useTarget and ResolveEyeTarget(ply) or ply
    if not IsValid(ent) or not ent.organism then return end

    ent.organism.heartstop = true
    ent.organism.pulse = 0
    ent.organism.heartbeat = 0
end)

concommand.Add("hg_heartstart", function(ply, cmd, args)
    if not IsValid(ply) then return end
    local useTarget = tostring(args and args[1] or "") == "target"
    local ent = useTarget and ResolveEyeTarget(ply) or ply
    if not IsValid(ent) or not ent.organism then return end

    ent.organism.heartstop = false
end)

hg.Mental = hg.Mental or {}
-- Z-SCAV: своя психика аддона выключена - в Z-SCAV настроение/депрессия свои (sv_mood.lua, sv_depression.lua)
local zcity_delta_mental_enabled = CreateConVar("zcity_delta_mental_enabled", "0", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Enable ZCity mental system", 0, 1)
local zcity_delta_traits_enabled = CreateConVar("zcity_delta_traits_enabled", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Enable ZCity traits system", 0, 1)
util.AddNetworkString("zcity_delta_laststand")
util.AddNetworkString("zcity_delta_moodles_extra")
util.AddNetworkString("zcity_delta_traits_sync")
util.AddNetworkString("zcity_delta_traits_set")

local function IsMentalEnabled()
    return zcity_delta_mental_enabled:GetBool()
end

local function IsTraitsEnabled()
    return zcity_delta_traits_enabled:GetBool()
end

local traitDefs = {
    { id = "trained", side = "pos", cost = 5, name = "Trained", desc = "Спокойнее под давлением и опаснее вблизи." },
    { id = "brawler", side = "pos", cost = 4, name = "Brawler", desc = "Насилие даётся вам естественно." },
    { id = "grunt", side = "pos", cost = 2, name = "Grunt", desc = "Мрачные зрелища выбивают вас из колеи труднее." },
    { id = "in_shape", side = "pos", cost = 5, name = "В форме", desc = "Лучше выносливость и восстановление." },
    { id = "lucky", side = "pos", cost = 3, name = "Lucky", desc = "Когда это важно, всё обычно складывается в вашу пользу." },
    { id = "medic", side = "pos", cost = 5, name = "Medic", desc = "Ваше лечение обычно действует лучше, чем у других." },
    { id = "optimist", side = "pos", cost = 3, name = "Optimist", desc = "Вы чуть дольше держитесь за светлую сторону." },
    { id = "maniac", side = "pos", cost = 4, name = "Maniac", desc = "Жуткие сцены влияют на вас необычно." },

    { id = "ptsd", side = "neg", cost = -4, name = "PTSD", desc = "Громкое насилие оставляет на вас более глубокий след." },
    { id = "depressed", side = "neg", cost = -5, name = "Depressed", desc = "Вам труднее сохранять мотивацию и устойчивость." },
    { id = "schizophrenia", side = "neg", cost = -2, name = "Schizophrenia", desc = "Что-то говорит с вами с края поля зрения." },
    { id = "gemophobia", side = "neg", cost = -3, name = "Gemophobia", desc = "Открытые раны и травмы особенно вас тревожат." },
    { id = "unlucky", side = "neg", cost = -2, name = "Unlucky", desc = "Удача редко на вашей стороне." },
}

local traitDefById = {}
for i = 1, #traitDefs do
    traitDefById[traitDefs[i].id] = traitDefs[i]
end

local function NormalizeTraits(raw)
    local out = {}
    if istable(raw) then
        if #raw > 0 then
            for i = 1, #raw do
                local id = tostring(raw[i] or "")
                if id ~= "" and traitDefById[id] then
                    out[id] = true
                end
            end
        else
            for id, v in pairs(raw) do
                id = tostring(id or "")
                if v and id ~= "" and traitDefById[id] then
                    out[id] = true
                end
            end
        end
    end
    return out
end

local function TraitsToArray(traits)
    local out = {}
    if istable(traits) then
        for id, v in pairs(traits) do
            if v and traitDefById[id] then
                out[#out + 1] = id
            end
        end
    end
    table.sort(out)
    return out
end

local function CalcTraitPoints(traits)
    local total = 0
    if istable(traits) then
        for id, v in pairs(traits) do
            if v and traitDefById[id] then
                total = total + (tonumber(traitDefById[id].cost) or 0)
            end
        end
    end
    return total
end

local function GetPlayerTraits(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return {} end
    if not IsTraitsEnabled() then return {} end
    if not istable(ply.__zcity_delta_traits) then
        ply.__zcity_delta_traits = {}
    end
    return ply.__zcity_delta_traits
end

HasTrait = function(ply, id)
    if not IsTraitsEnabled() then return false end
    local tr = GetPlayerTraits(ply)
    return tr[tostring(id or "")] == true
end

GetTraitState = function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return nil end
    ply.__zcity_delta_trait_state = ply.__zcity_delta_trait_state or {}
    return ply.__zcity_delta_trait_state
end

local function PushRawMental(ply, moodDelta, stressDelta)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    -- Z-SCAV: черты влияют на НАШЕ настроение (радость / удар по настроению)
    local org = ply.organism
    local d = (tonumber(moodDelta) or 0) / 100
    if org and d ~= 0 then
        if d > 0 and hg.organism and hg.organism.AddJoy then
            hg.organism.AddJoy(org, d)
        elseif d < 0 and org.happiness then
            org.happiness = math.Clamp(org.happiness + d * 0.5, 0, 1)
        end
    end
    local mood = tonumber(ply:GetNWInt("zcity_delta_mood", 0)) or 0
    ply:SetNWInt("zcity_delta_mood", math.Clamp(mood + (tonumber(moodDelta) or 0), -100, 100))
    ply:SetNWInt("zcity_delta_stress", 0)
end

GetMedicalSeverity = function(target)
    if not IsValid(target) or not target.organism then return 0, 0, 0, 0 end

    local org = target.organism
    local bleed = math.max(tonumber(org.bleed) or 0, 0)
    local woundSeverity = 0
    local arterialSeverity = 0

    if istable(org.wounds) then
        for _, wound in pairs(org.wounds) do
            if istable(wound) then
                woundSeverity = woundSeverity + math.max(tonumber(wound[1]) or 0, 0)
            end
        end
    end

    if istable(org.arterialwounds) then
        for _, wound in pairs(org.arterialwounds) do
            if istable(wound) then
                arterialSeverity = arterialSeverity + math.max(tonumber(wound[1]) or 0, 0)
            end
        end
    end

    local totalSeverity = bleed * 12 + woundSeverity * 0.06 + arterialSeverity * 0.75
    return totalSeverity, bleed, woundSeverity, arterialSeverity
end

local function HasPersistentPainSource(org)
    if not istable(org) then return false end

    local bleed = math.max(tonumber(org.bleed) or 0, 0)
    local internalBleed = math.max(tonumber(org.internalBleed) or 0, 0)
    local woundSeverity = 0
    local arterialSeverity = 0

    if istable(org.wounds) then
        for _, wound in pairs(org.wounds) do
            if istable(wound) then
                woundSeverity = woundSeverity + math.max(tonumber(wound[1]) or 0, 0)
            end
        end
    end

    if istable(org.arterialwounds) then
        for _, wound in pairs(org.arterialwounds) do
            if istable(wound) then
                arterialSeverity = arterialSeverity + math.max(tonumber(wound[1]) or 0, 0)
            end
        end
    end

    if bleed > 0.001 or internalBleed > 0.03 or woundSeverity > 0.01 or arterialSeverity > 0.01 then
        return true
    end

    if org.larmdislocation or org.rarmdislocation or org.llegdislocation or org.rlegdislocation or org.jawdislocation then
        return true
    end

    if org.headamputated or org.larmamputated or org.rarmamputated or org.llegamputated or org.rlegamputated then
        return true
    end

    if (tonumber(org.skull) or 0) >= 0.6 then return true end
    if (tonumber(org.chest) or 0) > 0 then return true end
    if (tonumber(org.pelvis) or 0) >= 0.99 then return true end
    if not org.larmamputated and (tonumber(org.larm) or 0) >= 0.99 then return true end
    if not org.rarmamputated and (tonumber(org.rarm) or 0) >= 0.99 then return true end
    if not org.llegamputated and (tonumber(org.lleg) or 0) >= 0.99 then return true end
    if not org.rlegamputated and (tonumber(org.rleg) or 0) >= 0.99 then return true end

    return false
end

GetMedicalProgressModifier = function(ply, target, minigameType, progressDelta)
    local mul = 1
    local state = GetTraitState(ply)
    local mood = tonumber(ply:GetNWInt("zcity_delta_mood", 0)) or 0
    local stress = tonumber(ply:GetNWInt("zcity_delta_stress", 10)) or 10

    if minigameType == "bandage" and HasTrait(ply, "gemophobia") then
        mul = mul * 0.84
    end

    if HasTrait(ply, "medic") then
        local sameTarget = state
            and state.lastMedicalTarget == target
            and state.lastMedicalType == minigameType
            and (state.lastMedicalAt or 0) + 8 > CurTime()
        mul = mul * (sameTarget and 1.15 or 1.06)
    end

    if HasTrait(ply, "ptsd") and state and (state.ptsdPanicUntil or 0) > CurTime() then
        mul = mul * 0.78
    end

    if HasTrait(ply, "depressed") and mood <= -35 then
        mul = mul * 0.82
    end

    if HasTrait(ply, "schizophrenia") and state and (state.schizoEpisodeUntil or 0) > CurTime() then
        mul = mul * 0.76
    end

    if HasTrait(ply, "grunt") and state and (state.gruntFocusUntil or 0) > CurTime() then
        mul = mul * 1.08
    end

    if HasTrait(ply, "in_shape") and ply.organism and istable(ply.organism.stamina) then
        local stamina = ply.organism.stamina
        local maxStamina = math.max(tonumber(stamina.max) or 0, 1)
        if (tonumber(stamina[1]) or 0) / maxStamina >= 0.6 then
            mul = mul * 1.05
        end
    end

    if HasTrait(ply, "maniac") and state and (state.maniacRushUntil or 0) > CurTime() and minigameType ~= "syringe" then
        mul = mul * 1.10
    end

    if HasTrait(ply, "optimist") and mood >= 20 and stress <= 35 then
        mul = mul * 1.04
    end

    if HasTrait(ply, "unlucky") and state and (state.unluckyFumbleUntil or 0) > CurTime() then
        mul = mul * 0.88
    end

    if state then
        state.lastMedicalTarget = target
        state.lastMedicalType = minigameType
        state.lastMedicalAt = CurTime()
    end

    return math.max((tonumber(progressDelta) or 0) * mul, 0)
end

local function UpdateTraitStamina(ply)
    if not IsTraitsEnabled() then return end
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not ply:Alive() then return end

    local org = ply.organism
    local stamina = org and org.stamina or nil
    if not istable(stamina) or stamina[1] == nil then return end

    local curMax = tonumber(stamina.max) or 220

    local mul = 1
    if HasTrait(ply, "in_shape") then
        mul = mul * 1.5
    end
    if HasTrait(ply, "depressed") then
        mul = mul * 0.7
    end

    local active = ply.__zcity_delta_stamina_trait_active == true

    if mul == 1 then
        if active then
            local base = tonumber(ply.__zcity_delta_stamina_base_max) or curMax
            stamina.max = base
            stamina[1] = math.min(tonumber(stamina[1]) or 0, base)
            ply.__zcity_delta_stamina_trait_active = nil
        end
        ply.__zcity_delta_stamina_base_max = curMax
        return
    end

    if not active then
        ply.__zcity_delta_stamina_base_max = curMax
    end

    local base = tonumber(ply.__zcity_delta_stamina_base_max) or curMax
    local newMax = math.max(1, math.floor(base * mul + 0.5))
    stamina.max = newMax
    stamina[1] = math.min(tonumber(stamina[1]) or 0, newMax)
    ply.__zcity_delta_stamina_trait_active = true
end

timer.Create("zcity_delta_inshape_stamina_tick", 1, 0, function()
    if not IsTraitsEnabled() then return end
    for _, ply in ipairs(player.GetAll()) do
        UpdateTraitStamina(ply)
    end
end)

local function AddMentalStress(ply, stressAdd)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    ply:SetNWInt("zcity_delta_stress", 0)
    return false
end

do
    local function ShouldPatchReload(stored)
        if not istable(stored) then return false end
        if stored.__zcity_delta_ptsd_reload_patched then return false end
        if not isfunction(stored.Reload) then return false end
        local primary = stored.Primary
        if not istable(primary) then return false end
        local clipSize = tonumber(primary.ClipSize) or 0
        local ammo = tostring(primary.Ammo or "")
        if clipSize <= 0 and ammo == "" then return false end
        return true
    end

    local function PatchWeaponReload(class)
        class = tostring(class or "")
        if class == "" then return false end
        local stored = weapons.GetStored(class)
        if not ShouldPatchReload(stored) then return false end

        stored.__zcity_delta_ptsd_reload_patched = true
        stored.__zcity_delta_ptsd_reload_orig = stored.Reload

        function stored:Reload(...)
            local owner = self:GetOwner()
            local speedMul = 1
            if IsValid(owner) and owner:IsPlayer() and HasTrait(owner, "ptsd") then
                speedMul = 0.80
            end

            local now = CurTime()
            local beforePrimary = (isfunction(self.GetNextPrimaryFire) and self:GetNextPrimaryFire()) or nil
            local beforeSecondary = (isfunction(self.GetNextSecondaryFire) and self:GetNextSecondaryFire()) or nil

            local res = self:__zcity_delta_ptsd_reload_orig(...)

            if speedMul ~= 1 then
                if isfunction(self.GetNextPrimaryFire) and isfunction(self.SetNextPrimaryFire) then
                    local after = self:GetNextPrimaryFire()
                    if isnumber(after) and (not isnumber(beforePrimary) or after > beforePrimary) and after > now + 0.05 then
                        self:SetNextPrimaryFire(now + (after - now) * speedMul)
                    end
                end
                if isfunction(self.GetNextSecondaryFire) and isfunction(self.SetNextSecondaryFire) then
                    local after = self:GetNextSecondaryFire()
                    if isnumber(after) and (not isnumber(beforeSecondary) or after > beforeSecondary) and after > now + 0.05 then
                        self:SetNextSecondaryFire(now + (after - now) * speedMul)
                    end
                end
            end

            return res
        end

        return true
    end

    local function ApplyWeaponReloadPatches()
        if not weapons or not weapons.GetList then return end
        local list = weapons.GetList() or {}
        for i = 1, #list do
            local class = list[i] and list[i].ClassName
            if class then
                PatchWeaponReload(class)
            end
        end
    end

    local function ScheduleWeaponReloadPatches()
        timer.Simple(0, ApplyWeaponReloadPatches)
        timer.Simple(1, ApplyWeaponReloadPatches)
        timer.Simple(5, ApplyWeaponReloadPatches)
    end

    hook.Add("Initialize", "zcity_delta_ptsd_reload_patch", ScheduleWeaponReloadPatches)
    hook.Add("InitPostEntity", "zcity_delta_ptsd_reload_patch_post", ScheduleWeaponReloadPatches)
    hook.Add("OnReloaded", "zcity_delta_ptsd_reload_patch_reload", ScheduleWeaponReloadPatches)
    timer.Simple(0, ScheduleWeaponReloadPatches)
end

do
    local shotRadius = 850
    local shotRadiusSqr = shotRadius * shotRadius
    local shotCooldown = 0.35

    hook.Add("EntityFireBullets", "zcity_delta_ptsd_near_shots", function(shooter, data)
        if not IsMentalEnabled() then return end
        if not IsValid(shooter) or not shooter:IsPlayer() then return end
        if not istable(data) then return end

        local src = data.Src
        if not isvector(src) then
            src = shooter:GetShootPos()
        end

        local now = CurTime()
        for _, ply in ipairs(player.GetAll()) do
            if ply == shooter then continue end
            if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then continue end
            if ply:GetPos():DistToSqr(src) > shotRadiusSqr then continue end
            local state = GetTraitState(ply)
            local dist = ply:GetPos():Distance(src)
            local t = 1 - math.Clamp(dist / shotRadius, 0, 1)

            if HasTrait(ply, "ptsd") then
                local untilTime = tonumber(ply.__zcity_delta_ptsd_nearshot_until or 0) or 0
                if untilTime <= now then
                    ply.__zcity_delta_ptsd_nearshot_until = now + shotCooldown
                    if state then
                        state.ptsdPanicUntil = now + 7
                    end
                    local add = 0.6 + (t ^ 0.7) * 1.8
                    AddMentalStress(ply, add)
                end
            end

            if HasTrait(ply, "grunt") and state then
                state.gruntFocusUntil = now + 8
            end

            if HasTrait(ply, "schizophrenia") and state and math.Rand(0, 1) <= 0.18 then
                state.schizoEpisodeUntil = math.max(tonumber(state.schizoEpisodeUntil or 0) or 0, now + 5)
            end
        end
    end)
end

do
    local blastRadius = 6000
    local blastRadiusSqr = blastRadius * blastRadius
    local blastCooldown = 0.85
    local blastSeen = {}
    local blastCleanupAt = 0

    local function CleanupBlastSeen(now)
        if now < blastCleanupAt then return end
        blastCleanupAt = now + 2
        for k, t in pairs(blastSeen) do
            if (now - (tonumber(t) or 0)) > 2 then
                blastSeen[k] = nil
            end
        end
    end

    hook.Add("EntityTakeDamage", "zcity_delta_ptsd_blast_stress", function(target, dmg)
        if not IsMentalEnabled() then return end
        if not IsValid(target) then return end
        if not IsValid(dmg) then return end

        local dtype = dmg:GetDamageType() or 0
        if bit.band(dtype, DMG_BLAST) == 0 and bit.band(dtype, DMG_BLAST_SURFACE) == 0 then return end

        local pos = dmg:GetDamagePosition()
        if not isvector(pos) or pos == vector_origin then
            pos = target:GetPos()
        end

        local now = CurTime()
        CleanupBlastSeen(now)

        local key = string.format(
            "%d:%d:%d:%d",
            math.floor((pos.x / 64) + 0.5),
            math.floor((pos.y / 64) + 0.5),
            math.floor((pos.z / 64) + 0.5),
            math.floor(now * 5)
        )
        if blastSeen[key] then return end
        blastSeen[key] = now

        for _, ply in ipairs(player.GetAll()) do
            if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then continue end
            if ply:GetPos():DistToSqr(pos) > blastRadiusSqr then continue end
            local state = GetTraitState(ply)

            if HasTrait(ply, "ptsd") then
                local untilTime = tonumber(ply.__zcity_delta_ptsd_blast_until or 0) or 0
                if untilTime <= now then
                    ply.__zcity_delta_ptsd_blast_until = now + blastCooldown
                    if state then
                        state.ptsdPanicUntil = now + 9
                    end
                    AddMentalStress(ply, 40)
                end
            end

            if HasTrait(ply, "grunt") and state then
                state.gruntFocusUntil = now + 10
            end

            if HasTrait(ply, "schizophrenia") and state then
                state.schizoEpisodeUntil = math.max(tonumber(state.schizoEpisodeUntil or 0) or 0, now + 6)
            end
        end
    end)
end

local function GetTraitMultipliers(ply)
    if not IsTraitsEnabled() then
        return {
            moodGain = 1,
            moodLoss = 1,
            stressGain = 1,
            stressLoss = 1,
            stressTargetMul = 1,
            dmgStressMul = 1,
            corpseStressMul = 1,
            foodMoodAdd = 0,
        }
    end
    local moodGain, moodLoss = 1, 1
    local stressGain, stressLoss = 1, 1
    local stressTargetMul = 1
    local dmgStressMul = 1
    local corpseStressMul = 1
    local foodMoodAdd = 0

    if HasTrait(ply, "trained") then
        stressGain = stressGain * 0.90
        stressLoss = stressLoss * 1.12
        dmgStressMul = dmgStressMul * 0.85
        stressTargetMul = stressTargetMul * 0.95
    end
    if HasTrait(ply, "brawler") then
        dmgStressMul = dmgStressMul * 0.90
        moodLoss = moodLoss * 0.90
        stressGain = stressGain * 0.95
    end
    if HasTrait(ply, "grunt") then
        corpseStressMul = corpseStressMul * 0.70
        stressGain = stressGain * 0.95
    end
    if HasTrait(ply, "in_shape") then
        stressLoss = stressLoss * 1.20
        stressTargetMul = stressTargetMul * 0.92
    end
    if HasTrait(ply, "medic") then
        stressTargetMul = stressTargetMul * 0.90
        stressGain = stressGain * 0.95
    end
    if HasTrait(ply, "maniac") then
        stressGain = stressGain * 0.92
        moodLoss = moodLoss * 0.92
    end

    if HasTrait(ply, "optimist") then
        moodGain = moodGain * 1.15
        moodLoss = moodLoss * 0.95
    end
    if HasTrait(ply, "depressed") then
        moodGain = moodGain * 0.75
        moodLoss = moodLoss * 1.25
    end
    if HasTrait(ply, "ptsd") then
        stressGain = stressGain * 1.15
        stressLoss = stressLoss * 0.8333333333
        dmgStressMul = dmgStressMul * 1.25
        corpseStressMul = corpseStressMul * 1.45
        stressTargetMul = stressTargetMul * 1.10
    end
    if HasTrait(ply, "gemophobia") then
        stressGain = stressGain * 1.08
        stressLoss = stressLoss * 0.95
        stressTargetMul = stressTargetMul * 1.12
        moodLoss = moodLoss * 1.05
    end

    return {
        moodGain = moodGain,
        moodLoss = moodLoss,
        stressGain = stressGain,
        stressLoss = stressLoss,
        stressTargetMul = stressTargetMul,
        dmgStressMul = dmgStressMul,
        corpseStressMul = corpseStressMul,
        foodMoodAdd = foodMoodAdd,
    }
end

local function SyncTraits(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not IsTraitsEnabled() then
        net.Start("zcity_delta_traits_sync")
        net.WriteString("[]")
        net.Send(ply)
        return
    end
    local arr = TraitsToArray(GetPlayerTraits(ply))
    net.Start("zcity_delta_traits_sync")
    net.WriteString(util.TableToJSON(arr) or "[]")
    net.Send(ply)
end

local function SaveTraits(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local arr = TraitsToArray(GetPlayerTraits(ply))
    ply:SetPData("zcity_delta_traits", util.TableToJSON(arr) or "[]")
end

local function LoadTraits(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not IsTraitsEnabled() then
        ply.__zcity_delta_traits = {}
        SyncTraits(ply)
        return
    end
    local raw = ply:GetPData("zcity_delta_traits", "[]") or "[]"
    local data = util.JSONToTable(raw)
    ply.__zcity_delta_traits = NormalizeTraits(data)
    SyncTraits(ply)
end

local function ApplyTraits(ply, traits)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    if not IsTraitsEnabled() then return false end
    traits = NormalizeTraits(traits)
    if traits.lucky and traits.unlucky then return false end
    if traits.ptsd and traits.depressed then return false end
    local totalCost = CalcTraitPoints(traits)
    if totalCost > 0 then return false end
    ply.__zcity_delta_traits = traits
    SaveTraits(ply)
    SyncTraits(ply)
    return true
end

hook.Add("PlayerInitialSpawn", "zcity_delta_traits_load", function(ply)
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        LoadTraits(ply)
    end)
end)

net.Receive("zcity_delta_traits_set", function(_, ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not IsTraitsEnabled() then
        SyncTraits(ply)
        return
    end
    local raw = net.ReadString() or "[]"
    local data = util.JSONToTable(raw)
    if not istable(data) then return end
    ApplyTraits(ply, data)
end)

local function ApplyTraitsEnabledState(enabled)
    if enabled then
        for _, p in ipairs(player.GetAll()) do
            if IsValid(p) and p:IsPlayer() then
                LoadTraits(p)
                UpdateTraitStamina(p)
            end
        end
        return
    end

    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and p:IsPlayer() then
            p.__zcity_delta_traits = {}
            SyncTraits(p)
            if p.__zcity_delta_stamina_trait_active and p.organism and istable(p.organism.stamina) then
                local base = tonumber(p.__zcity_delta_stamina_base_max) or tonumber(p.organism.stamina.max) or 220
                p.organism.stamina.max = base
                p.organism.stamina[1] = math.min(tonumber(p.organism.stamina[1]) or 0, base)
            end
            p.__zcity_delta_stamina_trait_active = nil
            p.__zcity_delta_stamina_base_max = nil
        end
    end
end

cvars.AddChangeCallback("zcity_delta_traits_enabled", function(_, _, newValue)
    ApplyTraitsEnabledState(tonumber(newValue or "0") == 1)
end, "zcity_delta_traits_enabled_apply")

concommand.Add("zcity_delta_traits_system", function(ply, _, args)
    if IsValid(ply) and (not ply:IsAdmin()) then return end

    local a = tostring(args and args[1] or "")
    if a == "" then
        zcity_delta_traits_enabled:SetBool(not IsTraitsEnabled())
    elseif a == "0" or a == "1" then
        zcity_delta_traits_enabled:SetBool(a == "1")
    else
        return
    end
end)

timer.Create("zcity_delta_moodles_extra_tick", 0.5, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:IsPlayer() then continue end
        local org = ply.organism
        if not org then continue end

        net.Start("zcity_delta_moodles_extra")
        net.WriteFloat(tonumber(org.satiety) or 0)
        net.WriteFloat(tonumber(org.internalBleed) or 0)
        net.WriteFloat(tonumber(org.hungry) or 0)
        net.Send(ply)
    end
end)

local function ClampStat(v)
    v = tonumber(v) or 0
    return math.Clamp(math.floor(v + 0.5), 0, 100)
end

local function ClampMood(v)
    v = tonumber(v) or 0
    return math.Clamp(math.floor(v + 0.5), -100, 100)
end

local function ResolvePlayerFromEntity(ent)
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() then return ent end
    local org = ent.organism
    if org and IsValid(org.owner) and org.owner:IsPlayer() then
        return org.owner
    end
    if IsValid(ent.Owner) and ent.Owner:IsPlayer() then
        return ent.Owner
    end
    return nil
end

local function IsBetaBlockerStressActive(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    local untilTime = tonumber(ply.__zcity_delta_betablock_until or 0) or 0
    return untilTime > CurTime()
end

local function ApplyBetaBlockerStressReset(target, duration)
    if not IsValid(target) or not target:IsPlayer() then return false end
    if not IsMentalEnabled() then return false end
    duration = math.Clamp(tonumber(duration) or 60, 1, 600)
    target.__zcity_delta_betablock_until = math.max(tonumber(target.__zcity_delta_betablock_until or 0) or 0, CurTime() + duration)
    local mood = tonumber(target:GetNWInt("zcity_delta_mood", 0)) or 0
    target:SetNWInt("zcity_delta_mood", ClampMood(mood))
    target:SetNWInt("zcity_delta_stress", 0)
    return true
end

local function SetMental(ply, mood, stress, force)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local currentMood = tonumber(ply:GetNWInt("zcity_delta_mood", 0)) or 0
    local currentStress = 0
    local nextMood = ClampMood(mood)
    local nextStress = 0

    if not force then
        local mult = GetTraitMultipliers(ply)

        local dm = nextMood - currentMood
        if dm > 0 then
            dm = dm * (mult.moodGain or 1)
        elseif dm < 0 then
            dm = dm * (mult.moodLoss or 1)
        end
        nextMood = ClampMood(currentMood + dm)

        nextStress = 0
    end

    if not force and currentMood <= -100 then
        local untilTime = tonumber(ply.__zcity_delta_antidep_until or 0) or 0
        if untilTime <= CurTime() then
            nextMood = -100
        end
    end
    ply:SetNWInt("zcity_delta_mood", nextMood)
    ply:SetNWInt("zcity_delta_stress", 0)
end

local function GetMental(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return 0, 0 end
    return tonumber(ply:GetNWInt("zcity_delta_mood", 0)) or 0, 0
end

local function ApplyAntidepressantDose(applier, target, strength)
    if not IsValid(target) or not target:IsPlayer() then return false end
    if not IsMentalEnabled() then
        -- Z-SCAV: антидепрессант снижает нашу депрессию и чуть поднимает настроение
        local org = target.organism
        if not org then return false end
        strength = math.Clamp(tonumber(strength) or 1, 0.1, 5)
        org.depression = math.max(0, (org.depression or 0) - 0.25 * strength)
        if hg.organism and hg.organism.AddJoy then hg.organism.AddJoy(org, 0.1 * strength) end
        return true
    end

    strength = math.Clamp(tonumber(strength) or 1, 0.1, 5)

    target.__zcity_delta_antidep_until = math.max(tonumber(target.__zcity_delta_antidep_until or 0) or 0, CurTime() + (240 * strength))
    target.__zcity_delta_antidep_strength = math.Clamp((tonumber(target.__zcity_delta_antidep_strength or 0) or 0) + strength, 0, 6)

    if IsValid(applier) and applier:IsPlayer() then
        applier.__zcity_delta_antidep_into = applier.__zcity_delta_antidep_into or {}
        local sid = target:SteamID64()
        applier.__zcity_delta_antidep_into[sid] = (applier.__zcity_delta_antidep_into[sid] or 0) + strength

        if applier.__zcity_delta_antidep_into[sid] > 1 then
            local dmgInfo = DamageInfo()
            dmgInfo:SetAttacker(applier)

            local overdoseMul = zb and zb.MaximumHarm or 2
            local character = (hg and hg.GetCurrentCharacter) and hg.GetCurrentCharacter(target) or target
            hook.Run("HomigradDamage", target, dmgInfo, HITGROUP_CHEST, character, strength * overdoseMul)
        end
    end

    return true
end

hg.Mental.Get = GetMental
hg.Mental.Set = SetMental
hg.Mental.IsEnabled = IsMentalEnabled
hg.Mental.ApplyAntidepressantDose = ApplyAntidepressantDose

local function PatchBetaBlockerWeapon()
    if not weapons or not weapons.GetStored then return end
    local swep = weapons.GetStored("weapon_betablock")
    if not swep or swep.__zcity_delta_betablock_patched then return end
    if not isfunction(swep.Heal) then return end
    swep.__zcity_delta_betablock_patched = true
    swep.PrintName = "Aphobasol"
    if istable(swep.modeNames) then
        swep.modeNames[1] = "aphobasol"
    end
    local oldHeal = swep.Heal
    swep.Heal = function(self, ent, mode)
        local target = ResolvePlayerFromEntity(ent)
        if IsValid(target) then
            ApplyBetaBlockerStressReset(target, 60)
        end
        return oldHeal(self, ent, mode)
    end
end

timer.Simple(0, PatchBetaBlockerWeapon)
timer.Create("zcity_delta_patch_betablock", 5, 0, PatchBetaBlockerWeapon)

local lastStandCurvePoints = {
    { h = -100, c = 0.00 },
    { h = -30, c = 0.00 },
    { h = -10.02, c = 0.10 },
    { h = -10, c = 0.20 },
    { h = 0, c = 0.20 },
    { h = 10, c = 0.50 },
    { h = 70, c = 1.00 },
    { h = 100, c = 1.00 },
}

local lastStandChanceScale = 0.5
local lastStandChanceCap = 0.5

local function EvaluateLastStandChance(happiness, ply)
    happiness = tonumber(happiness) or 0
    local chance = 0

    if happiness <= lastStandCurvePoints[1].h then
        chance = lastStandCurvePoints[1].c * lastStandChanceScale
    else
        for i = 2, #lastStandCurvePoints do
            local prev = lastStandCurvePoints[i - 1]
            local nextP = lastStandCurvePoints[i]
            if happiness <= nextP.h then
                local denom = (nextP.h - prev.h)
                if denom == 0 then
                    chance = nextP.c
                else
                    local t = math.Clamp((happiness - prev.h) / denom, 0, 1)
                    local baseChance = prev.c + (nextP.c - prev.c) * t
                    chance = baseChance * lastStandChanceScale
                end
                break
            end
        end
    end

    if chance <= 0 then
        chance = lastStandCurvePoints[#lastStandCurvePoints].c * lastStandChanceScale
    end

    if IsValid(ply) and ply:IsPlayer() then
        local mult = 1
        if HasTrait(ply, "lucky") then mult = mult * 1.15 end
        if HasTrait(ply, "unlucky") then mult = mult * 0.85 end
        chance = chance * mult
    end

    return math.min(chance, lastStandChanceCap)
end

local function EnsureLastStandHappinessHistory(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return nil end

    local hist = ply.__zcity_delta_last_happiness
    if not istable(hist) then
        hist = {}
        ply.__zcity_delta_last_happiness = hist
        ply.__zcity_delta_last_happiness_started = CurTime()
    end
    if ply.__zcity_delta_last_happiness_started == nil then
        ply.__zcity_delta_last_happiness_started = CurTime()
    end

    local mood = ClampMood(ply:GetNWInt("zcity_delta_mood", 0))
    if #hist < 10 then
        for i = #hist + 1, 10 do
            hist[i] = mood
        end
    end

    return hist
end

timer.Create("zcity_delta_laststand_happiness_updater", 60, 0, function()
    if not IsMentalEnabled() then return end
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then continue end

        local hist = EnsureLastStandHappinessHistory(ply)
        if not hist then continue end

        for i = 10, 2, -1 do
            hist[i] = hist[i - 1]
        end
        hist[1] = ClampMood(ply:GetNWInt("zcity_delta_mood", 0))
    end
end)

hook.Add("PlayerInitialSpawn", "zcity_delta_laststand_init_history", function(ply)
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        EnsureLastStandHappinessHistory(ply)
    end)
end)

local function ApplyLastStandEffects(ply, org)
    local now = CurTime()

    org.brain = 0.05
    org.blood = 3750
    org.pulse = 120
    org.heartbeat = 120
    org.heartstop = false

    if org.o2 and org.o2.range then
        org.o2[1] = org.o2.range
        org.o2.curregen = org.o2.regen
        org.lastStandO2Until = now + 6.7
    end

    org.temperature = 37

    org.internalBleed = (org.internalBleed or 0) * 0.05
    org.bleed = (org.bleed or 0) * 0.05

    if istable(org.wounds) then
        for _, wound in pairs(org.wounds) do
            if istable(wound) and isnumber(wound[1]) then
                wound[1] = wound[1] * 0.05
            end
        end
    end

    if istable(org.arterialwounds) then
        for _, wound in pairs(org.arterialwounds) do
            if istable(wound) and isnumber(wound[1]) then
                wound[1] = wound[1] * 0.05
            end
        end
    end

    org.painkiller = 0
    org.analgesia = 0
    org.analgesiaAdd = 0
    org.naloxone = 0
    org.naloxoneadd = 0
    org.tranquilizer = 0

    if org.stamina and org.stamina.max then
        org.stamina[1] = org.stamina.max
    end

    org.lastStandAdrenalineUntil = now + 300

    ply.__zcity_delta_laststand_active_until = now + 200
end

function hg.Mental.TryLastStand(ply, org)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    if not ply:Alive() then return false end
    if not IsMentalEnabled() then return false end

    org = org or ply.organism
    if not org or not org.brain then return false end

    if ply.__zcity_delta_laststand_rolled then return false end

    local hist = EnsureLastStandHappinessHistory(ply)
    local currentMood = ClampMood(ply:GetNWInt("zcity_delta_mood", 0))
    local histMood = (hist and hist[10] ~= nil) and ClampMood(hist[10]) or nil
    local useHist = histMood ~= nil
    local happiness = useHist and histMood or currentMood
    local chance = EvaluateLastStandChance(happiness, ply)
    local roll = math.Rand(0, 1)

    ply.__zcity_delta_laststand_rolled = true
    ply.__zcity_delta_laststand_last = {
        happiness = happiness,
        currentMood = currentMood,
        histMood = histMood,
        useHist = useHist,
        chance = chance,
        roll = roll,
    }

    if roll >= chance then
        return false
    end

    ApplyLastStandEffects(ply, org)

    net.Start("zcity_delta_laststand")
    net.WriteBool(true)
    net.WriteFloat(tonumber(ply.__zcity_delta_laststand_active_until) or (CurTime() + 200))
    net.Send(ply)

    local tid = "zcity_delta_laststand_end_" .. ply:SteamID64()
    timer.Remove(tid)
    timer.Create(tid, 200, 1, function()
        if not IsValid(ply) then return end
        net.Start("zcity_delta_laststand")
        net.WriteBool(false)
        net.WriteFloat(0)
        net.Send(ply)
    end)

    return true
end

local function SaveMental(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    ply:SetPData("zcity_delta_mental", "{}")
end

local function LoadMental(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    SetMental(ply, math.random(10, 30), 10)
end

hook.Add("PlayerInitialSpawn", "zcity_delta_mental_load", function(ply)
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        if not IsMentalEnabled() then
            SetMental(ply, math.random(10, 30), 10, true)
            return
        end
        LoadMental(ply)
    end)
end)

concommand.Add("zcity_delta_laststand_debug", function(ply)
    if not IsMentalEnabled() then return end
    if IsValid(ply) and not ply:IsAdmin() then return end
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local org = ply.organism
    local hist = EnsureLastStandHappinessHistory(ply)
    local currentMood = ClampMood(ply:GetNWInt("zcity_delta_mood", 0))
    local histMood = (hist and hist[10] ~= nil) and ClampMood(hist[10]) or nil
    local useHist = histMood ~= nil
    local used = useHist and histMood or currentMood
    local chance = EvaluateLastStandChance(used, ply)
    local last = ply.__zcity_delta_laststand_last
    local lastChance = istable(last) and tonumber(last.chance) or nil
    local lastRoll = istable(last) and tonumber(last.roll) or nil
    local lastHappiness = istable(last) and tonumber(last.happiness) or nil

    print(string.format(
        "[zcity-delta laststand] mood_now=%s mood_9_10=%s use_hist=%s chance=%.2f rolled=%s last_happiness=%s last_roll=%s last_chance=%s brain=%s org_alive=%s ply_alive=%s",
        tostring(currentMood),
        tostring(histMood),
        tostring(useHist),
        tonumber(chance) or 0,
        tostring(ply.__zcity_delta_laststand_rolled == true),
        tostring(lastHappiness),
        tostring(lastRoll),
        tostring(lastChance),
        tostring(org and org.brain),
        tostring(org and org.alive),
        tostring(ply:Alive())
    ))
end)

hook.Add("PlayerDisconnected", "zcity_delta_mental_save", function(ply)
    SaveMental(ply)
end)

hook.Add("PlayerDeath", "zcity_delta_mental_death", function(ply)
    if not IsValid(ply) then return end
    ply.__zcity_delta_laststand_rolled = nil
    ply.__zcity_delta_laststand_active_until = nil
    ply.__zcity_delta_laststand_last = nil
    ply.__zcity_delta_last_happiness = nil
    ply.__zcity_delta_last_happiness_started = nil
    ply.__zcity_delta_mental_last_damage = nil
    ply.__zcity_delta_mental_last_treated = nil
    ply.__zcity_delta_antidep_until = nil
    ply.__zcity_delta_antidep_strength = nil
    ply.__zcity_delta_seen_corpses = nil
    ply.__zcity_delta_seen_corpses_count = nil
    ply.__zcity_delta_seen_corpses_first_at = nil
    ply.__zcity_delta_pain_penalty_applied = nil
    ply.__zcity_delta_betablock_until = nil
    ply.__zcity_delta_ptsd_nearshot_until = nil
    ply.__zcity_delta_ptsd_blast_until = nil
    ply.__zcity_delta_basecalm_accum = nil
    ply.__zcity_delta_stamina_trait_active = nil
    ply.__zcity_delta_stamina_base_max = nil
    if ply.organism then
        ply.organism.lastStandAdrenalineUntil = 0
        ply.organism.lastStandO2Until = 0
        ply.organism.adrenalineAdd = 0
        ply.organism.adrenaline = 0
        if ply.organism.o2 and ply.organism.o2.curregen ~= nil then
            ply.organism.o2.curregen = ply.organism.o2.regen
        end
    end
    local tid = "zcity_delta_laststand_end_" .. ply:SteamID64()
    timer.Remove(tid)
    net.Start("zcity_delta_laststand")
    net.WriteBool(false)
    net.WriteFloat(0)
    net.Send(ply)
    if IsMentalEnabled() then
        SetMental(ply, math.random(10, 30), 10, true)
        SaveMental(ply)
    end
end)

hook.Add("EntityTakeDamage", "zcity_delta_mental_damage", function(target, dmg)
    if not IsValid(target) or not target:IsPlayer() then return end
    if not target:Alive() then return end
    if not IsMentalEnabled() then return end
    local d = math.max(dmg:GetDamage() or 0, 0)
    if d <= 0 then return end

    local mood, stress = GetMental(target)
    local stressAdd = math.Clamp(d * 0.25, 0.5, 10)
    local moodDrop = math.Clamp(d * 0.12, 0.5, 6)
    local mult = GetTraitMultipliers(target)
    stressAdd = stressAdd * (mult.dmgStressMul or 1)

    target.__zcity_delta_mental_last_damage = CurTime()
    SetMental(target, mood - moodDrop, stress + stressAdd)
end)

hook.Add("EntityTakeDamage", "zcity_delta_trait_trained_melee_damage", function(target, dmg)
    if not IsTraitsEnabled() then return end
    if not IsValid(target) or not target:IsPlayer() then return end
    if not target:Alive() then return end
    if not IsValid(dmg) then return end

    local att = dmg:GetAttacker()
    if not IsValid(att) or not att:IsPlayer() then return end
    if not HasTrait(att, "trained") then return end

    local inf = dmg:GetInflictor()
    local isFists = IsValid(inf) and inf:IsPlayer()
    local dtype = dmg:GetDamageType() or 0
    local isMeleeType = bit.band(dtype, DMG_CLUB) ~= 0 or bit.band(dtype, DMG_SLASH) ~= 0
    if not isFists and not isMeleeType then return end

    local cur = dmg:GetDamage() or 0
    if cur <= 0 then return end
    dmg:SetDamage(cur * 1.12)

    local state = GetTraitState(att)
    if not state or (state.trainedOpeningUntil or 0) <= CurTime() then return end
    if target.organism then
        target.organism.immobilization = math.max(tonumber(target.organism.immobilization) or 0, 2.5)
        target.organism.painadd = (tonumber(target.organism.painadd) or 0) + 1.5
    end
    state.trainedOpeningUntil = nil
end)

hook.Add("EntityTakeDamage", "zcity_delta_trait_brawler_damage_mood", function(target, dmg)
    if not IsMentalEnabled() then return end
    if not IsTraitsEnabled() then return end
    if not IsValid(dmg) then return end

    local att = dmg:GetAttacker()
    if not IsValid(att) or not att:IsPlayer() or not att:Alive() then return end
    if not HasTrait(att, "brawler") then return end
    if not IsValid(target) then return end

    local realTarget = target
    if not realTarget:IsPlayer() and realTarget:IsRagdoll() and hg and hg.RagdollOwner then
        realTarget = hg.RagdollOwner(realTarget) or realTarget
    end
    if not IsValid(realTarget) or not realTarget:IsPlayer() then return end
    if realTarget == att then return end

    local d = dmg:GetDamage() or 0
    if d <= 0 then return end

    local add = math.Clamp(d * 0.04, 0.2, 2.5)
    local mood, stress = hg.Mental.Get(att)
    hg.Mental.Set(att, mood + add, stress)

    local state = GetTraitState(att)
    if not state then return end
    local now = CurTime()
    if (state.brawlerComboUntil or 0) > now then
        state.brawlerCombo = (tonumber(state.brawlerCombo) or 0) + 1
    else
        state.brawlerCombo = 1
    end
    state.brawlerComboUntil = now + 3.5

    if (state.brawlerCombo or 0) < 3 then return end
    state.brawlerCombo = 0
    state.brawlerComboUntil = 0

    if realTarget.organism then
        realTarget.organism.immobilization = math.max(tonumber(realTarget.organism.immobilization) or 0, 3)
        if istable(realTarget.organism.stamina) then
            local stamina = realTarget.organism.stamina
            local maxStamina = math.max(tonumber(stamina.max) or 0, 1)
            stamina[1] = math.max(0, (tonumber(stamina[1]) or 0) - maxStamina * 0.22)
        end
    end
end)

hook.Add("PlayerDeath", "zcity_delta_trait_maniac_kill_mood", function(victim, inflictor, attacker)
    if not IsMentalEnabled() then return end
    if not IsTraitsEnabled() then return end
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    if attacker == victim then return end
    if not HasTrait(attacker, "maniac") then return end

    local mood, stress = hg.Mental.Get(attacker)
    hg.Mental.Set(attacker, mood + 14, stress)

    local state = GetTraitState(attacker)
    if state then
        state.maniacRushUntil = CurTime() + 18
    end
end)

hook.Add("EntityTakeDamage", "zcity_delta_trait_misc_damage", function(target, dmg)
    if not IsTraitsEnabled() then return end
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return end
    if not IsValid(dmg) then return end

    local cur = dmg:GetDamage() or 0
    if cur <= 0 then return end

    local now = CurTime()
    local state = GetTraitState(target)

    if HasTrait(target, "lucky") and state and (state.luckyGuardUntil or 0) <= now and math.Rand(0, 1) <= 0.14 then
        dmg:SetDamage(cur * 0.72)
        state.luckyGuardUntil = now + 18
        if target.organism then
            target.organism.immobilization = math.max((tonumber(target.organism.immobilization) or 0) - 2, 0)
        end
    elseif HasTrait(target, "unlucky") and state and (state.unluckyGuardUntil or 0) <= now and math.Rand(0, 1) <= 0.18 then
        dmg:SetDamage(cur * 1.16)
        state.unluckyGuardUntil = now + 14
        state.unluckyFumbleUntil = now + 12
    end

    if HasTrait(target, "grunt") and state then
        state.gruntFocusUntil = now + 8
    end

    if HasTrait(target, "schizophrenia") and state and math.Rand(0, 1) <= 0.12 then
        state.schizoEpisodeUntil = math.max(tonumber(state.schizoEpisodeUntil or 0) or 0, now + 4)
    end

    if (tonumber(target.__zcity_delta_stabilized_until or 0) or 0) > now and target.organism then
        target.organism.bleed = math.max((tonumber(target.organism.bleed) or 0) - 0.03, 0)
        target.organism.painadd = math.max((tonumber(target.organism.painadd) or 0) - 3.5, 0)
        target.organism.avgpain = math.max((tonumber(target.organism.avgpain) or 0) - 1.25, 0)
        target.organism.pain = math.max((tonumber(target.organism.pain) or 0) - 2.5, 0)
    end
end)

timer.Create("zcity_delta_trait_maintenance", 1, 0, function()
    if not IsTraitsEnabled() then return end

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then continue end

        local state = GetTraitState(ply)
        local org = ply.organism

        if HasTrait(ply, "in_shape") and org and istable(org.stamina) then
            local stamina = org.stamina
            local maxStamina = math.max(tonumber(stamina.max) or 0, 1)
            local frac = (tonumber(stamina[1]) or 0) / maxStamina
            if frac <= 0.33 and not ply:KeyDown(IN_SPEED) then
                stamina[1] = math.min(maxStamina, (tonumber(stamina[1]) or 0) + maxStamina * 0.12)
                if state then
                    state.secondWindUntil = CurTime() + 6
                end
            end
        end

        if HasTrait(ply, "optimist") and tonumber(ply:GetNWInt("zcity_delta_mood", 0)) >= 25 then
            for _, near in ipairs(player.GetAll()) do
                if near == ply then continue end
                if not IsValid(near) or not near:IsPlayer() or not near:Alive() then continue end
                if near:GetPos():DistToSqr(ply:GetPos()) > (280 * 280) then continue end
                PushRawMental(near, 1, -1)
            end
        end

        if HasTrait(ply, "schizophrenia") and state then
            if (tonumber(ply.__zcity_delta_clarity_until or 0) or 0) > CurTime() then
                state.schizoEpisodeUntil = nil
            elseif math.Rand(0, 1) <= 0.10 then
                state.schizoEpisodeUntil = CurTime() + math.Rand(3, 5)
                PushRawMental(ply, math.random(-2, 2), math.random(1, 4))
            end
        end

        if HasTrait(ply, "depressed") and (tonumber(ply.__zcity_delta_relief_until or 0) or 0) > CurTime() then
            PushRawMental(ply, 1, -2)
        end
    end
end)

timer.Create("zcity_delta_mental_tick", 2, 0, function()
    if not IsMentalEnabled() then return end
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:IsPlayer() then continue end
        if not ply:Alive() then continue end

        local mood, stress = GetMental(ply)
        local traitMult = GetTraitMultipliers(ply)
        local antidepUntil = tonumber(ply.__zcity_delta_antidep_until or 0) or 0
        local antidepStrength = math.Clamp(tonumber(ply.__zcity_delta_antidep_strength or 0) or 0, 0, 6)
        local antidepActive = antidepUntil > CurTime() and antidepStrength > 0

        if mood <= -100 and not antidepActive then
            SetMental(ply, -100, stress)
            continue
        end

        local function GetCorpseInFOV()
            local eyePos = ply:EyePos()
            local fwd = ply:EyeAngles():Forward()
            local near = ents.FindInSphere(eyePos, 900)
            local cosLimit = 0.78

            for i = 1, #near do
                local ent = near[i]
                if not IsValid(ent) or not ent:IsRagdoll() then continue end

                local owner = (hg and hg.RagdollOwner) and hg.RagdollOwner(ent) or nil
                if IsValid(owner) and owner:IsPlayer() and owner:Alive() then
                    continue
                end

                local pos = ent.WorldSpaceCenter and ent:WorldSpaceCenter() or ent:GetPos()
                local dir = pos - eyePos
                local distSqr = dir:LengthSqr()
                if distSqr < 25 then continue end
                dir:Normalize()

                if dir:Dot(fwd) < cosLimit then continue end

                local tr = util.TraceLine({
                    start = eyePos,
                    endpos = pos,
                    filter = ply,
                    mask = MASK_SOLID,
                })
                if not tr.Hit or tr.Entity == ent then
                    return ent
                end
            end

            return nil
        end

        local function GetWoundedPlayerInFOV()
            if not HasTrait(ply, "gemophobia") then return nil, 0 end
            local eyePos = ply:EyePos()
            local fwd = ply:EyeAngles():Forward()
            local near = ents.FindInSphere(eyePos, 1100)
            local cosLimit = 0.78
            local best, bestSeverity = nil, 0

            for i = 1, #near do
                local ent = near[i]
                if not IsValid(ent) or ent == ply then continue end

                local targetPly = nil
                local losEnt = ent
                if ent:IsPlayer() then
                    targetPly = ent
                elseif ent:IsRagdoll() then
                    local owner = (hg and hg.RagdollOwner) and hg.RagdollOwner(ent) or nil
                    if IsValid(owner) and owner:IsPlayer() then
                        targetPly = owner
                    end
                end

                if not IsValid(targetPly) or targetPly == ply or (not targetPly:Alive()) then continue end
                if not targetPly.organism then continue end

                local pos = losEnt.WorldSpaceCenter and losEnt:WorldSpaceCenter() or losEnt:GetPos()
                local dir = pos - eyePos
                local distSqr = dir:LengthSqr()
                if distSqr < 25 then continue end
                dir:Normalize()
                if dir:Dot(fwd) < cosLimit then continue end

                local tr = util.TraceLine({
                    start = eyePos,
                    endpos = pos,
                    filter = ply,
                    mask = MASK_SOLID,
                })
                if tr.Hit and tr.Entity ~= losEnt and tr.Entity ~= targetPly then continue end

                local org = targetPly.organism
                local bleed = math.max(tonumber(org.bleed) or 0, 0)
                local woundSeverity = 0
                if istable(org.wounds) then
                    for _, wound in pairs(org.wounds) do
                        if istable(wound) then
                            woundSeverity = woundSeverity + math.max(tonumber(wound[1]) or 0, 0)
                        end
                    end
                end
                local arterialSeverity = 0
                if istable(org.arterialwounds) then
                    for _, wound in pairs(org.arterialwounds) do
                        if istable(wound) then
                            arterialSeverity = arterialSeverity + math.max(tonumber(wound[1]) or 0, 0)
                        end
                    end
                end

                if bleed <= 0.001 and woundSeverity <= 0.01 and arterialSeverity <= 0.01 then
                    continue
                end

                local severity = 0
                severity = severity + math.Clamp(bleed * 14, 0, 40)
                severity = severity + math.Clamp(woundSeverity * 0.10, 0, 30)
                severity = severity + math.Clamp(arterialSeverity * 0.90, 0, 45)

                if severity > bestSeverity then
                    bestSeverity = severity
                    best = targetPly
                end
            end

            return best, bestSeverity
        end

        local corpse = GetCorpseInFOV()
        if corpse then
            local seen = ply.__zcity_delta_seen_corpses
            if not istable(seen) then
                seen = {}
                ply.__zcity_delta_seen_corpses = seen
                ply.__zcity_delta_seen_corpses_count = 0
            end

            local firstSeenAt = tonumber(ply.__zcity_delta_seen_corpses_first_at or 0) or 0
            if firstSeenAt > 0 and (CurTime() - firstSeenAt) >= 480 then
                ply.__zcity_delta_seen_corpses = {}
                ply.__zcity_delta_seen_corpses_count = 0
                ply.__zcity_delta_seen_corpses_first_at = 0
                seen = ply.__zcity_delta_seen_corpses
                firstSeenAt = 0
            end

            local key = tostring(corpse:EntIndex())
            if corpse.GetCreationID then
                key = key .. ":" .. tostring(corpse:GetCreationID())
            end

            if not seen[key] then
                seen[key] = true
                local seenCount = tonumber(ply.__zcity_delta_seen_corpses_count or 0) or 0
                local baseGain = math.max(1, math.floor((10 * (0.9 ^ seenCount)) + 0.5))
                if HasTrait(ply, "maniac") then
                    mood = mood + math.max(1, math.floor(baseGain * 1.25 + 0.5))
                else
                    local gain = math.max(1, math.floor(baseGain * (traitMult.corpseStressMul or 1) + 0.5))
                    stress = stress + gain
                    mood = mood - gain
                end
                ply.__zcity_delta_seen_corpses_count = seenCount + 1
                if firstSeenAt <= 0 then
                    ply.__zcity_delta_seen_corpses_first_at = CurTime()
                end
            end
        end

        local org = ply.organism
        if org then
            local pain = tonumber(org.pain or 0) or 0
            local desiredPainPenalty = math.floor(math.Clamp(math.min(pain, 120) / 24, 0, 5) + 0.5)
            local appliedPainPenalty = tonumber(ply.__zcity_delta_pain_penalty_applied or 0) or 0

            if desiredPainPenalty > appliedPainPenalty then
                mood = mood - (desiredPainPenalty - appliedPainPenalty)
            end

            ply.__zcity_delta_pain_penalty_applied = desiredPainPenalty
        end

        if antidepActive then
            stress = stress - (1 + math.floor(antidepStrength * 0.35))
            mood = mood + (2 + math.floor(antidepStrength * 0.6))

            ply.__zcity_delta_antidep_strength = math.max(antidepStrength - 0.35, 0)
            if ply.__zcity_delta_antidep_strength <= 0 then
                ply.__zcity_delta_antidep_until = 0
            end
        end

        do
            local org = ply.organism
            local stressTarget = 10

            local lastDmg = tonumber(ply.__zcity_delta_mental_last_damage or 0) or 0
            if lastDmg > 0 then
                local since = CurTime() - lastDmg
                if since < 20 then
                    stressTarget = math.max(stressTarget, 35 + math.Clamp(20 - since, 0, 20) * 0.5)
                end
            end

            if org then
                local pain = tonumber(org.pain) or 0
                local shock = tonumber(org.shock) or 0
                local bleed = tonumber(org.bleed) or 0
                local internalBleed = tonumber(org.internalBleed) or 0

                stressTarget = stressTarget + math.Clamp(pain * 0.18, 0, 25)
                stressTarget = stressTarget + math.Clamp(shock * 0.22, 0, 20)
                stressTarget = stressTarget + math.Clamp(bleed * 18, 0, 35)
                stressTarget = stressTarget + math.Clamp(internalBleed * 1.2, 0, 35)

                if HasTrait(ply, "gemophobia") then
                    local woundSeverity = 0
                    if istable(org.wounds) then
                        for _, wound in pairs(org.wounds) do
                            if istable(wound) then
                                woundSeverity = woundSeverity + math.max(tonumber(wound[1]) or 0, 0)
                            end
                        end
                    end

                    local arterialSeverity = 0
                    if istable(org.arterialwounds) then
                        for _, wound in pairs(org.arterialwounds) do
                            if istable(wound) then
                                arterialSeverity = arterialSeverity + math.max(tonumber(wound[1]) or 0, 0)
                            end
                        end
                    end
                    local extra = 0
                    local woundedInFov, woundedSeverity = GetWoundedPlayerInFOV()
                    if woundedInFov and woundedSeverity > 0 then
                        extra = extra + 12 + math.Clamp(woundedSeverity, 0, 40)
                    end
                    if bleed > 0.001 or woundSeverity > 0.01 or arterialSeverity > 0.01 then
                        extra = extra + 8
                    end
                    extra = extra + math.Clamp(bleed * 8, 0, 20)
                    extra = extra + math.Clamp(woundSeverity * 0.08, 0, 18)
                    extra = extra + math.Clamp(arterialSeverity * 0.6, 0, 22)
                    stressTarget = stressTarget + extra
                end

                if istable(org.o2) then
                    local cur = tonumber(org.o2[1])
                    local maxV = tonumber(org.o2.range)
                    if cur and maxV and maxV > 0 then
                        local pct = math.Clamp((cur / maxV) * 100, 0, 100)
                        if pct < 90 then
                            stressTarget = stressTarget + math.Clamp((90 - pct) * 0.35, 0, 20)
                        end
                    end
                end

                local t = tonumber(org.temperature)
                if t then
                    local dt = math.abs(t - 36.7)
                    if dt > 0.6 then
                        stressTarget = stressTarget + math.Clamp((dt - 0.6) * 4, 0, 16)
                    end
                end

                if org.otrub then
                    stressTarget = math.min(stressTarget, 5)
                end
            end

            stressTarget = math.Clamp(stressTarget, 0, 100)
            stressTarget = math.Clamp(stressTarget * (traitMult.stressTargetMul or 1), 0, 100)
            local diff = stressTarget - stress
            if diff > 0.01 then
                stress = stress + math.min(2, diff * 0.25)
            elseif diff < -0.01 then
                stress = stress - math.min(1, (-diff) * 0.15)
            end
        end

        mood = ClampMood(mood)
        stress = ClampStat(stress)

        SetMental(ply, mood, stress)
        do
            local sNow = tonumber(ply:GetNWInt("zcity_delta_stress", 10)) or 10
            local calmMul = 1
            if HasTrait(ply, "ptsd") then
                calmMul = calmMul * 0.8333333333
            end
            ply.__zcity_delta_basecalm_accum = (tonumber(ply.__zcity_delta_basecalm_accum) or 0) + calmMul
            local drain = math.max(0, math.floor((tonumber(ply.__zcity_delta_basecalm_accum) or 0) + 0.000001))
            if drain > 0 then
                ply.__zcity_delta_basecalm_accum = (tonumber(ply.__zcity_delta_basecalm_accum) or 0) - drain
            end
            local sNew = ClampStat(sNow - drain)
            if IsBetaBlockerStressActive(ply) then
                sNew = 0
            end
            ply:SetNWInt("zcity_delta_stress", sNew)
        end
        if (CurTime() % 30) < 2 then
            SaveMental(ply)
        end
    end
end)

timer.Create("zcity_delta_depression_stamina_drain", 0.35, 0, function()
    if not IsMentalEnabled() then return end
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then continue end
        if ply:InVehicle() then continue end
        if ply.organism and ply.organism.otrub then continue end

        local org = ply.organism
        local stamina = org and org.stamina
        if not stamina or stamina[1] == nil then continue end

        local mood = ClampMood(ply:GetNWInt("zcity_delta_mood", 0))
        if mood >= 0 then continue end

        local speed = ply:GetVelocity():Length2D()
        local sprinting = ply:KeyDown(IN_SPEED) and speed > 200
        if not sprinting then continue end

        local t = math.Clamp((-mood) / 100, 0, 1)
        local dt = 0.35
        local maxStam = tonumber(stamina.max) or 220
        local drainPerSec = (0.25 + 2.2 * (t ^ 1.35)) * (maxStam / 220)
        local drain = drainPerSec * dt

        stamina[1] = math.max(0, (tonumber(stamina[1]) or 0) - drain)
    end
end)

local function ApplyMentalEnabledState(enabled)
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:IsPlayer() then continue end
        if enabled then
            LoadMental(ply)
        else
            SaveMental(ply)
            SetMental(ply, math.random(10, 30), 10, true)
        end
    end
end

cvars.AddChangeCallback("zcity_delta_mental_enabled", function(_, _, newValue)
    local enabled = tonumber(newValue or "0") == 1
    ApplyMentalEnabledState(enabled)
end, "zcity_delta_mental_enabled_apply")

concommand.Add("zcity_delta_mental_toggle", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local v = zcity_delta_mental_enabled:GetInt()
    local nextV = (v == 1) and 0 or 1
    if args and args[1] ~= nil then
        nextV = tonumber(args[1]) == 1 and 1 or 0
    end
    zcity_delta_mental_enabled:SetBool(nextV == 1)
end)

concommand.Add("zcity_delta_depression_max", function(ply, _, args)
    if not IsMentalEnabled() then return end
    if IsValid(ply) and not ply:IsAdmin() then return end

    local target = ply
    if IsValid(ply) and tostring(args and args[1] or "") == "target" then
        target = ResolveEyeTarget(ply) or ply
    elseif args and args[1] ~= nil then
        local idx = tonumber(args[1])
        if idx then
            local ent = Entity(idx)
            if IsValid(ent) and ent:IsPlayer() then
                target = ent
            end
        end
    end

    if not IsValid(target) or not target:IsPlayer() then return end
    local _, stress = GetMental(target)
    SetMental(target, -100, stress, true)
    SaveMental(target)
end)

concommand.Add("zcity_delta_happiness_max", function(ply, _, args)
    if not IsMentalEnabled() then return end
    if IsValid(ply) and not ply:IsAdmin() then return end

    local target = ply
    if IsValid(ply) and tostring(args and args[1] or "") == "target" then
        target = ResolveEyeTarget(ply) or ply
    elseif args and args[1] ~= nil then
        local idx = tonumber(args[1])
        if idx then
            local ent = Entity(idx)
            if IsValid(ent) and ent:IsPlayer() then
                target = ent
            end
        end
    end

    if not IsValid(target) or not target:IsPlayer() then return end
    local _, stress = GetMental(target)
    SetMental(target, 100, stress, true)
    SaveMental(target)
end)

concommand.Add("zcity_delta_laststand", function(ply, _, args)
    if not IsMentalEnabled() then return end
    if IsValid(ply) and not ply:IsAdmin() then return end

    local target = ply
    if IsValid(ply) and tostring(args and args[1] or "") == "target" then
        target = ResolveEyeTarget(ply) or ply
    elseif args and args[1] ~= nil then
        local idx = tonumber(args[1])
        if idx then
            local ent = Entity(idx)
            if IsValid(ent) and ent:IsPlayer() then
                target = ent
            end
        end
    end

    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return end
    if not target.organism then return end

    target.__zcity_delta_laststand_rolled = nil
    hg.Mental.TryLastStand(target, target.organism)
end)

local function PatchOrganismForLastStand()
    if not hg or not hg.organism or not istable(hg.organism.module) then return false end

    local module = hg.organism.module

    if istable(module.lungs) and isfunction(module.lungs[2]) and not module.lungs.__zcity_delta_laststand_patched then
        local oldLungsThink = module.lungs[2]
        module.lungs[2] = function(owner, org, timeValue)
            if org and owner and owner:IsPlayer() then
                if org.alive and org.brain and org.brain >= 0.6 then
                    hg.Mental.TryLastStand(owner, org)
                end

                if (org.lastStandO2Until or 0) > CurTime() and org.o2 and org.o2.range then
                    org.o2[1] = org.o2.range
                    org.o2.curregen = org.o2.regen
                end
            end

            local ret = oldLungsThink(owner, org, timeValue)

            if org and owner and owner:IsPlayer() then
                if (not org.alive) and org.brain and org.brain >= 0.6 then
                    if hg.Mental.TryLastStand(owner, org) then
                        org.alive = true
                    end
                end

                if (org.lastStandO2Until or 0) > CurTime() and org.o2 and org.o2.range then
                    org.o2[1] = org.o2.range
                    org.o2.curregen = org.o2.regen
                end
            end

            return ret
        end

        module.lungs.__zcity_delta_laststand_patched = true
    end

    if istable(module.pain) and isfunction(module.pain[2]) and not module.pain.__zcity_delta_laststand_patched then
        local oldPainThink = module.pain[2]
        module.pain[2] = function(owner, org, timeValue)
            if org and (org.lastStandAdrenalineUntil or 0) > CurTime() then
                org.adrenalineAdd = 4
                org.adrenaline = math.max(tonumber(org.adrenaline) or 0, 4)
            end

            local ret = oldPainThink(owner, org, timeValue)

            if org then
                local now = CurTime()
                local lastTick = tonumber(org.__zcity_delta_pain_decay_tick or now) or now
                local dt = math.Clamp(now - lastTick, 0, 0.5)
                org.__zcity_delta_pain_decay_tick = now

                local recentHit = (tonumber(org.lasthit) or 0) > (now - 2.2)
                local hasPersistentSource = HasPersistentPainSource(org)

                if not recentHit then
                    if hasPersistentSource then
                        org.painadd = math.max((tonumber(org.painadd) or 0) - dt * 1.8, 0)
                        org.avgpain = math.max((tonumber(org.avgpain) or 0) - dt * 0.7, 0)
                    else
                        org.painadd = math.max((tonumber(org.painadd) or 0) - dt * 6.5, 0)
                        org.avgpain = math.max((tonumber(org.avgpain) or 0) - dt * 3.6, 0)
                        org.pain = math.max((tonumber(org.pain) or 0) - dt * 8.5, 0)
                    end
                end
            end

            if org and (org.lastStandAdrenalineUntil or 0) > CurTime() then
                org.adrenaline = math.max(tonumber(org.adrenaline) or 0, 4)
            end

            return ret
        end

        module.pain.__zcity_delta_laststand_patched = true
    end

    return true
end

timer.Create("zcity_delta_patch_organism_laststand", 1, 0, function()
    if PatchOrganismForLastStand() then
        timer.Remove("zcity_delta_patch_organism_laststand")
    end
end)

local function PatchConsumablesMood()
    if not weapons or not weapons.GetStored then return false end
    if not hg or not hg.Mental or not hg.Mental.IsEnabled or not hg.Mental.Get or not hg.Mental.Set then return false end

    local function PatchWeapon(className, moodGainPerUse)
        local swep = weapons.GetStored(className)
        if not istable(swep) then return false end
        if swep.__zcity_delta_mood_food_patched then return true end
        if not isfunction(swep.Heal) then return false end

        local oldHeal = swep.Heal
        swep.Heal = function(self, ent, ...)
            local ok = oldHeal(self, ent, ...)
            if ok and IsValid(ent) and ent:IsPlayer() and hg.Mental.IsEnabled() then
                local mood, stress = hg.Mental.Get(ent)
                local mult = GetTraitMultipliers(ent)
                local gain = (tonumber(moodGainPerUse) or 0) + (tonumber(mult.foodMoodAdd) or 0)
                hg.Mental.Set(ent, mood + gain, stress)
            end
            return ok
        end

        swep.__zcity_delta_mood_food_patched = true
        return true
    end

    local ok1 = PatchWeapon("weapon_bigconsumable", 2.5)
    local ok2 = PatchWeapon("weapon_smallconsumable", 1)
    return ok1 and ok2
end

timer.Create("zcity_delta_patch_consumables_mood", 1, 0, function()
    if PatchConsumablesMood() then
        timer.Remove("zcity_delta_patch_consumables_mood")
    end
end)
