--[[
    Z-SCAV: антибиотики. +70% к иммунитету на 4 минуты (несколько приёмов продлевают до 10 минут).
    ЛКМ - принять таблетку. В пачке 3 таблетки.
]]

SWEP.PrintName    = "Антибиотики"
SWEP.Author       = "Z-SCAV"
SWEP.Category     = "Z-SCAV"
SWEP.Spawnable    = true
SWEP.Slot         = 4
SWEP.SlotPos      = 6
SWEP.DrawAmmo     = false
SWEP.DrawCrosshair = false
SWEP.ViewModel    = "models/weapons/c_arms.mdl"
SWEP.UseHands     = true
SWEP.WorldModel   = "models/props_lab/jar01b.mdl"
SWEP.HoldType     = "slam"

SWEP.Primary.ClipSize, SWEP.Primary.DefaultClip, SWEP.Primary.Automatic, SWEP.Primary.Ammo = -1, -1, false, "none"
SWEP.Secondary.ClipSize, SWEP.Secondary.DefaultClip, SWEP.Secondary.Automatic, SWEP.Secondary.Ammo = -1, -1, false, "none"

local DOSE_TIME, MAX_TIME, PILLS = 240, 600, 3

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    self.Pills = PILLS
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 1.5)
    if CLIENT then return end
    local ply = self:GetOwner()
    local org = IsValid(ply) and ply.organism
    if not org or not org.alive then return end
    local now = CurTime()
    org.remAntibioticsUntil = math.min(math.max(org.remAntibioticsUntil or 0, now) + DOSE_TIME, now + MAX_TIME)
    ply:EmitSound("snd_jack_hmcd_pillsuse.wav", 60, math.random(95, 105))
    ply:Notify("Антибиотики.. организм сопротивляется.", 4, "zscav_antibiotics", 0)
    self.Pills = (self.Pills or PILLS) - 1
    if self.Pills <= 0 then
        ply:SelectWeapon("weapon_hands_sh")
        self:Remove()
    end
end

function SWEP:SecondaryAttack() end

if CLIENT then
    function SWEP:DrawHUD()
        draw.SimpleTextOutlined("ЛКМ - принять антибиотик", "DermaDefault", ScrW() * 0.5, ScrH() * 0.8, Color(220, 230, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    end
end
