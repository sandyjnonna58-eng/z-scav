if SERVER then AddCSLuaFile() end
SWEP.Base = "weapon_bandage_sh"
SWEP.PrintName = "Рифампицин"
SWEP.Instructions = "Антибиотик против проказы. Курс из 4 пузырьков (не чаще раза в минуту). Больше 2 пузырьков за раз - инфаркт. ЛКМ - выпить пузырёк, ПКМ - дать другому."
SWEP.Category = "ZCity Medicine"
SWEP.Spawnable = true
SWEP.Primary.Wait = 1
SWEP.Primary.Next = 0
SWEP.HoldType = "slam"
SWEP.ViewModel = ""
SWEP.WorldModel = "models/props_lab/jar01b.mdl"
SWEP.Color = Color(225, 80, 40)
SWEP.ModelScale = 0.5
if CLIENT then
	SWEP.WepSelectIcon = Material("vgui/wep_jack_hmcd_painpills")
	SWEP.IconOverride = "vgui/wep_jack_hmcd_painpills.png"
	SWEP.BounceWeaponIcon = false
end
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.Slot = 3
SWEP.SlotPos = 1
SWEP.WorkWithFake = true
SWEP.offsetVec = Vector(2.5, -2.5, 0)
SWEP.offsetAng = Angle(-30, 20, 180)
SWEP.modeNames = {
	[1] = "упаковка"
}
SWEP.VicodinPills = 1

function SWEP:InitializeAdd()
	self:SetHold(self.HoldType)

	self.modeValues = {
		[1] = self.VicodinPills
	}
end

SWEP.modeValuesdef = {
	[1] = 1,
}

SWEP.DeploySnd = "snd_jack_hmcd_pillsbounce.wav"
SWEP.FallSnd = "snd_jack_hmcd_pillsbounce.wav"

SWEP.showstats = false

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

function SWEP:OwnerChanged()
	local owner = self:GetOwner()
	if IsValid(owner) and owner:IsNPC() then
		self:SpawnGarbage(nil, nil, "snd_jack_hmcd_foodbounce.wav")
		self:NPCHeal(owner, 0.2, "snd_jack_hmcd_pillsuse.wav")
	end
end

if SERVER then
	function SWEP:Heal(ent, mode)
		if ent:IsNPC() then
			self:SpawnGarbage(nil, nil, "snd_jack_hmcd_foodbounce.wav")
			self:NPCHeal(ent, 0.2, "snd_jack_hmcd_pillsuse.wav")
		end

		local org = ent.organism
		if not org then return end
		if ent ~= self:GetOwner() and !IsValid(org.owner.FakeRagdoll) then return end
		if !org.analgesiaAdd or !self.modeValues or (self.modeValues[1] or 0) <= 0 then return end

		local owner = self:GetOwner()
		if ent == hg.GetCurrentCharacter(owner) and hg_healanims:GetBool() then
			self:SetHolding(math.min(self:GetHolding() + 4, 100))

			if self:GetHolding() < 100 then return end
		end

		-- одна таблетка за раз
		if (self.zscavNextPill or 0) > CurTime() then return end
		self.zscavNextPill = CurTime() + 2

		local entOwner = IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or owner
		entOwner:EmitSound(self.UseSound or "snd_jack_hmcd_pillsuse.wav", 60, math.random(95, 105))

		local target = org.owner
		if not (hg.organism.DiseaseMedicine and hg.organism.DiseaseMedicine(target, org, "rifampicin")) and IsValid(target) and target.Notify then
			target:Notify("Ничего не изменилось.", 3, "zscav_med", 0)
		end
		self.modeValues[1] = math.max((self.modeValues[1] or 1) - 1, 0)
		if self.modeValues[1] <= 0 then
			owner:SelectWeapon("weapon_hands_sh")
			self:SpawnGarbage(nil, nil, "snd_jack_hmcd_foodbounce.wav")
			self:Remove()
		end

		return true
	end
end