if SERVER then
	AddCSLuaFile()
	function SWEP:OnDrop()
		if self._carpetSpent then self:Remove() end
	end
end

SWEP.Base = "weapon_carpetbomber"
SWEP.PrintName = "Airstrike"
SWEP.Instructions = "ЛКМ - отметить область, затем прицельтесь и нажмите ЛКМ ещё раз, чтобы задать направление бомбёжки."
SWEP.Category = "ZCity Other"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.CarpetBombPairs = 3
SWEP.CarpetBombCount = 1
SWEP.CarpetWeapon = true
SWEP.RadioCallSound = "rem_callinairstrike.ogg"
SWEP.RadioCallSoundLevel = 80
SWEP.BomberModel = "models/xqm/jetbody3_s2.mdl"
SWEP.BomberAngleOffset = Angle(0, -90, 0)
SWEP.BomberSpeed = 3200
SWEP.BomberHeight = 2000
SWEP.BomberDistance = 10000
SWEP.CarpetBombInterval = 0.3
SWEP.SecondWaveAngleMin = 15
SWEP.SecondWaveAngleMax = 20
SWEP.SecondWaveDelay = 0
