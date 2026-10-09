if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_bandage_sh"
SWEP.PrintName = "Antidepressants"
SWEP.Instructions = "Используйте на себе или ПКМ на другом. Возможна передозировка."
SWEP.Category = "ZCity Medicine"
SWEP.Spawnable = true
SWEP.Primary.Wait = 1
SWEP.Primary.Next = 0
SWEP.HoldType = "slam"
SWEP.ViewModel = ""
SWEP.WorldModel = "models/bloocobalt/l4d/items/w_eq_pills.mdl"
SWEP.Model = nil

if CLIENT then
    SWEP.WepSelectIcon = Material("vgui/wep_jack_hmcd_painpills")
    SWEP.IconOverride = "vgui/wep_jack_hmcd_painpills.png"
    SWEP.BounceWeaponIcon = false
end

SWEP.Slot = 3
SWEP.SlotPos = 2
SWEP.WorkWithFake = true
SWEP.offsetVec = Vector(2.5, -2.5, 0)
SWEP.offsetAng = Angle(-30, 20, 180)

SWEP.modeNames = {
    [1] = "antidepressants"
}

function SWEP:InitializeAdd()
    self:SetHold(self.HoldType)
    self.modeValues = {
        [1] = 1
    }
end

local hg_healanims = ConVarExists("hg_healanims") and GetConVar("hg_healanims") or CreateConVar("hg_healanims", 0, FCVAR_REPLICATED + FCVAR_ARCHIVE, "Toggle heal/food animations", 0, 1)

function SWEP:Think()
    self:SetBodyGroups("111")
    if not self:GetOwner():KeyDown(IN_ATTACK) and hg_healanims:GetBool() then
        self:SetHolding(math.max(self:GetHolding() - 4, 0))
    end
end

local lang1, lang2 = Angle(0, -10, 0), Angle(0, 10, 0)
function SWEP:Animation()
    local owner = self:GetOwner()
    if (owner.zmanipstart ~= nil and not owner.organism.larmamputated) then return end

    local aimvec = owner:GetAimVector()
    if not aimvec then return end

    local hold = self:GetHolding()

    if owner:IsFlagSet(FL_DUCKING) or owner:GetVelocity():LengthSqr() >= 17000 then
        aimvec[3] = -2
        hold = hold / 2
    end

    local ducking = owner:IsFlagSet(FL_ANIMDUCKING)

    self:BoneSet("r_upperarm", vector_origin, Angle(30 + 10 * aimvec[3], (-50 - hold) + 10 * aimvec[3] * (ducking and -4 or -2) + hold / 2, 10 - hold / 3))
    self:BoneSet("r_forearm", vector_origin, Angle(-10, -hold, -hold))

    self:BoneSet("l_upperarm", vector_origin, lang1)
    self:BoneSet("l_forearm", vector_origin, lang2)
end

SWEP.modeValuesdef = {
    [1] = {1, true}
}

SWEP.DeploySnd = "snd_jack_hmcd_pillsbounce.wav"
SWEP.FallSnd = "snd_jack_hmcd_pillsbounce.wav"
SWEP.showstats = false

SWEP.ShouldDeleteOnFullUse = true

if SERVER then
    function SWEP:CanHeal(ent)
        if not IsValid(ent) or not ent:IsPlayer() or not ent.organism then return false end
        if (self.modeValues and self.modeValues[1] or 0) <= 0 then return false end
        return true
    end

    function SWEP:Heal(ent, mode)
        if hg and hg.GetCurrentCharacter then
            ent = hg.GetCurrentCharacter(ent) or ent
        end

        if not self:CanHeal(ent) then return false end

        local owner = self:GetOwner()
        if not IsValid(owner) then return false end

        local ok = hg and hg.Mental and hg.Mental.ApplyAntidepressantDose and hg.Mental.ApplyAntidepressantDose(owner, ent, 1)
        if not ok then return false end

        owner:EmitSound("snd_jack_hmcd_needleprick.wav", 60, math.random(95, 105))

        self.modeValues[1] = 0
        self:SetNetVar("modeValues", table.Copy(self.modeValues))

        if self.ShouldDeleteOnFullUse then
            owner:SelectWeapon("weapon_hands_sh")
            self:Remove()
        end

        return true
    end
end
