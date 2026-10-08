if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_bandage_sh"
SWEP.PrintName = "Auto-Resuscitator"
SWEP.Instructions = "Arms an emergency autoresuscitation dose. Use it on yourself or RMB on someone else. It triggers once after cardiac arrest."
SWEP.Category = "ZCity Medicine"
SWEP.Spawnable = false
SWEP.Primary.Wait = 1
SWEP.Primary.Next = 0
SWEP.HoldType = "normal"
SWEP.ViewModel = ""
SWEP.WorldModel = "models/alyx_emptool_prop.mdl"
SWEP.Model = nil

if CLIENT then
	SWEP.WepSelectIcon = Material("../addons/implant.png", "smooth")
	SWEP.IconOverride = "../addons/implant.png"
	SWEP.BounceWeaponIcon = false
end

SWEP.ScrappersSlot = nil
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.Slot = 5
SWEP.SlotPos = 2
SWEP.WorkWithFake = true
SWEP.offsetVec = Vector(5, -1.5, -2.5)
SWEP.offsetAng = Angle(90, 0, -90)
SWEP.modeNames = {
	[1] = "autoresuscitator"
}

function SWEP:InitializeAdd()
	self:SetHold(self.HoldType)
	self.modeValues = {
		[1] = 1
	}
end

SWEP.modeValuesdef = {
	[1] = 1
}

SWEP.DeploySnd = ""
SWEP.HolsterSnd = ""
SWEP.showstats = false

local hg_healanims = ConVarExists("hg_healanims") and GetConVar("hg_healanims") or CreateConVar("hg_healanims", 0, FCVAR_REPLICATED + FCVAR_ARCHIVE, "Toggle heal/food animations", 0, 1)

function SWEP:Think()
	if not self:GetOwner():KeyDown(IN_ATTACK) and hg_healanims:GetBool() then
		self:SetHolding(math.max(self:GetHolding() - 4, 0))
	end
end

function SWEP:Animation()
	local hold = self:GetHolding()
	self:BoneSet("r_upperarm", vector_origin, Angle(0, -hold + (100 * (hold / 100)), 0))
	self:BoneSet("r_forearm", vector_origin, Angle(-hold / 6, -hold * 2, -15))
end

if SERVER then
	function SWEP:Heal(ent, mode)
		if hg and hg.GetCurrentCharacter then
			ent = hg.GetCurrentCharacter(ent) or ent
		end

		local org = IsValid(ent) and ent.organism or nil
		if not org then return end

		local owner = self:GetOwner()
		if org.headamputated then
			if IsValid(owner) and owner.Notify then
				owner:Notify("Can't be used without a head.", 6, "autoresuscitator_nohead", 0.5)
			end
			return
		end

		local ownerChar = (hg and hg.GetCurrentCharacter) and (hg.GetCurrentCharacter(owner) or owner) or owner
		if ent == ownerChar and hg_healanims:GetBool() then
			self:SetHolding(math.min(self:GetHolding() + 4, 100))
			if self:GetHolding() < 100 then return end
		end

		local entOwner = IsValid(org.owner and org.owner.FakeRagdoll) and org.owner.FakeRagdoll or org.owner
		if IsValid(entOwner) then
			entOwner:EmitSound("snd_jack_hmcd_needleprick.wav", 60, math.random(95, 105))
		end

		org.autoResuscitator = 1
		org.autoResuscitatorArmed = true
		org.autoResuscitatorTry = 0

		self.modeValues[1] = 0
		if self.modeValues[1] == 0 then
			owner:SelectWeapon("weapon_hands_sh")
			self:Remove()
		end
	end
end
