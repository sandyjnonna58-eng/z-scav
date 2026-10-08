if SERVER then AddCSLuaFile() end
SWEP.Base = "weapon_bandage_sh"
SWEP.PrintName = "Bruice kit"
SWEP.Instructions = "A medical kit designed to restore limb condition. RMB to use on someone else."
SWEP.Category = "ZCity Medicine"
SWEP.Spawnable = true
SWEP.Primary.Wait = 1
SWEP.Primary.Next = 0

local hg_healanims = ConVarExists("hg_healanims") and GetConVar("hg_healanims") or CreateConVar("hg_healanims", 0, FCVAR_REPLICATED + FCVAR_ARCHIVE, "Toggle heal/food animations", 0, 1)

if CLIENT then
	SWEP.WepSelectIcon = Material("vgui/wep_jack_hmcd_medkit")
	SWEP.IconOverride = "vgui/wep_jack_hmcd_medkit.png"
	SWEP.BounceWeaponIcon = false
end

SWEP.Slot = 3
SWEP.SlotPos = 1

SWEP.mode = 1
SWEP.modes = 1
SWEP.modeNames = {
	[1] = "bruise kit",
}

function SWEP:InitializeAdd()
	self:SetHold(self.HoldType)
	self.ModelScale = 1

	self.modeValues = {
		[1] = 60,
	}
end

SWEP.modeValuesdef = {
	[1] = {60, true},
}

SWEP.ShouldDeleteOnFullUse = true

if SERVER then
	local conditionPriority = {
		"spine3",
		"spine2",
		"spine1",
		"pelvis",
		"lleg",
		"rleg",
		"larm",
		"rarm",
		"chest",
		"skull",
	}

	local function CanHealKey(org, key)
		local v = tonumber(org[key] or 0) or 0
		if key == "larm" and org.larmamputated then return false end
		if key == "rarm" and org.rarmamputated then return false end
		if key == "lleg" and org.llegamputated then return false end
		if key == "rleg" and org.rlegamputated then return false end
		return v > 0.05
	end

	local function FindMostDamagedKey(org)
		local bestKey = nil
		local bestVal = 0

		for _, key in ipairs(conditionPriority) do
			if CanHealKey(org, key) then
				local v = tonumber(org[key] or 0) or 0
				if v > bestVal then
					bestVal = v
					bestKey = key
				end
			end
		end

		return bestKey, bestVal
	end

	function SWEP:CanHeal(ent)
		local org = ent and ent.organism
		if not org then return false end
		if (self.modeValues and self.modeValues[1] or 0) <= 0 then return false end

		return FindMostDamagedKey(org) ~= nil
	end

	function SWEP:Heal(ent, mode, bone)
		if ent:IsNPC() then
			self:NPCHeal(ent, 0.25, "snd_jack_hmcd_bandage.wav")
		end

		local org = ent.organism
		if not org then return end

		local owner = self:GetOwner()
		if ent == hg.GetCurrentCharacter(owner) and hg_healanims:GetBool() then
			self:SetHolding(math.min(self:GetHolding() + 10, 100))
			if self:GetHolding() < 100 then return end
		end

		if not self:CanHeal(ent) then return false end

		local key = FindMostDamagedKey(org)
		if not key then return false end

		local heal = math.min(tonumber(self.modeValues[1] or 0) or 0, 15)
		if heal <= 0 then return false end

		local v = tonumber(org[key] or 0) or 0
		org[key] = math.max(v - (heal / 40), 0)
		self.modeValues[1] = math.max((tonumber(self.modeValues[1]) or 0) - heal, 0)

		owner:EmitSound("snd_jack_hmcd_bandage.wav", 60, math.random(95, 105))

		if (self.modeValues[1] <= 0) and self.ShouldDeleteOnFullUse then
			owner:SelectWeapon("weapon_hands_sh")
			self:Remove()
		end

		return true
	end
end
