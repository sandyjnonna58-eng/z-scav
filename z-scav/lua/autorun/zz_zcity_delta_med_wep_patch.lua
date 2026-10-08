if CLIENT then return end

-- Z-SCAV: мини-игры аддона для бинтов, жгута и набора от ушибов.
-- Шприцы (морфин/фентанил и др.) используют мини-игры Z-SCAV (lua/homigrad/remhealth/).
local MEDICAL_WEAPON_CLASSES = {
    "weapon_bandage_sh",
    "weapon_bigbandage_sh",
    "weapon_bruicekit",
    "weapon_tourniquet",
}

-- Z-SCAV: патч бинта-основы наследуют ВСЕ лекарства (морфин, аптечка и т.д.),
-- поэтому мини-игра аддона включается строго только для классов из списка выше
local ALLOWED = {}
for _, c in ipairs(MEDICAL_WEAPON_CLASSES) do ALLOWED[c] = true end

local function GetMinigameType(wep)
    if not IsValid(wep) then return nil end
    local class = wep:GetClass()
    if not ALLOWED[class] then return nil end

    if class == "weapon_bandage_sh" or class == "weapon_bigbandage_sh" or class == "weapon_bruicekit" then
        return "bandage"
    end

    if class == "weapon_tourniquet" then
        return "tourniquet"
    end

    if class == "weapon_morphine" or class == "weapon_fentanyl" then
        return "syringe"
    end

    if class == "weapon_medkit_sh" then
        if wep.mode == 1 then return "bandage" end
        if wep.mode == 3 then return "syringe" end
        if wep.mode == 4 then return "tourniquet" end
    end

    return nil
end

local function GetModeValueIndex(wep, minigameType)
    if not IsValid(wep) then return 1 end
    if wep:GetClass() ~= "weapon_medkit_sh" then return 1 end

    if minigameType == "syringe" then return 3 end
    if minigameType == "tourniquet" then return 4 end
    return 1
end

local function ResolveSecondaryTarget(owner)
    if not IsValid(owner) then return nil end
    local tr = owner:GetEyeTrace()
    local ent = tr and tr.Entity or nil
    if not IsValid(ent) then return nil end

    if ent:IsRagdoll() and hg and hg.RagdollOwner then
        ent = hg.RagdollOwner(ent) or ent
    end

    if not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() or not ent.organism then return nil end
    if ent ~= owner and owner:GetPos():DistToSqr(ent:GetPos()) > 10000 then return nil end
    return ent
end

local function StartMinigame(wep, owner, minigameType, target)
    if not IsValid(wep) or not IsValid(owner) then return false end
    if not minigameType then return false end

    local modeValueIndex = GetModeValueIndex(wep, minigameType)
    local startValue = wep.modeValues and wep.modeValues[modeValueIndex] or nil

    wep.healbuddy = target or owner
    wep.HGMedicalMinigameStartValue = startValue

    net.Start("hg_medical_minigame_start")
        net.WriteString(minigameType)
    net.Send(owner)

    return true
end

local function PatchWeapon(class)
    local stored = weapons.GetStored(class)
    if not istable(stored) then return false end
    if stored.__hg_med_minigame_patched then return true end

    stored.__hg_med_minigame_patched = true
    stored.__hg_med_minigame_primary = stored.PrimaryAttack
    stored.__hg_med_minigame_secondary = stored.SecondaryAttack

    function stored:PrimaryAttack()
        local owner = self:GetOwner()
        -- Z-SCAV: апатия
        if hg.ZSCAVApathyRefuse and hg.ZSCAVApathyRefuse(owner, self) then return end
        -- Z-SCAV: на себя - только через меню здоровья
        if hg.RemMedGate and hg.RemMedGate(self) then return end
        local minigameType = GetMinigameType(self)
        if IsValid(owner) and minigameType then
            StartMinigame(self, owner, minigameType, owner)
            self:SetNextPrimaryFire(CurTime() + 1)
            return
        end

        if self.__hg_med_minigame_primary then
            return self:__hg_med_minigame_primary()
        end
    end

    function stored:SecondaryAttack()
        local owner = self:GetOwner()
        local minigameType = GetMinigameType(self)
        if IsValid(owner) and minigameType then
            local target = ResolveSecondaryTarget(owner)
            if IsValid(target) then
                StartMinigame(self, owner, minigameType, target)
                self:SetNextSecondaryFire(CurTime() + 1)
                return
            end
        end

        if self.__hg_med_minigame_secondary then
            return self:__hg_med_minigame_secondary()
        end
    end

    return true
end

local function ApplyPatches()
    for _, class in ipairs(MEDICAL_WEAPON_CLASSES) do
        PatchWeapon(class)
    end
end

local function SchedulePatchRetries()
    timer.Simple(0, ApplyPatches)
    timer.Simple(1, ApplyPatches)
    timer.Simple(5, ApplyPatches)
end

hook.Add("Initialize", "zcity_delta_patch_med_weps", SchedulePatchRetries)
hook.Add("InitPostEntity", "zcity_delta_patch_med_weps_post", SchedulePatchRetries)
hook.Add("OnReloaded", "zcity_delta_patch_med_weps_reload", SchedulePatchRetries)

timer.Simple(0, SchedulePatchRetries)
